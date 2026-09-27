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
        guard rect.size.width > 0, rect.size.height > 0 else {
            return Path()
        }

        let k: CGFloat = 0.5522847498
        let earW = min(max(0, cornerRadius), rect.width / 2)
        let maxBottomRadiusH = max(0, (rect.width - 2 * earW) / 2)
        var bRadius = max(0, min(bottomRadius, maxBottomRadiusH))
        var blendH = earW > 0 ? max(0, filletBlend) : 0

        // 审计 U-C1：当 rect.height < blendH + bRadius 时，Step 2 终点 (minY + blendH)
        // 会低于 Step 3 起点/终点 (maxY - bRadius)，导致侧边路径反向倒退自交，破坏 GPU 填充与缠绕规则。
        // 常见于展开动画中间帧、面板最小保底高度 (minPanelHeight = 60pt < 64 + 26 = 90pt)、收起态 (28pt) 等场景。
        // 修复策略（视觉稳定优先）：在可用高度不足容纳 blendH + bRadius 时，将两者按比例等比压缩，
        // 既保持曲率形状协调与动画平滑连续，又确保 rect.maxY - bRadius >= rect.minY + blendH，消除路径自交；
        // 正常大高度下（如展开态 filletBlend=64, bottomRadius=26，总高 >= 90pt）两者数值完全不变（原值无漂移）。
        let totalH = blendH + bRadius
        if totalH > rect.height {
            if totalH > 0 {
                let scale = rect.height / totalH
                blendH *= scale
                bRadius *= scale
                // 浮点精度保护，确保 maxY - bRadius >= minY + blendH 绝对成立（下行直线位移 >= 0）
                blendH = min(blendH, max(0, rect.height - bRadius))
            } else {
                blendH = 0
                bRadius = 0
            }
        }

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
