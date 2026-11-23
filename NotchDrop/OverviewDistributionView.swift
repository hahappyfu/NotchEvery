//
//  OverviewDistributionView.swift
//  NotchEvery
//
//  第一页：今日用量分布（模型·提供商 / 提供商 / Group 三维切换）。
//

import SwiftUI

struct OverviewDistributionView: View {
    @ObservedObject var store: MagpieStore
    @StateObject private var copyFeedback = CopyFeedback()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: MagpieStore = .shared) {
        self.store = store
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            dimensionSwitcher
                .padding(.top, 6)
            DistributionBar(items: currentItems)
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

    private var netTokensText: String {
        let n = store.snapshot.todayNetTokens
        return n > 0 ? TokenFormatUtils.formatCompactTokens(n) : "—"
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(StudioColor.emerald)
                    .frame(width: 6, height: 6)
                Text("今日用量分布")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
            }

            Spacer()

            Text(netTokensText)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Dimension switcher

    private var dimensionSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(DistributionDimension.allCases) { dim in
                let selected = store.distributionDimension == dim
                Text(dim.title)
                    .font(.system(size: 9.5, weight: selected ? .semibold : .regular).monospacedDigit())
                    .foregroundStyle(selected ? .white : Color.white.opacity(0.5))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(selected ? Color.white.opacity(0.14) : Color.clear)
                    )
                    .contentShape(Capsule())
                    .onTapGesture {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82)) {
                            store.distributionDimension = dim
                        }
                    }
            }
        }
    }

    // MARK: - Rows

    private var rowsView: some View {
        let items = Array(currentItems.prefix(5).enumerated())
        return VStack(spacing: 4) {
            ForEach(items, id: \.element.id) { index, item in
                DistributionRowView(
                    item: item,
                    index: index,
                    dimension: store.distributionDimension,
                    providerGroups: store.snapshot.providerGroups,
                    copied: copyFeedback.copiedID == item.id
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    copyFeedback.copy(item.copyText, id: item.id)
                }
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
        .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)

                Spacer()

                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)

                Text("今日脱敏 \(store.snapshot.todayMaskedValues) 项 (\(store.snapshot.todayMaskedRequests) 次)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Palette (沿用旧 modelPaletteColor 配色)

private func distributionPaletteColor(for index: Int) -> Color {
    switch index {
    case 0: return StudioColor.emerald
    case 1: return Color(red: 90 / 255, green: 200 / 255, blue: 250 / 255)
    case 2: return Color(red: 175 / 255, green: 82 / 255, blue: 222 / 255)
    case 3: return StudioColor.amber
    default: return Color.white.opacity(0.35)
    }
}

// MARK: - DistributionBar (segmented proportion bar)

private struct DistributionBar: View {
    let items: [DistributionItem]

    private var validItems: [DistributionItem] {
        items.filter { $0.tokenCount > 0 && $0.shareFraction > 0 }
    }

    var body: some View {
        GeometryReader { geo in
            let totalW = geo.size.width
            if validItems.isEmpty {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 6)
            } else {
                let spacing: CGFloat = 1.5
                let count = validItems.count
                let totalSpacing = CGFloat(max(0, count - 1)) * spacing
                let availableW = max(0, totalW - totalSpacing)

                HStack(spacing: spacing) {
                    ForEach(Array(validItems.enumerated()), id: \.element.id) { index, item in
                        let rawW = availableW * CGFloat(item.shareFraction)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(distributionPaletteColor(for: index))
                            .frame(width: max(4.0, rawW), height: 6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .clipShape(Capsule())
            }
        }
        .frame(height: 6)
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
        distributionPaletteColor(for: index)
    }

    var body: some View {
        HStack(spacing: 0) {
            leftColumn
                .frame(maxWidth: .infinity, alignment: .leading)

            rightColumn
                .frame(width: 150, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(
            isHovered ? StudioMaterial.cardHoverBackground : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .onHover { isHovered = $0 }
    }

    // MARK: Left column per dimension

    @ViewBuilder
    private var leftColumn: some View {
        switch dimension {
        case .combo:
            comboRow
        case .provider:
            providerRow
        case .group:
            groupRow
        }
    }

    private var comboRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(accentColor)
                .frame(width: 5, height: 5)

            Text(TokenFormatUtils.friendlyModelName(item.label))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .lineLimit(1)

            if let secondary = item.secondaryLabel {
                Text(secondary)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(StudioColor.cyan.opacity(0.8))
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
                .foregroundStyle(.white)
                .lineLimit(1)

            if let detail = item.detail {
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(.white)
                .lineLimit(1)

            if let secondary = item.secondaryLabel {
                Text(secondary)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(StudioColor.cyan.opacity(0.8))
                    .lineLimit(1)
            }
        }
    }

    // MARK: Right column (metrics)

    private var rightColumn: some View {
        HStack(spacing: 5) {
            if copied {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(StudioColor.emerald)
                Text("已复制")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(StudioColor.emerald)
            } else {
                Text(TokenFormatUtils.percentText(item.shareFraction))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(accentColor)

                Text(TokenFormatUtils.formatCompactTokens(item.tokenCount))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)

                Text(cacheText)
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(item.cacheRead > 0 ? StudioColor.cyan : .secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var cacheText: String {
        item.cacheRead == 0 ? "无缓存" : TokenFormatUtils.formatCompactTokens(item.cacheRead) + " 缓存"
    }
}
