import XCTest
@testable import NotchEvery

final class MagpieAggregatorTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 12))!
    }

    private let yesterday = "2026-11-22T23:59:00+08:00"
    private let todayMorning = "2026-11-23T09:00:00+08:00"

    // MARK: - Fixtures

    private func record(
        _ id: String = UUID().uuidString,
        time: String = "2026-11-23T10:00:00+08:00",
        provider: String = "p",
        account: String = "a",
        model: String = "m",
        served: String? = nil,
        req: String = "group/g",
        routeID: Int64? = nil,
        input: Int = 10,
        output: Int = 5,
        cacheRead: Int = 0,
        ms: Int? = 100,
        status: Int? = 200,
        handedOn: Bool = false
    ) -> MagpieUsageRecord {
        MagpieUsageRecord(
            id: id,
            routeID: routeID,
            time: MagpieDate.parse(time)!,
            agent: "claude",
            provider: provider,
            providerAccount: account,
            model: model,
            served: served,
            req: req,
            inputTokens: input,
            outputTokens: output,
            cacheRead: cacheRead,
            cacheWrite: 0,
            reasoning: 0,
            durationMs: ms,
            ttftMs: nil,
            maskingMs: nil,
            status: status,
            handedOn: handedOn
        )
    }

    private func quota(
        _ provider: String,
        account: String = "a",
        name: String? = nil,
        icon: String? = nil,
        user: String? = nil,
        plan: String? = nil,
        windows: [MagpieQuotaWindow] = []
    ) -> MagpieQuotaFileEntry {
        MagpieQuotaFileEntry(
            accountKey: "\(provider)/\(account)",
            provider: provider,
            account: account,
            name: name,
            icon: icon,
            plan: plan,
            user: user,
            at: nil,
            windows: windows
        )
    }

    private func window(
        _ name: String = "总积分",
        used: Double? = nil,
        amount: Double? = nil,
        limit: Double? = nil,
        aside: Bool = false,
        display: String? = nil
    ) -> MagpieQuotaWindow {
        MagpieQuotaWindow(
            name: name,
            usedPercent: used,
            amount: amount,
            limit: limit,
            unit: "credits",
            display: display,
            resetsAt: nil,
            runsOutAt: nil,
            isAside: aside
        )
    }

    private func entry(_ provider: String, name: String?, signedIn: Bool = true) -> MagpieProviderCatalog.Entry {
        .init(id: provider, name: name ?? "", icon: nil, hidden: false, disabled: false, signedIn: signedIn)
    }

    private func snapshot(
        usage: [MagpieUsageRecord] = [],
        routes: MagpieRouteIndex = MagpieRouteIndex(),
        masking: [MagpieMaskingEntry] = [],
        quotas: [MagpieQuotaFileEntry] = [],
        notices: [String: MagpieLimitNotice] = [:],
        checkins: [MagpieCheckinFileEntry] = [],
        catalog: MagpieProviderCatalog = MagpieProviderCatalog(),
        gateway: MagpieGatewayFile? = nil,
        quotaHistory: [String: [String: [MagpieQuotaPoint]]] = [:],
        hasDirectory: Bool = true,
        pidAlive: @escaping (Int32) -> Bool = { _ in false }
    ) -> MagpieSnapshot {
        MagpieAggregator.buildSnapshot(
            usage: usage,
            routes: routes,
            masking: masking,
            quotas: quotas,
            notices: notices,
            checkins: checkins,
            catalog: catalog,
            gateway: gateway,
            quotaHistory: quotaHistory,
            hasMagpieDirectory: hasDirectory,
            now: now,
            calendar: calendar,
            pidAlive: pidAlive
        )
    }

    private func singleAccount(_ windows: [MagpieQuotaWindow]) -> MagpieQuotaAccount {
        snapshot(quotas: [quota("p", windows: windows)]).providerGroups.first!.accounts.first!
    }

    // 1. 昨日记录不计入今日口径
    func testTodayOnlyFiltering() {
        let result = snapshot(usage: [
            record("old", time: yesterday, input: 100, output: 50, ms: 500),
            record("new", time: todayMorning, input: 10, output: 5, ms: 100)
        ])
        XCTAssertEqual(result.todayRequestCount, 1)
        XCTAssertEqual(result.todayNetTokens, 15)
        XCTAssertEqual(result.todayAverageMs ?? -1, 100, accuracy: 0.0001)
        XCTAssertEqual(result.lastRequestAt, MagpieDate.parse(todayMorning))
        XCTAssertEqual(result.recentFlows.map(\.id), ["new"])
        XCTAssertEqual(result.distributions[.combo]?.reduce(0) { $0 + $1.tokenCount }, 15)
    }

    // 2. net = in + out；cacheRate = cacheRead/(in+cacheRead)；分母 0 → nil
    func testNetTokensAndCacheRate() {
        let result = snapshot(usage: [
            record(input: 100, output: 50, cacheRead: 100),
            record(input: 0, output: 10, cacheRead: 0)
        ])
        XCTAssertEqual(result.todayNetTokens, 160)
        XCTAssertEqual(result.todayCacheRead, 100)
        XCTAssertEqual(result.todayCacheRate ?? -1, 0.5, accuracy: 0.0001)

        let noDenominator = snapshot(usage: [record(input: 0, output: 10, cacheRead: 0)])
        XCTAssertNil(noDenominator.todayCacheRate)
    }

    // 3. 499、handed_on:true 不计错误；status:nil 计错误
    func testErrorCountExcludesCancelledAndHandedOn() {
        let result = snapshot(usage: [
            record(status: 200),
            record(status: 499),
            record(status: 500, handedOn: true),
            record(status: nil),
            record(status: 429)
        ])
        XCTAssertEqual(result.todayErrorCount, 2)
    }

    // 4. 平均耗时只统计今日有 durationMs 的记录
    func testAverageMsOnlyCompletedToday() {
        let result = snapshot(usage: [
            record(ms: 100),
            record(ms: 300),
            record(ms: nil),
            record(time: yesterday, ms: 1000)
        ])
        XCTAssertEqual(result.todayAverageMs ?? -1, 200, accuracy: 0.0001)

        XCTAssertNil(snapshot(usage: [record(ms: nil)]).todayAverageMs)
    }

    // 5. combo 分布：键 (provider, served ?? model)、token 降序、shareFraction 全量分母
    func testComboDistribution() {
        let catalog = MagpieProviderCatalog(
            entries: ["p1": entry("p1", name: "P One"), "p2": entry("p2", name: "P Two")],
            groupNameByProviderRef: [:]
        )
        let result = snapshot(usage: [
            record(provider: "p1", model: "m1", served: "s1", input: 100, output: 0, cacheRead: 50),
            record(provider: "p1", model: "m2", input: 100, output: 0),
            record(provider: "p2", model: "m1", input: 200, output: 0)
        ], catalog: catalog)

        let items = result.distributions[.combo] ?? []
        XCTAssertEqual(items.map(\.tokenCount), [200, 100, 100])
        XCTAssertEqual(items.map { $0.shareFraction }, [0.5, 0.25, 0.25])
        XCTAssertEqual(items.map(\.label), ["m1", "m2", "s1"])
        let servedItem = try? XCTUnwrap(items.first(where: { $0.label == "s1" }))
        XCTAssertEqual(servedItem?.secondaryLabel, "P One")
        XCTAssertEqual(servedItem?.copyText, "p1/s1")
        XCTAssertEqual(servedItem?.cacheRead, 50)
        XCTAssertEqual(servedItem?.calls, 1)
    }

    // 6. provider 分布：detail = N 账号 · M 模型
    func testProviderDistributionWithAccountAndModelCounts() {
        let catalog = MagpieProviderCatalog(entries: ["p1": entry("p1", name: "P One")], groupNameByProviderRef: [:])
        let result = snapshot(usage: [
            record(provider: "p1", account: "a1", model: "m1"),
            record(provider: "p1", account: "a2", model: "m2"),
            record(provider: "p1", account: "a1", model: "m3")
        ], catalog: catalog)

        let items = result.distributions[.provider] ?? []
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.label, "P One")
        XCTAssertEqual(items.first?.detail, "2 账号 · 3 模型")
        XCTAssertEqual(items.first?.calls, 3)
        XCTAssertEqual(items.first?.copyText, "p1")
    }

    // 7. group 名称优先级：routing 命中 > providers.json groups > 直连调用
    func testGroupDistributionNamePriority() {
        let routes = MagpieRouteIndex(groupNameByRouteID: [1: "Routing Name"])
        let catalog = MagpieProviderCatalog(
            entries: [:],
            groupNameByProviderRef: ["group/ref2": "Catalog Name2"]
        )
        let result = snapshot(usage: [
            record(model: "m1", served: "m1", req: "group/ref1", routeID: 1, input: 100),
            record(model: "m2", served: "m2", req: "group/ref2", routeID: 2, input: 50),
            record(model: "claude-sonnet", served: "claude-sonnet", req: "claude-sonnet", routeID: 3, input: 10)
        ], routes: routes, catalog: catalog)

        let items = result.distributions[.group] ?? []
        XCTAssertEqual(items.map(\.label), ["Routing Name", "Catalog Name2", "直连调用"])
        XCTAssertEqual(items.first?.copyText, "group/ref1")
        let direct = try? XCTUnwrap(items.first(where: { $0.label == "直连调用" }))
        XCTAssertEqual(direct?.secondaryLabel, "claude-sonnet")
        XCTAssertEqual(direct?.copyText, "claude-sonnet")
        XCTAssertNil(result.recentFlows.first(where: { $0.model == "claude-sonnet" })?.groupName)
        XCTAssertEqual(result.recentFlows.first(where: { $0.model == "m1" })?.groupName, "Routing Name")
    }

    // 8. 活跃告警：until nil / 过期 / 未来
    func testActiveNoticeCount() {
        let notices = [
            "a@x": MagpieLimitNotice(provider: "a", account: "x", status: 429),
            "b@y": MagpieLimitNotice(provider: "b", account: "y", status: 429, until: MagpieDate.parse("2026-11-23T10:00:00+08:00")),
            "c@z": MagpieLimitNotice(provider: "c", account: "z", status: 429, until: MagpieDate.parse("2026-11-23T18:00:00+08:00"))
        ]
        XCTAssertEqual(snapshot(notices: notices).activeAlertCount, 2)
    }

    // 9. 供应商合并：catalog/plugin/routing-only 都成组，hidden/disabled 排除，名称优先级
    func testProviderMergeIncludesCatalogPluginAndRoutingOnly() {
        let providers = MagpieProviderCatalog.ProviderPart(
            entries: [
                "catalogOnly": entry("catalogOnly", name: "Catalog Only"),
                "hiddenPro": entry("hiddenPro", name: "Hidden Provider"),
                "hiddenPro2": entry("hiddenPro2", name: "Hidden Provider 2"),
                "prio": entry("prio", name: "Provider Name"),
                "prio2": entry("prio2", name: "")
            ],
            groupNameByProviderRef: [:]
        )
        var entries = providers.entries
        entries["hiddenPro"] = .init(id: "hiddenPro", name: "Hidden Provider", icon: nil, hidden: true, disabled: false, signedIn: true)
        entries["hiddenPro2"] = .init(id: "hiddenPro2", name: "Hidden Provider 2", icon: nil, hidden: false, disabled: true, signedIn: true)
        let catalog = MagpieProviderCatalog.merged(
            providers: MagpieProviderCatalog.ProviderPart(entries: entries, groupNameByProviderRef: [:]),
            plugins: [
                .init(id: "pluginOnly", name: "Plugin Only", icon: nil, signedIn: true),
                .init(id: "signedOut", name: "Signed Out", icon: nil, signedIn: false),
                .init(id: "prio", name: "Plugin Name", icon: nil, signedIn: true),
                .init(id: "prio2", name: "Plugin Two", icon: nil, signedIn: true)
            ]
        )
        let routes = MagpieRouteIndex(
            orderSnapshotsByProvider: [
                "routingOnly": MagpieProviderOrderSnapshot(
                    provider: "routingOnly", name: "Routing Only", who: "who1",
                    unit: "credits", used: 10, amount: 10, limit: 100
                )
            ]
        )
        let quotas = [
            quota("hiddenPro", name: "Hidden Quota", windows: [window(used: 10, amount: 10, limit: 100)]),
            quota("hiddenPro2", name: "Disabled Quota", windows: [window(used: 10, amount: 10, limit: 100)]),
            quota("prio", name: "Quota Name", windows: [window(used: 10, amount: 10, limit: 100)]),
            quota("prio2", name: "Quota Name", windows: [window(used: 10, amount: 10, limit: 100)]),
            quota("prio3", name: "Quota Three", windows: [window(used: 10, amount: 10, limit: 100)])
        ]

        let groups = snapshot(routes: routes, quotas: quotas, catalog: catalog).providerGroups
        let names = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.name) })
        XCTAssertEqual(Set(names.keys), ["catalogOnly", "pluginOnly", "prio", "prio2", "prio3", "routingOnly"])
        XCTAssertEqual(names["catalogOnly"], "Catalog Only")
        XCTAssertEqual(names["pluginOnly"], "Plugin Only")
        XCTAssertEqual(names["prio"], "Provider Name")
        XCTAssertEqual(names["prio2"], "Plugin Two")
        XCTAssertEqual(names["prio3"], "Quota Three")
        XCTAssertEqual(names["routingOnly"], "Routing Only")
        XCTAssertFalse(groups.contains(where: { $0.id == "signedOut" }))
        XCTAssertFalse(groups.contains(where: { $0.id == "hiddenPro" }))
        XCTAssertFalse(groups.contains(where: { $0.id == "hiddenPro2" }))
    }

    // 10. 主窗口选择（aside 过滤/回退）与余量计算
    func testMainWindowSkipsAsideAndRemainingMath() {
        let withAside = singleAccount([
            window("附属", used: 90, limit: 100, aside: true),
            window("主窗口", used: 20, amount: 30, limit: 100)
        ])
        XCTAssertEqual(withAside.remaining ?? -1, 70, accuracy: 0.0001)
        XCTAssertEqual(withAside.limit ?? -1, 100, accuracy: 0.0001)
        XCTAssertEqual(withAside.remainingFraction ?? -1, 0.7, accuracy: 0.0001)

        let allAside = singleAccount([window("附属", used: 50, limit: 100, aside: true)])
        XCTAssertEqual(allAside.remaining ?? -1, 50, accuracy: 0.0001)

        let percentOnly = singleAccount([window(used: 25)])
        XCTAssertNil(percentOnly.remaining)
        XCTAssertNil(percentOnly.limit)
        XCTAssertEqual(percentOnly.remainingFraction ?? -1, 0.75, accuracy: 0.0001)

        let noScale = singleAccount([window()])
        XCTAssertNil(noScale.remaining)
        XCTAssertNil(noScale.remainingFraction)

        let overspent = singleAccount([window(used: 100, amount: 120, limit: 100)])
        XCTAssertEqual(overspent.remaining ?? -1, 0, accuracy: 0.0001)

        let zeroLimitGroup = snapshot(quotas: [quota("p", windows: [window(used: 10, limit: 0)])]).providerGroups.first
        XCTAssertNil(zeroLimitGroup?.totalLimit)
        XCTAssertNil(zeroLimitGroup?.totalRemaining)
        XCTAssertNil(zeroLimitGroup?.fraction)
    }

    // 11. 分组总量与账号可用性
    func testGroupTotalsAndAccountAvailability() {
        let quotas = [
            quota("p", account: "a1", windows: [window(used: 50, amount: 50, limit: 100)]),
            quota("p", account: "a2", windows: [window(used: 100, amount: 200, limit: 200)]),
            quota("p", account: "a3", windows: [window(used: 25)])
        ]
        let group = snapshot(quotas: quotas).providerGroups.first!
        XCTAssertEqual(group.totalLimit ?? -1, 300, accuracy: 0.0001)
        XCTAssertEqual(group.totalRemaining ?? -1, 50, accuracy: 0.0001)
        XCTAssertEqual(group.fraction ?? -1, 50.0 / 300.0, accuracy: 0.0001)
        XCTAssertEqual(group.availableAccounts, 1)
        XCTAssertEqual(group.exhaustedAccounts, 1)
    }

    // 12. 排序权重：正常 < 有告警 < 耗尽 < 无刻度，同档按名
    func testProviderSortingWeights() {
        let quotas = [
            quota("alpha", windows: [window(used: 10, amount: 10, limit: 100)]),
            quota("zeta", windows: [window(used: 10, amount: 10, limit: 100)]),
            quota("beta", windows: [window(used: 10, amount: 10, limit: 100)]),
            quota("gamma", windows: [window(used: 100, amount: 100, limit: 100)]),
            quota("delta", windows: [window()])
        ]
        let notices = ["beta@a": MagpieLimitNotice(provider: "beta", account: "a", status: 429)]
        XCTAssertEqual(snapshot(quotas: quotas, notices: notices).providerGroups.map(\.id),
                       ["alpha", "zeta", "beta", "gamma", "delta"])
    }

    // 13. 签到：claimed + done 计；ineligible 与跨天不计；窗口名含"今日未签" → pending
    func testCheckinClaimedDoneAndPending() {
        let checkins = [
            MagpieCheckinFileEntry(provider: "p1", slot: "default", day: "2026-11-23", outcome: "claimed", credit: 100),
            MagpieCheckinFileEntry(provider: "p2", slot: "main", day: "2026-11-23", outcome: "done", credit: 300),
            MagpieCheckinFileEntry(provider: "p3", slot: "x", day: "2026-11-23", outcome: "ineligible", credit: 500),
            MagpieCheckinFileEntry(provider: "p4", slot: "y", day: "2026-11-22", outcome: "claimed", credit: 50)
        ]
        let quotas = [quota("p1", windows: [window("今日未签", used: 0, limit: 100)])]
        let result = snapshot(quotas: quotas, checkins: checkins)
        XCTAssertEqual(result.checkin.claimedProviders, 2)
        XCTAssertEqual(result.checkin.totalCredit, 400, accuracy: 0.0001)
        XCTAssertEqual(result.checkin.pendingProviders, 1)
        XCTAssertEqual(result.providerGroups.first?.pendingCheckin, true)
    }

    // 14. 网关在线状态使用注入的 pidAlive
    func testGatewayOnlineUsesInjectedPidAlive() {
        let gateway = MagpieGatewayFile(addr: "127.0.0.1:3425", pid: 42, version: "1.2.3", started: nil)
        XCTAssertEqual(snapshot(gateway: gateway, pidAlive: { $0 == 42 }).gateway, .online(version: "1.2.3"))
        XCTAssertEqual(snapshot(gateway: gateway, pidAlive: { _ in false }).gateway, .offline)
        XCTAssertEqual(snapshot(gateway: nil).gateway, .offline)
    }

    // 15. 脱敏求和与去重路由数
    func testMaskingSumsAndDistinctRoutes() {
        let result = snapshot(
            usage: [record("r1", routeID: 1)],
            masking: [
                MagpieMaskingEntry(route: 1, n: 3),
                MagpieMaskingEntry(route: 1, n: 2),
                MagpieMaskingEntry(route: 2, n: 0),
                MagpieMaskingEntry(route: 3, n: 4)
            ]
        )
        XCTAssertEqual(result.todayMaskedValues, 9)
        XCTAssertEqual(result.todayMaskedRequests, 2)
        XCTAssertEqual(result.recentFlows.first?.maskedCount, 5)
    }

    // 16. quota-history 按 <provider>|<account> + 窗口名接入，取最近 20 点
    func testQuotaHistoryJoinsWindowSparkline() {
        let points = (1...25).map { MagpieQuotaPoint(at: nil, left: Double($0)) }
        let quotas = [quota("p", windows: [window("总积分", used: 30, amount: 30, limit: 100)])]
        let result = snapshot(quotas: quotas, quotaHistory: ["p|a": ["总积分": points]])
        let window = result.providerGroups.first?.accounts.first?.windows.first
        XCTAssertEqual(window?.history.count, 20)
        XCTAssertEqual(window?.history.first, 6)
        XCTAssertEqual(window?.history.last, 25)
    }

    // 17. 流水行字段：provider 显示名、账号、requestedModel、状态与耗时
    func testRecentFlowRowFields() {
        let catalog = MagpieProviderCatalog(entries: ["p": entry("p", name: "Provider Display")], groupNameByProviderRef: [:])
        let routes = MagpieRouteIndex(groupNameByRouteID: [7: "Group Name"])
        let result = snapshot(usage: [
            record("r1", time: todayMorning, provider: "p", account: "acct", model: "requested", served: "served", routeID: 7, ms: 250)
        ], routes: routes, catalog: catalog)
        let flow = result.recentFlows.first
        XCTAssertEqual(flow?.provider, "Provider Display")
        XCTAssertEqual(flow?.account, "acct")
        XCTAssertEqual(flow?.model, "served")
        XCTAssertEqual(flow?.requestedModel, "requested")
        XCTAssertEqual(flow?.groupName, "Group Name")
        XCTAssertEqual(flow?.durationMs, 250)
    }
}
