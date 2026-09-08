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
        // 概览 165：页自然高 105（探针实测）+ dots 行 19 + 上下 padding 40 + 1pt 余量（任务 8 方案 C，无头部行）
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.normal)
        XCTAssertEqual(vm.zoneOpenedSize.width, 520)
        XCTAssertEqual(vm.zoneOpenedSize.height, 165)
    }

    func testZoneOpenedSizeFollowsCurrentZone() {
        let vm = NotchViewModel(events: MockEventMonitors())
        for zone in NotchViewModel.zoneOrder {
            vm.jumpToZone(zone)
            XCTAssertEqual(vm.zoneOpenedSize.width, 520, "分区 \(zone) 宽度必须全区一致，选项卡跨区不动")
            XCTAssertEqual(vm.zoneOpenedSize.height, NotchViewModel.zonePanelHeight[zone])
        }
    }

    func testAllZonesShareWidthSoTabBarStaysPut() {
        XCTAssertEqual(NotchViewModel.zonePanelWidth, 520, "宽度全区锁定，切换不得重居中平移选项卡")
    }

    func testTokenZoneHeightIsSeeded() {
        // 探针实测页自然高 164（KPI 单行 + 表头 + 5 行）：164 + dots 行 19 + 上下 padding 40 + 1pt 余量 = 224
        XCTAssertEqual(NotchViewModel.zonePanelHeight[.token], 224)
    }

    func testMergedSettingsZoneHeightFitsButtonsPlusRows() {
        // 明细（守卫实测内容自然高 194、选项卡槽 29）：20+29+20+194+20 = 283，取 284 留 1pt 余量
        XCTAssertEqual(NotchViewModel.zonePanelHeight[.settings], 284)
    }

    func testHeaderSlotHeightMatchesHeightTableMath() {
        // 高度表推算依赖「选项卡 29」（守卫实测，原注释 28 差 1pt）：槽位改动必须同步高度表
        XCTAssertEqual(NotchViewModel.headerSlotHeight, 29)
    }

    func testZoneContentHeightSubtractsInsets() {
        // 全字面量：与实现公式重算即恒真，无检出力；这里锁定的是数值契约本身
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.normal)
        XCTAssertEqual(vm.zoneContentHeight, 125, "概览内容区可用高度必须锁定，额度卡排版以此为前提")
        vm.jumpToZone(.settings)
        XCTAssertEqual(vm.zoneContentHeight, 244, "设置内容区可用高度必须锁定，按钮行+设置行排版以此为前提")
    }

    func testTabTitleKeysAreUnique() {
        let keys = NotchViewModel.zoneOrder.map { String(describing: $0.tabTitleKey) }
        XCTAssertEqual(Set(keys).count, keys.count, "两区标题键重复")
    }

    func testPageZoneMapping() {
        XCTAssertEqual(NotchViewModel.zoneOrder, [.normal, .token])
        XCTAssertEqual(NotchViewModel.pageIndex(for: .normal), 0)
        XCTAssertEqual(NotchViewModel.pageIndex(for: .token), 1)
        XCTAssertEqual(NotchViewModel.zone(for: 0), .normal)
        XCTAssertEqual(NotchViewModel.zone(for: 1), .token)
    }
}
