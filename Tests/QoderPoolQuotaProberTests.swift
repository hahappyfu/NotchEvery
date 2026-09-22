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

        let raw = await prober.probeAll()
        let quotas = try XCTUnwrap(raw, "正常跑完的探测必须返回非 nil（nil 专用于被守卫跳过）")
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

        let raw = await prober.probeAll()
        let quotas = try XCTUnwrap(raw, "正常跑完的探测必须返回非 nil（nil 专用于被守卫跳过）")
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

        let raw = await prober.probeAll()
        let quotas = try XCTUnwrap(raw, "正常跑完的探测必须返回非 nil（nil 专用于被守卫跳过）")
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

        let raw = await prober.probeAll()
        XCTAssertNotNil(raw, "正常跑完的探测必须返回非 nil")
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

        let raw = await prober.probeAll()
        let quotas = try XCTUnwrap(raw, "正常跑完的探测必须返回非 nil（nil 专用于被守卫跳过）")
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

        let raw = await prober.probeAll()
        let quotas = try XCTUnwrap(raw, "正常跑完的探测必须返回非 nil（nil 专用于被守卫跳过）")
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

        let raw = await prober.probeAll()
        let quotas = try XCTUnwrap(raw, "正常跑完的探测必须返回非 nil（nil 专用于被守卫跳过）")
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

        let raw = await prober.probeAll()
        let quotas = try XCTUnwrap(raw, "正常跑完的探测必须返回非 nil（nil 专用于被守卫跳过）")
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

        let raw = await prober.probeAll()
        let quotas = try XCTUnwrap(raw, "正常跑完的探测必须返回非 nil（nil 专用于被守卫跳过）")
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

    /// 端到端交错验证（照搬 claimer 的 GatedCampaignTransport 测法，不靠 sleep 猜时间窗）：
    /// 闸门让第一轮探测卡在 GET 上不返回，期间发起第二轮。断言两件事：
    /// ① 第二轮没有发出任何新请求（守卫真的挡住了）；
    /// ② **第二轮返回 nil 而不是 []** —— 这是本 bug 的关键契约：被跳过的轮次必须让调用方
    ///    能区分出"这次没探"，否则上层会把这份空数组当成探测结果覆盖掉已有的好数据。
    @MainActor
    func testOverlappingTriggerReturnsNilInsteadOfEmptyArray() async throws {
        let dir = try makeTempPool(accounts: [("id1", "tok-1", "mach-1", "user-1")])
        let t = GatedQuotaTransport()
        t.gateMode = true
        t.responseByBearer["Bearer tok-1"] = (200, usageJSON(userId: "user-1", planRemaining: 300, addOnRemaining: 100))
        let prober = QoderPoolQuotaProber(transport: t, poolDirectory: dir)

        // 第一轮：挂在第一次 GET 上直到放行闸门
        let firstTask = Task.detached { await prober.probeAll() }
        await t.waitUntilFirstRequestArrives()
        XCTAssertEqual(t.requestCount, 1, "第一轮应已发出 GET 并被闸门挡住")

        // 第二轮：与第一轮真正并发 → 守卫拒绝 → 必须是 nil
        let second = await prober.probeAll()
        XCTAssertNil(second, "被 in-flight 守卫跳过时必须返回 nil（表示'这次没探'），返回 [] 会让上层把已有余额冲成空")
        XCTAssertEqual(t.requestCount, 1, "重入的触发不应发出任何新请求")

        // 放行第一轮，断言它正常收尾并拿到真值
        t.openGate()
        let firstRaw = await firstTask.value
        let first = try XCTUnwrap(firstRaw, "正常跑完的轮次必须返回非 nil")
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first[0].totalRemaining, 400, accuracy: 0.001)

        // 守卫复位硬证据：闸门关掉后再触发一轮，应真的重新发请求并返回非 nil
        t.resetForNextRound()
        let thirdRaw = await prober.probeAll()
        let third = try XCTUnwrap(thirdRaw, "上一轮结束后守卫必须已复位，否则后续永远探不到数")
        XCTAssertEqual(third.count, 1)
        XCTAssertEqual(t.requestCount, 2, "守卫复位后新一轮应重新发请求")
    }

    // MARK: - 余额浮点安全取整（防 Int(Double) runtime trap 闪退）

    func testSafeCreditsIntRejectsNonFiniteNegativeAndOutOfRange() {
        XCTAssertNil(Double.nan.safeCreditsInt, "NaN 直接 Int() 会 trap")
        XCTAssertNil(Double.infinity.safeCreditsInt, "+∞ 直接 Int() 会 trap")
        XCTAssertNil((-Double.infinity).safeCreditsInt, "-∞ 直接 Int() 会 trap")
        XCTAssertNil((-1.0).safeCreditsInt, "负余额不展示")
        XCTAssertNil(Double(Int.max).safeCreditsInt, "恰好 Double(Int.max) 已是 2^63，超出 Int 可表示上界")
        XCTAssertNil(1e300.safeCreditsInt, "无界极端值拦截")
    }

    func testSafeCreditsIntConvertsNormalValues() {
        XCTAssertEqual(0.0.safeCreditsInt, 0)
        XCTAssertEqual(250.5.safeCreditsInt, 250)
        XCTAssertEqual(400.0.safeCreditsInt, 400)
    }

    func testSafeCreditsTextFallsBackToPlaceholderOnIllegalValues() {
        XCTAssertEqual(400.0.safeCreditsText, "400")
        XCTAssertEqual(Double.nan.safeCreditsText, "--")
        XCTAssertEqual(Double.infinity.safeCreditsText, "--")
        XCTAssertEqual((-5.0).safeCreditsText, "--")
    }
}

/// 可控闸门 transport：gateMode 下只挡整场测试的第一次 request，用于确定性地制造"两轮探测真实重叠"
/// 的时序（与 QoderCampaignClaimerTests 的 GatedCampaignTransport 同款思路，避免 sleep 导致 flaky）。
private final class GatedQuotaTransport: QoderCampaignTransport, @unchecked Sendable {
    private let lock = UnfairLock()
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
    var responseByBearer: [String: (status: Int, data: Data)] = [:]
    var requestCount: Int { lock.withLock { _count } }

    func waitUntilFirstRequestArrives() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.withLock { arrivalContinuations.append(c) }
        }
    }

    /// 放行挂起中的请求。
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
        return responseByBearer[headers["Authorization"] ?? ""] ?? (200, Data())
    }
}
