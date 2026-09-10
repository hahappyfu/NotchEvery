import SQLite3
import XCTest
@testable import NotchEvery

/// UsageStore 外部行为测试：喂一个 cc-switch 形状的 SQLite fixture，断言发布的数据。
final class UsageStoreTests: XCTestCase {
    private var dirURL: URL!
    private var dbURL: URL!

    /// 固定"现在"：2026-09-11 12:00 本地时区，让今日/跨日边界可断言。
    private var now: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 12))!
    }

    override func setUpWithError() throws {
        dirURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        dbURL = dirURL.appendingPathComponent("cc-switch.db")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dirURL)
    }

    // MARK: - Fixture

    private func epoch(secondsFromNow offset: TimeInterval) -> Int {
        Int(now.addingTimeInterval(offset).timeIntervalSince1970)
    }

    private func makeFixtureDB() throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        try exec(db, """
        CREATE TABLE proxy_request_logs (
            request_id TEXT PRIMARY KEY, provider_id TEXT NOT NULL, app_type TEXT NOT NULL,
            model TEXT NOT NULL, input_tokens INTEGER NOT NULL DEFAULT 0,
            output_tokens INTEGER NOT NULL DEFAULT 0, cache_read_tokens INTEGER NOT NULL DEFAULT 0,
            cache_creation_tokens INTEGER NOT NULL DEFAULT 0, total_cost_usd TEXT NOT NULL DEFAULT '0',
            latency_ms INTEGER NOT NULL, status_code INTEGER NOT NULL, created_at INTEGER NOT NULL,
            data_source TEXT NOT NULL DEFAULT 'proxy', pricing_model TEXT,
            input_token_semantics INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE providers (
            id TEXT NOT NULL, app_type TEXT NOT NULL, name TEXT NOT NULL,
            is_current BOOLEAN NOT NULL DEFAULT 0, PRIMARY KEY (id, app_type)
        );
        CREATE TABLE model_pricing (
            model_id TEXT PRIMARY KEY, display_name TEXT NOT NULL,
            input_cost_per_million TEXT NOT NULL, output_cost_per_million TEXT NOT NULL,
            cache_read_cost_per_million TEXT NOT NULL DEFAULT '0',
            cache_creation_cost_per_million TEXT NOT NULL DEFAULT '0'
        );
        INSERT INTO model_pricing VALUES ('deepseek-v4-flash', 'DeepSeek V4 Flash', '0.44', '0.88', '0.014', '0');
        INSERT INTO model_pricing VALUES ('muse-spark', 'Muse Spark', '0.50', '1.00', '0.05', '0');
        INSERT INTO providers VALUES ('p1', 'claude-desktop', 'DeepSeek', 1);
        INSERT INTO providers VALUES ('p2', 'claude-desktop', 'Nvidia', 0);
        INSERT INTO providers VALUES ('p3', 'claude', 'OpenCode Go', 1);
        """)

        // r7 今日 11:50 session 来源（无 proxy 对应 → 保留）
        try insert(db, id: "r7", offset: -600, app: "claude", model: "deepseek-v4-flash",
                   input: 700, output: 70, cr: 3000, cc: 0, lat: 1500, status: 200,
                   cost: "0", pricing: nil, sem: 0, source: "session_log")
        // r6 今日 11:35 session 来源，与 r1 完全重复 → 应被去重
        try insert(db, id: "r6", offset: -1500, app: "claude", model: "deepseek-v4-flash",
                   input: 1000, output: 200, cr: 50000, cc: 0, lat: 3000, status: 200,
                   cost: "0.005", pricing: "deepseek-v4-flash", sem: 0, source: "session_log")
        // r1 今日 11:30 proxy
        try insert(db, id: "r1", offset: -1800, app: "claude-desktop", model: "deepseek-v4-flash",
                   input: 1000, output: 200, cr: 50000, cc: 0, lat: 3000, status: 200,
                   cost: "0.005", pricing: "deepseek-v4-flash", sem: 2, source: "proxy")
        // r2 今日 10:00 失败请求（无 token）
        try insert(db, id: "r2", offset: -7200, app: "claude-desktop", model: "deepseek-v4-flash",
                   input: 0, output: 0, cr: 0, cc: 0, lat: 2000, status: 429,
                   cost: "0", pricing: "deepseek-v4-flash", sem: 2, source: "proxy")
        // r4 今日 09:00，有定价但真零成本
        try insert(db, id: "r4", offset: -10800, app: "claude", model: "muse-spark",
                   input: 500, output: 50, cr: 2000, cc: 0, lat: 1000, status: 200,
                   cost: "0", pricing: "muse-spark", sem: 0, source: "session_log")
        // r5 今日 08:00 其他 app（codex）→ 应被 app 过滤
        try insert(db, id: "r5", offset: -14400, app: "codex", model: "gpt-5.2",
                   input: 9999, output: 999, cr: 0, cc: 0, lat: 500, status: 200,
                   cost: "0.5", pricing: "gpt-5.2", sem: 1, source: "proxy")
        // r3 昨日 23:00 → 跨日保留、不进今日 KPI
        try insert(db, id: "r3", offset: -46800, app: "claude-desktop", model: "deepseek-v4-pro",
                   input: 3000, output: 300, cr: 10000, cc: 0, lat: 4000, status: 200,
                   cost: "0.01", pricing: nil, sem: 2, source: "proxy")
    }

    private func insert(
        _ db: OpaquePointer?, id: String, offset: TimeInterval, app: String, model: String,
        input: Int, output: Int, cr: Int, cc: Int, lat: Int, status: Int,
        cost: String, pricing: String?, sem: Int, source: String
    ) throws {
        let pricingSQL = pricing.map { "'\($0)'" } ?? "NULL"
        try exec(db, """
        INSERT INTO proxy_request_logs
        (request_id, provider_id, app_type, model, input_tokens, output_tokens,
         cache_read_tokens, cache_creation_tokens, total_cost_usd, latency_ms,
         status_code, created_at, data_source, pricing_model, input_token_semantics)
        VALUES ('\(id)', 'p1', '\(app)', '\(model)', \(input), \(output), \(cr), \(cc),
                '\(cost)', \(lat), \(status), \(epoch(secondsFromNow: offset)), '\(source)', \(pricingSQL), \(sem));
        """)
    }

    private func exec(_ db: OpaquePointer?, _ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
            let message = err.map { String(cString: $0) } ?? "unknown sqlite error"
            sqlite3_free(err)
            throw NSError(domain: "UsageStoreTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    // MARK: - 列表

    func testRecentRequestsNewestFirstWithDedupAndAppFilter() throws {
        try makeFixtureDB()
        let data = UsageStore.fetch(dbPath: dbURL, now: now)

        // r6 被去重、r5 被 app 过滤、r3 跨日仍在列表里
        XCTAssertEqual(data.recentRequests.map(\.id), ["r7", "r1", "r2", "r4", "r3"])
    }

    func testRowDisplayMapping() throws {
        try makeFixtureDB()
        let data = UsageStore.fetch(dbPath: dbURL, now: now)

        let r1 = try XCTUnwrap(data.recentRequests.first { $0.id == "r1" })
        XCTAssertEqual(r1.time, "11:30")
        XCTAssertEqual(r1.model, "deepseek-v4-flash")
        XCTAssertEqual(r1.inputTokens, 1000) // 净输入 = input_tokens 原值（FRESH 语义）
        XCTAssertEqual(r1.outputTokens, 200)
        XCTAssertEqual(r1.durationSeconds, 3.0)
        XCTAssertEqual(r1.status, 200)
        XCTAssertEqual(r1.cost, "$0.0050") // <$0.01 → 四位小数

        let r2 = try XCTUnwrap(data.recentRequests.first { $0.id == "r2" })
        XCTAssertEqual(r2.cost, "$0.00") // 有定价、零消耗
        XCTAssertEqual(r2.status, 429)

        let r3 = try XCTUnwrap(data.recentRequests.first { $0.id == "r3" })
        XCTAssertEqual(r3.cost, "未定价") // pricing_model 为空
    }

    func testIDsStableAcrossFetches() throws {
        try makeFixtureDB()
        let first = UsageStore.fetch(dbPath: dbURL, now: now).recentRequests.map(\.id)
        let second = UsageStore.fetch(dbPath: dbURL, now: now).recentRequests.map(\.id)
        XCTAssertEqual(first, second)
    }

    // MARK: - 今日 KPI

    func testTodaySummary() throws {
        try makeFixtureDB()
        let data = UsageStore.fetch(dbPath: dbURL, now: now)
        let s = data.summary

        // 今日行：r7 + r1 + r2 + r4（r6 去重、r5 过滤、r3 昨日）
        // 净输入 2200 / 输出 320 / 缓存读 55000 → total 57520
        XCTAssertEqual(s.totalTokens, "57.5K")
        // 55000 / (2200 + 55000) = 96.2%
        XCTAssertEqual(s.cacheRate, "96.2%")
        XCTAssertEqual(s.calls, "4次")
        // 0 + 0.005 + 0 + 0（<$0.01 → 四位）
        XCTAssertEqual(s.cost, "$0.0050")
    }

    // MARK: - footer

    func testCacheSavedAndLastRequestTime() throws {
        try makeFixtureDB()
        let data = UsageStore.fetch(dbPath: dbURL, now: now)

        XCTAssertEqual(data.footer.cacheReadTotal, 55000)
        // r7: 3000/1e6×(0.44−0.014) + r1: 50000/1e6×0.426 + r4: 2000/1e6×(0.50−0.05)
        XCTAssertEqual(data.footer.savedUSD, 0.023478, accuracy: 1e-6)
        let last = try XCTUnwrap(data.footer.lastRequestAt)
        XCTAssertEqual(last.timeIntervalSince1970,
                       now.addingTimeInterval(-600).timeIntervalSince1970, accuracy: 1)
    }

    // MARK: - provider

    func testProviderNamePicksCurrentClaudeDesktop() throws {
        try makeFixtureDB()
        XCTAssertEqual(UsageStore.fetch(dbPath: dbURL, now: now).providerName, "DeepSeek")
    }

    // MARK: - 空态

    func testMissingDatabaseReturnsEmptyWithoutCrash() {
        let missing = dirURL.appendingPathComponent("does-not-exist.db")
        let data = UsageStore.fetch(dbPath: missing, now: now)
        XCTAssertTrue(data.recentRequests.isEmpty)
        XCTAssertNil(data.providerName)
        XCTAssertEqual(data.summary, TokenSummary.empty)
        XCTAssertEqual(data.footer.cacheReadTotal, 0)
        XCTAssertNil(data.footer.lastRequestAt)
    }

    func testEmptyTablesReturnEmpty() throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
        try exec(db, """
        CREATE TABLE proxy_request_logs (request_id TEXT PRIMARY KEY, provider_id TEXT, app_type TEXT,
            model TEXT, input_tokens INTEGER DEFAULT 0, output_tokens INTEGER DEFAULT 0,
            cache_read_tokens INTEGER DEFAULT 0, cache_creation_tokens INTEGER DEFAULT 0,
            total_cost_usd TEXT DEFAULT '0', latency_ms INTEGER DEFAULT 0, status_code INTEGER DEFAULT 0,
            created_at INTEGER DEFAULT 0, data_source TEXT DEFAULT 'proxy', pricing_model TEXT,
            input_token_semantics INTEGER DEFAULT 0);
        CREATE TABLE providers (id TEXT, app_type TEXT, name TEXT, is_current INTEGER DEFAULT 0);
        CREATE TABLE model_pricing (model_id TEXT PRIMARY KEY, display_name TEXT, input_cost_per_million TEXT,
            output_cost_per_million TEXT, cache_read_cost_per_million TEXT, cache_creation_cost_per_million TEXT);
        """)
        sqlite3_close(db)

        let data = UsageStore.fetch(dbPath: dbURL, now: now)
        XCTAssertTrue(data.recentRequests.isEmpty)
        XCTAssertNil(data.providerName)
        XCTAssertEqual(data.summary, TokenSummary.empty)
    }
}
