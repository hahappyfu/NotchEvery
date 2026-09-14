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
        .frame(width: 380, height: 430)
        .onDisappear {
            samplingTask?.cancel()
            countdownTask?.cancel()
        }
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

                CalibrationRing(progress: Double(countdown) / 5.0,
                                color: .accentColor, size: 96) {
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

                CalibrationRing(progress: samplingProgress, color: .green, size: 96) {
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

                CalibrationRing(progress: Double(countdown) / 10.0,
                                color: .orange, size: 100) {
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

                CalibrationRing(progress: samplingProgress, color: .red, size: 96) {
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
        return min(max(v, -95), -30)
    }

    private var suggestedLock: Int {
        let v = avgLock - 2
        return min(max(v, -95), -30)
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
            samplingProgress = 1.0
            try? await Task.sleep(nanoseconds: 200_000_000)
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
        samples = []
        currentRSSI = nil
        errorMessage = "未检测到信号，请靠近设备后重试"
        step = 0
    }

    private func applyValues() {
        let lock = max(min(suggestedLock, -30), -95)
        let unlock = max(min(suggestedUnlock, -30), -95)
        let finalUnlock = max(unlock, lock + 5)
        manager.setUnlockRSSI(finalUnlock)
        manager.setLockRSSI(lock)
        isPresented = false
    }

    private func cancelAndClose() {
        samplingTask?.cancel()
        countdownTask?.cancel()
        isPresented = false
    }
}

// MARK: - 环形进度组件

private struct CalibrationRing<Content: View>: View {
    let progress: Double
    let color: Color
    let size: CGFloat
    @ViewBuilder var center: () -> Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 7)
                .frame(width: size, height: size)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
            center()
        }
    }
}
