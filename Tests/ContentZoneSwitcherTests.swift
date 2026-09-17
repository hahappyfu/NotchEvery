import XCTest
@testable import NotchEvery

final class ContentZoneSwitcherTests: XCTestCase {
    func testNextZoneWrapsAround() {
        // 双分区循环：末区之后回到概览
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.token)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .normal)
    }

    func testPreviousZoneWrapsAround() {
        // 双分区循环：概览之前是 Token
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.normal)
        vm.previousZone()
        XCTAssertEqual(vm.contentType, .token)
    }

    func testNextZoneAdvancesInOrder() {
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.normal)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .token)
    }

    func testPreviousZoneStepsBackward() {
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.token)
        vm.previousZone()
        XCTAssertEqual(vm.contentType, .normal)
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
