//
//  ProviderQuotaFormat.swift
//  NotchEvery
//
//  供应商额度页的纯文案格式化：可单测，无副作用。
//

import Foundation

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

    static func fmt(_ value: Double) -> String {
        let text = String(format: "%.1f", value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}
