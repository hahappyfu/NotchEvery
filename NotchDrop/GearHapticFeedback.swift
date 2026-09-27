//
//  GearHapticFeedback.swift
//  NotchDrop
//
//  机械齿轮触觉发生器：
//  - 左右切页（触控板横向切）：触发一次沉稳入位的机械挡位咬合感（.levelChange + .generic 复合吸附）
//

import AppKit
import Foundation

public final class GearHapticFeedback {
    public static let shared = GearHapticFeedback()

    private init() {}

    /// 触发左右切页的挡位咬合反馈
    public func triggerPageDetent() {
        triggerHaptic(pattern: .levelChange)
        // 极短延迟追加微脉冲，形成沉稳卡入卡槽的机械复合阻尼感
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.triggerHaptic(pattern: .generic)
        }
    }

    /// 触发系统触觉反馈（NSHapticFeedbackManager 不依赖 Window Key 状态，杜绝触发触觉时抢夺前台焦点）
    private func triggerHaptic(pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
