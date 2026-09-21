//
//  QoderPoolRingView.swift
//  NotchEvery
//
//  网关分区第一张卡：Qoder 账号池。
//  严格对齐第一页 AntigravityAccountsCardView 的设计系统（360pt 定宽，18/12 边距，3D 对称排布），
//  每个账号做成【圆形】；顶栏集成状态点、标题、粘性号与启停控制按钮。
//

import SwiftUI

struct QoderPoolRingView: View {
    @ObservedObject var manager: QoderGatewayManager
    @ObservedObject var store: QoderStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 三态取色：冷却 amber、最近探针失败 rose、正常 emerald；离线灰。
    static func ringColor(_ m: QoderPoolMember, isRunning: Bool) -> Color {
        guard isRunning else { return Color.white.opacity(0.2) }
        if m.cooled { return StudioColor.amber }
        if !m.lastProbeOK { return StudioColor.rose }
        return StudioColor.emerald
    }

    /// 脱敏 user_id 取尾 4 位显示。
    static func tail(_ userId: String) -> String {
        let trimmed = userId.replacingOccurrences(of: "*", with: "")
        return String(trimmed.suffix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            membersRow
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 360)
    }

    private var isRunning: Bool {
        if case .running = manager.state { return true }
        return false
    }

    private var statusDotColor: Color {
        switch manager.state {
        case .running: return StudioColor.emerald
        case .crashed: return StudioColor.rose
        case .starting, .stopping: return StudioColor.amber
        case .stopped: return Color.white.opacity(0.3)
        }
    }

    private var stickyId: String? {
        if let s = store.poolStatusStickyId, store.poolMembers.contains(where: { $0.userId == s }) { return s }
        return store.poolMembers
            .filter { !$0.cooled }
            .max { ($0.lastUsedAt ?? .distantPast) < ($1.lastUsedAt ?? .distantPast) }?
            .userId
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 7, height: 7)
            Text("Qoder 账号池")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
            if let sticky = stickyId, isRunning {
                Text("粘性: …\(Self.tail(sticky))")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            toggleButton
        }
    }

    // MARK: - 启停按钮（集成在卡片顶栏右侧）

    @ViewBuilder
    private var toggleButton: some View {
        let busy = manager.state == .starting || manager.state == .stopping
        Button {
            switch manager.state {
            case .stopped: manager.start()
            case .crashed: manager.retry()
            case .running: manager.stop()
            default: break
            }
        } label: {
            HStack(spacing: 4) {
                if busy {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.65)
                } else {
                    Image(systemName: buttonIcon)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(buttonTitle)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(buttonForeground)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(buttonBackground))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.6 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: manager.state)
    }

    private var buttonIcon: String {
        switch manager.state {
        case .running: return "stop.fill"
        case .stopped: return "play.fill"
        case .crashed: return "arrow.clockwise"
        case .starting, .stopping: return "hourglass"
        }
    }

    private var buttonTitle: String {
        switch manager.state {
        case .running: return "停止"
        case .stopped: return "启动"
        case .crashed: return "重试"
        case .starting: return "启动中"
        case .stopping: return "停止中"
        }
    }

    private var buttonForeground: Color {
        switch manager.state {
        case .running: return StudioColor.rose
        case .stopped, .crashed: return StudioColor.emerald
        default: return Color.white.opacity(0.6)
        }
    }

    private var buttonBackground: Color {
        switch manager.state {
        case .running: return StudioColor.rose.opacity(0.12)
        case .stopped, .crashed: return StudioColor.emerald.opacity(0.12)
        default: return Color.white.opacity(0.08)
        }
    }

    // MARK: - 账号成员行（圆形）

    private var membersRow: some View {
        let arranged = AntigravityAccountsCardView.symmetricRearrange(
            accounts: store.poolMembers.map { member in
                AntigravityAccount(
                    id: member.userId,
                    name: Self.tail(member.userId),
                    email: "",
                    isCurrent: member.userId == stickyId,
                    isDisabled: false,
                    percentage: member.cooled ? 0 : 100,
                    resetTime: nil,
                    lastActiveTime: member.lastUsedAt
                )
            }
        )
        return HStack(spacing: 6) {
            if !isRunning {
                Text(emptyStateText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 14)
            } else if arranged.isEmpty {
                Text("等待账号池状态…")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 14)
            } else {
                ForEach(arranged, id: \.account.id) { item in
                    circleMember(item.account, distance: item.logicalDistance)
                }
            }
        }
        .animation(reduceMotion ? nil : StudioAnimation.interactiveSpring, value: arranged.map(\.account.id))
    }

    private var emptyStateText: String {
        if case .crashed(let reason) = manager.state {
            return "网关异常 · \(reason)"
        }
        return "网关未运行 · 点击右上角启动"
    }

    private func circleMember(_ account: AntigravityAccount, distance: Int) -> some View {
        let member = store.poolMembers.first(where: { $0.userId == account.id })
        let color = Self.ringColor(member ?? .placeholder(account.id), isRunning: isRunning)
        let scale: CGFloat = distance == 0 ? 1.08 : (abs(distance) == 1 ? 0.95 : 0.88)

        return VStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.9), lineWidth: 3)
                    .background(Circle().fill(Color.white.opacity(0.06)))
                VStack(spacing: 1) {
                    Text(account.name)
                        .font(.system(size: 10.5, weight: account.isCurrent ? .bold : .medium).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(account.isCurrent ? 0.95 : 0.7))
                    if member?.cooled == true {
                        Image(systemName: "snowflake")
                            .font(.system(size: 8))
                            .foregroundStyle(StudioColor.amber)
                    } else if member.map({ !$0.lastProbeOK }) == true {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(StudioColor.rose)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(StudioColor.emerald.opacity(0.8))
                    }
                }
            }
            .frame(width: 46, height: 46)
            .overlay(
                account.isCurrent
                    ? Circle().stroke(color.opacity(0.25), lineWidth: 5).blur(radius: 3)
                    : nil
            )
        }
        .offset(y: distance == 0 ? -3 : (abs(distance) == 1 ? -1 : 0))
        .scaleEffect(reduceMotion ? 1.0 : scale)
        .rotation3DEffect(
            .degrees(reduceMotion ? 0 : rotationAngle(for: distance)),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.45
        )
        .zIndex(distance == 0 ? 3 : (abs(distance) == 1 ? 2 : 1))
        .brightness(-0.10 * Double(abs(distance)))
        .help(tooltip(member))
    }

    private func rotationAngle(for distance: Int) -> Double {
        switch distance {
        case -2: return 22.0
        case -1: return 12.0
        case 1: return -12.0
        case 2: return -22.0
        default: return distance < 0 ? 22.0 : (distance > 0 ? -22.0 : 0.0)
        }
    }

    private func tooltip(_ m: QoderPoolMember?) -> String {
        guard let m else { return "" }
        var s = "\(m.userId)\n来源: \(m.source)"
        s += "\n状态: \(m.cooled ? "冷却中" : "活跃") · 探针\(m.lastProbeOK ? "通过" : "未通过/未探")"
        if let t = m.lastUsedAt { s += "\n最近使用: \(t.formatted(date: .omitted, time: .shortened))" }
        return s
    }
}
