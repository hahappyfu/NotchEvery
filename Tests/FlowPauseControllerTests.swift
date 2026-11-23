import XCTest
@testable import NotchEvery

@MainActor
final class FlowPauseControllerTests: XCTestCase {
    private func row(_ id: String) -> MagpieFlowRow {
        MagpieFlowRow(
            id: id,
            agent: "claude",
            providerID: "p",
            providerName: "P",
            account: "a",
            model: "m",
            requestedModel: "m",
            groupName: nil,
            inputTokens: 10,
            outputTokens: 20,
            cacheRead: 0,
            durationMs: 100,
            ttftMs: nil,
            maskingMs: nil,
            status: 200,
            handedOn: false,
            maskedCount: 0,
            time: Date(timeIntervalSince1970: 1000)
        )
    }

    func testPauseFreezesRows() {
        let rows = [row("a"), row("b")]
        var controller = FlowPauseController()
        controller.pause(liveRows: rows)
        XCTAssertTrue(controller.isPaused)
        XCTAssertEqual(controller.frozenRows, rows)
        XCTAssertEqual(controller.missedCount, 0)
    }

    func testReceiveAccumulatesMissedAndDedupes() {
        var controller = FlowPauseController()
        controller.pause(liveRows: [row("frozen")])
        controller.receive(liveRows: [row("new"), row("new"), row("frozen"), row("later")])
        XCTAssertEqual(controller.missedCount, 2)
    }

    func testQueueOverflowIncrementsGap() {
        var controller = FlowPauseController()
        controller.pause(liveRows: [])
        let rows = (0..<250).map { row("new-\($0)") }
        controller.receive(liveRows: rows)
        XCTAssertEqual(controller.missedCount, 250)
        XCTAssertEqual(controller.gapCount, 50)
        XCTAssertLessThanOrEqual(controller.pendingRowCount, FlowPauseController.pendingCapacity)
    }

    func testResumeReturnsGapAndUnfreezes() {
        var controller = FlowPauseController()
        controller.pause(liveRows: [row("frozen")])
        controller.receive(liveRows: (0..<250).map { row("new-\($0)") })
        let gap = controller.resume(liveRows: [])
        XCTAssertEqual(gap, 50)
        XCTAssertFalse(controller.isPaused)
        XCTAssertEqual(controller.gapCount, 50)
        XCTAssertEqual(controller.missedCount, 0)
    }

    func testReceiveWhileNotPausedIsNoop() {
        var controller = FlowPauseController()
        controller.receive(liveRows: [row("new")])
        XCTAssertEqual(controller.missedCount, 0)
        XCTAssertFalse(controller.isPaused)
    }

    // A6: 两次刷新间 >5 条新行（50 条）全数计入未读，不受旧 5 条展示窗口限制。
    func testReceiveFiftyNewRowsCountsAllMissed() {
        var controller = FlowPauseController()
        controller.pause(liveRows: [])
        controller.receive(liveRows: (0..<50).map { row("burst-\($0)") })
        XCTAssertEqual(controller.missedCount, 50)
        XCTAssertEqual(controller.gapCount, 0)
    }

    // A6: 再次 pause 清空缺口与待读，resume 仍返回上次 pause 周期的旧缺口。
    func testRepauseResetsGapButResumeReturnsOldValue() {
        var controller = FlowPauseController()
        controller.pause(liveRows: [])
        controller.receive(liveRows: (0..<250).map { row("old-\($0)") })
        XCTAssertEqual(controller.gapCount, 50)
        controller.pause(liveRows: [row("fresh")])
        XCTAssertEqual(controller.gapCount, 0)
        XCTAssertEqual(controller.missedCount, 0)
        XCTAssertEqual(controller.pendingRowCount, 0)
        XCTAssertEqual(controller.resume(liveRows: []), 0)
    }
}
