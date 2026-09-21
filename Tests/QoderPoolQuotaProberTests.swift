//
//  QoderPoolQuotaProberTests.swift
//  NotchEveryTests
//
//  QoderPoolQuotaProber 契约测试：GET /api/v2/quota/usage 的 URL/method/headers 构造、
//  嵌套 userQuota/addOnQuota 解析口径（plan+addOn 相加）、单号失败隔离。全程假 transport，绝不真联网。
//

import XCTest
@testable import NotchEvery

/// 假 transport：按 Authorization 头路由每个账号各自的响应；记录每次调用供断言。
private final class FakeQuotaTransport: QoderCampaignTransport {
    struct Call {
        let url: URL
        let method: String
        let headers: [String: String]
        let body: Data?
    }
    var calls: [Call] = []
    /// key = Bearer token，value = 该账号 GET 响应
    var responseByBearer: [String: (status: Int, data: Data)] = [:]
    var defaultResponse: (status: Int, data: Data) = (200, Data())
    /// 抛错的 bearer 集合
    var throwingBearers: Set<String> = []

    func request(url: URL, method: String, headers: [String: String], body: Data?) async throws -> (status: Int, data: Data) {
        calls.append(Call(url: url, method: method, headers: headers, body: body))
        let bearer = headers["Authorization"] ?? ""
        if throwingBearers.contains(bearer) { throw URLError(.cannotConnectToHost) }
        return responseByBearer[bearer] ?? defaultResponse
    }
}

final class QoderPoolQuotaProberTests: XCTestCase {

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

    /// 真实抓包样例：嵌套结构，remaining 为浮点。
    private func usageJSON(userId: String, planRemaining: Double?, addOnRemaining: Double?) -> Data {
        var parts = ["\"userId\":\"\(userId)\""]
        if let p = planRemaining {
            parts.append("\"userQuota\":{\"total\":300,\"used\":\(300 - p),\"remaining\":\(p),\"unit\":\"credits\",\"percentage\":0}")
        }
        if let a = addOnRemaining {
            parts.append("\"addOnQuota\":{\"total\":100,\"used\":\(100 - a),\"remaining\":\(a),\"unit\":\"credits\",\"percentage\":0}")
        }
        return Data("{\(parts.joined(separator: ","))}".utf8)
    }

    // MARK: - 解析口径

    @MainActor
    func testPlanAndAddBothPresentSumsBoth() async throws {
        let dir = try makeTempPool(accounts: [("id1", "tok-1", "mach-1", "user-1")])
        let t = FakeQuotaTransport()
        t.responseByBearer["Bearer tok-1"] = (200, usageJSON(userId: "user-1", planRemaining: 300, addOnRemaining: 100))
        let prober = QoderPoolQuotaProber(transport: t, poolDirectory: dir)

        let quotas = await prober.probeAll()
        XCTAssertEqual(quotas.count, 1)
        XCTAssertEqual(quotas[0].userId, "user-1")
        XCTAssertEqual(quotas[0].planRemaining, 300, accuracy: 0.001)
        XCTAssertEqual(quotas[0].addOnRemaining, 100, accuracy: 0.001)
        XCTAssertEqual(quotas[0].totalRemaining, 400, accuracy: 0.001, "总额应为 plan+addOn 相加")
    }

    @MainActor
    func testMissingAddOnCountsAsZero() async throws {
        let dir = try makeTempPool(accounts: [("id1", "tok-1", "mach-1", "user-1")])
        let t = FakeQuotaTransport()
        // addOnQuota 字段整体缺失
        t.responseByBearer["Bearer tok-1"] = (200, usageJSON(userId: "user-1", planRemaining: 250.5, addOnRemaining: nil))
        let prober = QoderPoolQuotaProber(transport: t, poolDirectory: dir)

        let quotas = await prober.probeAll()
        XCTAssertEqual(quotas.count, 1)
        XCTAssertEqual(quotas[0].planRemaining, 250.5, accuracy: 0.001)
        XCTAssertEqual(quotas[0].addOnRemaining, 0, accuracy: 0.001)
        XCTAssertEqual(quotas[0].totalRemaining, 250.5, accuracy: 0.001, "缺 addOn 时总额只算 plan")
    }

    @MainActor
    func testNullAddOnCountsAsZero() async throws {
        let dir = try makeTempPool(accounts: [("id1", "tok-1", "mach-1", "user-1")])
        let t = FakeQuotaTransport()
        // addOnQuota 显式为 null（真实上游会这样返回）
        t.responseByBearer["Bearer tok-1"] = (200, Data(#"{"userId":"user-1","userQuota":{"total":300,"used":0,"remaining":300.0,"unit":"credits"},"addOnQuota":null}"#.utf8))
        let prober = QoderPoolQuotaProber(transport: t, poolDirectory: dir)

        let quotas = await prober.probeAll()
        XCTAssertEqual(quotas.count, 1)
        XCTAssertEqual(quotas[0].totalRemaining, 300, accuracy: 0.001)
    }

    // MARK: - 请求构造

    @MainActor
    func testRequestCarriesCorrectUrlMethodAndCredentialHeaders() async throws {
        let dir = try makeTempPool(accounts: [("id1", "tok-1", "mach-1", "user-1")])
        let t = FakeQuotaTransport()
        t.responseByBearer["Bearer tok-1"] = (200, usageJSON(userId: "user-1", planRemaining: 300, addOnRemaining: 100))
        let prober = QoderPoolQuotaProber(transport: t, poolDirectory: dir)

        _ = await prober.probeAll()
        XCTAssertEqual(t.calls.count, 1, "应恰好一次 GET")
        let call = t.calls[0]
        XCTAssertEqual(call.url.absoluteString, "https://gateway.qoder.com.cn/api/v2/quota/usage")
        XCTAssertEqual(call.method, "GET")
        XCTAssertNil(call.body, "GET 不应带 body")
        for (k, v) in ["Authorization": "Bearer tok-1", "Cosy-ClientType": "10", "Cosy-Version": "0.1.18",
                       "Cosy-MachineOS": "darwin", "Cosy-MachineId": "mach-1", "User-Agent": "Qoder",
                       "Accept": "application/json"] {
            XCTAssertEqual(call.headers[k], v, "缺少正确的 \(k) 头")
        }
        XCTAssertNil(call.headers["Content-Type"], "GET 不应带 Content-Type")
    }

    @MainActor
    func testEachAccountGetsItsOwnCredentialHeaders() async throws {
        let dir = try makeTempPool(accounts: [
            ("id1", "tok-1", "mach-1", "user-1"),
            ("id2", "tok-2", "mach-2", "user-2"),
        ])
        let t = FakeQuotaTransport()
        t.responseByBearer["Bearer tok-1"] = (200, usageJSON(userId: "user-1", planRemaining: 400, addOnRemaining: nil))
        t.responseByBearer["Bearer tok-2"] = (200, usageJSON(userId: "user-2", planRemaining: 100, addOnRemaining: 50))
        let prober = QoderPoolQuotaProber(transport: t, poolDirectory: dir)

        let quotas = await prober.probeAll()
        XCTAssertEqual(Set(quotas.map(\.userId)), ["user-1", "user-2"])
        XCTAssertEqual(t.calls.count, 2)
        let byBearer = Dictionary(uniqueKeysWithValues: t.calls.map { ($0.headers["Authorization"] ?? "", $0) })
        XCTAssertEqual(byBearer["Bearer tok-1"]?.headers["Cosy-MachineId"], "mach-1")
        XCTAssertEqual(byBearer["Bearer tok-2"]?.headers["Cosy-MachineId"], "mach-2",
                       "第二个号的 Cosy-MachineId 必须取自它自己的凭证，不能串号")
    }

    // MARK: - 失败隔离

    @MainActor
    func testThrowingAccountIsSkippedButOthersSurvive() async throws {
        let dir = try makeTempPool(accounts: [
            ("id1", "tok-bad", "mach-1", "user-1"),
            ("id2", "tok-good", "mach-2", "user-2"),
        ])
        let t = FakeQuotaTransport()
        t.throwingBearers = ["Bearer tok-bad"]
        t.responseByBearer["Bearer tok-good"] = (200, usageJSON(userId: "user-2", planRemaining: 100, addOnRemaining: 100))
        let prober = QoderPoolQuotaProber(transport: t, poolDirectory: dir)

        let quotas = await prober.probeAll()
        XCTAssertEqual(quotas.count, 1, "抛错的号应被跳过")
        XCTAssertEqual(quotas.first?.userId, "user-2", "其它号必须照常返回")
    }

    @MainActor
    func testNon2xxStatusIsSkippedButOthersSurvive() async throws {
        let dir = try makeTempPool(accounts: [
            ("id1", "tok-401", "mach-1", "user-1"),
            ("id2", "tok-ok", "mach-2", "user-2"),
        ])
        let t = FakeQuotaTransport()
        t.responseByBearer["Bearer tok-401"] = (401, Data(#"{"error":"unauthorized"}"#.utf8))
        t.responseByBearer["Bearer tok-ok"] = (200, usageJSON(userId: "user-2", planRemaining: 20, addOnRemaining: nil))
        let prober = QoderPoolQuotaProber(transport: t, poolDirectory: dir)

        let quotas = await prober.probeAll()
        XCTAssertEqual(quotas.count, 1)
        XCTAssertEqual(try XCTUnwrap(quotas.first).userId, "user-2")
        XCTAssertEqual(try XCTUnwrap(quotas.first).totalRemaining, 20, accuracy: 0.001)
    }

    @MainActor
    func testUndecodableBodyIsSkippedButOthersSurvive() async throws {
        let dir = try makeTempPool(accounts: [
            ("id1", "tok-junk", "mach-1", "user-1"),
            ("id2", "tok-ok", "mach-2", "user-2"),
        ])
        let t = FakeQuotaTransport()
        t.responseByBearer["Bearer tok-junk"] = (200, Data("<html>not json</html>".utf8))
        t.responseByBearer["Bearer tok-ok"] = (200, usageJSON(userId: "user-2", planRemaining: 7, addOnRemaining: 3))
        let prober = QoderPoolQuotaProber(transport: t, poolDirectory: dir)

        let quotas = await prober.probeAll()
        XCTAssertEqual(quotas.count, 1)
        XCTAssertEqual(try XCTUnwrap(quotas.first).userId, "user-2")
        XCTAssertEqual(try XCTUnwrap(quotas.first).totalRemaining, 10, accuracy: 0.001)
    }

    @MainActor
    func testEmptyPoolReturnsEmptyWithoutAnyRequest() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pool-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let t = FakeQuotaTransport()
        let prober = QoderPoolQuotaProber(transport: t, poolDirectory: dir)

        let quotas = await prober.probeAll()
        XCTAssertTrue(quotas.isEmpty)
        XCTAssertEqual(t.calls.count, 0, "没有凭证文件时不应发任何请求")
    }

    // MARK: - in-flight 守卫

    /// 纯状态机断言（与 claimer 同款写法）：空闲时可占用、已占用时拒绝、结束后可再次占用。
    func testGuardStateMachineAllowsOnlyOneConcurrentProbe() {
        var running = false
        let first = QoderPoolQuotaGuard.begin(isRunning: running)
        XCTAssertTrue(first.shouldRun, "空闲时应允许开始")
        running = first.isRunning

        let second = QoderPoolQuotaGuard.begin(isRunning: running)
        XCTAssertFalse(second.shouldRun, "已有一轮在跑时第二次必须跳过")
        XCTAssertEqual(second.isRunning, true, "被拒绝的触发不得改动标志位")

        running = QoderPoolQuotaGuard.end()
        XCTAssertEqual(running, false, "一轮结束后必须释放")
        XCTAssertTrue(QoderPoolQuotaGuard.begin(isRunning: running).shouldRun, "释放后应能再次开始")
    }
}
