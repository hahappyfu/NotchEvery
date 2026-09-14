//
//  CalibrationWizardView.swift
//  NotchEvery
//
//  空间测距校准向导（移植自 FUnlock）：引导用户完成工位靠近采样与离开采样，
//  自动计算最佳解锁与锁定 RSSI 阈值，一键应用。
//

import SwiftUI
import AppKit

struct CalibrationWizardView: View {
    @ObservedObject var manager: FUnManager
    @Binding var isPresented: Bool

    @State private var step = 0          // 0=欢迎, 1=解锁倒计时, 2=解锁采样, 3=锁定倒计时, 4=锁定采样, 5=结果
    @State private var countdown = 0
    @State private var samplingProgress: Double = 0
    @State private var samples: [Int] = []
    @State private var avgUnlock: Int = 0
    @State private var avgLock: Int = 0
    @State private var samplingTask: Task<Void, Never>?
    @State private var countdownTask: Task<Void, Never>?
    @State private var currentRSSI: Int? = nil
    @State private var errorMessage = "" // 采样失败提示

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            // 流线型步骤指示器 (1 → 2 → 3)
            stepProgressIndicator
                .padding(.horizontal, 20)
                .padding(.bottom, 6)

            Form {
                switch step {
                case 0: welcomeSection
                case 1: unlockCountdownSection
                case 2: unlockSamplingSection
                case 3: lockCountdownSection
                case 4: lockSamplingSection
                case 5: resultSection
                default: EmptyView()
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 380, height: 465)
        .onDisappear {
            samplingTask?.cancel()
            countdownTask?.cancel()
        }
    }

    // MARK: - 步骤进度指示器 (1 → 2 → 3)

    private var currentStage: Int {
        switch step {
        case 1, 2: return 1
        case 3, 4: return 2
        case 5: return 3
        default: return 0
        }
    }

    @ViewBuilder
    private var stepProgressIndicator: some View {
        HStack(spacing: 0) {
            stepNode(number: 1, title: "靠近采样", isActive: currentStage == 1, isCompleted: currentStage > 1)

            stepConnectorLine(isCompleted: currentStage > 1)

            stepNode(number: 2, title: "离席采样", isActive: currentStage == 2, isCompleted: currentStage > 2)

            stepConnectorLine(isCompleted: currentStage > 2)

            stepNode(number: 3, title: "推荐阈值", isActive: currentStage == 3, isCompleted: currentStage == 3 && step == 5)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(StudioMaterial.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(StudioMaterial.strokeNormal, lineWidth: 0.5)
        )
    }

    private func stepNode(number: Int, title: String, isActive: Bool, isCompleted: Bool) -> some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(
                        isCompleted
                            ? StudioColor.emerald
                            : (isActive ? Color.accentColor : StudioMaterial.cardBackground)
                    )
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle().strokeBorder(
                            isActive ? Color.accentColor.opacity(0.8) : StudioMaterial.strokeNormal,
                            lineWidth: isActive ? 1.5 : 0.5
                        )
                    )
                    .shadow(
                        color: isActive ? Color.accentColor.opacity(0.4) : (isCompleted ? StudioColor.emerald.opacity(0.3) : .clear),
                        radius: isActive ? 3 : 1
                    )

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(isActive ? .white : .secondary)
                }
            }

            Text(title)
                .font(.system(size: 9.5, weight: (isActive || isCompleted) ? .medium : .regular))
                .foregroundStyle((isActive || isCompleted) ? .primary : .secondary)
        }
    }

    private func stepConnectorLine(isCompleted: Bool) -> some View {
        VStack {
            Capsule()
                .fill(isCompleted ? StudioColor.emerald : StudioMaterial.strokeNormal)
                .frame(height: 2)
                .padding(.horizontal, 4)
                .offset(y: -7)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.3), value: isCompleted)
    }

    // MARK: - Header

    @ViewBuilder
    private var headerBar: some View {
        HStack {
            Text("空间测距校准")
                .font(.headline)
            Spacer()
            Button(action: { cancelAndClose() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // MARK: - Step 0: 欢迎

    @ViewBuilder private var welcomeSection: some View {
        Section {
            VStack(spacing: 14) {
                Image(systemName: "location.viewfinder")
                    .font(.system(size: 38))
                    .foregroundColor(.accentColor)
                    .padding(.top, 6)
                Text("工位空间距离校准")
                    .font(.title3).fontWeight(.semibold)
                Text("通过佩戴 Apple Watch 站在靠近与离开电脑的不同位置，向导会自动采样真实环境信号，为你计算最稳定的解锁与锁屏阈值。")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                if !errorMessage.isEmpty {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)

            Button("开始校准") { startUnlockCalibration() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Step 1: 解锁倒计时

    @ViewBuilder private var unlockCountdownSection: some View {
        Section("步骤 1 / 2：靠近解锁位置") {
            VStack(spacing: 14) {
                Text("请正常坐在电脑前，佩戴好手表并保持自然姿态。倒计时后将开始采样。")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                CalibrationRing(
                    progress: Double(countdown) / 5.0,
                    size: 96,
                    rssi: currentRSSI,
                    isSampling: false,
                    isProximity: true
                ) {
                    Text("\(countdown)")
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                }

                Text("准备开始靠近采样...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Step 2: 解锁采样

    @ViewBuilder private var unlockSamplingSection: some View {
        Section {
            VStack(spacing: 14) {
                Text("正在采样靠近信号...")
                    .font(.headline)
                Text("请保持当前位置，双手自然放在键盘附近。")
                    .font(.callout)
                    .foregroundColor(.secondary)

                CalibrationRing(
                    progress: samplingProgress,
                    size: 96,
                    rssi: currentRSSI,
                    isSampling: true,
                    isProximity: true
                ) {
                    VStack(spacing: 2) {
                        Text(currentRSSI.map { "\($0)" } ?? "—")
                            .font(.system(size: 26, weight: .bold, design: .monospaced))
                        Text("dBm")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Text("已采集 \(samples.count) 个信号样本")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Step 3: 锁定倒计时

    @ViewBuilder private var lockCountdownSection: some View {
        Section("步骤 2 / 2：离席锁定位置") {
            VStack(spacing: 14) {
                Text("请起身离开电脑，走到你希望电脑自动锁屏的距离（如离开工位 1~2 米）。")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                CalibrationRing(
                    progress: Double(countdown) / 10.0,
                    size: 100,
                    rssi: currentRSSI,
                    isSampling: false,
                    isProximity: false
                ) {
                    VStack(spacing: 2) {
                        Text("\(countdown)")
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                        Text("秒")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                if countdown > 0 {
                    Text("请走至离开位置...")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Step 4: 锁定采样

    @ViewBuilder private var lockSamplingSection: some View {
        Section {
            VStack(spacing: 14) {
                Text("正在采样离开信号...")
                    .font(.headline)
                Text("请停在离开位置，保持姿态。")
                    .font(.callout)
                    .foregroundColor(.secondary)

                CalibrationRing(
                    progress: samplingProgress,
                    size: 96,
                    rssi: currentRSSI,
                    isSampling: true,
                    isProximity: false
                ) {
                    VStack(spacing: 2) {
                        Text(currentRSSI.map { "\($0)" } ?? "—")
                            .font(.system(size: 26, weight: .bold, design: .monospaced))
                        Text("dBm")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Text("已采集 \(samples.count) 个信号样本")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Step 5: 结果

    @ViewBuilder private var resultSection: some View {
        Section {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 34))
                    .foregroundColor(.green)
                Text("校准完成")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)

            resultRow(icon: "lock.open.fill", label: "靠近实测平均", value: "\(avgUnlock) dBm", color: .green)
            resultRow(icon: "lock.fill", label: "离开实测平均", value: "\(avgLock) dBm", color: .orange)
            resultRow(icon: "slider.horizontal.3", label: "推荐解锁阈值", value: "\(suggestedUnlock) dBm", color: .blue)
            resultRow(icon: "slider.horizontal.3", label: "推荐锁定阈值", value: "\(suggestedLock) dBm", color: .purple)

            HStack(spacing: 12) {
                Button("取消") { cancelAndClose() }
                    .buttonStyle(.bordered)
                Button("应用推荐值") { applyValues() }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
    }

    private func resultRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            Text(label)
                .font(.callout)
            Spacer()
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .fontWeight(.medium)
        }
    }

    // MARK: - 计算

    private var suggestedUnlock: Int {
        let v = avgUnlock - 2
        return min(max(v, -93), -30)
    }

    private var suggestedLock: Int {
        let rawLock = min(max(avgLock - 2, -95), -30)
        // 防倒挂约束：锁定阈值必须小于解锁阈值（至少保持 5 dBm 安全迟滞间距）
        return min(rawLock, max(suggestedUnlock - 5, -95))
    }

    // MARK: - 流程控制

    private func startUnlockCalibration() {
        step = 1
        countdown = 5
        samples = []
        errorMessage = ""
        countdownTask = Task {
            for i in (1...5).reversed() {
                guard !Task.isCancelled else { return }
                countdown = i
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard !Task.isCancelled else { return }
            startSampling(duration: 8, completion: {
                guard !Task.isCancelled else { return }
                guard let avg = self.averageSamples() else {
                    self.abortCalibration()
                    return
                }
                self.avgUnlock = avg
                self.startLockCountdown()
            })
        }
    }

    private func startLockCountdown() {
        step = 3
        countdown = 10
        samples = []
        countdownTask = Task {
            for i in (1...10).reversed() {
                guard !Task.isCancelled else { return }
                countdown = i
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard !Task.isCancelled else { return }
            startSampling(duration: 8, completion: {
                guard !Task.isCancelled else { return }
                guard let avg = self.averageSamples() else {
                    self.abortCalibration()
                    return
                }
                self.avgLock = avg
                NSSound(named: "Glass")?.play()
                self.step = 5
            })
        }
    }

    private func startSampling(duration: Int, completion: @escaping () -> Void) {
        step = (step == 1) ? 2 : 4
        samples = []
        samplingProgress = 0
        samplingTask = Task {
            let totalMs = duration * 10
            for i in 0..<totalMs {
                guard !Task.isCancelled else { return }
                if let rssi = manager.rssi {
                    samples.append(rssi)
                    currentRSSI = rssi
                }
                samplingProgress = Double(i) / Double(totalMs)
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            guard !Task.isCancelled else { return }
            samplingProgress = 1.0
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            completion()
        }
    }

    private func averageSamples() -> Int? {
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0, +) / samples.count
    }

    private func abortCalibration() {
        samplingTask?.cancel()
        countdownTask?.cancel()
        samplingTask = nil
        countdownTask = nil
        samples = []
        currentRSSI = nil
        errorMessage = "未检测到信号，请靠近设备后重试"
        step = 0
    }

    private func applyValues() {
        manager.setUnlockRSSI(suggestedUnlock)
        manager.setLockRSSI(suggestedLock)
        cancelAndClose()
    }

    private func cancelAndClose() {
        samplingTask?.cancel()
        countdownTask?.cancel()
        samplingTask = nil
        countdownTask = nil
        isPresented = false
    }
}

// MARK: - 环形雷达进度组件

private struct CalibrationRing<Content: View>: View {
    let progress: Double
    var color: Color? = nil
    let size: CGFloat
    var rssi: Int? = nil
    var isSampling: Bool = false
    var isProximity: Bool = true
    @ViewBuilder var center: () -> Content

    @State private var isBreathing = false

    private var isStrongSignal: Bool {
        if let rssi = rssi {
            return rssi >= -68
        }
        return isProximity
    }

    private var activeGradient: LinearGradient {
        if isStrongSignal {
            // 测距雷达圆环在信号强时由 StudioColor.cyan 渐变为 StudioColor.emerald
            return LinearGradient(
                colors: [StudioColor.cyan, StudioColor.emerald],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if isProximity {
            return LinearGradient(
                colors: [StudioColor.cyan, Color.accentColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [StudioColor.amber, StudioColor.rose],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var body: some View {
        ZStack {
            // 采样呼吸雷达光晕
            if isSampling {
                Circle()
                    .fill(activeGradient)
                    .frame(width: size - 12, height: size - 12)
                    .opacity(isBreathing ? 0.20 : 0.06)
                    .blur(radius: 6)

                Circle()
                    .strokeBorder(activeGradient, lineWidth: 1.5)
                    .frame(width: size + (isBreathing ? 14 : 2), height: size + (isBreathing ? 14 : 2))
                    .opacity(isBreathing ? 0.0 : 0.55)
            }

            // 底层轨道
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: 7)
                .frame(width: size, height: size)

            // 进度圆环
            if let singleColor = color, !isSampling {
                Circle()
                    .trim(from: 0, to: max(0, min(1, progress)))
                    .stroke(singleColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
                    .animation(isSampling ? .linear(duration: 0.1) : .easeInOut(duration: 0.25), value: progress)
            } else {
                Circle()
                    .trim(from: 0, to: max(0, min(1, progress)))
                    .stroke(activeGradient, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: isStrongSignal ? StudioColor.emerald.opacity(0.4) : StudioColor.amber.opacity(0.3), radius: 3)
                    .animation(isSampling ? .linear(duration: 0.1) : .easeInOut(duration: 0.25), value: progress)
            }

            center()
        }
        .onAppear {
            if isSampling {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
        }
    }
}
