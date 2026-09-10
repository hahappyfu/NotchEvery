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

    /// 顶部凹角半径：闲置与 popping 为 0（与刘海同形），悬停/展开出现
    var islandFillet: CGFloat {
        let isGhost = vm.hoverGhosting || vm.ghostFading
        switch vm.status {
        case .closed: return isGhost ? IslandMetrics.filletRadius(for: vm.deviceNotchRect.size) : 0
        case .opened: return IslandMetrics.filletRadius(for: vm.deviceNotchRect.size)
        case .popping: return 0
        }
    }

    /// 底部圆角：随状态变化（原型 12 / 20 / 26）
    var islandBottomRadius: CGFloat {
        let isGhost = vm.hoverGhosting || vm.ghostFading
        switch vm.status {
        case .closed: return isGhost ? IslandMetrics.peekBottomRadius(for: vm.deviceNotchRect.size) : 12
        case .opened: return IslandMetrics.openBottomRadius(for: vm.deviceNotchRect.size)
        case .popping: return 10
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            island
                .zIndex(0)
                .disabled(true)
                .opacity(vm.notchVisible ? 1 : 0.3)
            Group {
                if vm.status == .opened {
                    // 内容自适应（ADR-0008）：内容自然高，不锁死、不裁剪
                    VStack(spacing: vm.spacing) {
                        NotchContentView(vm: vm)
                            .frame(maxWidth: .infinity)
                            .modifier(StaggeredEntry(delay: 0.06))
                    }
                    .onAppear { notchTimingMark("contentAppear") }
                    .padding(.horizontal, vm.spacing)
                    .padding(.bottom, vm.spacing)
                    // 顶部收紧 20→10：安全区之上已垫刘海避让，内层不再 double（02 票）
                    .padding(.top, 10)
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
            .transition(
                .scale.combined(
                    with: .opacity
                ).combined(
                    with: .offset(y: -vm.zoneOpenedSize.height / 2)
                )
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
        IslandShape(bottomRadius: islandBottomRadius, filletRadius: islandFillet)
            .fill(Color.black)
            .frame(width: islandSize.width + islandFillet * 2, height: islandSize.height)
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
            // 岛尺寸随数据变化走同款弹簧（与 TokenZoneView 列宽变化同步 morph）
            .animation(reduceMotion ? nil : IslandMetrics.growSpring, value: islandSize)
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
struct StaggeredEntry: ViewModifier {
    let delay: TimeInterval
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
