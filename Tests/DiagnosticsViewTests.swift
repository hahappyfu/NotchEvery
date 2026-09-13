// FUnlockTests/DiagnosticsViewTests.swift（移植自 FUnlock，工单 01）
// 只随行与 DecisionLogger 相关的断言；testTimeStringContainsOnlyTime 测的是
// DiagnosticsView 上的静态方法，而该视图在工单 06 才按刘海形态重写 —— 该用例届时随视图一起回来。

import XCTest
@testable import NotchEvery

final class DiagnosticsViewTests: XCTestCase {
    func testScreenLabelMapsKnownStates() {
        XCTAssertEqual(DecisionEvent.screenLabel("locked(away)"), "screen_locked_away")
        XCTAssertEqual(DecisionEvent.screenLabel("locked(manual)"), "screen_locked_manual")
        XCTAssertEqual(DecisionEvent.screenLabel("unlocked"), "screen_unlocked")
        XCTAssertEqual(DecisionEvent.screenLabel("displaySleeping"), "screen_display_sleeping")
    }

    func testScreenLabelFallsBackToRaw() {
        XCTAssertEqual(DecisionEvent.screenLabel("unknown"), "unknown")
        XCTAssertNil(DecisionEvent.screenLabel(nil))
    }
}
