import XCTest
@testable import NotchEvery

final class ContentZoneSwitcherTests: XCTestCase {
    func testNextZoneWrapsAround() {
        // 诊断分区（工单 06）进循环：末区之后回到概览
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.diagnostics)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .normal)
    }

    func testPreviousZoneWrapsAround() {
        // 诊断分区（工单 06）进循环：概览之前是诊断
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.normal)
        vm.previousZone()
        XCTAssertEqual(vm.contentType, .diagnostics)
    }

    func testNextZoneAdvancesInOrder() {
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.normal)
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .token)
    }

    /// 诊断分区横扫双向可达（06 工单验收：横扫到达）
    func testDiagnosticsReachableBySwipe() {
        let vm = NotchViewModel(events: MockEventMonitors())
        vm.jumpToZone(.normal)
        vm.nextZone()
        vm.nextZone()
        XCTAssertEqual(vm.contentType, .diagnostics)
        vm.previousZone()
        XCTAssertEqual(vm.contentType, .token)
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
