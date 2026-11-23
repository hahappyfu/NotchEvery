import XCTest
@testable import NotchEvery

@MainActor
final class TokenZoneViewFormatTests: XCTestCase {
    private func row(
        id: String = "r-1",
        cacheRead: Int = 0,
        inputTokens: Int = 10,
        status: Int? = 499,
        durationMs: Int? = 1234,
        ttftMs: Int? = 56
    ) -> MagpieFlowRow {
        MagpieFlowRow(
            id: id,
            agent: "claude",
            provider: "p",
            account: "a",
            model: "m",
            requestedModel: "m",
            groupName: nil,
            inputTokens: inputTokens,
            outputTokens: 20,
            cacheRead: cacheRead,
            durationMs: durationMs,
            ttftMs: ttftMs,
            maskingMs: nil,
            status: status,
            handedOn: false,
            maskedCount: 0,
            time: Date(timeIntervalSince1970: 1000)
        )
    }

    func testCacheTextWithoutHits() {
        XCTAssertEqual(TokenZoneView.cacheText(for: row(cacheRead: 0)), "无缓存")
    }

    func testCacheTextWithHits() {
        XCTAssertEqual(TokenZoneView.cacheText(for: row(cacheRead: 100, inputTokens: 100)), "缓存 50%")
    }

    func testCopySummaryIncludesStatusPrefix() {
        let summary = TokenZoneView.copySummary(for: row(), time: "12:34:56")
        XCTAssertEqual(summary, "12:34:56 p@a m status=499 1234ms ttft=56ms rid=r-1")
    }

    func testCopySummaryUsesSentinelsForMissingNumbers() {
        let summary = TokenZoneView.copySummary(
            for: row(status: nil, durationMs: nil, ttftMs: nil),
            time: "00:00:00"
        )
        XCTAssertEqual(summary, "00:00:00 p@a m status=-1 -1ms ttft=-1ms rid=r-1")
    }
}
