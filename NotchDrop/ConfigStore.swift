// FUnlock/ConfigStore.swift
import Foundation
import os.log

/// 配置存储：独立 JSON 存储引擎，统一落盘至 ~/.notchevery/config.json。
/// 覆盖安装 app 后配置不丢失（文件独立于 bundle 且与 UserDefaults 解耦）。
/// 内部采用 NSLock 保护内存缓存，写操作执行原子落盘，并提供完整透明兼容接口。
final class ConfigStore {
    static let shared = ConfigStore()

    /// 现行 suite 域名（保留用于向后兼容迁移）。
    /// 由 FUnlock 时代的 `com.fuhahah.Funlock.config` 搬家而来（工单 02，见 .scratch/funlock-merge/）。
    static let suiteName = "com.hahappyfu.NotchEvery.guard"
    /// 旧域名：只在一次性迁移时读取，迁移后不再碰。
    static let legacySuiteName = "com.fuhahah.Funlock.config"
    private static let didMigrateKey = "didMigrate"
    private static let didMigrateFromLegacyKey = "didMigrateFromLegacy"

    /// 实际被代码读取、需要从旧域带过来的 key（逐项核对过，无摆设）。
    /// 在用户机器上实测有值的键（阈值、设备、iMessage 收件人、开关）全在其中；
    /// 已砍功能（Wi-Fi 联动、多配置、自动更新、暂停音乐）与无人读取的键一律不迁。
    static let migratedKeys: [String] = [
        "device", "deviceName", "enabled",
        "lockRSSI", "unlockRSSI", "wakeAdvance", "preUnlockTrigger",
        "lockOnIdle", "wakeOnProximity",
        "sleepDisplay", "screensaver",
        "iMessageNotify", "iMessageNotifyRecipient",
    ]

    let configFile: URL
    let defaults: UserDefaults
    let suiteName: String
    private var cache: [String: Any] = [:]
    private let lock = NSLock()

    /// 统一初始化入口：指定 configFile 与可选的 suiteName。
    /// - Parameters:
    ///   - configFile: 配置文件目标 URL，默认指向 AppPaths.configFile (~/.notchevery/config.json)。
    ///   - suiteName: 兼容 UserDefaults suite 域名称。
    init(configFile: URL? = nil, suiteName: String = ConfigStore.suiteName) {
        let resolvedConfigFile = configFile ?? (
            suiteName == ConfigStore.suiteName
                ? AppPaths.configFile
                : FileManager.default.temporaryDirectory.appendingPathComponent("ConfigStore-\(suiteName).json")
        )
        self.configFile = resolvedConfigFile
        self.suiteName = suiteName
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
        loadFromDisk()

        if suiteName == Self.suiteName {
            migrateFromLegacyIfNeeded(keys: Self.migratedKeys)
        }
    }

    /// 兼容旧构造器（通过 suiteName 初始化）
    convenience init(suiteName: String) {
        self.init(configFile: nil, suiteName: suiteName)
    }

    // MARK: - JSON 文件持久化与加载

    private func loadFromDisk() {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: configFile.path) else {
            migrateFromUserDefaultsLocked()
            return
        }

        do {
            let data = try Data(contentsOf: configFile)
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                self.cache = json
            } else {
                handleCorruptedFile(reason: "Top-level JSON is not a dictionary")
            }
        } catch {
            handleCorruptedFile(reason: error.localizedDescription)
        }
    }

    private func migrateFromUserDefaultsLocked() {
        self.cache = [:]

        // 逐一扫描所有已知 key，从 defaults 中读取并迁移至 cache
        let allKeys = Set(Self.migratedKeys + Self.legacyKeys)
        for key in allKeys {
            if let val = defaults.object(forKey: key) {
                cache[key] = sanitizeForJSON(val)
            }
        }

        // 仅在真实生产 suite 时，若有更古老的 legacy suite (com.fuhahah.Funlock.config)，才尝试带过来（隔离测试环境）
        if suiteName == Self.suiteName, let legacy = UserDefaults(suiteName: Self.legacySuiteName) {
            for key in Self.migratedKeys {
                if cache[key] == nil, let val = legacy.object(forKey: key) {
                    cache[key] = sanitizeForJSON(val)
                }
            }
        }

        // 立即原子写入磁盘
        saveToDiskLocked()
    }

    private func sanitizeForJSON(_ value: Any) -> Any {
        if let data = value as? Data {
            return data.base64EncodedString()
        }
        return value
    }

    private func handleCorruptedFile(reason: String) {
        os_log(.error, "ConfigStore: config file at %{public}@ is corrupted: %{public}@", configFile.path, reason)
        let backupPath = configFile.path + ".corrupt.\(Int(Date().timeIntervalSince1970))"
        try? FileManager.default.moveItem(atPath: configFile.path, toPath: backupPath)
        self.cache = [:]
    }

    private func saveToDiskLocked() {
        do {
            let dir = configFile.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }

            let data = try JSONSerialization.data(withJSONObject: cache, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: configFile, options: .atomic)
        } catch {
            os_log(.error, "ConfigStore: failed to write config atomically: %{public}@", error.localizedDescription)
        }
    }

    // MARK: - 迁移

    /// 一次性迁移：把旧 standard 的指定 key 搬到 JSON 存储和 suite。
    /// - Parameter keys: 需要迁移的业务 key 清单（不含系统 key）。
    func migrateIfNeeded(fromKeys keys: [String]) {
        guard !defaults.bool(forKey: ConfigStore.didMigrateKey) else { return }
        let standard = UserDefaults.standard
        standard.synchronize()

        lock.lock()
        for key in keys {
            if let value = standard.object(forKey: key) {
                cache[key] = value
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: ConfigStore.didMigrateKey)
        saveToDiskLocked()
        lock.unlock()
    }

    /// 一次性从 FUnlock 旧 suite（com.fuhahah.Funlock.config）把指定 key 搬到新域。
    func migrateFromLegacyIfNeeded(keys: [String]) {
        migrateFromLegacyIfNeeded(keys: keys, fromLegacySuite: Self.legacySuiteName)
    }

    /// 同上，但允许指定旧域名（测试隔离用）。
    func migrateFromLegacyIfNeeded(keys: [String], fromLegacySuite legacyName: String) {
        guard !defaults.bool(forKey: Self.didMigrateFromLegacyKey) else { return }
        lock.lock()
        if let legacy = UserDefaults(suiteName: legacyName) {
            for key in keys {
                if cache[key] == nil && defaults.object(forKey: key) == nil,
                   let value = legacy.object(forKey: key) {
                    cache[key] = value
                    defaults.set(value, forKey: key)
                }
            }
        }
        defaults.set(true, forKey: Self.didMigrateFromLegacyKey)
        saveToDiskLocked()
        lock.unlock()
    }

    // MARK: - 读写接口

    func get(_ key: String, fallback: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        if let num = cache[key] as? NSNumber {
            return num.intValue
        }
        if let intVal = cache[key] as? Int {
            return intVal
        }
        if let strVal = cache[key] as? String, let parsed = Int(strVal) {
            return parsed
        }
        return (defaults.object(forKey: key) as? Int) ?? fallback
    }

    func get(_ key: String, fallback: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let num = cache[key] as? NSNumber {
            return num.boolValue
        }
        if let boolVal = cache[key] as? Bool {
            return boolVal
        }
        if let strVal = cache[key] as? String {
            if strVal.lowercased() == "true" { return true }
            if strVal.lowercased() == "false" { return false }
        }
        return (defaults.object(forKey: key) as? Bool) ?? fallback
    }

    func get(_ key: String, fallback: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        if let str = cache[key] as? String {
            return str
        }
        return (defaults.object(forKey: key) as? String) ?? fallback
    }

    func getData(_ key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        if let base64Str = cache[key] as? String {
            return Data(base64Encoded: base64Str)
        }
        return defaults.data(forKey: key)
    }

    func set(_ value: Int, forKey key: String) {
        lock.lock()
        cache[key] = value
        defaults.set(value, forKey: key)
        saveToDiskLocked()
        lock.unlock()
    }

    func set(_ value: Bool, forKey key: String) {
        lock.lock()
        cache[key] = value
        defaults.set(value, forKey: key)
        saveToDiskLocked()
        lock.unlock()
    }

    func set(_ value: String, forKey key: String) {
        lock.lock()
        cache[key] = value
        defaults.set(value, forKey: key)
        saveToDiskLocked()
        lock.unlock()
    }

    func set(_ value: Data, forKey key: String) {
        lock.lock()
        cache[key] = value.base64EncodedString()
        defaults.set(value, forKey: key)
        saveToDiskLocked()
        lock.unlock()
    }

    func removeObject(forKey key: String) {
        lock.lock()
        cache.removeValue(forKey: key)
        defaults.removeObject(forKey: key)
        saveToDiskLocked()
        lock.unlock()
    }

    func object(forKey key: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return cache[key] ?? defaults.object(forKey: key)
    }

    func bool(forKey key: String) -> Bool {
        get(key, fallback: false)
    }

    func string(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let str = cache[key] as? String {
            return str
        }
        if let num = cache[key] as? NSNumber {
            return num.stringValue
        }
        return defaults.string(forKey: key)
    }

    func data(forKey key: String) -> Data? {
        getData(key)
    }
}

extension ConfigStore {
    /// 需要迁移的业务 key 全量清单（迁移时逐 key 搬迁）
    static let legacyKeys: [String] = [
        "device", "deviceName", "enabled", "launchAtLogin",
        "lockRSSI", "unlockRSSI", "wakeAdvance", "preUnlockTrigger",
        "lockOnIdle", "passiveMode", "wakeOnProximity", "wakeWithoutUnlocking",
        "sleepDisplay", "screensaver", "pauseOnWiFi", "pauseOnWiFiSSID",
        "pauseItunes", "iMessageNotify", "iMessageNotifyRecipient",
        "thresholdRSSI", "timeout", "lockDelay",
        "profiles", "activeProfileID",
        "hasCompletedOnboarding", "hasShownGuide", "hasCheckedAccessibility",
        "lastUpdateCheck", "manualLockNoAutoUnlock", "unlockMargin",
    ]
}
