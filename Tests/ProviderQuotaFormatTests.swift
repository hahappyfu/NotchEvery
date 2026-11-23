import XCTest
@testable import NotchEvery

final class ProviderQuotaFormatTests: XCTestCase {
    private func group(
        remaining: Double? = nil,
        limit: Double? = nil,
        fraction: Double? = nil,
        accounts: [MagpieQuotaAccount] = []
    ) -> MagpieProviderGroup {
        MagpieProviderGroup(
            id: "g1", name: "G1", icon: nil, accounts: accounts,
            limitState: .none, totalRemaining: remaining, totalLimit: limit,
            fraction: fraction, availableAccounts: 0, exhaustedAccounts: 0,
            pendingCheckin: false
        )
    }

    private func account(id: String = "a1") -> MagpieQuotaAccount {
        MagpieQuotaAccount(
            id: id, provider: "g1", label: "a***", plan: nil, windows: [],
            limitState: .none, noticeMessage: nil, remaining: nil, limit: nil,
            remainingFraction: nil
        )
    }

    func testRemainingTextWithAmounts() {
        XCTAssertEqual(ProviderQuotaFormat.remainingText(group(remaining: 88.02, limit: 4600)), "88 / 4600")
        XCTAssertEqual(ProviderQuotaFormat.remainingText(group(remaining: 4.65, limit: 4.7)), "4.7 / 4.7")
    }

    func testRemainingTextWithFractionOnly() {
        XCTAssertEqual(ProviderQuotaFormat.remainingText(group(fraction: 0.129)), "余 13%")
    }

    func testRemainingTextWithoutScale() {
        XCTAssertEqual(ProviderQuotaFormat.remainingText(group()), "无刻度")
        XCTAssertEqual(ProviderQuotaFormat.remainingText(group(remaining: 10, limit: 0)), "无刻度")
    }

    func testNoticeBadgeStates() {
        let now = Date(timeIntervalSince1970: 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let until = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 15, minute: 9))!
        XCTAssertEqual(ProviderQuotaFormat.noticeBadge(.riskBlocked, now: now, timeZone: calendar.timeZone), "403 风控")
        XCTAssertEqual(ProviderQuotaFormat.noticeBadge(.cooling(until: until), now: now, timeZone: calendar.timeZone), "冷却至 15:09")
        XCTAssertEqual(ProviderQuotaFormat.noticeBadge(.rateLimited, now: now, timeZone: calendar.timeZone), "429 限流")
        XCTAssertNil(ProviderQuotaFormat.noticeBadge(.none, now: now, timeZone: calendar.timeZone))
    }

    func testCountdownStates() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(ProviderQuotaFormat.countdown(now.addingTimeInterval(2 * 3600 + 30 * 60), now: now), "2h 过期")
        XCTAssertEqual(ProviderQuotaFormat.countdown(now.addingTimeInterval(34 * 60 - 10), now: now), "34m 过期")
        XCTAssertEqual(ProviderQuotaFormat.countdown(now.addingTimeInterval(30), now: now), "1m 过期")
        XCTAssertEqual(ProviderQuotaFormat.countdown(now.addingTimeInterval(-60), now: now), "已过期")
    }

    func testAccountSummary() {
        XCTAssertNil(ProviderQuotaFormat.accountSummary(group(accounts: [account()])))
        XCTAssertNil(ProviderQuotaFormat.accountSummary(group(accounts: [account(), account(id: "a2")])))
        var g = group(accounts: [account(), account(id: "a2"), account(id: "a3")])
        g = MagpieProviderGroup(
            id: g.id, name: g.name, icon: nil, accounts: g.accounts, limitState: .none,
            totalRemaining: nil, totalLimit: nil, fraction: nil,
            availableAccounts: 1, exhaustedAccounts: 2, pendingCheckin: false
        )
        XCTAssertEqual(ProviderQuotaFormat.accountSummary(g), "1 号可用 · 2 号耗尽")
    }

    func testCheckinText() {
        XCTAssertEqual(
            ProviderQuotaFormat.checkinText(MagpieCheckinSummary(claimedProviders: 4, totalCredit: 400, pendingProviders: 0, details: [])),
            "今日签到：4 家已领 +400"
        )
        XCTAssertEqual(
            ProviderQuotaFormat.checkinText(MagpieCheckinSummary(claimedProviders: 2, totalCredit: 0, pendingProviders: 1, details: [])),
            "今日签到：2 家已领"
        )
        XCTAssertEqual(
            ProviderQuotaFormat.checkinText(MagpieCheckinSummary(claimedProviders: 0, totalCredit: 0, pendingProviders: 3, details: [])),
            "今日签到：3 家可领"
        )
        XCTAssertEqual(ProviderQuotaFormat.checkinText(.empty), "今日暂无签到")
    }

    func testGatewayText() {
        XCTAssertEqual(ProviderQuotaFormat.gatewayText(.online(version: "0.1.4692")), "Magpie :3425 在线 v0.1.4692")
        XCTAssertEqual(ProviderQuotaFormat.gatewayText(.online(version: "  ")), "Magpie :3425 在线")
        XCTAssertEqual(ProviderQuotaFormat.gatewayText(.offline), "网关未运行")
    }
}
