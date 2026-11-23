//
//  ProviderQuotaFormat.swift
//  NotchEvery
//
//  供应商额度页的纯文案格式化：可单测，无副作用。
//

import Foundation
import SwiftUI

enum ProviderQuotaFormat {
    static func remainingText(_ group: MagpieProviderGroup) -> String {
        if let remaining = group.totalRemaining, let limit = group.totalLimit, limit > 0 {
            return "\(fmt(remaining)) / \(fmt(limit))"
        }
        if let fraction = group.fraction {
            return "余 \(Int((fraction * 100).rounded()))%"
        }
        return "无刻度"
    }

    static func noticeBadge(
        _ state: ProviderLimitState,
        now: Date,
        timeZone: TimeZone = .current
    ) -> String? {
        switch state {
        case .riskBlocked:
            return "403 风控"
        case .cooling(let until):
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            formatter.timeZone = timeZone
            return "冷却至 \(formatter.string(from: until))"
        case .rateLimited:
            return "429 限流"
        case .none:
            return nil
        }
    }

    static func countdown(_ date: Date, now: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "已过期" }
        let hours = seconds / 3600
        if hours >= 1 { return "\(Int(hours))h 过期" }
        return "\(max(1, Int(ceil(seconds / 60))))m 过期"
    }

    static func accountSummary(_ group: MagpieProviderGroup) -> String? {
        guard group.accounts.count > 1 else { return nil }
        var parts: [String] = []
        if group.availableAccounts > 0 { parts.append("\(group.availableAccounts) 号可用") }
        if group.exhaustedAccounts > 0 { parts.append("\(group.exhaustedAccounts) 号耗尽") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func checkinText(_ checkin: MagpieCheckinSummary) -> String {
        if checkin.claimedProviders > 0 {
            let base = "今日签到：\(checkin.claimedProviders) 家已领"
            return checkin.totalCredit > 0 ? "\(base) +\(fmt(checkin.totalCredit))" : base
        }
        if checkin.pendingProviders > 0 {
            return "今日签到：\(checkin.pendingProviders) 家可领"
        }
        return "今日暂无签到"
    }

    static func gatewayText(_ state: MagpieGatewayState) -> String {
        switch state {
        case .online(let version):
            let base = "Magpie :3425 在线"
            let trimmed = version?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? base : "\(base) v\(trimmed)"
        case .offline:
            return "网关未运行"
        }
    }

    static func windowUsage(_ window: MagpieWindow) -> String {
        if let amount = window.amount, let limit = window.limit {
            return "\(fmt(amount)) / \(fmt(limit))"
        }
        if let used = window.usedPercent { return "\(fmt(used))%" }
        return "—"
    }

    static func barFill(_ fraction: Double?) -> Double {
        guard let fraction else { return 1 }
        return min(max(fraction, 0), 1)
    }

    static func fmt(_ value: Double) -> String {
        // POSIX locale 锁定小数点字符；先四舍五入避免 printf 的 ties-to-even 改变 4.65 一类边界值。
        let rounded = (value * 10).rounded() / 10
        let text = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), rounded)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}

/// P3 展开态百分比圆环的纯格式化（可单测，无副作用）。
enum QuotaRingFormat {
    /// usedPercent(0–100) → 剩余比例(0–1)；nil → nil。
    static func remainingFraction(usedPercent: Double?) -> Double? {
        guard let used = usedPercent else { return nil }
        return max(0, 1 - used / 100)
    }

    /// 剩余比例 → 圆环颜色：>=0.3 emerald / >=0.1 amber / <0.1 rose / nil 白 0.35。
    static func ringColor(fraction: Double?) -> Color {
        guard let f = fraction else { return Color.white.opacity(0.35) }
        if f >= 0.3 { return StudioColor.emerald }
        if f >= 0.1 { return StudioColor.amber }
        return StudioColor.rose
    }

    /// 窗口短名：count>4 取 prefix(4)。
    static func shortWindowName(_ name: String) -> String {
        name.count > 4 ? String(name.prefix(4)) : name
    }

    /// resetsAt → "重置 MM/dd"；nil → ""。
    static func resetText(_ date: Date?, calendar: Calendar) -> String {
        guard let date else { return "" }
        let c = calendar.dateComponents([.month, .day], from: date)
        return String(format: "重置 %02d/%02d", c.month ?? 0, c.day ?? 0)
    }

    /// runsOutAt → "预计 Xh 耗尽"（h=ceil小时差）；已过 → "已耗尽"；nil → ""。
    static func exhaustionText(_ date: Date?, now: Date) -> String {
        guard let date else { return "" }
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "已耗尽" }
        let hours = Int(ceil(seconds / 3600))
        return "预计 \(hours)h 耗尽"
    }
}
