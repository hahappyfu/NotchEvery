import XCTest
@testable import NotchEvery

final class EarSummaryTests: XCTestCase {
    private var calendar: Calendar!

    override func setUpWithError() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        self.calendar = calendar
    }

    // MARK: - Fixtures

    private func item(_ id: String) -> DistributionItem {
        DistributionItem(
            id: id, label: id, secondaryLabel: nil, detail: nil,
            tokenCount: 0, cacheRead: 0, calls: 0, shareFraction: 0, copyText: id
        )
    }

    private func flow(provider: String, model: String = "claude-sonnet-4-5") -> MagpieFlowRow {
        MagpieFlowRow(
            id: "r1", agent: "claude", providerID: provider, providerName: provider + " 展示", account: "a***",
            model: model, requestedModel: model, groupName: nil,
            inputTokens: 10, outputTokens: 5, cacheRead: 2,
            durationMs: 100, ttftMs: nil, maskingMs: nil,
            status: 200, handedOn: false, maskedCount: 0, time: Date()
        )
    }

    private func group(id: String, name: String, limitState: ProviderLimitState = .none) -> MagpieProviderGroup {
        MagpieProviderGroup(
            id: id, name: name, icon: nil, accounts: [], limitState: limitState,
            totalRemaining: nil, totalLimit: nil, fraction: nil,
            availableAccounts: 0, exhaustedAccounts: 0, pendingCheckin: false
        )
    }

    private func snapshot(
        hasDirectory: Bool = true,
        distributions: [DistributionDimension: [DistributionItem]] = [:],
        lastRequestAt: Date? = nil,
        alerts: Int = 0,
        flows: [MagpieFlowRow] = [],
        requestCount: Int = 0,
        groups: [MagpieProviderGroup] = [],
        totalCredit: Double = 0
    ) -> MagpieSnapshot {
        var s = MagpieSnapshot.empty
        s.hasMagpieDirectory = hasDirectory
        s.distributions = distributions
        s.lastRequestAt = lastRequestAt
        s.activeAlertCount = alerts
        s.recentFlows = flows
        s.todayRequestCount = requestCount
        s.providerGroups = groups
        s.checkin = MagpieCheckinSummary(claimedProviders: 0, totalCredit: totalCredit, pendingProviders: 0, details: [])
        return s
    }

    private func time(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: hour, minute: minute))!
    }

    // MARK: - P1 左耳（三维度计数，0 → nil）

    func testOverviewLeftCountsByDimension() {
        let dims: [DistributionDimension: [DistributionItem]] = [
            .combo: [item("a"), item("b"), item("c")],
            .provider: [item("x"), item("y")],
            .group: [item("g")]
        ]
        let s = snapshot(distributions: dims)
        XCTAssertEqual(EarSummary.overviewLeft(dimension: .combo, snapshot: s), "3 个活跃组合")
        XCTAssertEqual(EarSummary.overviewLeft(dimension: .provider, snapshot: s), "2 家提供商")
        XCTAssertEqual(EarSummary.overviewLeft(dimension: .group, snapshot: s), "1 个路由组")
    }

    func testOverviewLeftZeroIsNil() {
        let s = snapshot(distributions: [:])
        XCTAssertNil(EarSummary.overviewLeft(dimension: .combo, snapshot: s))
        XCTAssertNil(EarSummary.overviewLeft(dimension: .provider, snapshot: s))
        XCTAssertNil(EarSummary.overviewLeft(dimension: .group, snapshot: s))
    }

    // MARK: - P1 右耳（时间 + 告警）

    func testOverviewRightTimeAndAlerts() {
        let s = snapshot(lastRequestAt: time(14, 5), alerts: 3)
        let r = EarSummary.overviewRight(snapshot: s, calendar: calendar)
        XCTAssertEqual(r.time, "14:05")
        XCTAssertEqual(r.alerts, 3)
    }

    func testOverviewRightNilTime() {
        let s = snapshot(lastRequestAt: nil, alerts: 0)
        let r = EarSummary.overviewRight(snapshot: s, calendar: calendar)
        XCTAssertNil(r.time)
        XCTAssertEqual(r.alerts, 0)
    }

    // MARK: - P2 左右

    func testFlowLeftUsesProviderGroupName() {
        let s = snapshot(flows: [flow(provider: "p1")], groups: [group(id: "p1", name: "Provider One")])
        XCTAssertEqual(EarSummary.flowLeft(snapshot: s), "Provider One")
    }

    func testFlowLeftFallsBackToProviderID() {
        let s = snapshot(flows: [flow(provider: "p1")], groups: [])
        XCTAssertEqual(EarSummary.flowLeft(snapshot: s), "p1 展示")
    }

    func testFlowLeftNoFlowsIsNil() {
        let s = snapshot(flows: [])
        XCTAssertNil(EarSummary.flowLeft(snapshot: s))
    }

    func testFlowRightRequestsAndAlerts() {
        let s = snapshot(alerts: 2, requestCount: 1500)
        let r = EarSummary.flowRight(snapshot: s)
        XCTAssertEqual(r.requests, "1.5k 次")
        XCTAssertEqual(r.alerts, 2)
    }

    // MARK: - P3 左右

    func testProvidersLeftAlertState() {
        let s = snapshot(groups: [
            group(id: "a", name: "A", limitState: .rateLimited),
            group(id: "b", name: "B", limitState: .none)
        ])
        let r = EarSummary.providersLeft(snapshot: s)
        XCTAssertTrue(r.hasAlert)
        XCTAssertEqual(r.text, "1 家受限")
    }

    func testProvidersLeftNormalState() {
        let s = snapshot(groups: [
            group(id: "a", name: "A", limitState: .none),
            group(id: "b", name: "B", limitState: .none)
        ])
        let r = EarSummary.providersLeft(snapshot: s)
        XCTAssertFalse(r.hasAlert)
        XCTAssertEqual(r.text, "2 家供应商")
    }

    func testProvidersRightCheckinAndAlerts() {
        let s = snapshot(alerts: 1, totalCredit: 400)
        let r = EarSummary.providersRight(snapshot: s)
        XCTAssertEqual(r.checkin, "签到 +400")
        XCTAssertEqual(r.alerts, 1)
    }

    func testProvidersRightNoCheckin() {
        let s = snapshot(alerts: 0, totalCredit: 0)
        let r = EarSummary.providersRight(snapshot: s)
        XCTAssertNil(r.checkin)
        XCTAssertEqual(r.alerts, 0)
    }
}
