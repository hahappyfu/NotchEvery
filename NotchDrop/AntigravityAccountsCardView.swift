//
//  AntigravityAccountsCardView.swift
//  NotchDrop
//
//  首页 Antigravity 4/5 账号池 3D 众星捧月立体环形舞台。
//  宽度固定 360pt，内边距与 GuardCardView 严格一致，不撑大面板。
//

import SwiftUI

struct AntigravityAccountsCardView: View {
    @StateObject var vm: NotchViewModel
    @StateObject var store = AntigravityStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func ringColor(_ percent: Int, isDisabled: Bool) -> Color {
        if isDisabled { return Color.white.opacity(0.2) }
        if percent >= 70 { return StudioColor.emerald }
        if percent >= 30 { return StudioColor.amber }
        return StudioColor.rose
    }

    /// 对称重排算法：
    /// 1. 优先提取最新调用的账号（或 isCurrent 标记）居中（distance = 0，聚光灯主焦点）
    /// 2. 其余账号按最近活跃时间倒序（无记录或相同则按配额降序），由近及远对称分布在两侧翼
    public static func symmetricRearrange(accounts: [AntigravityAccount]) -> [(account: AntigravityAccount, logicalDistance: Int)] {
        guard !accounts.isEmpty else { return [] }
        guard accounts.count > 1 else {
            return [(accounts[0], 0)]
        }

        // 统一排序规则：活跃时间越新越靠前；时间为空或相同时配额百分比越高越靠前
        let sortedByRecency = accounts.sorted { a, b in
            let timeA = a.lastActiveTime ?? .distantPast
            let timeB = b.lastActiveTime ?? .distantPast
            if timeA != timeB {
                return timeA > timeB
            }
            if a.percentage != b.percentage {
                return a.percentage > b.percentage
            }
            return a.id < b.id
        }

        // 中心账号：如果有明确 isCurrent 且位于列表中，优先使用；否则默认使用活跃度第一名
        let current: AntigravityAccount
        if let explicitCurrent = accounts.first(where: { $0.isCurrent }) {
            current = explicitCurrent
        } else {
            current = sortedByRecency[0]
        }

        // 其余账号按活跃度/配额降序
        let others = sortedByRecency.filter { $0.id != current.id }

        if others.count == 4 {
            // 标准 5 账号池排布：
            // - others[0] (第 2 新/上一轮活跃): 左内翼 -1
            // - others[1] (第 3 新): 右内翼 1
            // - others[2] (第 4 新): 右外翼 2
            // - others[3] (最久未活跃/最老): 左外翼 -2
            return [
                (others[3], -2),
                (others[0], -1),
                (current, 0),
                (others[1], 1),
                (others[2], 2)
            ]
        }

        // 通用 N 账号交替排布
        var left: [(AntigravityAccount, Int)] = []
        var right: [(AntigravityAccount, Int)] = []
        for (i, acc) in others.enumerated() {
            let dist = (i / 2) + 1
            if i % 2 == 0 {
                left.append((acc, -dist))
            } else {
                right.append((acc, dist))
            }
        }
        let sortedLeft = left.sorted { $0.1 < $1.1 }
        let sortedRight = right.sorted { $0.1 < $1.1 }
        return sortedLeft + [(current, 0)] + sortedRight
    }

    /// 获取首页展示的账号排列：
    /// 自动过滤隐藏已标记禁止反代（proxy_disabled）或已禁用的账号，
    /// 仅将真正可用的反代账号送入 3D 对称重排算法。
    public static func arrangedAccounts(from accounts: [AntigravityAccount]) -> [(account: AntigravityAccount, logicalDistance: Int)] {
        let activeAccounts = accounts.filter { !$0.isDisabled }
        guard !activeAccounts.isEmpty else { return [] }
        return symmetricRearrange(accounts: activeAccounts)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            accountsRow
            disabledAccountsRow
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
        // 收起兜底：面板收起时本卡片随子树被条件渲染整体摘除，onChange 收不到 .closed，
        // 不停的话 AntigravityStore 的后台轮询会永久跑下去。
        .onDisappear { store.stop() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(StudioColor.emerald)
                .frame(width: 7, height: 7)
            Text("Antigravity 账号池")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
            Spacer(minLength: 8)
            if let current = store.accounts.first(where: { $0.isCurrent }) {
                Text("当前: \(current.name)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
            } else if let currentId = store.currentAccountId {
                Text("当前: \(currentId)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
    }

    private var accountsRow: some View {
        let arranged = Self.arrangedAccounts(from: store.accounts)
        return HStack(spacing: 6) {
            if arranged.isEmpty {
                Text(store.accounts.isEmpty ? "未检测到本地 Antigravity 账号" : "暂无可用反代账号")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(arranged, id: \.account.id) { item in
                    accountCard(item.account, distance: item.logicalDistance)
                }
            }
        }
        .animation(reduceMotion ? nil : StudioAnimation.interactiveSpring, value: arranged.map(\.account.id))
    }

    /// 禁用账号下置行：主排只展示可用账号，被禁用的账号收敛到下方一行紧凑小胶囊，
    /// 不再占用主排大卡位。数量多时可横向滚动查看，整行仅在存在禁用账号时出现。
    @ViewBuilder
    private var disabledAccountsRow: some View {
        let disabled = store.accounts.filter(\.isDisabled)
        if !disabled.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(disabled) { account in
                        disabledCapsule(account)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    /// 单个禁用账号胶囊：灰点 + 姓名 + 「已禁用」微标，高约 22pt，玻璃底。
    private func disabledCapsule(_ account: AntigravityAccount) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.white.opacity(0.30))
                .frame(width: 4, height: 4)
            Text(account.name)
                .font(.system(size: 8.5))
                .foregroundStyle(Color.white.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.tail)
                .fixedSize(horizontal: true, vertical: false)
                // fixedSize 会抵消省略号，需给姓名一个宽度上限：短名按理想宽自适应，超长名截断出「…」
                .frame(maxWidth: 70, alignment: .leading)
            Text("已禁用")
                .font(.system(size: 8.5))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(Color.white.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(StudioMaterial.strokeNormal, lineWidth: 0.5))
    }

    private func rotationAngle(for distance: Int) -> Double {
        switch distance {
        case -2: return 22.0
        case -1: return 12.0
        case 1: return -12.0
        case 2: return -22.0
        default:
            if distance < 0 { return 22.0 }
            if distance > 0 { return -22.0 }
            return 0.0
        }
    }

    private func scale(for distance: Int) -> CGFloat {
        switch abs(distance) {
        case 0: return 1.08
        case 1: return 0.95
        default: return 0.88
        }
    }

    private func zIndex(for distance: Int) -> Double {
        switch abs(distance) {
        case 0: return 3
        case 1: return 2
        default: return 1
        }
    }

    private func yOffset(for distance: Int) -> CGFloat {
        switch abs(distance) {
        case 0: return -3
        case 1: return -1
        default: return 0
        }
    }

    private func brightness(for distance: Int) -> Double {
        -0.10 * Double(abs(distance))
    }

    private func accountCard(_ account: AntigravityAccount, distance: Int) -> some View {
        accountColumn(account)
            .offset(y: yOffset(for: distance))
            .scaleEffect(scale(for: distance))
            .rotation3DEffect(
                .degrees(reduceMotion ? 0 : rotationAngle(for: distance)),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.45
            )
            .zIndex(zIndex(for: distance))
            .brightness(brightness(for: distance))
            .shadow(
                color: distance == 0 ? Color.black.opacity(0.55) : Color.black.opacity(abs(distance) == 1 ? 0.25 : 0.15),
                radius: distance == 0 ? 12 : (abs(distance) == 1 ? 5 : 3),
                x: 0,
                y: distance == 0 ? 6 : (abs(distance) == 1 ? 2 : 1)
            )
            .shadow(
                color: distance == 0 ? StudioColor.emerald.opacity(0.28) : .clear,
                radius: 8,
                x: 0,
                y: 2
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if !account.isCurrent {
                    store.selectAccount(id: account.id)
                }
            }
    }

    private func accountColumn(_ account: AntigravityAccount) -> some View {
        let badgeColor = account.isDisabled ? Color.white.opacity(0.35) : (account.displayPercentage == 100 ? StudioColor.emerald : (account.displayPercentage >= 30 ? StudioColor.amber : StudioColor.rose))
        // 方案 1 恢复 Gemini 主力额度展示：底部胶囊已有明确的「周重置」倒计时，不再常态显示右上角琥珀微标
        let isWeeklyTier = false

        return VStack(spacing: 5) {
            Text(account.name)
                .font(.system(size: 11, weight: account.isCurrent ? .semibold : .regular))
                .foregroundStyle(account.isDisabled ? Color.white.opacity(0.4) : (account.isCurrent ? Color.white.opacity(0.95) : Color.white.opacity(0.65)))
                .lineLimit(1)
                .truncationMode(.tail)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: 3.5)
                    .frame(width: 44, height: 44)

                Circle()
                    .trim(from: 0, to: CGFloat(min(100, max(0, account.displayPercentage))) / 100.0)
                    .stroke(
                        Self.ringColor(account.displayPercentage, isDisabled: account.isDisabled),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 44, height: 44)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: account.displayPercentage)

                Text("\(account.displayPercentage)%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(account.isDisabled ? Color.white.opacity(0.35) : Color.white.opacity(0.92))
            }
            .overlay(
                Group {
                    if account.isCurrent {
                        Circle()
                            .stroke(StudioColor.emerald.opacity(0.4), lineWidth: 1.5)
                            .frame(width: 52, height: 52)
                    }
                }
            )
            .overlay(alignment: .topTrailing) {
                if isWeeklyTier {
                    weeklyTierBadge
                }
            }

            Text(statusText(for: account))
                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(badgeColor.opacity(0.16), in: Capsule())
                .overlay(Capsule().strokeBorder(badgeColor.opacity(0.32), lineWidth: 0.5))
                .foregroundStyle(badgeColor)
                .lineLimit(1)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .studioCard(radius: 8, isSelected: account.isCurrent)
        .opacity(account.isDisabled ? 0.6 : 1.0)
    }

    /// 周额度降级微标：骑在圆环右上角的琥珀色小胶囊，仅在 5h 耗尽、周额度接管时不打扰地点亮。
    private var weeklyTierBadge: some View {
        Text("周额度")
            .font(.system(size: 7.5, weight: .semibold))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(StudioColor.amber.opacity(0.16), in: Capsule())
            .foregroundStyle(StudioColor.amber)
            .offset(x: 7, y: -3)
    }

    /// 底部状态胶囊文案：
    /// - 已禁用 → 「已禁用」；
    /// - 周额度档位且未满 → 带「周重置」前缀的天级/小时级倒计时；
    /// - 满额 → 沿用原逻辑「在用中 / 已就绪」；
    /// - 其余（5h 正常档位未满）→ 当前档位重置倒计时。
    private func statusText(for account: AntigravityAccount) -> String {
        if account.isDisabled { return "已禁用" }
        if account.currentTier == .weekly && account.displayPercentage < 100 {
            let countdown = account.resetCountdownText
            return countdown == "已就绪" ? "等待周重置" : "周重置 \(countdown)"
        }
        if account.displayPercentage == 100 {
            return account.isCurrent ? "在用中" : "已就绪"
        }
        return account.resetCountdownText
    }
}

extension AntigravityAccount {
    var resetCountdownText: String {
        AntigravityStore.formatCountdown(from: resetTime)
    }
}

#if DEBUG
#Preview {
    AntigravityAccountsCardView(vm: .init())
        .padding()
        .background(Color.black)
}
#endif
