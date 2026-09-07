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
                .onAppear { Probe.log("appear normal") }
                .onDisappear { Probe.log("disappear normal") }
            case .settings:
                VStack(spacing: vm.spacing) {
                    NotchMenuView(vm: vm)
                    Divider()
                    NotchSettingsView(vm: vm)
                }
                .transition(reduceMotion ? .opacity : .blurFade)
                .onAppear { Probe.log("appear settings") }
                .onDisappear { Probe.log("disappear settings") }
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
            removal: .opacity.animation(.easeOut(duration: 0.18))
        )
    }
}

/// 探针：过渡诊断专用，定案后删除
enum Probe {
    static func log(_ msg: String) {
        let line = "\(Date().timeIntervalSince1970) \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: "/tmp/notch-transitions.log")
        if FileManager.default.fileExists(atPath: url.path) {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            try? handle.seekToEnd()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

#Preview {
    NotchContentView(vm: .init())
        .padding()
        .frame(width: 600, height: 150, alignment: .center)
        .background(.ultraThinMaterial)
}
