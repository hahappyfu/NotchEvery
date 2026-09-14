// GuardStoreTests.swift（工单 03 新建）
// 守护门面的状态映射测试：只断言对外可见的映射行为（状态/设备/信号/阈值/判定/蓝牙问题），
// 不碰 BLE、不扫描。manager 与 logger 均注入可控实例。

import XCTest
@testable import NotchEvery

@MainActor
final class GuardStoreTests: XCTestCase {
    private var manager: FUnManager!
    private var logger: DecisionLogger!
    private var config: ConfigStore!
    private var configName: String!
    private var logDir: URL!

    override func setUp() {
        super.setUp()
        configName = "GuardStoreTests-\(UUID().uuidString)"
        config = ConfigStore(suiteName: configName)
        logDir = FileManager.default.temporaryDirectory.appendingPathComponent("GuardStoreTests-\(UUID().uuidString)")
        logger = DecisionLogger(testLogDirectory: logDir)
        manager = FUnManager(fun: FUn(), nowProvider: { Date() }, decisionLogger: logger)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: configName)
        try? FileManager.default.removeItem(at: logDir)
        manager = nil
        logger = nil
        config = nil
        super.tearDown()
    }

    private func makeStore(guide: PermissionGuide? = nil) -> GuardStore {
        // 默认 stub 全授权（确定性；live 检查由 PermissionGuideTests 覆盖）
        let stub = PermissionGuide(isAXTrusted: { true },
                                   isBluetoothAuthorized: { true },
                                   hasFullDiskAccess: { true })
        return GuardStore(manager: manager, config: config, logger: logger, guide: guide ?? stub)
    }

    /// 初始态：开关默认开 + 空跑默认开 → 空跑观察
    func testInitialStateIsObserving() {
        let store = makeStore()
        XCTAssertEqual(store.guardState, .observing)
        XCTAssertTrue(store.isDryRun, "03 空跑门默认开启")
    }

    /// 总开关关闭 → 停用（且开关缺键时按启用处理，不静默拦截）
    func testDisabledWhenEnabledFalse() {
        config.set(false, forKey: "enabled")
        XCTAssertEqual(makeStore().guardState, .disabled)
    }

    func testEnabledDefaultsTrueWhenKeyMissing() {
        XCTAssertTrue(makeStore().enabled, "enabled 缺键按启用处理")
    }

    /// 空跑关闭 → 守护中（该映射为 09 的接管开关准备，03 恒为 observing）
    func testGuardingWhenDryRunOff() {
        let store = makeStore()
        manager.isDryRun = false
        XCTAssertEqual(store.guardState, .guarding)
    }

    /// 无绑定设备 → 设备名 nil（卡片显示占位，不崩）
    func testDeviceNameNilByDefault() {
        XCTAssertNil(makeStore().deviceName)
    }

    /// 设备名透出
    func testDeviceNameMirrorsManager() {
        manager.monitoredDeviceName = "Apple Watch Series 7"
        XCTAssertEqual(makeStore().deviceName, "Apple Watch Series 7")
    }

    /// 阈值透出管理器当前值
    func testThresholdsMirrorManager() {
        manager.lockRSSI = -70
        manager.unlockRSSI = -60
        let store = makeStore()
        XCTAssertEqual(store.lockRSSI, -70)
        XCTAssertEqual(store.unlockRSSI, -60)
    }

    /// 信号透出（含无信号）
    func testRssiMirrorsManager() {
        XCTAssertNil(makeStore().rssi)
        manager.rssi = -58
        XCTAssertEqual(makeStore().rssi, -58)
    }

    /// 蓝牙问题透出
    func testBluetoothIssueMapping() {
        let store = makeStore()
        XCTAssertNil(store.bluetoothIssue)
        manager.bluetoothIssue = .unauthorized
        XCTAssertEqual(store.bluetoothIssue, .unauthorized)
        manager.bluetoothIssue = .poweredOff
        XCTAssertEqual(store.bluetoothIssue, .poweredOff)
    }

    /// 最近一条判定透出 detail
    func testLastJudgementFromEvents() {
        logger.record(category: .lock, outcome: .success, reason: .lockedAway,
                      rssi: -74, device: "Watch", screen: "unlocked", detail: "空跑：本应锁屏")
        XCTAssertEqual(makeStore().lastJudgement, "空跑：本应锁屏")
    }

    /// 空日志 → 无判定（数据源缺失路径）
    func testEmptyLoggerGivesNilJudgement() {
        XCTAssertNil(makeStore().lastJudgement)
    }

    // MARK: - 真执行开关（工单 05 S2）

    /// 默认关闭：缺键即空跑观察
    func testRealExecutionDefaultsOff() {
        let store = makeStore()
        XCTAssertFalse(store.realExecution, "真执行默认关闭")
        XCTAssertTrue(store.isDryRun)
        XCTAssertEqual(store.guardState, .observing)
    }

    /// 打开 → 守护中；再关 → 回空跑观察（切换立即生效）
    func testRealExecutionFlipReachesGuarding() {
        let store = makeStore()
        store.realExecution = true
        XCTAssertFalse(store.isDryRun)
        XCTAssertEqual(store.guardState, .guarding)
        store.realExecution = false
        XCTAssertTrue(store.isDryRun)
        XCTAssertEqual(store.guardState, .observing)
    }

    /// 选择持久化：同域名新门面读到上次的选择（下次启动照旧）
    func testRealExecutionPersistsAcrossStores() {
        makeStore().realExecution = true
        let freshManager = FUnManager(fun: FUn(), nowProvider: { Date() }, decisionLogger: logger)
        let reopened = GuardStore(manager: freshManager, config: config, logger: logger)
        XCTAssertTrue(reopened.realExecution)
        XCTAssertFalse(reopened.isDryRun)
        XCTAssertEqual(reopened.guardState, .guarding)
    }

    // MARK: - 权限引导（工单 07 S2）

    func testPermissionsEmptyWhenAllGranted() {
        XCTAssertTrue(makeStore().permissionIssues.isEmpty)
    }

    /// 缺 AX 即 surface：标题/跳转齐备
    func testMissingAXSurfaced() {
        let guide = PermissionGuide(isAXTrusted: { false },
                                    isBluetoothAuthorized: { true },
                                    hasFullDiskAccess: { true })
        let issues = makeStore(guide: guide).permissionIssues
        XCTAssertEqual(issues.map { $0.kind }, [.ax])
        XCTAssertNotNil(issues[0].settingsURL)
    }

    /// "知道了"后不再出现，且同域名新门面照旧（迁移不骚扰）
    func testAcknowledgeHidesIssuePersistently() {
        let guide = PermissionGuide(isAXTrusted: { false },
                                    isBluetoothAuthorized: { true },
                                    hasFullDiskAccess: { true })
        let store = makeStore(guide: guide)
        XCTAssertEqual(store.permissionIssues.count, 1)
        store.acknowledgePermission(.ax)
        XCTAssertTrue(store.permissionIssues.isEmpty)
        XCTAssertTrue(makeStore(guide: guide).permissionIssues.isEmpty, "持久化：新门面也不再骚扰")
    }

    /// 蓝牙授权翻转（系统回调）即重检引导行，免重启
    func testBluetoothUnauthorizedSurfacedReactively() {
        let guide = PermissionGuide(isAXTrusted: { true },
                                    isBluetoothAuthorized: { [weak manager = self.manager] in
                                        manager?.bluetoothIssue != .unauthorized
                                    },
                                    hasFullDiskAccess: { true })
        let store = makeStore(guide: guide)
        XCTAssertTrue(store.permissionIssues.isEmpty)
        manager.bluetoothIssue = .unauthorized
        // 订阅投递在 willSet 时机，重检在下一跳主队列：等一拍再断言
        let done = expectation(description: "recheck")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { done.fulfill() }
        wait(for: [done], timeout: 2.0)
        XCTAssertEqual(store.permissionIssues.map { $0.kind }, [.bluetooth])
    }

    /// 修好即清确认：再坏重现骚扰（code-review 跟进：ack 不得永久过滤）
    func testGrantClearsAckSoRepeatOffenseResurfaces() {
        let denied = PermissionGuide(isAXTrusted: { false },
                                     isBluetoothAuthorized: { true },
                                     hasFullDiskAccess: { true })
        let store = makeStore(guide: denied)
        store.acknowledgePermission(.ax)
        XCTAssertTrue(store.permissionIssues.isEmpty)

        let granted = PermissionGuide(isAXTrusted: { true },
                                      isBluetoothAuthorized: { true },
                                      hasFullDiskAccess: { true })
        XCTAssertTrue(makeStore(guide: granted).permissionIssues.isEmpty, "修好即清确认")

        XCTAssertEqual(makeStore(guide: denied).permissionIssues.map { $0.kind },
                       [.ax], "再坏重现骚扰")
    }

    // MARK: - 上次未解锁回显（工单 08 S3）

    /// 无失败 → 无回显（不占行）
    func testNoFailureGivesNilEcho() {
        logger.record(category: .unlock, outcome: .success, reason: .unlockSuccess,
                      rssi: -50, device: "Watch", screen: "unlocked", detail: "")
        XCTAssertNil(makeStore().lastUnlockFailure)
    }

    /// 解锁失败 → 回显 detail；系统类失败（推送）不算未解锁
    func testUnlockFailureEchoesDetail() {
        logger.record(category: .system, outcome: .failed, reason: .iMessageFailed,
                      rssi: nil, device: nil, screen: nil, detail: "Messages 未授权")
        XCTAssertNil(makeStore().lastUnlockFailure, "推送失败不是未解锁")
        logger.record(category: .unlock, outcome: .failed, reason: .unlockFailed,
                      rssi: -60, device: "Watch", screen: "locked", detail: "第 1/3 次尝试")
        XCTAssertEqual(makeStore().lastUnlockFailure, "第 1/3 次尝试")
    }

    /// 之后解锁成功 → 回显清掉，不常驻（code-review 跟进）
    func testSuccessClearsFailureEcho() {
        logger.record(category: .unlock, outcome: .failed, reason: .unlockFailed,
                      rssi: -60, device: "Watch", screen: "locked", detail: "第 1/3 次尝试")
        logger.record(category: .unlock, outcome: .success, reason: .unlockSuccess,
                      rssi: -50, device: "Watch", screen: "unlocked", detail: "")
        XCTAssertNil(makeStore().lastUnlockFailure)
    }

    // MARK: - 密码状态与接管（工单 09）

    /// 初始密码状态透出 checker 闭包返回值
    func testHasPasswordMirrorsChecker() {
        var pwExists = false
        let store = GuardStore(manager: manager, config: config, logger: logger,
                               passwordChecker: { pwExists },
                               passwordPrompter: { pwExists = true; return true })
        XCTAssertFalse(store.hasPassword)
        pwExists = true
        store.checkPassword()
        XCTAssertTrue(store.hasPassword)
    }

    /// setOrChangePassword 调用 prompter 并在成功后更新 hasPassword
    func testSetOrChangePasswordPromptsAndUpdates() {
        var pwExists = false
        let store = GuardStore(manager: manager, config: config, logger: logger,
                               passwordChecker: { pwExists },
                               passwordPrompter: { pwExists = true; return true })
        XCTAssertFalse(store.hasPassword)
        store.setOrChangePassword()
        XCTAssertTrue(store.hasPassword)
    }
}
