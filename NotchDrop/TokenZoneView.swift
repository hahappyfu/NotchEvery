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
    // 白字纯色 pill：深底保证对比度（浅粉底深红字已删）
    status >= 400 ? Color(red: 0.75, green: 0.20, blue: 0.18) : Color(red: 0.16, green: 0.55, blue: 0.32)
}

struct TokenZoneView: View {
    var requests: [TokenRequest] = TokenRequest.mock
    var summary: TokenSummary = .mock

    var body: some View {
        VStack(spacing: 0) {
            kpiRow
                .padding(.bottom, 10)
            header
            ForEach(requests.prefix(5)) { row in
                HStack(spacing: 8) {
                    Text(row.time)
                        .frame(width: 42, alignment: .leading)
                        .foregroundStyle(.secondary)
                    Text(row.model)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .frame(width: 68, alignment: .leading)
                    Text("\(row.inputTokens.formatted()) / \(row.outputTokens.formatted())")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .trailing) {
                            if row.cached {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.green.opacity(0.8))
                            }
                        }
                    Text(String(format: "%.1fs", row.durationSeconds))
                        .frame(width: 50, alignment: .leading)
                        .foregroundStyle(.secondary)
                        .background(alignment: .bottomLeading) {
                            Capsule().fill(Color.accentColor.opacity(0.4))
                                .frame(width: min(1, row.durationSeconds / 60) * 46, height: 3)
                        }
                    Text("\(row.status)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(tokenStatusColor(row.status), in: Capsule())
                        .frame(width: 50, alignment: .trailing)
                }
                .font(.system(size: 11, design: .monospaced))
                .monospacedDigit()
                .padding(.vertical, 4)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var kpiRow: some View {
        HStack(spacing: 16) {
            kpiItem(label: "Tokens", value: summary.totalTokens)
            kpiItem(label: "缓存命中率", value: summary.cacheRate, valueColor: .green, fraction: 0.946)
            kpiItem(label: "调用", value: summary.calls)
        }
        .font(.system(size: 11, design: .monospaced))
        .monospacedDigit()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .padding(.trailing, 28)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private func kpiItem(label: String, value: String, valueColor: Color = .primary, fraction: Double? = nil) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            Text(value).fontWeight(.semibold).foregroundStyle(valueColor)
                .monospacedDigit()
            if let fraction {
                Capsule()
                    .fill(Color.green.opacity(0.8))
                    .frame(width: 30 * fraction, height: 4)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("时间").frame(width: 42, alignment: .leading)
            Text("模型").frame(width: 68, alignment: .leading)
            Text("入 / 出").frame(maxWidth: .infinity, alignment: .leading)
            Text("用时").frame(width: 50, alignment: .leading)
            Text("状态").frame(width: 50, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .padding(.bottom, 4)
    }
}

#Preview {
    TokenZoneView()
        .padding()
        .frame(width: 600)
        .background(.ultraThinMaterial)
}
