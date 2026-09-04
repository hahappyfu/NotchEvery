//
//  NotchView.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/7.
//

import SwiftUI

struct NotchView: View {
    @StateObject var vm: NotchViewModel

    @State var dropTargeting: Bool = false

    var notchSize: CGSize {
        switch vm.status {
        case .closed:
            var ans = CGSize(
                width: vm.deviceNotchRect.width - 4,
                height: vm.deviceNotchRect.height - 4
            )
            if ans.width < 0 { ans.width = 0 }
            if ans.height < 0 { ans.height = 0 }
            return ans
        case .opened:
            return vm.notchOpenedSize
        case .popping:
            return .init(
                width: vm.deviceNotchRect.width,
                height: vm.deviceNotchRect.height + 4
            )
        }
    }

    var notchCornerRadius: CGFloat {
        switch vm.status {
        case .closed: 8
        case .opened: 28
        case .popping: 10
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            notch
                .zIndex(0)
                .disabled(true)
                .opacity(vm.notchVisible ? 1 : 0.3)
            Group {
                if vm.isExpanded {
                    VStack(spacing: vm.spacing) {
                        NotchHeaderView(vm: vm)
                        NotchContentView(vm: vm)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            // 内容层：等容器基本撑开后再淡入，避免拉伸过程中的文字/图标形变
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                                    .animation(.easeOut(duration: 0.22).delay(0.12)),
                                removal: .opacity.animation(.easeOut(duration: 0.12))
                            ))
                    }
                    // 顶部 24pt 镜头避让区，其余沿用常规间距
                    .padding(.horizontal, vm.spacing)
                    .padding(.bottom, vm.spacing)
                    .padding(.top, 24)
                    .frame(maxWidth: vm.notchOpenedSize.width, maxHeight: vm.notchOpenedSize.height, alignment: .top)
                    .clipped()
                    .zIndex(1)
                }
            }
            .transition(.asymmetric(
                insertion: .scale(scale: 0.9, anchor: .top).combined(with: .opacity)
                    .combined(with: .offset(y: -vm.notchOpenedSize.height / 2))
                    .animation(vm.animation),
                // 收起：展开内容立即淡出，不做位移/回弹，容器跟随收缩
                removal: .opacity.animation(.easeOut(duration: 0.12))
            ))
            // 展开用弹性曲线软着陆，收起用快曲线干脆利落
            .animation(vm.isExpanded ? vm.animation : vm.closeAnimation, value: vm.isExpanded)
        }
        .background(dragDetector)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    var notch: some View {
        glassNotchBackground
            .mask(notchBackgroundMaskGroup)
            .frame(
                width: notchSize.width + notchCornerRadius * 2,
                height: notchSize.height
            )
            .shadow(
                color: .black.opacity(([.opened, .popping].contains(vm.status)) ? 0.3 : 0),
                radius: 20,
                y: 8
            )
            // 尺寸与底部圆角跟随展开/收起平滑过渡（展开 8→28，收起贴回默认圆角）
            .animation(vm.isExpanded ? vm.animation : vm.closeAnimation, value: vm.isExpanded)
    }

    /// 玻璃刘海背景：统一走 Glass 封装，底色锁定暗黑（浅色模式也不穿帮）
    private var glassNotchBackground: some View {
        Rectangle()
            .fill(Color.black.opacity(0.88))
            .background(.ultraThinMaterial)
            .glassCard(cornerRadius: notchCornerRadius)
            // 0.8px 高光内描边：用 strokeBorder 让整圈线宽留在 mask 内
            .overlay {
                RoundedRectangle(cornerRadius: notchCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
            }
    }

    var notchBackgroundMaskGroup: some View {
        Rectangle()
            .foregroundStyle(.black)
            .frame(
                width: notchSize.width,
                height: notchSize.height
            )
            // 顶部平直贴合屏幕上沿，底部连续平滑倒角
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: notchCornerRadius,
                bottomTrailingRadius: notchCornerRadius,
                topTrailingRadius: 0,
                style: .continuous
            ))
            .overlay {
                // 展开态去掉大反角飞檐：顶部平齐垂直向下（收起态保留小耳贴边）
                if !vm.isExpanded {
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
            }
            .overlay {
                // 展开态去掉大反角飞檐：顶部平齐垂直向下（收起态保留小耳贴边）
                if !vm.isExpanded {
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
