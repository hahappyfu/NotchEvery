import SQLite3
import XCTest
@testable import NotchEvery

final class AntigravityProxyStoreTests: XCTestCase {
    func testQueryAntigravityProxyLogs() throws {
        // 创建临时数据库模拟 request_logs
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbURL = tempDir.appendingPathComponent("proxy_logs.db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)

        let createTable = """
        CREATE TABLE request_logs (
            id TEXT PRIMARY KEY,
            timestamp INTEGER,
            method TEXT,
            url TEXT,
            status INTEGER,
            duration INTEGER,
            model TEXT,
            error TEXT,
            request_body TEXT,
            response_body TEXT,
            input_tokens INTEGER,
            output_tokens INTEGER,
            account_email TEXT,
            mapped_model TEXT,
            protocol TEXT,
            client_ip TEXT,
            username TEXT,
            cached_tokens INTEGER
        );
        """
        XCTAssertEqual(sqlite3_exec(db, createTable, nil, nil, nil), SQLITE_OK)

        // 插入两条测试记录
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let insertSQL = """
        INSERT INTO request_logs (id, timestamp, method, url, status, duration, model, input_tokens, output_tokens, cached_tokens, account_email)
        VALUES
        ('req-1', \(nowMs), 'POST', '/v1', 200, 1500, 'gemini-3.8-flash-high', 1000, 200, 500, 'test1@gmail.com'),
        ('req-2', \(nowMs - 5000), 'POST', '/v1', 200, 2500, 'gemini-3.8-flash-high', 2000, 400, 1000, 'test2@gmail.com');
        """
        XCTAssertEqual(sqlite3_exec(db, insertSQL, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        let store = AntigravityProxyStore(dbPath: dbURL, interval: 60)
        let data = store.fetchSnapshot()

        XCTAssertEqual(data.recentRequests.count, 2)
        XCTAssertEqual(data.recentRequests[0].id, "req-1")
        XCTAssertEqual(data.recentRequests[0].durationSeconds, 1.5)
        XCTAssertEqual(data.recentRequests[0].status, 200)
        XCTAssertEqual(data.recentRequests[0].accountEmail, "test1@gmail.com")
        XCTAssertEqual(data.summary.totalTokens, "3,600")
        XCTAssertEqual(data.summary.calls, "2")
        XCTAssertEqual(data.summary.cacheRate, "50.0%")
        XCTAssertEqual(data.cacheRateFraction, 0.5, accuracy: 0.001)
    }

    func testDualSourceSwitching() {
        XCTAssertEqual(UsageStore.activeSource, .antigravityTools)
    }

    func testMissingDatabaseReturnsEmpty() {
        let missingURL = FileManager.default.temporaryDirectory.appendingPathComponent("non_existent_\(UUID().uuidString).db")
        let store = AntigravityProxyStore(dbPath: missingURL, interval: 60)
        let data = store.fetchSnapshot()
        XCTAssertEqual(data.recentRequests.count, 0)
        XCTAssertEqual(data.summary, .empty)
    }

    func testWALModeReadOnlyAccess() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            // 恢复权限以便清理
            try? FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: tempDir.path)
            let dbFile = tempDir.appendingPathComponent("wal_test.db")
            try? FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: dbFile.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

        let dbURL = tempDir.appendingPathComponent("wal_test.db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)

        // 显式开启 WAL 模式
        XCTAssertEqual(sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil), SQLITE_OK)

        let createTable = """
        CREATE TABLE request_logs (
            id TEXT PRIMARY KEY,
            timestamp INTEGER,
            method TEXT,
            url TEXT,
            status INTEGER,
            duration INTEGER,
            model TEXT,
            error TEXT,
            request_body TEXT,
            response_body TEXT,
            input_tokens INTEGER,
            output_tokens INTEGER,
            account_email TEXT,
            mapped_model TEXT,
            protocol TEXT,
            client_ip TEXT,
            username TEXT,
            cached_tokens INTEGER
        );
        """
        XCTAssertEqual(sqlite3_exec(db, createTable, nil, nil, nil), SQLITE_OK)

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let insertSQL = """
        INSERT INTO request_logs (id, timestamp, method, url, status, duration, model, input_tokens, output_tokens, cached_tokens, account_email)
        VALUES
        ('wal-req-1', \(nowMs), 'POST', '/v1', 200, 1000, 'gemini-3.8-flash-high', 500, 100, 200, 'wal@test.com');
        """
        XCTAssertEqual(sqlite3_exec(db, insertSQL, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        // 模拟只读环境：将目录及数据库文件设置为只读权限 (目录 0555，文件 0444)
        // 在标准 WAL 模式下，未开启 immutable=1 会因无法创建/写入 -shm 共享内存文件而报 SQLITE_CANTOPEN (14)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: dbURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: tempDir.path)

        let store = AntigravityProxyStore(dbPath: dbURL, interval: 60)
        let data = store.fetchSnapshot()

        // 验证只读模式使用 immutable=1 能够成功读取数据，不返回空数据
        XCTAssertEqual(data.recentRequests.count, 1)
        XCTAssertEqual(data.recentRequests.first?.id, "wal-req-1")
        XCTAssertEqual(data.recentRequests.first?.accountEmail, "wal@test.com")
        XCTAssertEqual(data.summary.calls, "1")
    }
}
