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
}
