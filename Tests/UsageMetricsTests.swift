import SQLite3
import XCTest
@testable import NotchEvery

/// 今日用量口径：调用次数不过滤、Token 与模型榜只算有消耗的、占比分母取全量。
final class UsageMetricsTests: XCTestCase {

    // MARK: - 共享夹具（cc-switch.db schema）
    // 与 AntigravityProxyStoreTests 中的同名私有辅助重复：刻意不抽公共层，
    // 让每个测试文件自带一套 schema，改一处口径不会同时波及两套断言。

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

    private func openTempDB(fileName: String) throws -> (url: URL, db: OpaquePointer?) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent(fileName)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
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

    // MARK: - 口径

    func testCallsCountAllRowsWhileTokensAndModelsSkipZeroUsage() throws {
        let (dbURL, db) = try openTempDB(fileName: "cc-switch.db")
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }

        let ts = todayNoonTimestamp
        // 7 条有消耗行 + 2 条 0 token 行（其中一条落在 m-a 上）。
        // 全量 token = 5000+1000+300+4000+30+2000+1000 = 13330；top5 之和 = 13300
        XCTAssertEqual(sqlite3_exec(db, """
        INSERT INTO providers (id, name, app_type, is_current) VALUES ('p1', '本地反代集束', 'claude-desktop', 1);
        \(insertLogSQL("""
        ('r1', 'p1', 'claude-desktop', 'm-a', 'claude-opus-5', 5000, 0, 0, '0.001', 200, 1000, \(ts)),
        ('r2', 'p1', 'claude-desktop', 'm-a', 'claude-opus-5', 1000, 0, 0, '0.001', 200, 1000, \(ts - 10)),
        ('r3', 'p1', 'claude-desktop', 'm-b', 'claude-opus-5', 100, 100, 100, '0.002', 200, 1000, \(ts - 20)),
        ('r4', 'p1', 'claude-desktop', 'm-c', 'claude-opus-5', 4000, 0, 0, '0.004', 200, 1000, \(ts - 30)),
        ('r5', 'p1', 'claude-desktop', 'm-d', 'claude-opus-5', 10, 10, 10, '0.008', 200, 1000, \(ts - 40)),
        ('r6', 'p1', 'claude-desktop', 'm-e', 'claude-opus-5', 2000, 0, 0, '0.016', 200, 1000, \(ts - 50)),
        ('r7', 'p1', 'claude-desktop', 'm-f', 'claude-opus-5', 1000, 0, 0, '0.032', 200, 1000, \(ts - 60)),
        ('r-zero1', 'p1', 'claude-desktop', 'm-zero', 'claude-opus-5', 0, 0, 0, '0.0', 500, 1000, \(ts - 70)),
        ('r-zero2', 'p1', 'claude-desktop', 'm-a', 'claude-opus-5', 0, 0, 0, '0.0', 500, 1000, \(ts - 80))
        """))
        """, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        let data = CCSwitchUsageStore.fetch(dbPath: dbURL)

        // 1. 调用次数不过滤：零 token 的失败请求同样算一次调用
        XCTAssertEqual(data.summary.calls, "9次")

        // 2. 今日全量 token = 所有行 input+output+cache_read 之和
        XCTAssertEqual(data.todayTotalTokens, 13330)

        // 3. 模型榜只统计有消耗的，且列表截断到 5 条；活跃模型数不截断
        XCTAssertEqual(data.modelUsages.count, 5)
        XCTAssertEqual(data.activeModelCount, 6)
        XCTAssertEqual(data.modelUsages.map(\.model), ["m-a", "m-c", "m-e", "m-f", "m-b"])
        XCTAssertFalse(data.modelUsages.contains { $0.model == "m-zero" })

        // 4. 占比分母是全量 13330 而非 top5 的 13300：
        //    误用 top5 之和时占比之和恰好 1.0，故必须断言「严格小于 1」并逐条校验分母
        let top5Tokens = data.modelUsages.reduce(0) { $0 + $1.totalTokens }
        XCTAssertEqual(top5Tokens, 13300)
        XCTAssertLessThan(data.modelUsages.reduce(0.0) { $0 + $1.shareFraction }, 1.0)
        for item in data.modelUsages {
            XCTAssertEqual(
                item.shareFraction,
                Double(item.totalTokens) / Double(data.todayTotalTokens),
                accuracy: 1e-12,
                "\(item.model) 的占比分母不是今日全量 token"
            )
        }
    }

    func testRecentRequestColumnsSurviveCostColumnRemoval() throws {
        let (dbURL, db) = try openTempDB(fileName: "cc-switch.db")
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }

        let ts = todayNoonTimestamp
        // status_code 与 latency_ms 取互不相同且都非零：SELECT 里删掉 cost 列后若索引没左移，
        // status 会读到耗时、accountEmail 会读到状态码——三者都会在此处对不上
        XCTAssertEqual(sqlite3_exec(db, """
        INSERT INTO providers (id, name, app_type, is_current) VALUES ('p1', 'prov-idx', 'claude-desktop', 1);
        \(insertLogSQL("('idx-1', 'p1', 'claude-desktop', 'm-idx', 'claude-opus-5', 321, 0, 0, '0.5', 418, 1234, \(ts))"))
        """, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        let data = CCSwitchUsageStore.fetch(dbPath: dbURL)
        let req = try XCTUnwrap(data.recentRequests.first)

        XCTAssertEqual(req.id, "idx-1")
        XCTAssertEqual(req.status, 418)
        XCTAssertEqual(req.durationSeconds, 1.234, accuracy: 1e-9)
        XCTAssertEqual(req.accountEmail, "prov-idx")
        XCTAssertEqual(req.inputTokens, 321)
    }

    // MARK: - @Published 接入层

    func testRefreshPublishesTodayTotals() {
        let store = UsageStore(interval: 3600)
        let before = CCSwitchUsageStore.fetch(dbPath: CCSwitchUsageStore.defaultDBPath)

        store.refresh()
        // refresh() 在后台队列抓库、回主线程发布：转一小段 runloop 让它落地
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        // 真实库可能被别的进程并发写入，故用区间而非等值。
        // 漏掉 refresh() 里的赋值时 store 侧恒为 0，今天有数据就会被下界抓住；
        // 库为空时 before == after == store == 0，本条退化成冒烟检查。
        let after = CCSwitchUsageStore.fetch(dbPath: CCSwitchUsageStore.defaultDBPath)
        XCTAssertGreaterThanOrEqual(store.todayTotalTokens, before.todayTotalTokens)
        XCTAssertLessThanOrEqual(store.todayTotalTokens, after.todayTotalTokens)
        XCTAssertGreaterThanOrEqual(store.activeModelCount, before.activeModelCount)
        XCTAssertLessThanOrEqual(store.activeModelCount, after.activeModelCount)
    }
}
