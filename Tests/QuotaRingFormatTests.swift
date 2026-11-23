import SwiftUI
import XCTest
@testable import NotchEvery

final class QuotaRingFormatTests: XCTestCase {
    func testRemainingFraction() {
        XCTAssertEqual(QuotaRingFormat.remainingFraction(usedPercent: 0), 1.0)
        XCTAssertEqual(QuotaRingFormat.remainingFraction(usedPercent: 30), 0.7)
        XCTAssertEqual(QuotaRingFormat.remainingFraction(usedPercent: 100), 0.0)
        XCTAssertEqual(QuotaRingFormat.remainingFraction(usedPercent: 120), 0.0)
        XCTAssertNil(QuotaRingFormat.remainingFraction(usedPercent: nil))
    }

    func testRingColor() {
        XCTAssertEqual(QuotaRingFormat.ringColor(fraction: 0.5), StudioColor.emerald)
        XCTAssertEqual(QuotaRingFormat.ringColor(fraction: 0.3), StudioColor.emerald)
        XCTAssertEqual(QuotaRingFormat.ringColor(fraction: 0.2), StudioColor.amber)
        XCTAssertEqual(QuotaRingFormat.ringColor(fraction: 0.1), StudioColor.amber)
        XCTAssertEqual(QuotaRingFormat.ringColor(fraction: 0.05), StudioColor.rose)
        XCTAssertEqual(QuotaRingFormat.ringColor(fraction: 0.0), StudioColor.rose)
        XCTAssertEqual(QuotaRingFormat.ringColor(fraction: nil), Color.white.opacity(0.35))
    }

    func testShortWindowName() {
        XCTAssertEqual(QuotaRingFormat.shortWindowName("ab"), "ab")
        XCTAssertEqual(QuotaRingFormat.shortWindowName("abcd"), "abcd")
        XCTAssertEqual(QuotaRingFormat.shortWindowName("abcde"), "abcd")
        XCTAssertEqual(QuotaRingFormat.shortWindowName("5-hour"), "5-ho")
    }

    func testResetText() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 UTC
        let text = QuotaRingFormat.resetText(date, calendar: cal)
        XCTAssertTrue(text.hasPrefix("重置 "))
        XCTAssertEqual(text.count, "重置 MM/dd".count)

        XCTAssertEqual(QuotaRingFormat.resetText(nil, calendar: cal), "")
    }

    func testExhaustionText() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(QuotaRingFormat.exhaustionText(now.addingTimeInterval(3600 * 5), now: now), "预计 5h 耗尽")
        XCTAssertEqual(QuotaRingFormat.exhaustionText(now.addingTimeInterval(1800), now: now), "预计 1h 耗尽")
        XCTAssertEqual(QuotaRingFormat.exhaustionText(now, now: now), "已耗尽")
        XCTAssertEqual(QuotaRingFormat.exhaustionText(now.addingTimeInterval(-100), now: now), "已耗尽")
        XCTAssertEqual(QuotaRingFormat.exhaustionText(nil, now: now), "")
    }
}
