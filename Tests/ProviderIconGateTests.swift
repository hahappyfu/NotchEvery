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

    /// 顺序契约：任何新请求（含同步命中路径）都必须先 begin，让旧厂商的异步回调失效。
    func testSyncHitPathInvalidatesPreviousAsyncRequest() {
        var gate = IconRequestGate()
        let old = key(icon: "old.png", providerID: "p1")
        let new = key(icon: "new.png", providerID: "p2")

        XCTAssertTrue(gate.begin(old))       // 旧厂商发出异步 SVG 请求
        _ = gate.begin(new)                  // 新厂商同步命中：resolve() 仍先 begin
        XCTAssertFalse(gate.isCurrent(old))  // 旧回调回来必须被丢弃
        XCTAssertTrue(gate.isCurrent(new))
    }
}
