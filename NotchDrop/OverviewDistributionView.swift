//
//  OverviewDistributionView.swift
//  NotchEvery
//
//  第一页：今日用量（单行总览 + 24h 分时柱图 + 三维 Top 5）。
//

import SwiftUI

struct OverviewDistributionView: View {
    @ObservedObject var store: MagpieStore
    @StateObject private var copyFeedback = CopyFeedback()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredHour: Int?

    init(store: MagpieStore = .shared) {
        self.store = store
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            chartView
                .padding(.top, 8)

            if currentItems.isEmpty {
                emptyStateView
                    .padding(.top, 8)
            } else {
                rowsView
                    .padding(.top, 8)
            }

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

    // MARK: - Data

    private var currentItems: [DistributionItem] {
        store.snapshot.distributions[store.distributionDimension] ?? []
    }

    private var peakTokens: Int {
        store.snapshot.hourlyBuckets.map(\.netTokens).max() ?? 0
    }

    private var hoveredBucket: MagpieHourBucket? {
        guard let hoveredHour else { return nil }
        return store.snapshot.hourlyBuckets.first { $0.hour == hoveredHour }
    }

    private var currentTotalText: String {
        "当前总量 \(TokenFormatUtils.formatCompactTokens(store.snapshot.todayNetTokens))"
    }

    private var hoveredText: String? {
        guard let bucket = hoveredBucket else { return nil }
        let formatted = "\(String(format: "%02d", bucket.hour)):00 · \(bucket.netTokens) Tokens"
        guard let name = bucket.topProviderName, !name.isEmpty, bucket.netTokens > 0 else { return formatted }
        return formatted + " · \(name)"
    }

    static func baseSummaryText(netTokens: Int, cacheRate: Double?) -> String {
        var parts = [TokenFormatUtils.formatCompactTokens(netTokens)]
        if let cacheRate {
            parts.append("缓存 \(String(format: "%.1f%%", cacheRate * 100))")
        }
        return parts.joined(separator: " · ")
    }

    static func alertSummaryText(errorCount: Int, retriedSuccessCount: Int) -> String? {
        var parts: [String] = []
        if errorCount > 0 { parts.append("E \(errorCount)") }
        if retriedSuccessCount > 0 { parts.append("重试 \(retriedSuccessCount)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func barHeight(tokens: Int, peak: Int) -> CGFloat {
        guard peak > 0, tokens > 0 else { return 1 }
        return max(1, CGFloat(tokens) / CGFloat(peak) * 28)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(StudioColor.emerald)
                .frame(width: 6, height: 6)
            Text("今日用量")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(StudioInk.primary)

            HStack(spacing: 4) {
                Text(Self.baseSummaryText(
                    netTokens: store.snapshot.todayNetTokens,
                    cacheRate: store.snapshot.todayCacheRate
                ))
                if store.snapshot.todayMaskedValues > 0 {
                    Text("·")
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 9))
                    Text("\(store.snapshot.todayMaskedValues)")
                }
                if let alert = Self.alertSummaryText(
                    errorCount: store.snapshot.todayErrorCount,
                    retriedSuccessCount: store.snapshot.todayRetriedSuccessCount
                ) {
                    Text("· \(alert)")
                }
            }
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(StudioInk.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    // MARK: - 24h chart

    private var chartView: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                dimensionSwitcher

                Spacer(minLength: 4)

                Text(hoveredText ?? currentTotalText)
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(StudioInk.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            hourlyBars
                .frame(height: 28)
                .accessibilityLabel("今日 24 小时分时用量")

            HStack(alignment: .top) {
                ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                    Text(String(format: "%02d", hour))
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(StudioInk.axis)
                    if hour != 24 { Spacer(minLength: 0) }
                }
            }
        }
    }

    private var hourlyBars: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 1.5
            let width = max(0, (geo.size.width - spacing * 23) / 24)
            HStack(spacing: spacing) {
                ForEach(store.snapshot.hourlyBuckets, id: \.hour) { bucket in
                    bar(for: bucket, width: width)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func bar(for bucket: MagpieHourBucket, width: CGFloat) -> some View {
        let height = Self.barHeight(tokens: bucket.netTokens, peak: peakTokens)
        let primaryHeight = bucket.topProviderTokens > 0
            ? height * CGFloat(bucket.topProviderTokens) / CGFloat(max(1, bucket.netTokens))
            : 0
        VStack(spacing: 0) {
            if primaryHeight > 0 {
                Color.white.opacity(0.25).frame(height: height - primaryHeight)
                StudioColor.emerald.frame(height: primaryHeight)
            } else {
                Color.white.opacity(0.12).frame(height: height)
            }
        }
        .frame(width: width, height: 28, alignment: .bottom)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
                hoveredHour = hovering ? bucket.hour : nil
            }
        }
    }

    // MARK: - Dimension switcher

    private var dimensionSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(DistributionDimension.allCases) { dim in
                let selected = store.distributionDimension == dim
                Button {
                    if !reduceMotion {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            store.distributionDimension = dim
                        }
                    } else {
                        store.distributionDimension = dim
                    }
                } label: {
                    Text(dim.title)
                        .font(.system(size: 9.5, weight: selected ? .semibold : .regular).monospacedDigit())
                        .foregroundStyle(selected ? StudioInk.primary : StudioInk.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(selected ? Color.white.opacity(0.14) : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("维度：\(dim.title)")
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    // MARK: - Rows

    private var rowsView: some View {
        VStack(spacing: 4) {
            ForEach(Array(currentItems.prefix(5).enumerated()), id: \.element.id) { index, item in
                Button {
                    copyFeedback.copy(item.copyText, id: item.id)
                } label: {
                    DistributionRowView(
                        item: item,
                        index: index,
                        dimension: store.distributionDimension,
                        providerGroups: store.snapshot.providerGroups,
                        copied: copyFeedback.copiedID == item.id
                    )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel("复制 \(item.label)")
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        Group {
            if !store.snapshot.hasMagpieDirectory {
                Text("未检测到 Magpie 配置目录")
            } else if store.snapshot.todayRequestCount > 0 {
                Text("今日有请求，暂无可统计 Token 分布")
            } else {
                Text("今日暂无模型请求记录")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(StudioInk.secondary)
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    // MARK: - Footer

    private var footerView: some View {
        VStack(spacing: 6) {
            Rectangle()
                .fill(StudioMaterial.strokeNormal)
                .frame(height: 0.5)

            HStack {
                Text("缓存命中 \(TokenFormatUtils.formatCompactTokens(store.snapshot.todayCacheRead))")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(StudioInk.secondary)

                Spacer()

                if store.snapshot.todayMaskedValues > 0 {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(StudioInk.secondary)
                    Text("脱敏 \(store.snapshot.todayMaskedValues) 项 (\(store.snapshot.todayMaskedRequests) 次)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(StudioInk.secondary)
                }
            }
        }
    }
}

// MARK: - DistributionRowView

private struct DistributionRowView: View {
    let item: DistributionItem
    let index: Int
    let dimension: DistributionDimension
    let providerGroups: [MagpieProviderGroup]
    let copied: Bool

    @State private var isHovered = false

    private var accentColor: Color {
        switch index {
        case 0: return StudioColor.emerald
        case 1: return StudioColor.cyan
        case 2: return StudioColor.amber
        default: return StudioInk.secondary
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            leftColumn
                .frame(maxWidth: .infinity, alignment: .leading)

            rightColumn
                .frame(width: 178, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(
            isHovered ? StudioMaterial.cardHoverBackground : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var leftColumn: some View {
        switch dimension {
        case .combo: comboRow
        case .provider: providerRow
        case .group: groupRow
        }
    }

    private var comboRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(accentColor)
                .frame(width: 5, height: 5)
            Text(TokenFormatUtils.friendlyModelName(item.label))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(StudioInk.primary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .lineLimit(1)
            if let secondary = item.secondaryLabel {
                Text(secondary)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(StudioColor.cyan)
                    .lineLimit(1)
            }
        }
    }

    private var providerRow: some View {
        let icon = providerGroups.first { $0.id == item.id || $0.name == item.label }?.icon
        return HStack(spacing: 6) {
            ProviderIconView(icon: icon, providerID: item.id, size: 14)
            Text(item.label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(StudioInk.primary)
                .lineLimit(1)
            if let detail = item.detail {
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(StudioInk.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var groupRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(accentColor)
                .frame(width: 5, height: 5)
            Text(item.label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(StudioInk.primary)
                .lineLimit(1)
            if let secondary = item.secondaryLabel {
                Text(secondary)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(StudioColor.cyan)
                    .lineLimit(1)
            }
        }
    }

    private var rightColumn: some View {
        HStack(spacing: 4) {
            if copied {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(StudioColor.emerald)
                Text("已复制")
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(StudioColor.emerald)
            } else {
                Text(TokenFormatUtils.formatCompactTokens(item.tokenCount))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(StudioInk.primary)
                Text((item.tokensPerSecond.map { String(format: "%.0f", $0) } ?? "--") + " tok/s")
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(StudioInk.secondary)
                Text(cacheText)
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(item.cacheRead > 0 ? StudioColor.cyan : StudioInk.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private var cacheText: String {
        if item.cacheRead > 0 {
            return "缓存 \(TokenFormatUtils.formatCompactTokens(item.cacheRead))"
        }
        if let ttft = item.averageTTFTMs {
            return "首字 \(String(format: "%.1f", ttft / 1000.0))s"
        }
        return "无缓存"
    }
}
