//
//  EarSummary.swift
//  NotchEvery
//
//  三页耳区纯文案格式化：可单测，无副作用。
//  左耳/右耳分别按当前页返回要展示的文案与告警计数。
//

import Foundation

enum EarSummary {
    /// P1 左耳：当前维度下活跃条目计数（0 → nil 由视图整只隐藏）。
    static func overviewLeft(dimension: DistributionDimension, snapshot: MagpieSnapshot) -> String? {
        let count = snapshot.distributions[dimension]?.count ?? 0
        guard count > 0 else { return nil }
        switch dimension {
        case .combo: return "\(count) 个活跃组合"
        case .provider: return "\(count) 家提供商"
        case .group: return "\(count) 个路由组"
        }
    }

    /// P1 右耳：今日最新请求时间（无则 nil）+ 活跃告警数。
    static func overviewRight(snapshot: MagpieSnapshot, calendar: Calendar = .current) -> (time: String?, alerts: Int) {
        let time: String?
        if let last = snapshot.lastRequestAt {
            let c = calendar.dateComponents([.hour, .minute], from: last)
            time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        } else {
            time = nil
        }
        return (time, snapshot.activeAlertCount)
    }

    /// P2 左耳：最近一笔的提供商显示名（按稳定 providerID 查组名，找不到用展示名）；无流水 → nil。
    static func flowLeft(snapshot: MagpieSnapshot) -> String? {
        guard let first = snapshot.recentFlows.first else { return nil }
        if let name = snapshot.providerGroups.first(where: { $0.id == first.providerID })?.name, !name.isEmpty {
            return name
        }
        return first.providerName
    }

    /// P2 右耳：今日总请求（紧凑格式 + " 次"）+ 活跃告警数。
    static func flowRight(snapshot: MagpieSnapshot) -> (requests: String, alerts: Int) {
        (TokenFormatUtils.formatCompactTokens(snapshot.todayRequestCount) + " 次", snapshot.activeAlertCount)
    }

    /// P3 左耳：受限告警态（N 家受限）或正常态（N 家供应商）。
    static func providersLeft(snapshot: MagpieSnapshot) -> (text: String, hasAlert: Bool) {
        let alertGroups = snapshot.providerGroups.filter { $0.limitState.isActive }.count
        let hasAlert = alertGroups > 0
        let text = hasAlert ? "\(alertGroups) 家受限" : "\(snapshot.providerGroups.count) 家供应商"
        return (text, hasAlert)
    }

    /// P3 右耳：今日签到总加分（> 0 才显示）+ 活跃告警数。
    static func providersRight(snapshot: MagpieSnapshot) -> (checkin: String?, alerts: Int) {
        let checkin = snapshot.checkin.totalCredit > 0
            ? "签到 +\(Int(snapshot.checkin.totalCredit.rounded()))"
            : nil
        return (checkin, snapshot.activeAlertCount)
    }
}
