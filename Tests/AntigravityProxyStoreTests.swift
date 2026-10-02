import SQLite3
import XCTest
@testable import NotchEvery

/// 类名沿用旧测试 target 标识；现全部针对 CCSwitchUsageStore（~/.cc-switch/cc-switch.db 数据源）。
final class AntigravityProxyStoreTests: XCTestCase {

    // MARK: - 共享夹具（cc-switch.db schema）

    private let ccSchema = """
    CREATE TABLE providers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        app_type TEXT NOT NULL,
        is_current BOOLEAN NOT NULL DEFAULT 0
    );
    CREATE TABLE proxy_request_logs (
        request_id TEXT PRIMARY KEY,
        provider_id TEXT NOT NULL,
        app_type TEXT NOT NULL,
        model TEXT NOT NULL,
        request_model TEXT,
        input_tokens INTEGER NOT NULL DEFAULT 0,
        output_tokens INTEGER NOT NULL DEFAULT 0,
        cache_read_tokens INTEGER NOT NULL DEFAULT 0,
        total_cost_usd TEXT NOT NULL DEFAULT '0',
        status_code INTEGER NOT NULL DEFAULT 200,
        latency_ms INTEGER NOT NULL DEFAULT 1000,
        duration_ms INTEGER,
        created_at INTEGER NOT NULL
    );
    """

    /// 当天正午时间戳：避开午夜边界，保证数据必然落在「今天」窗口内
    private var todayNoonTimestamp: Int64 {
        Int64(Calendar.current.startOfDay(for: Date()).addingTimeInterval(43200).timeIntervalSince1970)
    }

    private func openTempDB(fileName: String, wal: Bool = false) throws -> (url: URL, db: OpaquePointer?) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent(fileName)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
        if wal {
            XCTAssertEqual(sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil), SQLITE_OK)
        }
        XCTAssertEqual(sqlite3_exec(db, ccSchema, nil, nil, nil), SQLITE_OK)
        return (dbURL, db)
    }

    private func insertLogSQL(_ rows: String) -> String {
        """
        INSERT INTO proxy_request_logs
        (request_id, provider_id, app_type, model, request_model, input_tokens, output_tokens, cache_read_tokens, total_cost_usd, status_code, latency_ms, created_at)
        VALUES \(rows);
        """
    }

    // MARK: - 缺库 / 只读降级

    func testMissingDatabaseReturnsEmpty() {
        let missingURL = FileManager.default.temporaryDirectory.appendingPathComponent("non_existent_\(UUID().uuidString).db")
        let data = CCSwitchUsageStore.fetch(dbPath: missingURL)
        XCTAssertEqual(data, .empty)
    }

    func testWALModeReadOnlyAccess() throws {
        let (dbURL, db) = try openTempDB(fileName: "wal_test.db", wal: true)
        let tempDir = dbURL.deletingLastPathComponent()
        defer {
            // 恢复权限以便清理
            try? FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: tempDir.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: dbURL.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

        let ts = todayNoonTimestamp
        XCTAssertEqual(sqlite3_exec(db, """
        INSERT INTO providers (id, name, app_type, is_current) VALUES ('p1', 'wal-prov', 'claude-desktop', 1);
        \(insertLogSQL("('wal-req-1', 'p1', 'claude-desktop', 'gemini-3.8-flash', 'claude-opus-5', 500, 100, 200, '0.001', 200, 1000, \(ts))"))
        """, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        // 模拟只读环境：目录 0555 + 文件 0444，无法创建/写 -shm；
        // 普通只读连接探针失败，必须降级 immutable=1 读主库（关库时 WAL 已自动 checkpoint）
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: dbURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: tempDir.path)

        let data = CCSwitchUsageStore.fetch(dbPath: dbURL)
        XCTAssertEqual(data.recentRequests.count, 1)
        XCTAssertEqual(data.recentRequests.first?.id, "wal-req-1")
        XCTAssertEqual(data.recentRequests.first?.accountEmail, "wal-prov")
        XCTAssertEqual(data.summary.calls, "1次")
    }

    func testWALUncheckpointedRowsVisibleWhileWriterAlive() throws {
        // 真实场景：写方进程持续存活，最新记录只存在于 WAL，主库文件要等 checkpoint 才更新。
        // 读取方必须能看到 WAL 里的未合并数据。
        let (dbURL, writer) = try openTempDB(fileName: "cc-switch.db", wal: true)
        defer {
            sqlite3_close(writer)
            try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent())
        }

        let ts = todayNoonTimestamp
        XCTAssertEqual(sqlite3_exec(writer, """
        INSERT INTO providers (id, name, app_type, is_current) VALUES ('p1', 'wal-live-prov', 'claude-desktop', 1);
        \(insertLogSQL("('wal-live-1', 'p1', 'claude-desktop', 'gemini-3.8-flash', 'claude-opus-5', 500, 100, 200, '0.001', 200, 1000, \(ts))"))
        """, nil, nil, nil), SQLITE_OK)

        // 写方连接在 fetch 期间保持打开：关掉最后一个连接会自动 checkpoint，测试就失去意义了
        let data = CCSwitchUsageStore.fetch(dbPath: dbURL)

        XCTAssertEqual(data.recentRequests.count, 1)
        XCTAssertEqual(data.recentRequests.first?.id, "wal-live-1")
        XCTAssertEqual(data.recentRequests.first?.accountEmail, "wal-live-prov")
        XCTAssertEqual(data.summary.calls, "1次")
        XCTAssertEqual(data.summary.totalTokens, "800") // 500 + 100 + 200
        XCTAssertEqual(data.footer.lastRequestAt, Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    func testReadOnlyFallbackToImmutableWhenSHMUnavailable() throws {
        // 模拟写方退出/清理导致 -shm 缺失且目录只读（无法创建 -shm）的错误码 14 场景：
        // 探针检测到 prepare 失败后平滑降级 immutable=1，读已合并进主库的数据。
        let (dbURL, writer) = try openTempDB(fileName: "cc-switch.db", wal: true)
        let tempDir = dbURL.deletingLastPathComponent()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

        let ts = todayNoonTimestamp
        XCTAssertEqual(sqlite3_exec(writer, """
        INSERT INTO providers (id, name, app_type, is_current) VALUES ('p1', 'fallback-prov', 'claude-desktop', 1);
        \(insertLogSQL("('fallback-1', 'p1', 'claude-desktop', 'gemini-3.8-flash', 'claude-opus-5', 300, 100, 50, '0.001', 200, 800, \(ts))"))
        """, nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_wal_checkpoint_v2(writer, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil), SQLITE_OK)
        sqlite3_close(writer)

        try? FileManager.default.removeItem(atPath: dbURL.path + "-shm")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: tempDir.path)

        let data = CCSwitchUsageStore.fetch(dbPath: dbURL)
        XCTAssertEqual(data.recentRequests.count, 1)
        XCTAssertEqual(data.recentRequests.first?.id, "fallback-1")
        XCTAssertEqual(data.recentRequests.first?.accountEmail, "fallback-prov")
        XCTAssertEqual(data.summary.calls, "1次")
        XCTAssertEqual(data.summary.totalTokens, "450") // 300 + 100 + 50
    }

    // MARK: - 查询与汇总

    func testCCSwitchUsageStoreQueryAndSummary() throws {
        let (dbURL, db) = try openTempDB(fileName: "cc-switch.db")
        defer {
            sqlite3_close(db)
            try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent())
        }

        let now = Date()
        let nowTimestamp = Int64(now.timeIntervalSince1970)
        let yesterdayTimestamp = nowTimestamp - 86400 * 2

        XCTAssertEqual(sqlite3_exec(db, """
        INSERT INTO providers (id, name, app_type, is_current) VALUES ('p1', '本地反代集束', 'claude-desktop', 1);
        \(insertLogSQL("""
        ('req-1', 'p1', 'claude-desktop', 'gemini-3.8-flash', 'claude-opus-5', 2000, 100, 8000, '0.015', 200, 3200, \(nowTimestamp)),
        ('req-2', 'p1', 'claude-desktop', 'Qwen3.8-Flash', 'claude-sonnet-5', 4000, 200, 6000, '0.008', 200, 1500, \(nowTimestamp - 10)),
        ('req-old', 'p1', 'claude-desktop', 'deepseek-v3', 'claude-sonnet-5', 5000, 500, 1000, '0.010', 200, 2000, \(yesterdayTimestamp))
        """))
        """, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        let data = CCSwitchUsageStore.fetch(dbPath: dbURL, now: now)
        XCTAssertEqual(data.providerName, "本地反代集束")
        XCTAssertEqual(data.summary.calls, "2次")
        XCTAssertEqual(data.recentRequests.count, 2)
        XCTAssertEqual(data.recentRequests[0].model, "gemini-3.8-flash")
        XCTAssertEqual(data.recentRequests[0].accountEmail, "本地反代集束")
        XCTAssertEqual(data.recentRequests[0].inputTokens, 2000)
        XCTAssertEqual(data.recentRequests[0].outputTokens, 100)
        XCTAssertEqual(data.recentRequests[0].cachedTokens, 8000)
        XCTAssertEqual(data.recentRequests[1].model, "Qwen3.8-Flash")
        XCTAssertEqual(data.footer.cacheReadTotal, 14000)
    }

    func testProviderFallbackToLatestRequestWhenNoCurrentProvider() throws {
        // 无 is_current=1 行时：providerId 保持 nil，providerName 回退为最近一次请求的供应商标识；
        // provider_id 在 providers 表无对应行时 COALESCE 回退到 id 本身。
        let (dbURL, db) = try openTempDB(fileName: "cc-switch.db")
        defer {
            sqlite3_close(db)
            try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent())
        }

        let ts = todayNoonTimestamp
        XCTAssertEqual(sqlite3_exec(db, """
        INSERT INTO providers (id, name, app_type, is_current) VALUES ('p1', 'P1', 'claude-desktop', 0);
        \(insertLogSQL("""
        ('req-1', 'p-ghost', 'claude-desktop', 'm1', 'claude-opus-5', 100, 10, 0, '0.001', 200, 1000, \(ts)),
        ('req-2', 'p1', 'claude-desktop', 'm2', 'claude-opus-5', 200, 20, 0, '0.002', 200, 1000, \(ts - 10))
        """))
        """, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        let data = CCSwitchUsageStore.fetch(dbPath: dbURL)
        XCTAssertNil(data.providerId)
        XCTAssertEqual(data.providerName, "p-ghost")
        XCTAssertEqual(data.recentRequests.count, 2)
        XCTAssertEqual(data.recentRequests[0].accountEmail, "p-ghost")
        XCTAssertEqual(data.recentRequests[1].accountEmail, "P1")
    }

    // MARK: - 今日模型用量分布

    func testQueryModelUsagesAggregationAndShare() throws {
        let (dbURL, db) = try openTempDB(fileName: "cc-switch.db")
        defer {
            sqlite3_close(db)
            try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent())
        }

        let ts = todayNoonTimestamp
        let yesterday = ts - 86400
        // 今天 6 个模型 + 1 条 0 Token 失败行 + 昨天干扰行；m-a 两行验证 calls 聚合
        // dayTotal = (5000+1000) + 300 + 4000 + 30 + 2000 + 1000 = 13330
        XCTAssertEqual(sqlite3_exec(db, insertLogSQL("""
        ('r1', 'p1', 'claude-desktop', 'm-a', 'claude-opus-5', 5000, 0, 0, '0.001', 200, 1000, \(ts)),
        ('r2', 'p1', 'claude-desktop', 'm-a', 'claude-opus-5', 1000, 0, 0, '0.001', 200, 1000, \(ts - 10)),
        ('r3', 'p1', 'claude-desktop', 'm-b', 'claude-opus-5', 100, 100, 100, '0.002', 200, 1000, \(ts - 20)),
        ('r4', 'p1', 'claude-desktop', 'm-c', 'claude-opus-5', 4000, 0, 0, '0.004', 200, 1000, \(ts - 30)),
        ('r5', 'p1', 'claude-desktop', 'm-d', 'claude-opus-5', 10, 10, 10, '0.008', 200, 1000, \(ts - 40)),
        ('r6', 'p1', 'claude-desktop', 'm-e', 'claude-opus-5', 2000, 0, 0, '0.016', 200, 1000, \(ts - 50)),
        ('r7', 'p1', 'claude-desktop', 'm-f', 'claude-opus-5', 1000, 0, 0, '0.032', 200, 1000, \(ts - 60)),
        ('r-zero', 'p1', 'claude-desktop', 'm-zero', 'claude-opus-5', 0, 0, 0, '0.0', 500, 1000, \(ts - 70)),
        ('r-old', 'p1', 'claude-desktop', 'm-old', 'claude-opus-5', 9000, 0, 0, '1.0', 200, 1000, \(yesterday))
        """), nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        let data = CCSwitchUsageStore.fetch(dbPath: dbURL)

        // 只聚合当天且有消耗的模型，且只取 top5（m-d 总量 30 被切掉，m-zero 0消耗被过滤，m-old 属于昨天被过滤）
        XCTAssertEqual(data.modelUsages.count, 5)
        XCTAssertEqual(data.modelUsages.map(\.model), ["m-a", "m-c", "m-e", "m-f", "m-b"])
        XCTAssertFalse(data.modelUsages.contains(where: { $0.model == "m-zero" }))

        let first = data.modelUsages[0]
        XCTAssertEqual(first.model, "m-a")
        XCTAssertEqual(first.calls, 2)
        XCTAssertEqual(first.totalTokens, 6000) // 5000 + 1000，input+output+cacheRead
        XCTAssertEqual(first.cachedTokens, 0)
        XCTAssertEqual(first.shareFraction, 6000.0 / 13330.0, accuracy: 1e-9)

        let last = data.modelUsages[4]
        XCTAssertEqual(last.model, "m-b")
        XCTAssertEqual(last.totalTokens, 300)
        XCTAssertEqual(last.cachedTokens, 100)
        XCTAssertEqual(last.shareFraction, 300.0 / 13330.0, accuracy: 1e-9)

        for item in data.modelUsages {
            XCTAssertTrue(item.shareFraction >= 0.0 && item.shareFraction <= 1.0)
        }

        XCTAssertEqual(data.totalCostTodayUSD, 0.064, accuracy: 1e-9) // 0.002+0.002+0.004+0.008+0.016+0.032
    }

    // MARK: - 文案格式化

    func testFormatCostBoundaries() {
        XCTAssertEqual(CCSwitchUsageStore.formatCost(usd: 0, priced: true), "$0.00")
        XCTAssertEqual(CCSwitchUsageStore.formatCost(usd: 0.005, priced: true), "$0.0050")
        XCTAssertEqual(CCSwitchUsageStore.formatCost(usd: 0.0099, priced: true), "$0.0099")
        XCTAssertEqual(CCSwitchUsageStore.formatCost(usd: 0.01, priced: true), "$0.01")
        XCTAssertEqual(CCSwitchUsageStore.formatCost(usd: 1.5, priced: true), "$1.50")
        XCTAssertEqual(CCSwitchUsageStore.formatCost(usd: 0.5, priced: false), "未定价")
    }
}
