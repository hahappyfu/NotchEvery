//
//  QoderPoolRingView.swift
//  NotchEvery
//
//  网关分区第一张卡：Qoder 账号池。
//  严格对齐第一页 AntigravityAccountsCardView 的设计系统（360pt 定宽，18/12 边距，3D 对称排布），
//  每个账号做成【圆形 Orb】：底层哑光槽 + 状态光环 + 尾号 + 状态副标；
//  顶栏集成状态点、标题、粘性号与启停微胶囊按钮。
//

import SwiftUI

struct QoderPoolRingView: View {
    @ObservedObject var manager: QoderGatewayManager
    @ObservedObject var store: QoderStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Orb 直径（任务 2 规定 48×48pt）。
    private static let orbDiameter: CGFloat = 48

    /// 取色规则（UI redesign unit A · 任务 1）：消灭「全红报警感」。
    /// - 主力/粘性号：emerald（配绿光晕）
    /// - 冷却号：amber（配迷你雪花）
    /// - 备用未冷却：哑光冰白银圈（正常工作态，探针未通过/未探测同样走此中性色，绝不整圈大红）
    static func ringColor(_ m: QoderPoolMember, isCurrent: Bool, isRunning: Bool) -> Color {
        guard isRunning else { return Color.white.opacity(0.20) }
        if isCurrent { return StudioColor.emerald }
        if m.cooled { return StudioColor.amber }
        return Color.white.opacity(0.38)
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

    /// 顶栏状态点：running 薄荷绿、crashed 暗红、忙态琥珀、stopped 深石墨灰。
    private var statusDotColor: Color {
        switch manager.state {
        case .running: return StudioColor.emerald
        case .crashed: return StudioColor.rose.opacity(0.75)
        case .starting, .stopping: return StudioColor.amber
        case .stopped: return Color.white.opacity(0.18)
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
            refreshButton
            Spacer(minLength: 4)
            toggleButton
        }
    }

    // MARK: - 手动刷新额度胶囊（原「粘性: …xxxx」标签位，替换为常驻刷新入口）

    private var refreshButton: some View {
        Button {
            Task { await store.triggerManualQuotaRefresh() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(store.isProbingPoolQuotas ? 360 : 0))
                    .animation(store.isProbingPoolQuotas ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: store.isProbingPoolQuotas)
                Text("刷新")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(Color.white.opacity(store.isProbingPoolQuotas ? 0.4 : 0.85))
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Color.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(StudioMaterial.strokeNormal, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(store.isProbingPoolQuotas)
    }

    // MARK: - 启停微胶囊（集成在卡片顶栏右侧）

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
                        .font(.system(size: buttonIconSize, weight: .semibold))
                }
                Text(buttonTitle)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(buttonForeground)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(buttonBackground))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.6 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: manager.state)
    }

    /// 运行态用极小方形停止图标（约 7pt），其余态维持常规尺寸。
    private var buttonIconSize: CGFloat {
        if case .running = manager.state { return 7 }
        return 10
    }

    private var buttonIcon: String {
        switch manager.state {
        case .running: return "square.fill"
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
        case .running: return Color.white.opacity(0.88)
        case .stopped, .crashed: return StudioColor.emerald
        default: return Color.white.opacity(0.6)
        }
    }

    private var buttonBackground: Color {
        switch manager.state {
        case .running: return Color.white.opacity(0.08)
        case .stopped, .crashed: return StudioColor.emerald.opacity(0.12)
        default: return Color.white.opacity(0.08)
        }
    }

    // MARK: - 账号成员行（圆形 Orb）

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
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(reduceMotion ? nil : StudioAnimation.interactiveSpring, value: arranged.map(\.account.id))
    }

    private var emptyStateText: String {
        if case .crashed(let reason) = manager.state {
            return "网关异常 · \(reason)"
        }
        return "网关未运行 · 点击右上角启动"
    }

    /// 多层 Orb：底层哑光槽 → 2.5pt 状态光环 → 尾号 + 状态副标。
    private func circleMember(_ account: AntigravityAccount, distance: Int) -> some View {
        let member = store.poolMembers.first(where: { $0.userId == account.id }) ?? .placeholder(account.id)
        let color = Self.ringColor(member, isCurrent: account.isCurrent, isRunning: isRunning)
        let scale: CGFloat = distance == 0 ? 1.08 : (abs(distance) == 1 ? 0.95 : 0.88)
        let d = Self.orbDiameter

        return VStack(spacing: 5) {
            // 3D 聚光灯变换只作用于圆本体，避免连带把下方余额行甩出卡片可视区
            ZStack {
                // 1. 底层槽：极淡填充 + 细边框，构成哑光玻璃底座
                Circle()
                    .fill(Color.white.opacity(0.04))
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)

                // 2. 状态光环：覆盖底层槽之上的 2.5pt 环形条
                Circle()
                    .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

                // 3. 文字排版：尾号 + 等高状态副标
                VStack(spacing: 2) {
                    Text(account.name)
                        .font(.system(size: 11, weight: account.isCurrent ? .bold : .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(account.isCurrent ? 0.95 : 0.72))
                    statusGlyph(member)
                }
            }
            .frame(width: d, height: d)
            .shadow(color: account.isCurrent && isRunning ? StudioColor.emerald.opacity(0.35) : .clear, radius: 6, y: 0)
            .offset(y: distance == 0 ? -3 : (abs(distance) == 1 ? -1 : 0))
            .scaleEffect(reduceMotion ? 1.0 : scale)
            .rotation3DEffect(
                .degrees(reduceMotion ? 0 : rotationAngle(for: distance)),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.45
            )
            .brightness(-0.10 * Double(abs(distance)))

            // 环下方余额小字：一眼可见该号剩余额度（探测不到则留空占位，保持各 Orb 等高）
            balanceLabel(for: account.id)
        }
        .zIndex(distance == 0 ? 3 : (abs(distance) == 1 ? 2 : 1))
        .help(tooltip(member))
    }

    /// 状态副标（各态统一 9pt 占位高度，保证呼吸感一致）：
    /// - 冷却：8pt 琥珀 snowflake
    /// - 探针通过 / 主力号：迷你实心绿点
    /// - 备用未冷却且探针未通过/未探测：极淡灰白短横（中性点缀，不用红三角、不整圈大红）
    @ViewBuilder
    private func statusGlyph(_ m: QoderPoolMember) -> some View {
        ZStack {
            if m.cooled {
                Image(systemName: "snowflake")
                    .font(.system(size: 8))
                    .foregroundStyle(StudioColor.amber)
            } else if m.lastProbeOK || m.userId == stickyId {
                Circle()
                    .fill(StudioColor.emerald.opacity(0.9))
                    .frame(width: 5, height: 5)
            } else {
                Capsule()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 9, height: 2)
            }
        }
        .frame(height: 9)
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

    /// 环下方余额小字：显示该号剩余额度（Int 取整，与顶部卡口径一致）。
    /// 未探测到余额时显示占位「--」并保留等高占位，避免各 Orb 高度不齐。
    @ViewBuilder
    private func balanceLabel(for userId: String) -> some View {
        let text = quota(for: userId).map { "\(Int($0.totalRemaining))" } ?? "--"
        Text(text)
            .font(.system(size: 9, weight: .medium).monospacedDigit())
            .foregroundStyle(Color.white.opacity(userId == stickyId ? 0.85 : 0.5))
            .frame(height: 11)
    }

    /// 整屏 Orb id —— 关联余额必须带上它做「多对一」歧义保护：
    /// 单看某个 Orb 命中唯一不代表安全，邻座 Orb 可能也在抢同一份余额。
    private var orbIds: [String] { store.poolMembers.map(\.userId) }

    /// Orb（脱敏 id）→ 该号额度快照。两侧 id 格式不同，相等匹配永远失败，故走 QoderPoolIdMatcher
    /// （详见该文件头注释）；任何歧义一律返回 nil → UI 降级为 `--`，绝不张冠李戴。
    private func quota(for userId: String) -> QoderAccountQuota? {
        QoderPoolIdMatcher.quota(for: userId, amongAllOrbs: orbIds, in: store.poolQuotas)
    }

    private func tooltip(_ m: QoderPoolMember?) -> String {
        guard let m else { return "" }
        var s = "\(m.userId)\n来源: \(m.source)"
        s += "\n状态: \(m.cooled ? "冷却中" : "活跃") · 探针\(m.lastProbeOK ? "通过" : "未通过/未探")"
        if let q = quota(for: m.userId) { s += "\n余额 \(Int(q.totalRemaining)) credits" }
        if let t = m.lastUsedAt { s += "\n最近使用: \(t.formatted(date: .omitted, time: .shortened))" }
        return s
    }
}
