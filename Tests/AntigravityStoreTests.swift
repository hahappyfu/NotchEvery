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
}
