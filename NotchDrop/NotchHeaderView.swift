//
//  NotchHeaderView.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/7.
//

import SwiftUI

struct NotchHeaderView: View {
    @StateObject var vm: NotchViewModel
    // 胶囊滑块的命名空间，选中项背景在此空间内做转场
    @Namespace private var tabSlider

    var versionText: String {
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return String(format: NSLocalizedString("Version: %@ (Build: %@)", comment: ""), ver, build)
    }

    // 单个胶囊按钮：选中项显示高亮胶囊背景并参与滑块动画
    private func tabButton(_ tab: NotchViewModel.PanelTab, title: String) -> some View {
        Button {
            // 点击切换面板 Tab，动画与全局保持一致
            withAnimation(vm.animation) { vm.activeTab = tab }
        } label: {
            Text(title)
                // 选中项主色、未选中次色，区分层级
                .foregroundStyle(vm.activeTab == tab ? .primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background {
                    if vm.activeTab == tab {
                        Capsule()
                            .fill(.white.opacity(0.14))
                            .matchedGeometryEffect(id: "panelTab", in: tabSlider)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        HStack {
            if vm.contentType == .normal {
                // 正常态左端双胶囊分段：状态 / 托盘
                HStack(spacing: 2) {
                    tabButton(.status, title: "状态")
                    tabButton(.tray, title: "托盘")
                }
                .padding(2)
                .background(Capsule().fill(.white.opacity(0.08)))
            } else {
                // 非正常态保持原标题展示不动
                Text(vm.contentType == .settings ? versionText : "NotchEvery")
                    .contentTransition(.numericText())
                    .foregroundStyle(.primary)
            }
            Spacer()
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
        }
        .animation(vm.animation, value: vm.contentType)
        .font(.system(.headline, design: .rounded))
    }
}

#Preview {
    NotchHeaderView(vm: .init())
}
