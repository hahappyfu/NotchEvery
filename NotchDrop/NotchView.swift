//
//  NotchView.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/7.
//

import SwiftUI
import os

struct NotchView: View {
    @StateObject var vm: NotchViewModel

    @State var dropTargeting: Bool = false
    @State private var swipeResolver = ScrollSwipeResolver()

    var notchSize: CGSize {
        let isGhost = vm.hoverGhosting || vm.ghostFading
        switch vm.status {
        case .closed:
            if isGhost {
                // 舌头形虚影：宽 = max(刘海宽×1.1, 200)、高 52
                let w = max(vm.deviceNotchRect.width * 1.1, 200)
                return CGSize(width: w, height: 52)
            }
            var ans = CGSize(
                width: vm.deviceNotchRect.width - 4,
                height: vm.deviceNotchRect.height - 4
            )
            if ans.width < 0 { ans.width = 0 }
            if ans.height < 0 { ans.height = 0 }
            return ans
        case .opened:
            return vm.zoneOpenedSize
        case .popping:
            return .init(
                width: vm.deviceNotchRect.width,
                height: vm.deviceNotchRect.height + 4
            )
        }
    }

    var notchCornerRadius: CGFloat {
        let isGhost = vm.hoverGhosting || vm.ghostFading
        switch vm.status {
        case .closed: return isGhost ? 16 : 8
        case .opened: return 32
        case .popping: return 10
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            notch
                .zIndex(0)
                .disabled(true)
                .opacity(vm.notchVisible ? 1 : 0.3)
            Group {
                if vm.status == .opened {
                    // 选项卡钉死结构：头部槽高度恒定，高度动画只作用于下方内容区；
                    // 外层 frame 只锁宽（无高度可居中），选项卡垂直位置因此与分区无关
                    VStack(spacing: vm.spacing) {
                        NotchHeaderView(vm: vm)
                            .zoneHeightReporter()
                            .frame(height: NotchViewModel.headerSlotHeight)
                            .background(HeaderProbe(label: "header"))
                            .modifier(StaggeredEntry(delay: 0.08))
                            .onPreferenceChange(ZoneNaturalHeightKey.self) { natural in
                                // 对称守卫：选项卡自然高若超过头部槽位，同样意味着排版脱节
                                assert(
                                    natural <= NotchViewModel.headerSlotHeight + 0.5,
                                    "头部槽位脱节：选项卡回报高 \(natural) > 槽位 \(NotchViewModel.headerSlotHeight)"
                                )
                            }
                        NotchContentView(vm: vm)
                            .frame(maxWidth: .infinity)
                            .frame(height: vm.zoneContentHeight)
                            .clipped()
                            .modifier(StaggeredEntry(delay: 0.16))
                    }
                    .padding(vm.spacing)
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
            .onReceive(vm.events.arrowKey) { key in
                guard vm.status == .opened else { return }
                guard NSApp.keyWindow is NotchWindow else { return }
                guard vm.notchOpenedRect.contains(NSEvent.mouseLocation) else { return }
                guard !dropTargeting else { return }
                if key == .rightForward {
                    vm.nextZone()
                } else {
                    vm.previousZone()
                }
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
        .animation(vm.status == .opened ? vm.openAnimation : vm.closeAnimation, value: vm.status)
        // 面板胀缩挂同一内容切换事务：背景与 frame 高度跟随当前区，无跳变
        .animation(vm.animation, value: vm.contentType)
        .background(dragDetector)
        // 右键菜单挂根层级：外壳带 .disabled(true) 会把菜单按钮全置灰，根层级无禁用
        .contextMenu {
            Button(LocalizedStringKey("Settings")) {
                vm.openFromGhost()
                vm.showSettings()
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

    var notch: some View {
        glassNotchBackground
            .mask(notchBackgroundMaskGroup)
            .frame(
                width: notchSize.width + notchCornerRadius * 2,
                height: notchSize.height
            )
            // 无外投影：悬浮感靠磨砂与描边，投影在浅底上显脏（2026-09-08 定稿）
            // 过桥菊花：openFromGhost 后 150ms 短闪
            .overlay {
                if vm.bridgeSpinning {
                    SpinnerView(size: 16, color: .white)
                        .transition(.opacity)
                }
            }
    }

    /// 玻璃刘海背景：控制中心式高透磨砂，浅底色 + 顶部折射高光
    private var glassNotchBackground: some View {
        Rectangle()
            .fill(.clear)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: notchCornerRadius, bottomTrailingRadius: notchCornerRadius, topTrailingRadius: 0, style: .continuous)
                    .fill((vm.hoverGhosting || vm.ghostFading)
                        ? Color(red: 0.165, green: 0.173, blue: 0.2).opacity(0.72)
                        : Color(red: 0.08, green: 0.08, blue: 0.09).opacity(0.15)
                    )
            )
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: notchCornerRadius, bottomTrailingRadius: notchCornerRadius, topTrailingRadius: 0, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: notchCornerRadius, bottomTrailingRadius: notchCornerRadius, topTrailingRadius: 0, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.10), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            )
            .overlay(
                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: notchCornerRadius, bottomTrailingRadius: notchCornerRadius, topTrailingRadius: 0, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
    }

    var notchBackgroundMaskGroup: some View {
        Rectangle()
            .foregroundStyle(.black)
            .frame(
                width: notchSize.width,
                height: notchSize.height
            )
            .clipShape(.rect(
                bottomLeadingRadius: notchCornerRadius,
                bottomTrailingRadius: notchCornerRadius
            ))
            .overlay {
                ZStack(alignment: .topTrailing) {
                    Rectangle()
                        .frame(width: notchCornerRadius, height: notchCornerRadius)
                        .foregroundStyle(.black)
                    Rectangle()
                        .clipShape(.rect(topTrailingRadius: notchCornerRadius))
                        .foregroundStyle(.white)
                        .frame(
                            width: notchCornerRadius + vm.spacing,
                            height: notchCornerRadius + vm.spacing
                        )
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: -notchCornerRadius - vm.spacing + 0.5, y: -0.5)
            }
            .overlay {
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .frame(width: notchCornerRadius, height: notchCornerRadius)
                        .foregroundStyle(.black)
                    Rectangle()
                        .clipShape(.rect(topLeadingRadius: notchCornerRadius))
                        .foregroundStyle(.white)
                        .frame(
                            width: notchCornerRadius + vm.spacing,
                            height: notchCornerRadius + vm.spacing
                        )
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: notchCornerRadius + vm.spacing - 0.5, y: -0.5)
            }
    }

    @ViewBuilder
    var dragDetector: some View {
        RoundedRectangle(cornerRadius: notchCornerRadius)
            .foregroundStyle(Color.black.opacity(0.001)) // fuck you apple and 0.001 is the smallest we can have
            .contentShape(Rectangle())
            .frame(width: notchSize.width + vm.dropDetectorRange, height: notchSize.height + vm.dropDetectorRange)
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

/// 分批入场修饰符：延迟后 blur 4→0 + opacity 0→1 + 下移入场；reduceMotion 直接显示
struct StaggeredEntry: ViewModifier {
    let delay: TimeInterval
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .blur(radius: shown || reduceMotion ? 0 : 4)
            .offset(y: shown || reduceMotion ? 0 : -6)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.2).delay(delay)) {
                    shown = true
                }
            }
    }
}

/// 诊断埋点（FIXME(tab-pin): 定案后删）：头部槽在屏幕全局坐标里的真实 y，绕开 AX 读数
private struct HeaderProbe: View {
    let label: String
    @State private var last: CGFloat = .nan

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { report(geo) }
                .onChange(of: geo.frame(in: .global).minY) { _ in
                    report(geo)
                }
        }
    }

    private func report(_ geo: GeometryProxy) {
        let y = geo.frame(in: .global).minY
        guard y != last else { return }
        last = y
        Logger(subsystem: "com.hahappyfu.NotchEvery", category: "header-probe")
            .log("\(self.label, privacy: .public) headerY=\(y, format: .fixed(precision: 1))")
    }
}
