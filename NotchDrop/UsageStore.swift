//
//  UsageStore.swift
//  NotchEvery
//
//  双数据源适配器：支持 Antigravity Tools 原生反代日志与 cc-switch 本地 SQLite 日志。
//  数据流：只读安全抓取 SQLite → 归一化/格式化 → 主线程发布。
//

import Combine
import Foundation
import os.log
import SQLite3

private let usageLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NotchEvery", category: "UsageStore")

// MARK: - 数据源枚举

public enum UsageDataSourceKind: String, Codable, CaseIterable {
    case antigravityTools
    case ccSwitch
}

// MARK: - 数据模型

/// footer 数据（文案格式化在展示层）
public struct UsageFooter: Equatable {
    public var cacheReadTotal: Int = 0
    public var savedUSD: Double = 0
    public var lastRequestAt: Date?

    public init(cacheReadTotal: Int = 0, savedUSD: Double = 0, lastRequestAt: Date? = nil) {
        self.cacheReadTotal = cacheReadTotal
        self.savedUSD = savedUSD
        self.lastRequestAt = lastRequestAt
    }
}

/// 一次抓取的完整快照
public struct UsageData: Equatable {
    public var recentRequests: [TokenRequest] = []
    public var summary: TokenSummary = .empty
    /// 缓存命中率数值形式（进度条填充用，0.0–1.0）
    public var cacheRateFraction: Double = 0
    public var footer = UsageFooter()
    public var providerName: String?
    public var providerId: String?

    public static let empty = UsageData()

    public init(
        recentRequests: [TokenRequest] = [],
        summary: TokenSummary = .empty,
        cacheRateFraction: Double = 0,
        footer: UsageFooter = UsageFooter(),
        providerName: String? = nil,
        providerId: String? = nil
    ) {
        self.recentRequests = recentRequests
        self.summary = summary
        self.cacheRateFraction = cacheRateFraction
        self.footer = footer
        self.providerName = providerName
        self.providerId = providerId
    }
}

// MARK: - UsageStore 主门面

public final class UsageStore: ObservableObject {
    public static let shared = UsageStore()

    /// 全局数据源路由开关（默认为 Antigravity Tools 本地反代原生日志）
    public static var activeSource: UsageDataSourceKind = .antigravityTools

    @Published public private(set) var recentRequests: [TokenRequest] = []
    @Published public private(set) var summary: TokenSummary = .empty
    @Published public private(set) var cacheRateFraction: Double = 0
    @Published public private(set) var footer = UsageFooter()
    @Published public private(set) var providerName: String?
    @Published public private(set) var providerId: String?

    /// 用 libc 直取真实家目录（不经过沙盒重定向的 Foundation 家目录 API）
    public static let defaultDBPath: URL = CCSwitchUsageStore.defaultDBPath

    private let dbPath: URL
    private let interval: TimeInterval
    private var timer: Timer?
    private var refreshing = false

    public init(dbPath: URL = UsageStore.defaultDBPath, interval: TimeInterval = 3) {
        self.dbPath = dbPath
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
        usageLog.info("UsageStore started, interval \(self.interval)s, source: \(Self.activeSource.rawValue)")
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func refresh() {
        guard !refreshing else { return }
        refreshing = true
        let source = Self.activeSource
        let ccPath = dbPath
        let antigravityPath = AntigravityProxyStore.defaultDBPath

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let data: UsageData
            switch source {
            case .antigravityTools:
                data = AntigravityProxyStore.fetch(dbPath: antigravityPath)
            case .ccSwitch:
                data = CCSwitchUsageStore.fetch(dbPath: ccPath)
            }

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.refreshing = false
                // 值级去重：无变化不发布，避免轮询空刷 UI
                if self.recentRequests != data.recentRequests { self.recentRequests = data.recentRequests }
                if self.summary != data.summary { self.summary = data.summary }
                if self.cacheRateFraction != data.cacheRateFraction { self.cacheRateFraction = data.cacheRateFraction }
                if self.footer != data.footer { self.footer = data.footer }
                if self.providerName != data.providerName { self.providerName = data.providerName }
                if self.providerId != data.providerId { self.providerId = data.providerId }
            }
        }
    }

    /// 保持向前兼容的静态抓取入口（直接委托给 CCSwitchUsageStore）
    public static func fetch(dbPath: URL, now: Date = Date()) -> UsageData {
        CCSwitchUsageStore.fetch(dbPath: dbPath, now: now)
    }

    public static func formatCost(usd: Double, priced: Bool) -> String {
        CCSwitchUsageStore.formatCost(usd: usd, priced: priced)
    }

    /// 针对最近请求计算的平均延迟文案
    public var averageLatencyText: String {
        guard !recentRequests.isEmpty else { return "--" }
        let total = recentRequests.reduce(0.0) { $0 + $1.durationSeconds }
        let avg = total / Double(recentRequests.count)
        return String(format: "%.1fs", avg)
    }

    public static func formatTokens(_ value: Int) -> String {
        CCSwitchUsageStore.formatTokens(value)
    }
}

// MARK: - AntigravityProxyStore 数据源实现

public final class AntigravityProxyStore: ObservableObject {
    public static let shared = AntigravityProxyStore()

    public static let defaultDBPath: URL = {
        let base: URL
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            base = URL(fileURLWithPath: String(cString: dir))
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
        }
        return base.appendingPathComponent(".antigravity_tools/proxy_logs.db")
    }()

    private let dbPath: URL
    private let interval: TimeInterval

    public init(dbPath: URL = AntigravityProxyStore.defaultDBPath, interval: TimeInterval = 3) {
        self.dbPath = dbPath
        self.interval = interval
    }

    public func fetchSnapshot(now: Date = Date()) -> UsageData {
        Self.fetch(dbPath: dbPath, now: now)
    }

    public static func fetch(dbPath: URL, now: Date = Date()) -> UsageData {
        guard let db = openReadOnly(dbPath) else { return .empty }
        defer { sqlite3_close(db) }

        var data = UsageData()
        data.providerName = "本地反代 :8045"
        data.providerId = "antigravity-proxy"
        data.recentRequests = queryRecent(db)

        let startOfDay = Calendar.current.startOfDay(for: now)
        let (summary, fraction, cacheTotal) = queryTodaySummary(db, since: startOfDay)
        data.summary = summary
        data.cacheRateFraction = fraction
        data.footer.cacheReadTotal = cacheTotal
        data.footer.savedUSD = 0.0
        data.footer.lastRequestAt = queryLatestCreatedAt(db)
        return data
    }

    private static func openReadOnly(_ url: URL) -> OpaquePointer? {
        var db: OpaquePointer?
        // 先普通只读打开才能读到 WAL 里未 checkpoint 的最新数据；immutable=1 会无视 WAL，
        // 仅当 -shm 不可用（如写方已退出且目录只读，错误码 14）时才降级
        let readOnlyFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(url.path, &db, readOnlyFlags, nil) != SQLITE_OK {
            sqlite3_close(db)
            db = nil
            let uriFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_FULLMUTEX
            guard sqlite3_open_v2("file://\(url.path)?immutable=1", &db, uriFlags, nil) == SQLITE_OK else {
                sqlite3_close(db)
                usageLog.info("antigravity proxy db unavailable at \(url.path)")
                return nil
            }
        }
        sqlite3_exec(db, "PRAGMA query_only = ON;", nil, nil, nil)
        sqlite3_busy_timeout(db, 500)
        return db
    }

    private static func prepare(_ db: OpaquePointer, _ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            usageLog.error("prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return nil
        }
        return stmt
    }

    private static func queryRecent(_ db: OpaquePointer) -> [TokenRequest] {
        let sql = """
            SELECT id, timestamp, model, input_tokens, output_tokens,
                   duration, status, account_email, mapped_model, cached_tokens
            FROM request_logs
            ORDER BY timestamp DESC
            LIMIT 5
            """
        guard let stmt = prepare(db, sql) else { return [] }
        defer { sqlite3_finalize(stmt) }

        var rows: [TokenRequest] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let tsRaw = sqlite3_column_int64(stmt, 1)
            let date = tsRaw > 10_000_000_000
                ? Date(timeIntervalSince1970: TimeInterval(tsRaw) / 1000.0)
                : Date(timeIntervalSince1970: TimeInterval(tsRaw))

            let mappedModel = text(stmt, 8)
            let rawModel = text(stmt, 2)
            let displayModel = (mappedModel?.isEmpty == false ? mappedModel : rawModel) ?? "unknown"
            let email = text(stmt, 7)
            let cached = Int(sqlite3_column_int64(stmt, 9))

            rows.append(TokenRequest(
                id: text(stmt, 0) ?? "",
                time: timeFormatter.string(from: date),
                model: displayModel,
                inputTokens: Int(sqlite3_column_int64(stmt, 3)),
                outputTokens: Int(sqlite3_column_int64(stmt, 4)),
                durationSeconds: Double(sqlite3_column_int64(stmt, 5)) / 1000.0,
                cost: "$0.00",
                status: Int(sqlite3_column_int64(stmt, 6)),
                accountEmail: email,
                cachedTokens: cached
            ))
        }
        return rows
    }

    private static func queryTodaySummary(_ db: OpaquePointer, since: Date) -> (TokenSummary, Double, Int) {
        let sinceMs = Int64(since.timeIntervalSince1970 * 1000.0)
        let sinceSec = Int64(since.timeIntervalSince1970)

        let sql = """
            SELECT COUNT(*),
                   COALESCE(SUM(input_tokens), 0),
                   COALESCE(SUM(output_tokens), 0),
                   COALESCE(SUM(cached_tokens), 0)
            FROM request_logs
            WHERE (timestamp >= ? AND timestamp > 10000000000)
               OR (timestamp >= ? AND timestamp <= 10000000000)
            """
        guard let stmt = prepare(db, sql) else { return (.empty, 0, 0) }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, sinceMs)
        sqlite3_bind_int64(stmt, 2, sinceSec)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return (.empty, 0, 0) }

        let calls = sqlite3_column_int64(stmt, 0)
        let inputTokens = sqlite3_column_int64(stmt, 1)
        let outputTokens = sqlite3_column_int64(stmt, 2)
        let cachedTokens = sqlite3_column_int64(stmt, 3)

        let total = inputTokens + outputTokens
        let fraction = inputTokens > 0 ? min(1.0, max(0.0, Double(cachedTokens) / Double(inputTokens))) : 0

        let summary = TokenSummary(
            totalTokens: total.formatted(),
            cacheRate: String(format: "%.1f%%", fraction * 100),
            calls: "\(calls)",
            cost: "$0.00"
        )
        return (summary, fraction, Int(cachedTokens))
    }

    private static func queryLatestCreatedAt(_ db: OpaquePointer) -> Date? {
        let sql = """
            SELECT timestamp
            FROM request_logs
            ORDER BY timestamp DESC
            LIMIT 1
            """
        guard let stmt = prepare(db, sql) else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let ts = sqlite3_column_int64(stmt, 0)
        return ts > 10_000_000_000
            ? Date(timeIntervalSince1970: TimeInterval(ts) / 1000.0)
            : Date(timeIntervalSince1970: TimeInterval(ts))
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static func text(_ stmt: OpaquePointer?, _ column: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, column) else { return nil }
        return String(cString: c)
    }
}

// MARK: - CCSwitchUsageStore 完整封装保留（严禁不可逆硬删除）

public enum CCSwitchUsageStore {
    public static let defaultDBPath: URL = {
        let base: URL
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            base = URL(fileURLWithPath: String(cString: dir))
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
        }
        return base.appendingPathComponent(".cc-switch/cc-switch.db")
    }()

    public static func fetch(dbPath: URL, now: Date = Date()) -> UsageData {
        guard let db = openReadOnly(dbPath) else { return .empty }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 500)

        let startOfDay = Calendar.current.startOfDay(for: now)
        var data = UsageData()
        let (provName, provId) = queryCurrentProvider(db)
        data.providerName = provName
        data.providerId = provId
        data.recentRequests = queryRecent(db, providerId: provId)
        let (summary, fraction) = queryTodaySummary(db, since: startOfDay, providerId: provId)
        data.summary = summary
        data.cacheRateFraction = fraction
        data.footer.cacheReadTotal = todayCacheReadTotal(db, since: startOfDay, providerId: provId)
        data.footer.savedUSD = todayCacheSaved(db, since: startOfDay, providerId: provId)
        data.footer.lastRequestAt = queryLatestCreatedAt(db)
        return data
    }

    private static let baseFilter = """
        l.app_type IN ('claude', 'claude-desktop')
        AND NOT (
            COALESCE(l.data_source, 'proxy') IN ('session_log', 'codex_session', 'gemini_session', 'opencode_session')
            AND EXISTS (
                SELECT 1 FROM proxy_request_logs pd
                WHERE COALESCE(pd.data_source, 'proxy') = 'proxy'
                  AND pd.app_type IN (l.app_type, CASE WHEN l.app_type = 'claude' THEN 'claude-desktop' ELSE l.app_type END)
                  AND pd.status_code >= 200 AND pd.status_code < 300
                  AND pd.input_tokens = l.input_tokens
                  AND pd.output_tokens = l.output_tokens
                  AND pd.cache_read_tokens = l.cache_read_tokens
                  AND (pd.cache_creation_tokens = l.cache_creation_tokens
                       OR (l.cache_creation_tokens = 0
                           AND COALESCE(l.data_source, 'proxy') IN ('codex_session', 'gemini_session', 'opencode_session')))
                  AND pd.created_at BETWEEN l.created_at - 600 AND l.created_at + 600
                  AND (LOWER(pd.model) = LOWER(l.model) OR LOWER(pd.model) = 'unknown' OR LOWER(l.model) = 'unknown')
            )
        )
        """

    private static let freshInputSQL = """
        CASE
            WHEN l.input_token_semantics = 2 THEN l.input_tokens
            WHEN l.app_type IN ('codex', 'gemini', 'grokbuild')
                 AND l.input_token_semantics = 1
                 AND l.input_tokens >= (l.cache_read_tokens + l.cache_creation_tokens)
            THEN (l.input_tokens - l.cache_read_tokens - l.cache_creation_tokens)
            WHEN l.app_type IN ('codex', 'gemini', 'grokbuild')
                 AND l.input_token_semantics = 0
                 AND l.input_tokens >= l.cache_read_tokens
            THEN (l.input_tokens - l.cache_read_tokens)
            ELSE l.input_tokens
        END
        """

    private static func openReadOnly(_ url: URL) -> OpaquePointer? {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK else {
            sqlite3_close(db)
            usageLog.info("cc-switch db unavailable at \(url.path)")
            return nil
        }
        sqlite3_exec(db, "PRAGMA query_only = ON;", nil, nil, nil)
        return db
    }

    private static func prepare(_ db: OpaquePointer, _ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            usageLog.error("prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return nil
        }
        return stmt
    }

    private static func queryRecent(_ db: OpaquePointer, providerId: String?) -> [TokenRequest] {
        let providerClause = providerId.map { " AND l.provider_id = '\($0)'" } ?? ""
        let sql = """
            SELECT l.request_id, l.created_at, l.model, l.input_tokens, l.output_tokens,
                   l.latency_ms, l.status_code, l.total_cost_usd, l.pricing_model
            FROM proxy_request_logs l
            WHERE \(baseFilter)\(providerClause)
            ORDER BY l.created_at DESC, l.rowid DESC
            LIMIT 5
            """
        guard let stmt = prepare(db, sql) else { return [] }
        defer { sqlite3_finalize(stmt) }

        var rows: [TokenRequest] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let createdAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 1)))
            let costUSD = Double(text(stmt, 7) ?? "0") ?? 0
            let pricing = text(stmt, 8)
            rows.append(TokenRequest(
                id: text(stmt, 0) ?? "",
                time: timeFormatter.string(from: createdAt),
                model: text(stmt, 2) ?? "unknown",
                inputTokens: Int(sqlite3_column_int64(stmt, 3)),
                outputTokens: Int(sqlite3_column_int64(stmt, 4)),
                durationSeconds: Double(sqlite3_column_int64(stmt, 5)) / 1000,
                cost: formatCost(usd: costUSD, priced: pricing?.isEmpty == false),
                status: Int(sqlite3_column_int64(stmt, 6))
            ))
        }
        return rows
    }

    private static func queryTodaySummary(_ db: OpaquePointer, since: Date, providerId: String?) -> (TokenSummary, Double) {
        let providerClause = providerId.map { " AND l.provider_id = '\($0)'" } ?? ""
        let sql = """
            SELECT COUNT(*),
                   COALESCE(SUM(\(freshInputSQL)), 0),
                   COALESCE(SUM(l.output_tokens), 0),
                   COALESCE(SUM(l.cache_read_tokens), 0),
                   COALESCE(SUM(l.cache_creation_tokens), 0),
                   COALESCE(SUM(CAST(l.total_cost_usd AS REAL)), 0)
            FROM proxy_request_logs l
            WHERE \(baseFilter)\(providerClause) AND l.created_at >= ?
            """
        guard let stmt = prepare(db, sql) else { return (.empty, 0) }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(since.timeIntervalSince1970))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return (.empty, 0) }

        let calls = sqlite3_column_int64(stmt, 0)
        let fresh = sqlite3_column_int64(stmt, 1)
        let output = sqlite3_column_int64(stmt, 2)
        let cacheRead = sqlite3_column_int64(stmt, 3)
        let cacheCreate = sqlite3_column_int64(stmt, 4)
        let costUSD = sqlite3_column_double(stmt, 5)

        let total = fresh + output + cacheRead + cacheCreate
        let cacheable = fresh + cacheRead + cacheCreate
        let fraction = cacheable > 0 ? Double(cacheRead) / Double(cacheable) : 0
        let summary = TokenSummary(
            totalTokens: formatTokens(Int(total)),
            cacheRate: String(format: "%.1f%%", fraction * 100),
            calls: "\(Int(calls).formatted())次",
            cost: formatCost(usd: costUSD, priced: true)
        )
        return (summary, fraction)
    }

    private static func todayCacheReadTotal(_ db: OpaquePointer, since: Date, providerId: String?) -> Int {
        let providerClause = providerId.map { " AND l.provider_id = '\($0)'" } ?? ""
        let sql = """
            SELECT COALESCE(SUM(l.cache_read_tokens), 0)
            FROM proxy_request_logs l
            WHERE \(baseFilter)\(providerClause) AND l.created_at >= ?
            """
        guard let stmt = prepare(db, sql) else { return 0 }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(since.timeIntervalSince1970))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private static func todayCacheSaved(_ db: OpaquePointer, since: Date, providerId: String?) -> Double {
        let providerClause = providerId.map { " AND l.provider_id = '\($0)'" } ?? ""
        let sql = """
            SELECT COALESCE(SUM(
                l.cache_read_tokens / 1000000.0
                * (CAST(mp.input_cost_per_million AS REAL) - CAST(mp.cache_read_cost_per_million AS REAL))
            ), 0)
            FROM proxy_request_logs l
            LEFT JOIN model_pricing mp ON mp.model_id = COALESCE(NULLIF(l.pricing_model, ''), l.model)
            WHERE \(baseFilter)\(providerClause) AND l.created_at >= ? AND mp.model_id IS NOT NULL
            """
        guard let stmt = prepare(db, sql) else { return 0 }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(since.timeIntervalSince1970))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return sqlite3_column_double(stmt, 0)
    }

    private static func queryLatestCreatedAt(_ db: OpaquePointer) -> Date? {
        let sql = """
            SELECT l.created_at
            FROM proxy_request_logs l
            WHERE \(baseFilter)
            ORDER BY l.created_at DESC, l.rowid DESC
            LIMIT 1
            """
        guard let stmt = prepare(db, sql) else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 0)))
    }

    private static func queryCurrentProvider(_ db: OpaquePointer) -> (name: String?, id: String?) {
        let sql = "SELECT id, name FROM providers WHERE app_type = 'claude-desktop' AND is_current = 1 LIMIT 1"
        guard let stmt = prepare(db, sql) else { return (nil, nil) }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return (nil, nil) }
        return (text(stmt, 1), text(stmt, 0))
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    public static func formatCost(usd: Double, priced: Bool) -> String {
        guard priced else { return "未定价" }
        if usd >= 0.01 { return String(format: "$%.2f", usd) }
        if usd > 0 { return String(format: "$%.4f", usd) }
        return "$0.00"
    }

    public static func formatTokens(_ value: Int) -> String {
        let v = Double(value)
        if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.1fK", v / 1_000) }
        return String(value)
    }

    private static func text(_ stmt: OpaquePointer?, _ column: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, column) else { return nil }
        return String(cString: c)
    }
}
