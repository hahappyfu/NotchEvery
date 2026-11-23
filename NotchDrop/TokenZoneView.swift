//
//  TokenZoneView.swift
//  NotchDrop
//
//  第 2 页：实时流水（Magpie 数据，暂停定格 / 逐行复制 / 新行绿闪）。
//

import SwiftUI

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

private func flowStatusColor(_ status: Int?) -> Color {
    guard let status else { return StudioColor.rose }
    switch status {
    case 200: return StudioColor.emerald
    case 499: return .gray
    case 429: return StudioColor.amber
    default: return status >= 400 ? StudioColor.rose : StudioColor.emerald
    }
}

private func secondsText(_ ms: Int?) -> String {
    guard let ms else { return "--" }
    return String(format: "%.1fs", Double(ms) / 1000.0)
}

private let flowTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f
}()

extension TokenZoneView {
    static func cacheText(for row: MagpieFlowRow) -> String {
        let fraction = TokenFormatUtils.cacheRateFraction(cached: row.cacheRead, input: row.inputTokens)
        return fraction > 0 ? "缓存 \(Int(fraction * 100))%" : "无缓存"
    }

    static func copySummary(for row: MagpieFlowRow, time: String) -> String {
        "\(time) \(row.providerID)@\(row.account) \(row.model) status=\(row.status ?? -1) \(row.durationMs ?? -1)ms ttft=\(row.ttftMs ?? -1)ms rid=\(row.id)"
    }
}

private struct FlowRowView: View {
    let row: MagpieFlowRow
    let icon: String?
    let copied: Bool
    var isNew: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var flashOpacity: Double = 0

    private var failure: Bool {
        guard let status = row.status else { return true }
        return status >= 400 && status != 499
    }

    /// 次行右侧指标段：[HTTP err] · 总Token · 耗时 · tok/s · [shield N] · 状态点 · [已切备用]
    private var metrics: some View {
        HStack(spacing: 4) {
            if failure, let status = row.status {
                Text("HTTP \(status)")
                    .foregroundStyle(StudioColor.rose)
            }
            Text(TokenFormatUtils.formatCompactTokens(row.inputTokens + row.outputTokens))
            Text("·")
            Text(secondsText(row.durationMs))
            if let tps = row.tokensPerSecond {
                Text("·")
                Text(String(format: "%.1f t/s", tps))
            }
            if row.maskedCount > 0 {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(StudioColor.cyan)
                Text("\(row.maskedCount)")
                    .foregroundStyle(StudioColor.cyan)
            }
            Circle()
                .fill(flowStatusColor(row.status))
                .frame(width: 5, height: 5)
            if row.handedOn {
                Text("已切备用")
                    .font(.system(size: 8))
                    .foregroundStyle(StudioInk.axis)
            }
        }
        .font(.system(size: 9.5).monospacedDigit())
        .foregroundStyle(StudioInk.secondary)
        .lineLimit(1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // 首行：Agent 胶囊 + 路由名/模型 + 时间
            HStack(spacing: 5) {
                Text(row.agent)
                    .font(.system(size: 9))
                    .foregroundStyle(StudioInk.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .lineLimit(1)
                Text(row.groupName ?? (row.requestedModel.isEmpty ? row.model : row.requestedModel))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(StudioInk.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(flowTimeFormatter.string(from: row.time))
                    .font(.system(size: 9.5).monospacedDigit())
                    .foregroundStyle(StudioInk.secondary)
            }
            // 次行：厂商图标 + 提供商 · 账号 · 模型 + 右侧指标
            HStack(spacing: 5) {
                ProviderIconView(icon: icon, providerID: row.providerID, size: 14)
                Text("\(row.providerName) · \(row.account) · \(TokenFormatUtils.friendlyModelName(row.model))")
                    .font(.system(size: 9.5))
                    .foregroundStyle(StudioInk.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                metrics
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(width: IslandMetrics.pageWidth - 10, alignment: .leading)
        .contentShape(Rectangle())
        .background(hovering ? StudioMaterial.cardHoverBackground : Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.035), lineWidth: 0.5))
        .background(StudioColor.emerald.opacity(flashOpacity), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topTrailing) {
            if copied {
                HStack(spacing: 2) {
                    Image(systemName: "checkmark")
                    Text("已复制")
                }
                .font(.system(size: 8.5))
                .foregroundStyle(StudioColor.emerald)
                .padding(4)
            }
        }
        .onHover { hovering = $0 }
        .onAppear {
            guard isNew, !reduceMotion else { return }
            flashOpacity = 0.16
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.9)) { flashOpacity = 0 }
            }
        }
    }
}

struct TokenZoneView: View {
    @ObservedObject var store: MagpieStore
    @StateObject private var copyFeedback = CopyFeedback()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pauseController = FlowPauseController()
    @State private var lastFirstID: String?

    init(store: MagpieStore = .shared) {
        self.store = store
    }

    private var liveRows: [MagpieFlowRow] { Array(store.snapshot.recentFlows.prefix(5)) }
    private var displayedRows: [MagpieFlowRow] {
        pauseController.isPaused ? pauseController.frozenRows : liveRows
    }

    private var statusText: String {
        if pauseController.isPaused {
            var text = "已暂停 · \(pauseController.missedCount) 条未读"
            if pauseController.gapCount > 0 { text += " · 缺口 \(pauseController.gapCount)" }
            return text
        }
        let avg = store.snapshot.todayAverageMs.map { String(format: "%.1fs", $0 / 1000.0) } ?? "--"
        return "\(store.snapshot.todayErrorCount) 错 · 均耗时 \(avg)"
    }

    private func togglePause() {
        if pauseController.isPaused {
            _ = pauseController.resume(liveRows: liveRows)
        } else {
            pauseController.pause(liveRows: liveRows)
        }
    }

    var body: some View {
        VStack(spacing: 5) {
            liveBar

            if displayedRows.isEmpty {
                Text("暂无近期请求记录")
                    .font(.system(size: 11))
                    .foregroundStyle(StudioInk.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(spacing: 4) {
                    ForEach(displayedRows) { row in
                        Button {
                            copyRow(row)
                        } label: {
                            FlowRowView(
                                row: row,
                                icon: store.snapshot.providerGroups.first { $0.id == row.providerID }?.icon,
                                copied: copyFeedback.copiedID == row.id,
                                isNew: !pauseController.isPaused
                                    && lastFirstID != nil
                                    && row.id == liveRows.first?.id
                                    && row.id != lastFirstID
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("复制 \(row.providerName) \(row.model) 流水")
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
                .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: displayedRows.map(\.id))
            }
        }
        .frame(width: IslandMetrics.pageWidth)
        .padding(.vertical, 4)
        .onChange(of: liveRows) { rows in
            if pauseController.isPaused {
                pauseController.receive(liveRows: store.snapshot.recentFlows)
            } else if let first = rows.first, first.id != lastFirstID {
                lastFirstID = first.id
            }
        }
    }

    private func copyRow(_ row: MagpieFlowRow) {
        let summary = TokenZoneView.copySummary(
            for: row,
            time: flowTimeFormatter.string(from: row.time)
        )
        copyFeedback.copy(summary, id: row.id)
    }

    private var liveBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(pauseController.isPaused ? StudioColor.amber : StudioColor.emerald)
                .frame(width: 6, height: 6)
            Text("今天 \(store.snapshot.todayRequestCount) 次")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(StudioInk.primary)
            Spacer(minLength: 4)
            Text(statusText)
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(StudioInk.secondary)
                .lineLimit(1)
            Button(action: togglePause) {
                Image(systemName: pauseController.isPaused ? "play.circle.fill" : "pause.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(StudioInk.primary)
                    .frame(width: 25, height: 25)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(pauseController.isPaused ? "继续流水" : "暂停流水")
            .help(pauseController.isPaused ? "恢复流水" : "暂停流水")
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
