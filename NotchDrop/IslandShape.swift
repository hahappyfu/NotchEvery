//
//  IslandShape.swift
//  NotchEvery
//
//  黑岛形状：顶部贴屏顶 + 左右凹角（concave fillet）、底部圆角。
//  macOS 13 兼容自绘（UnevenRoundedRectangle 需 14+）。
//  filletRadius = 0 时退化为「底部圆角矩形」= 物理刘海同形（闲置态）。
//  参数实现 animatableData：fillet 0↔15 随 morph 平滑生长。
//

import SwiftUI

struct IslandShape: Shape {
    var bottomRadius: CGFloat
    var filletRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, filletRadius) }
        set {
            bottomRadius = newValue.first
            filletRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(filletRadius, rect.width / 4, rect.height / 2)
        let br = min(bottomRadius, rect.width / 2, rect.height / 2)
        let bodyL = rect.minX + r
        let bodyR = rect.maxX - r

        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        if r > 0 {
            // 右凹角：顶边右端 → 右侧边（绕外上角，凹向内）
            p.addArc(center: CGPoint(x: bodyR, y: rect.minY), radius: r,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        }
        p.addLine(to: CGPoint(x: bodyR, y: rect.maxY - br))
        // 右下圆角
        p.addArc(center: CGPoint(x: bodyR - br, y: rect.maxY - br), radius: br,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: bodyL + br, y: rect.maxY))
        // 左下圆角
        p.addArc(center: CGPoint(x: bodyL + br, y: rect.maxY - br), radius: br,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: bodyL, y: rect.minY + r))
        if r > 0 {
            // 左凹角：左侧边 → 顶边左端
            p.addArc(center: CGPoint(x: bodyL, y: rect.minY), radius: r,
                     startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        }
        p.closeSubpath()
        return p
    }
}
