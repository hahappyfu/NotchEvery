# Qoder 账号池增强：分页圆点露出、定时与手动刷新、每日签到状态展示、DeepSeek 额度耗尽自动换号

- **日期**：2026-09-22
- **状态**：已批准
- **分支**：`feat/qoder-pool-enhancements`

## 1. 目标与背景

随着 Qoder 账号池额度（credits）在刘海面板的接入，需要进一步完善交互体验与模型调用韧性：
1. **第一页分页指示器被裁剪**：第一页底部 SmoothPageIndicator 因卡片与内边距总高超出面板限制，导致圆点被挤到屏幕可视区外。
2. **第三页缺少刷新机制**：当前账号池额度只在特定生命周期探测，缺少周期性自动刷新（1 分钟）与显式手动刷新入口。
3. **credits 每日签到感知不足**：缺少一键领取入口，且用户无法直观获知当天每个账号是否已领取成功。
4. **DeepSeek 付费模型可用性**：DeepSeek 模型消耗 credits，当前账号 credits 耗尽时，网关必须具备事前避让与事后报错换号能力，自动流转至池内有余额的账号。

---

## 2. 详细设计与实现方案

### 2.1 第一页分页圆点（SmoothPageIndicator）露出修复

#### 问题定位
`NotchRootView` 内：
- `NotchView` 面板高度依据 `zoneSizeReporter` 上报的尺寸经 `clampPanelSize` 钳制。
- 第一页 `OverviewPageView` 垂直排列 `AntigravityAccountsCardView` + `AntigravityProxyCardView`，间距为 10pt，加上卡片内边距后总高度偏大。
- 底部 `SmoothPageIndicator` 的 `padding(.top, 6)` 与底部无安全余量，导致底边在贴边处容易被遮挡或溢出。

#### 修改方案
1. `OverviewPageView.swift`：
   - 垂直间距由 `spacing: 10` 微调至 `spacing: 8`。
2. `NotchRootView.swift`：
   - 在底部的 `VStack` 增加 `padding(.bottom, 6)`，保证最底部的分页圆点和底部边缘有稳定的呼吸空间，并在计算高度时将圆点尺寸完整计入。

---

### 2.2 第三页额度刷新机制（1 分钟定时 + 手动刷新按钮）

#### 需求描述
- **定时刷新**：面板保持打开状态时，每 60 秒（1 分钟）自动调用一次 `QoderStore.shared.refreshPoolQuotas()`。
- **手动刷新按钮**：替换掉 `QoderPoolRingView` 顶部的「粘性: ...」标签，改为紧凑的胶囊刷新按钮。

#### 方案设计
1. **定时机制**：
   - 在 `QoderStore` 中增加 60 秒的定时器轮询任务 `quotaRefreshTimerTask: Task<Void, Never>?`。
   - 在 `start()` 时启动定时轮询，每 60 秒触发 `refreshPoolQuotas()`；在 `stop()` 时取消该任务。
2. **手动刷新按钮**：
   - 修改 `QoderPoolRingView.swift` 中的 `header`：
     - 将原有的 `stickyLabel` 替换为 `refreshButton`。
     - 按钮样式：胶囊形状，高度 20pt，内置 `arrow.triangle.2.circlepath` 图标与文本 "刷新"。
     - 状态响应：当正在探测刷新中时（`store.isQuotaProbing`），图标执行旋转或置灰不可点击。

---

### 2.3 credits 每日领取与各账号签到状态展示

#### 需求描述
- 增加「一键签到」入口，批量触发当天签到。
- 实时与持久化记录当天各账号的领取状态，并在 UI 上直观展现。

#### 方案设计
1. **数据模型与状态流转**：
   - `QoderCampaignClaimer` 维护当天每个账号的领取状态字典：`claimOutcomes: [String: QoderClaimOutcome]`（Key 为 userId）。
   - 在本地持久化当天签到状态（按日期 `yyyy-MM-dd` 隔离记录在 UserDefaults 或缓存文件），保证重启后状态不丢失。
   - `QoderStore` 暴露发布属性 `@Published var claimOutcomes: [String: QoderClaimOutcome] = [:]`。
2. **UI 展现**：
   - **反代用量卡片底部** (`GatewayZoneView.swift`)：
     - 在 `metricsFooter` 区域左侧增加状态文本：`今日签到: X/Y`（已签到的账号数 / 总账号数）。
     - 右侧增加按钮「一键签到」，点击后触发后台任务调用 `QoderCampaignClaimer.shared.claimAll()`，并在完成后自动触发 `refreshPoolQuotas()`。
   - **账号 Orb Tooltip** (`QoderPoolRingView.swift`)：
     - 在 `tooltip(_ m: QoderPoolMember?)` 中增加一行展示：
       - `今日签到: 已领取` (claimed 或 alreadyClaimed)
       - `今日签到: 待签到 / 未领` (nothingToClaim)
       - `今日签到: 失败 (错误信息)` (failure)

---

### 2.4 DeepSeek 模型 credits 耗尽自动换号

#### 需求描述
Qoder 网关使用 DeepSeek 模型时消耗账号的 credits。若当前账号 credits 耗尽，应自动流转到池内其它有余额的账号。

#### 方案设计（Go 网关层）
1. **模型识别**：
   - 在 `internal/remote/client.go` 中，检查当前请求的模型名称（转为小写后判断是否包含 `deepseek`）。
2. **事前避让**：
   - 网关维护各账号的实时/最近探测到的 credits 余额信息，或当账号标记为 `credits_exhausted` 时进入当日冷却。
   - 在 `credential_pool.go` 的 `Pick()` 中：
     - 若当前请求是 DeepSeek 模型，优先避开冷却以及已明确 credits <= 0 的账号，挑选 `CoolReason != "credits_exhausted"` 的有效账号。
3. **实时报错换号**：
   - 在 `Inspect()` 方法处理响应时：
     - 检查返回体中的关键词：包含 `credits`、`point`、`点数不足`、`额度不足`、`insufficient`、`balance` 等错误提示。
     - 若命中：
       - 将该账号标记为冷却：`acc.Cooled = true`, `acc.CoolReason = "credits_exhausted"`, `acc.CooledUntil = nextLocalMidnight()`。
       - 清除 `stickyUser`（若当前是粘性号）。
       - 返回 `VerdictSwitch`，促使 `client.go` 自动触发下一轮挑选重试（最多 `maxSwitches` 次）。

---

## 3. 测试与验证策略

1. **单元测试**：
   - `QoderPoolRingViewTests` / `QoderStoreTests`：测试 60s 定时触发与手动刷新状态变更。
   - `QoderCampaignClaimerTests`：测试 claim 状态映射表与当日持久化解析。
   - `credential_pool_test.go`：新增单测验证含有 `credits` 耗尽的 403 错误会返回 `VerdictSwitch` 并正确冷却该账号。
2. **端到端真机冒烟测试**：
   - 打开第一页，目测第一页底部的三个圆点（SmoothPageIndicator）是否完整露出。
   - 切换至第三页，点击「刷新」按钮，观察额度数字是否更新。
   - 点击「一键签到」按钮，观察状态变化与 tooltip 提示。
   - 针对 DeepSeek 模型接口进行模拟测试，验证撞额度后的自动切换。
