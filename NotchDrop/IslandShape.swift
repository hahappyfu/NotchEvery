//
//  IslandShape.swift
//  NotchEvery
//
//  黑岛形状：顶部贴屏顶 + 左右凹角（concave fillet）、底部圆角。
//  macOS 13 兼容自绘（UnevenRoundedRectangle 需 14+）。
//  filletRadius = 0 时退化为「底部圆角矩形」= 物理刘海同形（闲置态）。
//  参数不做 animatableData 插值：曾因动画竞争把参数卡在旧值致凹角恒不渲染；
//  状态 morph 由 frame 动画承担，圆角参数瞬时切换。
//  四段角均为显式三次贝塞尔（端点/控制点写死），不依赖 addArc 的角度/方向约定。
//

import SwiftUI

struct IslandShape: Shape {
    var bottomRadius: CGFloat
    var filletRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let _ = notchTimingMark("IslandShape.path fillet=\(filletRadius) br=\(bottomRadius) rect=\(rect)")
        var p = Path()
        let r = min(filletRadius, rect.width / 4, rect.height / 2)
        let br = min(bottomRadius, rect.width / 2, rect.height / 2)
        let _ = notchTimingMark("IslandShape.radius r=\(r) br=\(br)")
        let bodyL = rect.minX + r
        let bodyR = rect.maxX - r
        // 显式三次贝塞尔（k≈0.5523 标准四分之一圆常量）：不依赖 addArc 的
        // start/end/clockwise 角度约定（该约定曾致弧线反向扫掠 270°、圆角渲染成圆疙瘩）
        let kf = r * 0.5522847498
        let kb = br * 0.5522847498

        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        if r > 0 {
            // 右凹角：顶边右端 → 右侧边（绕圆心 (maxX, minY + r) = 挖槽外上角，凹向内；
            // 与原型 .nb-fillet.r radial-gradient(circle at 100% 100%) 同构）
            p.addCurve(
                to: CGPoint(x: bodyR, y: rect.minY + r),
                control1: CGPoint(x: rect.maxX - kf, y: rect.minY),
                control2: CGPoint(x: bodyR, y: rect.minY + r - kf)
            )
        }
        p.addLine(to: CGPoint(x: bodyR, y: rect.maxY - br))
        // 右下圆角
        p.addCurve(
            to: CGPoint(x: bodyR - br, y: rect.maxY),
            control1: CGPoint(x: bodyR, y: rect.maxY - br + kb),
            control2: CGPoint(x: bodyR - br + kb, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: bodyL + br, y: rect.maxY))
        // 左下圆角
        p.addCurve(
            to: CGPoint(x: bodyL, y: rect.maxY - br),
            control1: CGPoint(x: bodyL + br - kb, y: rect.maxY),
            control2: CGPoint(x: bodyL, y: rect.maxY - br + kb)
        )
        p.addLine(to: CGPoint(x: bodyL, y: rect.minY + r))
        if r > 0 {
            // 左凹角：左侧边 → 顶边左端（绕圆心 (minX, minY + r) = 挖槽外上角，凹向内；
            // 与原型 .nb-fillet.l radial-gradient(circle at 0% 100%) 同构）
            p.addCurve(
                to: CGPoint(x: rect.minX, y: rect.minY),
                control1: CGPoint(x: bodyL, y: rect.minY + r - kf),
                control2: CGPoint(x: rect.minX + kf, y: rect.minY)
            )
        }
        p.closeSubpath()
        return p
    }
}
