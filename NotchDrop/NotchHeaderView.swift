//
//  NotchHeaderView.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/7.
//

import SwiftUI

struct NotchHeaderView: View {
    @StateObject var vm: NotchViewModel

    var versionText: String {
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return String(format: NSLocalizedString("Version: %@ (Build: %@)", comment: ""), ver, build)
    }

    var body: some View {
        HStack {
            Text(vm.contentType == .settings ? versionText : "NotchEvery")
                .contentTransition(.numericText())
                .foregroundStyle(.primary)
            Spacer()
            PageIndicator(current: vm.contentType, onJump: { vm.jumpToZone($0) })
        }
        .animation(vm.animation, value: vm.contentType)
        .font(.system(.headline, design: .rounded))
    }
}

#Preview {
    NotchHeaderView(vm: .init())
}

/// 小圆点指示器：当前位置实心高亮，可点直跳
private struct PageIndicator: View {
    let current: NotchViewModel.ContentType
    let onJump: (NotchViewModel.ContentType) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(NotchViewModel.zoneOrder, id: \.self) { zone in
                Circle()
                    .fill(zone == current ? Color.primary : Color.secondary.opacity(0.35))
                    .frame(width: 6, height: 6)
                    .contentShape(Rectangle().inset(by: -6))
                    .onTapGesture { onJump(zone) }
            }
        }
    }
}
