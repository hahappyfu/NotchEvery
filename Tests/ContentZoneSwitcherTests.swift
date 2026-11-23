import XCTest
@testable import NotchEvery

final class ContentZoneSwitcherTests: XCTestCase {
    func testNextZoneWrapsAround() {
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.providers)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .overview)
    }

    func testPreviousZoneWrapsAround() {
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.overview)
        vm.previousZone()
        XCTAssertEqual(vm.contentType, .providers)
    }

    func testNextZoneAdvancesInOrder() {
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.overview)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .token)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .providers)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .overview)
    }

    func testPreviousZoneRewindsInOrder() {
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.providers)
        vm.previousZone()
        XCTAssertEqual(vm.contentType, .token)
        vm.previousZone()
        XCTAssertEqual(vm.contentType, .overview)
        vm.previousZone()
        XCTAssertEqual(vm.contentType, .providers)
    }

    func testZoneOrderIsThreePages() {
        XCTAssertEqual(NotchViewModel.zoneOrder, [.overview, .token, .providers])
        XCTAssertEqual(NotchViewModel.pageIndex(for: .overview), 0)
        XCTAssertEqual(NotchViewModel.pageIndex(for: .token), 1)
        XCTAssertEqual(NotchViewModel.pageIndex(for: .providers), 2)
    }

    func testMarkSwipeHintSeenSetsFlag() {
        try? FileManager.default.removeItem(at: FileStorage().pathForKey("hasSeenSwipeHint"))
        let vm = NotchViewModel(events: MockEventMonitors())
        XCTAssertFalse(vm.hasSeenSwipeHint)
        vm.markSwipeHintSeen()
        XCTAssertTrue(vm.hasSeenSwipeHint)
    }
}
