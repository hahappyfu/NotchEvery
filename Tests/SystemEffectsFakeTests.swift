// SystemEffectsFakeTests.swift（工单 04 新建）
// 用假副作用实现第一次把执行链跑通并断言：注入成功 / 双验证失败 /
// 连续失败触发告警 / 降级路径。只断言外部可观察结局
// （是否请求锁屏、注入被请求次数、失败计数归零、告警次数、状态机状态、决策记录），
// 不断言内部调用顺序。
//
// 两条安全绳（必读）：
// 1. iMessageNotifier.shared 不在接缝内——测试全程把真配置的 iMessageNotify 设 false
//   （沿用既有用例改真配置的模式，tearDown 恢复原值），否则会真发 iMessage。
// 2. Keychain 不在接缝内——取密码走假实现（SystemEffects 含 fetchPassword 正是为此），
//    全程不碰真钥匙串、不弹框。

import XCTest
@testable import NotchEvery

/// 记录调用、不执行的假副作用实现。
final class FakeSystemEffects: SystemEffects {
    var lockRequests = 0
    var notifyReasons: [String] = []
    var injectRequests = 0
    var injectedPasswords: [String] = []
    var injectResult = true
    var verifyResult = SystemInteractionService.UnlockNotification(unlock: true)
    var screenLocked = true
    var secureToInject = true
    var passwordResult: Result<String?, KeychainError> = .success("test-password")
    var abnormalAlerts = 0
    var mismatchAlerts = 0
    var clearedNotifications = 0
    var wakeRequests = 0
    var wakeReleases = 0
    var onInject: (() -> Void)?

    func isScreenLocked(screenState: ScreenState?) -> Bool { screenLocked }
    func isSecureToInject(screenState: ScreenState?) -> Bool { secureToInject }
    func verifyUnlock(timeout: TimeInterval, notificationTimeout: TimeInterval) async -> SystemInteractionService.UnlockNotification { verifyResult }
    func showPasswordMismatchAlert() { mismatchAlerts += 1 }
    func showAXRevokedAlertIfNeeded(lastAlertTime: inout Date) { lastAlertTime = Date() }
    func notifyLock(reason: String) { notifyReasons.append(reason) }
    func lockOrSaveScreen(useScreensaver: Bool, sleepDisplayAfter: Bool) { lockRequests += 1 }
    func injectPasswordWithPrelude(_ string: String, isSecureCheck: @escaping () -> Bool) -> Bool {
        // 与 live 契约一致：先查再发；检查失败即停且不记录密码
        //（指纹中途解锁即走此路——密码不出、不落盘）。
        guard isSecureCheck() else { return false }
        injectRequests += 1
        injectedPasswords.append(string)
        onInject?()
        return injectResult
    }
    func showAbnormalUnlockAlert(count: Int, window: Int) { abnormalAlerts += 1 }
    func clearLockNotification() { clearedNotifications += 1 }
    func fetchPassword(warn: Bool) -> Result<String?, KeychainError> { passwordResult }
    func wakeDisplay() { wakeRequests += 1 }
    func releaseWakeAssertion() { wakeReleases += 1 }
}

@MainActor
final class SystemEffectsFakeTests: XCTestCase {
    private var manager: FUnManager!
    private var fake: FakeSystemEffects!
    private var logger: DecisionLogger!
    private var logDir: URL!
    private var currentTime: Date!
    private var savedPrefs: [String: Any] = [:]
    private var absentPrefs: Set<String> = []

    override func setUp() {
        super.setUp()
        currentTime = Date(timeIntervalSince1970: 1_700_000_000)
        logDir = FileManager.default.temporaryDirectory.appendingPathComponent("SysFxFakeTests-\(UUID().uuidString)")
        logger = DecisionLogger(testLogDirectory: logDir)
        fake = FakeSystemEffects()
        manager = FUnManager(fun: FUn(), nowProvider: { [unowned self] in self.currentTime },
                             decisionLogger: logger, system: fake)
        manager.isDryRun = false
        manager.fun.unlockRSSI = -60
        manager.fun.lockRSSI = -70
        // 确定性优先：与机器真实配置解耦；缺键按启用处理，因此只固定四处
        for key in ["enabled", "iMessageNotify", "wakeWithoutUnlocking", "wakeOnProximity"] {
            if let v = ConfigStore.shared.defaults.object(forKey: key) {
                savedPrefs[key] = v
            } else {
                absentPrefs.insert(key)
            }
        }
        ConfigStore.shared.defaults.set(true, forKey: "enabled")
        ConfigStore.shared.defaults.set(false, forKey: "iMessageNotify")
        ConfigStore.shared.defaults.set(false, forKey: "wakeWithoutUnlocking")
        ConfigStore.shared.defaults.set(false, forKey: "wakeOnProximity")
    }

    override func tearDown() {
        for (key, value) in savedPrefs {
            ConfigStore.shared.defaults.set(value, forKey: key)
        }
        for key in absentPrefs {
            ConfigStore.shared.defaults.removeObject(forKey: key)
        }
        try? FileManager.default.removeItem(at: logDir)
        super.tearDown()
    }

    /// 驱动一次完整解锁尝试（含 0.8s 并行任务），等待注入发生后再留出验证与记账时间。
    /// 从锁屏态起步（与真机一致）：先离开锁屏（screen → .displaySleeping），再靠近——
    /// 注入检查闭包依赖 state.screen != .unlocked，从 .unlocked 起步永远到不了注入。
    private func driveUnlockAttempt(injectTimeout: TimeInterval = 6.0) {
        withWakeOnProximity(true)
        manager.onDeviceLeft(reason: "away")
        advance(1) // 跳过 0.8s 锁缓冲
        manager.fun.presence = true
        manager.fun.effectiveRSSI = -45.0
        let exp = expectation(description: "inject requested")
        fake.onInject = { exp.fulfill() }
        manager.attemptAutoUnlock()
        wait(for: [exp], timeout: injectTimeout)
        // 注入后的双验证与记账是 CPU 级联续（假实现瞬时返回），留 0.5s 足够
        let done = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 2.0)
        fake.onInject = nil
    }

    private func advance(_ seconds: TimeInterval) {
        currentTime = currentTime.addingTimeInterval(seconds)
    }

    /// 无注入可等的纯等待（唤醒循环是时间驱动）：与 driveUnlockAttempt 同一写法。
    private func settle(_ seconds: TimeInterval) {
        let done = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 2.0)
    }

    private func hasEvent(outcome: DecisionOutcome, reason: DecisionReason) -> Bool {
        logger.events.contains { $0.outcome == outcome && $0.reason == reason }
    }

    // MARK: - 锁屏请求

    func testLockRequestsLockScreen() {
        manager.onDeviceLeft(reason: "away")

        XCTAssertEqual(fake.lockRequests, 1, "离开应请求锁屏一次")
        XCTAssertEqual(fake.notifyReasons, ["away"])
        XCTAssertTrue(hasEvent(outcome: .success, reason: .lockedAway), "应记录锁定决策")
        XCTAssertEqual(manager.state.screen, .displaySleeping)
        XCTAssertEqual(fake.mismatchAlerts, 0, "锁屏不应触发密码告警")
    }

    /// 忘带设备（无信号）：第二次离开因屏已非 unlocked 被拦下，只锁一次、不反复锁屏。
    func testNoRepeatedLockWithoutSignal() {
        manager.isDryRun = false
        manager.onDeviceLeft(reason: "lost")
        manager.onDeviceLeft(reason: "lost")

        XCTAssertEqual(fake.lockRequests, 1, "只锁一次")
        XCTAssertEqual(fake.notifyReasons, ["lost"])
    }

    // MARK: - 抑制路径（工单 05 S4：code-review 跟进）

    /// 手动锁屏后不自动解锁（须手动解锁才重置），且留下可诊断的抑制记录。
    func testManualLockSuppressesAutoUnlock() {
        fake.screenLocked = false // lockNow 只在未锁屏时接受手动锁定
        manager.isDryRun = false
        manager.lockNow()
        advance(1) // 跳过 lockNow 自带的 0.8s 锁缓冲，走到手动锁屏抑制门
        manager.fun.presence = true
        manager.fun.effectiveRSSI = -45.0
        manager.attemptAutoUnlock()
        settle(1.0)

        XCTAssertEqual(fake.injectRequests, 0, "手动锁屏后不自动解锁")
        XCTAssertTrue(
            logger.events.contains { $0.reason == .manualLockActive },
            "抑制必须留下记录，不静默")
    }

    /// 成功解锁紧接着再试：冷却期内不重复注入，且成功只记一次。
    func testUnlockCooldownSuppressesImmediateRetry() {
        driveUnlockAttempt()
        XCTAssertEqual(fake.injectRequests, 1)

        manager.fun.presence = true
        manager.fun.effectiveRSSI = -45.0
        manager.attemptAutoUnlock()
        settle(1.0)

        XCTAssertEqual(fake.injectRequests, 1, "冷却期内不重复注入")
        XCTAssertEqual(
            logger.events.filter { $0.outcome == .success && $0.reason == .unlockSuccess }.count,
            1, "成功只记一次")
    }

    // MARK: - 注入成功

    func testInjectSuccessPath() {
        fake.verifyResult = SystemInteractionService.UnlockNotification(unlock: true)

        driveUnlockAttempt()

        XCTAssertEqual(fake.injectRequests, 1, "应请求注入一次，且密码来自假实现")
        XCTAssertEqual(fake.injectedPasswords, ["test-password"])
        XCTAssertTrue(hasEvent(outcome: .success, reason: .unlockSuccess), "应记录解锁成功")
        XCTAssertEqual(fake.mismatchAlerts, 0)
        XCTAssertEqual(fake.abnormalAlerts, 0)
        XCTAssertEqual(manager.stateMachine.currentState, .active)
    }

    // MARK: - 双验证失败

    func testDualVerifyFailurePath() {
        fake.verifyResult = SystemInteractionService.UnlockNotification(unlock: false)

        driveUnlockAttempt()

        XCTAssertEqual(fake.injectRequests, 1, "注入照常请求（失败发生在验证阶段）")
        XCTAssertTrue(hasEvent(outcome: .failed, reason: .unlockFailed), "应记录解锁失败")
        XCTAssertEqual(fake.mismatchAlerts, 0, "单次失败不应触发密码告警")
    }

    // MARK: - 连续失败触发告警 + 降级

    /// 驱动 N 次完整失败（每次推进时钟跳过各类冷却），返回实际注入次数。
    @discardableResult
    private func driveFailures(_ n: Int) -> Int {
        fake.verifyResult = SystemInteractionService.UnlockNotification(unlock: false)
        for _ in 0..<n {
            advance(15) // 跳过失败冷却 10s / 解锁冷却 5s / 锁缓冲 0.8s
            driveUnlockAttempt()
        }
        return fake.injectRequests
    }

    func testConsecutiveFailuresTriggerMismatchAlert() {
        driveFailures(3)

        XCTAssertEqual(fake.injectRequests, 3, "3 次尝试都应走到注入")
        XCTAssertEqual(fake.mismatchAlerts, 1, "连续 3 次失败应触发一次密码告警")
        // 注意：DecisionLogger 会把同因连续失败合并为一条（防刷屏，见其同因合并逻辑），
        // 因此此处不断言 3 条，只要求失败被记录下来；合并行为由 DecisionLoggerTests 覆盖。
        XCTAssertGreaterThanOrEqual(
            logger.events.filter { $0.outcome == .failed && $0.reason == .unlockFailed }.count,
            1, "失败应被记录")
    }

    func testRepeatedFailuresDriveDegraded() {
        driveFailures(3)

        XCTAssertEqual(manager.stateMachine.currentState, .degraded, "连续失败应进入降级")
    }

    // MARK: - 指纹中断（工单 05 S3）

    /// 指纹在注入前解开屏幕（已不再适合注入）→ 密码不出、不记成功。
    /// 不等注入（永远等不到）：0.3s/0.8s 任务跑完后直接断言。
    func testFingerprintUnlockStopsInjection() {
        fake.secureToInject = false // 模拟指纹已解开：继续注入即泄漏到前台应用
        manager.fun.presence = true
        manager.fun.effectiveRSSI = -45.0
        manager.attemptAutoUnlock()
        settle(1.5)

        XCTAssertTrue(fake.injectedPasswords.isEmpty, "密码不得外发")
        XCTAssertFalse(hasEvent(outcome: .success, reason: .unlockSuccess), "不得记成功")
    }

    // MARK: - 唤醒收编（工单 05 S1）

    /// 真执行 + 显示器休眠 + 系统醒着 + 允许接近唤醒 → 唤醒被请求且 assertion 被释放。
    /// 只断言外部可观察结局（请求计数、释放计数、唤醒相位），不断言重试轮次。
    func testWakeRequestedAndReleasedInRealMode() {
        withWakeOnProximity(true)
        fake.screenLocked = false // 假装唤醒即见解锁：首轮检查即成功，不空转 10 轮
        manager.isDryRun = false
        manager.onDeviceLeft(reason: "away") // screen → .displaySleeping
        advance(2) // 跳过 0.8s 锁缓冲
        manager.fun.presence = true
        manager.fun.effectiveRSSI = -45.0
        manager.attemptAutoUnlock()
        settle(2.0)

        XCTAssertGreaterThanOrEqual(fake.wakeRequests, 1, "真执行应请求唤醒")
        XCTAssertEqual(manager.state.wake, .succeeded, "假装已解锁应一次成功")
        XCTAssertGreaterThanOrEqual(fake.wakeReleases, 1, "defer 应释放 assertion")
    }

    /// 空跑仍不实际唤醒（03 既有语义），但状态流转照常（wake → .pending）。
    func testDryRunSkipsWake() {
        withWakeOnProximity(true)
        fake.screenLocked = false
        manager.isDryRun = true
        manager.onDeviceLeft(reason: "away")
        advance(2)
        manager.fun.presence = true
        manager.fun.effectiveRSSI = -45.0
        manager.attemptAutoUnlock()
        settle(1.5)

        XCTAssertEqual(fake.wakeRequests, 0, "空跑不应实际唤醒")
        XCTAssertEqual(manager.state.wake, .pending, "状态流转照常进行")
    }

    /// wakeOnProximity 非既有用例依赖项：setUp 固定 false 并负责恢复，此处仅按需打开。
    private func withWakeOnProximity(_ value: Bool) {
        ConfigStore.shared.defaults.set(value, forKey: "wakeOnProximity")
    }
}
