import XCTest
@testable import NotchEvery

final class ContentZoneSwitcherTests: XCTestCase {
    func testNextZoneWrapsAround() {
        // 分区循环：末区（剪贴板第 4 页）之后回到概览。显式开网关页，不依赖环境默认值。
        ConfigStore.shared.set(true, forKey: "showGatewayZone")
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.clipboard)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .normal)
    }

    func testPreviousZoneWrapsAround() {
        // 分区循环：概览之前是末区（剪贴板）。显式开网关页。
        ConfigStore.shared.set(true, forKey: "showGatewayZone")
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.normal)
        vm.previousZone()
        XCTAssertEqual(vm.contentType, .clipboard)
    }

    func testNextZoneAdvancesInOrder() {
        // 概览 → Token → 网关 → 剪贴板，逐段推进
        ConfigStore.shared.set(true, forKey: "showGatewayZone")
        let vm = NotchViewModel(events: MockEventMonitors())
        XCTAssertEqual(vm.contentType, .normal)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .token)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .gateway)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .clipboard)
    }

    func testPreviousZoneReversesInOrder() {
        // 剪贴板 → 网关 → Token → 概览，逆向逐段回退
        ConfigStore.shared.set(true, forKey: "showGatewayZone")
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.clipboard)
        XCTAssertEqual(vm.contentType, .clipboard)
        vm.previousZone()
        XCTAssertEqual(vm.contentType, .gateway)
        vm.previousZone()
        XCTAssertEqual(vm.contentType, .token)
        vm.previousZone()
        XCTAssertEqual(vm.contentType, .normal)
    }

    func testGatewayZoneExcludedWhenDisabled() {
        // 关闭网关页：顺序为 概览 → Token → 剪贴板
        ConfigStore.shared.set(false, forKey: "showGatewayZone")
        XCTAssertEqual(NotchViewModel.zoneOrder, [.normal, .token, .clipboard])
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.normal)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .token)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .clipboard)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .normal)
    }

    func testGatewayZoneIncludedWhenEnabled() {
        ConfigStore.shared.set(true, forKey: "showGatewayZone")
        XCTAssertEqual(NotchViewModel.zoneOrder, [.normal, .token, .gateway, .clipboard])
        XCTAssertEqual(NotchViewModel.pageIndex(for: .gateway), 2)
        XCTAssertEqual(NotchViewModel.pageIndex(for: .clipboard), 3)
    }

    func testMarkSwipeHintSeenSetsFlag() {
        try? FileManager.default.removeItem(at: FileStorage().pathForKey("hasSeenSwipeHint"))
        let vm = NotchViewModel(events: MockEventMonitors())
        XCTAssertFalse(vm.hasSeenSwipeHint)
        vm.markSwipeHintSeen()
        XCTAssertTrue(vm.hasSeenSwipeHint)
    }
}
