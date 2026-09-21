//
//  AntigravityStore.swift
//  NotchEvery
//
//  Antigravity 账号与配额数据轮询：读取 ~/.antigravity_tools 本地文件 → 归一化 → 主线程发布。
//  纯本地文件操作，不发网络请求。
//

import Combine
import Foundation
import os.log
import SQLite3

private let antigravityLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NotchEvery", category: "AntigravityStore")

// MARK: - Models

public struct AntigravityAccount: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let email: String
    public let isCurrent: Bool
    public let isDisabled: Bool
    public let isProxyDisabled: Bool
    public let percentage: Int
    public let resetTime: Date?
    public let lastActiveTime: Date?
    /// 单账号文件（accounts/<id>.json）里是否显式写了 `disabled` 字段；false 表示缺省，需要看索引兜底。仅 loadAccounts 内部使用。
    var rawDisabledPresent: Bool = false
    /// rawDisabledPresent 为 true 时该字段的实际值。
    var rawDisabledValue: Bool = false
    /// 单账号文件里是否显式写了 `proxy_disabled` 字段；false 表示缺省，需要看索引兜底。
    var rawProxyDisabledPresent: Bool = false

    public init(
        id: String,
        name: String,
        email: String,
        isCurrent: Bool,
        isDisabled: Bool,
        isProxyDisabled: Bool = false,
        percentage: Int,
        resetTime: Date?,
        lastActiveTime: Date? = nil,
        rawDisabledPresent: Bool = false,
        rawDisabledValue: Bool = false,
        rawProxyDisabledPresent: Bool = false
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.isCurrent = isCurrent
        self.isDisabled = isDisabled
        self.isProxyDisabled = isProxyDisabled
        self.percentage = percentage
        self.resetTime = resetTime
        self.lastActiveTime = lastActiveTime
        self.rawDisabledPresent = rawDisabledPresent
        self.rawDisabledValue = rawDisabledValue
        self.rawProxyDisabledPresent = rawProxyDisabledPresent
    }
}

public struct AntigravityIndex: Equatable {
    /// accounts.json 单条账号的开关状态（用户实际切换后的权威值）
    public struct AccountFlags: Equatable {
        public let disabled: Bool
        public let proxyDisabled: Bool

        public init(disabled: Bool = false, proxyDisabled: Bool = false) {
            self.disabled = disabled
            self.proxyDisabled = proxyDisabled
        }
    }

    public let currentAccountId: String?
    public let accountIds: [String]
    /// 账号 id → 索引开关状态。缺条目按全 false 处理。
    public let flags: [String: AccountFlags]

    public init(currentAccountId: String?, accountIds: [String], flags: [String: AccountFlags] = [:]) {
        self.currentAccountId = currentAccountId
        self.accountIds = accountIds
        self.flags = flags
    }
}

// MARK: - Store

public final class AntigravityStore: ObservableObject {
    public static let shared = AntigravityStore()

    @Published public private(set) var accounts: [AntigravityAccount] = []
    @Published public private(set) var currentAccountId: String?

    public static let baseDirectory: URL = {
        let base: URL
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            base = URL(fileURLWithPath: String(cString: dir))
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
        }
        return base.appendingPathComponent(".antigravity_tools")
    }()

    private let baseDir: URL
    private let interval: TimeInterval
    private var timer: Timer?
    private var isRefreshing = false

    public init(baseDir: URL = AntigravityStore.baseDirectory, interval: TimeInterval = 3) {
        self.baseDir = baseDir
        self.interval = interval
    }

    public func start() {
        guard timer == nil else { return }
        refresh()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        antigravityLog.info("AntigravityStore started, interval \(self.interval)s")
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let dir = baseDir

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let (newAccounts, currentId) = Self.loadAccounts(from: dir)

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isRefreshing = false
                if self.accounts != newAccounts {
                    self.accounts = newAccounts
                }
                if self.currentAccountId != currentId {
                    self.currentAccountId = currentId
                }
            }
        }
    }

    public func selectAccount(id: String) {
        guard currentAccountId != id else { return }
        currentAccountId = id
        // 乐观更新内存中 isCurrent
        accounts = accounts.map { acc in
            AntigravityAccount(
                id: acc.id,
                name: acc.name,
                email: acc.email,
                isCurrent: acc.id == id,
                isDisabled: acc.isDisabled,
                isProxyDisabled: acc.isProxyDisabled,
                percentage: acc.percentage,
                resetTime: acc.resetTime,
                lastActiveTime: acc.lastActiveTime,
                rawDisabledPresent: acc.rawDisabledPresent,
                rawDisabledValue: acc.rawDisabledValue,
                rawProxyDisabledPresent: acc.rawProxyDisabledPresent
            )
        }

        let dir = baseDir
        DispatchQueue.global(qos: .utility).async {
            let indexFile = dir.appendingPathComponent("accounts.json")
            guard let data = try? Data(contentsOf: indexFile),
                  var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            json["current_account_id"] = id
            if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
                try? updatedData.write(to: indexFile, options: .atomic)
            }
        }
    }

    // MARK: - Static Parsers & Helpers

    /// 从 token_stats.db（或回退 proxy_logs.db）中安全只读提取各账号最新请求时间戳
    public static func loadLastActiveTimes(from directory: URL) -> [String: Date] {
        var results: [String: Date] = [:]
        let tokenStatsDB = directory.appendingPathComponent("token_stats.db")

        func queryDB(url: URL, sql: String) {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            var db: OpaquePointer?
            let uriString = "file://\(url.path)?immutable=1"
            let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_FULLMUTEX
            if sqlite3_open_v2(uriString, &db, flags, nil) != SQLITE_OK {
                let fallbackFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
                guard sqlite3_open_v2(url.path, &db, fallbackFlags, nil) == SQLITE_OK else {
                    if let db = db { sqlite3_close(db) }
                    return
                }
            }
            guard let db = db else { return }
            defer { sqlite3_close(db) }
            sqlite3_exec(db, "PRAGMA query_only = ON;", nil, nil, nil)
            sqlite3_busy_timeout(db, 300)

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt {
                defer { sqlite3_finalize(stmt) }
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let emailPtr = sqlite3_column_text(stmt, 0) {
                        let email = String(cString: emailPtr).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !email.isEmpty else { continue }
                        let tsRaw = sqlite3_column_int64(stmt, 1)
                        guard tsRaw > 0 else { continue }
                        let date = tsRaw > 10_000_000_000
                            ? Date(timeIntervalSince1970: TimeInterval(tsRaw) / 1000.0)
                            : Date(timeIntervalSince1970: TimeInterval(tsRaw))
                        if let existing = results[email] {
                            if date > existing { results[email] = date }
                        } else {
                            results[email] = date
                        }
                    }
                }
            }
        }

        // 1. 从实时代理请求日志 proxy_logs.db 读取最新请求时间戳（流水级毫秒数据）
        let proxyLogsDB = directory.appendingPathComponent("proxy_logs.db")
        queryDB(
            url: proxyLogsDB,
            sql: "SELECT account_email, MAX(timestamp) FROM request_logs WHERE account_email != '' GROUP BY account_email;"
        )

        // 2. 从聚合统计库 token_stats.db 读取，取两者的最新时间戳最大值
        queryDB(
            url: tokenStatsDB,
            sql: "SELECT account_email, MAX(timestamp) FROM token_usage WHERE account_email != '' GROUP BY account_email;"
        )

        return results
    }

    public static func loadAccounts(from directory: URL) -> ([AntigravityAccount], String?) {
        let indexFile = directory.appendingPathComponent("accounts.json")
        guard let indexData = try? Data(contentsOf: indexFile),
              let index = parseIndex(data: indexData) else {
            return ([], nil)
        }

        let accountsDir = directory.appendingPathComponent("accounts")
        let activeTimes = loadLastActiveTimes(from: directory)
        var rawAccounts: [AntigravityAccount] = []

        for accId in index.accountIds {
            let fileURL = accountsDir.appendingPathComponent("\(accId).json")
            guard let data = try? Data(contentsOf: fileURL),
                  let account = parseAccountFile(data: data, currentAccountId: index.currentAccountId) else {
                continue
            }
            rawAccounts.append(account)
        }

        // 依据日志活跃时间动态检测当前在用账号（最新活跃账号 > index.currentAccountId）
        var mostRecentAccount: AntigravityAccount?
        var mostRecentDate: Date = .distantPast

        for acc in rawAccounts {
            let emailKey = acc.email.lowercased()
            if let actDate = activeTimes[emailKey], actDate > mostRecentDate {
                mostRecentDate = actDate
                mostRecentAccount = acc
            }
        }

        let dynamicCurrentId: String? = mostRecentAccount?.id ?? index.currentAccountId

        let finalizedAccounts = rawAccounts.map { acc in
            let emailKey = acc.email.lowercased()
            let actDate = activeTimes[emailKey]
            let isCurrent = (acc.id == dynamicCurrentId)
            // 单账号文件（accounts/<id>.json）是权威来源；索引 accounts.json 里的同名标记可能是历史残留，
            // 只有当单账号文件根本没写这个字段时，才用索引的值兜底（而不是两边 OR）。
            let indexFlags = index.flags[acc.id] ?? AntigravityIndex.AccountFlags()
            let fileHasProxyFlag = acc.rawProxyDisabledPresent
            let isProxyDisabled = fileHasProxyFlag ? acc.isProxyDisabled : indexFlags.proxyDisabled
            let fileHasDisabledFlag = acc.rawDisabledPresent
            let disabledResolved = fileHasDisabledFlag ? acc.rawDisabledValue : indexFlags.disabled
            return AntigravityAccount(
                id: acc.id,
                name: acc.name,
                email: acc.email,
                isCurrent: isCurrent,
                isDisabled: disabledResolved || isProxyDisabled,
                isProxyDisabled: isProxyDisabled,
                percentage: acc.percentage,
                resetTime: acc.resetTime,
                lastActiveTime: actDate
            )
        }

        return (finalizedAccounts, dynamicCurrentId)
    }

    public static func parseIndex(data: Data) -> AntigravityIndex? {
        struct RawIndex: Decodable {
            let current_account_id: String?
            let accounts: [RawAccountItem]?

            struct RawAccountItem: Decodable {
                let id: String
                let disabled: Bool?
                let proxy_disabled: Bool?
            }
        }

        guard let raw = try? JSONDecoder().decode(RawIndex.self, from: data) else {
            return nil
        }

        let items = raw.accounts ?? []
        let ids = items.map { $0.id }
        var flags: [String: AntigravityIndex.AccountFlags] = [:]
        for item in items {
            flags[item.id] = AntigravityIndex.AccountFlags(
                disabled: item.disabled == true,
                proxyDisabled: item.proxy_disabled == true
            )
        }
        return AntigravityIndex(currentAccountId: raw.current_account_id, accountIds: ids, flags: flags)
    }

    public static func parseAccountFile(data: Data, currentAccountId: String?) -> AntigravityAccount? {
        struct RawAccount: Decodable {
            let id: String
            let name: String?
            let email: String?
            let disabled: Bool?
            let proxy_disabled: Bool?
            let quota: RawQuota?

            struct RawQuota: Decodable {
                let models: [RawModel]?
            }

            struct RawModel: Decodable {
                let name: String?
                let percentage: Int?
                let reset_time: String?
            }
        }

        guard let raw = try? JSONDecoder().decode(RawAccount.self, from: data) else {
            return nil
        }

        let id = raw.id
        let email = raw.email ?? ""
        let name = (raw.name?.isEmpty == false) ? raw.name! : (!email.isEmpty ? email : id)
        let isCurrent = (id == currentAccountId)
        let isProxyDisabled = (raw.proxy_disabled == true)
        let isDisabled = (raw.disabled == true) || isProxyDisabled

        // 提取配额模型（优先选择包含 gemini 的共享模型，否则取第一个模型）
        var selectedModel: RawAccount.RawModel?
        if let models = raw.quota?.models, !models.isEmpty {
            selectedModel = models.first { ($0.name ?? "").lowercased().contains("gemini") } ?? models.first
        }

        let rawPercentage = selectedModel?.percentage ?? 0
        let percentage = min(100, max(0, rawPercentage))

        var resetDate: Date?
        if let resetStr = selectedModel?.reset_time {
            resetDate = parseISO8601(resetStr)
        }

        return AntigravityAccount(
            id: id,
            name: name,
            email: email,
            isCurrent: isCurrent,
            isDisabled: isDisabled,
            isProxyDisabled: isProxyDisabled,
            percentage: percentage,
            resetTime: resetDate,
            rawDisabledPresent: raw.disabled != nil,
            rawDisabledValue: raw.disabled == true,
            rawProxyDisabledPresent: raw.proxy_disabled != nil
        )
    }

    public static func formatCountdown(from resetTime: Date?, now: Date = Date()) -> String {
        guard let resetTime = resetTime else { return "已就绪" }
        let diff = resetTime.timeIntervalSince(now)
        guard diff > 0 else { return "已就绪" }

        let seconds = Int(diff)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours >= 48 {
            let days = hours / 24
            let remHours = hours % 24
            return "\(days)d\(remHours)h"
        } else if hours >= 24 {
            return "\(hours)h"
        } else if hours > 0 {
            return "\(hours)h\(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "已就绪"
        }
    }

    private static func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}
