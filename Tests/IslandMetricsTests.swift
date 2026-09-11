import XCTest
@testable import NotchEvery

/// 模型列宽自适应：纯函数外部行为（钳制边界与单调性），不测具体像素值。
final class IslandMetricsTests: XCTestCase {
    func testEmptyModelsReturnsMin() {
        XCTAssertEqual(IslandMetrics.modelColumnWidth(for: []), IslandMetrics.modelColumnMin)
    }

    func testShortModelsClampToMin() {
        XCTAssertEqual(
            IslandMetrics.modelColumnWidth(for: ["gpt", "kimi", "qwen-plus"]),
            IslandMetrics.modelColumnMin
        )
    }

    func testVeryLongModelClampsToMax() {
        let long = String(repeating: "very-long-model-name-", count: 5)
        XCTAssertEqual(IslandMetrics.modelColumnWidth(for: [long]), IslandMetrics.modelColumnMax)
    }

    func testWidthMonotonicWithLongerNames() {
        let short = IslandMetrics.modelColumnWidth(for: ["gpt-5"])
        let mid = IslandMetrics.modelColumnWidth(for: ["deepseek-v4-flash-0731"])
        let long = IslandMetrics.modelColumnWidth(for: ["deepseek-ai/deepseek-v4-flash-0731"])
        XCTAssertLessThanOrEqual(short, mid)
        XCTAssertLessThanOrEqual(mid, long)
    }

    func testLongestModelDrivesWidth() {
        let mixed = IslandMetrics.modelColumnWidth(for: ["gpt-5", "qwen-plus-2025-07-14"])
        let onlyLong = IslandMetrics.modelColumnWidth(for: ["qwen-plus-2025-07-14"])
        XCTAssertEqual(mixed, onlyLong)
    }

    func testAlwaysWithinBounds() {
        for sample in [["a"], ["deepseek-v4-flash-vision-exp"], [String(repeating: "x", count: 60)]] {
            let w = IslandMetrics.modelColumnWidth(for: sample)
            XCTAssertGreaterThanOrEqual(w, IslandMetrics.modelColumnMin)
            XCTAssertLessThanOrEqual(w, IslandMetrics.modelColumnMax)
        }
    }

    func testShapeMetricsIdentityAtPrototypeScale() {
        let proto = CGSize(width: 285, height: 46)
        XCTAssertEqual(IslandMetrics.filletRadius(for: proto), 15)
        XCTAssertEqual(IslandMetrics.peekSize(for: proto), CGSize(width: 350, height: 82))
        XCTAssertEqual(IslandMetrics.peekBottomRadius(for: proto), 20)
        XCTAssertEqual(IslandMetrics.openBottomRadius, 26)
        XCTAssertEqual(IslandMetrics.openFilletRadius, 14)
    }

    func testShapeMetricsScaleWithRealNotch() {
        let real = CGSize(width: 179, height: 32)
        XCTAssertEqual(IslandMetrics.filletRadius(for: real), 9)
        XCTAssertEqual(IslandMetrics.peekSize(for: real), CGSize(width: 220, height: 57))
        XCTAssertEqual(IslandMetrics.peekBottomRadius(for: real), 13)
    }
}
