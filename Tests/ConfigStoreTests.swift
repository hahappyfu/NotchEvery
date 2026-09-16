// FUnlockTests/ConfigStoreTests.swift
import XCTest
@testable import NotchEvery

final class ConfigStoreTests: XCTestCase {
    private var store: ConfigStore!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ConfigStoreTests-\(UUID().uuidString)"
        store = ConfigStore(suiteName: suiteName)
    }

    override func tearDown() {
        // 清理当前 suite 域的持久化文件（removePersistentDomain 按域名生效，与实例无关）
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        store = nil
        suiteName = nil
        super.tearDown()
    }

    /// 迁移：standard 有旧值 → 搬到 suite（用独立测试 key，不碰真实生产 key）
    func testMigrateMovesLegacyValues() {
        // 准备旧值：备份 standard 原值，结束后恢复，避免破坏真实配置
        let legacyKey = "testMigrateMovesLegacyValues_key"
        let original = UserDefaults.standard.object(forKey: legacyKey)
        UserDefaults.standard.set("legacy", forKey: legacyKey)
        defer { restore(original, forKey: legacyKey) }

        store.migrateIfNeeded(fromKeys: [legacyKey])

        XCTAssertEqual(store.defaults.string(forKey: legacyKey), "legacy",
                       "迁移后 suite 应包含旧值")
    }

    /// 幂等：第二次 migrateIfNeeded 不再覆盖
    func testMigrateIsIdempotent() {
        let legacyKey = "testMigrateIsIdempotent_key"
        let original = UserDefaults.standard.object(forKey: legacyKey)
        UserDefaults.standard.set("v1", forKey: legacyKey)
        defer { restore(original, forKey: legacyKey) }

        store.migrateIfNeeded(fromKeys: [legacyKey])
        store.defaults.set("v2", forKey: legacyKey) // 用户在 suite 中改了值
        store.migrateIfNeeded(fromKeys: [legacyKey])

        XCTAssertEqual(store.defaults.string(forKey: legacyKey), "v2",
                       "已迁移后再次调用不应覆盖 suite 中用户新值")
    }

    /// 把 standard 中某 key 恢复为原值（nil 表示原本不存在 → 删除）
    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// 读写
    func testSetGet() {
        store.set(42, forKey: "intKey")
        XCTAssertEqual(store.get("intKey", fallback: 0), 42)
        store.set("hello", forKey: "strKey")
        XCTAssertEqual(store.get("strKey", fallback: ""), "hello")
    }

    /// JSON 后端读写与独立文件持久化测试
    func testJSONBackendReadWriteAndPersistence() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let testConfigFile = tempDir.appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ConfigStore(configFile: testConfigFile)
        store.set("Apple Watch Series 7", forKey: "deviceName")
        store.set(-65, forKey: "lockRSSI")
        store.set(true, forKey: "wakeOnProximity")

        XCTAssertEqual(store.string(forKey: "deviceName"), "Apple Watch Series 7")
        XCTAssertEqual(store.get("lockRSSI", fallback: 0), -65)
        XCTAssertTrue(store.bool(forKey: "wakeOnProximity"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: testConfigFile.path))

        // 重新构造，验证从磁盘文件重新加载
        let store2 = ConfigStore(configFile: testConfigFile)
        XCTAssertEqual(store2.string(forKey: "deviceName"), "Apple Watch Series 7")
        XCTAssertEqual(store2.get("lockRSSI", fallback: 0), -65)
        XCTAssertTrue(store2.bool(forKey: "wakeOnProximity"))

        // 测试删除键
        store2.removeObject(forKey: "deviceName")
        XCTAssertNil(store2.string(forKey: "deviceName"))
        XCTAssertNil(store2.object(forKey: "deviceName"))

        let store3 = ConfigStore(configFile: testConfigFile)
        XCTAssertNil(store3.string(forKey: "deviceName"))
    }

    /// 测试损坏 JSON 的容错恢复机制
    func testJSONCorruptionRecovery() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let testConfigFile = tempDir.appendingPathComponent("config.json")
        let testSuiteName = "CorruptionTest-\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            UserDefaults.standard.removePersistentDomain(forName: testSuiteName)
        }

        // 写入非法 JSON
        try "INVALID JSON {{{".write(to: testConfigFile, atomically: true, encoding: .utf8)

        let store = ConfigStore(configFile: testConfigFile, suiteName: testSuiteName)
        XCTAssertEqual(store.get("corruptTestRSSI", fallback: -70), -70)

        // 写入新值应恢复正常文件
        store.set("Recovered Watch", forKey: "deviceName")
        XCTAssertEqual(store.string(forKey: "deviceName"), "Recovered Watch")

        let store2 = ConfigStore(configFile: testConfigFile, suiteName: testSuiteName)
        XCTAssertEqual(store2.string(forKey: "deviceName"), "Recovered Watch")
    }
    /// 多线程并发读写安全测试
    func testThreadSafeConcurrentAccess() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let testConfigFile = tempDir.appendingPathComponent("concurrent_config.json")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ConfigStore(configFile: testConfigFile)
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "test.concurrent.queue", attributes: .concurrent)

        for i in 0..<100 {
            group.enter()
            queue.async {
                store.set(i, forKey: "key_\(i)")
                _ = store.get("key_\(i)", fallback: -1)
                group.leave()
            }
        }
        group.wait()
        XCTAssertEqual(store.get("key_50", fallback: -1), 50)
    }

    // MARK: - 旧域 → 新域迁移（工单 02）

    /// 造一对隔离的新/旧 suite 名（随机域名，互不干扰、不碰生产 key）
    private func makeLegacyPair(_ tag: String) -> (target: ConfigStore, targetName: String, legacyName: String) {
        let targetName = "MigrateNewTests-\(tag)-\(UUID().uuidString)"
        let legacyName = "MigrateLegacyTests-\(tag)-\(UUID().uuidString)"
        return (ConfigStore(suiteName: targetName), targetName, legacyName)
    }

    private func legacyStore(_ name: String) -> ConfigStore {
        ConfigStore(suiteName: name)
    }

    private func dropSuites(_ names: String...) {
        for n in names { UserDefaults.standard.removePersistentDomain(forName: n) }
    }

    /// 首次迁移：旧域有值 → 新域得到值，并落迁移标记
    func testLegacyMigrateFirstRun() {
        let (target, tName, lName) = makeLegacyPair("first")
        defer { dropSuites(tName, lName) }
        let k = "testLegacyMigrateFirstRun_key"
        legacyStore(lName).set("v1", forKey: k)

        target.migrateFromLegacyIfNeeded(keys: [k], fromLegacySuite: lName)

        XCTAssertEqual(target.defaults.string(forKey: k), "v1", "首次迁移应把旧值带过来")
        XCTAssertTrue(target.defaults.bool(forKey: "didMigrateFromLegacy"), "迁移后应落标记")
    }

    /// 重复执行：第二次不覆盖新域中用户改过的值
    func testLegacyMigrateIsIdempotent() {
        let (target, tName, lName) = makeLegacyPair("idem")
        defer { dropSuites(tName, lName) }
        let k = "testLegacyMigrateIsIdempotent_key"
        legacyStore(lName).set("v1", forKey: k)

        target.migrateFromLegacyIfNeeded(keys: [k], fromLegacySuite: lName)
        target.defaults.set("v2", forKey: k) // 用户在新域改了值
        target.migrateFromLegacyIfNeeded(keys: [k], fromLegacySuite: lName)

        XCTAssertEqual(target.defaults.string(forKey: k), "v2", "重复迁移不应覆盖新域用户新值")
    }

    /// 旧域不存在：不崩溃，照写迁移标记（避免每次启动都空跑）
    func testLegacyMigrateMissingLegacySuite() {
        let (target, tName, lName) = makeLegacyPair("missing")
        defer { dropSuites(tName, lName) }

        target.migrateFromLegacyIfNeeded(keys: ["testLegacyMigrateMissing_key"], fromLegacySuite: lName)

        XCTAssertTrue(target.defaults.bool(forKey: "didMigrateFromLegacy"), "旧域缺失也应落标记")
    }

    /// 旧域有值但新域已有值：保留新域的（迁移只填空，不覆盖）
    func testLegacyMigrateKeepsExistingNewValues() {
        let (target, tName, lName) = makeLegacyPair("keep")
        defer { dropSuites(tName, lName) }
        let k = "testLegacyMigrateKeeps_key"
        target.defaults.set("mine", forKey: k)
        legacyStore(lName).set("theirs", forKey: k)

        target.migrateFromLegacyIfNeeded(keys: [k], fromLegacySuite: lName)

        XCTAssertEqual(target.defaults.string(forKey: k), "mine", "新域已有值时应保留")
    }
}