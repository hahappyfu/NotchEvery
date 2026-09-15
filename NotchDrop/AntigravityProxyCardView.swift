//
//  AntigravityProxyCardView.swift
//  NotchDrop
//
//  首页 Antigravity 本地反代今日流量与延迟看板组件。
//  宽度固定 360pt，内边距与 GuardCardView 严格一致，遵循 Apple Native Studio 工业级设计系统。
//

import SwiftUI

struct AntigravityProxyCardView: View {
    @StateObject var vm: NotchViewModel
    @StateObject var store = UsageStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            metricsGrid
            footer
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 360)
        .onAppear { store.start() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(StudioColor.emerald)
                .frame(width: 7, height: 7)
            Text("本地反代 · \(store.providerName ?? "8045 端口")")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
            Spacer()
            Text("今日看板")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.52))
        }
    }

    private var metricsGrid: some View {
        HStack(spacing: 8) {
            let callsVal = store.summary.calls.replacingOccurrences(of: "次", with: "")
            metricTile(title: "今日请求", value: callsVal, unit: "次")
            metricTile(title: "今日消耗", value: store.summary.totalTokens, unit: "")
            metricTile(title: "平均延迟", value: store.averageLatencyText, unit: "")
        }
    }

    private func metricTile(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.55))
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard(radius: 8)
    }

    private var footer: some View {
        HStack {
            Text("缓存命中率 \(store.summary.cacheRate)")
                .font(.system(size: 10.5))
                .foregroundStyle(StudioColor.emerald)
            Spacer()
            if let lastAt = store.footer.lastRequestAt {
                Text("最近调用 \(timeString(lastAt))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
        }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}
