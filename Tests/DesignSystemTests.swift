import XCTest
import SwiftUI
@testable import NotchEvery

final class DesignSystemTests: XCTestCase {
    func testStudioColorsExist() {
        XCTAssertNotNil(StudioColor.emerald)
        XCTAssertNotNil(StudioColor.amber)
        XCTAssertNotNil(StudioColor.rose)
        XCTAssertNotNil(StudioColor.indigo)
        XCTAssertNotNil(StudioColor.cyan)
    }

    func testStudioSpringTiming() {
        XCTAssertEqual(StudioAnimation.springResponse, 0.32, accuracy: 0.01)
        XCTAssertEqual(StudioAnimation.springDamping, 0.82, accuracy: 0.01)
    }
}
