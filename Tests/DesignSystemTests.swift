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
        XCTAssertEqual(StudioAnimation.springDamping, 0.86, accuracy: 0.01)
    }

    func testSmoothNotchShapePathValidity() {
        let shape = SmoothNotchShape(
            cornerRadius: 32,
            filletBlend: 64,
            bottomRadius: 26,
            isExpanded: true
        )
        let rect = CGRect(x: 0, y: 0, width: 320, height: 120)
        let path = shape.path(in: rect)
        XCTAssertFalse(path.isEmpty)
        XCTAssertTrue(path.boundingRect.width >= 320)

        // 零尺寸与边界防护
        let zeroPath = shape.path(in: CGRect.zero)
        XCTAssertTrue(zeroPath.isEmpty)

        // 收起态路径测试
        let closedShape = SmoothNotchShape(
            cornerRadius: 8,
            filletBlend: 16,
            bottomRadius: 8,
            isExpanded: false
        )
        let closedPath = closedShape.path(in: CGRect(x: 0, y: 0, width: 180, height: 32))
        XCTAssertFalse(closedPath.isEmpty)
        XCTAssertTrue(closedPath.boundingRect.width >= 180)
    }
}
