//
//  NotchRootView.swift
//  NotchDrop
//
import SwiftUI

/// 两页外壳：滑动切页 + dots + 耳区（设置走右键菜单 Popover，挂根，右上齿轮已删）。
struct NotchRootView: View {
    @StateObject var vm: NotchViewModel
    @StateObject private var usage = UsageStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 中央禁放区两侧边距（ADR-0009）：禁放区总宽 = 挖槽宽 + 2×margin，只画背景
    private let deadZoneMargin: CGFloat = 8

    var body: some View {
        // 黑岛（ADR-0010）：内容透明直接坐岛上，岛体由 NotchView 的 RoundedRectangle 绘制
        VStack(spacing: 0) {
            pages
            SmoothPageIndicator(pageCount: NotchViewModel.zoneOrder.count, currentPage: Binding(
                get: { NotchViewModel.pageIndex(for: vm.contentType) },
                set: { vm.jumpToZone(NotchViewModel.zone(for: $0)) }
            ))
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
        .padding(.bottom, 4)
        // 刘海安全区垫在测量区内：测量含安全区，面板才够高（03 工单）
        .padding(.top, vm.notchSafeAreaTop)
        // 耳区贴顶叠在禁放区两侧；中央禁放区留空只画背景（ADR-0009）
        .overlay(alignment: .top) { earsRow }
        // 整体上报：含安全区+内容（dots 已收进面板内，随内容一起量）
        // 宽度不再自钉 zone 宽：那会让外壳留白失效、内容永远贴边
        // （2026-09-11 探针坐实 box=704 / zone=640 / inner=640）；改由外壳给「面板宽−留白」的提案，内容按提案填充
        .zoneSizeReporter(active: true)
        // 用量轮询随面板开合（与额度卡同节奏，收起即停）；AntigravityStore 供第二页账号昵称匹配
        .onAppear {
            UsageStore.shared.start()
            AntigravityStore.shared.start()
        }
        .onChange(of: vm.status) { status in
            if status == .closed {
                UsageStore.shared.stop()
                AntigravityStore.shared.stop()
            } else {
                UsageStore.shared.start()
                AntigravityStore.shared.start()
            }
        }
        // 收起兜底：NotchView 用 `if vm.status == .opened` 条件渲染摘掉整棵子树，
        // 视图被移除时上面的 onChange 收不到 .closed，停轮询只能靠 onDisappear。
        .onDisappear {
            UsageStore.shared.stop()
            AntigravityStore.shared.stop()
        }
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
        // 左耳：当前 cc-switch 供应商（claude-desktop 槽）；查无则整只隐藏
        if vm.contentType == .token, let provider = usage.providerName {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text(provider)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .monospacedDigit()
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.75)
        }
    }

    @ViewBuilder
    private var rightEarPill: some View {
        // 右耳：今日调用次数（图标+数字紧凑呈现，防 16 寸真机 54.5pt 耳区截断）
        if vm.contentType == .token {
            HStack(spacing: 3) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                RollupText(text: usage.summary.calls, font: .system(size: 11, weight: .medium), color: .secondary)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.75)
        }
    }

    private var pages: some View {
        ZStack(alignment: .top) {
            PageTransitionWrapper(
                contentType: vm.contentType,
                direction: vm.lastSwipeDirection,
                reduceMotion: reduceMotion,
                vm: vm
            )
            .equatable()
            .id(vm.contentType)
        }
        // 切页专用快弹簧（清单 05；裁剪已撤：与窗口边双边打架是闪的根因，窗口自带裁剪 enough）
        .animation(vm.pageAnimation, value: vm.contentType)
    }
}

/// 切页过渡包装器：将切入时的方向值固定于视图实例本身，杜绝 300ms 转场期内连扫突变重写退场动画
private struct PageTransitionWrapper: View, Equatable {
    let contentType: NotchViewModel.ContentType
    let direction: SwipeDirection
    let reduceMotion: Bool
    @ObservedObject var vm: NotchViewModel

    static func == (lhs: PageTransitionWrapper, rhs: PageTransitionWrapper) -> Bool {
        lhs.contentType == rhs.contentType && lhs.direction == rhs.direction
    }

    var body: some View {
        Group {
            switch contentType {
            case .normal:
                OverviewPageView(vm: vm)
            case .token:
                TokenZoneView()
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .transition(reduceMotion ? .opacity : (direction == .next ? .zoneSlideNext : .zoneSlidePrevious))
    }
}
