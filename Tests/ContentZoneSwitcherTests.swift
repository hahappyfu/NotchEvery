import XCTest
@testable import NotchEvery

final class ContentZoneSwitcherTests: XCTestCase {
    func testNextZoneWrapsAround() {
        // 分区循环：末区（网关）之后回到概览。显式开网关页，不依赖环境默认值。
        ConfigStore.shared.set(true, forKey: "showGatewayZone")
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.gateway)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .normal)
    }

    func testPreviousZoneWrapsAround() {
        // 分区循环：概览之前是末区（网关）。显式开网关页。
        ConfigStore.shared.set(true, forKey: "showGatewayZone")
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.normal)
        vm.previousZone()
        XCTAssertEqual(vm.contentType, .gateway)
    }

    func testNextZoneAdvancesInOrder() {
        // 概览 → 剪贴板 → Token，逐段推进
        ConfigStore.shared.set(true, forKey: "showGatewayZone")
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.normal)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .clipboard)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .token)
    }

    func testPreviousZoneStepsBackward() {
        // Token → 剪贴板 → 概览，逐段倒退
        ConfigStore.shared.set(true, forKey: "showGatewayZone")
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.token)
        vm.previousZone()
        XCTAssertEqual(vm.contentType, .clipboard)
        vm.previousZone()
        XCTAssertEqual(vm.contentType, .normal)
    }

    func testGatewayZoneExcludedWhenDisabled() {
        // 关开关：网关页从分页剔除，Token 成为末区（循环回概览）
        ConfigStore.shared.set(false, forKey: "showGatewayZone")
        defer { ConfigStore.shared.set(true, forKey: "showGatewayZone") }
        XCTAssertEqual(NotchViewModel.zoneOrder, [.normal, .clipboard, .token])
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.clipboard)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .token)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .normal)
    }

    func testGatewayZoneIncludedWhenEnabled() {
        ConfigStore.shared.set(true, forKey: "showGatewayZone")
        XCTAssertEqual(NotchViewModel.zoneOrder, [.normal, .clipboard, .token, .gateway])
        XCTAssertEqual(NotchViewModel.pageIndex(for: .clipboard), 1)
        XCTAssertEqual(NotchViewModel.pageIndex(for: .gateway), 3)
    }

    func testMarkSwipeHintSeenSetsFlag() {
        // hasSeenSwipeHint 经 PublishedPersist 落盘到应用配置目录，
        // 先清掉残留文件再创建被测对象，保证首句断言稳定为默认 false。
        try? FileManager.default.removeItem(at: FileStorage().pathForKey("hasSeenSwipeHint"))
        let vm = NotchViewModel(events: MockEventMonitors())
        XCTAssertFalse(vm.hasSeenSwipeHint)
        vm.markSwipeHintSeen()
        XCTAssertTrue(vm.hasSeenSwipeHint)
    }
}
