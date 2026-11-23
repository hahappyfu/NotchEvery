import AppKit
import XCTest
@testable import NotchEvery

final class ProviderIconGateTests: XCTestCase {
    private func key(icon: String? = "icon.png", providerID: String = "p1") -> ProviderIconKey {
        ProviderIconKey(icon: icon, providerID: providerID)
    }

    func testBeginNewKeyReturnsTrue() {
        var gate = IconRequestGate()
        XCTAssertTrue(gate.begin(key()))
        XCTAssertEqual(gate.requested, [key()])
    }

    func testBeginSameKeyTwiceReturnsFalse() {
        var gate = IconRequestGate()
        XCTAssertTrue(gate.begin(key()))
        XCTAssertFalse(gate.begin(key()))
    }

    func testBeginDifferentProviderIDClearsAndReturnsTrue() {
        var gate = IconRequestGate()
        XCTAssertTrue(gate.begin(key(providerID: "p1")))
        XCTAssertTrue(gate.begin(key(providerID: "p2")))
        XCTAssertEqual(gate.requested, [key(providerID: "p2")])
    }

    func testBeginDifferentIconClearsAndReturnsTrue() {
        var gate = IconRequestGate()
        XCTAssertTrue(gate.begin(key(icon: "a.png")))
        XCTAssertTrue(gate.begin(key(icon: "b.png")))
        XCTAssertEqual(gate.requested, [key(icon: "b.png")])
    }

    func testIsCurrentForActiveKey() {
        var gate = IconRequestGate()
        let k = key()
        _ = gate.begin(k)
        XCTAssertTrue(gate.isCurrent(k))
    }

    func testIsCurrentFalseAfterSwitch() {
        var gate = IconRequestGate()
        let old = key(providerID: "p1")
        let new = key(providerID: "p2")
        _ = gate.begin(old)
        _ = gate.begin(new)
        XCTAssertFalse(gate.isCurrent(old))
        XCTAssertTrue(gate.isCurrent(new))
    }

    func testNilIconAndEmptyProviderIDIsValidKey() {
        var gate = IconRequestGate()
        let k = ProviderIconKey(icon: nil, providerID: "")
        XCTAssertTrue(gate.begin(k))
        XCTAssertTrue(gate.isCurrent(k))
    }

    /// 顺序契约：begin 必须发生在查同步图之前——闭包在查图时刻观察 gate，能抓住「先查图、后 begin」的回归。
    func testPlanInvalidatesOldKeyBeforeSyncLookup() {
        var gate = IconRequestGate()
        let old = key(icon: "old.png", providerID: "p1")
        let new = key(icon: "new.png", providerID: "p2")
        _ = gate.begin(old)

        let image = NSImage()
        let plan = planResolution(key: new, syncImage: { g in
            // 查图这一时刻旧 key 必须已失效，否则旧异步回调会覆盖新图
            XCTAssertFalse(g.isCurrent(old))
            return image
        }, gate: &gate)
        XCTAssertNotNil(plan.synced)
        XCTAssertEqual(plan.synced, image)
        XCTAssertFalse(plan.shouldRequestAsync)
        XCTAssertTrue(gate.isCurrent(new))
    }

    /// 同 key 重入（begin 返回 false）仍要出同步图，不能误判成「需要异步」。
    func testSameKeyReentryStillShowsSyncImage() {
        var gate = IconRequestGate()
        let k = key()
        let image = NSImage()
        let lookup = { (_ g: IconRequestGate) -> NSImage in image }

        let first = planResolution(key: k, syncImage: lookup, gate: &gate)
        let second = planResolution(key: k, syncImage: lookup, gate: &gate)

        XCTAssertEqual(first.synced, image)
        XCTAssertFalse(first.shouldRequestAsync)
        XCTAssertEqual(second.synced, image)
        XCTAssertFalse(second.shouldRequestAsync)
        XCTAssertTrue(gate.isCurrent(k))
    }

    /// 异步路径：新 key 且无同步图 → 需要补异步请求。
    func testPlanRequestsAsyncWhenNoSyncImage() {
        var gate = IconRequestGate()
        let plan = planResolution(key: key(icon: "a.svg"), syncImage: { _ in nil }, gate: &gate)
        XCTAssertNil(plan.synced)
        XCTAssertTrue(plan.shouldRequestAsync)
    }
}
