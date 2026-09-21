# 账号池优化与 Qoder 每日自动签到功能实现计划

> **目标**：
> 1. 第一张卡片 Antigravity 禁用账号下置为小胶囊，主排保留可用账号 3D 聚光灯居中。
> 2. 第三张卡片 Qoder 账号池 Orb 居中排布。
> 3. 实现 Qoder 账号池每日 100 Credits 自动签到模块并接入。

---

## 任务拆分与执行步骤

### 任务 1：Antigravity 数据层解析修复与单元测试
- **文件**：`NotchDrop/AntigravityStore.swift`，`Tests/AntigravityStoreTests.swift`
- **内容**：
  1. `parseIndex(data:)` 扩展：解析 `accounts.json` 中每个账号条目的 `disabled` 与 `proxy_disabled`。
  2. `loadAccounts` 映射更新：优先以 `accounts.json` 的标记为最终权威状态。
  3. 编写单测验证：测试 `accounts.json` 中 `proxy_disabled: true` 时返回的 `AntigravityAccount.isDisabled == true`。
- **验证**：`swift test --filter AntigravityStoreTests`

### 任务 2：Antigravity 卡片上下分层（禁用账号下置小胶囊）
- **文件**：`NotchDrop/AntigravityAccountsCardView.swift`
- **内容**：
  1. 将主排 `accountsRow` 严格限制为 `store.accounts.filter { !$0.isDisabled }` 的重排。
  2. 新增 `disabledAccountsRow` 子视图：
     - 若存在禁用账号，在下方通过 `ScrollView(.horizontal)` 或 `HStack` 显示小型胶囊。
     - 样式：高 22pt，灰白透明度 0.08 玻璃底，小圆点灰度标识，8.5pt 姓名，带「已禁用」微标。
- **验证**：单测与预览验证。

### 任务 3：Qoder 账号池 Orb 水平居中
- **文件**：`NotchDrop/QoderPoolRingView.swift`
- **内容**：
  1. 将 `membersRow` 的外层容器包装为 `.frame(maxWidth: .infinity, alignment: .center)`。
  2. 验证 1~4 个账号时的居中排布效果。
- **验证**：检查布局代码，运行 App 验证。

### 任务 4：Qoder 自动每日领取 Credits 模块与接入
- **文件**：
  - 新增：`NotchDrop/QoderCampaignClaimer.swift`
  - 新增：`Tests/QoderCampaignClaimerTests.swift`
  - 修改：`NotchDrop/QoderStore.swift`（接入签到触发）
- **内容**：
  1. 实现 `QoderCampaignClaimer`：
     - 扫描 `~/.qoder-cn/pool/account_*.json`。
     - 异步并发调用 `/sash/api/v1/me/campaigns` 查活动。
     - 匹配到可领项后执行 `POST .../claim`。
     - 记录当天领取的账号 ID 防止重复刷。
  2. 在 `QoderStore.refresh()` 或启动时静默唤起 `QoderCampaignClaimer.claimAllOncePerDay()`。
  3. 编写 Mock 测试验证请求格式与逻辑正确性。
- **验证**：`swift test --filter QoderCampaignClaimerTests`

### 任务 5：全量回归测试与真机验证
- **内容**：
  1. 运行 `swift test` 确保 170+ 测试全绿。
  2. 编译并部署新版本至 `/Applications/NotchEvery.app`。
  3. 重启 App 请用户真机过目验收。
