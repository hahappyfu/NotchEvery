//
//  IslandMetrics.swift
//  NotchEvery
//
//  黑岛几何与布局度量（纯逻辑，单测覆盖见 IslandMetricsTests）。
//

import AppKit
import SwiftUI

enum IslandMetrics {
    /// 悬停 peek 岛尺寸（原型 350×82，真机以视觉验收微调）
    static let peekSize = CGSize(width: 350, height: 82)
    /// 岛顶凹角半径
    static let filletRadius: CGFloat = 15
    /// 生长/收敛过渡弹簧（数据驱动宽度变化与岛尺寸变化共用）
    static let growSpring: Animation = .spring(response: 0.45, dampingFraction: 0.85)
    /// 模型列宽钳制区间
    static let modelColumnMin: CGFloat = 100
    static let modelColumnMax: CGFloat = 180

    /// 模型列宽：当前行最长模型名实测宽 + 4pt 呼吸，钳制 [min, max]。
    static func modelColumnWidth(for models: [String]) -> CGFloat {
        guard let longest = models.max(by: { textWidth($0) < textWidth($1) }) else {
            return modelColumnMin
        }
        return min(max(textWidth(longest) + 4, modelColumnMin), modelColumnMax)
    }

    private static let modelFont = NSFont.systemFont(ofSize: 11, weight: .semibold)

    private static func textWidth(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: modelFont]).width
    }
}
