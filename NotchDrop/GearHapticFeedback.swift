//
//  GearHapticFeedback.swift
//  NotchDrop
//
//  机械齿轮触觉发生器：
//  - 垂直滚动（触控板上下滑）：每滑过一个卡片步距触发一次短促清脆的机械棘轮感（.alignment）
//  - 左右切页（触控板横向切）：触发一次沉稳入位的机械挡位咬合感（.levelChange）
//

import AppKit
import Foundation

public final class GearHapticFeedback {
    public static let shared = GearHapticFeedback()

    /// 垂直滚动触发机械齿轮棘轮的步长（点）
    private let tickStep: CGFloat = 32.0
    /// 两次棘轮震动的最小防抖间隔（防超高频刷新爆震）
    private let minTickInterval: TimeInterval = 0.045

    private var accumulatedVerticalDelta: CGFloat = 0
    private var lastTickTime: TimeInterval = 0

    private init() {}

    /// 输入垂直滚动增量，满足齿距步进时回弹一次极短促的棘轮咬合感
    public func feedVertical(deltaY: CGFloat, now: TimeInterval) {
        accumulatedVerticalDelta += deltaY
        if abs(accumulatedVerticalDelta) >= tickStep {
            accumulatedVerticalDelta = 0
            if now - lastTickTime >= minTickInterval {
                lastTickTime = now
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
    }

    /// 触发左右切页的挡位咬合反馈
    public func triggerPageDetent() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    /// 重置累积量（手势中断或离开时调用）
    public func reset() {
        accumulatedVerticalDelta = 0
    }
}
