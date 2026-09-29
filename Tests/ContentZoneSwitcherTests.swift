import XCTest
@testable import NotchEvery

final class ContentZoneSwitcherTests: XCTestCase {
    func testNextZoneWrapsAround() {
        // 分区循环：末区（Token 第 2 页）之后回到概览
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.token)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .normal)
    }

    func testPreviousZoneWrapsAround() {
        // 分区循环：概览之前是末区（Token）
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.normal)
        vm.previousZone()
        XCTAssertEqual(vm.contentType, .token)
    }

    func testNextZoneAdvancesInOrder() {
        // 概览 → Token，逐段推进后回绕
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.normal)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .token)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .normal)
    }

    func testPreviousZoneRewindsInOrder() {
        // 概览 ← Token，反向推进后回绕
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.token)
        vm.previousZone()
        XCTAssertEqual(vm.contentType, .normal)
        vm.previousZone()
        XCTAssertEqual(vm.contentType, .token)
    }

    func testZoneOrderIsTwoPages() {
        // 双分区：概览与 Token
        XCTAssertEqual(NotchViewModel.zoneOrder, [.normal, .token])
        XCTAssertEqual(NotchViewModel.pageIndex(for: .normal), 0)
        XCTAssertEqual(NotchViewModel.pageIndex(for: .token), 1)
    }

    func testMarkSwipeHintSeenSetsFlag() {
        try? FileManager.default.removeItem(at: FileStorage().pathForKey("hasSeenSwipeHint"))
        let vm = NotchViewModel(events: MockEventMonitors())
        XCTAssertFalse(vm.hasSeenSwipeHint)
        vm.markSwipeHintSeen()
        XCTAssertTrue(vm.hasSeenSwipeHint)
    }
}
