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
        ZStack {
            switch vm.contentType {
            case .normal:
                HStack(spacing: vm.spacing) {
                    QuotaCardView(vm: vm)
                        .frame(width: 196)
                    TrayView(vm: vm)
                }
                .transition(slideTransition)
            case .menu:
                NotchMenuView(vm: vm)
                    .transition(slideTransition)
            case .settings:
                NotchSettingsView(vm: vm)
                    .transition(slideTransition)
            }
        }
        .animation(vm.animation, value: vm.contentType)
    }

    /// 下一区从右侧滑入，上一区从左侧滑入，淡入淡出叠加
    private var slideTransition: AnyTransition {
        if vm.lastSwipeDirection == .next {
            .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        } else {
            .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }
}

#Preview {
    NotchContentView(vm: .init())
        .padding()
        .frame(width: 600, height: 150, alignment: .center)
        .background(.ultraThinMaterial)
}
