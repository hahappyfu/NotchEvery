//
//  DiagZoneView.swift
//  NotchDrop
//
//  诊断分区（工单 06）：判定时间线，横扫/dots 可达，过渡与既有分区一致。
//  时间线在面板内部滚动，不撑外框（内容驱动尺寸契约）；数据源 DecisionLogger。

import AppKit
import SwiftUI

struct DiagZoneView: View {
    @StateObject private var logger = DecisionLogger.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            timeline
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        // 不写死宽度：行列宽合计约 524（原型实测达标值），由内容自然撑宽，
        // 经内容驱动尺寸上报 + 1.75 保底钳制（不得裁切内容来回避）。
        .onAppear { logger.loadHistory() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.green)
                .frame(width: 7, height: 7)
            Text("诊断 · \(logger.events.count)条")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
        }
    }

    private var timeline: some View {
        let days = DiagTimeline.build(from: logger.events)
        return Group {
            if days.isEmpty {
                Text("暂无判定记录")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(days, id: \.day) { day in
                            DiagDayView(day: day)
                        }
                    }
                }
                // 内部滚动定高：不撑大面板外框（06 工单约束）
                .frame(maxHeight: 220)
            }
        }
    }
}

/// 一天的分组：日期头 + 行（时间/信号/原因/结果/下一步建议）
struct DiagDayView: View {
    let day: DiagDay

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dayHeader(day.day))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(day.entries, id: \.event.id) { entry in
                DiagEntryView(entry: entry)
            }
        }
    }

    private func dayHeader(_ date: Date) -> String {
        Self.dayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        return f
    }()
}

/// 一行：结果圆点 + 时间 + 信号 + 原因（含建议行）；单行不折行，超长省略
struct DiagEntryView: View {
    let entry: DiagEntry

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(outcomeColor(entry.event.outcome))
                .frame(width: 6, height: 6)
            Spacer(minLength: 6)
            Text(entry.timeText)
                .foregroundStyle(.tertiary)
                .frame(width: 62, alignment: .leading)
            Spacer(minLength: 8)
            Text(outcomeText(entry.event.outcome))
                .foregroundStyle(outcomeColor(entry.event.outcome))
                .frame(width: 34, alignment: .leading)
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if let signal = entry.signalText {
                        Text(signal)
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.reasonText)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if let hint = entry.hintText {
                    if entry.hasExecutableAction {
                        Button(action: { handleAction(entry.action) }) {
                            Text(hint)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    } else {
                        Text(hint)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        }
        .font(.system(size: 11))
        .monospacedDigit()
    }

    private func handleAction(_ action: ActionHint?) {
        switch action {
        case .openAccessibilitySettings:
            openAccessibilitySettings()
        case .reEnterPassword:
            SecurityService.shared.askPassword()
        default:
            break
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// 结果色：与 Token 页状态色同 palette（成功绿 / 失败红 / 其余次级）
private func outcomeColor(_ outcome: DecisionOutcome) -> Color {
    switch outcome {
    case .success: return Color(red: 0.16, green: 0.55, blue: 0.32)
    case .failed, .blocked: return Color(red: 0.75, green: 0.20, blue: 0.18)
    case .skipped, .info: return .secondary
    }
}

/// 结果文字：圆点颜色之外再给一词（读屏与色觉可达）
private func outcomeText(_ outcome: DecisionOutcome) -> String {
    switch outcome {
    case .success: return "成功"
    case .skipped: return "跳过"
    case .failed: return "失败"
    case .blocked: return "拦截"
    case .info: return "信息"
    }
}
