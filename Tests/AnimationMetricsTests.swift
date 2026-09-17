import XCTest
import SwiftUI
@testable import NotchEvery

final class AnimationMetricsTests: XCTestCase {
    func testSpringAnimationDefinitionsExist() {
        let vm = NotchViewModel()
        XCTAssertNotNil(vm.openAnimation)
        XCTAssertNotNil(vm.closeAnimation)
        XCTAssertNotNil(vm.pageAnimation)
        XCTAssertNotNil(StudioAnimation.interactiveSpring)
    }

    func testStudioAnimationResponseRange() {
        XCTAssertEqual(StudioAnimation.springResponse, 0.32, accuracy: 0.01)
        XCTAssertEqual(StudioAnimation.springDamping, 0.86, accuracy: 0.01)
    }

    func testOpenTriggersTransitionActive() {
        let vm = NotchViewModel()
        XCTAssertFalse(vm.transitionActive)
        vm.notchOpen(.click)
        XCTAssertEqual(vm.status, .opened)
        XCTAssertTrue(vm.transitionActive)
    }

    func testJumpToZoneUpdatesDirectionAndTransitionActive() {
        let vm = NotchViewModel()
        vm.jumpToZone(.token)
        XCTAssertEqual(vm.contentType, .token)
        XCTAssertEqual(vm.lastSwipeDirection, .next)
        XCTAssertTrue(vm.transitionActive)
    }
}
