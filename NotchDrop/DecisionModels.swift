// DecisionModels.swift
// 决策数据模型与屏幕状态定义

import Foundation

enum ScreenState: Equatable, CustomStringConvertible {
    case unlocked
    case locked(reason: LockReason)
    case screensaver
    case displaySleeping

    enum LockReason: Equatable {
        case away, lost, manual, timeout
    }

    var description: String {
        switch self {
        case .unlocked: return "unlocked"
        case .locked(let reason): return "locked(\(reason))"
        case .screensaver: return "screensaver"
        case .displaySleeping: return "displaySleeping"
        }
    }
}

enum DecisionCategory: String, Codable, CaseIterable {
    case unlock, lock, system, user
}

enum DecisionOutcome: String, Codable {
    case success, skipped, failed, blocked, info
}

enum DecisionReason: String, Codable, CaseIterable {
    case noPresence
    case signalBelowThreshold
    case unlockCooldownActive
    case lockBufferActive
    case manualLockActive
    case wifiPaused
    case disabled
    case unlockDisabled
    case stateMachineBlocked
    case axRevoked
    case noPassword
    case keychainColdBoot
    case notSecureForInjection
    case displaySleeping
    case systemNotReady
    case lockedAway
    case lockedLost
    case lockedManual
    case lockedTimeout
    case lockCooldownActive
    case signalBelowLockThreshold
    case unlocked
    case unlockSuccess
    case unlockFailed
    case abnormalUnlockSpike
    case passwordMismatch
    case iMessageFailed
    case systemAwake
    case systemSleep
    case screenUnlocked
    case screenLocked
    case screensaverStarted
    case screensaverStopped
    case displayWoke
    case displaySlept
    case userPresent
    case userAway

    var titleKey: String {
        switch self {
        case .noPresence: return "reason_no_presence"
        case .signalBelowThreshold: return "reason_signal_below_threshold"
        case .unlockCooldownActive: return "reason_unlock_cooldown"
        case .lockBufferActive: return "reason_lock_buffer"
        case .manualLockActive: return "reason_manual_lock"
        case .wifiPaused: return "reason_wifi_paused"
        case .disabled: return "reason_disabled"
        case .unlockDisabled: return "reason_unlock_disabled"
        case .stateMachineBlocked: return "reason_state_machine"
        case .axRevoked: return "reason_ax_revoked"
        case .noPassword: return "reason_no_password"
        case .keychainColdBoot: return "reason_keychain_cold_boot"
        case .notSecureForInjection: return "reason_not_secure"
        case .displaySleeping: return "reason_display_sleeping"
        case .systemNotReady: return "reason_system_not_ready"
        case .lockedAway: return "reason_locked_away"
        case .lockedLost: return "reason_locked_lost"
        case .lockedManual: return "reason_locked_manual"
        case .lockedTimeout: return "reason_locked_timeout"
        case .lockCooldownActive: return "reason_lock_cooldown"
        case .signalBelowLockThreshold: return "reason_signal_below_lock_threshold"
        case .unlocked: return "reason_unlocked"
        case .unlockSuccess: return "reason_unlock_success"
        case .unlockFailed: return "reason_unlock_failed"
        case .abnormalUnlockSpike: return "reason_abnormal_unlock_spike"
        case .passwordMismatch: return "reason_password_mismatch"
        case .iMessageFailed: return "reason_imessage_failed"
        case .systemAwake: return "reason_system_awake"
        case .systemSleep: return "reason_system_sleep"
        case .screenUnlocked: return "reason_screen_unlocked"
        case .screenLocked: return "reason_screen_locked"
        case .screensaverStarted: return "reason_screensaver_started"
        case .screensaverStopped: return "reason_screensaver_stopped"
        case .displayWoke: return "reason_display_woke"
        case .displaySlept: return "reason_display_slept"
        case .userPresent: return "reason_user_present"
        case .userAway: return "reason_user_away"
        }
    }

    var action: ActionHint? {
        switch self {
        case .signalBelowThreshold: return .lowerUnlockThreshold
        case .manualLockActive: return .goToTab("lock")
        case .wifiPaused: return .goToTab("network")
        case .disabled: return .goToTab("basic")
        case .unlockDisabled: return .goToTab("unlock")
        case .stateMachineBlocked: return .resetStateMachine
        case .axRevoked: return .openAccessibilitySettings
        case .noPassword, .keychainColdBoot, .unlockFailed, .passwordMismatch: return .reEnterPassword
        case .signalBelowLockThreshold: return .goToTab("unlock")
        default: return nil
        }
    }
}

enum ActionHint: Equatable {
    case lowerUnlockThreshold
    case openAccessibilitySettings
    case reEnterPassword
    case goToTab(String)
    case resetStateMachine

    var labelKey: String {
        switch self {
        case .lowerUnlockThreshold: return "action_lower_unlock_threshold"
        case .openAccessibilitySettings: return "action_open_accessibility"
        case .reEnterPassword: return "action_reenter_password"
        case .goToTab: return "action_go_to_settings"
        case .resetStateMachine: return "action_reset_state_machine"
        }
    }
}

struct DecisionEvent: Codable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let category: DecisionCategory
    let outcome: DecisionOutcome
    let reason: DecisionReason?
    let rssi: Int?
    let device: String?
    let screen: String?
    let detail: String

    init(id: UUID = UUID(), timestamp: Date, category: DecisionCategory,
         outcome: DecisionOutcome, reason: DecisionReason?, rssi: Int?,
         device: String?, screen: String?, detail: String = "") {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.outcome = outcome
        self.reason = reason
        self.rssi = rssi
        self.device = device
        self.screen = screen
        self.detail = detail
    }
}
