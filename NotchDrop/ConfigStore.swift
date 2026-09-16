// FUnlock/ConfigStore.swift
import Foundation

/// 配置存储：独立 suite 域，与 bundle id 解耦。
/// 覆盖安装 app 后配置不丢失（偏好域不随 bundle 替换而重建）。
/// 所有配置读写走这里，不再直接使用 UserDefaults.standard。
final class ConfigStore {
    static let shared = ConfigStore()

    /// 现行 suite 域名（固定，不随 bundle id 变）。
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

    let defaults: UserDefaults

    /// 测试注入：允许指定 suite 名隔离。
    /// 注意：只有默认 suite 会在构造时触发一次性旧域迁移；测试用的隔离域名不会。
    init(suiteName: String = ConfigStore.suiteName) {
        // UserDefaults(suiteName:) 失败时回退 standard（理论不触发）
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
        if suiteName == Self.suiteName {
            migrateFromLegacyIfNeeded(keys: Self.migratedKeys)
        }
    }

    // MARK: - 迁移

    /// 一次性迁移：把旧 standard 的指定 key 搬到 suite。
    /// - Parameter keys: 需要迁移的业务 key 清单（不含系统 key）。
    func migrateIfNeeded(fromKeys keys: [String]) {
        guard !defaults.bool(forKey: ConfigStore.didMigrateKey) else { return }
        let standard = UserDefaults.standard
        // cfprefsd 缓存可能未就绪：阻塞同步磁盘，确保 standard 有值时能读到（避免空跑迁移）
        standard.synchronize()
        for key in keys {
            if let value = standard.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: ConfigStore.didMigrateKey)
    }

    /// 一次性迁移：把 FUnlock 旧 suite 域的指定 key 搬到现行域（工单 02）。
    /// 幂等：已落标记直接返回；且逐 key 只填空、不覆盖新域已有值，
    /// 因此即使标记丢失导致重跑，也不会覆盖迁移后用户改过的值。
    /// 旧域只读不删（失败不丢数据，且不引入对旧域的运行时读取依赖——
    /// 迁移完成后所有读写只走现行域）。
    /// - Parameter keys: 需要迁移的业务 key 清单。
    func migrateFromLegacyIfNeeded(keys: [String]) {
        migrateFromLegacyIfNeeded(keys: keys, fromLegacySuite: Self.legacySuiteName)
    }

    /// 同上，但允许指定旧域名（测试隔离用）。
    func migrateFromLegacyIfNeeded(keys: [String], fromLegacySuite legacyName: String) {
        guard !defaults.bool(forKey: Self.didMigrateFromLegacyKey) else { return }
        if let legacy = UserDefaults(suiteName: legacyName) {
            for key in keys {
                if defaults.object(forKey: key) == nil,
                   let value = legacy.object(forKey: key) {
                    defaults.set(value, forKey: key)
                }
            }
        }
        defaults.set(true, forKey: Self.didMigrateFromLegacyKey)
    }

    // MARK: - 读写

    func get(_ key: String, fallback: Int) -> Int {
        defaults.object(forKey: key) as? Int ?? fallback
    }
    func get(_ key: String, fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }
    func get(_ key: String, fallback: String) -> String {
        defaults.object(forKey: key) as? String ?? fallback
    }
    func getData(_ key: String) -> Data? {
        defaults.data(forKey: key)
    }
    func set(_ value: Int, forKey key: String) { defaults.set(value, forKey: key) }
    func set(_ value: Bool, forKey key: String) { defaults.set(value, forKey: key) }
    func set(_ value: String, forKey key: String) { defaults.set(value, forKey: key) }
    func set(_ value: Data, forKey key: String) { defaults.set(value, forKey: key) }
    func removeObject(forKey key: String) { defaults.removeObject(forKey: key) }
    func object(forKey key: String) -> Any? { defaults.object(forKey: key) }
    func bool(forKey key: String) -> Bool { defaults.bool(forKey: key) }
    func string(forKey key: String) -> String? { defaults.string(forKey: key) }
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
