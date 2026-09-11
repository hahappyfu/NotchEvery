//
//  UsageStore.swift
//  NotchEvery
//
//  用量轮询：只读 cc-switch 的 SQLite → 归一化/格式化 → 主线程发布。
//  官方口径与 cc-switch usage_stats.rs 对齐（净输入归一、去重过滤、KPI 公式）。
//

import Combine
import Foundation
import os.log
import SQLite3

private let usageLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NotchEvery", category: "UsageStore")

/// footer 数据（文案格式化在展示层）
struct UsageFooter: Equatable {
    var cacheReadTotal: Int = 0
    var savedUSD: Double = 0
    var lastRequestAt: Date?
}

/// 一次抓取的完整快照
struct UsageData: Equatable {
    var recentRequests: [TokenRequest] = []
    var summary: TokenSummary = .empty
    /// 缓存命中率数值形式（进度条填充用，0.0–1.0）
    var cacheRateFraction: Double = 0
    var footer = UsageFooter()
    var providerName: String?
    var providerId: String?

    static let empty = UsageData()
}

final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    @Published private(set) var recentRequests: [TokenRequest] = []
    @Published private(set) var summary: TokenSummary = .empty
    @Published private(set) var cacheRateFraction: Double = 0
    @Published private(set) var footer = UsageFooter()
    @Published private(set) var providerName: String?
    @Published private(set) var providerId: String?

    /// 用 libc 直取真实家目录（不经过沙盒重定向的 Foundation 家目录 API）
    static let defaultDBPath: URL = {
        let base: URL
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            base = URL(fileURLWithPath: String(cString: dir))
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
        }
        return base.appendingPathComponent(".cc-switch/cc-switch.db")
    }()

    private let dbPath: URL
    private let interval: TimeInterval
    private var timer: Timer?
    private var refreshing = false

    init(dbPath: URL = UsageStore.defaultDBPath, interval: TimeInterval = 3) {
        self.dbPath = dbPath
        self.interval = interval
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        usageLog.info("UsageStore started, interval \(self.interval)s")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        let path = dbPath
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let data = UsageStore.fetch(dbPath: path)
            DispatchQueue.main.async {
                guard let self else { return }
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
}

// MARK: - 抓取（纯函数，可注入 db 路径与"现在"）

extension UsageStore {
    static func fetch(dbPath: URL, now: Date = Date()) -> UsageData {
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

    /// claude 系折叠 + 跨源去重（防 session 日志与 proxy 双计），对齐 cc-switch effective_usage_log_filter。
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

    /// 行级净输入：FRESH 直取；TOTAL/LEGACY 归一到"不含缓存"（对齐 cc-switch fresh_input_sql）。
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

    /// 缓存节省 = Σ 缓存读/1e6 ×（输入单价 − 缓存读单价）；无定价行跳过。
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

    // MARK: - 展示格式化

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// ≥$0.01 两位小数；<$0.01 四位；无定价 → 未定价；零 → $0.00
    static func formatCost(usd: Double, priced: Bool) -> String {
        guard priced else { return "未定价" }
        if usd >= 0.01 { return String(format: "$%.2f", usd) }
        if usd > 0 { return String(format: "$%.4f", usd) }
        return "$0.00"
    }

    static func formatTokens(_ value: Int) -> String {
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
