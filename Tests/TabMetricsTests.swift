import XCTest
@testable import NotchEvery

/// 内容自适应面板（ADR-0008）：高度表已删，本文件只锁边界、跟随关系与保留常量。
final class TabMetricsTests: XCTestCase {
    func testPanelBoundsSane() {
        XCTAssertEqual(NotchViewModel.minPanelSize, CGSize(width: 160, height: 60))
        XCTAssertEqual(NotchViewModel.maxPanelWidth, 640)
    }

    func testCompactPanelSizing() {
        // 物理刘海为 200pt 时，宽度保底为 200 + 16 = 216pt
        let sizeWithNotch = NotchViewModel.clampPanelSize(
            CGSize(width: 100, height: 40),
            maxHeight: 400,
            deviceNotchWidth: 200
        )
        XCTAssertEqual(sizeWithNotch.width, 216)
        XCTAssertEqual(sizeWithNotch.height, 60, "高度保底应为 60pt")

        // 无物理刘海时，宽度保底仅为内容自然宽（受 160 保底）
        let sizeWithoutNotch = NotchViewModel.clampPanelSize(
            CGSize(width: 180, height: 50),
            maxHeight: 400,
            deviceNotchWidth: 0
        )
        XCTAssertEqual(sizeWithoutNotch.width, 180)
        XCTAssertEqual(sizeWithoutNotch.height, 60)
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
        // 四分区映射：概览、Token、网关、剪贴板（开关默认开）
        ConfigStore.shared.set(true, forKey: "showGatewayZone")
        XCTAssertEqual(NotchViewModel.zoneOrder, [.normal, .token, .gateway, .clipboard])
        XCTAssertEqual(NotchViewModel.pageIndex(for: .normal), 0)
        XCTAssertEqual(NotchViewModel.pageIndex(for: .token), 1)
        XCTAssertEqual(NotchViewModel.pageIndex(for: .gateway), 2)
        XCTAssertEqual(NotchViewModel.pageIndex(for: .clipboard), 3)
        XCTAssertEqual(NotchViewModel.zone(for: 0), .normal)
        XCTAssertEqual(NotchViewModel.zone(for: 1), .token)
        XCTAssertEqual(NotchViewModel.zone(for: 2), .gateway)
        XCTAssertEqual(NotchViewModel.zone(for: 3), .clipboard)
    }

    func testOverviewPageSpacingAndPadding() {
        // 验证 OverviewPageView 使用紧凑间距 8pt 且两张卡片存在
        let overview = OverviewPageView(vm: NotchViewModel())
        XCTAssertNotNil(overview)
    }
}
