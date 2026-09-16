//
//  GuardControlZoneViewTests.swift
//  NotchEvery
//
//  第三页：GuardControlZoneView 520pt 等宽重塑与布局约束测试
//

import XCTest
import SwiftUI
@testable import NotchEvery

final class GuardControlZoneViewTests: XCTestCase {

    func testGuardControlLayoutPreferredWidthIs520() {
        XCTAssertEqual(GuardControlLayout.preferredWidth, 520, "第三页控制台应使用 520pt 舒展等宽设计")
    }

    func testGuardControlLayoutPaddingsAndSpacing() {
        XCTAssertEqual(GuardControlLayout.horizontalPadding, 16, "水平边距收拢至 16pt")
        XCTAssertEqual(GuardControlLayout.verticalPadding, 10, "垂直边距收拢至 10pt")
        XCTAssertEqual(GuardControlLayout.toggleGridSpacing, 10, "2x2 开关间距调整为 10pt")
    }

    func testGuardControlLayoutToggleColumnWidthIsExpanded() {
        // preferredWidth (520) - horizontalPadding*2 (32) - toggleGridSpacing (10) = 478 / 2 = 239 > 230
        XCTAssertGreaterThan(GuardControlLayout.toggleColumnWidth, 230, "在 520pt 下单列可用宽度应大于 230pt，避免折行和拥挤")
        XCTAssertEqual(GuardControlLayout.toggleColumnWidth, 239)
    }

    func testJudgementDetailLineLimit() {
        XCTAssertEqual(GuardControlLayout.judgementDetailLineLimit, 2)
    }
}
