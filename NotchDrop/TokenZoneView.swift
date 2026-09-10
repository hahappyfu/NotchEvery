//
//  TokenZoneView.swift
//  NotchDrop
//
//  Token 分区：模型请求记录表（mock 先行，数据源后接，见 ADR-0005）。
//

import SwiftUI

/// 单条模型请求（mock 同构截图数据；接数据源时替换构造处）。
struct TokenRequest: Identifiable {
    let id = UUID()
    let time: String
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    /// 耗时存数值（秒），展示层格式化，避免反解析字符串
    let durationSeconds: Double
    let cost: String
    let status: Int
    let cached: Bool

    static let mock: [TokenRequest] = [
        .init(time: "14:46", model: "opus-5", inputTokens: 524, outputTokens: 283, durationSeconds: 26.8, cost: "未定价", status: 200, cached: true),
        .init(time: "14:45", model: "opus-5", inputTokens: 538, outputTokens: 185, durationSeconds: 19.3, cost: "未定价", status: 200, cached: true),
        .init(time: "14:44", model: "opus-5", inputTokens: 2977, outputTokens: 638, durationSeconds: 40.1, cost: "未定价", status: 200, cached: true),
        .init(time: "14:39", model: "opus-5", inputTokens: 0, outputTokens: 0, durationSeconds: 6.1, cost: "$0.00", status: 429, cached: false),
        .init(time: "14:37", model: "opus-5", inputTokens: 1126, outputTokens: 372, durationSeconds: 63.2, cost: "未定价", status: 200, cached: true),
    ]
}

/// KPI 聚合（mock 与表格自洽；接数据源时替换构造处）。
struct TokenSummary {
    let totalTokens: String
    let cacheRate: String
    let calls: String
    let cost: String

    static let mock = TokenSummary(totalTokens: "38.8M", cacheRate: "94.6%", calls: "527次", cost: "$0.00")
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
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(row.time)
                .frame(width: timeW, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(row.model)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
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
        .onHover { hovering = $0 }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.5))
                .frame(height: 0.5)
        }
    }
}

struct TokenZoneView: View {
    var requests: [TokenRequest] = TokenRequest.mock

    /// 列宽（header 与行共用同一组，保证对齐；文本列左对齐，数字列右对齐）
    private let timeW: CGFloat = 44
    private let modelW: CGFloat = 72
    private let durationW: CGFloat = 56
    private let statusW: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            summaryBar
            header
            ForEach(requests.prefix(5)) { row in
                TokenRowView(row: row, timeW: timeW, modelW: modelW, durationW: durationW, statusW: statusW)
            }
            footer
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var summaryBar: some View {
        HStack {
            HStack(spacing: 6) {
                Text("Tokens")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(TokenSummary.mock.totalTokens)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
            }
            Spacer()
            HStack(spacing: 6) {
                Text("缓存命中率")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
                Text(TokenSummary.mock.cacheRate)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.green)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.green.opacity(0.2))
                        .frame(width: 64, height: 6)
                    Capsule()
                        .fill(Color.green)
                        .frame(width: 64 * 0.946, height: 6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.green.opacity(0.20), lineWidth: 1))
            Spacer()
            HStack(spacing: 6) {
                Text("调用量")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(TokenSummary.mock.calls)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
            }
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
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("上下文缓存命中已开启 (Prompt Cache 10%)")
                Spacer()
                Text("更新于 \(Self.footerTime)")
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .padding(.top, 10)
    }

    private static var footerTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }
}

#Preview {
    TokenZoneView()
        .padding()
        .frame(width: 600)
        .background(.ultraThinMaterial)
}
