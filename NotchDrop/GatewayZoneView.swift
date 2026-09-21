//
//  GatewayZoneView.swift
//  NotchEvery
//
//  网关分区（第 3 页）：顶栏状态灯 + 启停开关，中部圆形账号池，底部今日统计条。
//  数据源 = QoderGatewayManager.shared（进程态）+ QoderStore.shared（/quota、/v1/pool/status、日志聚合）。
//

import SwiftUI

/// 收起态耳区也复用的紧凑状态灯。
struct GatewayStatePill: View {
    @ObservedObject var manager = QoderGatewayManager.shared

    private var dotColor: Color {
        switch manager.state {
        case .running: return StudioColor.emerald
        case .crashed: return StudioColor.rose
        case .starting, .stopping: return StudioColor.amber
        case .stopped: return Color.white.opacity(0.3)
        }
    }

    private var label: String {
        switch manager.state {
        case .running: return "网关 :\(manager.port)"
        case .starting: return "启动中…"
        case .stopping: return "停止中…"
        case .crashed(let r): return "网关异常"
        case .stopped: return "网关已停"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            if manager.state == .starting || manager.state == .stopping {
                ProgressView().controlSize(.mini).scaleEffect(0.6)
            } else {
                Circle().fill(dotColor).frame(width: 8, height: 8)
            }
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .monospacedDigit()
    }
}

struct GatewayZoneView: View {
    @StateObject var vm: NotchViewModel
    @ObservedObject var manager = QoderGatewayManager.shared
    @ObservedObject var store = QoderStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 分区主体：只放禁放区以下的内容；标题与启停按钮经 earTitle/earToggle 挂到耳区两端，
    /// 避免顶进中央禁放区被物理挖槽切字（2026-09-21 用户截图指出）。
    /// 注意：两个耳件用 @ObservedObject manager/store 而非捕获 self——耳区挂在根视图 overlay，
    /// 与 pages 里的整页实例是两个身份，状态变化必须各自独立驱动重渲染。
    var earTitle: some View {
        Text("Qoder 反代网关")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.92))
            .lineLimit(1)
    }

    /// 右耳：状态文案 + 启停按钮（贴死区右缘）。
    var earToggle: some View {
        HStack(spacing: 8) {
            if case .crashed(let reason) = manager.state {
                Text(reason)
                    .font(.system(size: 10.5))
                    .foregroundStyle(StudioColor.rose)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            toggleButton
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            QoderPoolRingView(store: store, port: manager.port)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            statsBar
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .onAppear {
            store.start(logURL: manager.gatewayLogURL)
        }
        .onChange(of: vm.status) { status in
            // 面板收起停轮询省资源；展开恢复（对齐 AntigravityAccountsCardView 生命周期语义）
            if status == .closed { store.stop() } else { store.start(logURL: manager.gatewayLogURL) }
        }
    }

    @ViewBuilder
    private var toggleButton: some View {
        let busy = manager.state == .starting || manager.state == .stopping
        Button {
            switch manager.state {
            case .stopped: manager.start()
            case .crashed: manager.retry()
            case .running: manager.stop()
            default: break
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: buttonIcon)
                    .font(.system(size: 11, weight: .semibold))
                Text(buttonTitle)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(buttonForeground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(buttonBackground))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.6 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: manager.state)
    }

    private var buttonIcon: String {
        switch manager.state {
        case .running: return "stop.fill"
        case .stopped: return "play.fill"
        case .crashed: return "arrow.clockwise"
        case .starting, .stopping: return "hourglass"
        }
    }

    private var buttonTitle: String {
        switch manager.state {
        case .running: return "停止"
        case .stopped: return "启动"
        case .crashed: return "重试"
        case .starting: return "启动中"
        case .stopping: return "停止中"
        }
    }

    private var buttonForeground: Color {
        switch manager.state {
        case .running: return StudioColor.rose
        case .stopped, .crashed: return StudioColor.emerald
        default: return Color.white.opacity(0.6)
        }
    }

    private var buttonBackground: Color {
        switch manager.state {
        case .running: return StudioColor.rose.opacity(0.12)
        case .stopped, .crashed: return StudioColor.emerald.opacity(0.12)
        default: return Color.white.opacity(0.08)
        }
    }

    private var statsBar: some View {
        HStack(spacing: 14) {
            statCell("今日请求", store.isQuotaStale ? "--" : "\(store.today.calls)")
            statCell("今日 credits", store.isQuotaStale ? "--" : String(format: "%.2f", store.today.credits))
            statCell("剩余额度", remainingText)
            Spacer(minLength: 0)
        }
        // 宽度随内容区填充（钳制保证 ≥ 挖槽+16，死区两侧各余 ≥8pt），与账号池卡同宽成列
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var remainingText: String {
        guard let q = store.quota else { return "--" }
        let base = "\(q.remaining)\(store.isQuotaStale ? " · 离线" : "")"
        return base
    }

    private func statCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.92))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.45))
        }
    }
}
