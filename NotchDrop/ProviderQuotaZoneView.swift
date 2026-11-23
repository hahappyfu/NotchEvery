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
                        .foregroundStyle(StudioInk.secondary)
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
            Text("供应商额度")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(StudioInk.primary)
            Spacer(minLength: 4)
            Text(store.snapshot.activeAlertCount > 0
                 ? "\(store.snapshot.activeAlertCount) 家受限"
                 : "点击行展开明细")
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(store.snapshot.activeAlertCount > 0 ? StudioColor.amber : StudioInk.secondary)
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
                    .foregroundStyle(StudioInk.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Circle()
                    .fill(gatewayOnline ? StudioColor.emerald : Color.gray)
                    .frame(width: 5, height: 5)
                Text(ProviderQuotaFormat.gatewayText(store.snapshot.gateway))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(StudioInk.secondary)
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
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                    expandedProviderID = expanded ? nil : group.id
                }
            } label: {
                providerRow(group, expanded: expanded)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("展开 \(group.name)")

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
                    .foregroundStyle(StudioInk.primary)
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

                trackView(group)
                Text(ProviderQuotaFormat.remainingText(group))
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(StudioInk.primary)
                    .lineLimit(1)
            }

            let details = summaryParts(group)
            if !details.isEmpty {
                Text(details.joined(separator: " · "))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(StudioInk.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    /// 折叠行右侧轨道：有刻度用水位条（语义=剩余比例），无刻度画虚线轨道。
    /// 「无刻度」文案由右侧 remainingText 统一给出，此处不再重复。
    private func trackView(_ group: MagpieProviderGroup) -> some View {
        if group.fraction == nil {
            return AnyView(
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(
                        StudioInk.axis.opacity(0.5),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
                    .frame(width: 40, height: 5)
            )
        }
        return AnyView(
            WaterLevelBar(fraction: group.fraction, active: group.limitState.isActive)
                .frame(width: 54)
        )
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

    // MARK: - Accordion detail（单账号卡片：左区信息 + 右区 1–3 枚百分比圆环）

    private func detailView(_ group: MagpieProviderGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(group.accounts) { account in
                accountCard(account)
            }
        }
        .padding(.top, 4)
    }

    private func accountCard(_ account: MagpieQuotaAccount) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // 左区：别名 + 套餐 + 虚线 Sparkline + 重置/耗尽 + 活跃限流摘要
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(account.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(StudioInk.primary)
                        .lineLimit(1)
                    if let plan = account.plan, !plan.isEmpty {
                        Text(plan)
                            .font(.system(size: 9.5))
                            .foregroundStyle(StudioInk.secondary)
                            .lineLimit(1)
                    }
                }

                dashedSparkline(account)

                Text(resetAndExhaustionText(account))
                    .font(.system(size: 9.5).monospacedDigit())
                    .foregroundStyle(StudioInk.secondary)
                    .lineLimit(1)

                if account.limitState.isActive, let message = account.noticeMessage, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 9))
                        .foregroundStyle(account.limitState.severity >= 3 ? StudioColor.rose : StudioColor.amber)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 右区：横向并排 1–3 枚 26pt 百分比小圆环
            HStack(spacing: 8) {
                ForEach(ringWindows(account)) { window in
                    quotaRing(window)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// 主窗口历史虚线 Sparkline（宽 96 高 24，不足 2 点显示 —）。
    private func dashedSparkline(_ account: MagpieQuotaAccount) -> some View {
        let history = Array((account.windows.first(where: { !$0.isAside }) ?? account.windows.first)?.history ?? []).suffix(24)
        return Group {
            if history.count >= 2 {
                Path { path in
                    let step = 96 / CGFloat(history.count - 1)
                    for (index, value) in history.enumerated() {
                        let y = 24 - 24 * CGFloat(min(max(value / 100, 0), 1))
                        let point = CGPoint(x: CGFloat(index) * step, y: y)
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }
                .stroke(StudioColor.emerald, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .frame(width: 96, height: 24)
            } else {
                Text("—")
                    .font(.system(size: 11))
                    .foregroundStyle(StudioInk.axis)
                    .frame(width: 96, height: 24, alignment: .leading)
            }
        }
    }

    /// "重置 MM/dd · 预计 Xh 耗尽"，两段都空时不渲染文字（外层 lineLimit 已隐藏空串）。
    private func resetAndExhaustionText(_ account: MagpieQuotaAccount) -> String {
        let mainWindow = account.windows.first(where: { !$0.isAside }) ?? account.windows.first
        var parts: [String] = []
        let reset = QuotaRingFormat.resetText(mainWindow?.resetsAt, calendar: Calendar.current)
        if !reset.isEmpty { parts.append(reset) }
        let exhaustion = QuotaRingFormat.exhaustionText(mainWindow?.runsOutAt, now: now)
        if !exhaustion.isEmpty { parts.append(exhaustion) }
        return parts.joined(separator: " · ")
    }

    /// 圆环窗口顺序：主窗口（非 aside 第一个）在前，其余依序，最多 3 枚。
    private func ringWindows(_ account: MagpieQuotaAccount) -> [MagpieWindow] {
        let main = account.windows.first(where: { !$0.isAside })
        let rest = account.windows.filter { $0.id != main?.id }
        let ordered = (main.map { [$0] } ?? []) + rest
        return Array(ordered.prefix(3))
    }

    /// 26pt 百分比小圆环：12 点起顺时针，中心 .monospacedDigit() 百分比，下方窗口短名。
    private func quotaRing(_ window: MagpieWindow) -> some View {
        let fraction = QuotaRingFormat.remainingFraction(usedPercent: window.usedPercent)
        let color = QuotaRingFormat.ringColor(fraction: fraction)
        let centerText = fraction.map { "\(Int(round($0 * 100)))%" } ?? "--"

        return VStack(spacing: 2) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 2.5)
                if let f = fraction {
                    Circle()
                        .trim(from: 0, to: max(0.001, f))
                        .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Text(centerText)
                    .font(.system(size: 7.5).monospacedDigit())
                    .foregroundStyle(fraction == nil ? StudioInk.axis : color)
            }
            .frame(width: 26, height: 26)
            Text(QuotaRingFormat.shortWindowName(window.name))
                .font(.system(size: 8.5))
                .foregroundStyle(StudioInk.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Water level（语义=剩余比例，0..1；nil → 不填充）

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
