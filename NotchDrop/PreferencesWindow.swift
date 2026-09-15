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
    @State private var searchText = ""

    private var filteredEvents: [DecisionEvent] {
        var list = logger.events
        if let cat = selectedCategory {
            list = list.filter { $0.category == cat }
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter { e in
                if e.detail.lowercased().contains(q) { return true }
                if let r = e.reason?.rawValue.lowercased(), r.contains(q) { return true }
                if let dev = e.device?.lowercased(), dev.contains(q) { return true }
                let badge = badgeInfo(for: e)
                if badge.label.lowercased().contains(q) { return true }
                return false
            }
        }
        return list
    }

    var body: some View {
        let events = filteredEvents

        VStack(alignment: .leading, spacing: 10) {
            // 顶部胶囊工具栏：搜索过滤与一键清理
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("搜索原因、设备或详情...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(StudioMaterial.cardBackground, in: Capsule())
                .overlay(Capsule().strokeBorder(StudioMaterial.strokeNormal, lineWidth: 0.5))
                .frame(minWidth: 160, maxWidth: 260)

                Spacer()

                Button(action: {
                    logger.clear()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 10.5))
                        Text("清空历史")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(StudioMaterial.cardBackground, in: Capsule())
                    .overlay(Capsule().strokeBorder(StudioMaterial.strokeNormal, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .help("清空当前所有诊断决策日志")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // 分类胶囊筛选行
            HStack(spacing: 6) {
                categoryChip(nil, label: "全部 (\(logger.events.count))")
                categoryChip(.unlock, label: "近距解锁")
                categoryChip(.lock, label: "离席锁屏")
                categoryChip(.system, label: "系统守护")
                categoryChip(.user, label: "用户操作")

                Spacer()

                if !searchText.isEmpty || selectedCategory != nil {
                    Text("过滤: \(events.count) 条")
                        .font(.system(size: 10.5, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)

            // 诊断时序小卡片列表
            ScrollView {
                LazyVStack(spacing: 6) {
                    if events.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 26))
                                .foregroundStyle(.tertiary)
                            Text("暂无匹配的诊断时序记录")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                    } else {
                        ForEach(events.reversed()) { event in
                            timelineEventCard(for: event)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }

    private func timelineEventCard(for event: DecisionEvent) -> some View {
        let badge = badgeInfo(for: event)

        return HStack(spacing: 8) {
            // 时序状态指示呼吸点
            Circle()
                .fill(badge.color)
                .frame(width: 6, height: 6)
                .shadow(color: badge.color.opacity(0.4), radius: 2)

            // 精准时间戳
            Text(timeText(event.timestamp))
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            // 专属类别徽标
            Text(badge.label)
                .studioPillBadge(color: badge.color)

            // 决策详情或原因文案
            Text(eventDisplayDetail(event))
                .font(.system(size: 11.5))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 6)

            // 关联设备
            if let dev = event.device, !dev.isEmpty {
                Text(dev)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            // RSSI 信号强度
            if let rssi = event.rssi {
                Text("\(rssi) dBm")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(badge.color.opacity(0.9))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .studioCard(radius: 8)
    }

    private func categoryChip(_ cat: DecisionCategory?, label: String) -> some View {
        let isSelected = selectedCategory == cat
        return Button(action: {
            withAnimation(StudioAnimation.interactiveSpring) {
                selectedCategory = cat
            }
        }) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(
                    isSelected ? Color.accentColor : StudioMaterial.cardBackground,
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? Color.clear : StudioMaterial.strokeNormal,
                        lineWidth: 0.5
                    )
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func badgeInfo(for event: DecisionEvent) -> (label: String, color: Color) {
        if let reason = event.reason {
            switch reason {
            // 近距 / 解锁成功
            case .unlockSuccess:
                return ("近距解锁", StudioColor.emerald)
            case .userUnlocked:
                return ("用户解锁", StudioColor.emerald)

            // 离开 / 锁屏
            case .lockedAway:
                return ("离席锁定", StudioColor.amber)
            case .lockedLost:
                return ("失联锁定", StudioColor.amber)
            case .userLocked:
                return ("用户锁屏", StudioColor.amber)
            case .gracePeriod:
                return ("离席缓冲", StudioColor.amber)
            case .lockBufferActive:
                return ("锁定保护", StudioColor.amber)
            case .signalBelowLockThreshold:
                return ("信号衰减", StudioColor.amber)

            // 防误触 / 信号阻断 / 失败保护
            case .signalBelowThreshold:
                return ("防误触", StudioColor.rose)
            case .unlockCooldownActive:
                return ("冷却防误触", StudioColor.rose)
            case .manualLockActive:
                return ("手动防误触", StudioColor.rose)
            case .wifiPaused:
                return ("Wi-Fi阻断", StudioColor.rose)
            case .stateMachineBlocked:
                return ("状态阻断", StudioColor.rose)
            case .unlockFailed:
                return ("解锁失败", StudioColor.rose)
            case .unlockTimeout:
                return ("解锁超时", StudioColor.rose)
            case .passwordMismatch:
                return ("密码不符", StudioColor.rose)
            case .axRevoked, .notSecureForInjection, .noPassword, .keychainColdBoot:
                return ("权限安全", StudioColor.rose)
            case .iMessageFailed:
                return ("通知告警", StudioColor.rose)

            // 系统与蓝牙
            case .displaySleep, .displayWake, .systemSleep, .systemWake:
                return ("系统电源", StudioColor.cyan)
            case .dryRun:
                return ("空跑诊断", StudioColor.indigo)
            case .bluetoothOff, .bluetoothUnauthorized:
                return ("蓝牙异常", StudioColor.rose)
            default:
                break
            }
        }

        switch (event.category, event.outcome) {
        case (.unlock, .success): return ("近距解锁", StudioColor.emerald)
        case (.unlock, .skipped): return ("防误触", StudioColor.rose)
        case (.unlock, .failed), (.unlock, .blocked): return ("解锁阻断", StudioColor.rose)
        case (.lock, .success): return ("离席锁定", StudioColor.amber)
        case (.lock, .skipped): return ("保持工作", StudioColor.amber)
        case (.system, _): return ("系统事件", StudioColor.cyan)
        case (.user, _): return ("用户操作", StudioColor.indigo)
        default:
            switch event.outcome {
            case .success: return ("成功", StudioColor.emerald)
            case .failed, .blocked: return ("阻断", StudioColor.rose)
            case .skipped: return ("跳过", StudioColor.amber)
            case .info: return ("信息", StudioColor.cyan)
            }
        }
    }

    private func eventDisplayDetail(_ event: DecisionEvent) -> String {
        if !event.detail.isEmpty {
            return event.detail
        }
        if let reason = event.reason {
            return reasonText(for: reason)
        }
        return categoryText(event.category)
    }

    private func reasonText(for reason: DecisionReason) -> String {
        switch reason {
        case .noPresence: return "未检测到 Apple Watch 佩戴"
        case .signalBelowThreshold: return "信号强度低于靠近解锁阈值"
        case .unlockCooldownActive: return "解锁冷却中，避免频繁触发"
        case .lockBufferActive: return "离席锁屏缓冲期进行中"
        case .manualLockActive: return "用户手动锁屏后暂不自动解锁"
        case .wifiPaused: return "连接到指定 Wi-Fi 时暂停自动解锁"
        case .disabled: return "守护功能已在设置中关闭"
        case .unlockDisabled: return "自动解锁功能已关闭"
        case .stateMachineBlocked: return "状态机处于保护状态"
        case .axRevoked: return "辅助功能权限已失效，请重新授权"
        case .noPassword: return "钥匙串中未保存锁屏解锁密码"
        case .keychainColdBoot: return "冷启动后需要首次手动输入密码"
        case .notSecureForInjection: return "密码输入环境校验未通过"
        case .displaySleeping: return "屏幕当前处于休眠状态"
        case .systemNotReady: return "系统服务尚未准备就绪"
        case .wakeWithoutUnlocking: return "已唤醒屏幕但暂不执行密码注入"
        case .recentlyUnlocked: return "近期刚完成解锁"
        case .screenNotLocked: return "屏幕未处于锁定状态"
        case .inputActive: return "检测到键鼠输入活跃，保持不锁屏"
        case .gracePeriod: return "离席离开倒计时缓冲期"
        case .signalBelowLockThreshold: return "信号低于离开锁定阈值"
        case .unlockSuccess: return "近距离感应成功，已自动注入密码解锁"
        case .unlockFailed: return "密码解锁注入失败"
        case .unlockTimeout: return "解锁操作超时未完成"
        case .passwordMismatch: return "密码验证错误，请检查设置"
        case .lockedAway: return "用户已离开工位，自动锁屏保护"
        case .lockedLost: return "手环设备失联超时，自动锁定系统"
        case .displaySleep: return "检测到显示器进入休眠"
        case .displayWake: return "检测到显示器点亮唤醒"
        case .systemSleep: return "系统进入睡眠模式"
        case .systemWake: return "系统从睡眠中唤醒"
        case .userUnlocked: return "用户通过触控ID或键盘手动解锁"
        case .userLocked: return "用户主动锁屏"
        case .dryRun: return "空跑模式：记录诊断行为，不实际操作"
        case .bluetoothOff: return "系统蓝牙已关闭"
        case .bluetoothUnauthorized: return "未授予蓝牙使用权限"
        case .iMessageFailed: return "iMessage 安全告警通知发送失败"
        }
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
}
