import XCTest
@testable import NotchEvery

final class TabMetricsTests: XCTestCase {
    func testZoneHeightTableCoversAllZones() {
        for zone in NotchViewModel.zoneOrder {
            let height = NotchViewModel.zonePanelHeight[zone]
            XCTAssertNotNil(height, "分区 \(zone) 缺少高度表条目")
            XCTAssertGreaterThan(height ?? 0, 0)
        }
    }

    func testOverviewSizeLocked() {
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.normal)
        XCTAssertEqual(vm.zoneOpenedSize.width, 600)
        XCTAssertEqual(vm.zoneOpenedSize.height, 160)
    }

    func testZoneOpenedSizeFollowsCurrentZone() {
        let vm = NotchViewModel(events: MockEventMonitors())
        for zone in NotchViewModel.zoneOrder {
            vm.jumpToZone(zone)
            XCTAssertEqual(vm.zoneOpenedSize.width, 600, "分区 \(zone) 宽度必须全区一致，选项卡跨区不动")
            XCTAssertEqual(vm.zoneOpenedSize.height, NotchViewModel.zonePanelHeight[zone])
        }
    }

    func testAllZonesShareWidthSoTabBarStaysPut() {
        XCTAssertEqual(NotchViewModel.zonePanelWidth, 600, "宽度全区锁定，切换不得重居中平移选项卡")
    }

    func testMergedSettingsZoneHeightFitsButtonsPlusRows() {
        // 明细：选项卡 28 + 间距 20 + 按钮行 88 + 间距 20 + 设置行 120 + 上下内边距 40 = 316，取 320 留舍入余量
        XCTAssertEqual(NotchViewModel.zonePanelHeight[.settings], 320)
    }

    func testTabTitleKeysAreUnique() {
        let keys = NotchViewModel.zoneOrder.map { String(describing: $0.tabTitleKey) }
        XCTAssertEqual(Set(keys).count, keys.count, "两区标题键重复")
    }
}
