//
//  TokenZoneView.swift
//  NotchDrop
//
//  Token 分区：模型请求记录表（真数据来自 UsageStore 的 cc-switch 统计，见 ADR-0005）。
//

import SwiftUI

/// 单条模型请求（真数据来自 cc-switch 使用统计）。
struct TokenRequest: Identifiable, Equatable {
    /// cc-switch 的 request_id（稳定标识，滚动动画依赖）
    let id: String
    let time: String
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    /// 耗时存数值（秒），展示层格式化，避免反解析字符串
    let durationSeconds: Double
    let cost: String
    let status: Int
}

/// KPI 聚合（真数据来自 UsageStore）。
struct TokenSummary: Equatable {
    let totalTokens: String
    let cacheRate: String
    let calls: String
    let cost: String

    static let empty = TokenSummary(totalTokens: "0", cacheRate: "0.0%", calls: "0次", cost: "$0.00")
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
    status >= 400 ? Color(red: 0.75, green: 0.20, blue: 0.18) : Color(red: 0.16, green: 0.55, blue: 0.32)
}

private struct TokenRowView: View {
    let row: TokenRequest
    let timeW: CGFloat
    let modelW: CGFloat
    let durationW: CGFloat
    let statusW: CGFloat
    /// 刚插入的新行：播一次绿闪渐隐
    var isNew: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var flashOpacity: Double = 0

    var body: some View {
        HStack(spacing: 8) {
            Text(row.time)
                .frame(width: timeW, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(row.model)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: modelW, alignment: .leading)
            Text("\(row.inputTokens.formatted()) / \(row.outputTokens.formatted())")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(String(format: "%.1fs", row.durationSeconds))
                .frame(width: durationW, alignment: .trailing)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Circle()
                    .fill(tokenStatusColor(row.status))
                    .frame(width: 6, height: 6)
                Text("\(row.status)")
                    .foregroundStyle(row.status >= 400 ? tokenStatusColor(row.status) : .secondary)
            }
            .frame(width: statusW, alignment: .trailing)
        }
        .font(.system(size: 11))
        .monospacedDigit()
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(hovering ? Color.white.opacity(0.04) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .background(Color.green.opacity(flashOpacity), in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
        .onAppear {
            // 新行入场：绿闪一下后渐隐（B 柔闪）；reduceMotion 下不闪
            guard isNew, !reduceMotion else { return }
            flashOpacity = 0.16
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.9)) { flashOpacity = 0 }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.5))
                .frame(height: 0.5)
        }
    }
}

struct TokenZoneView: View {
    @StateObject private var store = UsageStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 首行 id 追踪：只对新插入的行播绿闪（首帧不闪）
    @State private var lastFirstID: String?

    /// 列宽（header 与行共用同一组，保证对齐；文本列左对齐，数字列右对齐）
    private let timeW: CGFloat = 40
    private let modelW: CGFloat = 100
    private let durationW: CGFloat = 48
    private let statusW: CGFloat = 38

    var body: some View {
        VStack(spacing: 0) {
            summaryBar
            header
            VStack(spacing: 0) {
                ForEach(store.recentRequests.prefix(5)) { row in
                    TokenRowView(
                        row: row, timeW: timeW, modelW: modelW, durationW: durationW, statusW: statusW,
                        isNew: lastFirstID != nil
                            && row.id == store.recentRequests.first?.id
                            && row.id != lastFirstID
                    )
                    .transition(reduceMotion ? .identity : .opacity)
                }
            }
            // 上下渐隐遮罩：行进不出硬边（B 柔闪配套）
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.03),
                        .init(color: .black, location: 0.97),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: store.recentRequests)
            footer
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .onChange(of: store.recentRequests) { rows in
            if let first = rows.first, first.id != lastFirstID { lastFirstID = first.id }
        }
    }

    private var summaryBar: some View {
        HStack {
            HStack(spacing: 6) {
                Text("Tokens")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                RollupText(text: store.summary.totalTokens)
            }
            Spacer()
            HStack(spacing: 6) {
                Text("缓存命中率")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
                RollupText(text: store.summary.cacheRate, font: .system(size: 12, weight: .bold), color: .green)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.green.opacity(0.2))
                        .frame(width: 64, height: 6)
                    Capsule()
                        .fill(Color.green)
                        .frame(width: 64 * min(1, max(0, store.cacheRateFraction)), height: 6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.green.opacity(0.20), lineWidth: 1))
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1))
        .padding(.bottom, 10)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("时间").frame(width: timeW, alignment: .leading)
            Text("模型").frame(width: modelW, alignment: .leading)
            Text("入 / 出").frame(maxWidth: .infinity, alignment: .trailing)
            Text("用时").frame(width: durationW, alignment: .trailing)
            Text("状态").frame(width: statusW, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.5))
                .frame(height: 0.5)
        }
        .padding(.bottom, 4)
    }
    private var footer: some View {
        VStack(spacing: 10) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.5))
                .frame(height: 0.5)
            HStack {
                Circle()
                    .fill(store.footer.cacheReadTotal > 0 ? Color.green : Color.secondary)
                    .frame(width: 6, height: 6)
                Text("缓存命中 \(UsageStore.formatTokens(store.footer.cacheReadTotal)) · 省 \(UsageStore.formatCost(usd: store.footer.savedUSD, priced: true))")
                Spacer()
                Text("更新于 \(footerTimeText)")
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .padding(.top, 10)
    }

    private var footerTimeText: String {
        guard let at = store.footer.lastRequestAt else { return "--:--" }
        return Self.footerFormatter.string(from: at)
    }

    private static let footerFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

#Preview {
    TokenZoneView()
        .padding()
        .frame(width: 600)
        .background(.ultraThinMaterial)
}
