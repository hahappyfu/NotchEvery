//
//  ModelDistributionCardView.swift
//  NotchEvery
//
//  Apple Native Studio 工业级设计规范：今日模型用量分布卡片。
//

import SwiftUI

public struct ModelDistributionCardView: View {
    @ObservedObject var store: UsageStore

    public init(store: UsageStore = .shared) {
        self.store = store
    }

    private var dayTotalTokens: Int {
        store.modelUsages.reduce(0) { $0 + $1.totalTokens }
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerView

            segmentedBarView
                .padding(.top, 8)

            if store.modelUsages.isEmpty {
                emptyStateView
                    .padding(.top, 8)
            } else {
                modelListView
                    .padding(.top, 8)
            }

            footerView
                .padding(.top, 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 410)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.035), lineWidth: 0.5)
        )
    }

    // MARK: - Header
    private var headerView: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(StudioColor.emerald)
                    .frame(width: 6, height: 6)
                Text("今日模型用量分布")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
            }

            Spacer()

            Text("\(TokenFormatUtils.formatCompactTokens(dayTotalTokens)) Tokens")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Segmented Proportion Bar
    private var segmentedBarView: some View {
        SegmentedProportionBar(items: store.modelUsages)
    }

    // MARK: - Model List
    private var modelListView: some View {
        VStack(spacing: 4) {
            ForEach(Array(store.modelUsages.prefix(5).enumerated()), id: \.element.id) { index, item in
                ModelRowView(item: item, index: index)
            }
        }
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        Text("今日暂无模型请求记录")
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
                Text(String(format: "今日花费 $%.2f", store.totalCostTodayUSD))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("共 \(store.modelUsages.count) 个活跃模型")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Palette Color Mapping
func modelPaletteColor(for index: Int) -> Color {
    switch index {
    case 0:
        return StudioColor.emerald
    case 1:
        return Color(red: 90/255, green: 200/255, blue: 250/255)
    case 2:
        return Color(red: 175/255, green: 82/255, blue: 222/255)
    case 3:
        return StudioColor.amber
    default:
        return Color.white.opacity(0.35)
    }
}

// MARK: - Segmented Proportion Bar Component
private struct SegmentedProportionBar: View {
    let items: [ModelUsageItem]

    private var validItems: [ModelUsageItem] {
        items.filter { $0.totalTokens > 0 && $0.shareFraction > 0 }
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
                        let w = max(4.0, rawW)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(modelPaletteColor(for: index))
                            .frame(width: w, height: 6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                )
                .clipShape(Capsule())
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Model Row View
private struct ModelRowView: View {
    let item: ModelUsageItem
    let index: Int
    @State private var isHovered = false

    private var color: Color {
        modelPaletteColor(for: index)
    }

    private var costText: String? {
        guard item.costUSD > 0 else { return nil }
        if item.costUSD >= 0.01 {
            return String(format: "$%.2f", item.costUSD)
        } else {
            return String(format: "$%.3f", item.costUSD)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // 1. 左栏（定宽 145pt，左侧对齐）
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)

                Text(TokenFormatUtils.friendlyModelName(item.model))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .lineLimit(1)
            }
            .padding(.leading, 3)
            .frame(width: 145, alignment: .leading)

            // 2. 中栏（定宽 160pt，显示总消耗与占比）
            HStack(spacing: 6) {
                Text(TokenFormatUtils.formatCompactTokens(item.totalTokens))
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)

                Text(String(format: "%.1f%%", item.shareFraction * 100))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(color)
            }
            .frame(width: 160, alignment: .leading)

            Spacer(minLength: 0)

            // 3. 右栏（定宽 75pt，右对齐）
            HStack(spacing: 4) {
                Text("\(item.calls)次")
                    .font(.system(size: 9.5).monospacedDigit())
                    .foregroundStyle(.secondary)

                if let cost = costText {
                    Text(cost)
                        .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.trailing, 3)
            .frame(width: 75, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(
            isHovered ? StudioMaterial.cardHoverBackground : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .onHover { isHovered = $0 }
    }
}
