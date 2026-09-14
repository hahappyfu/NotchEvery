// DiagTimelineTests.swift（工单 06 新建）
// 行模型纯逻辑测试：分组/排序/文案规则，不碰视图与本地化 bundle
//（断言 detail 优先与结构，本地化解析只要求非空）。

import XCTest
@testable import NotchEvery

final class DiagTimelineTests: XCTestCase {
    private var base: Date!

    override func setUp() {
        super.setUp()
        // 取当天 00:00 作基址：timeText 断言与机器时区无关
        base = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
    }

    private func event(at offset: TimeInterval, reason: DecisionReason? = nil,
                       rssi: Int? = nil, detail: String = "") -> DecisionEvent {
        DecisionEvent(timestamp: base.addingTimeInterval(offset), category: .unlock,
                      outcome: .skipped, reason: reason, rssi: rssi,
                      device: nil, screen: nil, detail: detail)
    }

    func testEmptyGivesNoDays() {
        XCTAssertTrue(DiagTimeline.build(from: []).isEmpty)
    }

    /// 乱序输入 → 组内倒序；同天并入一组
    func testSortsDescendingAndGroupsSameDay() {
        let days = DiagTimeline.build(from: [
            event(at: 10, reason: .noPresence),
            event(at: 30, reason: .signalBelowThreshold, rssi: -58),
            event(at: 20, detail: "空跑：本应解锁"),
        ])

        XCTAssertEqual(days.count, 1, "同天应并入一组")
        XCTAssertEqual(days[0].entries.map { $0.timeText },
                       ["00:00:30", "00:00:20", "00:00:10"], "组内倒序")
    }

    /// 跨天 → 按天分组且天倒序
    func testGroupsByDayDescending() {
        let days = DiagTimeline.build(from: [
            event(at: 10),
            event(at: 90_000), // 次日
        ])

        XCTAssertEqual(days.count, 2)
        XCTAssertGreaterThan(days[0].day, days[1].day)
        XCTAssertEqual(days[0].entries.count, 1)
    }

    /// detail 非空优先于 reason 文案
    func testDetailPreferredOverReason() {
        let days = DiagTimeline.build(from: [event(at: 0, reason: .noPresence, detail: "空跑：本应解锁")])
        XCTAssertEqual(days[0].entries[0].reasonText, "空跑：本应解锁")
    }

    /// 无 detail 时 reason 文案非空（本地化缺键则回退 key 本身，不断言具体文案）
    func testReasonTextFallsBackToTitleKey() {
        let days = DiagTimeline.build(from: [event(at: 0, reason: .noPresence)])
        XCTAssertFalse(days[0].entries[0].reasonText.isEmpty)
    }

    func testSignalTextFormatsNil() {
        let days = DiagTimeline.build(from: [
            event(at: 0, rssi: -58),
            event(at: 1),
        ])
        XCTAssertNil(days[0].entries[0].signalText, "倒序首条为 offset 1（无信号）")
        XCTAssertEqual(days[0].entries[1].signalText, "-58 dBm")
    }

    /// 无 action 的原因不给建议；axRevoked 与 reEnterPassword 给建议且可执行
    func testHintsOnlyWhenActionExists() {
        let days = DiagTimeline.build(from: [
            event(at: 0, reason: .noPresence),
            event(at: 1, reason: .axRevoked),
            event(at: 2, reason: .unlockFailed),
        ])
        let plain = days[0].entries[2]
        XCTAssertNil(plain.hintText)
        XCTAssertFalse(plain.hasExecutableAction)
        let ax = days[0].entries[1]
        XCTAssertNotNil(ax.hintText)
        XCTAssertTrue(ax.hasExecutableAction, "可执行：辅助功能设置")
        let pw = days[0].entries[0]
        XCTAssertNotNil(pw.hintText)
        XCTAssertTrue(pw.hasExecutableAction, "09 可执行：重录密码")
    }
}
