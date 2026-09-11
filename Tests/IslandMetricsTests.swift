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
        XCTAssertEqual(IslandMetrics.openBottomRadius(for: proto), 26)
    }

    func testShapeMetricsScaleWithRealNotch() {
        let real = CGSize(width: 179, height: 32)
        XCTAssertEqual(IslandMetrics.filletRadius(for: real), 9)
        XCTAssertEqual(IslandMetrics.peekSize(for: real), CGSize(width: 220, height: 57))
        XCTAssertEqual(IslandMetrics.peekBottomRadius(for: real), 13)
        XCTAssertEqual(IslandMetrics.openBottomRadius(for: real), 16)
    }
}

/// 形状几何：凹角切角与圆角收角的点位断言（治「弧线反向扫掠成圆疙瘩」回归）。
final class IslandShapeTests: XCTestCase {
    func testConcaveFilletsCutTheCorners() {
        let rect = CGRect(x: 0, y: 0, width: 220, height: 57)
        let path = IslandShape(bottomRadius: 13, filletRadius: 9).path(in: rect)
        // 顶部两凹角区中心应被挖掉
        XCTAssertFalse(path.contains(CGPoint(x: 4.5, y: 4.5)))
        XCTAssertFalse(path.contains(CGPoint(x: 215.5, y: 4.5)))
        // 贴顶外侧被挖掉，内侧是实体
        XCTAssertFalse(path.contains(CGPoint(x: 0.5, y: 1)))
        XCTAssertTrue(path.contains(CGPoint(x: 30, y: 4.5)))
        XCTAssertTrue(path.contains(CGPoint(x: 110, y: 30)))
        // 底部两圆角切掉的角点之外
        XCTAssertFalse(path.contains(CGPoint(x: 0.5, y: 56.5)))
        XCTAssertFalse(path.contains(CGPoint(x: 219.5, y: 56.5)))
        XCTAssertTrue(path.contains(CGPoint(x: 110, y: 56.5)))
    }
}
