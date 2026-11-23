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
}
