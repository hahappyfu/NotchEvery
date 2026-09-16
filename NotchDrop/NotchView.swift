//
//  NotchView.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/7.
//

import SwiftUI

struct NotchView: View {
    @StateObject var vm: NotchViewModel
    @StateObject private var usage = UsageStore.shared
    @StateObject private var guardStore = GuardStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State var dropTargeting: Bool = false
    @State private var swipeResolver = ScrollSwipeResolver()

    /// 岛体尺寸：闲置=物理刘海同形；悬停=peek；展开=内容测量值；popping=微胀
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
        case .popping:
            return CGSize(width: vm.deviceNotchRect.width, height: vm.deviceNotchRect.height + 4)
        }
    }

    /// 岛体侧边呼吸边距（旧称「凹角半径」；凹角方案已废弃，此值现仅作岛宽外扩与内容留白，见 ADR-0010 修订）
    var islandFillet: CGFloat {
        let isGhost = vm.hoverGhosting || vm.ghostFading
        switch vm.status {
        case .closed: return isGhost ? IslandMetrics.filletRadius(for: vm.deviceNotchRect.size) : 0
        case .opened: return IslandMetrics.openFilletRadius
        case .popping: return 0
        }
    }

    /// 底部圆角：随状态变化（原型 12 / 20 / 26）
    var islandBottomRadius: CGFloat {
        let isGhost = vm.hoverGhosting || vm.ghostFading
        switch vm.status {
        case .closed: return isGhost ? IslandMetrics.peekBottomRadius(for: vm.deviceNotchRect.size) : 12
        case .opened: return IslandMetrics.openBottomRadius
        case .popping: return 10
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
                            .modifier(StaggeredEntry(delay: 0.06))
                    }
                    .onAppear { notchTimingMark("contentAppear") }
                    .padding(.horizontal, IslandMetrics.panelContentInset)
                    .padding(.bottom, IslandMetrics.panelContentInset)
                    // 顶部收紧 20→12：安全区之上已垫刘海避让，内层不再 double（02 票）
                    .padding(.top, 12)
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
                guard !dropTargeting else { return }
                guard let direction = swipeResolver.feed(
                    deltaX: delta.deltaX,
                    hasMomentum: delta.hasMomentum,
                    now: delta.timestamp
                ) else { return }
                if direction == .next {
                    vm.nextZone()
                } else {
                    vm.previousZone()
                }
                vm.markSwipeHintSeen()
            }
            .onReceive(vm.events.arrowKey) { _ in
                guard vm.status == .opened else { return }
                guard NSApp.keyWindow is NotchWindow else { return }
                guard vm.notchOpenedRect.contains(NSEvent.mouseLocation) else { return }
                guard !dropTargeting else { return }
                vm.markSwipeHintSeen()
            }
            // 入场：从顶部锚点放大淡入（旧实现叠了 offset(-h/2)，内容从上方 191pt 处滑入，
            // 视觉上「顶部探过头、没吸住屏顶」，2026-09-11 用户反馈后撤掉）
            .transition(
                .scale(scale: 0.92, anchor: .top).combined(with: .opacity)
            )
        }
        .background(dragDetector)
        // 右键菜单挂根层级：外壳带 .disabled(true) 会把菜单按钮全置灰，根层级无禁用
        .contextMenu {
            Button(LocalizedStringKey("Settings")) {
                vm.openFromGhost()
                vm.showSettings = true
            }
            Divider()
            Button(LocalizedStringKey("Exit")) {
                NSApp.terminate(nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // 窗口压过菜单栏，安全区会把内容顶下去导致顶部留缝，直接无视（纯自绘 chrome，无系统控件要避让）
        .ignoresSafeArea()
    }

    var island: some View {
        // 正向平滑连续贝塞尔曲线岛体背景，天然纯黑填充消灭边缘半透明白边
        // 帧尺寸瞬时变更、不叠动画：SwiftUI 帧动画按中心锚定（顶边甩出屏顶），
        // 且帧理想尺寸若超窗口会触发宿主垂直居中。形变动画由 notchBackground 内部承担。
        return notchBackground
            // frame 瞬时跳终值：所有形变动画由内部 islandSize 驱动，外层不再追弹簧
            .frame(width: islandSize.width + islandCornerRadius * 2, height: islandSize.height)
            .opacity(vm.status == .closed && !vm.hoverGhosting && !vm.ghostFading ? 0.3 : 1)
            .overlay(alignment: .bottom) {
                if (vm.hoverGhosting || vm.ghostFading), usage.summary != TokenSummary.empty {
                    peekHint
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }
            }
    }

    /// 岛体圆角（照抄原版数值：收起 8 / popping 10 / 展开 32；虚影态取 peek 底圆角）
    var islandCornerRadius: CGFloat {
        let isGhost = vm.hoverGhosting || vm.ghostFading
        switch vm.status {
        case .closed: return isGhost ? IslandMetrics.peekBottomRadius(for: vm.deviceNotchRect.size) : 8
        case .opened: return IslandMetrics.openCornerRadius
        case .popping: return 10
        }
    }

    /// 顶部凹角融合深度（"拉长"旋钮）：出挑的 2 倍——比正圆弧更长更丝滑的过渡
    var islandFilletBlend: CGFloat { islandCornerRadius * 2 }

    /// 正向平滑贝塞尔形状岛体背景，消灭原 destinationOut 反向挖切遮罩与边缘白边
    var notchBackground: some View {
        SmoothNotchShape(
            cornerRadius: islandCornerRadius,
            filletBlend: islandFilletBlend,
            bottomRadius: islandBottomRadius,
            isExpanded: vm.status == .opened
        )
        .fill(.black)
        .frame(width: islandSize.width + islandCornerRadius * 2, height: islandSize.height)
        // 背景在外框内顶部对齐：黑体永远从屏顶向下生长（外框恒定，不参与动画）
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // 弹簧驱动内部 islandSize 变形：过渡期（开/关/切页）才动画，稳态锁定
        .animation(reduceMotion ? nil : (vm.transitionActive ? (vm.status == .opened ? vm.openAnimation : vm.closeAnimation) : nil), value: islandSize)
    }

    /// 悬停 peek 提示：双模态胶囊（左侧 Antigravity 代理今日看板，右侧近场守护安全感知）
    private var peekHint: some View {
        HStack(spacing: 7) {
            // 左区：Antigravity 代理今日看板
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("今日 \(formattedTokensText) · \(formattedCallsText)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.90))
                    .monospacedDigit()
                    .fixedSize()
            }

            // 中区：弱分隔
            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 1, height: 10)

            // 右区：近场守护安全感知
            Text(guardStatusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.90))
                .fixedSize()
        }
        .padding(.horizontal, 4)
    }

    private var formattedTokensText: String {
        let clean = usage.summary.totalTokens.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        if let count = Int(clean) {
            return TokenFormatUtils.formatCompactTokens(count)
        }
        if clean.hasSuffix("K") || clean.hasSuffix("k") || clean.hasSuffix("M") || clean.hasSuffix("B") {
            return clean
        }
        return usage.summary.totalTokens
    }

    private var formattedCallsText: String {
        let clean = usage.summary.calls.replacingOccurrences(of: "次", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        if let count = Int(clean) {
            return "\(TokenFormatUtils.formatCount(count)) 次"
        }
        if !usage.summary.calls.isEmpty {
            return "\(clean) 次"
        }
        return "0 次"
    }

    private var guardStatusText: String {
        switch guardStore.guardState {
        case .disabled:
            return "⏸️ 已停用"
        case .observing:
            return "🛡️ 空跑"
        case .guarding:
            if let rssi = guardStore.rssi {
                return "⌚️ \(rssi) dBm · 安全"
            } else {
                return "⌚️ 搜寻中..."
            }
        }
    }

    @ViewBuilder
    var dragDetector: some View {
        RoundedRectangle(cornerRadius: islandBottomRadius)
            .foregroundStyle(Color.black.opacity(0.001)) // 近乎透明的命中区：SwiftUI 最小可用不透明度
            .contentShape(Rectangle())
            .frame(width: islandSize.width + vm.dropDetectorRange, height: islandSize.height + vm.dropDetectorRange)
            .onDrop(of: [.data], isTargeted: $dropTargeting) { _ in true }
            .onChange(of: dropTargeting) { isTargeted in
                if isTargeted, vm.status == .closed {
                    // Open the notch when a file is dragged over it
                    vm.notchOpen(.drag)
                    vm.hapticSender.send()
                } else if !isTargeted {
                    // Close the notch when the dragged item leaves the area
                    let mouseLocation: NSPoint = NSEvent.mouseLocation
                    if !vm.notchOpenedRect.insetBy(dx: vm.inset, dy: vm.inset).contains(mouseLocation) {
                        vm.notchClose()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// 分批入场修饰符：延迟后 opacity 0→1 + 下移入场；reduceMotion 直接显示
/// （blur 已踢出动画：离屏重渲染逐帧掉帧是卡顿感来源；NOTCH_TIMING 证实同步链路 ≤70ms）
struct StaggeredEntry: ViewModifier {    let delay: TimeInterval
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : -6)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.2).delay(delay)) {
                    shown = true
                }
            }
    }
}

