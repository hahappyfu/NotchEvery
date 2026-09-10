//
//  NotchRootView.swift
//  NotchDrop
//
import SwiftUI

/// 双页外壳：滑动切页 + dots + 耳区（设置走右键菜单 Popover，挂根，右上齿轮已删）。
struct NotchRootView: View {
    @StateObject var vm: NotchViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 中央禁放区两侧边距（ADR-0009）：禁放区总宽 = 挖槽宽 + 2×margin，只画背景
    private let deadZoneMargin: CGFloat = 8

    var body: some View {
        VStack(spacing: 10) {
            pages
            SmoothPageIndicator(pageCount: 2, currentPage: Binding(
                get: { NotchViewModel.pageIndex(for: vm.contentType) },
                set: { vm.jumpToZone(NotchViewModel.zone(for: $0)) }
            ))
        }
        // 刘海安全区垫在测量区内：测量含安全区，面板才够高（03 工单）
        .padding(.top, vm.notchSafeAreaTop)
        // 耳区贴顶叠在禁放区两侧；中央禁放区留空只画背景（ADR-0009）
        .overlay(alignment: .top) { earsRow }
        // 设置挂根：入口走右键菜单 Settings，右上齿轮已删（ADR-0009）
        .popover(isPresented: $vm.showSettings, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 8) {
                NotchMenuView(vm: vm)
                NotchSettingsView(vm: vm)
                Text("NotchEvery \(appVersion)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(minWidth: 360)
        }
        // 整体上报：含安全区+内容+dots，dots 预留魔法数不再需要
        .zoneSizeReporter(active: true)
        .frame(width: vm.zoneOpenedSize.width)
    }

    private var earsRow: some View {
        HStack(spacing: 0) {
            earItem(text: leftEarText, alignment: .leading)
            Color.clear
                .frame(width: vm.deviceNotchRect.width + deadZoneMargin * 2)
            earItem(text: rightEarText, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, maxHeight: vm.notchSafeAreaTop, alignment: .top)
    }

    /// 单耳：单行内容、超长截断；内容 nil 页只画背景仍占位（跨页等高，切页顶部不跳）
    private func earItem(text: String?, alignment: HorizontalAlignment) -> some View {
        Text(text ?? "")
            .font(.system(size: 11, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, maxHeight: vm.notchSafeAreaTop, alignment: Alignment(horizontal: alignment, vertical: .center))
    }

    private var leftEarText: String? {
        switch vm.contentType {
        case .normal: return nil
        case .token: return "\(TokenSummary.mock.totalTokens) · \(TokenSummary.mock.cacheRate)"
        }
    }

    private var rightEarText: String? {
        switch vm.contentType {
        case .normal: return nil
        case .token: return TokenSummary.mock.calls
        }
    }

    private var pages: some View {
        ZStack(alignment: .topLeading) {
            switch vm.contentType {
            case .normal:
                OverviewPageView(vm: vm)
                    // 量理想宽：maxWidth 填充会让测量值永远等于容器宽、宽度锁死，
                    // 水平 fixedSize 让面板宽度收敛到内容（垂直保持 flexible）
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(reduceMotion ? .opacity : (vm.lastSwipeDirection == .next ? .zoneSlideNext : .zoneSlidePrevious))
            case .token:
                TokenZoneView()
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(reduceMotion ? .opacity : (vm.lastSwipeDirection == .next ? .zoneSlideNext : .zoneSlidePrevious))
            }
        }
        // 切页专用快弹簧（清单 05；裁剪已撤：与窗口边双边打架是闪的根因，窗口自带裁剪 enough）
        .animation(vm.pageAnimation, value: vm.contentType)
    }
}
