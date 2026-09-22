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
    /// 「一键签到」进行中标志：签到要跑完整一轮网络巡检（账号数 × GET/POST），耗时不短，
    /// 用本地状态把按钮置灰并给出文案反馈；同时它也是收尾后让这一行重算的驱动源
    /// （QoderCampaignClaimer 不是 ObservableObject，见其类内注释）。
    @State private var isClaimingCredits = false

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
            if showPoolTotal {
                Text("· 已探测 \(store.poolQuotas.count) / 共 \(poolSize) 号")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
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
            // 端口号取 manager.port，勿写字面量。
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
                value: poolTotalText,
                unit: store.quota?.unit ?? "credits"
            )
        }
    }

    /// 全池合计是否有意义可展示：网关在跑（否则数据无意义）且至少探测到一个号（poolTotalRemaining 非 nil）。
    /// 「剩余额度」取值与小字标注共用，避免两处守卫各写一遍、日后改一漏一。
    private var showPoolTotal: Bool {
        isRunning && store.poolTotalRemaining != nil
    }

    /// 池规模（总号数）以 /v1/pool/status 返回的成员列表为准；该接口尚未回填时兜底为已探测数，
    /// 避免出现「已探测 3 / 共 0 号」这种荒谬值。
    private var poolSize: Int {
        max(store.poolMembers.count, store.poolQuotas.count)
    }

    /// 全池合计来自直连探测（QoderPoolQuotaProber），不依赖网关元数据轮询，故不受 isQuotaStale 影响；
    /// 仅在网关未运行（数据无意义）或尚未探测到任何账号时显示 --。
    private var poolTotalText: String {
        guard showPoolTotal, let total = store.poolTotalRemaining else { return "--" }
        return "\(Int(total))"
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
        VStack(alignment: .leading, spacing: 6) {
            quotaStatusRow
            dailyClaimRow
        }
        .padding(.top, 2)
    }

    /// 页脚第一行：额度重置时间 / 网关状态 + 缓存命中率。
    @ViewBuilder
    private var quotaStatusRow: some View {
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
                Text("缓存命中 " + String(format: "%.1f%%", store.today.cacheRateFraction * 100))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(StudioColor.emerald)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(StudioColor.emerald.opacity(0.16), in: Capsule())
                    .overlay(Capsule().strokeBorder(StudioColor.emerald.opacity(0.32), lineWidth: 0.5))
            }
        }
    }

    /// 页脚第二行：今日 credits 签到进度 + 一键签到入口。签到走本地账号池凭证文件，与网关在不在跑无关，
    /// 故不受 isRunning 门控。分子口径（claimed + alreadyClaimed）由 claimer 的纯函数统一裁决；
    /// 分母优先用网关回填的成员数，未回填时退回当日已有记录的账号数，避免出现「已领 2 / 共 0」的自相矛盾。
    private var dailyClaimRow: some View {
        let outcomes = QoderCampaignClaimer.shared.dailyOutcomes
        let claimed = QoderCampaignClaimer.claimedCount(in: outcomes)
        let total = max(store.poolMembers.count, outcomes.count)
        return HStack(spacing: 8) {
            Text("今日签到: \(claimed)/\(total)")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.white.opacity(0.45))
            Spacer()
            Button(isClaimingCredits ? "签到中…" : "一键签到") {
                isClaimingCredits = true
                Task {
                    _ = await QoderCampaignClaimer.shared.claimAll()
                    await store.refreshPoolQuotas()
                    isClaimingCredits = false
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(isClaimingCredits ? Color.white.opacity(0.45) : StudioColor.emerald)
            .disabled(isClaimingCredits)
        }
    }
}
