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
        ZStack(alignment: .topLeading) {
            switch vm.contentType {
            case .normal:
                HStack(spacing: vm.spacing) {
                    QuotaCardView(vm: vm)
                        .frame(width: 196)
                    Divider()
                    TrayView(vm: vm)
                }
                .zoneHeightReporter(active: vm.contentType == .normal)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .transition(reduceMotion ? .opacity : .blurFade)
            case .settings:
                VStack(alignment: .leading, spacing: 8) {
                    NotchMenuView(vm: vm)
                    NotchSettingsView(vm: vm)
                    Text("NotchEvery \(appVersion)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                .zoneHeightReporter(active: vm.contentType == .settings)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .transition(reduceMotion ? .opacity : .blurFade)
            }
        }
        .animation(vm.animation, value: vm.contentType)
        .onPreferenceChange(ZoneNaturalHeightKey.self) { natural in
            // 溢出守卫：内容回报高超过内容区槽位 = 高度表与内容脱节，选项卡会被挤动
            // 语义边界见 ZoneHeightGuard.swift（弹性子视图会吸收溢出导致漏报）
            assert(
                natural <= vm.zoneContentHeight + 0.5,
                "高度表与内容脱节：\(vm.contentType) 内容回报高 \(natural) > 可用 \(vm.zoneContentHeight)，请更新 zonePanelHeight 或收缩内容"
            )
        }
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
            removal: .opacity.animation(.easeOut(duration: 0.18))
        )
    }
}

#Preview {
    NotchContentView(vm: .init())
        .padding()
        .frame(width: 600, height: 150, alignment: .center)
        .background(.ultraThinMaterial)
}
