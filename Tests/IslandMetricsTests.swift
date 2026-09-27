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
        XCTAssertEqual(IslandMetrics.peekSize(for: proto), CGSize(width: 380, height: 82))
        XCTAssertEqual(IslandMetrics.peekBottomRadius(for: proto), 20)
        XCTAssertEqual(IslandMetrics.openBottomRadius, 26)
        XCTAssertEqual(IslandMetrics.openFilletRadius, 14)
    }

    func testShapeMetricsScaleWithRealNotch() {
        let real = CGSize(width: 179, height: 32)
        XCTAssertEqual(IslandMetrics.filletRadius(for: real), 9)
        XCTAssertEqual(IslandMetrics.peekSize(for: real), CGSize(width: 239, height: 57))
        XCTAssertEqual(IslandMetrics.peekBottomRadius(for: real), 13)
    }

    func testHoverActiveRectClosedMatchesDeviceNotchWithInset() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let notch = CGRect(x: (1440 - 285) / 2, y: 900 - 46, width: 285, height: 46)
        let geo = NotchGeometry(deviceNotchRect: notch, screenRect: screen, zoneOpenedSize: CGSize(width: 400, height: 300), inset: -4)

        let rect = geo.hoverActiveRect(status: .closed, hoverGhosting: false)
        XCTAssertEqual(rect, notch.insetBy(dx: -4, dy: -4))

        // 物理挖槽正中心应命中
        XCTAssertTrue(rect.contains(CGPoint(x: notch.midX, y: notch.midY)))
        // 挖槽下方（进入 peekHint 区域，例如 y = 900 - 65）在关闭态未进虚影时不命中
        XCTAssertFalse(rect.contains(CGPoint(x: notch.midX, y: 900 - 65)))
    }

    func testHoverActiveRectGhostExpandsToPeekSize() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let notch = CGRect(x: (1440 - 285) / 2, y: 900 - 46, width: 285, height: 46)
        let geo = NotchGeometry(deviceNotchRect: notch, screenRect: screen, zoneOpenedSize: CGSize(width: 400, height: 300), inset: -4)

        let ghostRect = geo.hoverActiveRect(status: .closed, hoverGhosting: true)
        XCTAssertEqual(ghostRect.width, 380)
        XCTAssertEqual(ghostRect.height, 82)
        XCTAssertEqual(ghostRect.maxY, 900)
        XCTAssertEqual(ghostRect.minY, 900 - 82)

        // 挖槽正中心命中
        XCTAssertTrue(ghostRect.contains(CGPoint(x: notch.midX, y: notch.midY)))
        // 挖槽下方 peekHint 文案区（y = 900 - 65）在虚影态必须命中，防止触发延时收起
        XCTAssertTrue(ghostRect.contains(CGPoint(x: notch.midX, y: 900 - 65)))
        // 左右边缘外扩区（例如距离中线 160pt）必须命中（原 285 挖槽半宽 142.5，peek 380 半宽 190）
        XCTAssertTrue(ghostRect.contains(CGPoint(x: notch.midX + 160, y: 900 - 30)))
        // 虚影岛体完全外部不应命中
        XCTAssertFalse(ghostRect.contains(CGPoint(x: notch.midX, y: 900 - 95)))
    }

    func testHoverActiveRectOpenedMatchesNotchOpenedRect() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let notch = CGRect(x: (1440 - 285) / 2, y: 900 - 46, width: 285, height: 46)
        let openedSize = CGSize(width: 500, height: 350)
        let geo = NotchGeometry(deviceNotchRect: notch, screenRect: screen, zoneOpenedSize: openedSize, inset: -4)

        let openedRect = geo.hoverActiveRect(status: .opened, hoverGhosting: false)
        XCTAssertEqual(openedRect, geo.notchOpenedRect)
        XCTAssertEqual(openedRect.width, 500)
        XCTAssertEqual(openedRect.height, 350)
        XCTAssertTrue(openedRect.contains(CGPoint(x: notch.midX, y: 900 - 200)))
    }
}
