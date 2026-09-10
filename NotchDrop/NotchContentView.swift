//
//  NotchContentView.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/7.
//  Last Modified by 冷月 on 2025/5/5.
//

import SwiftUI

struct NotchContentView: View {
    @StateObject var vm: NotchViewModel

    var body: some View {
        NotchRootView(vm: vm)
        .animation(vm.animation, value: vm.contentType)
        // 尺寸上报：内容自然大小驱动面板（ADR-0008），见 ZoneSizeGuard.swift
        .onPreferenceChange(ZoneNaturalSizeKey.self) { natural in
            vm.measuredNaturalSize = natural
            // 越界守卫：内容超过最大界 = 钳制将生效，内部必须可滚/可裁
            assert(
                natural.width <= NotchViewModel.maxPanelWidth + 0.5,
                "内容超宽：\(vm.contentType) 自然宽 \(natural.width) > 最大 \(NotchViewModel.maxPanelWidth)，内部必须收缩"
            )
        }
    }
}

extension AnyTransition {
    /// 分区滑动（旧项目灵感合成 + 弹开修正）：插入 24pt 方向轻推，移除 0.15s 快淡出——
    /// 移除不带行程，转场并集期压到最短，面板/窗口尺寸不弹到两页最大（systematic-debugging H1）。
    static var zoneSlideNext: AnyTransition {
        .asymmetric(
            insertion: .offset(x: 24).combined(with: .opacity),
            removal: .opacity.animation(.easeOut(duration: 0.15))
        )
    }

    static var zoneSlidePrevious: AnyTransition {
        .asymmetric(
            insertion: .offset(x: -24).combined(with: .opacity),
            removal: .opacity.animation(.easeOut(duration: 0.15))
        )
    }
}

#Preview {
    NotchContentView(vm: .init())
        .padding()
        .frame(width: 600, height: 150, alignment: .center)
        .background(.ultraThinMaterial)
}
