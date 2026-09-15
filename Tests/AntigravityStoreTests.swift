import XCTest
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
}
