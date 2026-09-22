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

/// 门控假 prober：`probeAll()` 会一直挂起，直到测试手动 `resumeNext()`/`resumeAll()` 放行。
/// 用于确定性模拟「上一次探测还在飞行中」——不靠猜 sleep 时长，避免时序敏感导致的偶发失败。
private final class GatedFakeQuotaProber: QoderPoolQuotaProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    var result: [QoderAccountQuota]?

    var callCount: Int { lock.lock(); defer { lock.unlock() }; return _callCount }

    init(result: [QoderAccountQuota]?) { self.result = result }

    func probeAll() async -> [QoderAccountQuota]? {
        lock.lock(); _callCount += 1; lock.unlock()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock(); waiters.append(cont); lock.unlock()
        }
        return result
    }

    /// 放行最早的一个挂起中调用；当前没有挂起中的调用则什么都不做。
    func resumeNext() {
        lock.lock(); let cont = waiters.isEmpty ? nil : waiters.removeFirst(); lock.unlock()
        cont?.resume()
    }

    /// 放行所有当前挂起中的调用。
    func resumeAll() {
        lock.lock(); let pending = waiters; waiters = []; lock.unlock()
        pending.forEach { $0.resume() }
    }
}

/// 轮询等待条件成立，超时返回 false 交给调用方断言（避免测试依赖精确 sleep 时序）。
private func waitUntil(timeoutNanos: UInt64 = 2_000_000_000, pollNanos: UInt64 = 5_000_000, _ condition: @escaping @Sendable () -> Bool) async -> Bool {
    var elapsed: UInt64 = 0
    while elapsed < timeoutNanos {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: pollNanos)
        elapsed += pollNanos
    }
    return condition()
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
        // 前置断言：首轮刷新（quota + pool/status 三处 @Published 从 nil/空变为有值）必须真的发布过。
        // 不加这条的话，一旦订阅句柄没被持有（计数恒 0），下面的等值断言会退化成 0 == 0 永真、形同虚设。
        XCTAssertGreaterThan(first, 0, "首轮刷新应至少发布一次 objectWillChange，否则去重断言无意义")
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

    // MARK: - 手动刷新额度（第三页「刷新」按钮）：标志位 + 重入守卫

    @MainActor
    func testManualRefreshAndTimerControl() async {
        let prober = FakeQuotaProberStub(result: [
            QoderAccountQuota(userId: "user-1", planRemaining: 150, addOnRemaining: 50),
        ])
        let store = QoderStore(port: 8096, transport: FakeTransport(), quotaProber: prober)
        XCTAssertFalse(store.isProbingPoolQuotas, "初始未探测时，标志位应为 false")

        await store.triggerManualQuotaRefresh()

        XCTAssertEqual(prober.callCount, 1, "triggerManualQuotaRefresh 应恰好驱动一次探测")
        XCTAssertEqual(store.poolQuotas.count, 1, "探测回填后 poolQuotas 应更新")
        XCTAssertFalse(store.isProbingPoolQuotas, "探测结束后标志位必须复位，不能卡在 true")

        // 定时刷新与手动刷新共用同一套 refreshPoolQuotas()；此处只验证 stop() 不会崩溃、
        // 且未 start() 的独立实例上 stop() 也是安全的（quotaTimerTask 为 nil 时直接跳过）。
        store.stop()
    }

    @MainActor
    func testTriggerManualQuotaRefreshIgnoresReentrantCallWhileInFlight() async {
        let prober = GatedFakeQuotaProber(result: [
            QoderAccountQuota(userId: "user-1", planRemaining: 100, addOnRemaining: 0),
        ])
        let store = QoderStore(port: 8096, transport: FakeTransport(), quotaProber: prober)

        let firstTask = Task { await store.triggerManualQuotaRefresh() }
        let started = await waitUntil { prober.callCount == 1 }
        XCTAssertTrue(started, "第一次触发应已驱动 probeAll 并挂起等待放行")
        XCTAssertTrue(store.isProbingPoolQuotas, "飞行中标志位应为 true")

        // 飞行中重复触发：应被重入守卫直接忽略，不再驱动第二次 probeAll。
        await store.triggerManualQuotaRefresh()
        XCTAssertEqual(prober.callCount, 1, "飞行中的二次触发不得驱动第二次 probeAll")

        prober.resumeNext()
        await firstTask.value

        XCTAssertFalse(store.isProbingPoolQuotas, "全部触发结束后标志位应复位")
    }

    // MARK: - 今日真实消耗（余额基准线，替代日志名义 credits 累加）

    private func uniqueDefaults() -> UserDefaults {
        let suite = "QoderStoreTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @MainActor
    func testDailyBaselineCapturedOnFirstProbeAndConsumptionComputed() async {
        let prober = FakeQuotaProberStub(result: [
            QoderAccountQuota(userId: "user-1", planRemaining: 300, addOnRemaining: 400),
        ])
        let store = QoderStore(port: 8096, transport: FakeTransport(), quotaProber: prober, defaults: uniqueDefaults())
        XCTAssertNil(store.todayRealConsumption, "还没探测过，基准线未建立，不能凭空显示 0 或任何数字")

        await store.refreshPoolQuotas()
        XCTAssertEqual(store.dailyBaselineRemaining ?? 0, 700, accuracy: 0.001, "当天第一次探测必须把当前余额记为基准线")
        XCTAssertEqual(store.todayRealConsumption ?? -1, 0, accuracy: 0.001, "刚建立基准线、还没消耗，应为 0")

        prober.result = [QoderAccountQuota(userId: "user-1", planRemaining: 250, addOnRemaining: 400)]
        await store.refreshPoolQuotas()
        XCTAssertEqual(store.dailyBaselineRemaining ?? 0, 700, accuracy: 0.001, "基准线一旦建立，后续探测不得改动它")
        XCTAssertEqual(store.todayRealConsumption ?? -1, 50, accuracy: 0.001, "真实消耗 = 基准线 700 - 当前 650")
    }

    /// 充值 / 每日重置到账：余额不降反升时，基准线要跟着抬到新高点，否则「消耗」会被 max(0,...)
    /// 钳成 0 并长期卡住，之后真实下降反而看不出来。
    @MainActor
    func testDailyBaselineRaisesWhenBalanceGoesUp() async {
        let prober = FakeQuotaProberStub(result: [
            QoderAccountQuota(userId: "user-1", planRemaining: 100, addOnRemaining: 0),
        ])
        let store = QoderStore(port: 8096, transport: FakeTransport(), quotaProber: prober, defaults: uniqueDefaults())
        await store.refreshPoolQuotas()
        XCTAssertEqual(store.dailyBaselineRemaining ?? 0, 100, accuracy: 0.001)

        prober.result = [QoderAccountQuota(userId: "user-1", planRemaining: 180, addOnRemaining: 0)]
        await store.refreshPoolQuotas()
        XCTAssertEqual(store.dailyBaselineRemaining ?? 0, 180, accuracy: 0.001, "余额上涨（充值/重置）时基准线要抬到新高点")
        XCTAssertEqual(store.todayRealConsumption ?? -1, 0, accuracy: 0.001, "刚抬到新高点、还没消耗，应为 0")

        prober.result = [QoderAccountQuota(userId: "user-1", planRemaining: 160, addOnRemaining: 0)]
        await store.refreshPoolQuotas()
        XCTAssertEqual(store.todayRealConsumption ?? -1, 20, accuracy: 0.001, "之后真实下降要相对新基准线算，不能被旧基准线卡住")
    }

    /// 隔天自然换新基准线：跟 `QoderCampaignClaimer` 的按天隔离同一套路，不写清理逻辑，靠 Key 带日期天然重置。
    @MainActor
    func testDailyBaselineResetsOnNewDay() async {
        var day = Date(timeIntervalSince1970: 1_700_000_000)
        let prober = FakeQuotaProberStub(result: [
            QoderAccountQuota(userId: "user-1", planRemaining: 300, addOnRemaining: 0),
        ])
        let store = QoderStore(port: 8096, transport: FakeTransport(), quotaProber: prober,
                               defaults: uniqueDefaults(), now: { day })
        await store.refreshPoolQuotas()
        XCTAssertEqual(store.dailyBaselineRemaining ?? 0, 300, accuracy: 0.001)

        prober.result = [QoderAccountQuota(userId: "user-1", planRemaining: 250, addOnRemaining: 0)]
        await store.refreshPoolQuotas()
        XCTAssertEqual(store.todayRealConsumption ?? -1, 50, accuracy: 0.001, "前置条件：当天已产生 50 消耗")

        day = day.addingTimeInterval(86_400)   // 恰好 24 小时后必然跨到下一个日历日
        prober.result = [QoderAccountQuota(userId: "user-1", planRemaining: 250, addOnRemaining: 0)]
        await store.refreshPoolQuotas()
        XCTAssertEqual(store.dailyBaselineRemaining ?? 0, 250, accuracy: 0.001, "隔天第一次探测应把当时余额当作新基准线，不带昨天的账")
        XCTAssertEqual(store.todayRealConsumption ?? -1, 0, accuracy: 0.001, "新的一天刚开始，消耗应归零重算")
    }

    /// App 重启（新实例、同一份 UserDefaults）不能把当天已建立的基准线弄丢，否则「今日真实消耗」
    /// 每次重启都会清零重来，跟用户预期的"今天一共花了多少"不符。
    @MainActor
    func testDailyBaselinePersistsAcrossStoreInstances() async {
        let defaults = uniqueDefaults()
        let prober = FakeQuotaProberStub(result: [
            QoderAccountQuota(userId: "user-1", planRemaining: 300, addOnRemaining: 0),
        ])
        let first = QoderStore(port: 8096, transport: FakeTransport(), quotaProber: prober, defaults: defaults)
        await first.refreshPoolQuotas()
        XCTAssertEqual(first.dailyBaselineRemaining ?? 0, 300, accuracy: 0.001)

        prober.result = [QoderAccountQuota(userId: "user-1", planRemaining: 270, addOnRemaining: 0)]
        let revived = QoderStore(port: 8096, transport: FakeTransport(), quotaProber: prober, defaults: defaults)
        XCTAssertEqual(revived.dailyBaselineRemaining ?? 0, 300, accuracy: 0.001, "新实例初始化时应从 UserDefaults 读回当天已建立的基准线")
        await revived.refreshPoolQuotas()
        XCTAssertEqual(revived.todayRealConsumption ?? -1, 30, accuracy: 0.001, "重启后消耗继续按同一基准线算，不能清零重来")
    }
}
