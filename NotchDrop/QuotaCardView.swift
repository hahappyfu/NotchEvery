//
//  QuotaCardView.swift
//  NotchEvery
//
//  额度卡（样式 C：5h 大环 + 周/月小字）。纯展示，点击穿透。
//  视觉已锁定（7pt 中环 / 阈值三色 / 虚线占位 / reduceMotion 跳值）。
//

import Foundation
import SwiftUI

struct QuotaCardView: View {
    @StateObject var vm: NotchViewModel
    @StateObject var store = QuotaStore.shared

    /// 用量阈值配色：<70 绿，70–90 橙，≥90 红
    static func ringColor(_ percent: Double) -> Color {
        if percent >= 90 { return .red }
        if percent >= 70 { return .orange }
        return .green
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        HStack(spacing: 12) {
            ring(size: 68, percent: store.snapshot.window("5h")?.percent, label: "5h")
            VStack(alignment: .leading, spacing: 8) {
                row(key: "weekly", title: "周")
                row(key: "monthly", title: "月")
                statusLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .glassCard(cornerRadius: vm.cornerRadius)
        .onAppear { store.start() }
    }

    private func row(key: String, title: String) -> some View {
        let percent = store.snapshot.window(key)?.percent
        return HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            miniBar(percent: percent)
                .frame(minWidth: 40)
            if let percent {
                Text("\(Int(percent))%")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(width: 40, alignment: .trailing)
            } else {
                Text("--%")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }

    /// 行内小进度条：阈值配色与大环一致（无数据时只显示轨道）
    private func miniBar(percent: Double?) -> some View {
        let fraction = percent.map { min(1, max(0, $0 / 100)) } ?? 0
        let fill: Color = percent.map(Self.ringColor) ?? .clear
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 5)
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(fill)
                    .frame(width: geo.size.width * fraction, height: 5)
            }
        }
        .frame(height: 5)
    }

    /// 分钟精度倒计时（秒级跳动在状态栏是噪音，且 8 字符必换行）。
    /// 随 30s 额度刷新自然更新，无需每秒定时器。
    private var resetCountdownText: String? {
        guard let resetAt = store.snapshot.window("5h")?.resetAt else { return nil }
        let secs = Int(resetAt.timeIntervalSince(Date()))
        guard secs > 0 else { return nil }
        let h = secs / 3600, m = (secs % 3600) / 60
        if h > 0 { return "\(h)时\(m)分后重置" }
        return "\(m)分后重置"
    }

    private var statusLine: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(store.snapshot.expired ? .orange : .green)
                .frame(width: 6, height: 6)
            if store.snapshot.expired || !store.snapshot.available {
                Text(store.snapshot.available ? "已过期" : "暂无数据")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else if let countdown = resetCountdownText {
                Text(countdown)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else if let at = store.snapshot.fetchedAt {
                Text(at, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func ring(size: CGFloat, percent: Double?, label: String) -> some View {
        VStack(spacing: 2) {
            ZStack {
                if let percent {
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 7)
                        .frame(width: size, height: size)
                    Circle()
                        .trim(from: 0, to: min(1, max(0, percent / 100)))
                        .stroke(Self.ringColor(percent), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: size, height: size)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: percent)
                    Text("\(Int(percent))%")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                } else {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 7, dash: [4, 4]))
                        .frame(width: size, height: size)
                    Text("--%")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
#Preview("正常") {
    QuotaCardView(vm: .init())
        .frame(width: 180)
        .padding()
        .background(.ultraThinMaterial)
        .onAppear {
            QuotaStore.shared.seedForPreview(QuotaSnapshot(
                fetchedAt: Date(),
                expired: false,
                available: true,
                windows: [
                    QuotaWindow(key: "5h", used: 11, limit: 100, percent: 11, resetAt: Date().addingTimeInterval(3600)),
                    QuotaWindow(key: "weekly", used: 41, limit: 100, percent: 41, resetAt: nil),
                    QuotaWindow(key: "monthly", used: 53, limit: 100, percent: 53, resetAt: nil),
                ]
            ))
        }
}

#Preview("过期") {
    QuotaCardView(vm: .init())
        .frame(width: 180)
        .padding()
        .background(.ultraThinMaterial)
        .onAppear {
            QuotaStore.shared.seedForPreview(QuotaSnapshot(
                fetchedAt: Date().addingTimeInterval(-3600),
                expired: true,
                available: true,
                windows: [
                    QuotaWindow(key: "5h", used: 92, limit: 100, percent: 92, resetAt: nil),
                    QuotaWindow(key: "weekly", used: 75, limit: 100, percent: 75, resetAt: nil),
                    QuotaWindow(key: "monthly", used: 53, limit: 100, percent: 53, resetAt: nil),
                ]
            ))
        }
}

#Preview("无数据") {
    QuotaCardView(vm: .init())
        .frame(width: 180)
        .padding()
        .background(.ultraThinMaterial)
        .onAppear {
            QuotaStore.shared.seedForPreview(.empty)
        }
}
#endif
