//
//  QoderPoolRingView.swift
//  NotchEvery
//
//  网关分区账号池：照第一页 AntigravityAccountsCardView 的设计语言（3D 众星捧月对称环形排布、
//  同字号/边距体系），但每个账号项做成【圆形】——圆内上排脱敏尾号、下排冷却态图标。
//  描边色：active=emerald / cooled=amber / 探针失败=rose / 离线灰=white 0.2。
//

import SwiftUI

struct QoderPoolRingView: View {
    @ObservedObject var store: QoderStore
    var port: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 三态取色：冷却 amber、最近探针失败 rose、正常 emerald；无数据灰。
    static func ringColor(_ m: QoderPoolMember, poolOnline: Bool) -> Color {
        guard poolOnline else { return Color.white.opacity(0.2) }
        if m.cooled { return StudioColor.amber }
        if !m.lastProbeOK { return StudioColor.rose }
        return StudioColor.emerald
    }

    /// 脱敏 user_id 取尾 4 位显示（形如 "01a***…4a9" → "4a9"）。
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

    private var poolOnline: Bool { !store.poolMembers.isEmpty }

    /// 粘性号：优先 /v1/pool/status 顶层 sticky_user_id；缺字段时兜底取最近使用的活跃号。
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
                .fill(poolOnline ? StudioColor.emerald : Color.white.opacity(0.25))
                .frame(width: 7, height: 7)
            Text("Qoder 账号池")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
            Spacer(minLength: 8)
            if store.isQuotaStale {
                // stale 时 stickyId 已空，右上角给离线提示（对齐「· 离线」后缀语义）
                Text("· 离线")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.45))
            } else if let sticky = stickyId {
                Text("粘性: …\(Self.tail(sticky))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
    }

    private var membersRow: some View {
        // 复用第一页对称重排：粘性号居中，其余按最近活跃倒序分布两翼
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
            if arranged.isEmpty {
                Text(store.isQuotaStale ? "网关无响应 · 池状态读取失败" : "网关未运行")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(arranged, id: \.account.id) { item in
                    circleMember(item.account, distance: item.logicalDistance)
                }
            }
        }
        .animation(reduceMotion ? nil : StudioAnimation.interactiveSpring, value: arranged.map(\.account.id))
    }

    private func circleMember(_ account: AntigravityAccount, distance: Int) -> some View {
        let member = store.poolMembers.first(where: { $0.userId == account.id })
        let color = Self.ringColor(member ?? .placeholder(account.id), poolOnline: poolOnline)
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
                        Image(systemName: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
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
                // 粘性当前号：外圈柔光强调（对齐第一页主焦点绿影）
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
