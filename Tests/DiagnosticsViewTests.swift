// FUnlockTests/DiagnosticsViewTests.swift（移植自 FUnlock，工单 01）
// 随行与 DecisionLogger 相关的断言，以及第三页守护控制台（GuardControlZoneView）的
// 尺寸提案、组件布局健壮性与状态文本映射测试。

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

    // MARK: - GuardControlZoneView 布局与尺寸健壮性测试

    func testGuardControlLayoutMetrics() {
        // 宽度放宽至 390pt
        XCTAssertEqual(GuardControlLayout.preferredWidth, 390, "控制台定宽应为 390pt 以彻底杜绝截断")
        XCTAssertEqual(GuardControlLayout.horizontalPadding, 18)
        XCTAssertEqual(GuardControlLayout.verticalPadding, 12)
        XCTAssertEqual(GuardControlLayout.toggleCardFontSize, 11.5)
        XCTAssertEqual(GuardControlLayout.judgementDetailLineLimit, 2, "判定详情卡片应支持双行展示")

        // 验证 2x2 每列卡片可用宽度大于 170pt
        XCTAssertGreaterThan(GuardControlLayout.toggleColumnWidth, 170, "每列卡片宽度应充足（>170pt）以舒适显示6字中文")
    }

    func testGuardControlTimeStringFormat() {
        let now = Date()
        let formatted = GuardControlZoneView.timeString(now)
        let regex = try? NSRegularExpression(pattern: #"^\d{2}:\d{2}:\d{2}$"#)
        let range = NSRange(location: 0, length: formatted.utf16.count)
        XCTAssertNotNil(regex?.firstMatch(in: formatted, options: [], range: range), "时间格式应为 HH:mm:ss")
    }

    func testGuardControlStateText() {
        XCTAssertEqual(GuardControlZoneView.stateText(for: .disabled), "停用")
        XCTAssertEqual(GuardControlZoneView.stateText(for: .observing), "空跑")
        XCTAssertEqual(GuardControlZoneView.stateText(for: .guarding), "生效中")
    }

    func testGuardControlOutcomeText() {
        XCTAssertEqual(GuardControlZoneView.outcomeText(.success), "成功")
        XCTAssertEqual(GuardControlZoneView.outcomeText(.skipped), "跳过")
        XCTAssertEqual(GuardControlZoneView.outcomeText(.failed), "失败")
        XCTAssertEqual(GuardControlZoneView.outcomeText(.blocked), "拦截")
        XCTAssertEqual(GuardControlZoneView.outcomeText(.info), "信息")
    }

    func testGuardControlDeviceSummary() {
        XCTAssertEqual(GuardControlZoneView.deviceSummary(name: nil as String?, rssi: nil as Int?), "未绑定设备")
        XCTAssertEqual(GuardControlZoneView.deviceSummary(name: "iPhone 16 Pro", rssi: -65), "iPhone 16 Pro · -65 dBm")
        XCTAssertEqual(GuardControlZoneView.deviceSummary(name: "MacBook", rssi: nil as Int?), "MacBook · -- dBm")
    }

    func testGuardControlJudgementDetail() {
        let eventWithDetail = DecisionEvent(
            timestamp: Date(),
            category: .lock,
            outcome: .success,
            reason: .lockedAway,
            rssi: -85,
            device: "iPhone",
            screen: nil,
            detail: "信号强度 -85 dBm 低于阈值 -80 dBm"
        )
        XCTAssertEqual(GuardControlZoneView.judgementDetail(for: eventWithDetail), "信号强度 -85 dBm 低于阈值 -80 dBm")

        let eventWithoutDetail = DecisionEvent(
            timestamp: Date(),
            category: .unlock,
            outcome: .success,
            reason: .unlockSuccess,
            rssi: -60,
            device: "iPhone",
            screen: nil,
            detail: ""
        )
        XCTAssertFalse(GuardControlZoneView.judgementDetail(for: eventWithoutDetail).isEmpty)
    }

    func testGuardControlLatestCoreEventFiltersIMessageFailure() {
        let lockEvent = DecisionEvent(
            timestamp: Date().addingTimeInterval(-10),
            category: .lock,
            outcome: .success,
            reason: .lockedAway,
            rssi: -85,
            device: "iPhone",
            screen: nil,
            detail: "信号低于阈值"
        )
        let imessageFailedEvent = DecisionEvent(
            timestamp: Date(),
            category: .system,
            outcome: .failed,
            reason: .iMessageFailed,
            rssi: nil,
            device: nil,
            screen: nil,
            detail: "AppleScript 权限未授权"
        )

        let events = [lockEvent, imessageFailedEvent]
        let coreEvent = GuardControlZoneView.latestCoreEvent(in: events)

        XCTAssertNotNil(coreEvent, "应该能获取到核心锁屏/解锁判定事件")
        XCTAssertEqual(coreEvent?.reason, .lockedAway, "最新核心事件应为锁屏事件，而非异步 iMessage 失败事件")
    }

    func testGuardControlHasRecentIMessageFailure() {
        let imessageFailedEvent = DecisionEvent(
            timestamp: Date(),
            category: .system,
            outcome: .failed,
            reason: .iMessageFailed,
            rssi: nil,
            device: nil,
            screen: nil,
            detail: "AppleScript 权限未授权"
        )

        // 当用户未开启 iMessage 通知时，不应提示
        XCTAssertFalse(
            GuardControlZoneView.hasRecentIMessageFailure(in: [imessageFailedEvent], isNotifyEnabled: false),
            "用户未开启通知时不应展示授权提示"
        )

        // 当用户开启了 iMessage 通知且发生过失败时，应提示
        XCTAssertTrue(
            GuardControlZoneView.hasRecentIMessageFailure(in: [imessageFailedEvent], isNotifyEnabled: true),
            "开启通知且出现错误时应展示授权提示"
        )
    }
}
