# Qoder 账号池全池额度汇总与每号余额展示 · 设计规范

- **日期**：2026-09-21
- **状态**：待评审
- **相关组件**：`QoderStore`, `QoderCampaignClaimer`（复用凭证扫描）, `GatewayZoneView`（用量卡）, `QoderPoolRingView`（Orb tooltip）

---

## 1. 背景与目标

现状：第三页「Qoder 反代用量」卡的"剩余额度"只显示**当前粘性账号一个人**的额度（实测 300），但账号池实际有 4 个号、总池约 600 credits。用户希望：

1. **一处显示总的**：顶部"剩余额度"改为**全池所有账号合计**，让面板反映真实可用总量。
2. **一处显示每个的**：每个 Orb 能看到自己账号的余额。

### 数据现实（决定架构的关键约束）

- 网关 `/quota`（`handleQuota → svc.Quota → FetchQuota`）只查**当前活跃/粘性账号一个**的上游额度，返回扁平 `{total, used, remaining, ...}`。它拿不到全池。
- 网关 `/v1/pool/status`（`AccountStatusDTO`）每个成员只有 `user_id/source/cooled/token_expires_at/last_used_at/last_probe_ok`，**不含任何 quota 字段**。
- 结论：**per-account 余额目前不存在于任何一层**，必须新增数据源。

## 2. 架构决策（控制者已定）

**方案 A：App 侧直连查询。** App 读取 `~/.qoder-cn/pool/account_*.json` 里每个账号的凭证（access_token + machine_id + user_id），逐个向 `https://gateway.qoder.com.cn/api/v2/quota/usage` 发 GET，解析该号余额，汇总为全池总额并回填到每个 Orb。纯 Swift，不改 vendor Go，复用现有 `QoderCampaignClaimer` 已经验证过的凭证读取模式（同一批 token、同类后台轮询行为）。

**口径（控制者已定）**：单号余额 = `userQuota.remaining + addOnQuota.remaining`（套餐余量 + Add-on 资源包余量全加，最贴近"还能用多少"）。全池总额 = 各号该值之和。

**每号展示（控制者已定）**：tooltip 悬浮显示（零布局改动，最克制）。

### 为什么不选 B/C

- B（改网关 Go 给 PoolStatus 加 quota）：跨语言改动 + 重编译内嵌二进制 + DTO/前端三处联动，侵入本仓库边界之外，风险高。
- C（只做标注不扩数据源）：不满足"看总数"诉求，治标不治本。

## 3. 详细设计

### 模块 D-1：凭证级额度探针 `QoderPoolQuotaProber`

新文件 `NotchDrop/QoderPoolQuotaProber.swift`（与 claimer 平级、同风格、可注入 transport）：

- 复用/参照 `QoderPoolAccountCredential`（已在 claimer 定义，含 access_token/machine_id/user_id）与其 pool 目录扫描逻辑。为避免重复，凭证类型和 `scanAccounts` 提取到共享位置或直接从 claimer 暴露；**优先做法**：把 `QoderPoolAccountCredential` + 目录常量提到一个新的小文件 `QoderPoolCredentials.swift`，claimer 与 prober 都 import 它（消除复制）。若判定提取会牵动 claimer 测试过多，则退化为 prober 自带一份私有扫描（在计划里标注取舍）。
- `struct QoderAccountQuota: Equatable { let userId: String; let planRemaining: Double; let addOnRemaining: Double; var totalRemaining: Double { planRemaining + addOnRemaining } }`
- `func probeAll() async -> [QoderAccountQuota]`：遍历凭证，逐个 GET `/api/v2/quota/usage`（带与 claimer 相同的 Cosy-* 头），解析 `userQuota.remaining` 与 `addOnQuota?.remaining ?? 0`；单号失败静默跳过（不影响其余），日志脱敏（只打 userId 前缀）。
- 并发：顺序 for-await（与 claimer 一致，简单优先，避免多号并发打线上接口触发风控）。
- transport：复用 claimer 已定义的通用 `QoderCampaignTransport`（GET+POST+多 header+body）协议及其 URLSession 默认实现；若该协议命名过于绑定"campaign"语义，可在计划里决定是否改名/新建等价协议——**裁决倾向**：直接复用，不过度重构。

### 模块 D-2：`QoderStore` 集成

- 新增 `@Published private(set) var poolQuotas: [QoderAccountQuota] = []`。
- 计算属性 `var poolTotalRemaining: Double? { poolQuotas.isEmpty ? nil : poolQuotas.reduce(0){ $0 + $1.totalRemaining } }`。
- 触发时机：与 claimer 同节奏——`start()` 首次、`refresh()` 轮询时顺带异步 `probeAll()`（detached、catch 全部错误仅日志、绝不阻塞主流程）。加 in-flight 守卫防重叠（照搬 claimer 的 `UnfairLock` + isRunning 模式）。
- 缓存去抖：结果非空才覆盖 `poolQuotas`；prober 内部按 userId 记录上次成功时间，避免同一 tick 对已成功号重复查（可选，若成本可控）。

### 模块 D-3：顶部用量卡（GatewayZoneView）

- "剩余额度" metricCell 的值来源从 `store.quota!.remaining`（单人）改为 `store.poolTotalRemaining`（全池合计），取整显示。
- 标题旁/副文案补一行小字：`· N 个号合计`（N = poolQuotas.count）。当 `poolTotalRemaining == nil`（未运行/无数据）回退显示 `--`，并在 footer 保持既有"网关已停止/离线"文案。
- 保留原"重置"footer 不变（那是粘性号的刷新点，仍有效）。

### 模块 D-4：Orb tooltip（QoderPoolRingView）

- `circleMember` 的 `.help(tooltip(member))` 扩展：若 `store.poolQuotas` 里有该 userId 的余额，追加一行「余额 X credits」。
- tooltip 函数签名相应调整（多传一个可选 quota 参数或在视图内拼接）。

## 4. 测试与验证

- `QoderPoolQuotaProberTests`：fake transport 返回含 userQuota+addOnQuota 的样例 JSON → 断言 totalRemaining = 两者相加；缺 addOnQuota → 只算 plan；单号 GET 抛错 → 结果数组跳过该号但不中断其余；header 构造正确（Authorization + Cosy-MachineId 等）。
- `QoderStore` 层：poolTotalRemaining 求和正确性（可直接测计算属性，喂入固定 poolQuotas）。
- 真机：面板展开后顶部数字应等于各号 tooltip 余额之和；对照手动 curl 每号 `/api/v2/quota/usage` 验证数值准确。

## 5. 风险与边界

- App 周期性用全部账号 token 打线上额度接口：与现有 claimer 打活动接口是同一批凭证、同类后台行为，风控面相当；靠顺序处理 + in-flight 守卫 + 轮询节流控制频率。
- 某号 token 失效（401）：该号跳过、不计入总额，UI 上其 Orb tooltip 无余额行——可接受降级，不 crash。
- 时区/刷新窗口：仅影响"重置"文案（沿用现状），不影响余额读数（余额是实时快照）。
