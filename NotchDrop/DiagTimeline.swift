// DiagTimeline.swift
// NotchEvery
//
// 诊断时间线行模型（工单 06）：纯 Foundation，视图与单测共用。
// 输入 DecisionLogger.events（时间顺序），输出按日期分组、组内组外全倒序。
// 文案规则与守护卡保持一致：detail 非空优先，否则 reason.titleKey。

import Foundation

/// 一天（day 为当天 00:00；entries 时间倒序）
struct DiagDay: Equatable {
    let day: Date
    var entries: [DiagEntry]
}

/// 一行：时间 / 信号 / 原因 / 结果 / 下一步建议（均为展示就绪文本）
struct DiagEntry: Equatable {
    let event: DecisionEvent
    var timeText: String
    var signalText: String?
    var reasonText: String
    var hintText: String?
    /// 可执行的操作（辅助功能设置、重录密码等；无则为 nil）
    var action: ActionHint?
    var hasExecutableAction: Bool { action != nil }
}

enum DiagTimeline {
    static func build(from events: [DecisionEvent], calendar: Calendar = .current) -> [DiagDay] {
        let sorted = events.sorted { $0.timestamp > $1.timestamp }
        var days: [DiagDay] = []
        for event in sorted {
            let day = calendar.startOfDay(for: event.timestamp)
            let executableAction: ActionHint?
            switch event.reason?.action {
            case .openAccessibilitySettings, .reEnterPassword:
                executableAction = event.reason?.action
            default:
                executableAction = nil
            }
            let entry = DiagEntry(
                event: event,
                timeText: timeFormatter.string(from: event.timestamp),
                signalText: event.rssi.map { "\($0) dBm" },
                reasonText: event.detail.isEmpty
                    ? (event.reason.map { t($0.titleKey) } ?? "") : event.detail,
                hintText: event.reason?.action.map { t($0.labelKey) },
                action: executableAction
            )
            if days.last?.day == day {
                days[days.count - 1].entries.append(entry)
            } else {
                days.append(DiagDay(day: day, entries: [entry]))
            }
        }
        return days
    }

    /// HH:mm:ss 复用静态实例（与 TokenZoneView.footerFormatter 同 pattern）
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
