//
//  GuardControlZoneView.swift
//  NotchEvery
//
//  第三页：守护控制台（替换原 DiagZoneView 长列表）。
//  定宽 360pt，包含 2×2 高频开关、RSSI 阈值快捷步进调节、精简判定卡片与校准向导入口。
//

import AppKit
import SwiftUI

struct GuardControlZoneView: View {
    @StateObject var vm: NotchViewModel
    @StateObject var store = GuardStore.shared
    @StateObject private var logger = DecisionLogger.shared

    // 高频行为开关持久化绑定（读取 ConfigStore.shared.defaults）
    @AppStorage("wakeOnProximity", store: ConfigStore.shared.defaults) private var wakeOnProximity = false
    @AppStorage("sleepDisplay", store: ConfigStore.shared.defaults) private var sleepDisplay = true
    @AppStorage("pauseItunes", store: ConfigStore.shared.defaults) private var pauseItunes = false
    @AppStorage("lockOnIdle", store: ConfigStore.shared.defaults) private var lockOnIdle = true

    // 校准向导弹窗
    @State private var showCalibration = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            togglesGrid
            thresholdRow
            recentJudgementCard
            bottomActions
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 360)
        .sheet(isPresented: $showCalibration) {
            CalibrationWizardView(manager: store.funManager, isPresented: $showCalibration)
        }
        .onAppear {
            store.start()
            logger.loadHistory()
        }
    }

    // MARK: - Header 状态行

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(stateColor)
                .frame(width: 7, height: 7)
            Text("守护控制 · \(stateText)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
            Spacer(minLength: 8)
            Text(deviceSummary)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(0.52))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var stateText: String {
        switch store.guardState {
        case .disabled: return "停用"
        case .observing: return "空跑"
        case .guarding: return "生效中"
        }
    }

    private var stateColor: Color {
        switch store.guardState {
        case .disabled: return Color.white.opacity(0.35)
        case .observing: return .orange
        case .guarding: return Color(red: 0.16, green: 0.75, blue: 0.38)
        }
    }

    private var deviceSummary: String {
        guard let name = store.deviceName else { return "未绑定设备" }
        let rssi = store.rssi.map { "\($0) dBm" } ?? "-- dBm"
        return "\(name) · \(rssi)"
    }

    // MARK: - 2×2 高频行为开关

    private var togglesGrid: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                toggleItem("接近唤醒屏幕", isOn: $wakeOnProximity)
                toggleItem("离开立即熄屏", isOn: $sleepDisplay)
            }
            HStack(spacing: 12) {
                toggleItem("离开暂停音乐", isOn: $pauseItunes)
                toggleItem("键鼠活动保护", isOn: $lockOnIdle)
            }
        }
        .padding(.vertical, 2)
    }

    private func toggleItem(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(1)
            Spacer(minLength: 4)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity)
    }

    // MARK: - RSSI 阈值快速调节

    private var thresholdRow: some View {
        HStack(spacing: 12) {
            // 解锁阈值
            HStack(spacing: 4) {
                Text("解锁")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.55))
                Text("\(store.unlockRSSI) dBm")
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.92))
                Spacer(minLength: 4)
                Stepper("", onIncrement: {
                    let next = min(store.unlockRSSI + 1, -30)
                    store.setUnlockRSSI(next)
                }, onDecrement: {
                    let next = max(store.unlockRSSI - 1, -93)
                    store.setUnlockRSSI(next)
                })
                .labelsHidden()
                .controlSize(.mini)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

            // 锁定阈值
            HStack(spacing: 4) {
                Text("锁屏")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.55))
                Text("\(store.lockRSSI) dBm")
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.92))
                Spacer(minLength: 4)
                Stepper("", onIncrement: {
                    guard store.lockRSSI + 1 <= store.unlockRSSI - 2 else { return }
                    store.setLockRSSI(store.lockRSSI + 1)
                }, onDecrement: {
                    let next = max(store.lockRSSI - 1, -95)
                    store.setLockRSSI(next)
                })
                .labelsHidden()
                .controlSize(.mini)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - 精简最近判定卡片

    private var recentJudgementCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let latest = logger.events.last {
                HStack(spacing: 6) {
                    Circle()
                        .fill(outcomeColor(latest.outcome))
                        .frame(width: 6, height: 6)
                    Text(timeString(latest.timestamp))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.45))
                    Text(outcomeText(latest.outcome))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(outcomeColor(latest.outcome))
                    Text(latest.detail.isEmpty ? (latest.reason?.localizedTitle ?? latest.reason?.rawValue ?? "") : latest.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 6, height: 6)
                    Text("暂无判定事件记录")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - 操作底栏

    private var bottomActions: some View {
        HStack(spacing: 10) {
            Button(action: { showCalibration = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "location.viewfinder")
                    Text("空间测距校准")
                }
                .font(.system(size: 11))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(action: { openPreferences() }) {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                    Text("完整偏好设置...")
                }
                .font(.system(size: 11))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func openPreferences() {
        vm.notchClose()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            PreferencesWindowController.shared.show()
        }
    }

    private func timeString(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private func outcomeColor(_ outcome: DecisionOutcome) -> Color {
        switch outcome {
        case .success: return Color(red: 0.16, green: 0.75, blue: 0.38)
        case .failed, .blocked: return Color(red: 0.85, green: 0.25, blue: 0.2)
        case .skipped, .info: return Color.white.opacity(0.45)
        }
    }

    private func outcomeText(_ outcome: DecisionOutcome) -> String {
        switch outcome {
        case .success: return "成功"
        case .skipped: return "跳过"
        case .failed: return "失败"
        case .blocked: return "拦截"
        case .info: return "信息"
        }
    }
}
