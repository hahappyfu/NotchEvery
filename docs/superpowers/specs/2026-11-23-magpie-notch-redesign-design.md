# NotchEvery × Magpie 数据与刘海重构设计

- **日期**：2026-11-23
- **状态**：已定稿（完成 Builder Check、录屏参考筛选与 Unslop 瘦身审计）
- **目标仓库**：`/Users/fupingguo/fuhawa_workspace/NotchEvery`
- **视觉基线**：`design-system/notchevery/MASTER.md` + `design-system/notchevery/pages/notch-island.md`
- **分工约定**：设计文档与实施计划定稿后，编码与测试由 Claude Code 实施。

---

## 1. 背景与重构目标

NotchEvery 此前合入 `fuckharness/apps/fluxbar-mac`（`FluxNotch`），现用户停用 `fuckharness`，回归独立的 `NotchEvery` macOS 刘海应用；本地聚合网关已切换为 **`magpie.app`**（`~/.config/magpie/`），不再依赖 `~/.cc-switch/cc-switch.db` 与 `~/.antigravity_tools`。

本次从 **数据层** 与 **UI/交互层** 同步改造：
1. **接入 Magpie 自描述数据源**：用纯本地文件监听与增量解析替代 CC Switch SQLite，覆盖 `Group → 提供商 + 模型` 聚合路由、`accountNames` 账号别名、`quotas.json` + `quota-history.json` 多窗口额度与历史曲线、`limit-notices.json` 限流冷却、`plugin-checkin.json` 签到、以及 `masking/*.jsonl` 隐私脱敏统计。新增供应商或路由组无需改代码即可自动识别。
2. **克制移植有效视觉，不做仪表盘堆砌**：从用户提供的 Magpie 托盘录屏（`PixPin_2026-11-23_16-15-04.mp4`）中只保留真正服务「抬头瞄一眼」的组件——第 1 页「极简汇总 + 28pt 24h 分时柱图 + 吞吐 `tok/s`」、第 3 页「折叠按家汇总 + 展开单账号 `accountNames` / Sparkline / 百分比小圆环」；**明确舍弃**第 2 页占高度的曲线流向拓扑图（高度还给完整 5 笔流水）、四格重复大 KPI、美元费用估算与年度热力图。
3. **吸收 `FluxNotch` 工程改进并清退三方依赖**：迁入按页条件耳区、流水暂停定格（`isPaused`/`missedCount`/`gapCount`）、点击行复制、三态空态归因、纯 SwiftUI 新行入场绿闪；彻底剔除 `BallPit`（额度球盆）、`Pow`、`LaunchAtLogin-Modern`、`LookInside-Release`、`swift-collections` 与 `libsqlite3`，开机自启改用 `SMAppService.mainApp`。

---

## 2. 边界与约束（Constraints & Anti-Goals）

### 必须守住的红线
- **部署目标**：`MACOSX_DEPLOYMENT_TARGET = 13.0`（禁 macOS 14+ 独有 API 如 `@Observable`；状态发布延续 `@MainActor` + `ObservableObject`/`@Published`）。
- **零硬编码供应商**：禁止定义供应商枚举；名称、图标、窗口均从 Magpie 数据与配置动态解析。
- **不读密钥、不调私有接口**：绝不读取 `logins.json`、`plugin-auth.json`、`caller-keys.json`、`redact.key`、`settings.json`、`sessions.json`，不请求 `127.0.0.1:3425`。
- **不造假 0**：数据源未就绪显示 `—`，无额度刻度渠道显示「无刻度」与虚线轨道，绝不渲染假 `0%`。
- **闭合零空转**：刘海处于 `.closed` 且未悬停虚影时，停止高频解析与定时器。
- **零 Emoji 与无障碍**：结构图标全用 SF Symbols 或本地厂商图标；动态数字全加 `.monospacedDigit()`；全量适配 `@Environment(\.accessibilityReduceMotion)` 与 `.accessibilityLabel(...)`。
- **尺寸纪律**：`IslandMetrics.panelContentInset = 18pt`，页宽 `420pt`–`430pt`，受 `ZoneSizeGuard`（宽 `<= 640pt`、高 `<= screenRect.height * 0.4`）限制。
- **离线单测**：`MagpieStore` 与聚合器必须支持注入 `magpieConfigDir: URL` 与 `now: Date`，单测仅读临时 Fixture，不依赖本机真实目录。

---

## 3. 数据接入方案选型

| 方案 | 做法 | 取舍结论 |
| :--- | :--- | :--- |
| **方案 1：纯本地文件直读 + FSEvents 增量监听（选定）** | `MagpieStore` 监听 `~/.config/magpie/` 白名单文件，JSONL 增量 tail，小 JSON 去抖整读 | 不耦合 `3425` 私有接口与 `lanKey`，Magpie 滚动升级不断联，单测完全离线可控；缺点是刷新频率跟随 Magpie 落盘节奏 |
| **方案 2：轮询 `127.0.0.1:3425`** | 请求 Magpie 内部 HTTP 接口 | 私有接口无稳定契约且带鉴权，随高频发版易断，否决 |

---

## 4. Magpie 本地文件契约（实盘核实）

默认根路径：`~/.config/magpie/`（`AppPaths` 集中定义并支持测试注入）。

### 4.1 增量 JSONL 日志

1. **`usage.jsonl`**（跨天追加）：
   - 关键字段：`route_id: Int64?`、`rid: String?`、`t: String`（变长微秒 RFC3339）、`agent: String`、`provider: String`、`providerAccount: String?`、`req: String?`、`model: String`、`served: String?`、`in: Int`、`out: Int`、`cache_read: Int`、`cache_write: Int`、`ms: Int?`、`ttft_ms: Int?`、`flow_ms: Int?`、`masking_ms: Int?`、`status: Int?`、`tries: Int?`、`handed_on: Bool?`、`kind: String?`、`source: String?`。
   - **探活过滤**：丢弃 `kind == "provider_test" || source == "probe"` 的内部探活行（否则会混入大量 403 噪音）。
   - **主键与乱序**：重试/故障转移会使同 `route_id` 出现多行（前序失败标 `handed_on: true`，接管成功行带 `tries >= 2`）；行 ID 取 `rid ?? "\(route_id ?? 0)-\(byteOffset)"`。因并发请求完成时间可能微幅乱序，冷启动从文件尾逆扫时需保留跨日缓冲。
   - **指标口径（仅统计本地今日 00:00 起）**：
     - 净消耗 `netTokens = in + out`；缓存命中率 `cache_read / (in + cache_read)`（分母为 0 返回 `nil`）。
     - 吞吐速率 `tokensPerSecond`：当 `out > 0` 且 `genMs = flow_ms ?? (ms != nil && ttft_ms != nil ? max(0, ms! - ttft_ms!) : nil) > 0` 时，取 `Double(out) / (Double(genMs) / 1000.0)`。
     - 错误与重试：`499` 客户端取消流水标灰「已取消」，不计入错误；`handed_on == true` 标「已切备用」，不计入错误；`E 错` 统计今日 `status >= 400 && status != 499 && handed_on != true`；`status == 200 && (tries ?? 1) > 1` 计入重试成功数。
2. **`routing/YYYY-MM-DD.jsonl`**（按本地日期轮转）：
   - 读取 `id: Int64`、`group: { id, ref, name }?` 与 `order: [{ id, provider, name?, icon?, who?, plan?, used?, amount?, limit?, unit?, usedWindow?, due?, known? }]?`。
   - 内存只保留「最近 200 条 `id → group` 映射」与「每个 `order[].id` 最新额度快照」（用于补全 `quotas.json` 未落盘的 `sensenova-token-plan`、`workbuddy` 等渠道）。
3. **`masking/YYYY-MM-DD.jsonl`**（按本地日期轮转）：
   - 读取 `route: Int64`、`n: Int`；按 `route` 累加 `n`，输出单笔脱敏数与今日总脱敏项数。

### 4.2 状态与元数据 JSON

1. **`quotas.json`**：Dict，键 `"<provider>/<account>"`（剥除 `"<quota.provider>/"` 得 `accountKey`），值 `{ at, quota: { provider, name, icon?, plan?, user?, windows[] }, spans: [{ aside? }] }`。
   - `aside == true` 位于平行数组 `spans[i]` 中；主窗口取首个 `spans[i].aside != true` 的窗口（全为 `aside` 时回退第一个）。
   - `used` 为百分比 `0...100`，剩余量 `remaining = max(0, limit - (amount ?? limit * used / 100))`。
2. **`quota-history.json`**：Dict，键 `"<provider>|<account>"`（按首个 `|` 拆分），值 `[windowName: [{ at, left, resetsAt? }]]`，取主窗口最近最多 24 个 `left`（`0...100`）绘制 Sparkline。
3. **`limit-notices.json`**：Dict，键 `"<provider>@<account>"`（按首个 `@` 拆分），值 `{ key, why, status?, error?, at, until? }`；`until == nil || until > now` 计为活跃告警，映射 `.cooling(until)` / `.riskBlocked`（403/405）/ `.rateLimited`（429/`rate`）。
4. **`plugin-checkin.json`**：Dict，键 `"<provider>|<slot>"`（按首个 `|` 拆分），值 `{ day, at, outcome, credit?, msg? }`；过滤 `day == 今日`，`"claimed"` 与 `"done"` 均计入今日已领积分。
5. **`providers.json`**：读取 `providers[]`（`id`, `name`, `icon?`, `disabled?`, `hidden?`, **`accountNames: [String: String]?`**）与 `groups[]`（`id`, `name`, `members?`, `hidden?`）。
   - 账号展示名优先级：`accountNames[accountKey]`（如 `手机主号`、`傅1`）→ `who`/`user`（已脱敏）→ 截断 `accountKey`。
6. **`plugin-providers.json`**（只读 `id`, `name`, `icon?`, `signedIn?`）、**`plugin-icons.json`**（映射 `"file:<filename>"`）、**`gateway.json`**（`addr`, `pid`, `version`, `started`，结合 `kill(pid, 0)` 校验在线态）。

### 4.3 调度、跨天与动态图标

- **FSEvents + 去抖**：监听 `~/.config/magpie` 与 `routing/`、`masking/`，`0.4s` 去抖；检测 `inode` 变化或 `size < offset` 时归零重读。
- **开合三级调度**：`.closed`（非虚影）停表零空转；`hoverGhosting` 立即追平一次并按 `1.5s` 去抖刷新；`.opened` 按 `1.5s` 刷新，P2 暂停定格冻结视图并缓冲最多 `200` 条新行（超出递增 `gapCount`）。跨午夜自动切换当日文件并清空今日累计。
- **图标解析 `MagpieIconResolver`**：先查 `plugin-icons.json`；得 `file:<name>` 后依次查 `~/.cache/magpie/icons-small/<name>.png` → `~/.config/magpie/icons/<name>`（PNG/WebP 直读 `NSImage`，`.svg` 用 `QLThumbnailGenerator` 光栅化缓存 32×32）；缺失时兜底基于 `provider` ID 哈希的渐变圆徽 + 首字母。

---

## 5. 三页刘海设计与组件清单

沿用 `CONTEXT.md` 黑岛外观、物理挖槽中央禁放区（`deviceNotchRect.width + 16pt`）与底部 `SmoothPageIndicator`（3 页：`[.overview, .token, .providers]`）。

### 5.1 悬停虚影（Peek）与耳区（Notch Ears）

- **Peek 胶囊**：状态圆点（正常绿 / 活跃 `limit-notices` 琥珀或红）+ `[最近或主力提供商 · 模型短名]` | `今日净 Token · 缓存率` +（活跃告警 `> 0` 时）SF `exclamationmark.triangle.fill` + `N`。无配置目录显示「等待 Magpie 数据」，今日 0 请求显示「Magpie 就绪 · 今日 0 请求」。
- **耳区（等高占位）**：
  - **P1 用量**：左耳绿点 + `N 个活跃组合`（随切换维度变更）；右耳 SF `clock` + `HH:mm`（今日最新请求）+ 可点击 `⚠ N`（SF `exclamationmark.triangle.fill`，直跳 P3）。
  - **P2 流水**：左耳最新命中 `提供商图标 + 名称`；右耳 SF `arrow.up.arrow.down` + `RollupText` 今日总请求 + 可点击 `⚠ N`。
  - **P3 额度**：左耳有告警时 `琥珀/红点 + N 家受限`，否则 `绿点 + N 家供应商`；右耳今日签到 `> 0` 时 `签到 +N` + 网关在线态或 `⚠ N`。

### 5.2 第 1 页：今日用量（`OverviewDistributionView`）
- **单行紧凑总览**：绿点 +「今日用量」+ `.monospacedDigit()` 展示 `总净Token · 缓存率 · 脱敏 N`（SF `lock.shield.fill`，0 次脱敏时隐去）。
- **24h 分时堆叠柱图（`28pt` 高）**：左上放三段切换胶囊 **`模型·提供商`（默认）| `提供商` | `Group`**，右上显示当前总量或悬停小时读数（`HH:00 · X Tokens · 主力提供商`）；底部配 `00 / 06 / 12 / 18 / 24` 刻标。
- **Top 5 列表**：按所选维度聚合，右侧统一 `.monospacedDigit()` 展示 `净Token · tok/s · 缓存%`（无缓存时展示 `首字 X.Xs`）；点击行复制原始标识并展示 1.5s 绿色 `✓ 已复制`。
- **三态空态**：`未检测到 Magpie 配置目录` / `今日有请求，暂无可统计 Token 分布` / `今日暂无模型请求记录`。

### 5.3 第 2 页：最近 5 笔实时流水（`TokenZoneView`）
- **Live Bar**：状态点 + `今天 N 次` + 汇总 `E 错 · 均耗时`（暂停优先显示 `已暂停 · M 条未读`，缺口追加 `缺口 G`）+ SF `pause.circle` / `play.circle.fill` 按钮。
- **完整 5 行 2 行式流水**（无顶部拓扑图，把全部高度留给真实请求）：
  - **首行**：`[Agent 胶囊]` + `group/xxx`（或模型）+ 右对齐 `HH:mm:ss`；
  - **次行**：`厂商图标 + 提供商 · 账号别名 · 模型短名` + 右对齐 `总Token · 耗时 · tok/s · 脱敏N(若有) · 状态点`（200 绿 / 499 灰 / 429 琥珀 / ≥400 玫红）。
- **交互**：纯 SwiftUI `withAnimation` 新行绿闪；点击行复制排查摘要。

### 5.4 第 3 页：供应商额度（`ProviderQuotaZoneView`）
- **顶栏**：状态点 +「供应商额度」+ 右侧「点行展开明细」。
- **受限滚动列表（`ScrollView` 最高 `220pt`）**：
  - **折叠态（默认 1 行/家）**：状态点 + 动态图标 + 提供商名 + 多账号胶囊 `N 账号` + 限流/冷却徽标（`429` / `冷却至 HH:mm`）；右侧横向水位条 + `剩余 / 上限`（或 `余 XX%`、`无刻度`+虚线轨道）+ 副行摘要（`12h过期`、`2 可用 · 3 耗尽`）。排序：`有余量活跃 > 有余量带告警 > 已耗尽 > 无刻度`。
  - **手风琴展开态（单账号卡片）**：左区显示 `accountNames` 友好别名 + `plan` + `quota-history` 虚线 Sparkline + `重置 MM/dd · 预计 Xh 耗尽`（带限流时附报错摘要）；右区横向并排 1–3 枚 `26pt` 百分比小圆环（含所有窗口）。
- **底栏**：左侧今日签到汇总（`签到：4 家已领 +400`），右侧网关在线态（`Magpie :3425 在线` / `网关未运行`）。

### 5.5 菜单、设置与清理范围
- **右键 `.contextMenu`**：直接提供 **设置**（直开 `PreferencesWindowController`）、**打开 Magpie**（唤起 `/Applications/magpie.app`）、**退出**；删除 `NotchMenuView.swift`、`vm.showSettings` 与中间 `.popover`。
- **`PreferencesWindow.swift`**：用 `ServiceManagement` `SMAppService.mainApp` 替换 `LaunchAtLogin.Toggle`；「数据源」显示 `"Magpie (~/.config/magpie)"` 与网关版本号。
- **清理删除清单**：
  - 删除 `UsageStore.swift`、`AntigravityStore.swift`、`Share.swift`、`Share+View.swift`、`NotchMenuView.swift`、`OverviewPageView.swift`（重构为第 1 页载体）；
  - 删除 `NotchView.swift` 的 `dragDetector` / `dropTargeting` 与 `.popping` 状态；
  - 从 `NotchDrop.xcodeproj/project.pbxproj` 移除 `Pow`、`LaunchAtLogin-Modern`、`LookInside-Release`、`swift-collections` 4 个 SPM 依赖及 `libsqlite3.tbd`；
  - 替换 `Tests/` 中依赖 `SQLite3` 与 CC Switch / Antigravity / `showSettings` 的旧单测为 `MagpieStore`、增量 tail、探活/重试过滤、`accountNames` / `quota-history` 解析、三维聚合、24h 分时桶、动态合并、图标回退、P2 暂停/缺口、三页耳区切换测试。

---

## 6. 设计拍板说明（Calls Made）

1. **取舍依据**：从录屏保留 P1 分时柱图/`tok/s` 与 P3 别名/Sparkline/小圆环，砍掉 P2 拓扑曲线、四格大 KPI、美元估算与热力图，优先保证黑岛留白与 5 行流水完整可见。
2. **数据口径**：过滤 `provider_test` 探活；`499` 与 `handed_on: true` 不计入 `E 错`；P1/P2 按本地今日 `00:00` 归零；黄色 `⚠ N` 全刘海统一统计未过期 `limit-notices` 条数；不解析 `app.log` 与 `affinity`。
3. **默认边界**：P3 单账号展开展示前 3–4 个窗口圆环；P2 暂停定格缓冲区上限 `200` 条。

---

## 7. 留给 Claude Code 决定的细节

1. `MagpieStore` 内部文件拆分与队列/actor 并发组织。
2. `NotchDrop.xcodeproj/project.pbxproj` 增删文件节点与清理 4 个 SPM 引用（可复用 `scripts/add_file_to_project.py`）。
3. `NotchViewModel.ContentType` 枚举命名及受影响旧测试的重构组织。
4. 单元测试 Fixture 目录与构造写法。
