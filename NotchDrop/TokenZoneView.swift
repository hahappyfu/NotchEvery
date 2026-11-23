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

private struct FlowRowView: View {
    let row: MagpieFlowRow
    let icon: String?
    let copied: Bool
    var isNew: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var flashOpacity: Double = 0

    private let colIdentityW: CGFloat = 145
    private let colTokensW: CGFloat = 175
    private let colTimingW: CGFloat = 70

    private var cacheFraction: Double {
        TokenFormatUtils.cacheRateFraction(cached: row.cacheRead, input: row.inputTokens)
    }

    private var cacheColor: Color {
        switch TokenFormatUtils.cacheRateTier(fraction: cacheFraction) {
        case .high: return StudioColor.emerald
        case .medium: return Color(red: 90/255, green: 200/255, blue: 250/255)
        case .low: return StudioColor.amber
        case .none: return Color.white.opacity(0.25)
        }
    }

    private var failure: Bool {
        guard let status = row.status else { return true }
        return status >= 400 && status != 499
    }

    private var secondaryRight: String {
        if let ttft = row.ttftMs { return "TTFT \(secondsText(ttft))" }
        return flowTimeFormatter.string(from: row.time)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    ProviderIconView(icon: icon, providerID: row.provider, size: 12)
                    Text(TokenFormatUtils.friendlyModelName(row.model))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        .lineLimit(1)
                }
                Text("\(row.provider) · \(row.groupName ?? "直连") · \(row.agent)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: colIdentityW, alignment: .leading)

            VStack(spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(TokenFormatUtils.formatCompactTokens(row.inputTokens + row.outputTokens))
                        .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                    Spacer()
                    Text("缓存 \(Int(cacheFraction * 100))%")
                        .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(cacheColor)
                }
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
                HStack(spacing: 4) {
                    Text("入 \(TokenFormatUtils.formatCompactTokens(row.inputTokens))")
                    Text("·")
                    Text("出 \(TokenFormatUtils.formatCompactTokens(row.outputTokens))")
                    Spacer()
                    if row.maskedCount > 0 {
                        Image(systemName: "shield.lefthalf.filled")
                            .foregroundStyle(Color.cyan)
                        Text("\(row.maskedCount)")
                            .foregroundStyle(Color.cyan)
                    }
                }
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .frame(width: colTokensW)

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text(secondsText(row.durationMs))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                    Circle()
                        .fill(flowStatusColor(row.status))
                        .frame(width: 5, height: 5)
                }
                Text(secondaryRight)
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.secondary)
                if failure {
                    Text("HTTP \(row.status.map(String.init) ?? "—")")
                        .font(.system(size: 8.5).monospacedDigit())
                        .foregroundStyle(StudioColor.rose)
                }
                if row.handedOn {
                    Text("已切备用")
                        .font(.system(size: 8.5))
                        .foregroundStyle(StudioColor.amber)
                }
            }
            .frame(width: colTimingW, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: IslandMetrics.pageWidth - 10)
        .contentShape(Rectangle())
        .background(hovering ? StudioMaterial.cardHoverBackground : Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white.opacity(0.035), lineWidth: 0.5))
        .background(StudioColor.emerald.opacity(flashOpacity), in: RoundedRectangle(cornerRadius: 9))
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

    private var liveRows: [MagpieFlowRow] { store.snapshot.recentFlows }
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
        return "\(store.snapshot.todayRequestCount) 请求 · \(store.snapshot.todayErrorCount) 错 · 均耗时 \(avg)"
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
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(spacing: 5) {
                    ForEach(displayedRows) { row in
                        FlowRowView(
                            row: row,
                            icon: store.snapshot.providerGroups.first { $0.name == row.provider }?.icon,
                            copied: copyFeedback.copiedID == row.id,
                            isNew: !pauseController.isPaused
                                && lastFirstID != nil
                                && row.id == liveRows.first?.id
                                && row.id != lastFirstID
                        )
                        .transition(reduceMotion ? .identity : .opacity)
                        .onTapGesture { copyRow(row) }
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
                pauseController.receive(liveRows: rows)
            } else if let first = rows.first, first.id != lastFirstID {
                lastFirstID = first.id
            }
        }
    }

    private func copyRow(_ row: MagpieFlowRow) {
        let summary = "\(flowTimeFormatter.string(from: row.time)) \(row.provider)@\(row.account) \(row.model) status=\(row.status ?? -1) \(row.durationMs ?? -1)ms ttft=\(row.ttftMs ?? -1)ms rid=\(row.id)"
        copyFeedback.copy(summary, id: row.id)
    }

    private var liveBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(pauseController.isPaused ? StudioColor.amber : StudioColor.emerald)
                .frame(width: 6, height: 6)
            Text("最近 5 笔流水")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
            Spacer(minLength: 4)
            Text(statusText)
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.65))
                .lineLimit(1)
            Button(action: togglePause) {
                Image(systemName: pauseController.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            .buttonStyle(.plain)
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
