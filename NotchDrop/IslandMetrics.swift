//
//  IslandMetrics.swift
//  NotchEvery
//
//  黑岛几何与布局度量（纯逻辑，单测覆盖见 IslandMetricsTests）。
//

import AppKit
import SwiftUI

enum IslandMetrics {
    /// 原型基准画布：挖槽 285×46，fillet 15、peek 380×82（放宽余量杜绝截断）、peek 底圆角 20、open 底圆角 26。
    /// 真机按物理挖槽逐轴等比换算（2026-09-11 验收：直搬像素值相对挖槽放大约 1.6 倍，显笨）。
    private static let protoNotch = CGSize(width: 285, height: 46)

    /// 岛体侧边呼吸边距（旧「凹角半径」，凹角方案已废弃；现仅作岛宽外扩，按挖槽宽等比）
    static func filletRadius(for notch: CGSize) -> CGFloat {
        (15 * notch.width / protoNotch.width).rounded()
    }

    /// 悬停 peek 岛尺寸（逐轴等比，基准宽 380pt 提供充裕的双模态排版余量）
    static func peekSize(for notch: CGSize) -> CGSize {
        CGSize(
            width: (380 * notch.width / protoNotch.width).rounded(),
            height: (82 * notch.height / protoNotch.height).rounded()
        )
    }

    /// peek 态底部圆角（按挖槽宽等比）
    static func peekBottomRadius(for notch: CGSize) -> CGFloat {
        (20 * notch.width / protoNotch.width).rounded()
    }

    /// 展开态底部圆角（绝对常数：对齐原型 26px 在浏览器 1:1 呈现的物理曲率。
    /// 等比换算会给 16pt、实测显方正，2026-09-11 用户验收改为绝对值）
    static let openBottomRadius: CGFloat = 26
    /// 展开态侧边呼吸边距（绝对常数，对齐原型 15px 物理尺度；凹角方案已废弃）
    static let openFilletRadius: CGFloat = 14
    /// 展开态凹角半径（= 侧翼出挑宽；长宽比保底的翼宽来源，与 NotchView 共用）
    static let openCornerRadius: CGFloat = 32
    /// 面板长宽比保底：岛体宽（内容宽 + 2×openCornerRadius）对高之比不低于此值，防「窄高条」。
    /// 任务 3 调整为 1.15，支持更紧凑的内容自适应。
    static let panelAspectFloor: CGFloat = 1.15
    /// 面板内容与岛体边缘的留白：内容不贴边界（对齐原版 600/664 的 32pt 比例，2026-09-11 用户验收要求）
    static let panelContentInset: CGFloat = 32

    /// 面板最小高度与外接屏幕/无刘海保底宽度
    static let minPanelHeight: CGFloat = 60
    static let minExternalPanelWidth: CGFloat = 160

    /// 模型列宽钳制区间
    static let modelColumnMin: CGFloat = 100
    static let modelColumnMax: CGFloat = 220

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
