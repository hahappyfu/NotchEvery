//
//  ZoneSizeGuard.swift
//  NotchDrop
//
//  内容自适应的测量词汇：内容自然尺寸 preference + 挂报告器（ADR-0008）。
//  语义注意：量到的是「压缩提案下的布局回报尺寸」——全部子视图定尺寸时等于自然尺寸；
//  若区内含可压缩/弹性子视图，溢出会被弹性子视图吸收而漏报。
//

import SwiftUI

/// 内容尺寸测量 key：多分支并存时每维取最大值
struct ZoneNaturalSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(width: max(value.width, next.width), height: max(value.height, next.height))
    }
}

extension View {

    /// 挂尺寸报告器：上报本视图被布局后的实际宽高；active 为 false 时上报零（静默语义同高度报告器）。
    func zoneSizeReporter(active: Bool = true) -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(key: ZoneNaturalSizeKey.self, value: active ? geo.size : .zero)
            }
        }
    }
}
