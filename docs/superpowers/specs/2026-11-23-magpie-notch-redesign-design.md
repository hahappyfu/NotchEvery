# NotchEvery × Magpie 数据与刘海重构设计

- **日期**：2026-11-23
- **状态**：已过 Builder Check，待用户终审批准
- **目标仓库**：`/Users/fupingguo/fuhaha_workspace/NotchEvery`
- **分工约定**：本设计文档经用户批准并拆分为实施计划后，由 Claude Code 实施编码与测试。

---

## 1. 意图与背景（Intent & Why）

NotchEvery 此前曾将部分刘海逻辑合入 `fuckharness/apps/fluxbar-mac`（`FluxNotch`），现用户停用 `fuckharness`，回归独立的 `NotchEvery` macOS 刘海驻留应用。同时，本地代理与多池聚合路由已切换为 **`magpie.app`**（`~/.config/magpie/`），不再使用 `~/.cc-switch/cc-switch.db` 与 `~/.antigravity_tools`。

本次重构从 **数据层** 与 **刘海 UI / 交互层** 同步重新设计：
1. **数据层彻底迁移至 Magpie**：发挥 Magpie 独有的 `Group → 提供商 + 模型` 聚合路由、多账户多窗口积分额度、429/405 限流风控告警、隐私脱敏统计与逐请求 TTFT 指标；同时保证**零硬编码可扩展性**——用户在 Magpie 后台新增供应商或路由组后，NotchEvery 自动识别展示，无需改代码重编译。
2. **吸收 `FluxNotch` 的优质交互并保持克制**：引入其按页条件渲染的耳区、流水定格暂停（`isPaused`/`missedCount`/`gapCount`）、点击行复制、三态空态归因、纯 SwiftUI 新行入场绿闪、紧凑排版度量与零三方依赖瘦身；**明确排除** `BallPit`（额度球盆，用户确认不需要）与重型主控台窗口（账号/路由管理留在 `magpie.app`）。

---

## 2. 目标、非目标与反目标

### Goals
1. **3 页黑岛新结构**（保留恒黑连续圆角黑岛、物理挖槽中央禁放区、悬停 Peek、底部 `SmoothPageIndicator`、横扫/方向键切页与 `ADR-0008` 内容自适应尺寸）：
   - **第 1 页（默认首页 · 今日用量分布）**：保留分段彩条 + Top 5 列表，新增右上角维度切换 **`模型·提供商`（默认）| `提供商` | `Group`**，底部展示缓存命中总量与今日隐私脱敏总量；耳区展示活跃项数、最近请求时间与可点击告警角标。
   - **第 2 页（实时请求流水）**：最近 5 笔真实请求（过滤内部探活），展示 `模型` + `提供商 · Group · Agent`、`总 Token + 缓存命中条 + 🛡脱敏数`、`总耗时 + TTFT + 状态点 + 时间`；引入 `FluxNotch` 的暂停定格（含 `missedCount`/`gapCount`）、点击行复制与纯 SwiftUI 绿闪。
   - **第 3 页（供应商额度与限流状态）**：按供应商聚合展示（**排版 1：每家 1 行汇总，点击展开单账号/多窗口明细**），叠加 `limit-notices.json` 的 429/405 冷却倒计时与 `plugin-checkin.json` 今日签到摘要；支持 Magpie 后台新增供应商零改码自动接入。
2. **纯本地文件自描述数据引擎 `MagpieStore`**：增量读取 `~/.config/magpie/` 非敏感文件，面板收起时不空转烧 CPU。
3. **移除历史遗留依赖**：清理 `UsageStore`（CC Switch SQLite）、`AntigravityStore`、文件拖拽与分享残余（`Share`、`Share+View`、`NotchMenuView` 中间弹窗、`dragDetector`），移除 SPM 依赖 `Pow`、`LaunchAtLogin-Modern`、`LookInside-Release`、`swift-collections` 及 `libsqlite3`，开机自启改用原生 `SMAppService.mainApp`。

### Non-Goals
- **不做额度球盆（`BallPit`）**：悬停虚影保持轻量双栏信息胶囊，不做物理球盆。
- **不做账号编辑/路由修改/手动签到/写请求**：NotchEvery 只作只读观测与快速直达展示，不替代 `magpie.app` 的管理界面。
- **不调用 Magpie 私有 HTTP 接口**：不请求 `127.0.0.1:3425`，避免耦合私有管理 API 与 `lanKey` 鉴权。

### Anti-Goals（绝不可接受）
- **绝不硬编码供应商白名单/枚举**（禁止 `enum ProviderID { case codearts, ... }`）；必须基于字符串 ID 与 Magpie 自描述文件动态生成。
- **绝不读取任何密钥或凭据文件**：严禁读取 `logins.json`、`plugin-auth.json`、`caller-keys.json`、`redact.key`、`settings.json` 中的 `lanKey`。
- **绝不造假 0**：数据源未就绪、无文件或某供应商无额度刻度时必须显示 `—` 或「无刻度」，绝不渲染成 `0%` 或 `0`。
- **绝不破坏面板关闭态零空转纪律**：面板 `.closed` 且非虚影悬停时，停止高频解析与定时器。

---

## 3. 备选方案与技术选型

| 方案 | 核心做法 | 优点 | 缺点与取舍 |
| :--- | :--- | :--- | :--- |
| **方案 1：纯本地文件直读 + FSEvents 增量监听（已选定）** | 新建 `MagpieStore`，用 `FSEvents` + `size/mtime` 增量 tail `~/.config/magpie/*.jsonl` 与小 JSON 快照 | 零网络/鉴权依赖、绝不碰密钥、Magpie 滚动升级零影响、可完全注入临时目录做离线单测 | 额度刷新节奏跟随 Magpie 后台落盘频率；需实现按天轮转 JSONL 的安全 tail |
| **方案 2：轮询 Magpie 本地网关 `127.0.0.1:3425`** | 请求本地网关管理接口拿实时数据 | 省去本地 JSONL 聚合代码 | 管理路由属 Magpie 内部私有契约且受 `lanKey` 保护，随客户端高频发版易断 |

**选型结论**：执行 **方案 1**。

---

## 4. 关键约束

1. **部署目标**：`MACOSX_DEPLOYMENT_TARGET = 13.0`（不可使用 macOS 14+ 独有 API，如 `@Observable`、`containerRelativeFrame` 等；状态发布继续使用 `@MainActor` + `ObservableObject`/`@Published`）。
2. **尺寸与安全区纪律**：延续 `NotchDrop` / `FluxNotch` 既有护栏——内容宽度由 `IslandMetrics` 控制（建议统一 `pageWidth = 420pt`，受 `ZoneSizeGuard` 上限 `640pt` 约束），面板高上限 `screenRect.height * 0.4`（未知屏回落 `360pt`）；第 3 页列表内部用受限高度 `ScrollView`，绝不撑爆面板高度。
3. **只读隔离与去敏**：只读 `~/.config/magpie/` 下明确白名单文件；账户名（`who` / `user`）直接使用 Magpie 自身已脱敏的展示值（如 `151****4090`），不额外拼装或推断敏感信息。
4. **单测可测性**：`MagpieStore` 及其纯聚合逻辑必须接受可注入的 `magpieConfigDir: URL` 与当前时间 `now: Date`，单元测试全部使用临时 fixture 目录，不依赖本机真实 `~/.config/magpie/`。

---

## 5. 数据层架构与实测契约（`MagpieStore`）

### 5.1 读取文件白名单与实测 Schema

默认根路径：`~/.config/magpie/`（通过 `AppPaths` 可配置/可注入）。以下字段均已针对 Magpie 实盘文件核实：

#### 1) `usage.jsonl`（跨天持久追加 JSONL）
每行代表一次上游尝试或探活。典型真实记录：
```json
{
  "route_id": 1795409334679,
  "t": "2026-11-23T15:14:06.480483+08:00",
  "agent": "claude",
  "provider": "codearts",
  "providerAccount": "iam::01a1fc0081877016bb44a0ab38227d99:user:hw079460577245900",
  "model": "deepseek-v4.1-flash",
  "req": "group/deepseekflash",
  "served": "deepseek-v4.1-flash",
  "in": 1082,
  "out": 172,
  "cache_read": 93440,
  "cache_write": 0,
  "reasoning": 116,
  "ms": 3598,
  "ttft_ms": 2665,
  "masking_ms": 150,
  "status": 200,
  "rid": "445db8aa925d0f07c2d53acdec32a51d",
  "handed_on": true,
  "kind": "provider_test",
  "source": "probe"
}
```
- **探活过滤规则**：Magpie 内部探活行带有 `"kind": "provider_test"` / `"source": "probe"`（且无 `route_id`/`rid`，多为 `403`）。**读取时必须丢弃 `kind == "provider_test" || source == "probe"` 的行**，避免污染流水与错误计数。
- **唯一标识与重试语义**：同一 `route_id` 发生组内故障转移时，前面失败尝试会标记 `handed_on: true`，最终接管尝试会产生新行且带有唯一 `rid`。行稳定标识取 `rid ?? "\(route_id ?? 0)-\(byteOffset)"`。
- **时间戳与非严格单调**：`t` 为 RFC3339 / ISO-8601 变长微秒字符串（例如 `.841213+08:00` 与 `.35674+08:00`），需用支持变长小数的日期解析器；并发请求完成顺序可能略微乱序，冷启动从文件尾部逆扫时不能遇到一条跨天记录就盲停，应加少量缓冲或扫描到连续越过当日零点（或尾部固定窗口如最近 4MB/当日区间）。`status` 建议解码为 `Int?`（缺省归为异常状态）。

#### 2) `routing/YYYY-MM-DD.jsonl`（按本地日期轮转）
- 关键字段：
  - `id`（`Int64`，对应 `usage.jsonl` 的 `route_id`）
  - `group`: `{ "id": String, "ref": String, "name": String }?`（非路由组直连请求时为 `null` 或缺省）
  - `order`: `[{ "id": String, "provider": String, "name": String?, "icon": String?, "who": String?, "plan": String?, "used": Double?, "amount": Double?, "limit": Double?, "unit": String?, "usedWindow": String?, "due": String?, "known": Bool? }]?`
- **内存边界**：单日 `routing` 文件可达数 MB，解析后只在内存保留「最近 200 条 `id → group` 映射」和「每个 `order[].id` 最新一条额度快照（用于补充 `quotas.json` 未覆盖的 `sensenova-token-plan` / `workbuddy` 等渠道）」。

#### 3) `masking/YYYY-MM-DD.jsonl`（按本地日期轮转）
- 关键字段：`route: Int64`（对应 `route_id`）、`n: Int`（本笔脱敏替换项数）、`t: String`。
- 按 `route` 聚合（同 `route` 多行累加 `n`），统计今日总脱敏项数 `sum(n)` 与命中脱敏的请求次数（`n > 0` 的唯一 `route` 数 / 行数）。

#### 4) `quotas.json`（JSON Dict）
- 顶层字典键为 `"<provider>/<account>"`（解析 `account` 时直接剥除 `"<quota.provider>/"` 前缀，避免账户名含 `/` 时误切）。
- 值结构：
  ```json
  {
    "at": "2026-11-23T16:08:31.500874+08:00",
    "quota": {
      "provider": "codearts",
      "name": "CodeArts",
      "icon": "file:33fdbde9f5f8ea57.svg",
      "plan": "体验版",
      "user": "151****4090",
      "windows": [
        { "name": "总积分", "used": 1.88, "amount": 86.76, "limit": 4600, "unit": "credits", "display": "87 / 4600 · 13 即将过期", "resetsAt": "...", "runsOutAt": "..." }
      ]
    },
    "spans": [{}, {"aside": true}, {"aside": true}]
  }
  ```
- **注意 `aside` 位置**：`aside: Bool?` 位于与 `windows[]` 等长的平行数组 `spans[]` 中（`spans[i].aside == true` 表示附属子窗口，如基础包/赠送包）。

#### 5) `limit-notices.json`（JSON Dict）
- 顶层键 `"<provider>@<account>"`（按首个 `@` 拆分 `provider` 与 `accountKey`）。
- 值结构：`{ "key": String, "why": String, "status": Int?, "error": String?, "at": String, "until": String? }`。
- 有效判定：`until == nil` 或 `until > now` 视为当前活跃告警；映射规则：有明确 `until > now` 归为 `.cooling(until)`，否则 `status == 403 || status == 405` 归为 `.riskBlocked`，其余 `status == 429 || why == "rate"` 归为 `.rateLimited`。

#### 6) `plugin-checkin.json`（JSON Dict）
- 顶层键 `"<provider>|<slot>"`（按首个 `|` 拆分 `provider`）。
- 值结构：`{ "day": "YYYY-MM-DD", "at": String, "outcome": String, "credit": Double?, "msg": String? }`。
- 实测 `outcome` 值包含：`"claimed"`、`"done"`（WorkBuddy 使用 `"done"`，二者均计入今日已领！）、`"ineligible"`、`"inactive"`、`"failed"`。只汇总 `day == 今日本地日期` 的记录；若某账号存在「可领未领」（如 `quotas.json` 窗口名含 `今日未签`），则在详情/摘要中保留提示。

#### 7) `providers.json`、`plugin-providers.json`、`plugin-icons.json`、`gateway.json`
- `providers.json`：根对象 `{ "providers": [{ "id", "name", "icon"?, "disabled"?, "hidden"? }], "groups": [{ "id", "name", "members": [String]?, "hidden"? }] }`。
- `plugin-providers.json`：数组 `[{ "id", "name", "icon"?, "signedIn": Bool? }]`（只读元数据字段，不解码账号凭据）。展示名称优先级：`providers.json.name`（非空） → `plugin-providers.json.name` → `quotas/routing` 自带 `name` → `id`。
- `plugin-icons.json`：字典 `[providerOrKey: "file:<filename>" | ...]`，其中 `file:` 后的文件名已含扩展名（如 `33fdbde9f5f8ea57.svg`）。
- `gateway.json`：`{ "addr": String, "pid": Int32, "version": String, "started": String }`，用 `kill(pid, 0) == 0`（`errno != ESRCH`）判断网关进程是否存活。

> **安全边界**：白名单之外的 `logins.json`、`plugin-auth.json`、`caller-keys.json`、`redact.key`、`settings.json`、`sessions.json` 等文件**严禁读取**；`~/Library/Logs/magpie/app.log` 不作读取（因同类限流/405 信息已由 `limit-notices.json` 与 `usage.jsonl` 结构化覆盖）。

---

### 5.2 增量读取与防空转生命周期

1. **目录监听 + 去抖**：
   - 使用 `FSEvents` / `DispatchSource` 监听 `~/.config/magpie`、`~/.config/magpie/routing`、`~/.config/magpie/masking`。
   - 变更事件做 `0.4s` 去抖合并；读取 jsonl 前比对 `inode` 与 `size`，若文件轮转/重写（`inode` 变或 `size < offset`）自动将 `offset` 归零重读。
2. **随面板开合分级调度**：
   - **`.closed`（非虚影）**：暂停定时刷新与增量解析，保持近零 CPU。
   - **`.closed` + 悬停虚影（`hoverGhosting`）**：立即同步追平一次增量数据，并在悬停期间允许 `1.5s` 去抖刷新。
   - **`.opened`**：第 1/3 页使用 `1.5s` 去抖刷新；第 2 页未暂停时实时增量推送（用户点「暂停定格」时冻结展示列表，新行暂存入最多 `200` 条的待读队列并累计 `missedCount`；超出 `200` 条上限则递增 `gapCount` 丢弃最旧待读，点击恢复后切回最新 5 条并将 `gapCount` 保留展示至下次刷新或清空）。
3. **跨天切换**：每次刷新校验本地日期字符串 `YYYY-MM-DD`，跨午夜自动切向当日 `routing/YYYY-MM-DD.jsonl` 与 `masking/YYYY-MM-DD.jsonl`，并重置当日统计。

---

### 5.3 核心口径与零硬编码模型

1. **当日口径（Usage & P1/P2）**：
   - `usage.jsonl` 只统计 **本地今日（00:00 起）且非探活** 的记录；跨午夜归零（保留 `lastRequestAt` 为今日最新请求时间，今日 0 请求时为 `nil`）。
   - **Net Tokens**：`netTokens = in + out`；**Cache Rate**：`cache_read / (in + cache_read)`（分母为 0 返回 `nil`）。
   - **分布统计入账**：包含所有今日 `status == 200 || (in + out + cache_read > 0)` 的非探活行。
   - **流水（P2）错误口径**：`499`（客户端取消）在流水行标为弱灰「已取消」，不计入上游异常 `E 错`；`handed_on == true` 在流水行标为「已切备用」；P2 Live Bar 的 `E 错` 统计 **今日非探活且 `status >= 400 && status != 499 && handed_on != true` 的未恢复上游错误数**，`均耗时` 取今日已完成非探活请求的 `ms` 平均值。
   - **`⚠ N` 角标统一口径**：全刘海（Peek、P1/P2/P3 右耳）的黄色 `⚠ N` 统一显示 **`limit-notices.json` 当前未过期活跃限流/风控条数**（点击即跳 P3 查看哪家被限流）。
2. **第 1 页三维聚合（`DistributionDimension`）**：
   - `.combo`（默认：**模型 · 提供商**）：键 `(provider, served ?? model)`。
   - `.provider`（**按提供商**）：键 `provider`，副标示 `N 账号 · M 模型`。
   - `.group`（**按 Group**）：将 `req` 与 `providers.json` 的 `groups[]` 映射（优先取 `groups[].name`，如 `group/deepseekflash` → `DeepSeekFlash(主用)`；若同时在 `routing` 索引命中 `group.name` 可补全；非组直连模型统一归为 `直连调用` 或保留模型标识）。
3. **第 3 页供应商额度自描述聚合（`ProviderQuotaGroup`）**：
   - **合并来源**：`providers.json`（未 `hidden`/`disabled`） + `plugin-providers.json`（`signedIn == true`） + `quotas.json` + `routing/YYYY-MM-DD.jsonl` 最新 `order[]`。遇到未见过的 `provider` ID 直接用记录自带 `name`/`icon` 动态建组。
   - **单账号主窗口选择**：按 `spans[i].aside != true` 过滤附属窗口后取第一个窗口（全为 `aside` 时回退 `windows.first`）。
   - **数值计算**：在 `quotas.json` 与 `order[]` 中，`used` 是**已用百分比（0~100）**，`limit` 为总额度，`amount` 为已用数量；**剩余量** `remaining = max(0, limit - (amount ?? limit * used / 100))`（单账号若 `limit == nil`，仅保留 `remainingFraction = max(0, 1 - used / 100)`；若连 `used` 均无则标 `isUngraded`）。
   - **多账号汇总**：
     - 对该供应商下有 `limit > 0` 的账号求和：`totalRemaining = sum(remaining)`、`totalLimit = sum(limit)`、`fraction = totalRemaining / totalLimit`；同时统计 `availableAccounts`（`remaining > 0`）与 `exhaustedAccounts`（`remaining <= 0`）。
     - 若有活跃 `limit-notices` 告警，不抹除其剩余额度数字（依然诚实显示余量），但同步挂上 `.cooling(until)` / `.rateLimited` / `.riskBlocked` 徽标与状态色。
     - 排序权重：`有可用额度且有今日活动或正常 > 有可用额度但带限流告警 > 已耗尽 > 无刻度`，同档按供应商名称稳定排序。
4. **动态图标加载器（`MagpieIconResolver`）**：
   - 解析 `icon` 字符串：若非 `file:` 开头，先查 `plugin-icons.json[icon]` 尝试转为 `file:<name>`。
   - 若得 `file:<name>`：先查 `~/.cache/magpie/icons-small/<name>.png`，再查 `~/.config/magpie/icons/<name>`；PNG/WebP/JPG 用 `NSImage(contentsOf:)` 内存缓存加载；`.svg` 通过 `QuickLookThumbnailing`（`QLThumbnailGenerator`）异步生成 32×32 缩略图并缓存。
   - 兜底：文件不存在或渲染失败时，基于 `provider` ID 哈希生成稳定的深色渐变圆徽 + 首字母。

---

## 6. UI 与交互详细设计

延续 `CONTEXT.md` 与 `ADR-0008 / 0009 / 0010` 确立的「恒黑连续曲率黑岛 + 内容自适应尺寸 + 物理挖槽中央禁放区 + 等高耳区 + 底部胶囊 Dots」。

### 6.1 布局常量与分区定义

- `IslandMetrics.panelContentInset`: `32pt → 18pt`；统一内容页宽 `pageWidth = 420pt`（受 `ZoneSizeGuard` `maxPanelWidth = 640pt` 约束，面板高上限 `screenRect.height * 0.4`）。
- `NotchViewModel.ContentType` 扩为 3 页：`[.overview, .token, .providers]`（对应 P1 今日分布、P2 实时流水、P3 供应商额度）。

### 6.2 悬停虚影（Peek）

- 移除 `BallPit` 相关构想，保持轻巧双栏信息胶囊：
  - **左区**：状态点（全正常翠绿；有活跃 `limit-notices` 改琥珀/玫红）+ `[最近或主力提供商 · 模型短名]`（如 `CodeArts · ds-v4.1-flash`）。
  - **右区**：今日总净 Token（如 `12.4M`）+ `· XX.X%`（青色缓存命中率）+ 若活跃 `limit-notices > 0` 展示轻量 `⚠ N`。
  - **空态**：无 `~/.config/magpie` 时展示「等待 Magpie 数据」；有目录但今日 0 请求时展示「Magpie 就绪 · 今日 0 请求」。

### 6.3 耳区（Notch Ears）

中央禁放区 `width = deviceNotchRect.width + 16pt`、`height = notchSafeAreaTop`，左右耳按当前页条件渲染且等高占位：

| 分页 | 左耳 | 右耳 |
| :--- | :--- | :--- |
| **P1 今日分布** | 绿点 + `N 个活跃组合`（随维度切为 `N 家提供商` / `N 个路由组`） | `🕒 HH:mm`（今日最新请求，无则隐藏）+ 若活跃告警 `> 0` 显可点击 `⚠ N`（直跳 P3） |
| **P2 实时流水** | 最新一笔命中的 `提供商图标 + 名称` | `⇅ N 次`（`RollupText` 今日总请求）+ 可点击 `⚠ N`（直跳 P3） |
| **P3 供应商额度** | 若有告警：`琥珀/红点 + N 家受限`；否则：`绿点 + N 家供应商` | 今日签到总加分 `> 0` 时显 `签到 +N` + 网关在线状态或 `⚠ N` |

### 6.4 三页内容设计

#### 第 1 页：今日用量分布（`OverviewDistributionView`）
- **顶栏**：绿点 + 「今日用量分布」 + 三段式紧凑切换胶囊 **`模型·提供商` | `提供商` | `Group`** + 右侧今日总净 Token（或 `—`）。
- **彩条 + Top 5**：`SegmentedProportionBar` + Top 5 行。`.combo` 行显示 `[模型短名]` 胶囊 + `[提供商]` 淡青标签；`.provider` 行显示图标 + 提供商名 + `N 账号 · M 模型`；`.group` 行显示 Group 名 + 命中提供商；右侧统一展示 `占比%`、`净 Token` 与分级 `缓存 XX%`。点击任意行复制原始标识并展示 1.5s 绿色 `✓ 已复制`。
- **三态空态归因**：`未检测到 Magpie 配置目录` / `今日有请求，暂无可统计 Token 分布` / `今日暂无模型请求记录`。
- **底栏**：左侧 `缓存命中 X.XM`，右侧 `🛡 今日脱敏 N 项 (M 次)`。

#### 第 2 页：最近 5 笔实时流水（`TokenZoneView`）
- **Live Bar**：状态点 + 「最近 5 笔流水」 + 右侧状态（暂停时优先 `已暂停 · M 条未读`，有缺口追加 `缺口 G`，正常态 `N 请求 · E 错 · 均耗时`）+ **⏸/▶ 暂停定格按钮**。
- **单行三栏**：
  - 左栏：主行 `[厂商小图标] 模型短名`；副行 `提供商 · 组名(或直连) · Agent`。
  - 中栏：顶部 `总 Token` + `缓存 XX%`（无命中率则主行显示 `入 X · 出 Y`）；中部 `3pt` 缓存进度条；底部 `入 X · 出 Y` + 若该笔命中脱敏 `n > 0` 显示青色 `🛡N`。
  - 右栏：主行 `总耗时` + 状态点（200 绿 / 499 灰 / 429 琥珀 / ≥400 玫红）；副行优先 `TTFT X.Xs`（无则 `HH:mm:ss`，失败行标 `HTTP 405` / `已切备用`）。
- **交互**：纯 SwiftUI `withAnimation` 新行绿闪（无 `Pow`）；点击行复制完整排查摘要并反馈 `✓ 已复制`。

#### 第 3 页：供应商额度与限流状态（`ProviderQuotaZoneView`）
- **顶栏**：状态点 + 「供应商额度与积分」 + 右侧提示「点击行展开明细」（或受限计数）。
- **列表区域（受控高度 `ScrollView`，最高 `220pt`）**：
  - 默认每家供应商折叠为 1 行：状态点 + 动态图标 + 提供商名 + 多账号徽标（`N 账号`）+ 限流/冷却徽标（`429 限流` / `冷却至 HH:mm`）；右侧横向水位条 + `剩余 / 上限`（或 `余 XX%`、`今日消耗 X`、`无刻度`）+ 副行摘要（如 `12h过期`、`2 号可用 · 3 号耗尽`、`可签到 +400`）。
  - 点击某家供应商行**手风琴展开**其所有账号与未隐藏窗口（显示脱敏账号名、套餐 `plan`、独立水位条、`runsOutAt`/`resetsAt`、以及 `limit-notices` 报错摘录）。
- **底栏**：左侧今日签到汇总（如 `今日签到：4 家已领 +400`），右侧 `gateway.json` + PID 校验后的网关在线态（绿点 `Magpie :3425 在线` 或灰点 `网关未运行`）。

### 6.5 设置、右键菜单与旧代码清理

- **精简右键菜单（直接挂接，移除中间 Popover）**：删除 `NotchMenuView.swift`、`Share.swift`、`Share+View.swift`、`NotchViewModel.showSettings` 及 `.popover(...)`；右键 `.contextMenu` 直接提供 **设置**（直开 `PreferencesWindowController`）、**打开 Magpie**（通过 `NSWorkspace` 唤起 `/Applications/magpie.app`）、**退出**。
- **`PreferencesWindow.swift`**：用 `ServiceManagement` 框架的 `SMAppService.mainApp` 原生 `Toggle` 替换 `LaunchAtLogin.Toggle`；「关于与状态 → 数据源」改为 `"Magpie (~/.config/magpie)"` 并展示网关状态。
- **彻底删除的旧文件与依赖**：
  - 删除 `UsageStore.swift`、`AntigravityStore.swift`、`Share.swift`、`Share+View.swift`、`NotchMenuView.swift`、`OverviewPageView.swift`（重构为新第 1 页载体）；
  - 删除 `NotchView.swift` 的 `dragDetector` / `dropTargeting` 与 `.popping` 状态；
  - 从 `NotchDrop.xcodeproj/project.pbxproj` 移除 `Pow`、`LaunchAtLogin-Modern`、`LookInside-Release`、`swift-collections` 4 个 SPM 依赖及 `libsqlite3.tbd`；
  - 替换 `Tests/` 中依赖 `SQLite3` 与 CC Switch / Antigravity / `showSettings` popover 的旧测试，新建覆盖 `MagpieStore`、增量 tail、探活/重试过滤、三维聚合、动态供应商合并、图标回退、P2 暂停/缺口、三页耳区切换的 `XCTest` 测试套件。

---

## 7. 设计拍板说明（Calls Made）

以下非分支性工程细节已一并拍板，审阅时可直接确认或覆写：
1. **探活与重试行过滤**：`usage.jsonl` 中 `kind == "provider_test" || source == "probe"` 的内部探活行全部过滤；`handed_on == true` 的组内失败重试行在流水保留「已切备用」标注，不计入 `E 错` 与异常率，避免自动兜底掩盖成功体验或制造假警报。
2. **P2 跨天边界与延迟口径**：当日 00:00 后 P2 流水与 P1 分布均按本地今日统计（不把昨天的流水带到今天），`均耗时` 取今日已完成非探活请求的平均值；`499` 客户端取消不计入 `E 错`。
3. **`⚠ N` 统一语义**：Peek 与 P1/P2/P3 耳区的黄色 `⚠ N` 统一统计 `limit-notices.json` 中尚未过期的活跃限流/风控条数（点击跳转 P3），保持跨页数字一致。
4. **放弃冗余日志解析**：不额外解析 `~/Library/Logs/magpie/app.log` 与 `routing` 的 `affinity` 字段，因限流/报错已由 `limit-notices.json` 和 `usage.jsonl` 完整承载，保持 `MagpieStore` 精简低耗。
5. **P3 多窗口与混合账号汇总**：按 `spans[i].aside != true` 选取第一个主窗口；限流中的有余量账号仍计入供应商总余量条但叠加警告徽标；`M 个耗尽` 统计 `limit > 0 && remaining <= 0` 的账号。
6. **移除 `NotchMenuView` 中间弹窗**：右键菜单直达设置窗口、打开 Magpie 与退出，消除多余的二次弹窗层级。
7. **暂停缓冲区上限**：P2 暂停定格队列上限设为 `200` 条，溢出后递增 `gapCount`。

---

## 8. 留给实现者（Claude Code）决定的细节

1. `MagpieStore` 内部子文件组织方式与 Swift 并发（GCD 串行队列 vs Swift `actor` + `@MainActor` 发布）实现细节。
2. `NotchDrop.xcodeproj/project.pbxproj` 中增删 Swift 文件（可复用 `scripts/`）及清理 4 个 SPM 引用节点。
3. `NotchViewModel.ContentType` 具体枚举命名及受影响旧测试的重写结构。
4. 单元测试 Fixture JSON/JSONL 的具体组织目录与用例拆分。
