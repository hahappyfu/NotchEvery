//
//  SmoothNotchShape.swift
//  NotchDrop
//
//  Created by Antigravity on 2026/9/15.
//

import SwiftUI

/// 正向平滑连续贝塞尔曲线刘海轮廓，替代原先 destinationOut 反向遮罩以消灭边缘白边
public struct SmoothNotchShape: Shape {
    public var cornerRadius: CGFloat
    public var filletBlend: CGFloat
    public var bottomRadius: CGFloat
    public var isExpanded: Bool

    public var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(cornerRadius, AnimatablePair(filletBlend, bottomRadius))
        }
        set {
            cornerRadius = newValue.first
            filletBlend = newValue.second.first
            bottomRadius = newValue.second.second
        }
    }

    public init(
        cornerRadius: CGFloat = 8,
        filletBlend: CGFloat = 16,
        bottomRadius: CGFloat = 8,
        isExpanded: Bool = false
    ) {
        self.cornerRadius = cornerRadius
        self.filletBlend = filletBlend
        self.bottomRadius = bottomRadius
        self.isExpanded = isExpanded
    }

    public func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else {
            return Path()
        }

        let k: CGFloat = 0.5522847498
        let earW = min(max(0, cornerRadius), rect.width / 2)
        let blendH = min(max(0, filletBlend), rect.height)
        let maxBottomRadius = min(rect.height, (rect.width - 2 * earW) / 2)
        let bRadius = max(0, min(bottomRadius, maxBottomRadius))

        let mainLeft = rect.minX + earW
        let mainRight = rect.maxX - earW

        var path = Path()

        if earW <= 0 || blendH <= 0 {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - bRadius))
            if bRadius > 0 {
                path.addCurve(
                    to: CGPoint(x: rect.minX + bRadius, y: rect.maxY),
                    control1: CGPoint(x: rect.minX, y: rect.maxY - bRadius + bRadius * k),
                    control2: CGPoint(x: rect.minX + bRadius - bRadius * k, y: rect.maxY)
                )
            }
            path.addLine(to: CGPoint(x: rect.maxX - bRadius, y: rect.maxY))
            if bRadius > 0 {
                path.addCurve(
                    to: CGPoint(x: rect.maxX, y: rect.maxY - bRadius),
                    control1: CGPoint(x: rect.maxX - bRadius + bRadius * k, y: rect.maxY),
                    control2: CGPoint(x: rect.maxX, y: rect.maxY - bRadius + bRadius * k)
                )
            }
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.closeSubpath()
            return path
        }

        // 1. 从顶部中心出发向左绘制顶边
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        // 2. 在左侧以反曲贝塞尔曲线平滑外延到外耳过渡区
        path.addCurve(
            to: CGPoint(x: mainLeft, y: rect.minY + blendH),
            control1: CGPoint(x: rect.minX + earW * k, y: rect.minY),
            control2: CGPoint(x: mainLeft, y: rect.minY + blendH - blendH * k)
        )

        // 3. 沿外侧下行至底角
        path.addLine(to: CGPoint(x: mainLeft, y: rect.maxY - bRadius))

        // 4. 绘制左底平滑圆角
        if bRadius > 0 {
            path.addCurve(
                to: CGPoint(x: mainLeft + bRadius, y: rect.maxY),
                control1: CGPoint(x: mainLeft, y: rect.maxY - bRadius + bRadius * k),
                control2: CGPoint(x: mainLeft + bRadius - bRadius * k, y: rect.maxY)
            )
        }

        // 5. 沿底部水平连接至右底角
        path.addLine(to: CGPoint(x: mainRight - bRadius, y: rect.maxY))

        // 6. 绘制右底平滑圆角
        if bRadius > 0 {
            path.addCurve(
                to: CGPoint(x: mainRight, y: rect.maxY - bRadius),
                control1: CGPoint(x: mainRight - bRadius + bRadius * k, y: rect.maxY),
                control2: CGPoint(x: mainRight, y: rect.maxY - bRadius + bRadius * k)
            )
        }

        // 7. 沿右侧边缘上行至右耳过渡起点
        path.addLine(to: CGPoint(x: mainRight, y: rect.minY + blendH))

        // 8. 右侧以反曲贝塞尔曲线平滑收回顶边
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control1: CGPoint(x: mainRight, y: rect.minY + blendH - blendH * k),
            control2: CGPoint(x: rect.maxX - earW * k, y: rect.minY)
        )

        // 9. 沿顶边闭合到顶部中心
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.closeSubpath()

        return path
    }
}
