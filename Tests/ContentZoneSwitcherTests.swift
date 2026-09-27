import XCTest
@testable import NotchEvery

final class ContentZoneSwitcherTests: XCTestCase {
    func testNextZoneWrapsAround() {
        // 分区循环：末区（网关第 3 页）之后回到概览。显式开网关页，不依赖环境默认值。
        ConfigStore.shared.set(1, forKey: "showGatewayZone") // Int 走 NSNumber.boolValue，等价 Bool
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.gateway)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .normal)
    }

    func testPreviousZoneWrapsAround() {
        // 分区循环：概览之前是末区（网关）。显式开网关页。
        ConfigStore.shared.set(1, forKey: "showGatewayZone")
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.normal)
        vm.previousZone()
        XCTAssertEqual(vm.contentType, .gateway)
    }

    func testNextZoneAdvancesInOrder() {
        // 概览 → Token → 网关，逐段推进后回绕
        ConfigStore.shared.set(1, forKey: "showGatewayZone")
        let vm = NotchViewModel(events: MockEventMonitors())
        XCTAssertEqual(vm.contentType, .normal)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .token)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .gateway)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .normal)
    }

    func testPreviousZoneReversesInOrder() {
        // 网关 → Token → 概览，逆向逐段回退后回绕
        ConfigStore.shared.set(1, forKey: "showGatewayZone")
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.gateway)
        XCTAssertEqual(vm.contentType, .gateway)
        vm.previousZone()
        XCTAssertEqual(vm.contentType, .token)
        vm.previousZone()
        XCTAssertEqual(vm.contentType, .normal)
        vm.previousZone()
        XCTAssertEqual(vm.contentType, .gateway)
    }

    func testGatewayZoneExcludedWhenDisabled() {
        // 关闭网关页：顺序为 概览 → Token
        ConfigStore.shared.set(0, forKey: "showGatewayZone")
        XCTAssertEqual(NotchViewModel.zoneOrder, [.normal, .token])
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.normal)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .token)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .normal)
    }

    func testGatewayZoneIncludedWhenEnabled() {
        ConfigStore.shared.set(1, forKey: "showGatewayZone")
        XCTAssertEqual(NotchViewModel.zoneOrder, [.normal, .token, .gateway])
        XCTAssertEqual(NotchViewModel.pageIndex(for: .gateway), 2)
    }

    func testMarkSwipeHintSeenSetsFlag() {
        try? FileManager.default.removeItem(at: FileStorage().pathForKey("hasSeenSwipeHint"))
        let vm = NotchViewModel(events: MockEventMonitors())
        XCTAssertFalse(vm.hasSeenSwipeHint)
        vm.markSwipeHintSeen()
        XCTAssertTrue(vm.hasSeenSwipeHint)
    }
}
