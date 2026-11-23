//
//  NotchRootView.swift
//  NotchDrop
//
import SwiftUI

/// 三页外壳：滑动切页 + dots + 耳区（设置走右键菜单 Popover，挂根，右上齿轮已删）。
struct NotchRootView: View {
    @StateObject var vm: NotchViewModel
    @ObservedObject private var magpie = MagpieStore.shared
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
        // Magpie 生命周期由常驻 NotchView 统一裁决（悬停/开合/清态启停），
        // NotchRootView 只读已发布快照；本视图会随面板开合挂载/卸载，不适合挂生命周期。
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
        let snapshot = MagpieStore.shared.snapshot
        switch vm.contentType {
        case .overview:
            if let text = EarSummary.overviewLeft(dimension: MagpieStore.shared.distributionDimension, snapshot: snapshot) {
                earTextPill(statusDot: StudioColor.emerald, text: text)
            }
        case .token:
            if let text = EarSummary.flowLeft(snapshot: snapshot) {
                let provider = snapshot.recentFlows.first?.providerID ?? ""
                let icon = snapshot.providerGroups.first(where: { $0.id == provider })?.icon
                HStack(spacing: 4) {
                    ProviderIconView(icon: icon, providerID: provider, size: 11)
                        .id(provider)
                    Text(text)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(StudioInk.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .monospacedDigit()
                .truncationMode(.tail)
            }
        case .providers:
            let r = EarSummary.providersLeft(snapshot: snapshot)
            earTextPill(statusDot: r.hasAlert ? StudioColor.amber : StudioColor.emerald, text: r.text)
        }
    }

    @ViewBuilder
    private var rightEarPill: some View {
        let snapshot = MagpieStore.shared.snapshot
        switch vm.contentType {
        case .overview:
            let r = EarSummary.overviewRight(snapshot: snapshot)
            if r.time != nil || r.alerts > 0 {
                HStack(spacing: 3) {
                    if let time = r.time {
                        Image(systemName: "clock")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(StudioInk.secondary)
                        Text(time)
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(StudioInk.secondary)
                    }
                    if r.alerts > 0 {
                        alertBadge(count: r.alerts)
                    }
                }
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.75)
            }
        case .token:
            let r = EarSummary.flowRight(snapshot: snapshot)
            HStack(spacing: 3) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(StudioInk.secondary)
                RollupText(text: r.requests, font: .system(size: 11, weight: .medium), color: StudioInk.secondary)
                if r.alerts > 0 {
                    alertBadge(count: r.alerts)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.75)
        case .providers:
            let r = EarSummary.providersRight(snapshot: snapshot)
            if r.checkin != nil || r.alerts > 0 {
                HStack(spacing: 3) {
                    if let checkin = r.checkin {
                        Text(checkin)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(StudioInk.secondary)
                    }
                    if r.alerts > 0 {
                        alertBadge(count: r.alerts)
                    }
                }
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.75)
            }
        }
    }

    /// 状态点 + 单行文案胶囊（P1/P3 左耳共用）。
    private func earTextPill(statusDot: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusDot)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(StudioInk.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .monospacedDigit()
        .truncationMode(.tail)
    }

    /// 黄色告警角标：可点击 Button，直跳 P3 供应商额度页。
    private func alertBadge(count: Int) -> some View {
        Button {
            vm.jumpToZone(.providers)
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(StudioColor.amber)
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(StudioColor.amber)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) 家受限，查看详情")
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
            case .overview:
                OverviewDistributionView()
            case .token:
                TokenZoneView()
                    .frame(maxWidth: .infinity, alignment: .top)
            case .providers:
                ProviderQuotaZoneView()
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .transition(reduceMotion ? .opacity : (direction == .next ? .zoneSlideNext : .zoneSlidePrevious))
    }
}
