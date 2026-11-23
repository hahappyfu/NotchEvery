//
//  ProviderQuotaZoneView.swift
//  NotchEvery
//
//  第三页：供应商额度与限流状态（手风琴明细 / 水位条 / 签到 / 网关）。
//

import SwiftUI

struct ProviderQuotaZoneView: View {
    @ObservedObject var store: MagpieStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedProviderID: String?

    init(store: MagpieStore = .shared) {
        self.store = store
    }

    private var groups: [MagpieProviderGroup] { store.snapshot.providerGroups }
    private var now: Date { store.snapshot.refreshedAt }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            ScrollView {
                if groups.isEmpty {
                    Text("未检测到供应商数据")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    VStack(spacing: 4) {
                        ForEach(groups) { group in
                            providerSection(group)
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
            .padding(.top, 6)
            footerView
                .padding(.top, 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: IslandMetrics.pageWidth)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.035), lineWidth: 0.5)
        )
    }

    // MARK: - Header / Footer

    private var headerView: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(store.snapshot.activeAlertCount > 0 ? StudioColor.amber : StudioColor.emerald)
                .frame(width: 6, height: 6)
            Text("供应商额度与积分")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
            Spacer(minLength: 4)
            Text(store.snapshot.activeAlertCount > 0
                 ? "\(store.snapshot.activeAlertCount) 家受限"
                 : "点击行展开明细")
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(store.snapshot.activeAlertCount > 0 ? StudioColor.amber : Color.white.opacity(0.65))
                .lineLimit(1)
        }
    }

    private var footerView: some View {
        VStack(spacing: 6) {
            Rectangle()
                .fill(StudioMaterial.strokeNormal)
                .frame(height: 0.5)
            HStack(spacing: 6) {
                Text(ProviderQuotaFormat.checkinText(store.snapshot.checkin))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Circle()
                    .fill(gatewayOnline ? StudioColor.emerald : Color.gray)
                    .frame(width: 5, height: 5)
                Text(ProviderQuotaFormat.gatewayText(store.snapshot.gateway))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var gatewayOnline: Bool {
        if case .online = store.snapshot.gateway { return true }
        return false
    }

    // MARK: - Provider rows

    private func providerSection(_ group: MagpieProviderGroup) -> some View {
        let expanded = expandedProviderID == group.id
        return VStack(alignment: .leading, spacing: 0) {
            providerRow(group, expanded: expanded)
            if expanded {
                detailView(group)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                    .transition(reduceMotion ? .identity : .opacity)
            }
        }
        .background(
            expanded ? StudioMaterial.cardSelectedBackground : StudioMaterial.cardBackground,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }

    private func providerRow(_ group: MagpieProviderGroup, expanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle()
                    .fill(stateColor(group.limitState))
                    .frame(width: 5, height: 5)
                ProviderIconView(icon: group.icon, providerID: group.id, size: 13)
                Text(group.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if group.accounts.count > 1 {
                    Text("\(group.accounts.count) 账号")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(StudioColor.cyan)
                        .lineLimit(1)
                }
                if let badge = ProviderQuotaFormat.noticeBadge(group.limitState, now: now) {
                    badgeView(badge, state: group.limitState)
                }

                Spacer(minLength: 2)

                WaterLevelBar(fraction: group.fraction, active: group.limitState.isActive)
                    .frame(width: 54)
                Text(ProviderQuotaFormat.remainingText(group))
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
            }

            let details = summaryParts(group)
            if !details.isEmpty {
                Text(details.joined(separator: " · "))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                expandedProviderID = expanded ? nil : group.id
            }
        }
    }

    private func summaryParts(_ group: MagpieProviderGroup) -> [String] {
        var parts: [String] = []
        if let summary = ProviderQuotaFormat.accountSummary(group) { parts.append(summary) }
        if let mainWindow = group.accounts.compactMap({ $0.windows.first(where: { !$0.isAside }) ?? $0.windows.first }).first,
           let runsOutAt = mainWindow.runsOutAt
        {
            parts.append(ProviderQuotaFormat.countdown(runsOutAt, now: now))
        }
        if group.pendingCheckin { parts.append("可签到") }
        return parts
    }

    private func badgeView(_ text: String, state: ProviderLimitState) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .medium).monospacedDigit())
            .foregroundStyle(stateColor(state))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(stateColor(state).opacity(0.14), in: Capsule())
            .lineLimit(1)
    }

    private func stateColor(_ state: ProviderLimitState) -> Color {
        switch state {
        case .none: return StudioColor.emerald
        case .rateLimited: return StudioColor.amber
        case .cooling: return StudioColor.amber
        case .riskBlocked: return StudioColor.rose
        }
    }

    // MARK: - Accordion detail

    private func detailView(_ group: MagpieProviderGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(group.accounts) { account in
                accountDetail(account)
            }
        }
        .padding(.top, 4)
    }

    private func accountDetail(_ account: MagpieQuotaAccount) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(account.label)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
                if let plan = account.plan, !plan.isEmpty {
                    Text(plan)
                        .font(.system(size: 8.5))
                        .foregroundStyle(StudioColor.indigo)
                        .lineLimit(1)
                }
                if let message = account.noticeMessage, !message.isEmpty {
                    badgeView(ProviderQuotaFormat.noticeBadge(account.limitState, now: now) ?? "告警", state: account.limitState)
                }
            }

            ForEach(account.windows) { window in
                windowRow(window)
            }

            if let history = account.windows.first(where: { !$0.isAside })?.history,
               !history.isEmpty
            {
                Sparkline(history: history)
                    .frame(width: 48, height: 12)
            }

            if let message = account.noticeMessage, !message.isEmpty {
                Text(message)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }

    private func windowRow(_ window: MagpieWindow) -> some View {
        HStack(spacing: 5) {
            Text(window.name)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            WaterLevelBar(fraction: window.usedPercent.map { $0 / 100 })
                .frame(width: 40)
            Text(windowText(window))
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.75))
                .lineLimit(1)
            if let resetText = resetText(window) {
                Text(resetText)
                    .font(.system(size: 8.5).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func windowText(_ window: MagpieWindow) -> String {
        ProviderQuotaFormat.windowUsage(window)
    }

    private func resetText(_ window: MagpieWindow) -> String? {
        if let runsOutAt = window.runsOutAt {
            return ProviderQuotaFormat.countdown(runsOutAt, now: now)
        }
        if let resetsAt = window.resetsAt {
            return ProviderQuotaFormat.countdown(resetsAt, now: now)
        }
        return nil
    }
}

// MARK: - Water level

private struct WaterLevelBar: View {
    let fraction: Double?
    var active = false

    var body: some View {
        GeometryReader { geo in
            let value = ProviderQuotaFormat.barFill(fraction)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(value))
            }
        }
        .frame(height: 4)
    }

    private var color: Color {
        guard fraction != nil else { return Color.white.opacity(0.35) }
        if active { return StudioColor.amber }
        return (fraction ?? 0) > 0.2 ? StudioColor.emerald : StudioColor.rose
    }
}

// MARK: - Sparkline（纯 Path，最近 20 点，0–100 映射）
// shortcut: 趋势仅取最近 20 点并线性映射 0–100，窗口历史口径变化时需调整

private struct Sparkline: View {
    let history: [Double]

    var body: some View {
        let points = Array(history.suffix(20))
        Path { path in
            guard points.count > 1 else { return }
            let step = 48 / CGFloat(points.count - 1)
            for (index, value) in points.enumerated() {
                let y = 12 - 12 * CGFloat(min(max(value / 100, 0), 1))
                let point = CGPoint(x: CGFloat(index) * step, y: y)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
        .stroke(StudioColor.cyan.opacity(0.8), lineWidth: 1)
    }
}
