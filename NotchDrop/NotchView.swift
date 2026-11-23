//
//  NotchView.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/7.
//

import SwiftUI

struct NotchView: View {
    @StateObject var vm: NotchViewModel
    @ObservedObject private var magpie = MagpieStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var swipeResolver = ScrollSwipeResolver()

    /// 岛体尺寸：闲置=物理刘海同形；悬停=peek；展开=内容测量值
    var islandSize: CGSize {
        let isGhost = vm.hoverGhosting || vm.ghostFading
        switch vm.status {
        case .closed:
            if isGhost { return IslandMetrics.peekSize(for: vm.deviceNotchRect.size) }
            return CGSize(
                width: max(vm.deviceNotchRect.width - 4, 0),
                height: max(vm.deviceNotchRect.height - 4, 0)
            )
        case .opened:
            return vm.zoneOpenedSize
        }
    }

    /// 底部圆角：随状态变化（原型 12 / 20 / 26）
    var islandBottomRadius: CGFloat {
        let isGhost = vm.hoverGhosting || vm.ghostFading
        switch vm.status {
        case .closed: return isGhost ? IslandMetrics.peekBottomRadius(for: vm.deviceNotchRect.size) : 12
        case .opened: return IslandMetrics.openBottomRadius
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            island
                .zIndex(0)
                .disabled(true)
            Group {
                if vm.status == .opened {
                    // 内容自适应（ADR-0008）：内容自然高，不锁死、不裁剪
                    VStack(spacing: vm.spacing) {
                        // 不给 maxWidth 填充：内容自然宽要能向上传播成面板测量值，
                        // 撑满会让测量跟随上页面板宽 → 来回切页后卡大不缩（2026-09-11 探针实锤 box=605 / inner=388）
                        NotchContentView(vm: vm)
                            .transition(
                                .scale(scale: 0.94, anchor: .top).combined(with: .opacity)
                            )
                    }
                    .onAppear { notchTimingMark("contentAppear") }
                    .padding(.horizontal, IslandMetrics.panelContentInset)
                    // 底部收紧 32→14：消除内层与外壳留白叠加导致的下巴大面积空黑
                    .padding(.bottom, 14)
                    // 顶部避让已由 NotchRootView 按 notchSafeAreaTop 垫齐，外层不再 double（I3）
                    // 面板尺寸 = 内容 + 外壳留白（否则边距被当作挤压余量，内容贴边）
                    .zoneSizeReporter(active: true)
                    .onPreferenceChange(ZoneNaturalSizeKey.self) { [weak vm] size in
                        // 面板尺寸 = 内容 + 外壳留白（不留的话边距被内容吃穿，贴边/裁切）
                        vm?.measuredNaturalSize = size
                    }
                    .frame(width: vm.zoneOpenedSize.width, alignment: .top)
                    .overlay(alignment: .bottom) {
                        if !vm.hasSeenSwipeHint {
                            Text("SwipeHint")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .transition(.opacity)
                                .task {
                                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                                    // 面板提前收起时本 .task 被取消，sleep 抛 CancellationError 被 try? 吞掉——
                                    // 不查 isCancelled 的话，用户只开了半秒就收起也会被永久标记「提示已看过」。
                                    guard !Task.isCancelled else { return }
                                    vm.markSwipeHintSeen()
                                }
                        }
                    }
                    .zIndex(1)
                }
            }
            .allowsHitTesting(vm.status == .opened && !vm.hoverGhosting)
            .onReceive(vm.events.scrollDelta) { delta in
                // 三重守卫：展开态、鼠标在面板内、未拖文件
                guard vm.status == .opened else { return }
                guard vm.notchOpenedRect.contains(NSEvent.mouseLocation) else { return }

                guard let direction = swipeResolver.feed(
                    deltaX: delta.deltaX,
                    deltaY: delta.deltaY,
                    hasMomentum: delta.hasMomentum,
                    now: delta.timestamp
                ) else { return }

                // 触发切页沉稳挡位咬合感
                GearHapticFeedback.shared.triggerPageDetent()

                if direction == .next {
                    vm.nextZone()
                } else {
                    vm.previousZone()
                }
                vm.markSwipeHintSeen()
            }
            .onReceive(vm.events.arrowKey) { direction in
                guard vm.status == .opened else { return }
                guard NSApp.keyWindow is NotchWindow else { return }
                guard vm.notchOpenedRect.contains(NSEvent.mouseLocation) else { return }
                GearHapticFeedback.shared.triggerPageDetent()
                vm.handleArrowKey(direction)
            }
            // 入场：从顶部锚点放大淡入（旧实现叠了 offset(-h/2)，内容从上方 191pt 处滑入，
            // 视觉上「顶部探过头、没吸住屏顶」，2026-09-11 用户反馈后撤掉）
            .transition(
                .scale(scale: 0.92, anchor: .top).combined(with: .opacity)
            )
        }
        // 右键菜单挂根层级：外壳带 .disabled(true) 会把菜单按钮全置灰，根层级无禁用
        .contextMenu {
            Button(LocalizedStringKey("Settings")) {
                vm.notchClose()
                PreferencesWindowController.shared.show()
            }
            Button("打开 Magpie") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/magpie.app"))
            }
            Divider()
            Button(LocalizedStringKey("Exit")) {
                NSApp.terminate(nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // 窗口压过菜单栏，安全区会把内容顶下去导致顶部留缝，直接无视（纯自绘 chrome，无系统控件要避让）
        .ignoresSafeArea()
        // Magpie 生命周期统一裁决（常驻视图）：开合/悬停/虚影清态变化时启停。
        // 悬停即 start()（幂等、立即 refresh），1.5s Timer 提供去抖刷新，满足「悬停立即追平」。
        .onAppear { syncMagpieLifecycle() }
        .onChange(of: vm.status) { _ in syncMagpieLifecycle() }
        .onChange(of: vm.hoverGhosting) { _ in syncMagpieLifecycle() }
        .onChange(of: vm.ghostFading) { _ in syncMagpieLifecycle() }
    }

    private func syncMagpieLifecycle() {
        if MagpieStore.shouldRun(status: vm.status, hoverGhosting: vm.hoverGhosting, ghostFading: vm.ghostFading) {
            MagpieStore.shared.start()
        } else {
            MagpieStore.shared.stop()
        }
    }

    var island: some View {
        // 正向平滑连续贝塞尔曲线岛体背景，天然纯黑填充消灭边缘半透明白边
        // 帧尺寸瞬时变更、不叠动画：SwiftUI 帧动画按中心锚定（顶边甩出屏顶），
        // 且帧理想尺寸若超窗口会触发宿主垂直居中。形变动画由 notchBackground 内部承担。
        return notchBackground
            // frame 瞬时跳终值：所有形变动画由内部 islandSize 驱动，外层不再追弹簧
            .frame(width: islandSize.width + islandCornerRadius * 2, height: islandSize.height)
            .overlay(alignment: .bottom) {
                if vm.hoverGhosting || vm.ghostFading {
                    peekHint
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }
            }
    }

    /// 岛体圆角（照抄原版数值：收起 8 / 展开 32；虚影态取 peek 底圆角）
    var islandCornerRadius: CGFloat {
        let isGhost = vm.hoverGhosting || vm.ghostFading
        switch vm.status {
        case .closed: return isGhost ? IslandMetrics.peekBottomRadius(for: vm.deviceNotchRect.size) : 8
        case .opened: return IslandMetrics.openCornerRadius
        }
    }

    /// 顶部凹角融合深度（"拉长"旋钮）：出挑的 2 倍——比正圆弧更长更丝滑的过渡
    var islandFilletBlend: CGFloat { islandCornerRadius * 2 }

    /// 正向平滑贝塞尔形状岛体背景，消灭原 destinationOut 反向挖切遮罩与边缘白边
    var notchBackground: some View {
        let isOpening = vm.status == .opened || vm.hoverGhosting
        return SmoothNotchShape(
            cornerRadius: islandCornerRadius,
            filletBlend: islandFilletBlend,
            bottomRadius: islandBottomRadius,
            isExpanded: vm.status == .opened
        )
        .fill(.black)
        .frame(width: islandSize.width + islandCornerRadius * 2, height: islandSize.height)
        // 背景在外框内顶部对齐：黑体永远从屏顶向下生长（外框恒定，不参与动画）
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // 弹簧驱动内部 islandSize 变形：过渡期（开/关/切页/预展开）才动画，稳态锁定
        .animation(reduceMotion ? nil : (vm.transitionActive ? (isOpening ? vm.openAnimation : vm.closeAnimation) : nil), value: islandSize)
    }

    /// 悬停 peek 提示：双模态胶囊（左侧状态点+身份，右侧今日净 Token 与缓存命中率）
    private var peekHint: some View {
        HStack(spacing: 8) {
            // 左区：状态点 + 最近提供商 · 模型短名
            HStack(spacing: 5) {
                Circle()
                    .fill(peekStatusColor)
                    .frame(width: 4.5, height: 4.5)
                Text(peekLeftText)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 4, style: .continuous))

            // 中区：极细半透明分割线（仅数据态显示）
            if peekHasData {
                Rectangle()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 1, height: 9)

                // 右区：今日净 Token 与缓存命中率（纯净排版，等宽数字；空态整块隐藏）
                HStack(spacing: 5) {
                    Text(TokenFormatUtils.formatCompactTokens(magpie.snapshot.todayNetTokens))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.92))

                    if let rate = magpie.snapshot.todayCacheRate {
                        Text("·")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.35))
                        Text(String(format: "%.1f%%", rate * 100))
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(StudioColor.cyan)
                    }

                    if magpie.snapshot.activeAlertCount > 0 {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(StudioColor.amber)
                        Text("\(magpie.snapshot.activeAlertCount)")
                            .font(.system(size: 10, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(StudioColor.amber)
                    }
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 6)
        .frame(maxWidth: islandSize.width - 8, alignment: .center)
    }

    /// Peek 数据态：有 Magpie 目录且今日已有请求（非空态文案时显示右侧数字块）。
    private var peekHasData: Bool {
        let s = magpie.snapshot
        return s.hasMagpieDirectory && s.todayRequestCount > 0
    }

    /// Peek 左区状态点：活跃告警 → 琥珀，否则翠绿。
    private var peekStatusColor: Color {
        magpie.snapshot.activeAlertCount > 0 ? StudioColor.amber : StudioColor.emerald
    }

    /// Peek 左区文案：空态归因，否则「最近提供商 · 模型短名」。
    private var peekLeftText: String {
        let snapshot = magpie.snapshot
        if !snapshot.hasMagpieDirectory {
            return "等待 Magpie 数据"
        }
        if snapshot.todayRequestCount == 0 {
            return "Magpie 就绪 · 今日 0 请求"
        }
        guard let first = snapshot.recentFlows.first else {
            return "Magpie 就绪"
        }
        let model = TokenFormatUtils.friendlyModelName(first.model)
        if model.isEmpty {
            return first.providerName
        }
        return "\(first.providerName) · \(model)"
    }
}
