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
}
