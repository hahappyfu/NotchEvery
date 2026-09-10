import XCTest
@testable import NotchEvery

/// 内容自适应面板（ADR-0008）：高度表已删，本文件只锁边界、跟随关系与保留常量。
final class TabMetricsTests: XCTestCase {
    func testPanelBoundsSane() {
        XCTAssertEqual(NotchViewModel.minPanelSize, CGSize(width: 320, height: 120))
        XCTAssertEqual(NotchViewModel.maxPanelWidth, 640)
    }

    func testMaxHeightFollowsScreen() {
        let vm = NotchViewModel(events: MockEventMonitors())
        XCTAssertEqual(vm.maxPanelHeight, 360, "屏幕未知时回落 360")
        vm.screenRect = CGRect(x: 0, y: 0, width: 1512, height: 982)
        XCTAssertEqual(vm.maxPanelHeight, 982 * 0.4, accuracy: 0.001)
    }

    func testHeaderSlotHeightRetained() {
        // headerSlotHeight 常量保留，不作语义用途
        XCTAssertEqual(NotchViewModel.headerSlotHeight, 29)
    }

    func testNotchSafeAreaTop() {
        // 安全区 = 物理刘海高 + 8pt；无刘海屏沿用控制器兜底值
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.deviceNotchRect = CGRect(x: 0, y: 0, width: 200, height: 30)
        XCTAssertEqual(vm.notchSafeAreaTop, 38)
    }

    func testPageZoneMapping() {
        XCTAssertEqual(NotchViewModel.zoneOrder, [.normal, .token])
        XCTAssertEqual(NotchViewModel.pageIndex(for: .normal), 0)
        XCTAssertEqual(NotchViewModel.pageIndex(for: .token), 1)
        XCTAssertEqual(NotchViewModel.zone(for: 0), .normal)
        XCTAssertEqual(NotchViewModel.zone(for: 1), .token)
    }
}
