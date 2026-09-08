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
    let duration: String
    let cost: String
    let status: Int
    let cached: Bool

    static let mock: [TokenRequest] = [
        .init(time: "14:46", model: "opus-5", inputTokens:524, outputTokens:283, duration: "26.8s", cost: "未定价", status: 200, cached: true),
        .init(time: "14:45", model: "opus-5", inputTokens:538, outputTokens:185, duration: "19.3s", cost: "未定价", status: 200, cached: true),
        .init(time: "14:44", model: "opus-5", inputTokens:2977, outputTokens:638, duration: "40.1s", cost: "未定价", status: 200, cached: true),
        .init(time: "14:39", model: "opus-5", inputTokens:0, outputTokens:0, duration: "6.1s", cost: "$0.00", status: 429, cached: false),
        .init(time: "14:37", model: "opus-5", inputTokens:1126, outputTokens:372, duration: "63.2s", cost: "未定价", status: 200, cached: true),
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
    status >= 400 ? .red : .green
}

struct TokenZoneView: View {
    var requests: [TokenRequest] = TokenRequest.mock
    var summary: TokenSummary = .mock

    var body: some View {
        VStack(spacing: 2) {
            kpiRow
                .padding(.bottom, 6)
            header
            ForEach(requests.prefix(5)) { row in
                HStack(spacing: 6) {
                    Text(row.time)
                        .frame(width: 40, alignment: .leading)
                        .foregroundStyle(.secondary)
                    Text(row.model)
                        .frame(width: 64, alignment: .leading)
                    Text("\(row.inputTokens.formatted()) / \(row.outputTokens.formatted())")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .trailing) {
                            if row.cached {
                                Text("⚡︎").font(.system(size: 9)).foregroundStyle(.green.opacity(0.8))
                            }
                        }
                    Text(row.duration)
                        .frame(width: 48, alignment: .leading)
                        .foregroundStyle(.secondary)
                        .background(alignment: .bottomLeading) {
                            Capsule().fill(Color.accentColor.opacity(0.5))
                                .frame(width: min(1, durationSeconds(row.duration) / 60) * 44, height: 3)
                        }
                    Text(row.cost)
                        .frame(width: 56, alignment: .leading)
                        .foregroundStyle(.secondary)
                    Text("\(row.status)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(tokenStatusColor(row.status))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(tokenStatusColor(row.status).opacity(0.15), in: Capsule())
                        .frame(width: 48, alignment: .trailing)
                }
                .font(.system(size: 11, design: .monospaced))
                .monospacedDigit()
                .padding(.vertical, 3)
            }
        }
    }

    private var kpiRow: some View {
        HStack(spacing: 12) {
            kpiItem(label: "Tokens", value: summary.totalTokens)
            kpiItem(label: "缓存率", value: summary.cacheRate, valueColor: .green, fraction: 0.946)
            kpiItem(label: "调用", value: summary.calls)
            Spacer()
            kpiItem(label: "成本", value: summary.cost)
        }
        .font(.system(size: 11, design: .monospaced))
        .monospacedDigit()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
    }

    private func kpiItem(label: String, value: String, valueColor: Color = .primary, fraction: Double? = nil) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).fontWeight(.semibold).foregroundStyle(valueColor)
                .monospacedDigit()
            if let fraction {
                Capsule()
                    .fill(Color.green)
                    .frame(width: 28 * fraction, height: 4)
            }
        }
    }

    private func durationSeconds(_ duration: String) -> Double {
        Double(duration.replacingOccurrences(of: "s", with: "")) ?? 0
    }

    private var header: some View {        HStack(spacing: 6) {
            Text("时间").frame(width: 40, alignment: .leading)
            Text("模型").frame(width: 64, alignment: .leading)
            Text("入 / 出").frame(maxWidth: .infinity, alignment: .leading)
            Text("用时").frame(width: 48, alignment: .leading)
            Text("成本").frame(width: 56, alignment: .leading)
            Text("状态").frame(width: 48, alignment: .trailing)
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .padding(.bottom, 2)
    }
}

#Preview {
    TokenZoneView()
        .padding()
        .frame(width: 600)
        .background(.ultraThinMaterial)
}
