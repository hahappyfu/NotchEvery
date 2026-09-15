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

    // 校准向导弹窗
    @State private var showCalibration = false

    // 雷达呼吸微动效
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.65
    @State private var isPulsing = false

    // 底部按钮悬停态
    @State private var hoverCalibration = false
    @State private var hoverPreferences = false

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
            startPulseAnimation()
        }
        .onDisappear {
            stopPulseAnimation()
        }
        .onChange(of: vm.status) { status in
            if status == .closed {
                stopPulseAnimation()
                store.stop()
            } else {
                store.start()
                startPulseAnimation()
            }
        }
        .onChange(of: store.guardState) { state in
            if state == .disabled {
                stopPulseAnimation()
            } else {
                startPulseAnimation()
            }
        }
    }

    // MARK: - Header 状态行（左状态+中设备+右控制舒展分层）

    private var header: some View {
        HStack(spacing: 8) {
            // 左侧：呼吸指示灯与守护状态
            HStack(spacing: 6) {
                ZStack {
                    if store.guardState != .disabled {
                        Circle()
                            .stroke(pulseColor.opacity(pulseOpacity), lineWidth: 1.5)
                            .scaleEffect(pulseScale)
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

            Spacer(minLength: 4)

            // 中间：设备名与 RSSI，自适应空间避免截断
            Text(deviceSummary)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(0.52))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            Spacer(minLength: 4)

            // 右侧：紧凑控制开关（真执行 + 启用）
            HStack(spacing: 6) {
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

                Toggle("", isOn: Binding(
                    get: { store.enabled },
                    set: { store.enabled = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
        }
    }

    private var pulseColor: Color {
        stateColor
    }

    private func startPulseAnimation() {
        guard store.guardState != .disabled, vm.status != .closed else {
            stopPulseAnimation()
            return
        }
        guard !isPulsing else { return }
        isPulsing = true
        pulseScale = 1.0
        pulseOpacity = 0.65
        withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
            pulseScale = 2.4
            pulseOpacity = 0.0
        }
    }

    private func stopPulseAnimation() {
        isPulsing = false
        withAnimation(.default) {
            pulseScale = 1.0
            pulseOpacity = 0.65
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

    // MARK: - RSSI 阈值快速调节

    private var thresholdRow: some View {
        HStack(spacing: 12) {
            // 解锁阈值
            thresholdCard(
                title: "解锁",
                value: "\(store.unlockRSSI) dBm",
                canDecrement: store.unlockRSSI > -93,
                canIncrement: store.unlockRSSI < -30,
                onDecrement: {
                    let next = max(store.unlockRSSI - 1, -93)
                    store.setUnlockRSSI(next)
                },
                onIncrement: {
                    let next = min(store.unlockRSSI + 1, -30)
                    store.setUnlockRSSI(next)
                }
            )

            // 锁定阈值
            thresholdCard(
                title: "锁屏",
                value: "\(store.lockRSSI) dBm",
                canDecrement: store.lockRSSI > -95,
                canIncrement: store.lockRSSI + 1 <= store.unlockRSSI - 2,
                onDecrement: {
                    let next = max(store.lockRSSI - 1, -95)
                    store.setLockRSSI(next)
                },
                onIncrement: {
                    guard store.lockRSSI + 1 <= store.unlockRSSI - 2 else { return }
                    store.setLockRSSI(store.lockRSSI + 1)
                }
            )
        }
    }

    private func thresholdCard(
        title: String,
        value: String,
        canDecrement: Bool,
        canIncrement: Bool,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))

            Spacer(minLength: 2)

            Button {
                withAnimation(StudioAnimation.interactiveSpring) {
                    onDecrement()
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(canDecrement ? Color.white.opacity(0.85) : Color.white.opacity(0.25))
                    .frame(width: 18, height: 18)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .disabled(!canDecrement)

            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(minWidth: 54, alignment: .center)

            Button {
                withAnimation(StudioAnimation.interactiveSpring) {
                    onIncrement()
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(canIncrement ? Color.white.opacity(0.85) : Color.white.opacity(0.25))
                    .frame(width: 18, height: 18)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .disabled(!canIncrement)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .studioCard(radius: 8)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 最近判定事件卡片（双行舒展展示）

    private var recentJudgementCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let latest = logger.events.last {
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
