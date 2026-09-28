//
//  UsageStore.swift
//  NotchEvery
//
//  单数据源适配器：Antigravity Tools 本地反代日志（~/.antigravity_tools/proxy_logs.db）。
//  数据流：只读安全抓取 SQLite → 归一化/格式化 → 主线程发布。
//

import Combine
import Foundation
import os.log
import SQLite3

private let usageLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NotchEvery", category: "UsageStore")

// MARK: - 数据模型

/// footer 数据（文案格式化在展示层）
public struct UsageFooter: Equatable {
    public var cacheReadTotal: Int = 0
    public var lastRequestAt: Date?

    public init(cacheReadTotal: Int = 0, lastRequestAt: Date? = nil) {
        self.cacheReadTotal = cacheReadTotal
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

    @Published public private(set) var recentRequests: [TokenRequest] = []
    @Published public private(set) var summary: TokenSummary = .empty
    @Published public private(set) var cacheRateFraction: Double = 0
    @Published public private(set) var footer = UsageFooter()
    @Published public private(set) var providerName: String?
    @Published public private(set) var providerId: String?

    private let interval: TimeInterval
    private var timer: Timer?
    private var refreshing = false

    public init(interval: TimeInterval = 3) {
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
        usageLog.info("UsageStore started, interval \(self.interval)s")
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func refresh() {
        guard !refreshing else { return }
        refreshing = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let data = AntigravityProxyStore.fetch(dbPath: AntigravityProxyStore.defaultDBPath)

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

    /// 针对最近请求计算的平均延迟文案
    public var averageLatencyText: String {
        guard !recentRequests.isEmpty else { return "--" }
        let total = recentRequests.reduce(0.0) { $0 + $1.durationSeconds }
        let avg = total / Double(recentRequests.count)
        return String(format: "%.1fs", avg)
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
        data.footer.lastRequestAt = queryLatestCreatedAt(db)
        return data
    }

    private static func openReadOnly(_ url: URL) -> OpaquePointer? {
        var db: OpaquePointer?
        // 先普通只读打开才能读到 WAL 里未 checkpoint 的最新数据；immutable=1 会无视 WAL。
        // 但 sqlite3_open_v2 是惰性的，当 -shm 缺失且无写方或权限不足时 open 返回 0，后续 prepare 会报 14 (CANTOPEN)。
        // 必须通过探针检测真实读取能力，不可用时才平滑降级到 immutable=1。
        let readOnlyFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        var canRead = false
        if sqlite3_open_v2(url.path, &db, readOnlyFlags, nil) == SQLITE_OK {
            var probe: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT 1 FROM sqlite_master LIMIT 1;", -1, &probe, nil) == SQLITE_OK {
                sqlite3_finalize(probe)
                canRead = true
            }
        }

        if !canRead {
            if let db = db { sqlite3_close(db) }
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
