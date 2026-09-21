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
        // POST .../claim
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
}
