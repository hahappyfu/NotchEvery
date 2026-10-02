//
//  UsageStore.swift
//  NotchEvery
//
//  单数据源适配器：CC Switch 本地用量库（~/.cc-switch/cc-switch.db）。
//  数据流：只读安全抓取 SQLite → 归一化/格式化 → 主线程发布。
//

import Combine
import Foundation
import os.log
import SQLite3

private let usageLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NotchEvery", category: "UsageStore")

// MARK: - 数据模型

/// 单个模型的今日用量条目（shareFraction 为占今日全量 token 的比例）
public struct ModelUsageItem: Identifiable, Equatable {
    public var id: String { model }
    public let model: String
    public let calls: Int
    public let totalTokens: Int
    public let cachedTokens: Int
    public let costUSD: Double
    public let shareFraction: Double

    public init(
        model: String,
        calls: Int,
        totalTokens: Int,
        cachedTokens: Int,
        costUSD: Double,
        shareFraction: Double
    ) {
        self.model = model
        self.calls = calls
        self.totalTokens = totalTokens
        self.cachedTokens = cachedTokens
        self.costUSD = costUSD
        self.shareFraction = shareFraction
    }
}

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
    /// 今日按模型聚合的用量（token 降序，最多 5 条）
    public var modelUsages: [ModelUsageItem] = []
    public var totalCostTodayUSD: Double = 0.0

    public static let empty = UsageData()

    public init(
        recentRequests: [TokenRequest] = [],
        summary: TokenSummary = .empty,
        cacheRateFraction: Double = 0,
        footer: UsageFooter = UsageFooter(),
        providerName: String? = nil,
        providerId: String? = nil,
        modelUsages: [ModelUsageItem] = [],
        totalCostTodayUSD: Double = 0.0
    ) {
        self.recentRequests = recentRequests
        self.summary = summary
        self.cacheRateFraction = cacheRateFraction
        self.footer = footer
        self.providerName = providerName
        self.providerId = providerId
        self.modelUsages = modelUsages
        self.totalCostTodayUSD = totalCostTodayUSD
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
    @Published public private(set) var modelUsages: [ModelUsageItem] = []
    @Published public private(set) var totalCostTodayUSD: Double = 0.0

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
            let data = CCSwitchUsageStore.fetch(dbPath: CCSwitchUsageStore.defaultDBPath)

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
                if self.modelUsages != data.modelUsages { self.modelUsages = data.modelUsages }
                if self.totalCostTodayUSD != data.totalCostTodayUSD { self.totalCostTodayUSD = data.totalCostTodayUSD }
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

// MARK: - CCSwitchUsageStore 数据源实现

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

    public static func fetch(dbPath: URL = defaultDBPath, now: Date = Date()) -> UsageData {
        guard let db = openReadOnly(dbPath) else { return .empty }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 500)

        let startOfDay = Calendar.current.startOfDay(for: now)
        let startOfDayTimestamp = Int64(startOfDay.timeIntervalSince1970)

        var data = UsageData()
        let (provName, provId) = queryCurrentProvider(db)
        data.providerName = provName
        data.providerId = provId
        data.recentRequests = queryRecent(db, startOfDayTimestamp: startOfDayTimestamp)

        // 若当前未查到 is_current 供应商，回退取最近一次请求的供应商名
        if data.providerName == nil, let latest = data.recentRequests.first {
            data.providerName = latest.accountEmail
        }

        let summaryTuple = querySummary(db, startOfDayTimestamp: startOfDayTimestamp)
        data.summary = summaryTuple.summary
        data.cacheRateFraction = summaryTuple.cacheRateFraction
        data.footer = UsageFooter(
            cacheReadTotal: summaryTuple.cacheReadTotal,
            lastRequestAt: queryLastRequestTime(db)
        )

        let modelTuple = queryModelUsages(db, startOfDayTimestamp: startOfDayTimestamp)
        data.modelUsages = modelTuple.items
        data.totalCostTodayUSD = modelTuple.totalCost

        return data
    }

    private static func openReadOnly(_ url: URL) -> OpaquePointer? {
        var db: OpaquePointer?
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
                if let db = db { sqlite3_close(db) }
                return nil
            }
        }
        sqlite3_exec(db, "PRAGMA query_only = ON;", nil, nil, nil)
        return db
    }

    private static func prepare(_ db: OpaquePointer, _ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        return stmt
    }

    private static func text(_ stmt: OpaquePointer, _ col: Int32) -> String {
        guard let cStr = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: cStr)
    }

    private static func queryRecent(_ db: OpaquePointer, startOfDayTimestamp: Int64) -> [TokenRequest] {
        let sql = """
        SELECT
            l.request_id,
            l.created_at,
            l.model,
            l.input_tokens,
            l.output_tokens,
            l.cache_read_tokens,
            CAST(l.total_cost_usd AS REAL),
            l.status_code,
            COALESCE(l.latency_ms, l.duration_ms, 0),
            COALESCE(p.name, l.provider_id)
        FROM proxy_request_logs l
        LEFT JOIN providers p ON p.id = l.provider_id
        WHERE l.created_at >= ?
        ORDER BY l.created_at DESC
        LIMIT 5;
        """
        guard let stmt = prepare(db, sql) else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, startOfDayTimestamp)
        var list: [TokenRequest] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let reqId = text(stmt, 0)
            let createdAt = sqlite3_column_int64(stmt, 1)
            let model = text(stmt, 2)
            let inTokens = Int(sqlite3_column_int64(stmt, 3))
            let outTokens = Int(sqlite3_column_int64(stmt, 4))
            let cachedTokens = Int(sqlite3_column_int64(stmt, 5))
            let costUSD = sqlite3_column_double(stmt, 6)
            let status = Int(sqlite3_column_int(stmt, 7))
            let latencyMs = sqlite3_column_double(stmt, 8)
            let provName = text(stmt, 9)

            let timeStr = timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(createdAt)))
            let costStr = formatCost(usd: costUSD, priced: true)

            list.append(TokenRequest(
                id: reqId,
                time: timeStr,
                model: model,
                inputTokens: inTokens,
                outputTokens: outTokens,
                durationSeconds: latencyMs / 1000.0,
                cost: costStr,
                status: status,
                accountEmail: provName.isEmpty ? nil : provName,
                cachedTokens: cachedTokens
            ))
        }
        return list
    }

    private static func querySummary(_ db: OpaquePointer, startOfDayTimestamp: Int64) -> (summary: TokenSummary, cacheRateFraction: Double, cacheReadTotal: Int) {
        let sql = """
        SELECT
            COUNT(*),
            COALESCE(SUM(input_tokens), 0),
            COALESCE(SUM(output_tokens), 0),
            COALESCE(SUM(cache_read_tokens), 0),
            COALESCE(SUM(CAST(total_cost_usd AS REAL)), 0.0)
        FROM proxy_request_logs
        WHERE created_at >= ?;
        """
        guard let stmt = prepare(db, sql) else { return (.empty, 0, 0) }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, startOfDayTimestamp)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return (.empty, 0, 0) }

        let callsCount = Int(sqlite3_column_int64(stmt, 0))
        let inTotal = Int(sqlite3_column_int64(stmt, 1))
        let outTotal = Int(sqlite3_column_int64(stmt, 2))
        let cacheReadTotal = Int(sqlite3_column_int64(stmt, 3))
        let costTotalUSD = sqlite3_column_double(stmt, 4)

        let totalTokens = inTotal + outTotal + cacheReadTotal
        let totalTokensStr = TokenFormatUtils.formatCompactTokens(totalTokens)

        let denominator = inTotal + cacheReadTotal
        let fraction = denominator > 0 ? Double(cacheReadTotal) / Double(denominator) : 0
        let cacheRateStr = String(format: "%.1f%%", fraction * 100)
        let costStr = formatCost(usd: costTotalUSD, priced: true)
        let callsStr = "\(callsCount)次"

        let summary = TokenSummary(
            totalTokens: totalTokensStr,
            cacheRate: cacheRateStr,
            calls: callsStr,
            cost: costStr
        )
        return (summary, fraction, cacheReadTotal)
    }

    private static func queryLastRequestTime(_ db: OpaquePointer) -> Date? {
        let sql = "SELECT created_at FROM proxy_request_logs ORDER BY created_at DESC LIMIT 1"
        guard let stmt = prepare(db, sql) else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 0)))
    }

    /// 今日按模型聚合：token 降序取前 5；shareFraction 分母与 totalCost 均按今日全量口径
    private static func queryModelUsages(_ db: OpaquePointer, startOfDayTimestamp: Int64) -> (items: [ModelUsageItem], totalCost: Double) {
        let sql = """
        SELECT
            model,
            COUNT(*) as calls,
            COALESCE(SUM(input_tokens + output_tokens + cache_read_tokens), 0) as total_tokens,
            COALESCE(SUM(cache_read_tokens), 0) as cached_tokens,
            COALESCE(SUM(CAST(total_cost_usd AS REAL)), 0.0) as cost
        FROM proxy_request_logs
        WHERE created_at >= ?
        GROUP BY model
        HAVING total_tokens > 0
        ORDER BY total_tokens DESC;
        """
        guard let stmt = prepare(db, sql) else { return ([], 0) }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, startOfDayTimestamp)
        var rows: [(model: String, calls: Int, totalTokens: Int, cachedTokens: Int, cost: Double)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append((
                model: text(stmt, 0),
                calls: Int(sqlite3_column_int64(stmt, 1)),
                totalTokens: Int(sqlite3_column_int64(stmt, 2)),
                cachedTokens: Int(sqlite3_column_int64(stmt, 3)),
                cost: sqlite3_column_double(stmt, 4)
            ))
        }

        let dayTotalTokens = rows.reduce(0) { $0 + $1.totalTokens }
        let totalCost = rows.reduce(0.0) { $0 + $1.cost }
        let items = rows.prefix(5).map { row in
            ModelUsageItem(
                model: row.model,
                calls: row.calls,
                totalTokens: row.totalTokens,
                cachedTokens: row.cachedTokens,
                costUSD: row.cost,
                shareFraction: dayTotalTokens > 0 ? Double(row.totalTokens) / Double(dayTotalTokens) : 0.0
            )
        }
        return (items, totalCost)
    }

    private static func queryCurrentProvider(_ db: OpaquePointer) -> (name: String?, id: String?) {
        let sql = "SELECT id, name FROM providers WHERE is_current = 1 ORDER BY (CASE WHEN app_type = 'claude-desktop' THEN 0 ELSE 1 END) LIMIT 1"
        guard let stmt = prepare(db, sql) else { return (nil, nil) }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return (nil, nil) }
        let idStr = text(stmt, 0)
        let nameStr = text(stmt, 1)
        return (nameStr.isEmpty ? nil : nameStr, idStr.isEmpty ? nil : idStr)
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
}
