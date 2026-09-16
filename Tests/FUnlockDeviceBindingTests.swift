//
//  FUnlockDeviceBindingTests.swift
//  NotchEvery
//
//  验证设备绑定与解绑接口、持久化与门面透出
//

import XCTest
@testable import NotchEvery

@MainActor
final class FUnlockDeviceBindingTests: XCTestCase {
    private var manager: FUnManager!
    private var logger: DecisionLogger!
    private var config: ConfigStore!
    private var configName: String!
    private var logDir: URL!

    override func setUp() {
        super.setUp()
        configName = "DeviceBindingTests-\(UUID().uuidString)"
        config = ConfigStore(suiteName: configName)
        logDir = FileManager.default.temporaryDirectory.appendingPathComponent("DeviceBindingTests-\(UUID().uuidString)")
        logger = DecisionLogger(testLogDirectory: logDir)
        manager = FUnManager(fun: FUn(), nowProvider: { Date() }, decisionLogger: logger, config: config)
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
        let stub = PermissionGuide(isAXTrusted: { true },
                                   isBluetoothAuthorized: { true },
                                   hasFullDiskAccess: { true })
        return GuardStore(manager: manager, config: config, logger: logger, guide: stub)
    }

    func testBindDeviceUpdatesManagerAndStorage() {
        let testUUID = UUID()
        let testName = "Test Apple Watch Ultra"

        manager.bindDevice(uuid: testUUID, name: testName)

        XCTAssertEqual(manager.monitoredDeviceName, testName)
        XCTAssertEqual(config.string(forKey: "device"), testUUID.uuidString)
        XCTAssertEqual(config.string(forKey: "deviceName"), testName)
    }

    func testUnbindDeviceClearsStateAndStorage() {
        let testUUID = UUID()
        let testName = "Test iPhone"

        manager.bindDevice(uuid: testUUID, name: testName)
        XCTAssertEqual(manager.monitoredDeviceName, testName)

        manager.unbindDevice()

        XCTAssertNil(manager.monitoredDeviceName)
        XCTAssertNil(manager.rssi)
        XCTAssertFalse(manager.connected)
        XCTAssertNil(config.string(forKey: "device"))
        XCTAssertNil(config.string(forKey: "deviceName"))
    }

    func testGuardStoreFacadeDeviceBinding() {
        let store = makeStore()
        let testUUID = UUID()
        let testName = "Office Watch"

        store.bindDevice(uuid: testUUID, name: testName)
        XCTAssertEqual(store.deviceName, testName)
        XCTAssertEqual(config.string(forKey: "device"), testUUID.uuidString)
        XCTAssertEqual(config.string(forKey: "deviceName"), testName)

        store.unbindDevice()
        XCTAssertNil(store.deviceName)
        XCTAssertNil(config.string(forKey: "device"))
        XCTAssertNil(config.string(forKey: "deviceName"))
    }
}
