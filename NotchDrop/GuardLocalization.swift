// GuardLocalization.swift
// 守护能力的本地化与事件标签映射（纯 Foundation，不引入 SwiftUI / AppKit）。
//
// 来源：由 FUnlock 的 FUnlockUtils.swift 拆分而来（工单 01，见 .scratch/funlock-merge/）。
// 原文件把四类关注点混在一起：本地化 t()、时序埋点 timingLog()、设备图标名 deviceIconName()、
// 以及 DecisionEvent 的 UI 映射扩展。其中 `icon` 返回 SwiftUI Color，属视图关注点，
// 随诊断分区（工单 06）落地；timingLog / deviceIconName 随其调用方（工单 03/05）落地。
// 本文件只承载逻辑层需要、且被既有测试直接断言的两项：t() 与 DecisionEvent.screenLabel()。
// 两者逻辑逐字未改。

import Foundation

/// 本地化查询（原 FUnlockUtils.swift:4）。
func t(_ key: String) -> String {
    return NSLocalizedString(key, comment: "")
}

extension DecisionEvent {
    /// 屏幕状态 → 本地化 key（静态，便于测试；原 FUnlockUtils.swift:84）。
    static func screenLabel(_ screen: String?) -> String? {
        guard let screen else { return nil }
        switch screen {
        case "unlocked": return "screen_unlocked"
        case "locked(away)": return "screen_locked_away"
        case "locked(manual)": return "screen_locked_manual"
        case "locked(lost)": return "screen_locked_lost"
        case "locked(timeout)": return "screen_locked_timeout"
        case "displaySleeping": return "screen_display_sleeping"
        case "screensaver": return "screen_screensaver"
        default: return screen
        }
    }
}
