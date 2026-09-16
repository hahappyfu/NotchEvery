//
//  GuardControlZoneView.swift
//  NotchEvery
//
//  第三页：守护控制台（替换原 DiagZoneView 长列表）。
//  定宽 390pt，包含 2×2 高频开关、RSSI 阈值快捷步进调节、精简双行判定卡片与校准向导入口。
//

import AppKit
import SwiftUI

// MARK: - 第三页布局常量与指标

enum GuardSignalConstants {
    static let minRSSI: Int = -95
    static let maxRSSI: Int = -40
    static let minSafetyGap: Int = 3
}

enum GuardControlLayout {
    /// 控制台舒展宽度（增加 30pt 排版余量）
    static let preferredWidth: CGFloat = 390
    static let horizontalPadding: CGFloat = 18
    static let verticalPadding: CGFloat = 12
    static let toggleGridSpacing: CGFloat = 12
    static let toggleCardFontSize: CGFloat = 11.5
    static let judgementDetailLineLimit: Int = 2

    /// 计算出的单列 2x2 开关卡片可用宽度（> 170pt）
    static var toggleColumnWidth: CGFloat {
        let available = preferredWidth - (horizontalPadding * 2) - toggleGridSpacing
        return available / 2
    }
}

struct GuardControlZoneView: View {
    @StateObject var vm: NotchViewModel
    @StateObject var store = GuardStore.shared
    @StateObject private var logger = DecisionLogger.shared

    // 高频行为开关持久化绑定（读取 ConfigStore.shared.defaults）
    @AppStorage("wakeOnProximity", store: ConfigStore.shared.defaults) private var wakeOnProximity = false
    @AppStorage("sleepDisplay", store: ConfigStore.shared.defaults) private var sleepDisplay = true
    @AppStorage("screensaver", store: ConfigStore.shared.defaults) private var screensaver = false
    @AppStorage("lockOnIdle", store: ConfigStore.shared.defaults) private var lockOnIdle = true
    @AppStorage("iMessageNotify", store: ConfigStore.shared.defaults) private var iMessageNotify = false

    // 校准向导弹窗
    @State private var showCalibration = false

    // 底部按钮悬停态
    @State private var hoverCalibration = false
    @State private var hoverPreferences = false
    @State private var hoverAuthButton = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            togglesGrid
            thresholdRow
            recentJudgementCard
            bottomActions
        }
        .padding(.horizontal, GuardControlLayout.horizontalPadding)
        .padding(.vertical, GuardControlLayout.verticalPadding)
        .frame(width: GuardControlLayout.preferredWidth)
        .sheet(isPresented: $showCalibration) {
            CalibrationWizardView(manager: store.funManager, isPresented: $showCalibration)
        }
        .onAppear {
            store.start()
            logger.loadHistory()
        }
        .onChange(of: vm.status) { status in
            if status == .closed {
                store.stop()
            } else {
                store.start()
            }
        }
    }

    // MARK: - Header 状态行（左状态+右控制两端对齐）

    private var header: some View {
        HStack(spacing: 8) {
            // 左侧：状态指示灯与守护状态
            HStack(spacing: 6) {
                ZStack {
                    if store.guardState != .disabled {
                        Circle()
                            .stroke(stateColor.opacity(0.35), lineWidth: 1.5)
                    }
                    Circle()
                        .fill(stateColor)
                        .frame(width: 7, height: 7)
                }
                .frame(width: 14, height: 14)

                Text("守护控制 · \(stateText)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .fixedSize()
            }

            Spacer()

            // 右侧：紧凑控制开关（守护 + 真执行）
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("守护")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.52))
                        .fixedSize()
                    Toggle("", isOn: Binding(
                        get: { store.enabled },
                        set: { store.enabled = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }

                HStack(spacing: 4) {
                    Text("真执行")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.52))
                        .fixedSize()
                    Toggle("", isOn: Binding(
                        get: { store.realExecution },
                        set: { store.realExecution = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
            }
        }
    }

    static func stateText(for state: GuardState) -> String {
        switch state {
        case .disabled: return "停用"
        case .observing: return "空跑"
        case .guarding: return "生效中"
        }
    }

    private var stateText: String {
        Self.stateText(for: store.guardState)
    }

    private var stateColor: Color {
        switch store.guardState {
        case .disabled: return Color.white.opacity(0.35)
        case .observing: return StudioColor.amber
        case .guarding: return StudioColor.emerald
        }
    }

    static func deviceSummary(name: String? = nil, rssi: Int? = nil) -> String {
        guard let name = name else { return "未绑定设备" }
        let rssiStr = rssi.map { "\($0) dBm" } ?? "-- dBm"
        return "\(name) · \(rssiStr)"
    }

    private var deviceSummary: String {
        Self.deviceSummary(name: store.deviceName, rssi: store.rssi)
    }

    // MARK: - 2×2 高频行为开关（舒展展示，防文字截断）

    private var togglesGrid: some View {
        VStack(spacing: 6) {
            HStack(spacing: GuardControlLayout.toggleGridSpacing) {
                toggleItem("接近唤醒屏幕", isOn: $wakeOnProximity)
                toggleItem("离开立即熄屏", isOn: $sleepDisplay)
            }
            HStack(spacing: GuardControlLayout.toggleGridSpacing) {
                toggleItem("屏保替代熄屏", isOn: $screensaver)
                toggleItem("键鼠活动保护", isOn: $lockOnIdle)
            }
        }
        .padding(.vertical, 2)
    }

    private func toggleItem(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: GuardControlLayout.toggleCardFontSize, weight: isOn.wrappedValue ? .medium : .regular))
                .foregroundStyle(Color.white.opacity(isOn.wrappedValue ? 0.95 : 0.80))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 4)
            Toggle("", isOn: Binding(
                get: { isOn.wrappedValue },
                set: { newValue in
                    withAnimation(StudioAnimation.interactiveSpring) {
                        isOn.wrappedValue = newValue
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .allowsHitTesting(false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            withAnimation(StudioAnimation.interactiveSpring) {
                isOn.wrappedValue.toggle()
            }
        }
        .studioCard(radius: 10, isSelected: isOn.wrappedValue)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 空间距离与信号可视化滑动条（Dual Sliders + Live Radar Needle）

    private var thresholdRow: some View {
        GuardSignalRangeSlider(store: store)
    }
}

// MARK: - GuardSignalRangeSlider 组件

struct GuardSignalRangeSlider: View {
    @ObservedObject var store: GuardStore

    var body: some View {
        VStack(spacing: 8) {
            // 顶部：实时信号状态条（Live Radar Needle 提示）
            liveSignalHeader

            // 中部：空间可视化指示标尺（含刻度、区间色带与实时动态光标）
            spatialTrackView

            // 底部：双滑块控制（贴近解锁 & 离开锁屏）
            slidersControlView
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .studioCard(radius: 8)
    }

    // MARK: - 实时信号状态条
    private var liveSignalHeader: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(liveSignalColor)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle()
                        .stroke(liveSignalColor.opacity(0.4), lineWidth: 1.5)
                        .scaleEffect(store.rssi != nil ? 1.6 : 1.0)
                )

            Text(liveSignalTitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.90))

            Spacer()

            if let rssi = store.rssi {
                Text(Self.distanceDescription(for: rssi))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
        }
    }

    private var liveSignalTitle: String {
        guard let rssi = store.rssi else {
            return "当前信号: 未检测到设备"
        }
        let zone = Self.zoneDescription(rssi: rssi, unlockRSSI: store.unlockRSSI, lockRSSI: store.lockRSSI)
        return "当前信号: \(rssi) dBm · \(zone)"
    }

    private var liveSignalColor: Color {
        guard let rssi = store.rssi else { return Color.white.opacity(0.3) }
        if rssi >= store.unlockRSSI {
            return StudioColor.emerald
        } else if rssi > store.lockRSSI {
            return StudioColor.amber
        } else {
            return StudioColor.rose
        }
    }

    // MARK: - 空间可视化标尺与光标
    private var spatialTrackView: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    // 背景渐变轨道（-95dBm 锁屏区 -> 缓冲 -> -40dBm 解锁区）
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: StudioColor.rose.opacity(0.35), location: 0.0),
                                    .init(color: StudioColor.amber.opacity(0.25), location: 0.45),
                                    .init(color: StudioColor.emerald.opacity(0.45), location: 1.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 6)

                    // 锁屏与解锁阈值分割标记点
                    let lockPos = normalizedPosition(for: store.lockRSSI, in: width)
                    let unlockPos = normalizedPosition(for: store.unlockRSSI, in: width)

                    // 离开锁屏阈值竖线
                    Rectangle()
                        .fill(StudioColor.rose)
                        .frame(width: 1.5, height: 10)
                        .offset(x: max(0, min(width - 1.5, lockPos)))

                    // 靠近解锁阈值竖线
                    Rectangle()
                        .fill(StudioColor.emerald)
                        .frame(width: 1.5, height: 10)
                        .offset(x: max(0, min(width - 1.5, unlockPos)))

                    // 实时信号光标（Live Radar Needle）
                    if let rssi = store.rssi {
                        let clampedRSSI = max(GuardSignalConstants.minRSSI, min(GuardSignalConstants.maxRSSI, rssi))
                        let needlePos = normalizedPosition(for: clampedRSSI, in: width)

                        ZStack {
                            // 微光扩散光晕
                            Circle()
                                .fill(StudioColor.emerald.opacity(0.35))
                                .frame(width: 12, height: 12)

                            // 实体中心游标
                            Circle()
                                .fill(Color.white)
                                .frame(width: 5, height: 5)
                                .overlay(
                                    Circle()
                                        .stroke(StudioColor.emerald, lineWidth: 1.5)
                                )
                        }
                        .offset(x: max(0, min(width - 12, needlePos - 6)))
                    }
                }
            }
            .frame(height: 12)

            // 标尺两端与物理距离提示
            HStack {
                Text("离座锁屏 (-95)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.white.opacity(0.45))
                Spacer()
                Text("防抖缓冲")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.35))
                Spacer()
                Text("贴近解锁 (-40)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
        }
    }

    // MARK: - 双滑块控制区
    private var slidersControlView: some View {
        VStack(spacing: 6) {
            // 靠近解锁阈值滑块
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(StudioColor.emerald)
                    Text("靠近解锁")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .frame(width: 68, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { Double(store.unlockRSSI) },
                        set: { newUnlock in
                            updateUnlockRSSI(Int(newUnlock))
                        }
                    ),
                    in: Double(GuardSignalConstants.minRSSI + GuardSignalConstants.minSafetyGap)...Double(GuardSignalConstants.maxRSSI),
                    step: 1
                )
                .tint(StudioColor.emerald)
                .controlSize(.mini)

                Text("\(store.unlockRSSI) dBm")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(StudioColor.emerald)
                    .frame(width: 52, alignment: .trailing)
            }

            // 离开锁屏阈值滑块
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(StudioColor.rose)
                    Text("离开锁屏")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .frame(width: 68, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { Double(store.lockRSSI) },
                        set: { newLock in
                            updateLockRSSI(Int(newLock))
                        }
                    ),
                    in: Double(GuardSignalConstants.minRSSI)...Double(GuardSignalConstants.maxRSSI - GuardSignalConstants.minSafetyGap),
                    step: 1
                )
                .tint(StudioColor.rose)
                .controlSize(.mini)

                Text("\(store.lockRSSI) dBm")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(StudioColor.rose)
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }

    // MARK: - 安全互锁与阈值调节逻辑
    private func updateUnlockRSSI(_ newUnlock: Int) {
        let clampedUnlock = max(GuardSignalConstants.minRSSI + GuardSignalConstants.minSafetyGap, min(GuardSignalConstants.maxRSSI, newUnlock))
        if clampedUnlock - store.lockRSSI < GuardSignalConstants.minSafetyGap {
            let newLock = max(GuardSignalConstants.minRSSI, clampedUnlock - GuardSignalConstants.minSafetyGap)
            store.setLockRSSI(newLock)
        }
        store.setUnlockRSSI(clampedUnlock)
    }

    private func updateLockRSSI(_ newLock: Int) {
        let clampedLock = max(GuardSignalConstants.minRSSI, min(GuardSignalConstants.maxRSSI - GuardSignalConstants.minSafetyGap, newLock))
        if store.unlockRSSI - clampedLock < GuardSignalConstants.minSafetyGap {
            let newUnlock = min(GuardSignalConstants.maxRSSI, clampedLock + GuardSignalConstants.minSafetyGap)
            store.setUnlockRSSI(newUnlock)
        }
        store.setLockRSSI(clampedLock)
    }

    private func normalizedPosition(for rssi: Int, in totalWidth: CGFloat) -> CGFloat {
        let minR = CGFloat(GuardSignalConstants.minRSSI)
        let maxR = CGFloat(GuardSignalConstants.maxRSSI)
        let r = CGFloat(max(GuardSignalConstants.minRSSI, min(GuardSignalConstants.maxRSSI, rssi)))
        let ratio = (r - minR) / (maxR - minR)
        return ratio * totalWidth
    }

    // MARK: - 静态语义转换函数（供测试与视图共享）
    static func zoneDescription(rssi: Int, unlockRSSI: Int, lockRSSI: Int) -> String {
        if rssi >= unlockRSSI {
            return "已在解锁区"
        } else if rssi > lockRSSI {
            return "处于缓冲区分界"
        } else {
            return "处于离座锁屏区"
        }
    }

    static func distanceDescription(for rssi: Int) -> String {
        switch rssi {
        case -50 ... -30:
            return "贴身 (<0.5米)"
        case -65 ..< -50:
            return "工位近距 (~1米)"
        case -80 ..< -65:
            return "中距离 (~2-3米)"
        case -90 ..< -80:
            return "远距离 (~4-6米)"
        default:
            return "极远/微弱 (>6米)"
        }
    }
}

extension GuardControlZoneView {
    // MARK: - 最近判定事件卡片（双行舒展展示）与系统授权引导

    /// 提纯核心判定事件（过滤掉非锁屏决策的异步通道错误，如 iMessageFailed）
    static func latestCoreEvent(in events: [DecisionEvent]) -> DecisionEvent? {
        events.last(where: { event in
            if event.category == .system && event.reason == .iMessageFailed {
                return false
            }
            return true
        })
    }

    /// 检测最近是否存在 iMessage 推送受限/失败（仅在用户开启通知时响应）
    static func hasRecentIMessageFailure(in events: [DecisionEvent], isNotifyEnabled: Bool) -> Bool {
        guard isNotifyEnabled else { return false }
        return events.contains(where: { $0.category == .system && $0.reason == .iMessageFailed })
    }

    private var latestCoreEvent: DecisionEvent? {
        Self.latestCoreEvent(in: logger.events)
    }

    private var hasRecentIMessageFailure: Bool {
        Self.hasRecentIMessageFailure(in: logger.events, isNotifyEnabled: iMessageNotify)
    }

    private var recentJudgementCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let latest = latestCoreEvent {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(outcomeColor(latest.outcome))
                            .frame(width: 6, height: 6)
                        Text(Self.timeString(latest.timestamp))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.45))
                        Text(Self.outcomeText(latest.outcome))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(outcomeColor(latest.outcome))
                        Spacer()
                    }

                    let detail = Self.judgementDetail(for: latest)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineLimit(GuardControlLayout.judgementDetailLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .studioCard(radius: 8)
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
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .studioCard(radius: 8)
            }

            if hasRecentIMessageFailure {
                iMessageAuthGuideView
            }
        }
    }

    private var iMessageAuthGuideView: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(StudioColor.amber)

            Text("iMessage 发送受限，需开启自动化权限")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.white.opacity(0.80))
                .lineLimit(1)

            Spacer(minLength: 4)

            Button(action: {
                openSystemAutomationSettings()
            }) {
                Text("去设置开启授权")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(StudioColor.amber)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(StudioColor.amber.opacity(0.15), in: Capsule())
                    .overlay(Capsule().strokeBorder(StudioColor.amber.opacity(hoverAuthButton ? 0.45 : 0.25), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .onHover { hoverAuthButton = $0 }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .studioCard(radius: 8)
    }

    private func openSystemAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 操作底栏（平分宽度，字号居中）

    private var bottomActions: some View {
        HStack(spacing: 10) {
            Button(action: { showCalibration = true }) {
                HStack(spacing: 5) {
                    Image(systemName: "location.viewfinder")
                        .font(.system(size: 11, weight: .medium))
                    Text("空间测距校准")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Color.white.opacity(hoverCalibration ? 0.98 : 0.85))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .studioCard(radius: 8, isHovered: hoverCalibration)
            .onHover { hoverCalibration = $0 }

            Button(action: { openPreferences() }) {
                HStack(spacing: 5) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .medium))
                    Text("完整偏好设置...")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Color.white.opacity(hoverPreferences ? 0.98 : 0.85))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .studioCard(radius: 8, isHovered: hoverPreferences)
            .onHover { hoverPreferences = $0 }
        }
    }

    private func openPreferences() {
        vm.notchClose()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            PreferencesWindowController.shared.show()
        }
    }

    // MARK: - 判定与文本转换纯函数（供内部及测试使用）

    static func judgementDetail(for event: DecisionEvent) -> String {
        if !event.detail.isEmpty {
            return event.detail
        }
        return event.reason?.localizedTitle ?? event.reason?.rawValue ?? ""
    }

    static func timeString(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private func outcomeColor(_ outcome: DecisionOutcome) -> Color {
        switch outcome {
        case .success: return StudioColor.emerald
        case .failed, .blocked: return StudioColor.rose
        case .skipped, .info: return Color.white.opacity(0.45)
        }
    }

    static func outcomeText(_ outcome: DecisionOutcome) -> String {
        switch outcome {
        case .success: return "成功"
        case .skipped: return "跳过"
        case .failed: return "失败"
        case .blocked: return "拦截"
        case .info: return "信息"
        }
    }
}
