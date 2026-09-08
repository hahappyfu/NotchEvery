//
//  NotchRootView.swift
//  NotchDrop
//
import SwiftUI

/// 520 双页外壳：滑动切页 + dots + 右上齿轮（设置 Popover 在任务 6 接）。
struct NotchRootView: View {
    @StateObject var vm: NotchViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                pages
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .padding(6)
            }
            iOSPageIndicator(count: 2, current: NotchViewModel.pageIndex(for: vm.contentType)) {
                vm.jumpToZone(NotchViewModel.zone(for: $0))
            }
        }
        .frame(width: NotchViewModel.zonePanelWidth)
    }

    private var pages: some View {
        ZStack(alignment: .topLeading) {
            switch vm.contentType {
            case .normal:
                OverviewPageView(vm: vm)
                    .zoneHeightReporter(active: vm.contentType == .normal)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(reduceMotion ? .opacity : .blurFade)
            case .token:
                TokenZoneView()
                    .zoneHeightReporter(active: vm.contentType == .token)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(reduceMotion ? .opacity : .blurFade)
            case .settings:
                Color.clear
            }
        }
        .animation(vm.animation, value: vm.contentType)
    }
}

struct OverviewPageView: View {
    @StateObject var vm: NotchViewModel
    var body: some View { Color.clear }
}
