//
//  ZoneHeightGuard.swift
//  NotchDrop
//
//  溢出守卫的测量词汇：内容自然高 preference + 挂报告器。
//  语义注意：量到的是「压缩提案下的布局回报高」——全部子视图定高时等于自然高；
//  若区内含可压缩/弹性子视图，溢出会被弹性子视图吸收而漏报（现状：设置区全定高可靠，概览区 TrayView 弹性会吸收）。
//

import SwiftUI

/// 内容高度测量 key：多分支并存时取最大值
struct ZoneNaturalHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// 挂高度报告器：把本视图被布局后的实际高度上报给祖先的 onPreferenceChange。
    /// active 为 false 时上报 0：分区切换过渡中两区短暂共存，旧区必须静默，
    /// 否则 max 合并会把旧区高度算到新区头上造成误杀（2026-09-08 实测 settings→normal 上报 195 vs 可用 106）。
    func zoneHeightReporter(active: Bool = true) -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(key: ZoneNaturalHeightKey.self, value: active ? geo.size.height : 0)
            }
        }
    }
}
