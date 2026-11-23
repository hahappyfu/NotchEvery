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
            providerID: "p",
            providerName: "P",
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

    // A1: 复制摘要打印稳定 providerID，而不是仅用于展示的 providerName。
    func testCopySummaryUsesProviderIDNotDisplayName() {
        let flow = MagpieFlowRow(
            id: "r-1", agent: "claude", providerID: "stable-id", providerName: "展示名",
            account: "a", model: "m", requestedModel: "m", groupName: nil,
            inputTokens: 10, outputTokens: 20, cacheRead: 0, durationMs: 1234,
            ttftMs: 56, maskingMs: nil, status: 499, handedOn: false,
            maskedCount: 0, time: Date(timeIntervalSince1970: 1000)
        )
        XCTAssertEqual(TokenZoneView.copySummary(for: flow, time: "12:34:56"),
                       "12:34:56 stable-id@a m status=499 1234ms ttft=56ms rid=r-1")
    }
}
