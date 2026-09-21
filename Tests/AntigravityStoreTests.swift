import XCTest
import SQLite3
@testable import NotchEvery

final class AntigravityStoreTests: XCTestCase {
    func testFormatCountdown() {
        let now = Date(timeIntervalSince1970: 1789370000)
        // 已过期或就绪
        XCTAssertEqual(AntigravityStore.formatCountdown(from: nil, now: now), "已就绪")
        XCTAssertEqual(AntigravityStore.formatCountdown(from: Date(timeIntervalSince1970: 1789369000), now: now), "已就绪")

        // 2小时27分后重置
        let future = Date(timeIntervalSince1970: 1789370000 + 2 * 3600 + 27 * 60)
        XCTAssertEqual(AntigravityStore.formatCountdown(from: future, now: now), "2h27m")

        // 45分钟后重置
        let soon = Date(timeIntervalSince1970: 1789370000 + 45 * 60)
        XCTAssertEqual(AntigravityStore.formatCountdown(from: soon, now: now), "45m")
    }

    func testFormatCountdownCompact() {
        let now = Date(timeIntervalSince1970: 1789370000)
        // 149小时20分 -> 格式化为 6d5h
        let longFuture = Date(timeIntervalSince1970: 1789370000 + 149 * 3600 + 20 * 60)
        XCTAssertEqual(AntigravityStore.formatCountdown(from: longFuture, now: now), "6d5h")

        // 36小时10分 -> 格式化为 36h
        let midFuture = Date(timeIntervalSince1970: 1789370000 + 36 * 3600 + 10 * 60)
        XCTAssertEqual(AntigravityStore.formatCountdown(from: midFuture, now: now), "36h")

        // 3小时15分 -> 格式化为 3h15m
        let shortFuture = Date(timeIntervalSince1970: 1789370000 + 3 * 3600 + 15 * 60)
        XCTAssertEqual(AntigravityStore.formatCountdown(from: shortFuture, now: now), "3h15m")
    }

    func testSelectAccountUpdatesMemoryAndDisk() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let indexFile = tempDir.appendingPathComponent("accounts.json")
        let initialIndexJSON = """
        {
            "current_account_id": "acc-1",
            "accounts": [
                {"id": "acc-1"},
                {"id": "acc-2"}
            ]
        }
        """
        try initialIndexJSON.data(using: .utf8)!.write(to: indexFile)

        let store = AntigravityStore(baseDir: tempDir)
        let acc1 = AntigravityAccount(id: "acc-1", name: "A1", email: "a1@test.com", isCurrent: true, isDisabled: false, percentage: 80, resetTime: nil)
        let acc2 = AntigravityAccount(id: "acc-2", name: "A2", email: "a2@test.com", isCurrent: false, isDisabled: false, percentage: 90, resetTime: nil)

        // 注入初始内存数据（模拟 loadAccounts 完成后）
        let (initialAccounts, currentId) = AntigravityStore.loadAccounts(from: tempDir)
        XCTAssertEqual(currentId, "acc-1")

        // 手动赋值以验证 selectAccount 行为
        store.selectAccount(id: "acc-2")
        XCTAssertEqual(store.currentAccountId, "acc-2")

        // 等待异步磁盘写入
        let exp = expectation(description: "Wait for file write")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) {
            if let data = try? Data(contentsOf: indexFile),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let currentId = json["current_account_id"] as? String {
                XCTAssertEqual(currentId, "acc-2")
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 2.0)
    }

    func testParseAccountDetails() throws {
        let jsonStr = """
        {
          "id": "test-account-1",
          "name": "测试账号",
          "email": "test@example.com",
          "disabled": false,
          "proxy_disabled": false,
          "quota": {
            "models": [
              {
                "name": "gemini-3.1-pro-high",
                "percentage": 85,
                "reset_time": "2026-09-14T15:30:00Z"
              },
              {
                "name": "gemini-3.5-flash-low",
                "percentage": 85,
                "reset_time": "2026-09-14T15:30:00Z"
              }
            ]
          }
        }
        """
        let data = jsonStr.data(using: .utf8)!
        let account = try XCTUnwrap(AntigravityStore.parseAccountFile(data: data, currentAccountId: "test-account-1"))

        XCTAssertEqual(account.id, "test-account-1")
        XCTAssertEqual(account.name, "测试账号")
        XCTAssertEqual(account.email, "test@example.com")
        XCTAssertTrue(account.isCurrent)
        XCTAssertFalse(account.isDisabled)
        XCTAssertEqual(account.percentage, 85)
        XCTAssertNotNil(account.resetTime)
    }

    func testParseAccountsIndex() {
        let jsonStr = """
        {
          "version": "2.0",
          "accounts": [
            { "id": "acc-1", "name": "A1" },
            { "id": "acc-2", "name": "A2" }
          ],
          "current_account_id": "acc-2"
        }
        """
        let data = jsonStr.data(using: .utf8)!
        let index = AntigravityStore.parseIndex(data: data)
        XCTAssertEqual(index?.currentAccountId, "acc-2")
        XCTAssertEqual(index?.accountIds, ["acc-1", "acc-2"])
    }

    func testParseIndexCarriesDisabledAndProxyDisabledFlags() throws {
        let jsonStr = """
        {
          "version": "2.0",
          "accounts": [
            { "id": "acc-1", "disabled": false, "proxy_disabled": true },
            { "id": "acc-2", "disabled": true, "proxy_disabled": false },
            { "id": "acc-3" }
          ],
          "current_account_id": "acc-1"
        }
        """
        let data = jsonStr.data(using: .utf8)!
        let index = try XCTUnwrap(AntigravityStore.parseIndex(data: data))

        XCTAssertEqual(index.flags["acc-1"]?.disabled, false)
        XCTAssertEqual(index.flags["acc-1"]?.proxyDisabled, true)
        XCTAssertEqual(index.flags["acc-2"]?.disabled, true)
        XCTAssertEqual(index.flags["acc-2"]?.proxyDisabled, false)
        // 索引条目缺字段时按未禁用处理
        XCTAssertEqual(index.flags["acc-3"], AntigravityIndex.AccountFlags())
    }

    func testLoadAccountsUsesAccountFileWhenIndexStale() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let accountsDir = tempDir.appendingPathComponent("accounts")
        try FileManager.default.createDirectory(at: accountsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 真实数据场景：索引里 acc-1 proxy_disabled=true，但单账号文件（权威来源）是 false——
        // 说明用户后来在别处改过、索引没同步。应以单账号文件为准，acc-1 判定为未禁用。
        let indexJSON = """
        {
          "version": "2.0",
          "accounts": [
            { "id": "acc-1", "disabled": false, "proxy_disabled": true },
            { "id": "acc-2", "disabled": false, "proxy_disabled": false }
          ],
          "current_account_id": "acc-2"
        }
        """
        try indexJSON.write(to: tempDir.appendingPathComponent("accounts.json"), atomically: true, encoding: .utf8)

        for id in ["acc-1", "acc-2"] {
            let accJSON = """
            {
              "id": "\(id)",
              "email": "\(id)@example.com",
              "name": "\(id)",
              "disabled": false,
              "proxy_disabled": false
            }
            """
            try accJSON.write(to: accountsDir.appendingPathComponent("\(id).json"), atomically: true, encoding: .utf8)
        }

        let (accounts, _) = AntigravityStore.loadAccounts(from: tempDir)
        let acc1 = try XCTUnwrap(accounts.first(where: { $0.id == "acc-1" }))
        XCTAssertFalse(acc1.isProxyDisabled, "单账号文件显式写了 proxy_disabled=false，应覆盖索引的过时 true")
        XCTAssertFalse(acc1.isDisabled)

        let acc2 = try XCTUnwrap(accounts.first(where: { $0.id == "acc-2" }))
        XCTAssertFalse(acc2.isProxyDisabled)
        XCTAssertFalse(acc2.isDisabled)
    }

    func testLoadAccountsFallsBackToIndexWhenAccountFileOmitsFlag() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let accountsDir = tempDir.appendingPathComponent("accounts")
        try FileManager.default.createDirectory(at: accountsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 单账号文件根本没写 proxy_disabled 字段（缺省），此时才用索引兜底
        let indexJSON = """
        {
          "version": "2.0",
          "accounts": [
            { "id": "acc-1", "disabled": false, "proxy_disabled": true }
          ],
          "current_account_id": "acc-1"
        }
        """
        try indexJSON.write(to: tempDir.appendingPathComponent("accounts.json"), atomically: true, encoding: .utf8)

        let acc1JSON = """
        { "id": "acc-1", "email": "acc1@example.com", "name": "acc1" }
        """
        try acc1JSON.write(to: accountsDir.appendingPathComponent("acc-1.json"), atomically: true, encoding: .utf8)

        let (accounts, _) = AntigravityStore.loadAccounts(from: tempDir)
        let acc1 = try XCTUnwrap(accounts.first(where: { $0.id == "acc-1" }))
        XCTAssertTrue(acc1.isProxyDisabled, "单账号文件缺省时，索引值生效")
        XCTAssertTrue(acc1.isDisabled)
    }

    func testLoadAccountsOrMergeOfIndexAndAccountFileFlags() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let accountsDir = tempDir.appendingPathComponent("accounts")
        try FileManager.default.createDirectory(at: accountsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // acc-1：单账号文件 proxy_disabled=true（权威）；acc-2：两边都干净
        let indexJSON = """
        {
          "version": "2.0",
          "accounts": [
            { "id": "acc-1", "disabled": true, "proxy_disabled": false },
            { "id": "acc-2", "disabled": false, "proxy_disabled": false }
          ],
          "current_account_id": "acc-2"
        }
        """
        try indexJSON.write(to: tempDir.appendingPathComponent("accounts.json"), atomically: true, encoding: .utf8)

        let acc1JSON = """
        { "id": "acc-1", "email": "acc1@example.com", "disabled": false, "proxy_disabled": true }
        """
        try acc1JSON.write(to: accountsDir.appendingPathComponent("acc-1.json"), atomically: true, encoding: .utf8)

        let acc2JSON = """
        { "id": "acc-2", "email": "acc2@example.com", "disabled": false, "proxy_disabled": false }
        """
        try acc2JSON.write(to: accountsDir.appendingPathComponent("acc-2.json"), atomically: true, encoding: .utf8)

        let (accounts, _) = AntigravityStore.loadAccounts(from: tempDir)
        let acc1 = try XCTUnwrap(accounts.first(where: { $0.id == "acc-1" }))
        XCTAssertTrue(acc1.isProxyDisabled, "单账号文件显式写了 proxy_disabled=true，以此为准")
        XCTAssertTrue(acc1.isDisabled, "proxy_disabled 为真时 isDisabled 必为真")

        let acc2 = try XCTUnwrap(accounts.first(where: { $0.id == "acc-2" }))
        XCTAssertFalse(acc2.isDisabled)
        XCTAssertFalse(acc2.isProxyDisabled)
    }

    func testDisabledAndClampedPercentage() throws {
        let jsonStr = """
        {
          "id": "disabled-account",
          "email": "disabled@example.com",
          "disabled": false,
          "proxy_disabled": true,
          "quota": {
            "models": [
              {
                "name": "gemini-pro",
                "percentage": 150
              }
            ]
          }
        }
        """
        let data = jsonStr.data(using: .utf8)!
        let account = try XCTUnwrap(AntigravityStore.parseAccountFile(data: data, currentAccountId: "other"))
        XCTAssertEqual(account.name, "disabled@example.com")
        XCTAssertTrue(account.isDisabled)
        XCTAssertFalse(account.isCurrent)
        XCTAssertEqual(account.percentage, 100) // 封顶 100
    }

    func testSymmetricRearrangeStandardPool() {
        // 空数组
        XCTAssertTrue(AntigravityAccountsCardView.symmetricRearrange(accounts: []).isEmpty)

        // 单账号
        let singleAcc = AntigravityAccount(id: "acc-0", name: "A0", email: "a0@test.com", isCurrent: true, isDisabled: false, percentage: 80, resetTime: nil)
        let singleResult = AntigravityAccountsCardView.symmetricRearrange(accounts: [singleAcc])
        XCTAssertEqual(singleResult.count, 1)
        XCTAssertEqual(singleResult[0].account.id, "acc-0")
        XCTAssertEqual(singleResult[0].logicalDistance, 0)

        // 标准 5 账号池：acc-cur (50%, current), acc-high (95%), acc-midhigh (80%), acc-midlow (30%), acc-low (10%)
        let cur = AntigravityAccount(id: "cur", name: "Current", email: "cur@test.com", isCurrent: true, isDisabled: false, percentage: 50, resetTime: nil)
        let high = AntigravityAccount(id: "high", name: "High", email: "high@test.com", isCurrent: false, isDisabled: false, percentage: 95, resetTime: nil)
        let midHigh = AntigravityAccount(id: "midHigh", name: "MidHigh", email: "midhigh@test.com", isCurrent: false, isDisabled: false, percentage: 80, resetTime: nil)
        let midLow = AntigravityAccount(id: "midLow", name: "MidLow", email: "midlow@test.com", isCurrent: false, isDisabled: false, percentage: 30, resetTime: nil)
        let low = AntigravityAccount(id: "low", name: "Low", email: "low@test.com", isCurrent: false, isDisabled: false, percentage: 10, resetTime: nil)

        let pool = [midLow, high, cur, low, midHigh]
        let arranged = AntigravityAccountsCardView.symmetricRearrange(accounts: pool)

        XCTAssertEqual(arranged.count, 5)
        // 期望序列：[-2: low(10%), -1: high(95%), 0: cur(50%), 1: midHigh(80%), 2: midLow(30%)]
        XCTAssertEqual(arranged[0].account.id, "low")
        XCTAssertEqual(arranged[0].logicalDistance, -2)

        XCTAssertEqual(arranged[1].account.id, "high")
        XCTAssertEqual(arranged[1].logicalDistance, -1)

        XCTAssertEqual(arranged[2].account.id, "cur")
        XCTAssertEqual(arranged[2].logicalDistance, 0)

        XCTAssertEqual(arranged[3].account.id, "midHigh")
        XCTAssertEqual(arranged[3].logicalDistance, 1)

        XCTAssertEqual(arranged[4].account.id, "midLow")
        XCTAssertEqual(arranged[4].logicalDistance, 2)
    }

    func testSymmetricRearrangeWithActiveTime() {
        let t0 = Date(timeIntervalSince1970: 1789500000)
        let t1 = Date(timeIntervalSince1970: 1789501000) // 活跃第 4
        let t2 = Date(timeIntervalSince1970: 1789502000) // 活跃第 3
        let t3 = Date(timeIntervalSince1970: 1789503000) // 活跃第 2
        let t4 = Date(timeIntervalSince1970: 1789504000) // 活跃最新（第 1，居中）

        let accOldest = AntigravityAccount(id: "a0", name: "A0", email: "a0@test.com", isCurrent: false, isDisabled: false, percentage: 100, resetTime: nil, lastActiveTime: t0)
        let acc4th = AntigravityAccount(id: "a1", name: "A1", email: "a1@test.com", isCurrent: false, isDisabled: false, percentage: 90, resetTime: nil, lastActiveTime: t1)
        let acc3rd = AntigravityAccount(id: "a2", name: "A2", email: "a2@test.com", isCurrent: false, isDisabled: false, percentage: 80, resetTime: nil, lastActiveTime: t2)
        let acc2nd = AntigravityAccount(id: "a3", name: "A3", email: "a3@test.com", isCurrent: false, isDisabled: false, percentage: 70, resetTime: nil, lastActiveTime: t3)
        let accNewest = AntigravityAccount(id: "a4", name: "A4", email: "A4", isCurrent: true, isDisabled: false, percentage: 20, resetTime: nil, lastActiveTime: t4)

        // 故意乱序输入
        let pool = [acc3rd, accOldest, accNewest, acc2nd, acc4th]
        let arranged = AntigravityAccountsCardView.symmetricRearrange(accounts: pool)

        XCTAssertEqual(arranged.count, 5)
        // 期望：
        // distance 0 (中心): accNewest (a4, 最新活跃)
        // distance -1 (左内翼): acc2nd (a3, 第 2 新)
        // distance 1 (右内翼): acc3rd (a2, 第 3 新)
        // distance -2 (左外翼): accOldest (a0, 最老)
        // distance 2 (右外翼): acc4th (a1, 第 4 新)
        XCTAssertEqual(arranged[0].account.id, "a0")
        XCTAssertEqual(arranged[0].logicalDistance, -2)

        XCTAssertEqual(arranged[1].account.id, "a3")
        XCTAssertEqual(arranged[1].logicalDistance, -1)

        XCTAssertEqual(arranged[2].account.id, "a4")
        XCTAssertEqual(arranged[2].logicalDistance, 0)

        XCTAssertEqual(arranged[3].account.id, "a2")
        XCTAssertEqual(arranged[3].logicalDistance, 1)

        XCTAssertEqual(arranged[4].account.id, "a1")
        XCTAssertEqual(arranged[4].logicalDistance, 2)
    }

    func testLoadAccountsWithDynamicActiveRouting() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let accountsDir = tempDir.appendingPathComponent("accounts")
        try FileManager.default.createDirectory(at: accountsDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // accounts.json 中默认配置 current 为 acc-1
        let indexJSON = """
        {
          "version": "2.0",
          "accounts": [
            { "id": "acc-1" },
            { "id": "acc-2" }
          ],
          "current_account_id": "acc-1"
        }
        """
        try indexJSON.write(to: tempDir.appendingPathComponent("accounts.json"), atomically: true, encoding: .utf8)

        let acc1JSON = """
        {
          "id": "acc-1",
          "email": "user1@example.com",
          "name": "User 1",
          "disabled": false
        }
        """
        try acc1JSON.write(to: accountsDir.appendingPathComponent("acc-1.json"), atomically: true, encoding: .utf8)

        let acc2JSON = """
        {
          "id": "acc-2",
          "email": "user2@example.com",
          "name": "User 2",
          "disabled": false
        }
        """
        try acc2JSON.write(to: accountsDir.appendingPathComponent("acc-2.json"), atomically: true, encoding: .utf8)

        // 1. 无日志数据库时：正常回退到 accounts.json 的 acc-1
        let (fallbackAccounts, fallbackCurId) = AntigravityStore.loadAccounts(from: tempDir)
        XCTAssertEqual(fallbackCurId, "acc-1")
        XCTAssertTrue(fallbackAccounts.first(where: { $0.id == "acc-1" })?.isCurrent == true)
        XCTAssertTrue(fallbackAccounts.first(where: { $0.id == "acc-2" })?.isCurrent == false)

        // 2. 创建模拟 token_stats.db，记录 user2 最近产生请求（活跃时间晚于 user1）
        let dbURL = tempDir.appendingPathComponent("token_stats.db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
        let createTable = """
        CREATE TABLE token_usage (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            account_email TEXT NOT NULL,
            model TEXT NOT NULL,
            total_tokens INTEGER NOT NULL
        );
        INSERT INTO token_usage (timestamp, account_email, model, total_tokens) VALUES (1000, 'user1@example.com', 'model-a', 100);
        INSERT INTO token_usage (timestamp, account_email, model, total_tokens) VALUES (2000, 'user2@example.com', 'model-b', 200);
        """
        XCTAssertEqual(sqlite3_exec(db, createTable, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        // 验证 loadLastActiveTimes
        let activeTimes = AntigravityStore.loadLastActiveTimes(from: tempDir)
        XCTAssertEqual(activeTimes["user1@example.com"], Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(activeTimes["user2@example.com"], Date(timeIntervalSince1970: 2000))

        // 验证 loadAccounts 动态切换当前账号为 user2 (acc-2)！
        let (dynamicAccounts, dynamicCurId) = AntigravityStore.loadAccounts(from: tempDir)
        XCTAssertEqual(dynamicCurId, "acc-2")
        let acc2 = dynamicAccounts.first(where: { $0.id == "acc-2" })
        XCTAssertEqual(acc2?.isCurrent, true)
        XCTAssertEqual(acc2?.lastActiveTime, Date(timeIntervalSince1970: 2000))

        let acc1 = dynamicAccounts.first(where: { $0.id == "acc-1" })
        XCTAssertEqual(acc1?.isCurrent, false)
        XCTAssertEqual(acc1?.lastActiveTime, Date(timeIntervalSince1970: 1000))
    }

    func testLoadLastActiveTimesMergesBothTokenStatsAndProxyLogs() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // 1. token_stats.db: user1 在 1000，user2 在 2000
        let tokenStatsDB = tempDir.appendingPathComponent("token_stats.db")
        var db1: OpaquePointer?
        XCTAssertEqual(sqlite3_open(tokenStatsDB.path, &db1), SQLITE_OK)
        let createTokenStats = """
        CREATE TABLE token_usage (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            account_email TEXT NOT NULL
        );
        INSERT INTO token_usage (timestamp, account_email) VALUES (1000, 'user1@example.com');
        INSERT INTO token_usage (timestamp, account_email) VALUES (2000, 'user2@example.com');
        """
        XCTAssertEqual(sqlite3_exec(db1, createTokenStats, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db1)

        // 2. proxy_logs.db: user1 实时产生了更新的请求 (3000)
        let proxyLogsDB = tempDir.appendingPathComponent("proxy_logs.db")
        var db2: OpaquePointer?
        XCTAssertEqual(sqlite3_open(proxyLogsDB.path, &db2), SQLITE_OK)
        let createProxyLogs = """
        CREATE TABLE request_logs (
            id TEXT PRIMARY KEY,
            timestamp INTEGER NOT NULL,
            account_email TEXT NOT NULL
        );
        INSERT INTO request_logs (id, timestamp, account_email) VALUES ('req-1', 3000, 'user1@example.com');
        """
        XCTAssertEqual(sqlite3_exec(db2, createProxyLogs, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db2)

        // 验证两者融合：user1 应该取到 3000（来自 proxy_logs），user2 取到 2000（来自 token_stats）
        let activeTimes = AntigravityStore.loadLastActiveTimes(from: tempDir)
        XCTAssertEqual(activeTimes["user1@example.com"], Date(timeIntervalSince1970: 3000))
        XCTAssertEqual(activeTimes["user2@example.com"], Date(timeIntervalSince1970: 2000))
    }

    func testParseAccountWithProxyDisabled() throws {
        let jsonStr = """
        {
          "id": "test-account-proxy-disabled",
          "name": "禁止反代账号",
          "email": "banned@example.com",
          "disabled": false,
          "proxy_disabled": true,
          "quota": {
            "models": [
              {
                "name": "gemini-3.1-pro-high",
                "percentage": 50,
                "reset_time": "2026-09-18T15:30:00Z"
              }
            ]
          }
        }
        """
        let data = jsonStr.data(using: .utf8)!
        let account = try XCTUnwrap(AntigravityStore.parseAccountFile(data: data, currentAccountId: nil))

        XCTAssertEqual(account.id, "test-account-proxy-disabled")
        XCTAssertTrue(account.isProxyDisabled)
        XCTAssertTrue(account.isDisabled)
    }

    func testArrangedAccountsExcludesDisabledAndProxyDisabledAccounts() {
        let acc1 = AntigravityAccount(id: "acc-ok-1", name: "OK1", email: "1@ok.com", isCurrent: false, isDisabled: false, percentage: 80, resetTime: nil)
        let acc2 = AntigravityAccount(id: "acc-disabled", name: "Banned", email: "2@ban.com", isCurrent: false, isDisabled: true, isProxyDisabled: true, percentage: 90, resetTime: nil)
        let acc3 = AntigravityAccount(id: "acc-ok-2", name: "OK2", email: "3@ok.com", isCurrent: true, isDisabled: false, percentage: 60, resetTime: nil)

        let arranged = AntigravityAccountsCardView.arrangedAccounts(from: [acc1, acc2, acc3])
        XCTAssertEqual(arranged.count, 2)
        XCTAssertFalse(arranged.contains(where: { $0.account.id == "acc-disabled" }))
        XCTAssertEqual(arranged.first(where: { $0.logicalDistance == 0 })?.account.id, "acc-ok-2")
    }
}
