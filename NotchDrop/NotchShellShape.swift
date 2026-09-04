import SwiftUI

// 自定义刘海外壳几何：一笔画出顶部微圆角 + 底部大圆角，无飞檐。
struct NotchShellShape: InsettableShape {
    // 顶部微圆角半径
    var topMicroRadius: CGFloat = 6
    // 底部大圆角半径
    var bottomRadius: CGFloat = 26
    // 内描边 inset 量（strokeBorder 用）
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        var path = Path()
        // 顶部微圆角与底部大圆角，取整避免负值
        let tr = max(topMicroRadius, 0)
        let br = max(bottomRadius, 0)
        // 三次贝塞尔控制臂长（圆角近似系数）
        let k = br * 0.52
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY

        // 起笔：左上弧下方
        path.move(to: CGPoint(x: minX, y: minY + tr))
        // 左上弧：180 度到 270 度
        path.addArc(
            center: CGPoint(x: minX + tr, y: minY + tr),
            radius: tr,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        // 顶边直线
        path.addLine(to: CGPoint(x: maxX - tr, y: minY))
        // 右上弧：-90 度到 0 度
        path.addArc(
            center: CGPoint(x: maxX - tr, y: minY + tr),
            radius: tr,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        // 右侧直线
        path.addLine(to: CGPoint(x: maxX, y: maxY - br))
        // 右下大圆角：三次贝塞尔
        path.addCurve(
            to: CGPoint(x: maxX - br, y: maxY),
            control1: CGPoint(x: maxX, y: maxY - br + k),
            control2: CGPoint(x: maxX - br + k, y: maxY)
        )
        // 底边直线
        path.addLine(to: CGPoint(x: minX + br, y: maxY))
        // 左下大圆角：右下镜像
        path.addCurve(
            to: CGPoint(x: minX, y: maxY - br),
            control1: CGPoint(x: minX + br - k, y: maxY),
            control2: CGPoint(x: minX, y: maxY - br + k)
        )
        // 左侧直线上收
        path.addLine(to: CGPoint(x: minX, y: minY + tr))
        path.closeSubpath()
        return path
    }
}
