import XCTest
@testable import NotchEvery

// normalize 单测（待 Xcode Test Target 后启用；用例抄 EveryPlus QuotaColdTests）
final class QuotaSnapshotTests: XCTestCase {
    func testEmptyInputReturnsEmpty() {
        XCTAssertEqual(QuotaSnapshot.normalize(nil), .empty)
        XCTAssertEqual(QuotaSnapshot.normalize(Data()), .empty)
    }

    func testIgnoresCachedPercentBug() throws {
        // 缓存 percent 恒 0，used=62 limit=100 → 自算 62
        let json = #"{"at": 1788423000000, "quota": {"5h": {"used": 62, "limit": 100, "percent": 0}}}"#
        let snap = QuotaSnapshot.normalize(json.data(using: .utf8)!, now: Date(timeIntervalSince1970: 1788423000))
        let percent = try XCTUnwrap(snap.window("5h")?.percent)
        XCTAssertEqual(percent, 62, accuracy: 0.01)
    }

    func testDropsInvalidWindows() {
        let json = #"{"quota": {"5h": {"used": 1}, "weekly": {"used": 30, "limit": 100}}}"#
        let snap = QuotaSnapshot.normalize(json.data(using: .utf8)!)
        XCTAssertNil(snap.window("5h"))
        XCTAssertNotNil(snap.window("weekly"))
    }

    func testExpiredWhenStale() {
        let json = #"{"at": 1000000000000, "quota": {"5h": {"used": 1, "limit": 2}}}"#
        let snap = QuotaSnapshot.normalize(json.data(using: .utf8)!)
        XCTAssertTrue(snap.expired)
        XCTAssertTrue(snap.available)
    }
}
