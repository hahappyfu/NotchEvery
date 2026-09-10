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
        // dots 已收进面板内容区（NotchView 内），外层只剩 pages
        pages
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
        // 整体上报：含安全区+内容（dots 已收进面板内，随内容一起量）
        .zoneSizeReporter(active: true)
        .frame(width: vm.zoneOpenedSize.width)
    }

    private var earsRow: some View {
        HStack(spacing: 0) {
            // 左耳：靠右对齐 → 右缘贴死区左缘（外侧自然留白）
            leftEarPill
                .frame(maxWidth: .infinity, alignment: .trailing)
            // 中央禁放区：挖槽宽 + 双侧 margin，只画背景（ADR-0009）；
            // 高度写死：Color 是弹性视图，不锁高会把整行撑成面板高（掉到第二行即此因）
            Color.clear
                .frame(width: vm.deviceNotchRect.width + deadZoneMargin * 2, height: vm.notchSafeAreaTop)
            // 右耳：靠左对齐 → 左缘贴死区右缘（外侧自然留白）
            rightEarPill
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: vm.notchSafeAreaTop, alignment: .center)
    }

    @ViewBuilder
    private var leftEarPill: some View {
        if vm.contentType == .token {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text(TokenRequest.mock.first?.model ?? "opus-5")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Token")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.white.opacity(0.10), in: Capsule())
            }
            .monospacedDigit()
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.8)
        }
    }

    @ViewBuilder
    private var rightEarPill: some View {
        if vm.contentType == .token {
            Text("实时调用流")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
