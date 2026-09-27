import Combine
import XCTest
@testable import NotchEvery

final class ArrowKeyZoneSwitchTests: XCTestCase {
    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testArrowKeyNextAdvancesAndWraps() {
        ConfigStore.shared.set(1, forKey: "showGatewayZone")
        let mocks = MockEventMonitors()
        let vm = NotchViewModel(events: mocks)
        mocks.arrowKey.sink { [weak vm] direction in
            vm?.handleArrowKey(direction)
        }.store(in: &cancellables)

        vm.jumpToZone(.normal)
        mocks.arrowKey.send(.rightForward)
        XCTAssertEqual(vm.contentType, .token)
        XCTAssertTrue(vm.hasSeenSwipeHint)

        mocks.arrowKey.send(.rightForward)
        XCTAssertEqual(vm.contentType, .gateway)

        mocks.arrowKey.send(.rightForward)
        XCTAssertEqual(vm.contentType, .normal)
    }

    func testArrowKeyPreviousWrapsAround() {
        ConfigStore.shared.set(1, forKey: "showGatewayZone")
        let mocks = MockEventMonitors()
        let vm = NotchViewModel(events: mocks)
        mocks.arrowKey.sink { [weak vm] direction in
            vm?.handleArrowKey(direction)
        }.store(in: &cancellables)

        vm.jumpToZone(.normal)
        mocks.arrowKey.send(.leftBackward)
        XCTAssertEqual(vm.contentType, .gateway)
        XCTAssertTrue(vm.hasSeenSwipeHint)
    }

    func testArrowKeyRespectsGatewayDisabled() {
        ConfigStore.shared.set(0, forKey: "showGatewayZone")
        let mocks = MockEventMonitors()
        let vm = NotchViewModel(events: mocks)
        mocks.arrowKey.sink { [weak vm] direction in
            vm?.handleArrowKey(direction)
        }.store(in: &cancellables)

        vm.jumpToZone(.normal)
        mocks.arrowKey.send(.rightForward)
        XCTAssertEqual(vm.contentType, .token)

        mocks.arrowKey.send(.rightForward)
        XCTAssertEqual(vm.contentType, .normal)

        mocks.arrowKey.send(.leftBackward)
        XCTAssertEqual(vm.contentType, .token)
    }
}
