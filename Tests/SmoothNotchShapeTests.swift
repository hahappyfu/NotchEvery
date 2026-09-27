//
//  SmoothNotchShapeTests.swift
//  NotchEveryTests
//
//  Created for audit U-C1: SmoothNotchShape 贝塞尔路径自相交与非单调倒退防护测试。
//

import XCTest
import SwiftUI
@testable import NotchEvery

final class SmoothNotchShapeTests: XCTestCase {

    // MARK: - 辅助结构与路径点提取

    struct PathPointSample {
        let type: CGPathElementType
        let points: [CGPoint]
    }

    private func extractElements(from path: Path) -> [PathPointSample] {
        var samples: [PathPointSample] = []
        path.cgPath.applyWithBlock { elementPtr in
            let element = elementPtr.pointee
            let count: Int
            switch element.type {
            case .moveToPoint, .addLineToPoint:
                count = 1
            case .addQuadCurveToPoint:
                count = 2
            case .addCurveToPoint:
                count = 3
            case .closeSubpath:
                count = 0
            @unknown default:
                count = 0
            }
            let pts = (0..<count).map { element.points[$0] }
            samples.append(PathPointSample(type: element.type, points: pts))
        }
        return samples
    }

    // MARK: - 1. 展开态大高度逐点数值恒定测试（原值未漂移）

    func testExpandedLargeHeightValuesPreserved() {
        // 展开态真实参数：filletBlend=64, bottomRadius=26, cornerRadius=32
        let shape = SmoothNotchShape(
            cornerRadius: 32,
            filletBlend: 64,
            bottomRadius: 26,
            isExpanded: true
        )
        let rect = CGRect(x: 0, y: 0, width: 600, height: 300)
        let path = shape.path(in: rect)
        let elements = extractElements(from: path)

        let k: CGFloat = 0.5522847498
        let earW: CGFloat = 32
        let blendH: CGFloat = 64
        let bRadius: CGFloat = 26
        let mainLeft: CGFloat = earW
        let mainRight: CGFloat = 600 - earW

        // 验证关键路径点
        // 1. Move to (midX, minY) = (300, 0)
        XCTAssertEqual(elements[0].type, .moveToPoint)
        XCTAssertEqual(elements[0].points[0], CGPoint(x: 300, y: 0))

        // 2. Line to (minX, minY) = (0, 0)
        XCTAssertEqual(elements[1].type, .addLineToPoint)
        XCTAssertEqual(elements[1].points[0], CGPoint(x: 0, y: 0))

        // 3. Curve to (mainLeft, blendH) = (32, 64)
        XCTAssertEqual(elements[2].type, .addCurveToPoint)
        XCTAssertEqual(elements[2].points[0].x, earW * k, accuracy: 0.0001)
        XCTAssertEqual(elements[2].points[0].y, 0, accuracy: 0.0001)
        XCTAssertEqual(elements[2].points[1].x, mainLeft, accuracy: 0.0001)
        XCTAssertEqual(elements[2].points[1].y, blendH - blendH * k, accuracy: 0.0001)
        XCTAssertEqual(elements[2].points[2], CGPoint(x: mainLeft, y: blendH))

        // 4. Line to (mainLeft, maxY - bRadius) = (32, 300 - 26 = 274)
        XCTAssertEqual(elements[3].type, .addLineToPoint)
        XCTAssertEqual(elements[3].points[0], CGPoint(x: mainLeft, y: 300 - bRadius))

        // 5. Curve to (mainLeft + bRadius, maxY) = (32 + 26 = 58, 300)
        XCTAssertEqual(elements[4].type, .addCurveToPoint)
        XCTAssertEqual(elements[4].points[2], CGPoint(x: mainLeft + bRadius, y: 300))

        // 6. Line to (mainRight - bRadius, maxY) = (568 - 26 = 542, 300)
        XCTAssertEqual(elements[5].type, .addLineToPoint)
        XCTAssertEqual(elements[5].points[0], CGPoint(x: mainRight - bRadius, y: 300))

        // 7. Curve to (mainRight, maxY - bRadius) = (568, 274)
        XCTAssertEqual(elements[6].type, .addCurveToPoint)
        XCTAssertEqual(elements[6].points[2], CGPoint(x: mainRight, y: 300 - bRadius))

        // 8. Line to (mainRight, blendH) = (568, 64)
        XCTAssertEqual(elements[7].type, .addLineToPoint)
        XCTAssertEqual(elements[7].points[0], CGPoint(x: mainRight, y: blendH))

        // 9. Curve to (maxX, minY) = (600, 0)
        XCTAssertEqual(elements[8].type, .addCurveToPoint)
        XCTAssertEqual(elements[8].points[2], CGPoint(x: 600, y: 0))

        // 10. Line to (midX, minY) = (300, 0)
        XCTAssertEqual(elements[9].type, .addLineToPoint)
        XCTAssertEqual(elements[9].points[0], CGPoint(x: 300, y: 0))

        // 11. Close
        XCTAssertEqual(elements[10].type, .closeSubpath)
    }

    // MARK: - 2. 参数化高度扫描与防自交几何单调性验证

    func testHeightSweepMonotonicityAndNoSelfIntersection() {
        // 测试多种不同参数组合（覆盖收起态、展开态、peek态、popping态）
        let configs: [(name: String, cornerRadius: CGFloat, filletBlend: CGFloat, bottomRadius: CGFloat)] = [
            ("Opened", 32, 64, 26),
            ("Closed", 8, 16, 12),
            ("Peek", 20, 40, 20),
            ("Popping", 10, 20, 10),
            ("NoEar", 0, 0, 16),
            ("NoBottomRadius", 16, 32, 0)
        ]

        // 步进覆盖：从 20pt 到 400pt，特别包含临界点附近 20, 24, 28, 42, 60, 89, 90, 91, 100, 400
        var sampleHeights: [CGFloat] = [
            20, 24, 27.9, 28, 28.1, 35, 41.9, 42, 42.1, 50,
            59.9, 60, 60.1, 75, 89.9, 90, 90.1, 100, 120, 180, 250, 400
        ]
        // 增加规则步进
        for h in stride(from: 20.0, through: 400.0, by: 10.0) {
            sampleHeights.append(CGFloat(h))
        }

        for config in configs {
            let shape = SmoothNotchShape(
                cornerRadius: config.cornerRadius,
                filletBlend: config.filletBlend,
                bottomRadius: config.bottomRadius,
                isExpanded: true
            )

            for h in sampleHeights {
                let rect = CGRect(x: 0, y: 0, width: 400, height: h)
                let path = shape.path(in: rect)

                // 1. 基本约束：bounding box 高度不得超过 rect.height，无 NaN
                let bounds = path.boundingRect
                XCTAssertFalse(bounds.origin.x.isNaN, "[\(config.name) h=\(h)] bounds.origin.x is NaN")
                XCTAssertFalse(bounds.origin.y.isNaN, "[\(config.name) h=\(h)] bounds.origin.y is NaN")
                XCTAssertFalse(bounds.width.isNaN, "[\(config.name) h=\(h)] bounds.width is NaN")
                XCTAssertFalse(bounds.height.isNaN, "[\(config.name) h=\(h)] bounds.height is NaN")
                XCTAssertLessThanOrEqual(
                    bounds.maxY,
                    rect.maxY + 0.001,
                    "[\(config.name) h=\(h)] path bounds.maxY \(bounds.maxY) exceeds rect.maxY \(rect.maxY)"
                )

                // 2. 提取元素，验证所有控制点与端点无 NaN，且同侧几何单调
                let elements = extractElements(from: path)
                for element in elements {
                    for pt in element.points {
                        XCTAssertFalse(pt.x.isNaN, "[\(config.name) h=\(h)] point.x is NaN")
                        XCTAssertFalse(pt.y.isNaN, "[\(config.name) h=\(h)] point.y is NaN")
                        XCTAssertFalse(pt.x.isInfinite, "[\(config.name) h=\(h)] point.x is Infinite")
                        XCTAssertFalse(pt.y.isInfinite, "[\(config.name) h=\(h)] point.y is Infinite")
                    }
                }

                // 3. 几何单调性验证（左侧下行单调不减，右侧上行单调不增）
                // 查找到达底边的分界点（元素中 y 达到 maxY 的第一个点为底边起点）
                var reachedBottom = false
                var prevY: CGFloat = rect.minY

                for element in elements {
                    for pt in element.points {
                        if !reachedBottom {
                            // 左半部分：从顶向下前进，y 必须单调不减（允许极小浮点误差 -0.001）
                            XCTAssertGreaterThanOrEqual(
                                pt.y,
                                prevY - 0.001,
                                "[\(config.name) h=\(h)] Left side inverted/folded! pt.y (\(pt.y)) < prevY (\(prevY))"
                            )
                            prevY = max(prevY, pt.y)
                            if abs(pt.y - rect.maxY) < 0.001 {
                                reachedBottom = true
                            }
                        } else {
                            // 右半部分：从底向上前进，y 必须单调不增（允许极小浮点误差 +0.001）
                            XCTAssertLessThanOrEqual(
                                pt.y,
                                prevY + 0.001,
                                "[\(config.name) h=\(h)] Right side inverted/folded! pt.y (\(pt.y)) > prevY (\(prevY))"
                            )
                            prevY = min(prevY, pt.y)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 3. 边界退化场景测试

    func testDegenerateRectSizes() {
        let shape = SmoothNotchShape(cornerRadius: 32, filletBlend: 64, bottomRadius: 26)
        XCTAssertTrue(shape.path(in: .zero).isEmpty)
        XCTAssertTrue(shape.path(in: CGRect(x: 0, y: 0, width: -10, height: 100)).isEmpty)
        XCTAssertTrue(shape.path(in: CGRect(x: 0, y: 0, width: 100, height: 0)).isEmpty)
        XCTAssertTrue(shape.path(in: CGRect(x: 0, y: 0, width: 100, height: -50)).isEmpty)
    }
}
