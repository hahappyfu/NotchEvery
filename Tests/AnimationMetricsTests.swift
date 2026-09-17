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
}
