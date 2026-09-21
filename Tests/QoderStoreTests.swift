//
//  QoderStoreTests.swift
//  NotchEveryTests
//
//  任务 6：QoderStore 的解码契约 + isStale 语义 + 发布去重。网络经假 transport 注入，不真联网。
//

import XCTest
@testable import NotchEvery

/// 假 transport：按 URL path 返回预置 Data / 抛错。
private final class FakeTransport: QoderHTTPTransport {
    var quotaData: Data?
    var poolData: Data?
    var shouldFail = false
    func get(url: URL, bearer: String) async throws -> Data {
        if shouldFail { throw URLError(.cannotConnectToHost) }
        if url.path.hasSuffix("/quota") { return quotaData ?? Data() }
        if url.path.hasSuffix("/pool/status") { return poolData ?? Data() }
        return Data()
    }
}

/// 假 prober：非 actor class（QoderPoolQuotaProbing 要求 AnyObject），直接返回预置额度数组，绝不真联网。
/// `result` 为 nil 模拟「本轮探测被 in-flight 守卫挡掉、什么都没探」；为 [] 模拟「探测跑完了但一个号都没查到」。
private final class FakeQuotaProberStub: QoderPoolQuotaProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount = 0
    var callCount: Int { lock.lock(); defer { lock.unlock() }; return _callCount }
    var result: [QoderAccountQuota]?
    init(result: [QoderAccountQuota]?) { self.result = result }
    func probeAll() async -> [QoderAccountQuota]? {
        lock.lock(); _callCount += 1; lock.unlock()
        return result
    }
}

final class QoderStoreTests: XCTestCase {

    private func fixture(_ name: String, _ ext: String) -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("Fixtures/\(name).\(ext)")
        return (try? Data(contentsOf: url)) ?? Data()
    }

    // MARK: - /quota 解码 golden

    func testQuotaDecodesGoldenFields() throws {
        let q = try XCTUnwrap(QoderQuota.decode(fixture("quota", "json")))
        XCTAssertEqual(q.userType, "personal_professional_trial")
        XCTAssertEqual(q.unit, "credits")
        XCTAssertEqual(q.total, 300)
        XCTAssertEqual(q.used, 0)
        XCTAssertEqual(q.remaining, 300)
        XCTAssertFalse(q.isExceeded)
        // reset_at_ms → Date
        XCTAssertEqual(q.resetDate?.timeIntervalSince1970 ?? 0, 1791104839.834, accuracy: 0.5)
    }

    func testQuotaDecodeGarbageReturnsNil() {
        XCTAssertNil(QoderQuota.decode(Data("not json".utf8)))
        XCTAssertNil(QoderQuota.decode(Data()))
    }

    // MARK: - /v1/pool/status 解码 golden（供圆形池）

    func testPoolStatusDecodesMembers() throws {
        let parsed = try XCTUnwrap(QoderPoolStatus.decode(fixture("pool-status", "json")))
        XCTAssertEqual(parsed.totalAccounts, 4)
        XCTAssertEqual(parsed.activeAccounts, 4)
        XCTAssertEqual(parsed.cooledAccounts, 0)
        XCTAssertEqual(parsed.accounts.count, 4)
        XCTAssertTrue(parsed.accounts.allSatisfy { !$0.cooled })
        // sticky 与 accounts 尾号一致校验
        XCTAssertEqual(parsed.stickyUserId, parsed.accounts.last?.userId)
    }

    // MARK: - 未托管时直接离线空态，不发请求也不误报 stale

    @MainActor
    func testGatewayDownShortCircuitsToEmptyOffline() async {
        let t = FakeTransport()
        t.quotaData = fixture("quota", "json")   // 即使 transport 有数据可给
        let store = QoderStore(port: 8096, transport: t)
        await store.refreshNow(gatewayUp: false) // 网关没在跑
        XCTAssertNil(store.quota, "未托管不应消费任何响应")
        XCTAssertTrue(store.poolMembers.isEmpty)
        XCTAssertFalse(store.isQuotaStale, "未托管是正常离线态，不是故障 stale")
    }

    // MARK: - isStale：连续失败 ≥2 ⇒ stale；成功即清除

    @MainActor
    func testStaleAfterTwoConsecutiveFailures() async {
        let t = FakeTransport()
        t.shouldFail = true
        let store = QoderStore(port: 8096, transport: t)
        await store.refreshNow()
        XCTAssertFalse(store.isQuotaStale, "单次失败不算 stale")
        await store.refreshNow()
        XCTAssertTrue(store.isQuotaStale, "连续两次失败应 stale")

        t.shouldFail = false
        t.quotaData = fixture("quota", "json")
        await store.refreshNow()
        XCTAssertFalse(store.isQuotaStale, "成功后 stale 标志清除")
        XCTAssertNotNil(store.quota)
    }

    // MARK: - 发布去重：同值不重复 publish

    @MainActor
    func testPublishDedupOnIdenticalValue() async {
        let t = FakeTransport()
        t.quotaData = fixture("quota", "json")
        t.poolData = fixture("pool-status", "json")
        let store = QoderStore(port: 8096, transport: t)
        await store.refreshNow()
        let first = store.objectWillChangeCountForTest
        await store.refreshNow()   // 完全相同数据
        XCTAssertEqual(store.objectWillChangeCountForTest, first, "同值不应再次 objectWillChange")
    }

    // MARK: - poolTotalRemaining 求和口径（纯逻辑，直接喂 poolQuotas）

    @MainActor
    func testPoolTotalRemainingEmptyIsNil() {
        let store = QoderStore(port: 8096, transport: FakeTransport())
        XCTAssertNil(store.poolTotalRemaining, "未探测到任何账号余额时应为 nil（无数据），不是 0")
    }

    @MainActor
    func testPoolTotalRemainingSumsAcrossAccounts() async {
        let prober = FakeQuotaProberStub(result: [
            QoderAccountQuota(userId: "user-1", planRemaining: 300, addOnRemaining: 100), // total 400
            QoderAccountQuota(userId: "user-2", planRemaining: 250.5, addOnRemaining: 0), // total 250.5
            QoderAccountQuota(userId: "user-3", planRemaining: 0, addOnRemaining: 50),    // total 50
        ])
        let store = QoderStore(port: 8096, transport: FakeTransport(), quotaProber: prober)
        await store.refreshPoolQuotas()
        XCTAssertEqual(store.poolQuotas.count, 3)
        XCTAssertEqual(store.poolTotalRemaining ?? 0, 700.5, accuracy: 0.001, "全池总额应为各号 plan+addOn 相加后再求和")
    }

    // MARK: - refreshPoolQuotas() 触发一次后写入 published 状态

    @MainActor
    func testRefreshPoolQuotasPopulatesPublishedState() async {
        let prober = FakeQuotaProberStub(result: [
            QoderAccountQuota(userId: "user-1", planRemaining: 100, addOnRemaining: 20),
        ])
        let store = QoderStore(port: 8096, transport: FakeTransport(), quotaProber: prober)
        XCTAssertTrue(store.poolQuotas.isEmpty, "初始应为空")
        await store.refreshPoolQuotas()
        XCTAssertEqual(prober.callCount, 1, "应恰好调用一次 probeAll")
        XCTAssertEqual(store.poolQuotas.count, 1)
        XCTAssertEqual(store.poolTotalRemaining ?? 0, 120, accuracy: 0.001)
    }

    @MainActor
    func testRefreshPoolQuotasEmptyResultKeepsTotalNil() async {
        let prober = FakeQuotaProberStub(result: [])
        let store = QoderStore(port: 8096, transport: FakeTransport(), quotaProber: prober)
        await store.refreshPoolQuotas()
        XCTAssertTrue(store.poolQuotas.isEmpty)
        XCTAssertNil(store.poolTotalRemaining, "probeAll 返回空数组时仍应视为无数据(nil)，不能误当成 0")
    }

    // MARK: - 守卫竞态回归锁（真机 bug：第三页 Orb 环下方余额全变 --）

    /// probeAll() 返回 nil 表示「本轮被 in-flight 守卫挡掉、压根没探」，此时**绝不能**动已有数据。
    /// 时序还原：App 启动探测 A 在跑 → 用户开面板触发 B → B 撞守卫返回 nil → 若 B 用空数组覆盖，
    /// 且 B 的覆盖晚于 A 回填真值，poolQuotas 就永久停在空态，UI 全显示 `--`。
    @MainActor
    func testRefreshPoolQuotasNilFromGuardDoesNotOverwriteExistingData() async {
        let good = QoderAccountQuota(userId: "user-1", planRemaining: 300, addOnRemaining: 100)
        let prober = FakeQuotaProberStub(result: [good])
        let store = QoderStore(port: 8096, transport: FakeTransport(), quotaProber: prober)
        await store.refreshPoolQuotas()
        XCTAssertEqual(store.poolQuotas, [good], "前置条件：先有一份好数据")

        // 换成"被守卫跳过"的语义：返回 nil
        prober.result = nil
        await store.refreshPoolQuotas()
        XCTAssertEqual(prober.callCount, 2, "两轮都应真的调用过 probeAll")
        XCTAssertEqual(store.poolQuotas, [good], "probeAll 返回 nil(被守卫跳过)时必须保留旧数据，不能被冲成空")
        XCTAssertEqual(store.poolTotalRemaining ?? 0, 400, accuracy: 0.001, "合计同样不得因被跳过的轮次而丢失")
    }

    /// 与上一条配对：[] 是「探测确实跑完了、一个号都没查到」（如 token 全失效），语义上**应该**清空。
    @MainActor
    func testRefreshPoolQuotasEmptyArrayFromCompletedProbeClearsStaleData() async {
        let good = QoderAccountQuota(userId: "user-1", planRemaining: 300, addOnRemaining: 100)
        let prober = FakeQuotaProberStub(result: [good])
        let store = QoderStore(port: 8096, transport: FakeTransport(), quotaProber: prober)
        await store.refreshPoolQuotas()
        XCTAssertEqual(store.poolQuotas.count, 1)

        prober.result = []
        await store.refreshPoolQuotas()
        XCTAssertTrue(store.poolQuotas.isEmpty, "探测完成但结果为空 → 应以本次结果为准清空旧数据")
        XCTAssertNil(store.poolTotalRemaining)
    }
}
