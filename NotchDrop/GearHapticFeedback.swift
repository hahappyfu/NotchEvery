//
//  GearHapticFeedback.swift
//  NotchDrop
//
//  机械齿轮触觉发生器：
//  - 垂直滚动（触控板上下滑）：每滑过一个卡片步距触发一次短促清脆的机械棘轮感（.generic 明确触感）
//  - 左右切页（触控板横向切）：触发一次沉稳入位的机械挡位咬合感（.levelChange + .generic 复合吸附）
//

import AppKit
import Foundation

public final class GearHapticFeedback {
    public static let shared = GearHapticFeedback()

    /// 垂直滚动触发机械齿轮棘轮的步长（点，约半个卡片高度，齿感更细腻连贯）
    private let tickStep: CGFloat = 26.0
    /// 两次棘轮震动的最小防抖间隔（防高刷过度堆积）
    private let minTickInterval: TimeInterval = 0.035

    private var accumulatedVerticalDelta: CGFloat = 0
    private var lastTickTime: TimeInterval = 0

    private init() {}

    /// 输入垂直滚动增量，满足齿距步进时回弹一次极短促清脆的棘轮咬合感
    public func feedVertical(deltaY: CGFloat, now: TimeInterval) {
        accumulatedVerticalDelta += deltaY
        if abs(accumulatedVerticalDelta) >= tickStep {
            accumulatedVerticalDelta = 0
            if now - lastTickTime >= minTickInterval {
                lastTickTime = now
                triggerHaptic(pattern: .generic)
            }
        }
    }

    /// 触发左右切页的挡位咬合反馈
    public func triggerPageDetent() {
        triggerHaptic(pattern: .levelChange)
        // 极短延迟追加微脉冲，形成沉稳卡入卡槽的机械复合阻尼感
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.triggerHaptic(pattern: .generic)
        }
    }

    /// 触发系统触觉反馈，确保 Window 处于 Key 状态以唤醒 Force Touch 硬件执行器
    private func triggerHaptic(pattern: NSHapticFeedbackManager.FeedbackPattern) {
        ensureWindowActive()
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    private func ensureWindowActive() {
        if let notchWin = NSApp.windows.first(where: { $0 is NotchWindow }) {
            if !notchWin.isKeyWindow {
                notchWin.makeKey()
            }
        }
    }

    /// 重置累积量
    public func reset() {
        accumulatedVerticalDelta = 0
    }
}
