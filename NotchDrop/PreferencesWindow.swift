//
//  PreferencesWindow.swift
//  NotchEvery
//
//  独立侧边栏偏好设置大窗口：包含常规、解锁、锁定、通知、校准、诊断日志 6 大 Tab。
//

import SwiftUI
import LaunchAtLogin
import AppKit

enum PreferencesTab: String, CaseIterable, Identifiable {
    case general = "通用"
    case unlock = "解锁"
    case lock = "锁定"
    case notification = "通知告警"
    case calibration = "测距校准"
    case diagnostics = "诊断日志"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .unlock: return "lock.open"
        case .lock: return "lock"
        case .notification: return "message.fill"
        case .calibration: return "location.viewfinder"
        case .diagnostics: return "waveform.path.ecg"
        }
    }
}

struct PreferencesWindow: View {
    @State private var selectedTab: PreferencesTab = .general

    var body: some View {
        NavigationSplitView {
            List(PreferencesTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 200)
        } detail: {
            detailContent
                .frame(minWidth: 460, minHeight: 400)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .general:
            GeneralSettingsTab()
        case .unlock:
            UnlockSettingsTab()
        case .lock:
            LockSettingsTab()
        case .notification:
            NotificationSettingsTab()
        case .calibration:
            CalibrationSettingsTab()
        case .diagnostics:
            DiagnosticsSettingsTab()
        }
    }
}

// MARK: - Tab 1: 通用

struct GeneralSettingsTab: View {
    @AppStorage("hapticFeedback") private var hapticFeedback = true

    var body: some View {
        ScrollView {
            Form {
                Section("开机与交互") {
                    LaunchAtLogin.Toggle {
                        Text("开机自动启动")
                    }
                    Toggle("触觉振动反馈", isOn: $hapticFeedback)
                }

                Section("关于 NotchEvery") {
                    HStack {
                        Text("当前版本")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("反代数据源")
                        Spacer()
                        Text("Antigravity Tools")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .padding()
        }
    }
}

// MARK: - Tab 2: 解锁

struct UnlockSettingsTab: View {
    @AppStorage("wakeOnProximity", store: ConfigStore.shared.defaults) private var wakeOnProximity = false
    @AppStorage("wakeWithoutUnlocking", store: ConfigStore.shared.defaults) private var wakeWithoutUnlocking = false
    @AppStorage("screensaver", store: ConfigStore.shared.defaults) private var screensaver = false
    @StateObject private var store = GuardStore.shared

    var body: some View {
        ScrollView {
            Form {
                Section("靠近唤醒机制") {
                    Toggle("接近自动唤醒屏幕", isOn: $wakeOnProximity)
                    Text("当 Apple Watch 靠近至解锁距离时，提前点亮屏幕。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("允许仅唤醒屏幕不自动解锁", isOn: $wakeWithoutUnlocking)
                    Text("点亮屏幕供查看锁屏小组件或时间，不自动输入密码。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("使用屏幕保护程序替代熄屏", isOn: $screensaver)
                }

                Section("锁屏密码与安全") {
                    HStack {
                        Text("钥匙串密码状态")
                        Spacer()
                        Text(store.hasPassword ? "已录入" : "未录入")
                            .foregroundStyle(store.hasPassword ? .green : .orange)
                        Button("重新录入密码") {
                            store.setOrChangePassword()
                        }
                        .controlSize(.small)
                    }
                }
            }
            .formStyle(.grouped)
            .padding()
        }
    }
}

// MARK: - Tab 3: 锁定

struct LockSettingsTab: View {
    @AppStorage("sleepDisplay", store: ConfigStore.shared.defaults) private var sleepDisplay = true
    @AppStorage("pauseItunes", store: ConfigStore.shared.defaults) private var pauseItunes = false
    @AppStorage("lockOnIdle", store: ConfigStore.shared.defaults) private var lockOnIdle = true

    var body: some View {
        ScrollView {
            Form {
                Section("离席锁定动作") {
                    Toggle("离开后立即熄灭显示器", isOn: $sleepDisplay)
                    Text("检测到远离时不仅锁屏，同时让屏幕进入休眠节电。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("锁屏时暂停媒体播放", isOn: $pauseItunes)
                    Text("自动暂停正在播放的音乐或视频。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("键盘鼠标输入中防误锁", isOn: $lockOnIdle)
                    Text("若当前正在敲击键盘或移动鼠标，即便蓝牙信号瞬时衰减也不触发锁屏。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding()
        }
    }
}

// MARK: - Tab 4: 通知告警

struct NotificationSettingsTab: View {
    @AppStorage("iMessageNotify", store: ConfigStore.shared.defaults) private var iMessageNotify = false
    @AppStorage("iMessageNotifyRecipient", store: ConfigStore.shared.defaults) private var recipient = ""
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testSuccess = false

    var body: some View {
        ScrollView {
            Form {
                Section("iMessage 远程异常告警") {
                    Toggle("开启解锁异常 iMessage 推送", isOn: $iMessageNotify)
                    Text("在多次解锁失败、密码错误或可能被触碰入侵时向手机发送告警。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if iMessageNotify {
                        TextField("收件人手机号或 Apple ID 邮箱", text: $recipient)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            Button("发送测试通知") {
                                runTest()
                            }
                            .disabled(isTesting || recipient.isEmpty)

                            if isTesting {
                                ProgressView()
                                    .controlSize(.small)
                            }

                            if let res = testResult {
                                Text(res)
                                    .font(.caption)
                                    .foregroundStyle(testSuccess ? .green : .red)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding()
        }
    }

    private func runTest() {
        guard !recipient.isEmpty else { return }
        isTesting = true
        testResult = nil
        ConfigStore.shared.set(recipient, forKey: "iMessageNotifyRecipient")
        let (title, msg) = IMMessageComposer.compose(.test)
        iMessageNotifier.shared.sendTestNotification(title: title, message: msg) { res in
            isTesting = false
            switch res {
            case .success:
                testSuccess = true
                testResult = "测试消息已成功发送！"
            case .failure(let err):
                testSuccess = false
                testResult = err.message
            }
        }
    }
}

// MARK: - Tab 5: 测距校准

struct CalibrationSettingsTab: View {
    @StateObject private var store = GuardStore.shared
    @State private var isPresentingWizard = false

    var body: some View {
        ScrollView {
            Form {
                Section("当前信号阈值") {
                    HStack {
                        Text("当前绑定设备")
                        Spacer()
                        Text(store.deviceName ?? "未绑定设备")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("当前信号强度 (RSSI)")
                        Spacer()
                        Text(store.rssi.map { "\($0) dBm" } ?? "--")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("解锁阈值")
                        Spacer()
                        Text("\(store.unlockRSSI) dBm")
                            .font(.system(.body, design: .monospaced))
                    }
                    HStack {
                        Text("锁定阈值")
                        Spacer()
                        Text("\(store.lockRSSI) dBm")
                            .font(.system(.body, design: .monospaced))
                    }
                }

                Section("向导式校准") {
                    Text("如果当前距离下经常出现误锁或无法及时解锁，建议运行测距校准向导，通过采样计算适合当前办公环境的信号阈值。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("启动空间测距校准向导...") {
                        isPresentingWizard = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .formStyle(.grouped)
            .padding()
            .sheet(isPresented: $isPresentingWizard) {
                CalibrationWizardView(manager: store.funManager, isPresented: $isPresentingWizard)
            }
        }
    }
}

// MARK: - Tab 6: 诊断日志

struct DiagnosticsSettingsTab: View {
    @StateObject private var logger = DecisionLogger.shared
    @State private var selectedCategory: DecisionCategory?

    private var filteredEvents: [DecisionEvent] {
        guard let cat = selectedCategory else { return logger.events }
        return logger.events.filter { $0.category == cat }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                categoryChip(nil, label: "全部 (\(logger.events.count))")
                categoryChip(.unlock, label: "解锁")
                categoryChip(.lock, label: "锁屏")
                categoryChip(.system, label: "系统")
                categoryChip(.user, label: "用户")
                Spacer()
                Button("清空历史") {
                    logger.clear()
                }
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            List(filteredEvents.reversed()) { event in
                HStack(spacing: 8) {
                    Circle()
                        .fill(outcomeColor(event.outcome))
                        .frame(width: 7, height: 7)
                    Text(timeText(event.timestamp))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(event.category.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    Text(event.detail.isEmpty ? (event.reason?.rawValue ?? "") : event.detail)
                        .font(.system(size: 11.5))
                        .lineLimit(1)
                    Spacer()
                    if let rssi = event.rssi {
                        Text("\(rssi) dBm")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func categoryChip(_ cat: DecisionCategory?, label: String) -> some View {
        Button(action: { selectedCategory = cat }) {
            Text(label)
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(selectedCategory == cat ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(selectedCategory == cat ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func timeText(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M-d HH:mm:ss"
        return f
    }()

    private func outcomeColor(_ outcome: DecisionOutcome) -> Color {
        switch outcome {
        case .success: return Color(red: 0.16, green: 0.75, blue: 0.38)
        case .failed, .blocked: return Color(red: 0.85, green: 0.25, blue: 0.2)
        case .skipped, .info: return Color.gray
        }
    }
}
