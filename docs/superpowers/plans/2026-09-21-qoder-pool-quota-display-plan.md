# Qoder 全池额度汇总与每号余额展示 · 实现计划

> 设计权威：`docs/superpowers/specs/2026-09-21-qoder-pool-quota-display-design.md`
> 分支：从 main 起 `feat-qoder-pool-quota`。工程为 Xcode pbxproj（非自动同步文件组），新增源文件必须手工登记 8 处（见既有 claimer 提交范例）。

## 全局约束

- 单号余额口径 = `userQuota.remaining + addOnQuota.remaining`；全池总额 = 各号之和，取整显示。
- prober 顺序处理、in-flight 守卫、失败静默跳过、日志脱敏（userId 前缀）——照搬 `QoderCampaignClaimer` 模式。
- 绝不在单元测试打真实接口；全部走 fake transport。
- 网络经注入协议（复用 `QoderCampaignTransport`）。

---

### 任务 1：凭证扫描去重 + `QoderPoolQuotaProber` 核心 + 测试
- 文件：新增 `NotchDrop/QoderPoolCredentials.swift`（把 `QoderPoolAccountCredential` + pool 目录常量 + `scanAccounts` 从 claimer 提取共享）、新增 `NotchDrop/QoderPoolQuotaProber.swift`、新增 `Tests/QoderPoolQuotaProberTests.swift`；改 `NotchDrop/QoderCampaignClaimer.swift`（改用共享凭证类型，行为不变）。
- 内容：prober 定义 `QoderAccountQuota`、`probeAll()`（GET `/api/v2/quota/usage`，解析 userQuota+addOnQuota，单号失败跳过）。TDD：先写红测再实现。
- 验证：`xcodebuild test -only-testing:NotchEveryTests/QoderPoolQuotaProberTests`；pbxproj 为新文件登记。

### 任务 2：`QoderStore` 集成 poolQuotas + 触发 + in-flight 守卫
- 文件：`NotchDrop/QoderStore.swift`；测试补进 `Tests/QoderStoreTests.swift`。
- 内容：`@Published poolQuotas`、`poolTotalRemaining` 计算属性、start()/refresh() 异步触发 probeAll（detached+catch+守卫）。
- 验证：`xcodebuild test -only-testing:NotchEveryTests/QoderStoreTests`。

### 任务 3：顶部用量卡显示全池合计
- 文件：`NotchDrop/GatewayZoneView.swift`。
- 内容："剩余额度" metricCell 值改 `store.poolTotalRemaining`（取整），副文案「· N 个号合计」，nil→"--"。
- 验证：编译 + 预览。

### 任务 4：Orb tooltip 每号余额
- 文件：`NotchDrop/QoderPoolRingView.swift`。
- 内容：tooltip 追加「余额 X credits」行（按 userId 查 poolQuotas）。
- 验证：编译。

### 任务 5：全量回归 + Release 构建部署真机验收
- `xcodebuild test`（全绿）→ Release 构建 → 装 /Applications → 请用户对照手动 curl 数值验收。
