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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch vm.contentType {
            case .normal:
                HStack(spacing: vm.spacing) {
                    QuotaCardView(vm: vm)
                        .frame(width: 196)
                    TrayView(vm: vm)
                }
                .transition(reduceMotion ? .opacity : .blurFade)
            case .menu:
                NotchMenuView(vm: vm)
                    .transition(reduceMotion ? .opacity : .blurFade)
            case .settings:
                NotchSettingsView(vm: vm)
                    .transition(reduceMotion ? .opacity : .blurFade)
            }
        }
        .animation(vm.animation, value: vm.contentType)
    }
}

/// 模糊淡入过渡：出现时 blur 6→0 + 透明度 + 轻微放大，消失时反向快退
private struct BlurFadeModifier: ViewModifier, Animatable {
    var amount: CGFloat

    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func body(content: Content) -> some View {
        content
            .opacity(1 - amount)
            .blur(radius: 6 * amount)
            .scaleEffect(1 - 0.02 * amount)
    }
}

private extension AnyTransition {
    static var blurFade: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: BlurFadeModifier(amount: 1), identity: BlurFadeModifier(amount: 0)),
            removal: .opacity
        )
    }
}

#Preview {
    NotchContentView(vm: .init())
        .padding()
        .frame(width: 600, height: 150, alignment: .center)
        .background(.ultraThinMaterial)
}
