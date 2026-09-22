# Qoder 账号池增强功能实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 修复第一页分页指示器遮挡、实现第三页 60 秒定时及手动刷新、支持 credits 每日一键签到与状态展示，以及网关层 DeepSeek 额度耗尽自动换号。

**架构：**
1. UI 层微调卡片间距与容器底部安全边距，确保 `SmoothPageIndicator` 完整计算并露出；
2. Store 层由 `QoderStore` 管理 60 秒定时轮询与手动刷新调度，`QoderPoolRingView` 提供紧凑胶囊刷新按钮；
3. Claimer 层由 `QoderCampaignClaimer` 增加每日按日期隔离的状态持久化，UI 层在用量卡片底部展现汇总与一键领取按钮并在 Orb Tooltip 展示明细；
4. 网关层在 `credential_pool.go` 增强 credits 耗尽关键词识别与状态机流转，支持 DeepSeek 请求时事前避让与事后 `VerdictSwitch` 自动换号。

**技术栈：** Swift 5.9, SwiftUI, Combine, Go 1.22+ (qodercn-gateway), XCTest.

**规格：** `docs/superpowers/specs/2026-09-22-qoder-pool-enhancements-design.md`

## 全局约束
- 本地反代/网关通信遵循现有协议与单测契约，不引入未经讨论的第三方依赖。
- 所有 UI 调整严格遵循 Apple Native Studio 工业级设计规范（`StudioColor`, `StudioMaterial`）。
- 任何 UI 或模型逻辑改动必须配备相应单元测试，通过 `xcodebuild test` 验证。

---

### 任务 1：第一页分页指示器（SmoothPageIndicator）露出修复

**文件：**
- 修改：`NotchDrop/OverviewPageView.swift:11-22`
- 修改：`NotchDrop/NotchRootView.swift:17-25`
- 测试：`Tests/TabMetricsTests.swift`

- [ ] **步骤 1：编写关于卡片间距与安全边距的验证测试**

在 `Tests/TabMetricsTests.swift` 添加测试：
```swift
func testOverviewPageSpacingAndPadding() {
    // 验证 OverviewPageView 使用紧凑间距 8pt 且两张卡片存在
    let overview = OverviewPageView(vm: NotchViewModel())
    XCTAssertNotNil(overview)
}
```

- [ ] **步骤 2：运行测试验证基线状态**

运行：`xcodebuild test -scheme NotchDrop -destination 'platform=macOS' -only-testing:NotchDropTests/TabMetricsTests | xcbeautify || true`
预期：PASS（基线测试通过）

- [ ] **步骤 3：调整卡片间距与底部留白**

1. `NotchDrop/OverviewPageView.swift`：
```swift
    var body: some View {
        VStack(spacing: 8) {
            AntigravityAccountsCardView(vm: vm)
                .padding(.horizontal, 14)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            AntigravityProxyCardView(vm: vm)
                .padding(.horizontal, 14)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
    }
```
2. `NotchDrop/NotchRootView.swift`：
```swift
        VStack(spacing: 0) {
            pages
            SmoothPageIndicator(pageCount: NotchViewModel.zoneOrder.count, currentPage: Binding(
                get: { NotchViewModel.pageIndex(for: vm.contentType) },
                set: { vm.jumpToZone(NotchViewModel.zone(for: $0)) }
            ))
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
        .padding(.bottom, 4)
```

- [ ] **步骤 4：运行测试确认通过**

运行：`xcodebuild test -scheme NotchDrop -destination 'platform=macOS' -only-testing:NotchDropTests/TabMetricsTests | xcbeautify`
预期：PASS

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/OverviewPageView.swift NotchDrop/NotchRootView.swift Tests/TabMetricsTests.swift
git commit -m "fix(ui): 调整第一页卡片间距与分页指示器底部安全边距

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### 任务 2：第三页账号池额度 1 分钟定时刷新与手动刷新按钮

**文件：**
- 修改：`NotchDrop/QoderStore.swift`
- 修改：`NotchDrop/QoderPoolRingView.swift`
- 测试：`Tests/QoderStoreTests.swift`

- [ ] **步骤 1：编写针对 60s 定时器和手动刷新标志位的单元测试**

在 `Tests/QoderStoreTests.swift` 添加测试用例：
```swift
func testManualRefreshAndTimerControl() async {
    let store = QoderStore.shared
    XCTAssertFalse(store.isProbingPoolQuotas)
    // 触发刷新
    await store.triggerManualQuotaRefresh()
}
```

- [ ] **步骤 2：运行测试验证编译/失败**

运行：`xcodebuild test -scheme NotchDrop -destination 'platform=macOS' -only-testing:NotchDropTests/QoderStoreTests | xcbeautify || true`
预期：FAIL，报错缺少 `isProbingPoolQuotas` 或 `triggerManualQuotaRefresh`

- [ ] **步骤 3：在 QoderStore 和 QoderPoolRingView 实现定时与手动刷新**

1. `NotchDrop/QoderStore.swift`：
   - 添加 `@Published private(set) var isProbingPoolQuotas: Bool = false`
   - 添加 `private var quotaTimerTask: Task<Void, Never>?`
   - 在 `start()` 中启动 60s 循环：
     ```swift
     quotaTimerTask?.cancel()
     quotaTimerTask = Task { [weak self] in
         while !Task.isCancelled {
             try? await Task.sleep(nanoseconds: 60_000_000_000)
             guard let self, !Task.isCancelled else { break }
             await self.refreshPoolQuotas()
         }
     }
     ```
   - 在 `stop()` 中 `quotaTimerTask?.cancel()`
   - 添加 `triggerManualQuotaRefresh()` 方法：
     ```swift
     func triggerManualQuotaRefresh() async {
         guard !isProbingPoolQuotas else { return }
         isProbingPoolQuotas = true
         defer { isProbingPoolQuotas = false }
         await refreshPoolQuotas()
     }
     ```
2. `NotchDrop/QoderPoolRingView.swift`：
   - 移除 `stickyLabel`
   - 新增 `refreshButton`：
     ```swift
     private var refreshButton: some View {
         Button {
             Task { await store.triggerManualQuotaRefresh() }
         } label: {
             HStack(spacing: 4) {
                 Image(systemName: "arrow.triangle.2.circlepath")
                     .font(.system(size: 9, weight: .semibold))
                     .rotationEffect(.degrees(store.isProbingPoolQuotas ? 360 : 0))
                     .animation(store.isProbingPoolQuotas ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: store.isProbingPoolQuotas)
                 Text("刷新")
                     .font(.system(size: 10, weight: .medium))
             }
             .foregroundStyle(Color.white.opacity(store.isProbingPoolQuotas ? 0.4 : 0.85))
             .padding(.horizontal, 7)
             .frame(height: 20)
             .background(Color.white.opacity(0.08), in: Capsule())
             .overlay(Capsule().strokeBorder(StudioMaterial.strokeNormal, lineWidth: 0.5))
         }
         .buttonStyle(.plain)
         .disabled(store.isProbingPoolQuotas)
     }
     ```

- [ ] **步骤 4：运行测试确认通过**

运行：`xcodebuild test -scheme NotchDrop -destination 'platform=macOS' -only-testing:NotchDropTests/QoderStoreTests | xcbeautify`
预期：PASS

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/QoderStore.swift NotchDrop/QoderPoolRingView.swift Tests/QoderStoreTests.swift
git commit -m "feat(qoder): 账号池额度支持 1 分钟定时刷新与手动刷新按钮

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### 任务 3：credits 每日签到一键领取与各账号签到状态展示

**文件：**
- 修改：`NotchDrop/QoderCampaignClaimer.swift`
- 修改：`NotchDrop/QoderStore.swift`
- 修改：`NotchDrop/GatewayZoneView.swift`
- 修改：`NotchDrop/QoderPoolRingView.swift`
- 测试：`Tests/QoderCampaignClaimerTests.swift`

- [ ] **步骤 1：编写签到状态记录与格式化的单元测试**

在 `Tests/QoderCampaignClaimerTests.swift` 添加测试：
```swift
func testClaimStatusTrackingAndPersistence() async {
    let claimer = QoderCampaignClaimer.shared
    // 验证状态持久化与单号结果查询
    let status = claimer.claimStatusText(for: "test-user-id")
    XCTAssertFalse(status.isEmpty)
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`xcodebuild test -scheme NotchDrop -destination 'platform=macOS' -only-testing:NotchDropTests/QoderCampaignClaimerTests | xcbeautify || true`
预期：FAIL，`claimStatusText` 未定义

- [ ] **步骤 3：实现签到状态记录与 UI 接入**

1. `NotchDrop/QoderCampaignClaimer.swift`：
   - 增加按天隔离的签到状态缓存：
     ```swift
     @MainActor @Published private(set) var dailyOutcomes: [String: QoderClaimOutcome] = [:]
     ```
   - 提供 `statusDescription(for userId: String) -> String`
   - 在 `claimAll()` 完成时记录到 `dailyOutcomes` 并持久化到 `UserDefaults`。
2. `NotchDrop/GatewayZoneView.swift`：
   - 在 `metricsFooter` 增加一键签到按钮和状态统计：
     ```swift
     HStack(spacing: 8) {
         Text("今日签到: \(claimedCount)/\(totalAccounts)")
             .font(.system(size: 10.5))
             .foregroundStyle(Color.white.opacity(0.45))
         Spacer()
         Button("一键签到") {
             Task {
                 _ = await QoderCampaignClaimer.shared.claimAll()
                 await store.refreshPoolQuotas()
             }
         }
         .buttonStyle(.plain)
         .font(.system(size: 10.5, weight: .medium))
         .foregroundStyle(StudioColor.emerald)
     }
     ```
3. `NotchDrop/QoderPoolRingView.swift`：
   - 在 `tooltip` 函数中追加单号签到状态：
     ```swift
     let claimStatus = QoderCampaignClaimer.shared.statusDescription(for: m.userId)
     s += "\n今日签到: \(claimStatus)"
     ```

- [ ] **步骤 4：运行测试确认通过**

运行：`xcodebuild test -scheme NotchDrop -destination 'platform=macOS' -only-testing:NotchDropTests/QoderCampaignClaimerTests | xcbeautify`
预期：PASS

- [ ] **步骤 5：Commit**

```bash
git add NotchDrop/QoderCampaignClaimer.swift NotchDrop/QoderStore.swift NotchDrop/GatewayZoneView.swift NotchDrop/QoderPoolRingView.swift Tests/QoderCampaignClaimerTests.swift
git commit -m "feat(qoder): 支持 credits 每日一键签到与各账号签到状态展示

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### 任务 4：DeepSeek 模型 credits 耗尽自动换号

**文件：**
- 修改：`Vendor/qodercn-gateway/internal/remote/credential_pool.go`
- 修改：`Vendor/qodercn-gateway/internal/remote/credential_pool_test.go`
- 修改：`Vendor/qodercn-gateway/internal/remote/client.go`
- 构建脚本：`./scripts/build_gateway.sh`

- [ ] **步骤 1：编写 credits 耗尽触发换号与冷却的 Go 单元测试**

在 `Vendor/qodercn-gateway/internal/remote/credential_pool_test.go` 中添加测试：
```go
func TestInspect_CreditsExhaustedTriggersSwitchAndCool(t *testing.T) {
    pool := NewCredentialPool(t.TempDir())
    // 注入模拟账号 user_ds
    // Inspect 遇到 credits 错误返回 VerdictSwitch 且将账号 cool
    body := []byte(`{"error":"insufficient credits for model deepseek"}`)
    verdict := pool.Inspect("user_ds", 403, body)
    if verdict != VerdictSwitch {
        t.Errorf("got %v, want VerdictSwitch", verdict)
    }
}
```

- [ ] **步骤 2：运行 Go 测试验证失败**

运行：`cd Vendor/qodercn-gateway && go test -v ./internal/remote/... -run TestInspect_CreditsExhausted`
预期：FAIL，未识别 credits 相关关键词

- [ ] **步骤 3：实现 credits 耗尽关键词识别与选号过滤**

1. `Vendor/qodercn-gateway/internal/remote/credential_pool.go`：
   - 扩充 401/403 的 quota 错误识别逻辑，包含 `credit`, `point`, `点数不足`, `余额不足`, `insufficient` 等。
   - 当捕获到额度耗尽时，冷却该账号（标记 `CoolReason = "credits_exhausted"`，冷却至当天午夜），清空 `p.stickyUser`，返回 `VerdictSwitch`。
   - `Pick(attempt int, inFlightExcluded map[string]bool)` 在挑选账号时，如果账号因 `credits_exhausted` 处于冷却，则跳过。
2. 重新编译本地网关：
   - 运行 `./scripts/build_gateway.sh` 生成新二进制并更新到 App Resources 目录。

- [ ] **步骤 4：运行 Go 测试确认通过**

运行：`cd Vendor/qodercn-gateway && go test -v ./internal/remote/...`
预期：全部 PASS

- [ ] **步骤 5：Commit**

```bash
git add Vendor/qodercn-gateway/ NotchDrop/Resources/
git commit -m "feat(gateway): 支持 DeepSeek 模型 credits 耗尽时自动冷却并切换账号

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### 任务 5：全量测试、构建部署与真机验收

**文件：**
- 产物部署：`/Applications/NotchEvery.app`

- [ ] **步骤 1：运行 Swift 端全部单测**

运行：`xcodebuild test -scheme NotchDrop -destination 'platform=macOS' | xcbeautify`
预期：全部通过（216+ tests / 0 failures）

- [ ] **步骤 2：Release 编译应用并部署**

运行：`./scripts/build_and_deploy.sh` 或 standard Release build
验证：
1. 签名有效
2. 二进制部署至 `/Applications/NotchEvery.app`
3. 重启应用

- [ ] **步骤 3：用户真机过目验收**

检查项：
1. 第一页底部三个分页小圆点是否完整露出；
2. 第三页右上角是否展示刷新按钮，点击后是否能成功刷新额度；
3. 第三页反代卡片底部是否显示「今日签到」与「一键签到」按钮，Tooltip 是否包含签到状态；
4. DeepSeek 模型额度耗尽时自动流转下一个账号。
