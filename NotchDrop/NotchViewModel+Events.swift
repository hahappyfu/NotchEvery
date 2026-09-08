//
//  NotchViewModel+Events.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/8.
//

import Cocoa
import Combine
import Foundation
import SwiftUI

extension NotchViewModel {
    func setupCancellables(events: any EventMonitorsProtocol = EventMonitors.shared) {
        events.mouseDown
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let mouseLocation: NSPoint = NSEvent.mouseLocation
                switch status {
                case .opened:
                    // touch outside, close
                    if !notchOpenedRect.contains(mouseLocation) {
                        notchClose()
                        // click where user open the panel
                    } else if deviceNotchRect.insetBy(dx: inset, dy: inset).contains(mouseLocation) {
                        notchClose()
                        // for the same height as device notch, open the url of project
                    }
                    // 顶栏点击已搬到 NotchHeaderView 的 onTapGesture（视图层 Button 优先，天然互斥），
                    // 这里不再处理：否则 mouseDown 先切会跟 Button 的 mouseUp 打架
                case .closed, .popping:
                    // touch inside, open
                    if deviceNotchRect.insetBy(dx: inset, dy: inset).contains(mouseLocation) {
                        // 虚影态点击 → 展开；否则直接展开
                        if hoverGhosting {
                            openFromGhost()
                        } else {
                            notchOpen(.click)
                        }
                    }
                }
            }
            .store(in: &cancellables)

        events.optionKeyPress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] input in
                guard let self else { return }
                optionKeyPressed = input
            }
            .store(in: &cancellables)

        events.mouseLocation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mouseLocation in
                guard let self else { return }
                let aboutToOpen = deviceNotchRect.insetBy(dx: inset, dy: inset).contains(mouseLocation)
                if status == .closed, aboutToOpen, !hoverGhosting { notchOpen(.hover) }
                // 边界防御 A：虚影态期间光标离开热区，300ms 缓冲后清虚影（防幽灵展开）
                if hoverGhosting, !aboutToOpen {
                    scheduleHoverClose()
                } else if hoverGhosting, aboutToOpen {
                    cancelHoverClose()
                }
                if status == .popping, !aboutToOpen { notchClose() }
                // hover 展开态：离开面板区延迟收起，移回取消
                if status == .opened, openReason == .hover {
                    if notchOpenedRect.contains(mouseLocation) {
                        cancelHoverClose()
                    } else {
                        scheduleHoverClose()
                    }
                }
            }
            .store(in: &cancellables)

        $status
            .filter { $0 != .closed }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                withAnimation { self?.notchVisible = true }
            }
            .store(in: &cancellables)

        $status
            .filter { $0 == .popping }
            .throttle(for: .seconds(0.5), scheduler: DispatchQueue.main, latest: false)
            .sink { [weak self] _ in
                guard NSEvent.pressedMouseButtons == 0 else { return }
                self?.hapticSender.send()
            }
            .store(in: &cancellables)

        hapticSender
            .throttle(for: .seconds(0.5), scheduler: DispatchQueue.main, latest: false)
            .sink { [weak self] _ in
                guard self?.hapticFeedback ?? false else { return }
                NSHapticFeedbackManager.defaultPerformer.perform(
                    .levelChange,
                    performanceTime: .now
                )
            }
            .store(in: &cancellables)

        $status
            .debounce(for: 0.5, scheduler: DispatchQueue.global())
            .filter { $0 == .closed }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                withAnimation {
                    self?.notchVisible = false
                }
            }
            .store(in: &cancellables)

        $selectedLanguage
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] output in
                self?.notchClose()
                output.apply()
            }
            .store(in: &cancellables)
    }

    func destroy() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
}
