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

    private func makeStore() -> GuardStore {
        GuardStore(manager: manager, config: config, logger: logger)
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
}
