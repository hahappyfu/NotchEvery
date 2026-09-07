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
            XCTAssertEqual(vm.zoneOpenedSize.width, NotchViewModel.zonePanelWidth[zone])
            XCTAssertEqual(vm.zoneOpenedSize.height, NotchViewModel.zonePanelHeight[zone])
        }
    }

    func testZoneWidthTableCoversAllZones() {
        for zone in NotchViewModel.zoneOrder {
            let width = NotchViewModel.zonePanelWidth[zone]
            XCTAssertNotNil(width, "分区 \(zone) 缺少宽度表条目")
            XCTAssertGreaterThan(width ?? 0, 0)
        }
    }

    func testMenuZoneIsNarrowerThanOverview() {
        XCTAssertLessThan(
            NotchViewModel.zonePanelWidth[.menu] ?? 600,
            NotchViewModel.zonePanelWidth[.normal] ?? 600,
            "菜单区必须比概览窄"
        )
    }

    func testTabTitleKeysAreUnique() {
        let keys = NotchViewModel.zoneOrder.map { String(describing: $0.tabTitleKey) }
        XCTAssertEqual(Set(keys).count, keys.count, "三区标题键重复")
    }
}
