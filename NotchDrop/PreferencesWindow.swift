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

    var color: Color {
        switch self {
        case .general: return Color.gray
        case .unlock: return StudioColor.emerald
        case .lock: return StudioColor.amber
        case .notification: return StudioColor.rose
        case .calibration: return Color.blue
        case .diagnostics: return StudioColor.indigo
        }
    }
}

struct PreferencesWindow: View {
    @State private var selectedTab: PreferencesTab = .general

    var body: some View {
        NavigationSplitView {
            List(PreferencesTab.allCases, selection: $selectedTab) { tab in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(tab.color)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Image(systemName: tab.icon)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                        )
                    Text(tab.rawValue)
                        .font(.system(size: 13))
                }
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

// MARK: - Studio Section Group Component

struct StudioSectionGroup<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    @ViewBuilder let content: () -> Content

    init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                content()
            }
            .studioCard(radius: 10)
        }
        .padding(.horizontal)
    }
}

// MARK: - Tab 1: 通用

struct GeneralSettingsTab: View {
    @State private var hapticFeedback: Bool = {
        if let data = FileStorage().data(forKey: "hapticFeedback"),
           let val = try? JSONDecoder().decode(Bool.self, from: data) {
            return val
        }
        return true
    }()
    @StateObject private var tvm = TrayDrop.shared
    @State private var selectedLanguage: Language = {
        if let data = FileStorage().data(forKey: "selectedLanguage"),
           let val = try? JSONDecoder().decode(Language.self, from: data) {
            return val
        }
        return .system
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                StudioSectionGroup("开机与交互") {
                    VStack(spacing: 0) {
                        LaunchAtLogin.Toggle {
                            Text("开机自动启动")
                        }
                        .toggleStyle(.switch)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        Divider().overlay(StudioMaterial.strokeNormal)

                        Toggle("触觉振动反馈", isOn: $hapticFeedback)
                            .toggleStyle(.switch)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .onChange(of: hapticFeedback) { newValue in
                                if let vm = (NSApp.delegate as? AppDelegate)?.mainWindowController?.vm {
                                    vm.hapticFeedback = newValue
                                } else if let data = try? JSONEncoder().encode(newValue) {
                                    FileStorage().set(data, forKey: "hapticFeedback")
                                }
                            }

                        Divider().overlay(StudioMaterial.strokeNormal)

                        HStack {
                            Text("语言设置")
                            Spacer()
                            Picker("", selection: $selectedLanguage) {
                                ForEach(Language.allCases) { lang in
                                    Text(lang.localized).tag(lang)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .onChange(of: selectedLanguage) { newValue in
                            if let vm = (NSApp.delegate as? AppDelegate)?.mainWindowController?.vm {
                                vm.selectedLanguage = newValue
                            } else if let data = try? JSONEncoder().encode(newValue) {
                                FileStorage().set(data, forKey: "selectedLanguage")
                            }
                            newValue.apply()
                        }
                    }
                }

                StudioSectionGroup("暂存区管理") {
                    VStack(spacing: 0) {
                        HStack {
                            Text("文件暂存保留时长")
                            Spacer()
                            Picker("", selection: $tvm.selectedFileStorageTime) {
                                ForEach(TrayDrop.FileStorageTime.allCases) { time in
                                    Text(time.localized).tag(time)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        if tvm.selectedFileStorageTime == .custom {
                            Divider().overlay(StudioMaterial.strokeNormal)
                            HStack {
                                Text("自定义时长")
                                Spacer()
                                TextField("时长", value: $tvm.customStorageTime, formatter: NumberFormatter())
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                                Picker("", selection: $tvm.customStorageTimeUnit) {
                                    ForEach(TrayDrop.CustomStorageTimeUnit.allCases) { unit in
                                        Text(unit.localized).tag(unit)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 80)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }
                }

                StudioSectionGroup("关于 NotchEvery") {
                    VStack(spacing: 0) {
                        HStack {
                            Text("当前版本")
                            Spacer()
                            Text(appVersion)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        Divider().overlay(StudioMaterial.strokeNormal)

                        HStack {
                            Text("反代数据源")
                            Spacer()
                            Text("Antigravity Tools")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }
            }
            .padding(.vertical)
            .onAppear {
                if let vm = (NSApp.delegate as? AppDelegate)?.mainWindowController?.vm {
                    hapticFeedback = vm.hapticFeedback
                    selectedLanguage = vm.selectedLanguage
                }
            }
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
            VStack(spacing: 16) {
                StudioSectionGroup("靠近唤醒机制") {
                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("接近自动唤醒屏幕", isOn: $wakeOnProximity)
                                .toggleStyle(.switch)
                            Text("当 Apple Watch 靠近至解锁距离时，提前点亮屏幕。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        Divider().overlay(StudioMaterial.strokeNormal)

                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("允许仅唤醒屏幕不自动解锁", isOn: $wakeWithoutUnlocking)
                                .toggleStyle(.switch)
                            Text("点亮屏幕供查看锁屏小组件或时间，不自动输入密码。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        Divider().overlay(StudioMaterial.strokeNormal)

                        Toggle("使用屏幕保护程序替代熄屏", isOn: $screensaver)
                            .toggleStyle(.switch)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                }

                StudioSectionGroup("锁屏密码与安全") {
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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
            .padding(.vertical)
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
            VStack(spacing: 16) {
                StudioSectionGroup("离席锁定动作") {
                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("离开后立即熄灭显示器", isOn: $sleepDisplay)
                                .toggleStyle(.switch)
                            Text("检测到远离时不仅锁屏，同时让屏幕进入休眠节电。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        Divider().overlay(StudioMaterial.strokeNormal)

                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("锁屏时暂停媒体播放", isOn: $pauseItunes)
                                .toggleStyle(.switch)
                            Text("自动暂停正在播放的音乐或视频。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        Divider().overlay(StudioMaterial.strokeNormal)

                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("键盘鼠标输入中防误锁", isOn: $lockOnIdle)
                                .toggleStyle(.switch)
                            Text("若当前正在敲击键盘或移动鼠标，即便蓝牙信号瞬时衰减也不触发锁屏。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }
            }
            .padding(.vertical)
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
            VStack(spacing: 16) {
                StudioSectionGroup("iMessage 远程异常告警") {
                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("开启解锁异常 iMessage 推送", isOn: $iMessageNotify)
                                .toggleStyle(.switch)
                            Text("在多次解锁失败、密码错误或可能被触碰入侵时向手机发送告警。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        if iMessageNotify {
                            Divider().overlay(StudioMaterial.strokeNormal)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("收件人手机号或 Apple ID 邮箱")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                                .padding(.top, 4)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }
                }
            }
            .padding(.vertical)
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
            VStack(spacing: 16) {
                StudioSectionGroup("当前信号阈值") {
                    VStack(spacing: 0) {
                        HStack {
                            Text("当前绑定设备")
                            Spacer()
                            Text(store.deviceName ?? "未绑定设备")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        Divider().overlay(StudioMaterial.strokeNormal)

                        HStack {
                            Text("当前信号强度 (RSSI)")
                            Spacer()
                            Text(store.rssi.map { "\($0) dBm" } ?? "--")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        Divider().overlay(StudioMaterial.strokeNormal)

                        HStack {
                            Text("解锁阈值")
                            Spacer()
                            Text("\(store.unlockRSSI) dBm")
                                .font(.system(.body, design: .monospaced))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        Divider().overlay(StudioMaterial.strokeNormal)

                        HStack {
                            Text("锁定阈值")
                            Spacer()
                            Text("\(store.lockRSSI) dBm")
                                .font(.system(.body, design: .monospaced))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }

                StudioSectionGroup("向导式校准") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("如果当前距离下经常出现误锁或无法及时解锁，建议运行测距校准向导，通过采样计算适合当前办公环境的信号阈值。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("启动空间测距校准向导...") {
                            isPresentingWizard = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
            .padding(.vertical)
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
                    Text(categoryText(event.category))
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    Text(event.detail.isEmpty ? (event.reason?.localizedTitle ?? event.reason?.rawValue ?? "") : event.detail)
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

    private func categoryText(_ cat: DecisionCategory) -> String {
        switch cat {
        case .unlock: return "解锁"
        case .lock: return "锁屏"
        case .system: return "系统"
        case .user: return "用户"
        }
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
