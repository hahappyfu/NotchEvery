//
//  QoderCampaignClaimerTests.swift
//  NotchEveryTests
//
//  任务 4：QoderCampaignClaimer 协议契约测试 —— GET/POST 两步请求的 URL/method/headers/body、
//  过滤条件（actionType+claimStatus）、幂等 replayed、单账号失败隔离、账号池文件扫描解析。
//  全程假 transport，绝不真联网。
//

import XCTest
@testable import NotchEvery

/// 假 transport：按 URL path 含 "/claim" 与否分别路由；记录每次调用供断言。
private final class FakeCampaignTransport: QoderCampaignTransport {
    struct Call {
        let url: URL
        let method: String
        let headers: [String: String]
        let body: Data?
    }
    var calls: [Call] = []
    /// key = userId（用 Authorization 头区分），value = 该账号 GET 响应
    var campaignsResponseByBearer: [String: (status: Int, data: Data)] = [:]
    var defaultCampaigns: (status: Int, data: Data)?
    var claimResult: (status: Int, data: Data) = (200, Data(#"{"status":"CLAIMED","replayed":false}"#.utf8))
    /// 按 campaignId（POST URL 倒数第二段）路由不同响应，优先于全局 claimResult；用于测多条活动部分成功场景。
    var claimResultByCampaignId: [String: (status: Int, data: Data)] = [:]
    /// 抛错的 campaignId 集合（POST 阶段）
    var throwingCampaignIds: Set<String> = []
    /// 抛错的 bearer 集合（GET 阶段）
    var throwingBearers: Set<String> = []

    func request(url: URL, method: String, headers: [String: String], body: Data?) async throws -> (status: Int, data: Data) {
        calls.append(Call(url: url, method: method, headers: headers, body: body))
        let bearer = headers["Authorization"] ?? ""
        if url.path.hasSuffix("/campaigns") {
            if throwingBearers.contains(bearer) { throw URLError(.cannotConnectToHost) }
            if let r = campaignsResponseByBearer[bearer] { return r }
            return defaultCampaigns ?? (200, Data())
        }
        // POST .../campaigns/<id>/claim —— path 倒数第二段是 campaignId
        let components = url.path.split(separator: "/")
        let campaignId = components.dropLast().last.map(String.init) ?? ""
        if throwingCampaignIds.contains(campaignId) { throw URLError(.timedOut) }
        if let r = claimResultByCampaignId[campaignId] { return r }
        return claimResult
    }
}

final class QoderCampaignClaimerTests: XCTestCase {

    private func makeTempPool(accounts: [(id: String, accessToken: String, machineId: String, userId: String)]) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pool-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for a in accounts {
            let json = """
            {"auth":{"access_token":"\(a.accessToken)","cosy_key":"x","encrypt_user_info":"y","machine_id":"\(a.machineId)","user_id":"\(a.userId)"}}
            """
            try Data(json.utf8).write(to: dir.appendingPathComponent("account_\(a.id).json"))
        }
        return dir
    }

    private func uniqueDefaults() -> UserDefaults {
        let suite = "QoderCampaignClaimerTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    private func campaignsJSON(_ entries: [(id: String, actionType: String, claimStatus: String)]) -> Data {
        let items = entries.map { e -> String in
            #"{"campaignId":"\#(e.id)","actionType":"\#(e.actionType)","claimStatus":"\#(e.claimStatus)"}"#
        }
        return Data(#"{"uid":"u1","showCampaign":true,"claimable":true,"campaigns":[\#(items.joined(separator: ","))]}"#.utf8)
    }

    // MARK: - scanAccounts

    func testScanAccountsParsesCredentialsAndSkipsGarbage() throws {
        let dir = try makeTempPool(accounts: [
            ("aaa", "tok-1", "mach-1", "user-1"),
            ("bbb", "tok-2", "mach-2", "user-2"),
        ])
        // 一个坏文件（缺 auth.user_id）应被跳过，不影响其它两个
        try Data(#"{"auth":{"access_token":"x","machine_id":"y"}}"#.utf8).write(to: dir.appendingPathComponent("account_bad.json"))
        // 非 account_* 前缀的文件应被忽略
        try Data("{}".utf8).write(to: dir.appendingPathComponent("gateway.json"))

        let claimer = QoderCampaignClaimer(transport: FakeCampaignTransport(), poolDirectory: dir, defaults: uniqueDefaults())
        let accounts = claimer.scanAccounts()
        XCTAssertEqual(Set(accounts.map(\.accessToken)), ["tok-1", "tok-2"])
        XCTAssertEqual(Set(accounts.map(\.userId)), ["user-1", "user-2"])
        XCTAssertEqual(Set(accounts.map(\.machineId)), ["mach-1", "mach-2"])
    }

    // MARK: - 完整两步流程 + 请求构造断言

    @MainActor
    func testClaimSendsCorrectGetThenPostForClaimableCampaign() async throws {
        let dir = try makeTempPool(accounts: [("id1", "tok-1", "mach-1", "user-1")])
        let t = FakeCampaignTransport()
        t.defaultCampaigns = (200, campaignsJSON([("c-100", "CLAIM_BENEFIT", "CLAIMABLE")]))
        let claimer = QoderCampaignClaimer(transport: t, poolDirectory: dir, defaults: uniqueDefaults())

        let cred = try XCTUnwrap(claimer.scanAccounts().first)
        let outcome = await claimer.claim(for: cred)
        XCTAssertEqual(outcome, .claimed)

        XCTAssertEqual(t.calls.count, 2, "应恰好一次 GET + 一次 POST")
        let get = t.calls[0], post = t.calls[1]

        XCTAssertEqual(get.url.absoluteString, "https://openapi.qoder.com.cn/sash/api/v1/me/campaigns")
        XCTAssertEqual(get.method, "GET")
        XCTAssertNil(get.body)
        for (k, v) in ["Authorization": "Bearer tok-1", "Cosy-ClientType": "10", "Cosy-Version": "0.1.18",
                       "Cosy-MachineOS": "darwin", "Cosy-MachineId": "mach-1", "User-Agent": "Qoder",
                       "Accept": "application/json"] {
            XCTAssertEqual(get.headers[k], v, "GET 缺少正确的 \(k) 头")
        }
        XCTAssertNil(get.headers["Content-Type"], "GET 不应带 Content-Type")

        XCTAssertTrue(post.url.absoluteString.hasSuffix("/sash/api/v1/me/campaigns/c-100/claim"), "POST URL 必须包含 campaignId")
        XCTAssertEqual(post.method, "POST")
        XCTAssertEqual(String(data: post.body ?? Data(), encoding: .utf8), "{}")
        XCTAssertEqual(post.headers["Content-Type"], "application/json", "POST 必须带 Content-Type")
        XCTAssertEqual(post.headers["Authorization"], "Bearer tok-1")
        XCTAssertEqual(post.headers["Cosy-MachineId"], "mach-1")
    }

    @MainActor
    func testNoClaimWhenNothingClaimable() async throws {
        let dir = try makeTempPool(accounts: [("id1", "tok-1", "mach-1", "user-1")])
        let t = FakeCampaignTransport()
        t.defaultCampaigns = (200, campaignsJSON([
            ("c-1", "VIEW_DETAILS", "CLAIMABLE"),      // actionType 不匹配
            ("c-2", "CLAIM_BENEFIT", "CLAIMED"),       // claimStatus 不匹配
        ]))
        let claimer = QoderCampaignClaimer(transport: t, poolDirectory: dir, defaults: uniqueDefaults())
        let cred = try XCTUnwrap(claimer.scanAccounts().first)
        let outcome = await claimer.claim(for: cred)
        XCTAssertEqual(outcome, .nothingToClaim)
        XCTAssertEqual(t.calls.count, 1, "无满足条件的活动不应发 POST")
        XCTAssertEqual(t.calls[0].method, "GET")
    }

    @MainActor
    func testReplayedIsSuccessButNotNewClaim() async throws {
        let dir = try makeTempPool(accounts: [("id1", "tok-1", "mach-1", "user-1")])
        let t = FakeCampaignTransport()
        t.defaultCampaigns = (200, campaignsJSON([("c-100", "CLAIM_BENEFIT", "CLAIMABLE")]))
        t.claimResult = (200, Data(#"{"grantId":"g1","status":"CLAIMED","replayed":true,"campaignId":"c-100"}"#.utf8))
        let claimer = QoderCampaignClaimer(transport: t, poolDirectory: dir, defaults: uniqueDefaults())
        let cred = try XCTUnwrap(claimer.scanAccounts().first)
        let outcome = await claimer.claim(for: cred)
        XCTAssertEqual(outcome, .alreadyClaimed)
    }

    // MARK: - 多账号失败隔离 + 每日去重

    @MainActor
    func testOneAccountFailureDoesNotBlockOthersAndDedupsSameDay() async throws {
        let dir = try makeTempPool(accounts: [
            ("id1", "tok-bad", "mach-1", "user-1"),
            ("id2", "tok-good", "mach-2", "user-2"),
        ])
        let t = FakeCampaignTransport()
        t.throwingBearers = ["Bearer tok-bad"]   // user-1 GET 直接抛错
        t.defaultCampaigns = (200, campaignsJSON([("c-100", "CLAIM_BENEFIT", "CLAIMABLE")]))
        let d = uniqueDefaults()
        let claimer = QoderCampaignClaimer(transport: t, poolDirectory: dir, defaults: d)

        await claimer.claimAllOncePerDay()

        // user-2 应该正常走完 GET+POST 两步
        XCTAssertTrue(t.calls.contains { $0.method == "POST" && $0.headers["Authorization"] == "Bearer tok-good" },
                      "user-1 失败不应阻止 user-2 领取")
        // user-1 失败不应该被标记为「今天已处理」，user-2 成功应该被标记
        XCTAssertNil(d.string(forKey: "qoder.campaign.claimed.user-1"))
        XCTAssertNotNil(d.string(forKey: "qoder.campaign.claimed.user-2"))

        // 再跑一次：user-2 已标记今天处理过，不应再次触发任何针对 tok-good 的请求
        let goodCallsAfterFirstRun = t.calls.filter { $0.headers["Authorization"] == "Bearer tok-good" }.count
        XCTAssertEqual(goodCallsAfterFirstRun, 2)   // GET + POST
        await claimer.claimAllOncePerDay()
        XCTAssertEqual(t.calls.filter { $0.headers["Authorization"] == "Bearer tok-good" }.count, goodCallsAfterFirstRun,
                       "当天已处理过的账号不应再次发起请求")
    }

    @MainActor
    func testSecondRunSkipsAlreadyProcessedAccount() async throws {
        let dir = try makeTempPool(accounts: [("id1", "tok-1", "mach-1", "user-1")])
        let t = FakeCampaignTransport()
        t.defaultCampaigns = (200, campaignsJSON([("c-100", "CLAIM_BENEFIT", "CLAIMABLE")]))
        let claimer = QoderCampaignClaimer(transport: t, poolDirectory: dir, defaults: uniqueDefaults())

        await claimer.claimAllOncePerDay()
        let firstRunCount = t.calls.count
        XCTAssertEqual(firstRunCount, 2)

        await claimer.claimAllOncePerDay()   // 同一天第二次调用
        XCTAssertEqual(t.calls.count, firstRunCount, "当天已处理过的账号不应再次发起任何请求")
    }

    // MARK: - 审查问题 1：部分成功 / 全部失败 / 无可领项 三种语义要区分开

    /// 多条可领活动，fake transport 按 campaignId 路由不同响应：一条成功、一条抛错 → 至少有一条成功，
    /// 应判定为 .claimed（而不是被"全部失败"分支误伤），且这个结果会写入今日标记。
    @MainActor
    func testPartialSuccessAcrossMultipleCampaignsIsStillClaimed() async throws {
        let dir = try makeTempPool(accounts: [("id1", "tok-1", "mach-1", "user-1")])
        let t = FakeCampaignTransport()
        t.defaultCampaigns = (200, campaignsJSON([
            ("c-ok", "CLAIM_BENEFIT", "CLAIMABLE"),
            ("c-bad", "CLAIM_BENEFIT", "CLAIMABLE"),
        ]))
        t.throwingCampaignIds = ["c-bad"]   // c-ok 走全局默认成功响应；c-bad POST 阶段抛错
        let d = uniqueDefaults()
        let claimer = QoderCampaignClaimer(transport: t, poolDirectory: dir, defaults: d)

        await claimer.claimAllOncePerDay()

        XCTAssertEqual(d.string(forKey: "qoder.campaign.claimed.user-1").map { _ in true }, true,
                       "至少有一条领取成功，应该写入今日标记")
        let posts = t.calls.filter { $0.method == "POST" }
        XCTAssertEqual(posts.count, 2, "两条可领活动都应尝试发 POST")
    }

    /// 多条可领活动全部 POST 都失败（无一条成功、也无幂等命中）→ 必须判定为 .failure，
    /// 不能像旧逻辑那样误判成 alreadyClaimed 并写入今日标记（否则当天漏领且不再重试）。
    @MainActor
    func testAllClaimsFailingReturnsFailureAndDoesNotMarkToday() async throws {
        let dir = try makeTempPool(accounts: [("id1", "tok-1", "mach-1", "user-1")])
        let t = FakeCampaignTransport()
        t.defaultCampaigns = (200, campaignsJSON([
            ("c-a", "CLAIM_BENEFIT", "CLAIMABLE"),
            ("c-b", "CLAIM_BENEFIT", "CLAIMABLE"),
        ]))
        t.throwingCampaignIds = ["c-a", "c-b"]   // 两条 POST 全部抛错
        let d = uniqueDefaults()
        let claimer = QoderCampaignClaimer(transport: t, poolDirectory: dir, defaults: d)

        await claimer.claimAllOncePerDay()

        XCTAssertNil(d.string(forKey: "qoder.campaign.claimed.user-1"),
                     "全部失败不应该写入今日标记，否则当天不会重试")
    }

    /// GET 成功但当前没有任何可领活动（比如还没到每日刷新点）→ .nothingToClaim，
    /// 同样不写今日标记，留待下一次触发重新查一遍（审查问题 1a）。
    @MainActor
    func testNothingToClaimDoesNotMarkTodayAndRetriesOnNextTrigger() async throws {
        let dir = try makeTempPool(accounts: [("id1", "tok-1", "mach-1", "user-1")])
        let t = FakeCampaignTransport()
        t.defaultCampaigns = (200, campaignsJSON([]))   // 空列表
        let d = uniqueDefaults()
        let claimer = QoderCampaignClaimer(transport: t, poolDirectory: dir, defaults: d)

        await claimer.claimAllOncePerDay()
        XCTAssertNil(d.string(forKey: "qoder.campaign.claimed.user-1"))
        XCTAssertEqual(t.calls.count, 1, "第一次触发只发了 GET")

        // 模拟活动刷新窗口到了：列表里现在有了可领项
        t.defaultCampaigns = (200, campaignsJSON([("c-new", "CLAIM_BENEFIT", "CLAIMABLE")]))
        await claimer.claimAllOncePerDay()
        XCTAssertNotNil(d.string(forKey: "qoder.campaign.claimed.user-1"),
                        "第二次触发时列表已有可领项，应完成领取并写入今日标记")
        XCTAssertEqual(t.calls.count, 3, "第二次触发应再发一次 GET + 一次 POST")
    }

    // MARK: - 审查修复 1：in-flight 并发守卫

    /// 纯状态机断言：守卫的语义是「空闲时可占用、已占用时拒绝、结束后可再次占用」。
    /// 把判断抽成纯函数就是为了不依赖异步时序也能稳定验证这条规则。
    func testGuardStateMachineAllowsOnlyOneConcurrentSweep() {
        var running = false
        let first = QoderCampaignGuard.begin(isRunning: running)
        XCTAssertTrue(first.shouldRun, "空闲时应允许开始")
        running = first.isRunning

        let second = QoderCampaignGuard.begin(isRunning: running)
        XCTAssertFalse(second.shouldRun, "已有一轮在跑时第二次必须跳过")
        XCTAssertEqual(second.isRunning, true, "被拒绝的触发不得改动标志位")

        running = QoderCampaignGuard.end()
        XCTAssertEqual(running, false, "一轮结束后必须释放")
        XCTAssertTrue(QoderCampaignGuard.begin(isRunning: running).shouldRun, "释放后应能再次开始")
    }

    /// 端到端交错验证：用一个"闸门"transport 让第一轮巡检卡在 GET 上不返回，
    /// 期间发起第二轮，断言第二轮没有产生任何新的 transport 请求（即守卫真的挡住了），
    /// 再放行闸门，断言第一轮正常收尾、守卫复位后后续轮次仍能正常领取。
    func testOverlappingTriggerDoesNotIssueExtraRequests() async throws {
        let dir = try makeTempPool(accounts: [("id1", "tok-1", "mach-1", "user-1")])
        let t = GatedCampaignTransport()
        t.gateMode = true
        t.defaultCampaigns = (200, campaignsJSON([("c-100", "CLAIM_BENEFIT", "CLAIMABLE")]))
        let d = uniqueDefaults()
        let claimer = QoderCampaignClaimer(transport: t, poolDirectory: dir, defaults: d)

        // 第一轮：会挂在第一次 GET 上直到我们放行闸门
        let firstTask = Task.detached { await claimer.claimAllOncePerDay() }
        await t.waitUntilFirstRequestArrives()
        XCTAssertEqual(t.requestCount, 1, "第一轮应已发出 GET 并被闸门挡住")

        // 第二轮：与第一轮真正并发，应被守卫直接跳过
        await claimer.claimAllOncePerDay()
        XCTAssertEqual(t.requestCount, 1, "重入的触发不应发出任何新请求")
        XCTAssertNil(d.string(forKey: "qoder.campaign.claimed.user-1"))

        // 放行第一轮，等它正常跑完
        t.openGate()
        await firstTask.value
        XCTAssertEqual(t.requestCount, 2, "第一轮应完成 GET + POST")
        XCTAssertNotNil(d.string(forKey: "qoder.campaign.claimed.user-1"), "守卫不应影响正常收尾写标记")

        // 守卫复位验证：换新默认值后在同一 claimer 上再触发一轮。
        // 此刻 user-1 已有今日标记会被 continue 跳过（不发请求），但循环确实进入了、函数正常返回，
        // 说明 isRunning 已释放；若没释放，这次调用会在守卫处直接 return（用下面的日志/行为区分不出来，
        // 故再用第二个 claimer 走一遍真正发请求的路径作为硬证据）。
        t.resetForNextRound()
        t.defaultCampaigns = (200, campaignsJSON([("c-200", "CLAIM_BENEFIT", "CLAIMABLE")]))
        await claimer.claimAllOncePerDay()

        let dir2 = try makeTempPool(accounts: [("id2", "tok-2", "mach-2", "user-2")])
        let claimer2 = QoderCampaignClaimer(transport: t, poolDirectory: dir2, defaults: d)
        await claimer2.claimAllOncePerDay()
        XCTAssertEqual(t.requestCount, 4, "守卫复位后新一轮应再发 GET + POST")
        XCTAssertNotNil(d.string(forKey: "qoder.campaign.claimed.user-2"),
                        "上一轮结束后守卫必须已复位，否则后续永远不会再领取")
    }

    // MARK: - 任务 3：每日签到状态记录、按天隔离与展示文案

    /// 当天日期字符串（与 claimer 内部同口径：en_US_POSIX + 默认时区），用于预置/断言按天 Key。
    private func todayString(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    /// 单轮签到跑完，结果既进内存状态也持久化；换一个新实例（模拟 App 重启）读同一份 defaults 仍能看到状态。
    func testClaimStatusTrackingAndPersistence() async throws {
        let dir = try makeTempPool(accounts: [("id1", "tok-1", "mach-1", "user-1")])
        let t = FakeCampaignTransport()
        t.defaultCampaigns = (200, campaignsJSON([("c-100", "CLAIM_BENEFIT", "CLAIMABLE")]))
        let d = uniqueDefaults()
        let claimer = QoderCampaignClaimer(transport: t, poolDirectory: dir, defaults: d)

        let outcomes = await claimer.claimAll()
        XCTAssertEqual(outcomes["user-1"], .claimed, "claimAll() 应把本轮各账号结果回传，供 UI 直接取用")
        XCTAssertEqual(claimer.statusDescription(for: "user-1"), "已领取")
        XCTAssertEqual(QoderCampaignClaimer.claimedCount(in: claimer.dailyOutcomes), 1)

        // Key 必须带当天日期，隔天自然重置（而不是靠手动清理旧 Key）
        let outcomeKeys = d.dictionaryRepresentation().keys.filter { $0.hasPrefix("QoderCampaignClaimer_outcomes_") }
        XCTAssertEqual(outcomeKeys, ["QoderCampaignClaimer_outcomes_\(todayString())"])

        // 模拟重启：新实例、同一份 UserDefaults，仍应读到今天的签到状态（且不再重复发请求）
        let t2 = FakeCampaignTransport()
        t2.defaultCampaigns = (200, campaignsJSON([("c-100", "CLAIM_BENEFIT", "CLAIMABLE")]))
        let revived = QoderCampaignClaimer(transport: t2, poolDirectory: dir, defaults: d)
        XCTAssertEqual(revived.statusDescription(for: "user-1"), "已领取", "签到状态必须跨重启保留")
        await revived.claimAll()
        XCTAssertEqual(t2.calls.count, 0, "今日已处理过的账号重启后不应再次发起请求")
    }

    /// 状态文案映射是纯函数，逐条钉死（含无记录 = 待签到），UI 与 tooltip 共用同一口径。
    func testStatusTextMapsEveryOutcome() {
        XCTAssertEqual(QoderCampaignClaimer.statusText(for: .claimed), "已领取")
        XCTAssertEqual(QoderCampaignClaimer.statusText(for: .alreadyClaimed), "今日已领过")
        XCTAssertEqual(QoderCampaignClaimer.statusText(for: .nothingToClaim), "待签到")
        XCTAssertEqual(QoderCampaignClaimer.statusText(for: nil), "待签到", "当天没有任何记录也归待签到")
        XCTAssertEqual(QoderCampaignClaimer.statusText(for: .failure("boom")), "签到失败(boom)")
    }

    /// 「已领取」统计口径：claimed 与 alreadyClaimed 都算今天拿到过，nothingToClaim / failure 不算。
    func testClaimedCountCountsOnlyClaimedAndAlreadyClaimed() {
        let outcomes: [String: QoderClaimOutcome] = [
            "a": .claimed, "b": .alreadyClaimed, "c": .nothingToClaim, "d": .failure("boom"),
        ]
        XCTAssertEqual(QoderCampaignClaimer.claimedCount(in: outcomes), 2)
        XCTAssertEqual(QoderCampaignClaimer.claimedCount(in: [:]), 0)
    }

    /// 按天隔离：日期翻篇后当天的状态字典自然为空，不依赖后台清理任务。
    func testDailyOutcomesResetOnNewDay() async throws {
        let dir = try makeTempPool(accounts: [("id1", "tok-1", "mach-1", "user-1")])
        let t = FakeCampaignTransport()
        t.defaultCampaigns = (200, campaignsJSON([("c-100", "CLAIM_BENEFIT", "CLAIMABLE")]))
        let d = uniqueDefaults()
        var day = Date(timeIntervalSince1970: 1_700_000_000)
        let claimer = QoderCampaignClaimer(transport: t, poolDirectory: dir, defaults: d, now: { day })

        await claimer.claimAll()
        XCTAssertEqual(claimer.statusDescription(for: "user-1"), "已领取")

        day = day.addingTimeInterval(86_400)   // 恰好 24 小时后必然跨到下一个日历日
        XCTAssertTrue(claimer.dailyOutcomes.isEmpty, "隔天读取应自然重置为空")
        XCTAssertEqual(claimer.statusDescription(for: "user-1"), "待签到")
    }

    /// 老版本只写了「今日已处理」标记、没有当日状态字典：升级后既要继续跳过该账号（不重复领），
    /// 又要把展示态补齐成「今日已领过」，避免 UI 谎报「待签到」。
    func testLegacyTodayMarkerBackfillsAlreadyClaimedStatus() async throws {
        let dir = try makeTempPool(accounts: [("id1", "tok-1", "mach-1", "user-1")])
        let t = FakeCampaignTransport()
        t.defaultCampaigns = (200, campaignsJSON([("c-100", "CLAIM_BENEFIT", "CLAIMABLE")]))
        let d = uniqueDefaults()
        d.set(todayString(), forKey: "qoder.campaign.claimed.user-1")
        let claimer = QoderCampaignClaimer(transport: t, poolDirectory: dir, defaults: d)

        await claimer.claimAll()
        XCTAssertEqual(t.calls.count, 0, "仅有标记时仍须走去重分支，不重复领取")
        XCTAssertEqual(claimer.statusDescription(for: "user-1"), "今日已领过")
        XCTAssertEqual(QoderCampaignClaimer.claimedCount(in: claimer.dailyOutcomes), 1)
    }

    /// 失败的账号也要留痕（tooltip 能看到原因），但绝不能被算进「今日已签到」进度分子。
    func testFailureOutcomeIsRecordedButNotCountedAsClaimed() async throws {
        let dir = try makeTempPool(accounts: [("id1", "tok-1", "mach-1", "user-1")])
        let t = FakeCampaignTransport()
        t.throwingBearers = ["Bearer tok-1"]
        t.defaultCampaigns = (200, campaignsJSON([("c-100", "CLAIM_BENEFIT", "CLAIMABLE")]))
        let d = uniqueDefaults()
        let claimer = QoderCampaignClaimer(transport: t, poolDirectory: dir, defaults: d)

        let outcomes = await claimer.claimAll()
        guard case .failure = outcomes["user-1"] else {
            return XCTFail("GET 抛错应记录为 .failure，实际 \(String(describing: outcomes["user-1"]))")
        }
        XCTAssertTrue(claimer.statusDescription(for: "user-1").hasPrefix("签到失败"),
                      "tooltip 需以「签到失败」开头带上原因")
        XCTAssertEqual(QoderCampaignClaimer.claimedCount(in: claimer.dailyOutcomes), 0)
        XCTAssertNil(d.string(forKey: "qoder.campaign.claimed.user-1"), "失败不得写今日去重标记")
    }
}

/// 可控闸门 transport：gateMode 下第一次 request 会挂起，直到 openGate() 被调用。
/// 用于确定性地制造"两轮巡检真实重叠"的时序，而不是靠 sleep 猜时间窗（那种写法容易 flaky）。
private final class GatedCampaignTransport: QoderCampaignTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _gateMode = false
    private var _gateReleased = false
    private var _count = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var arrivalContinuations: [CheckedContinuation<Void, Never>] = []

    /// 是否启用闸门（只挡整场测试的第一次请求）。必须在发起任何调用之前设好。
    var gateMode: Bool {
        get { lock.withLock { _gateMode } }
        set { lock.withLock { _gateMode = newValue } }
    }
    var defaultCampaigns: (status: Int, data: Data)?
    var requestCount: Int { lock.withLock { _count } }

    func waitUntilFirstRequestArrives() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.withLock { arrivalContinuations.append(c) }
        }
    }

    /// 放行挂起中的第一次请求。
    func openGate() {
        let pending: [CheckedContinuation<Void, Never>] = lock.withLock {
            _gateReleased = true
            let list = continuations
            continuations = []
            return list
        }
        pending.forEach { $0.resume() }
    }

    /// 彻底结束闸门语义：之后的请求一律立即返回。
    func resetForNextRound() {
        lock.withLock { _gateMode = false; _gateReleased = true }
    }

    func request(url: URL, method: String, headers: [String: String], body: Data?) async throws -> (status: Int, data: Data) {
        let shouldWait: Bool = lock.withLock {
            _count += 1
            // 只挡住整场测试的第一次请求：够用来维持 in-flight 窗口，又不会卡死收尾
            return _gateMode && _count == 1
        }
        let arrivals: [CheckedContinuation<Void, Never>] = lock.withLock {
            let n = arrivalContinuations
            arrivalContinuations = []
            return n
        }
        arrivals.forEach { $0.resume() }
        if shouldWait {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                let alreadyResumed: Bool = lock.withLock {
                    if _gateReleased { return true }
                    continuations.append(c)
                    return false
                }
                if alreadyResumed { c.resume() }
            }
        }
        if url.path.hasSuffix("/campaigns") {
            return defaultCampaigns ?? (200, Data())
        }
        return (200, Data(#"{"status":"CLAIMED","replayed":false}"#.utf8))
    }
}
