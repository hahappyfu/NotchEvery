//
//  TokenZoneView.swift
//  NotchDrop
//
//  Token 分区：模型请求记录表（真数据来自 UsageStore 的 cc-switch 统计，见 ADR-0005）。
//

import SwiftUI

/// 单条模型请求（真数据来自 cc-switch 或 antigravity-tools 使用统计）。
public struct TokenRequest: Identifiable, Equatable {
    /// cc-switch 的 request_id 或 antigravity 的 id（稳定标识，滚动动画依赖）
    public let id: String
    public let time: String
    public let model: String
    public let inputTokens: Int
    public let outputTokens: Int
    /// 耗时存数值（秒），展示层格式化，避免反解析字符串
    public let durationSeconds: Double
    public let cost: String
    public let status: Int
    public var accountEmail: String?
    public let cachedTokens: Int

    public init(
        id: String,
        time: String,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        durationSeconds: Double,
        cost: String,
        status: Int,
        accountEmail: String? = nil,
        cachedTokens: Int = 0
    ) {
        self.id = id
        self.time = time
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.durationSeconds = durationSeconds
        self.cost = cost
        self.status = status
        self.accountEmail = accountEmail
        self.cachedTokens = cachedTokens
    }

    /// 友好的账号显示名称（从 AntigravityStore 匹配别名，若无则提取邮箱用户名）
    public var friendlyAccountName: String {
        guard let email = accountEmail, !email.isEmpty else { return "" }
        let lower = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let matched = AntigravityStore.shared.accounts.first(where: { $0.email.lowercased() == lower }) {
            return matched.name
        }
        if let atIndex = lower.firstIndex(of: "@") {
            return String(lower[..<atIndex])
        }
        return lower
    }

    /// 账号邮箱前缀
    public var accountEmailPrefix: String {
        guard let email = accountEmail, !email.isEmpty else { return "" }
        let lower = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let atIndex = lower.firstIndex(of: "@") {
            return String(lower[..<atIndex])
        }
        return lower
    }
}

/// KPI 聚合（真数据来自 UsageStore）。
public struct TokenSummary: Equatable {
    public let totalTokens: String
    public let cacheRate: String
    public let calls: String
    public let cost: String

    public init(totalTokens: String, cacheRate: String, calls: String, cost: String) {
        self.totalTokens = totalTokens
        self.cacheRate = cacheRate
        self.calls = calls
        self.cost = cost
    }

    public static let empty = TokenSummary(totalTokens: "0", cacheRate: "0.0%", calls: "0次", cost: "$0.00")
}

/// 数字变化时的滚动过渡：老值上滑出、新值滑入（reduceMotion 降级为直替）。
struct RollupText: View {
    let text: String
    var font: Font = .system(size: 14, weight: .bold)
    var color: Color = .primary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Text(text)
                .font(font.monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .id(text)
                .transition(reduceMotion ? .identity : .asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
        }
        .clipped()
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85), value: text)
    }
}
private func tokenStatusColor(_ status: Int) -> Color {
    // 状态色：圆点 + 文字用色（白字实心 pill 已删）
    status >= 400 ? StudioColor.rose : StudioColor.emerald
}

private struct TokenRowView: View {
    let row: TokenRequest
    /// 刚插入的新行：播一次绿闪渐隐
    var isNew: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var flashOpacity: Double = 0

    private let colIdentityW: CGFloat = 145
    private let colTokensW: CGFloat = 160
    private let colTimingW: CGFloat = 75

    private var cacheFraction: Double {
        TokenFormatUtils.cacheRateFraction(cached: row.cachedTokens, input: row.inputTokens)
    }

    private var cacheTier: TokenFormatUtils.CacheRateTier {
        TokenFormatUtils.cacheRateTier(fraction: cacheFraction)
    }

    private var cacheColor: Color {
        switch cacheTier {
        case .high:
            return StudioColor.emerald
        case .medium:
            return Color(red: 90/255, green: 200/255, blue: 250/255) // 科技青蓝
        case .low:
            return StudioColor.amber
        case .none:
            return Color.white.opacity(0.25)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // 1. 左栏：身份（定宽 145，左对齐）
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(TokenFormatUtils.friendlyModelName(row.model))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        .lineLimit(1)

                    Text(row.friendlyAccountName)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .lineLimit(1)
                }
                Text(row.accountEmailPrefix.isEmpty ? row.time : row.accountEmailPrefix)
                    .font(.system(size: 9.5).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(width: colIdentityW, alignment: .leading)

            // 2. 中栏：Token 构成与缓存命中（定宽 160，水平居中）
            VStack(spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    let total = row.inputTokens + row.outputTokens
                    Text(TokenFormatUtils.formatCompactTokens(total))
                        .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)

                    Spacer()

                    if cacheFraction > 0 {
                        Text("缓存 \(Int(cacheFraction * 100))%")
                            .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(cacheColor)
                    } else {
                        Text("无缓存")
                            .font(.system(size: 9.5).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }

                // 微型缓存命中胶囊比例条
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: colTokensW, height: 3)
                    if cacheFraction > 0 {
                        Capsule()
                            .fill(cacheColor)
                            .frame(width: max(4, colTokensW * CGFloat(cacheFraction)), height: 3)
                    }
                }
                .frame(width: colTokensW, height: 3)

                HStack {
                    Text("入 \(TokenFormatUtils.formatCompactTokens(row.inputTokens))")
                    Spacer()
                    Text("出 \(TokenFormatUtils.formatCompactTokens(row.outputTokens))")
                }
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.tertiary)
            }
            .frame(width: colTokensW)
            .padding(.horizontal, 10)

            // 3. 右栏：耗时与时间（定宽 75，右对齐）
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text(String(format: "%.1fs", row.durationSeconds))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)

                    Circle()
                        .fill(tokenStatusColor(row.status))
                        .frame(width: 5, height: 5)
                }

                Text(row.time)
                    .font(.system(size: 9.5).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .frame(width: colTimingW, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 410)
        .contentShape(Rectangle())
        .background(hovering ? StudioMaterial.cardHoverBackground : Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white.opacity(0.035), lineWidth: 0.5))
        .background(StudioColor.emerald.opacity(flashOpacity), in: RoundedRectangle(cornerRadius: 9))
        .onHover { hovering = $0 }
        .onAppear {
            // 新行入场：绿闪一下后渐隐；reduceMotion 下不闪
            guard isNew, !reduceMotion else { return }
            flashOpacity = 0.16
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.9)) { flashOpacity = 0 }
            }
        }
    }
}

struct TokenZoneView: View {
    @StateObject private var store = UsageStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 首行 id 追踪：只对新插入的行播绿闪（首帧不闪）
    @State private var lastFirstID: String?

    var body: some View {
        VStack(spacing: 5) {
            liveBar

            if store.recentRequests.isEmpty {
                Text("暂无近期请求日志")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(spacing: 5) {
                    ForEach(store.recentRequests.prefix(5)) { row in
                        TokenRowView(
                            row: row,
                            isNew: lastFirstID != nil
                                && row.id == store.recentRequests.first?.id
                                && row.id != lastFirstID
                        )
                        .transition(reduceMotion ? .identity : .opacity)
                    }
                }
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.02),
                            .init(color: .black, location: 0.98),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: store.recentRequests)
            }
        }
        .frame(width: 410)
        .padding(.vertical, 4)
        .onChange(of: store.recentRequests) { rows in
            if let first = rows.first, first.id != lastFirstID { lastFirstID = first.id }
        }
    }

    private var liveBar: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(StudioColor.emerald)
                    .frame(width: 6, height: 6)
                Text("最近 5 笔请求流水")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            Spacer()
            Text("模型/账号 · 缓存率分级 · 耗时")
                .font(.system(size: 9.5))
                .foregroundStyle(Color.white.opacity(0.4))
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(StudioMaterial.strokeNormal)
                .frame(height: 0.5)
        }
        .padding(.bottom, 4)
    }
}

#Preview {
    TokenZoneView()
        .padding()
        .frame(width: 600)
        .background(.ultraThinMaterial)
}
