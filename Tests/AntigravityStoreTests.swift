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
        XCTAssertNotNil(account.displayResetTime)
    }

    func testParseAccountDualTierQuotas() throws {
        // 1. quota_groups 权威源：5h 有剩余 → 5h 档（圆环 91%，倒计时挂 5h）
        let json5hNormal = """
        {
            "id": "acc1",
            "email": "test@example.com",
            "quota": {
                "quota_groups": [
                    {
                        "display_name": "Gemini Models",
                        "buckets": [
                            { "bucket_id": "gemini-weekly", "window": "weekly", "remaining_fraction": 0.23, "reset_time": "2026-09-30T00:00:00Z" },
                            { "bucket_id": "gemini-5h", "window": "5h", "remaining_fraction": 0.91, "reset_time": "2026-09-24T12:00:00Z" }
                        ]
                    }
                ]
            }
        }
        """.data(using: .utf8)!
        let acc = try XCTUnwrap(AntigravityStore.parseAccountFile(data: json5hNormal, currentAccountId: nil))
        XCTAssertEqual(acc.currentTier, .fiveHour)
        XCTAssertEqual(acc.displayPercentage, 91)
        XCTAssertEqual(acc.weeklyPercentage, 23)
        XCTAssertEqual(acc.displayResetTime, acc.fiveHourResetTime)
        XCTAssertNotEqual(acc.displayResetTime, acc.weeklyResetTime)

        // 2. 周额度耗尽（0%）→ 判死：圆环归零、倒计时挂周重置（5h 再满也用不了）
        let jsonWeeklyDead = """
        {
            "id": "acc2",
            "email": "test@example.com",
            "quota": {
                "quota_groups": [
                    {
                        "display_name": "Gemini Models",
                        "buckets": [
                            { "bucket_id": "gemini-weekly", "window": "weekly", "remaining_fraction": 0.0, "reset_time": "2026-09-30T00:00:00Z" },
                            { "bucket_id": "gemini-5h", "window": "5h", "remaining_fraction": 1.0, "reset_time": "2026-09-24T12:00:00Z" }
                        ]
                    }
                ]
            }
        }
        """.data(using: .utf8)!
        let acc2 = try XCTUnwrap(AntigravityStore.parseAccountFile(data: jsonWeeklyDead, currentAccountId: nil))
        XCTAssertEqual(acc2.currentTier, .exhausted)
        XCTAssertEqual(acc2.displayPercentage, 0)
        XCTAssertEqual(acc2.displayResetTime, acc2.weeklyResetTime)

        // 3. 5h 耗尽但周额度尚在 → 降级周档
        let json5hExhausted = """
        {
            "id": "acc3",
            "email": "test@example.com",
            "quota": {
                "quota_groups": [
                    {
                        "display_name": "Gemini Models",
                        "buckets": [
                            { "bucket_id": "gemini-weekly", "window": "weekly", "remaining_fraction": 0.5, "reset_time": "2026-09-30T00:00:00Z" },
                            { "bucket_id": "gemini-5h", "window": "5h", "remaining_fraction": 0.0, "reset_time": "2026-09-24T12:00:00Z" }
                        ]
                    }
                ]
            }
        }
        """.data(using: .utf8)!
        let acc3 = try XCTUnwrap(AntigravityStore.parseAccountFile(data: json5hExhausted, currentAccountId: nil))
        XCTAssertEqual(acc3.currentTier, .weekly)
        XCTAssertEqual(acc3.displayPercentage, 50)
        XCTAssertEqual(acc3.displayResetTime, acc3.weeklyResetTime)

        // 4. 无 quota_groups（老数据）→ models 兜底：weekly = gemini 模型，5h = nil
        let jsonModelsOnly = """
        {
            "id": "acc4",
            "email": "test@example.com",
            "quota": {
                "models": [
                    { "name": "gemini-3.1-pro-high", "percentage": 70, "reset_time": "2026-09-14T15:30:00Z" },
                    { "name": "claude-sonnet-4-6", "percentage": 100, "reset_time": "2026-09-23T18:00:00Z" }
                ]
            }
        }
        """.data(using: .utf8)!
        let acc4 = try XCTUnwrap(AntigravityStore.parseAccountFile(data: jsonModelsOnly, currentAccountId: nil))
        XCTAssertNil(acc4.fiveHourPercentage)
        XCTAssertEqual(acc4.currentTier, .weekly)
        XCTAssertEqual(acc4.displayPercentage, 70)
        XCTAssertEqual(acc4.weeklyPercentage, 70)

        // 5. 无 quota 字段：不崩，判死归零
        let jsonNoQuota = """
        { "id": "acc5", "email": "noquota@example.com" }
        """.data(using: .utf8)!
        let acc5 = try XCTUnwrap(AntigravityStore.parseAccountFile(data: jsonNoQuota, currentAccountId: nil))
        XCTAssertEqual(acc5.currentTier, .exhausted)
        XCTAssertEqual(acc5.displayPercentage, 0)
        XCTAssertNil(acc5.displayResetTime)
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

    // MARK: - 审计 I1：点选意向保护

    /// fixture：两个账号，acc-1（user1）活跃时间更新（2000 > 1000），即「活跃度推断会选 acc-1」，
    /// 用来模拟「用户点了 acc-2 但轮询按活跃度算回 acc-1」的冲突场景。
    private func makeIntentFixture() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("accounts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let indexJSON = """
        {"current_account_id": "acc-1", "accounts": [{"id": "acc-1"}, {"id": "acc-2"}]}
        """
        try indexJSON.data(using: .utf8)!.write(to: tempDir.appendingPathComponent("accounts.json"))

        try """
        {"id": "acc-1", "email": "user1@example.com", "name": "User 1", "disabled": false}
        """.write(to: tempDir.appendingPathComponent("accounts/acc-1.json"), atomically: true, encoding: .utf8)
        try """
        {"id": "acc-2", "email": "user2@example.com", "name": "User 2", "disabled": false}
        """.write(to: tempDir.appendingPathComponent("accounts/acc-2.json"), atomically: true, encoding: .utf8)

        // user1 活跃时间更新 → 无意向时活跃度推断应选 acc-1
        let dbURL = tempDir.appendingPathComponent("token_stats.db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
        let sql = """
        CREATE TABLE token_usage (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            account_email TEXT NOT NULL,
            model TEXT NOT NULL,
            total_tokens INTEGER NOT NULL
        );
        INSERT INTO token_usage (timestamp, account_email, model, total_tokens) VALUES (2000, 'user1@example.com', 'model-a', 100);
        INSERT INTO token_usage (timestamp, account_email, model, total_tokens) VALUES (1000, 'user2@example.com', 'model-b', 200);
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        return tempDir
    }

    /// 用户点选 acc-2 后、即使 acc-1 活跃度更新，10 分钟意向窗口内轮询刷新不得把 current 弹回 acc-1。
    func testIntentProtectsSelectionAgainstActivityInference() throws {
        let tempDir = try makeIntentFixture()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let now = Date(timeIntervalSince1970: 1_000_000)

        // 前置：无意向时活跃度推断选 acc-1（红线：无点选行为不变）
        let (noIntentAccounts, noIntentId) = AntigravityStore.loadAccounts(from: tempDir, now: now)
        XCTAssertEqual(noIntentId, "acc-1")

        // 点选 acc-2（活跃度低于 acc-1）→ 意向新鲜期内 current 仍为 acc-2
        let intent = AntigravityStore.AccountIntent(id: "acc-2", date: now)
        let (accounts, currentId) = AntigravityStore.loadAccounts(from: tempDir, intent: intent, now: now.addingTimeInterval(5))
        XCTAssertEqual(currentId, "acc-2", "意向新鲜期内不得被活跃度推断冲掉")
        XCTAssertEqual(accounts.first(where: { $0.id == "acc-2" })?.isCurrent, true, "isCurrent 标记须与意向一致")
        XCTAssertEqual(accounts.first(where: { $0.id == "acc-1" })?.isCurrent, false)

        // 意向过期（> 600s）→ 回落活跃度推断
        let (_, expiredId) = AntigravityStore.loadAccounts(
            from: tempDir, intent: intent, now: now.addingTimeInterval(AntigravityStore.accountIntentFreshness + 1))
        XCTAssertEqual(expiredId, "acc-1", "意向过期后应回到活跃度推断")

        // 意向账号已消失 → 回落活跃度推断
        let (_, vanishedId) = AntigravityStore.loadAccounts(
            from: tempDir, intent: AntigravityStore.AccountIntent(id: "acc-9", date: now), now: now.addingTimeInterval(5))
        XCTAssertEqual(vanishedId, "acc-1")
    }
}
