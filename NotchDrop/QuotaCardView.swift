//
//  QuotaCardView.swift
//  NotchEvery
//
//  额度卡（样式 C：5h 大环 + 周/月小字，2026-09-08 定稿视觉，锁定）。
//  环内数字 15pt（100.0% ≈52pt < 内径 54，不溢出）
//

import Foundation
import SwiftUI

struct QuotaCardView: View {
    @StateObject var vm: NotchViewModel
    @StateObject var store = QuotaStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 用量阈值配色：<70 绿，70–90 橙，≥90 红
    static func ringColor(_ percent: Double) -> Color {
        if percent >= 90 { return .red }
        if percent >= 70 { return .orange }
        return .green
    }

    var body: some View {
        // 放大版横块（2026-09-11 用户验收：内容放大、面板=内容+黑边）：环 72 + 纵向 12，宽 360+
        HStack(spacing: 14) {
            ring(size: 72, percent: store.snapshot.window("5h")?.percent, label: "5h")
            VStack(alignment: .leading, spacing: 7) {
                row(key: "weekly", title: "周")
                row(key: "monthly", title: "月")
                statusLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 横块：固定设计宽 360（不随面板伸缩——弹性宽会把面板测量撑成"跟着上次页走"，划回来不缩）
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 360)
        .onAppear { store.start() }
        // 30s 轮询随面板收起停表（常驻定时器归零）：面板收起 → status closed
        .onChange(of: vm.status) { status in
            if status == .closed {
                store.stop()
            } else {
                store.start()
            }
        }
    }

    private func row(key: String, title: String) -> some View {
        let percent = store.snapshot.window(key)?.percent
        return HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
                .frame(width: 22, alignment: .leading)
            miniBar(percent: percent)
                .frame(minWidth: 70)
            if let percent {
                Text("\(Int(percent))%")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .frame(width: 46, alignment: .trailing)
            } else {
                Text("--%")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .frame(width: 46, alignment: .trailing)
            }
        }
    }

    /// 行内小进度条：阈值配色与大环一致（无数据时只显示轨道）
    private func miniBar(percent: Double?) -> some View {
        let fraction = percent.map { min(1, max(0, $0 / 100)) } ?? 0
        let fill: Color = percent.map(Self.ringColor) ?? .clear
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 8)
                RoundedRectangle(cornerRadius: 4)
                    .fill(fill)
                    .frame(width: geo.size.width * fraction, height: 8)
                    .animation(.easeInOut(duration: 0.3), value: fraction)
            }
        }
        .frame(height: 8)
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
                .fill(!store.snapshot.available ? Color.white.opacity(0.4) : (store.snapshot.expired ? Color.orange : Color.green))
                .frame(width: 6, height: 6)
            if store.snapshot.expired || !store.snapshot.available {
                Text(store.snapshot.available ? "已过期" : "暂无数据")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.55))
            } else if let countdown = resetCountdownText {
                Text(countdown)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.55))
            } else if let at = store.snapshot.fetchedAt {
                Text(at, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
        }
    }

    private func ring(size: CGFloat, percent: Double?, label: String) -> some View {
        VStack(spacing: 4) {
            ZStack {
                if let percent {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 9)
                        .frame(width: size, height: size)
                    Circle()
                        .trim(from: 0, to: min(1, max(0, percent / 100)))
                        .stroke(
                            AngularGradient(
                                colors: [Self.ringColor(percent).opacity(0.8), Self.ringColor(percent)],
                                center: .center,
                                startAngle: .degrees(-90),
                                endAngle: .degrees(270)
                            ),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: size, height: size)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: percent)
                    Text(String(format: "%.1f%%", percent))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .frame(width: size - 16)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                } else {
                    Circle()
                        .strokeBorder(
                            Color.white.opacity(0.12),
                            style: StrokeStyle(lineWidth: 9, dash: [6, 6])
                        )
                        .frame(width: size, height: size)
                    Text("--%")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
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
