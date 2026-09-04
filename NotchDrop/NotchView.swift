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
        case .opened: 26
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
                if vm.status == .opened {
                    VStack(spacing: vm.spacing) {
                        NotchHeaderView(vm: vm)
                        NotchContentView(vm: vm)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.horizontal, 10).padding(.bottom, 10).padding(.top, 24)
                    .frame(maxWidth: vm.notchOpenedSize.width, maxHeight: vm.notchOpenedSize.height)
                    .zIndex(1)
                }
            }
            .transition(
                .scale.combined(
                    with: .opacity
                ).combined(
                    with: .offset(y: -vm.notchOpenedSize.height / 2)
                ).animation(vm.animation)
            )
            .animation(vm.animation, value: vm.status)
        }
        .background(dragDetector)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// 自定义外壳：黑曜石材质直接画进一笔画 Shape，无飞檐
    var notch: some View {
        Rectangle()
            .fill(.clear)
            .obsidian(in: NotchShellShape(
                topMicroRadius: vm.status == .opened ? 6 : notchCornerRadius,
                bottomRadius: notchCornerRadius
            ))
            .frame(
                width: notchSize.width,
                height: notchSize.height
            )
            .shadow(
                color: .black.opacity(([.opened, .popping].contains(vm.status)) ? 0.3 : 0),
                radius: 20,
                y: 8
            )
    }

    @ViewBuilder
    var dragDetector: some View {
        RoundedRectangle(cornerRadius: notchCornerRadius)
            .foregroundStyle(Color.black.opacity(0.001)) // fuck you apple and 0.001 is the smallest we can have
            .contentShape(Rectangle())
            .frame(width: notchSize.width + vm.dropDetectorRange, height: notchSize.height + vm.dropDetectorRange)
            .onDrop(of: [.data], isTargeted: $dropTargeting) { _ in true }
            .onChange(of: dropTargeting) { isTargeted in
                if isTargeted {
                    // 拖入时先展开（内部重置为状态页），再切到托盘页
                    if vm.status == .closed {
                        vm.notchOpen(.drag)
                    }
                    // 已在托盘页则不再重复切换，避免动画抖动
                    if vm.activeTab != .tray {
                        withAnimation(vm.animation) { vm.activeTab = .tray }
                    }
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
