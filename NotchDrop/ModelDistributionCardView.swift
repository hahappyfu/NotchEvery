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

            Text("\(TokenFormatUtils.formatCompactTokens(store.todayTotalTokens)) Tokens")
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
        // 整批先算一次显示名：短名是否唯一取决于同屏的其他行，不能按行独立决定；
        // 去前缀后再过 friendlyModelName，保住 Claude 系列的型号压缩
        let names = TokenFormatUtils.displayModelNames(store.modelUsages.map(\.model))
            .map(TokenFormatUtils.friendlyModelName)
        return VStack(spacing: 4) {
            ForEach(Array(store.modelUsages.prefix(5).enumerated()), id: \.element.id) { index, item in
                ModelRowView(item: item, index: index, displayName: names[index])
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
                Spacer()

                Text(activeModelsText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 活跃模型数与列表行数同源：超出前 5 时标明截断，避免「6 个模型 vs 5 行」的同屏矛盾
    private var activeModelsText: String {
        store.activeModelCount > 5
            ? "共 \(store.activeModelCount) 个活跃模型 · 显示前 5"
            : "共 \(store.activeModelCount) 个活跃模型"
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
    let displayName: String
    @State private var isHovered = false

    private var color: Color {
        modelPaletteColor(for: index)
    }

    var body: some View {
        HStack(spacing: 0) {
            // 1. 左栏（定宽 145pt，左侧对齐）
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)

                Text(displayName)
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

                Text(TokenFormatUtils.percentText(item.shareFraction))
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
