//
//  GatewayZoneView.swift
//  NotchEvery
//
//  网关分区（第 3 页）：严格对齐第一页（OverviewPageView）的双卡布局结构：
//    卡片 1：Qoder 账号池（圆形卡 + 顶栏启停按钮）
//    卡片 2：Qoder 用量看板（今日请求、今日 credits、剩余额度）
//  两张卡片均居中且严格落在刘海安全区（vm.notchSafeAreaTop）下方，彻底规避硬件挖槽。
//

import SwiftUI

struct GatewayZoneView: View {
    @StateObject var vm: NotchViewModel
    @ObservedObject var manager = QoderGatewayManager.shared
    @ObservedObject var store = QoderStore.shared

    var body: some View {
        VStack(spacing: 10) {
            // 卡片 1：Qoder 账号池
            QoderPoolRingView(manager: manager, store: store)
                .padding(.horizontal, 14)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

            // 卡片 2：Qoder 用量看板（对齐第一页的 AntigravityProxyCardView）
            qoderMetricsCard
                .padding(.horizontal, 14)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
        .onAppear {
            store.start(logURL: manager.gatewayLogURL)
        }
        .onChange(of: vm.status) { status in
            if status == .closed {
                store.stop()
            } else {
                store.start(logURL: manager.gatewayLogURL)
            }
        }
    }

    // MARK: - 第二张卡：用量看板

    private var isRunning: Bool {
        if case .running = manager.state { return true }
        return false
    }

    private var qoderMetricsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            metricsHeader
            metricsGrid
            metricsFooter
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 360)
    }

    private var metricsHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isRunning ? StudioColor.emerald : Color.white.opacity(0.25))
                .frame(width: 7, height: 7)
            Text("Qoder 反代用量")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
            Spacer()
            // 微型深色胶囊包裹端口号（动态取值：manager.port，默认 8097，绝不硬编码）。
            Text(":\(String(manager.port))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.55))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.05), in: Capsule())
        }
    }

    private var metricsGrid: some View {
        HStack(spacing: 8) {
            metricCell(
                title: "今日请求",
                value: isRunning && !store.isQuotaStale ? "\(store.today.calls)" : "--",
                unit: "次"
            )
            metricCell(
                title: "今日 credits",
                value: isRunning && !store.isQuotaStale ? String(format: "%.2f", store.today.credits) : "--",
                unit: ""
            )
            metricCell(
                title: "剩余额度",
                value: isRunning && !store.isQuotaStale && store.quota != nil ? "\(store.quota!.remaining)" : "--",
                unit: store.quota?.unit ?? "credits"
            )
        }
    }

    private func metricCell(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.45))
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

    @ViewBuilder
    private var metricsFooter: some View {
        HStack {
            if let resetDate = store.quota?.resetDate, isRunning {
                Text("重置: \(resetDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.4))
            } else if !isRunning {
                Text("网关已停止")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.35))
            } else if store.isQuotaStale {
                Text("额度数据已离线")
                    .font(.system(size: 10.5))
                    .foregroundStyle(StudioColor.amber.opacity(0.8))
            } else {
                Text("就绪")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            Spacer()
            if isRunning && store.today.cached > 0 {
                // 翠绿缓存率徽章（对齐首页 footer 的 emerald 语言）。
                Text("缓存命中 \(Int(store.today.cacheRateFraction * 100))%")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(StudioColor.emerald)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(StudioColor.emerald.opacity(0.16), in: Capsule())
                    .overlay(Capsule().strokeBorder(StudioColor.emerald.opacity(0.32), lineWidth: 0.5))
            }
        }
        .padding(.top, 2)
    }
}
