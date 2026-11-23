import Combine
import XCTest
@testable import NotchEvery

final class MagpieStoreTests: XCTestCase {
    private final class Clock {
        var date: Date
        init(_ date: Date) { self.date = date }
        func now() -> Date {
            let value = date
            date = date.addingTimeInterval(1)
            return value
        }
    }

    private var root: URL!
    private var calendar: Calendar!
    private var clock: Clock!
    private var store: MagpieStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MagpieStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        self.calendar = calendar
        clock = Clock(calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 12))!)
    }

    override func tearDown() {
        store?.stop()
        store = nil
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    private func makeStore() -> MagpieStore {
        let store = MagpieStore(paths: MagpiePaths(root: root), calendar: calendar, now: clock.now)
        self.store = store
        return store
    }

    private func write(_ text: String, to name: String) throws {
        try Data(text.utf8).write(to: root.appendingPathComponent(name))
    }

    private func usageLine(time: String) -> String {
        #"{"route_id":1,"t":"\#(time)","agent":"claude","provider":"p","providerAccount":"a","model":"m","req":"claude-sonnet","in":10,"out":5,"cache_read":2,"status":200,"rid":"rid-1"}"# + "\n"
    }

    private func waitFor(_ store: MagpieStore, timeout: TimeInterval = 3,
                         trigger: (() -> Void)? = nil, _ predicate: @escaping (MagpieSnapshot) -> Bool) {
        let snapshotExpectation = expectation(description: "snapshot")
        snapshotExpectation.assertForOverFulfill = false
        let cancellable = store.$snapshot.sink { snapshot in
            if predicate(snapshot) { snapshotExpectation.fulfill() }
        }
        if predicate(store.snapshot) { snapshotExpectation.fulfill() }
        trigger?()
        wait(for: [snapshotExpectation], timeout: timeout)
        cancellable.cancel()
    }

    // 1. start 后发布 fixture 快照
    func testStartPublishesFixtureSnapshot() throws {
        try write(usageLine(time: "2026-11-23T10:00:00+08:00"), to: "usage.jsonl")
        let store = makeStore()
        waitFor(store, trigger: { store.start() }) { $0.todayRequestCount == 1 }
        XCTAssertTrue(store.isRunning)
        XCTAssertEqual(store.snapshot.todayNetTokens, 15)
        XCTAssertEqual(store.snapshot.todayCacheRead, 2)
    }

    // 2. stop 停表且幂等；start 幂等
    func testStopHaltsTimersAndIsIdempotent() {
        let store = makeStore()
        store.start()
        XCTAssertTrue(store.isRunning)
        store.start()
        XCTAssertTrue(store.isRunning)
        store.stop()
        XCTAssertFalse(store.isRunning)
        store.stop()
        XCTAssertFalse(store.isRunning)
    }

    // 3. 小 JSON 损坏时保留上次解析值，不闪零/清空
    func testCorruptSmallJSONKeepsPreviousSnapshot() throws {
        try write(#"{"providers":[{"id":"p1","name":"Provider One"}]}"#, to: "providers.json")
        try write(#"{"q1/a":{"quota":{"provider":"q1","name":"Quota One","windows":[{"name":"总积分","used":5,"amount":5,"limit":100}]}}}"#, to: "quotas.json")
        let store = makeStore()
        waitFor(store, trigger: { store.catchUp() }) { $0.providerGroups.contains(where: { $0.id == "q1" }) }
        try write("not json", to: "quotas.json")
        let refreshed = expectation(description: "refresh completed")
        store.catchUp()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { refreshed.fulfill() }
        wait(for: [refreshed], timeout: 3)
        XCTAssertTrue(store.snapshot.providerGroups.contains(where: { $0.id == "q1" }))
        XCTAssertTrue(store.snapshot.providerGroups.contains(where: { $0.id == "p1" }))
    }

    // 4. routing/masking 文件缺失不崩
    func testMissingRoutingAndMaskingFilesDoNotCrash() throws {
        try write(usageLine(time: "2026-11-23T10:00:00+08:00"), to: "usage.jsonl")
        let store = makeStore()
        waitFor(store, trigger: { store.catchUp() }) { $0.todayRequestCount == 1 }
        XCTAssertEqual(store.snapshot.todayMaskedValues, 0)
        XCTAssertEqual(store.snapshot.recentFlows.count, 1)
        XCTAssertEqual(store.snapshot.recentFlows.first?.groupName, nil)
    }

    // 5. 跨午夜后今日计数归零
    func testMidnightRolloverPrunesYesterday() throws {
        clock.date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 23, minute: 59))!
        try write(usageLine(time: "2026-11-22T23:50:00+08:00"), to: "usage.jsonl")
        let store = makeStore()
        waitFor(store, trigger: { store.catchUp() }) { $0.todayRequestCount == 1 }

        clock.date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 0, minute: 1))!
        waitFor(store, trigger: { store.catchUp() }) { $0.todayRequestCount == 0 }
        XCTAssertEqual(store.snapshot.todayNetTokens, 0)
        XCTAssertNil(store.snapshot.lastRequestAt)
    }

    // 6. 无 Magpie 目录 → hasMagpieDirectory false，其余为空值
    func testNoMagpieDirectory() throws {
        try FileManager.default.removeItem(at: root)
        let store = makeStore()
        let refreshed = expectation(description: "refresh completed")
        store.catchUp()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { refreshed.fulfill() }
        wait(for: [refreshed], timeout: 3)
        XCTAssertFalse(store.snapshot.hasMagpieDirectory)
        XCTAssertEqual(store.snapshot.todayNetTokens, 0)
        XCTAssertEqual(store.snapshot.todayRequestCount, 0)
        XCTAssertEqual(store.snapshot.distributions[.combo] ?? [], [])
        XCTAssertEqual(store.snapshot.providerGroups, [])
        XCTAssertEqual(store.snapshot.gateway, .offline)
    }

    // 7. 文件被合法清空时快照应及时清空，而不是保留陈旧值
    func testEmptyQuotasFileClearsProviderGroups() throws {
        try write(#"{"q1/a":{"quota":{"provider":"q1","name":"Quota One","windows":[{"name":"总积分","used":5,"amount":5,"limit":100}]}}}"#, to: "quotas.json")
        let store = makeStore()
        waitFor(store, trigger: { store.catchUp() }) { $0.providerGroups.contains(where: { $0.id == "q1" }) }

        try write("", to: "quotas.json")
        waitFor(store, trigger: { store.catchUp() }) { $0.providerGroups.isEmpty }
        XCTAssertTrue(store.snapshot.providerGroups.isEmpty)
    }

    // 8. 相同数据连续刷新不重复发布（忽略 refreshedAt）
    func testIdenticalRefreshDoesNotRepublish() throws {
        try write(usageLine(time: "2026-11-23T10:00:00+08:00"), to: "usage.jsonl")
        let store = makeStore()
        let published = expectation(description: "first publish")
        let cancellable = store.objectWillChange.sink { _ in published.fulfill() }
        defer { cancellable.cancel() }

        store.catchUp()
        wait(for: [published], timeout: 3)
        let baseline = store.snapshot
        XCTAssertEqual(baseline.todayRequestCount, 1)

        let noExtra = expectation(description: "no extra publish")
        noExtra.isInverted = true
        let observer = store.objectWillChange.sink { _ in noExtra.fulfill() }
        defer { observer.cancel() }
        store.catchUp()
        // 等 ioQueue + 主线程派发完成后再判定 inverted expectation。
        let drained = expectation(description: "drained")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { drained.fulfill() }
        wait(for: [noExtra, drained], timeout: 3)
    }
}
