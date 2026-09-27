// FUnlockTests/ConfigStoreTests.swift
import XCTest
@testable import NotchEvery

final class ConfigStoreTests: XCTestCase {
    private var store: ConfigStore!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ConfigStoreTests-\(UUID().uuidString)"
        store = ConfigStore(configFile: nil, suiteName: suiteName)
    }

    override func tearDown() {
        // 清理当前 suite 域的持久化文件（removePersistentDomain 按域名生效，与实例无关）
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        store = nil
        suiteName = nil
        super.tearDown()
    }

    /// 读写
    func testSetGet() {
        store.set(42, forKey: "intKey")
        XCTAssertEqual(store.get("intKey", fallback: 0), 42)
    }

    /// JSON 后端读写与独立文件持久化测试
    func testJSONBackendReadWriteAndPersistence() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let testConfigFile = tempDir.appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ConfigStore(configFile: testConfigFile)
        store.set(-65, forKey: "lockRSSI")
        XCTAssertEqual(store.get("lockRSSI", fallback: 0), -65)
        XCTAssertTrue(FileManager.default.fileExists(atPath: testConfigFile.path))

        // 重新构造，验证从磁盘文件重新加载
        let store2 = ConfigStore(configFile: testConfigFile)
        XCTAssertEqual(store2.get("lockRSSI", fallback: 0), -65)
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
        store.set(-63, forKey: "corruptTestRSSI")
        XCTAssertEqual(store.get("corruptTestRSSI", fallback: -70), -63)

        let store2 = ConfigStore(configFile: testConfigFile, suiteName: testSuiteName)
        XCTAssertEqual(store2.get("corruptTestRSSI", fallback: -70), -63)
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
        return (ConfigStore(configFile: nil, suiteName: targetName), targetName, legacyName)
    }

    private func dropSuites(_ names: String...) {
        for n in names { UserDefaults.standard.removePersistentDomain(forName: n) }
    }

    /// 首次迁移：旧域有值 → 新域得到值，并落迁移标记
    func testLegacyMigrateFirstRun() {
        let (target, tName, lName) = makeLegacyPair("first")
        defer { dropSuites(tName, lName) }
        let k = "testLegacyMigrateFirstRun_key"
        UserDefaults(suiteName: lName)!.set("v1", forKey: k)

        target.migrateFromLegacyIfNeeded(keys: [k], fromLegacySuite: lName)

        XCTAssertEqual(target.defaults.string(forKey: k), "v1", "首次迁移应把旧值带过来")
        XCTAssertTrue(target.defaults.bool(forKey: "didMigrateFromLegacy"), "迁移后应落标记")
    }

    /// 重复执行：第二次不覆盖新域中用户改过的值
    func testLegacyMigrateIsIdempotent() {
        let (target, tName, lName) = makeLegacyPair("idem")
        defer { dropSuites(tName, lName) }
        let k = "testLegacyMigrateIsIdempotent_key"
        UserDefaults(suiteName: lName)!.set("v1", forKey: k)

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
        UserDefaults(suiteName: lName)!.set("theirs", forKey: k)

        target.migrateFromLegacyIfNeeded(keys: [k], fromLegacySuite: lName)

        XCTAssertEqual(target.defaults.string(forKey: k), "mine", "新域已有值时应保留")
    }

    /// 验证：当 config.json 在磁盘尚不存在时，自动读取现存 UserDefaults suite 数据并生成 config.json
    func testMigrateFromUserDefaultsToJSONFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let testConfigFile = tempDir.appendingPathComponent("config.json")
        let testSuite = "test.migration.\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            UserDefaults.standard.removePersistentDomain(forName: testSuite)
        }

        let fakeLegacy = UserDefaults(suiteName: testSuite)!
        fakeLegacy.set("-62", forKey: "lockRSSI")
        fakeLegacy.set(true, forKey: "iMessageNotify")
        fakeLegacy.synchronize()

        XCTAssertFalse(FileManager.default.fileExists(atPath: testConfigFile.path))

        let store = ConfigStore(configFile: testConfigFile, suiteName: testSuite)

        XCTAssertTrue(FileManager.default.fileExists(atPath: testConfigFile.path), "初始化后应立即自动生成 config.json")
        XCTAssertEqual(store.get("lockRSSI", fallback: -99), -62)
        XCTAssertEqual(store.get("iMessageNotify", fallback: false), true)
    }
}
