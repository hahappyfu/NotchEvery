//
//  PreferencesWindow.swift
//  NotchEvery
//
//  独立侧边栏偏好设置大窗口：重组为通用、近场守护、安全与日志 3 大核心 Tab。
//  适配 macOS 原生系统偏好设置设计规范（圆角分组浮岛卡片 + 安全边距）。
//

import SwiftUI
import LaunchAtLogin
import AppKit

enum PreferencesTab: String, CaseIterable, Identifiable {
    case general = "通用"
    case guardSecurity = "近场守护"
    case diagnostics = "安全与日志"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .guardSecurity: return "lock.shield"
        case .diagnostics: return "waveform.path.ecg"
        }
    }

    var color: Color {
        switch self {
        case .general: return Color.gray
        case .guardSecurity: return StudioColor.emerald
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
                        .font(.system(size: 13, weight: .medium))
                }
                .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 210)
        } detail: {
            detailContent
                .frame(minWidth: 480, minHeight: 450)
                .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .general:
            GeneralSettingsTab()
        case .guardSecurity:
            GuardSecuritySettingsTab()
        case .diagnostics:
            DiagnosticsSettingsTab()
        }
    }
}

// MARK: - Native macOS Settings Section Group Component

struct SettingsSectionGroup<Content: View, Trailing: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    init(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                trailing()
            }
            .padding(.horizontal, 4)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
            }

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: Color.black.opacity(0.03), radius: 2, y: 1)
        }
        .padding(.horizontal, 20)
    }
}

extension SettingsSectionGroup where Trailing == EmptyView {
    init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title, subtitle: subtitle, trailing: { EmptyView() }, content: content)
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
            VStack(spacing: 20) {
                SettingsSectionGroup("基础与交互") {
                    VStack(spacing: 0) {
                        LaunchAtLogin.Toggle {
                            Text("开机自动启动")
                                .font(.system(size: 13))
                        }
                        .toggleStyle(.switch)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        Divider().padding(.leading, 16)

                        Toggle("触觉振动反馈", isOn: $hapticFeedback)
                            .font(.system(size: 13))
                            .toggleStyle(.switch)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .onChange(of: hapticFeedback) { newValue in
                                if let vm = (NSApp.delegate as? AppDelegate)?.mainWindowController?.vm {
                                    vm.hapticFeedback = newValue
                                } else if let data = try? JSONEncoder().encode(newValue) {
                                    FileStorage().set(data, forKey: "hapticFeedback")
                                }
                            }

                        Divider().padding(.leading, 16)

                        HStack {
                            Text("语言设置")
                                .font(.system(size: 13))
                            Spacer()
                            Picker("", selection: $selectedLanguage) {
                                ForEach(Language.allCases) { lang in
                                    Text(lang.localized).tag(lang)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                        }
                        .padding(.horizontal, 16)
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

                SettingsSectionGroup("暂存区管理") {
                    VStack(spacing: 0) {
                        HStack {
                            Text("文件暂存保留时长")
                                .font(.system(size: 13))
                            Spacer()
                            Picker("", selection: $tvm.selectedFileStorageTime) {
                                ForEach(TrayDrop.FileStorageTime.allCases) { time in
                                    Text(time.localized).tag(time)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        if tvm.selectedFileStorageTime == .custom {
                            Divider().padding(.leading, 16)
                            HStack {
                                Text("自定义时长")
                                    .font(.system(size: 13))
                                Spacer()
                                HStack(spacing: 6) {
                                    TextField("天数", value: $tvm.customStorageTime, formatter: NumberFormatter())
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .controlSize(.small)
                                        .frame(width: 50)
                                    Picker("", selection: $tvm.customStorageTimeUnit) {
                                        ForEach(TrayDrop.CustomStorageTimeUnit.allCases) { unit in
                                            Text(unit.localized).tag(unit)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 80)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                    }
                }

                SettingsSectionGroup("关于与状态") {
                    VStack(spacing: 0) {
                        HStack {
                            Text("当前版本")
                                .font(.system(size: 13))
                            Spacer()
                            Text(appVersion)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        Divider().padding(.leading, 16)

                        HStack {
                            Text("反代数据源")
                                .font(.system(size: 13))
                            Spacer()
                            Text("Antigravity Tools")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 30)
            .onAppear {
                if let vm = (NSApp.delegate as? AppDelegate)?.mainWindowController?.vm {
                    hapticFeedback = vm.hapticFeedback
                    selectedLanguage = vm.selectedLanguage
                }
            }
        }
    }
}

// MARK: - Tab 2: 近场守护 (设备配对 + 模式安全 + 测距校准 + 动作策略)

struct GuardSecuritySettingsTab: View {
    @StateObject private var store = GuardStore.shared
    @State private var isPresentingWizard = false
    @State private var selectedDeviceUUID: UUID? = nil
    @State private var isScanning = false

    @AppStorage("wakeOnProximity", store: ConfigStore.shared.defaults) private var wakeOnProximity = false
    @AppStorage("manualLockOnUserLock", store: ConfigStore.shared.defaults) private var manualLockOnUserLock = false
    @AppStorage("screensaver", store: ConfigStore.shared.defaults) private var screensaver = false
    @AppStorage("sleepDisplay", store: ConfigStore.shared.defaults) private var sleepDisplay = true
    @AppStorage("lockOnIdle", store: ConfigStore.shared.defaults) private var lockOnIdle = true

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. 蓝牙设备配对与扫描
                SettingsSectionGroup("蓝牙设备与配对", trailing: {
                    Button(action: toggleScanning) {
                        HStack(spacing: 4) {
                            if isScanning {
                                ProgressView()
                                    .controlSize(.mini)
                                Text("正在扫描...")
                            } else {
                                Image(systemName: "arrow.clockwise")
                                Text("扫描设备")
                            }
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }) {
                    VStack(spacing: 0) {
                        // 当前绑定设备状态行
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("当前绑定设备")
                                    .font(.system(size: 13, weight: .medium))
                                if let name = store.deviceName {
                                    Text(name)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("尚未绑定任何蓝牙设备（如 Apple Watch）")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            if store.deviceName != nil {
                                Button("解除绑定") {
                                    store.unbindDevice()
                                }
                                .controlSize(.small)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        // 扫描发现可用设备选择器
                        if !store.funManager.discoveredDevices.isEmpty {
                            Divider().padding(.leading, 16)
                            HStack {
                                Text("选择附近设备绑定")
                                    .font(.system(size: 13))
                                Spacer()
                                Picker("", selection: $selectedDeviceUUID) {
                                    Text("请选择周边检测到的设备").tag(Optional<UUID>(nil))
                                    ForEach(store.funManager.discoveredDevices, id: \.uuid) { dev in
                                        Text("\(dev.description) (\(dev.rssi) dBm)").tag(Optional(dev.uuid))
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 220)
                                .onChange(of: selectedDeviceUUID) { newUUID in
                                    if let uuid = newUUID,
                                       let found = store.funManager.discoveredDevices.first(where: { $0.uuid == uuid }) {
                                        store.bindDevice(uuid: uuid, name: found.description)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                    }
                }

                // 2. 守护总控与钥匙串安全
                SettingsSectionGroup("核心守护模式") {
                    VStack(spacing: 0) {
                        Toggle("启用近场守护", isOn: Binding(
                            get: { store.enabled },
                            set: { store.enabled = $0 }
                        ))
                        .font(.system(size: 13, weight: .medium))
                        .toggleStyle(.switch)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        Divider().padding(.leading, 16)

                        Toggle(isOn: Binding(
                            get: { store.realExecution },
                            set: { store.realExecution = $0 }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("真实执行驱动")
                                    .font(.system(size: 13, weight: .medium))
                                Text("关闭为「空跑观察」仅记录日志；开启后真正执行锁屏与解锁")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        Divider().padding(.leading, 16)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("钥匙串密码托管")
                                    .font(.system(size: 13, weight: .medium))
                                Text(store.hasPassword ? "已在安全钥匙串中加密保存" : "未录入，无法自动键入解锁")
                                    .font(.system(size: 11))
                                    .foregroundStyle(store.hasPassword ? Color.secondary : Color.orange)
                            }
                            Spacer()
                            Button(store.hasPassword ? "重新录入" : "录入密码") {
                                store.setOrChangePassword()
                            }
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }

                // 3. 测距阈值与空间校准
                SettingsSectionGroup("测距阈值与空间校准", trailing: {
                    Button("恢复推荐值") {
                        withAnimation(StudioAnimation.interactiveSpring) {
                            store.setUnlockRSSI(-60)
                            store.setLockRSSI(-70)
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }) {
                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("靠近解锁阈值")
                                    .font(.system(size: 13))
                                Spacer()
                                Text("\(store.unlockRSSI) dBm")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(StudioColor.emerald)
                            }
                            Slider(
                                value: Binding(
                                    get: { Double(store.unlockRSSI) },
                                    set: { store.setUnlockRSSI(Int($0)) }
                                ),
                                in: Double(GuardSignalConstants.minRSSI)...Double(GuardSignalConstants.maxRSSI),
                                step: 1
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        Divider().padding(.leading, 16)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("离席锁定阈值")
                                    .font(.system(size: 13))
                                Spacer()
                                Text("\(store.lockRSSI) dBm")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(StudioColor.amber)
                            }
                            Slider(
                                value: Binding(
                                    get: { Double(store.lockRSSI) },
                                    set: { store.setLockRSSI(Int($0)) }
                                ),
                                in: Double(GuardSignalConstants.minRSSI)...Double(GuardSignalConstants.maxRSSI),
                                step: 1
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        Divider().padding(.leading, 16)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("空间测距校准向导")
                                    .font(.system(size: 13))
                                Text("自动引导工位两阶段实测采样，计算最佳信号阈值")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("启动向导...") {
                                isPresentingWizard = true
                            }
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }

                // 4. 触发动作策略
                SettingsSectionGroup("靠近唤醒与离席策略") {
                    VStack(spacing: 0) {
                        Toggle(isOn: $wakeOnProximity) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("接近自动点亮屏幕")
                                    .font(.system(size: 13))
                                Text("进入靠近距离时，提前唤醒显示器")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        Divider().padding(.leading, 16)

                        Toggle(isOn: $manualLockOnUserLock) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("手动锁屏后暂不自动解锁")
                                    .font(.system(size: 13))
                                Text("按快捷键手动锁屏后暂停自动解锁，需手动输入密码一次以恢复")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        Divider().padding(.leading, 16)

                        Toggle(isOn: $sleepDisplay) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("离开后立即熄灭显示器")
                                    .font(.system(size: 13))
                                Text("锁屏同时休眠屏幕以节能省电")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        Divider().padding(.leading, 16)

                        Toggle(isOn: $lockOnIdle) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("键鼠输入中防误锁")
                                    .font(.system(size: 13))
                                Text("正在敲击键盘或移动鼠标时，即使信号抖动也不锁屏")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        Divider().padding(.leading, 16)

                        Toggle("使用屏幕保护程序替代熄屏", isOn: $screensaver)
                            .font(.system(size: 13))
                            .toggleStyle(.switch)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 30)
            .sheet(isPresented: $isPresentingWizard) {
                CalibrationWizardView(manager: store.funManager, isPresented: $isPresentingWizard)
            }
        }
    }

    private func toggleScanning() {
        if isScanning {
            store.stopScanning()
            isScanning = false
        } else {
            store.startScanning()
            isScanning = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                isScanning = false
            }
        }
    }
}

// MARK: - Tab 3: 安全与日志 (iMessage 异常推送 + 决策审计流水线)

struct DiagnosticsSettingsTab: View {
    @StateObject private var logger = DecisionLogger.shared
    @State private var filterCategory: DecisionCategory? = nil
    @State private var searchText = ""

    @AppStorage("iMessageNotify", store: ConfigStore.shared.defaults) private var iMessageNotify = false
    @AppStorage("iMessageNotifyRecipient", store: ConfigStore.shared.defaults) private var recipient = ""
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testSuccess = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // iMessage 告警
                SettingsSectionGroup("iMessage 远程异常告警") {
                    VStack(spacing: 0) {
                        Toggle(isOn: $iMessageNotify) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("开启解锁异常 iMessage 推送")
                                    .font(.system(size: 13, weight: .medium))
                                Text("连续多次解锁失败或疑似入侵时向手机发送警报")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        if iMessageNotify {
                            Divider().padding(.leading, 16)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("接收者手机号或 Apple ID")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                TextField("例如：+86 13800000000 或 example@icloud.com", text: $recipient)
                                    .textFieldStyle(.roundedBorder)

                                HStack {
                                    Button("发送测试通知") {
                                        runTest()
                                    }
                                    .disabled(isTesting || recipient.isEmpty)

                                    if isTesting {
                                        ProgressView().controlSize(.small)
                                    }
                                    if let res = testResult {
                                        Text(res)
                                            .font(.system(size: 11))
                                            .foregroundStyle(testSuccess ? .green : .red)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                }

                // 决策审计流水线
                SettingsSectionGroup("决策审计时序流水线", trailing: {
                    Button("清空历史") {
                        logger.clear()
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }) {
                    VStack(spacing: 0) {
                        // 搜索与过滤栏
                        HStack(spacing: 10) {
                            HStack(spacing: 6) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                TextField("搜索原因、设备或详情...", text: $searchText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        Divider().padding(.leading, 16)

                        // 过滤分类 Pills
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                FilterPill(title: "全部 (\(logger.events.count))", isSelected: filterCategory == nil) {
                                    filterCategory = nil
                                }
                                FilterPill(title: "解锁", isSelected: filterCategory == .unlock) {
                                    filterCategory = .unlock
                                }
                                FilterPill(title: "锁屏", isSelected: filterCategory == .lock) {
                                    filterCategory = .lock
                                }
                                FilterPill(title: "系统", isSelected: filterCategory == .system) {
                                    filterCategory = .system
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }

                        Divider().padding(.leading, 16)

                        // 事件列表
                        let events = filteredEvents
                        if events.isEmpty {
                            HStack {
                                Spacer()
                                Text("暂无决策事件记录")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                                Spacer()
                            }
                            .padding(.vertical, 30)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(events.prefix(30)) { event in
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(outcomeColor(event.outcome))
                                            .frame(width: 6, height: 6)

                                        Text(timeString(event.timestamp))
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.tertiary)

                                        Text(outcomeLabel(event.outcome))
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(outcomeColor(event.outcome))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(outcomeColor(event.outcome).opacity(0.12), in: Capsule())

                                        Text(event.detail)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)

                                        Spacer()

                                        if let dev = event.device {
                                            Text(dev)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }

                                        if let rssi = event.rssi {
                                            Text("\(rssi) dBm")
                                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                                .foregroundStyle(rssi >= -65 ? StudioColor.emerald : .secondary)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 9)

                                    if event.id != events.prefix(30).last?.id {
                                        Divider().padding(.leading, 32)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 30)
        }
    }

    private var filteredEvents: [DecisionEvent] {
        logger.events.filter { event in
            if let cat = filterCategory, event.category != cat { return false }
            if !searchText.isEmpty {
                let match = event.detail.localizedCaseInsensitiveContains(searchText)
                    || (event.device?.localizedCaseInsensitiveContains(searchText) ?? false)
                if !match { return false }
            }
            return true
        }
    }

    private func outcomeLabel(_ outcome: DecisionOutcome) -> String {
        switch outcome {
        case .success: return "成功"
        case .failed, .blocked: return "阻断"
        case .skipped: return "跳过"
        case .info: return "信息"
        }
    }

    private func outcomeColor(_ outcome: DecisionOutcome) -> Color {
        switch outcome {
        case .success: return StudioColor.emerald
        case .failed, .blocked: return StudioColor.rose
        case .skipped: return StudioColor.amber
        case .info: return StudioColor.cyan
        }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f.string(from: date)
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

// MARK: - 辅助筛选 Pill

struct FilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? Color.clear : Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}
