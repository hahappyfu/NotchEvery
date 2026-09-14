//
//  GuardCardView.swift
//  NotchDrop
//
//  守护卡（工单 03）：概览页第二张卡，与额度卡并列（面板结构定案 D，见 ADR-0013）。
//  两行均单行不折行，超长走省略号——折行会自己给自己加高度（原型阶段已验证）。
//

import AppKit
import SwiftUI

struct GuardCardView: View {
    @StateObject var vm: NotchViewModel
    @StateObject var store = GuardStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(stateColor)
                    .frame(width: 7, height: 7)
                Text("守护 · \(stateText)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                Spacer(minLength: 8)
                Text("真执行")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.52))
                Toggle("", isOn: Binding(
                    get: { store.realExecution },
                    set: { handleRealExecutionToggle($0) }
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
            if let issue = store.bluetoothIssue {
                Text(bluetoothText(issue))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.orange.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text(deviceLine)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.52))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            // 密码录入引导行（工单 09）：未录入锁屏密码时提示，单行省略
            if !store.hasPassword {
                HStack(spacing: 6) {
                    Text("未录入锁屏密码（自动解锁需要）")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.orange.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 6)
                    Button("去录入") { store.setOrChangePassword() }
                        .font(.system(size: 11))
                        .controlSize(.mini)
                }
            }
            // 上次未解锁回显（工单 08）：单行省略，点进诊断分区；无失败时不占行
            if let failure = store.lastUnlockFailure {
                Button(action: { vm.jumpToZone(.diagnostics) }) {
                    Text("上次未解锁：\(failure)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.orange.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .buttonStyle(.plain)
            }
            // 权限引导行（工单 07）：缺失项各一行（单行省略）+ 去开启/知道了；
            // 另起 slim 行重检。只在缺失时出现，不撑常态高度。
            ForEach(store.permissionIssues, id: \.kind) { issue in
                HStack(spacing: 6) {
                    Text("\(issue.title)：\(issue.reason)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.orange.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 6)
                    if issue.settingsURL != nil {
                        Button("去开启") { openSettings(issue) }
                            .font(.system(size: 11))
                    }
                    Button("知道了") { store.acknowledgePermission(issue.kind) }
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.52))
                }
            }
            if !store.permissionIssues.isEmpty {
                Button("重新检测授权状态") { store.recheckPermissions() }
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.52))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 360)
        .onAppear { store.start() }
        .onChange(of: vm.status) { status in
            if status == .closed {
                store.stop()
            } else {
                store.start()
            }
        }
    }

    private var stateText: String {
        switch store.guardState {
        case .disabled: return "停用"
        case .observing: return "空跑观察"
        case .guarding: return "守护中"
        }
    }

    private var stateColor: Color {
        switch store.guardState {
        case .disabled: return Color.white.opacity(0.35)
        case .observing: return .orange
        case .guarding: return .green
        }
    }

    private var deviceLine: String {
        guard let name = store.deviceName else { return "尚未绑定设备" }
        let rssi = store.rssi.map { "\($0) dBm" } ?? "-- dBm"
        return "\(name) · \(rssi) · 解锁 \(store.unlockRSSI) / 锁定 \(store.lockRSSI)"
    }

    private func bluetoothText(_ issue: BluetoothIssue) -> String {
        switch issue {
        case .poweredOff: return "蓝牙未开启，去系统设置打开蓝牙"
        case .unauthorized: return "未授予蓝牙权限，去系统设置授权"
        }
    }

    private func openSettings(_ issue: PermissionIssue) {
        guard let url = issue.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// 切换真执行开关：开启前做安全风险提示与接管检查（工单 09）
    private func handleRealExecutionToggle(_ newValue: Bool) {
        if !newValue {
            // 关闭真执行直接生效回空跑
            store.realExecution = false
            return
        }

        let alert = NSAlert()
        alert.messageText = "开启真执行守护"
        alert.alertStyle = .warning

        var infoLines: [String] = []
        infoLines.append("开启后 NotchEvery 将真正执行锁屏与自动密码解锁，不再仅是空跑观察。")
        infoLines.append("")

        let isFUnlockRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.fuhahah.FUnlock").isEmpty
        if isFUnlockRunning {
            infoLines.append("⚠️ 检测到原 FUnlock 正在运行！请先手动退出原 FUnlock（状态栏点退出或强制退出），避免两个应用同时测距与注入冲突。")
            infoLines.append("")
        } else {
            infoLines.append("⚠️ 如果原 FUnlock 仍在运行，请务必先手动退出，避免两个应用同时测距与注入冲突。")
            infoLines.append("")
        }

        infoLines.append("接管准备确认：")
        infoLines.append("1. 【重录密码】macOS Keychain 隔离不同应用，原 FUnlock 密码无法自动迁移，必须在此录入。")
        infoLines.append("2. 【系统权限】需确保辅助功能、蓝牙与完全磁盘访问三项权限均已开启。")

        alert.informativeText = infoLines.joined(separator: "\n")

        if !store.hasPassword {
            alert.addButton(withTitle: "录入密码并开启")
            alert.addButton(withTitle: "取消")
        } else {
            alert.addButton(withTitle: "确认开启")
            alert.addButton(withTitle: "取消")
        }

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if !store.hasPassword {
                store.setOrChangePassword()
                if store.hasPassword {
                    store.realExecution = true
                }
            } else {
                store.realExecution = true
            }
        }
    }
}
