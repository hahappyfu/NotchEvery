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
            ring(size: 76, percent: store.snapshot.window("5h")?.percent, label: "5h")
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
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            if let w = store.snapshot.window(key) {
                Text("\(Int(w.percent))%")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            } else {
                Text("--%")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var statusLine: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(store.snapshot.expired ? .orange : .green)
                .frame(width: 6, height: 6)
            if let at = store.snapshot.fetchedAt {
                Text(at, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                Text(store.snapshot.available ? "已过期" : "暂无数据")
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
