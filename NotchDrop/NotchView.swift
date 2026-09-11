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
        .animation(reduceMotion ? nil : (vm.status == .opened ? vm.openAnimation : vm.closeAnimation), value: vm.status)
        // 背景跟随切页尺寸：瞬变贴顶。窗口已一步到位锁顶，背景若再用 spring 会相对窗口
        // "从上往下慢慢铺开"，用户感知为"最上层滑下来"；顶部恒贴顶，不回弹不脱开。
        // 页面内容转场由 NotchRootView 内层 pageAnimation 独立驱动。
        .animation(nil, value: vm.contentType)
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
        // 原型：照抄原版 NotchDrop 外形——凹角遮罩组合逐字移植自原版 notchBackgroundMaskGroup。
        // 2026-09-11 离屏渲染实测：凹角在本机 macOS 26 SDK 正常渲染，旧「凹角全线失效」结论作废。
        // 帧尺寸瞬时变更、不叠动画：SwiftUI 帧动画按中心锚定（顶边甩出屏顶），
        // 且帧理想尺寸若超窗口会触发宿主垂直居中（历史坑）。形变动画由遮罩 body 内部承担。
        return Rectangle()
            .foregroundStyle(.black)
            .mask(notchBackgroundMaskGroup)
            // frame 瞬时跳终值：所有形变动画由遮罩内部 islandSize 驱动，外层不再追弹簧
            .frame(width: islandSize.width + islandCornerRadius * 2, height: islandSize.height)
            .opacity(vm.status == .closed && !vm.hoverGhosting && !vm.ghostFading ? 0.3 : 1)
            .overlay(alignment: .bottom) {
                if (vm.hoverGhosting || vm.ghostFading), usage.summary != TokenSummary.empty {
                    peekHint
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }
            }
            .overlay {
                if vm.bridgeSpinning {
                    SpinnerView(size: 16, color: .white)
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

    /// 原版凹角遮罩结构（destinationOut 挖角），切角由圆改为**拉长椭圆**：出挑不变、融合更深更丝滑
    var notchBackgroundMaskGroup: some View {
        let r = islandCornerRadius
        let blend = islandFilletBlend
        let spacing = vm.spacing
        let cutSide = blend + spacing
        return Rectangle()
            .foregroundStyle(.black)
            .frame(width: islandSize.width, height: islandSize.height)
            .clipShape(.rect(bottomLeadingRadius: r, bottomTrailingRadius: r))
            .overlay {
                ZStack(alignment: .topTrailing) {
                    Rectangle()
                        .frame(width: r, height: blend)
                        .foregroundStyle(.black)
                    EllipticalCornerCut(rx: r, ry: blend, trailing: true)
                        .foregroundStyle(.white)
                        .frame(width: cutSide, height: cutSide)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: -cutSide + 0.5, y: -0.5)
            }
            .overlay {
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .frame(width: r, height: blend)
                        .foregroundStyle(.black)
                    EllipticalCornerCut(rx: r, ry: blend, trailing: false)
                        .foregroundStyle(.white)
                        .frame(width: cutSide, height: cutSide)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: cutSide - 0.5, y: -0.5)
            }
            // 遮罩 body 在外框内顶部对齐：黑体永远从屏顶向下生长（外框恒定，不参与动画）
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // 弹簧驱动遮罩内部 islandSize 变形：过渡期（开/关/切页）才动画，稳态锁定
            .animation(reduceMotion ? nil : (vm.transitionActive ? (vm.status == .opened ? vm.openAnimation : vm.closeAnimation) : nil), value: islandSize)
    }

    /// 悬停 peek 提示：今日用量一行小字（真数据）
    private var peekHint: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color.green)
                .frame(width: 7, height: 7)
            Text("\(usage.summary.totalTokens) · \(usage.summary.cacheRate)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.62))
                .monospacedDigit()
                .lineLimit(1)
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

/// 右上/左上角为椭圆弧的方形切割：凹角遮罩的 destinationOut 切刀（ry > rx 即为"拉长"的融合弧）
struct EllipticalCornerCut: Shape {
    var rx: CGFloat
    var ry: CGFloat
    var trailing: Bool

    func path(in rect: CGRect) -> Path {
        let k: CGFloat = 0.5522847498
        var p = Path()
        if trailing {
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - rx, y: rect.minY))
            p.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + ry),
                control1: CGPoint(x: rect.maxX - rx + rx * k, y: rect.minY),
                control2: CGPoint(x: rect.maxX, y: rect.minY + ry - ry * k)
            )
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX + rx, y: rect.minY))
            p.addCurve(
                to: CGPoint(x: rect.minX, y: rect.minY + ry),
                control1: CGPoint(x: rect.minX + rx - rx * k, y: rect.minY),
                control2: CGPoint(x: rect.minX, y: rect.minY + ry - ry * k)
            )
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}
