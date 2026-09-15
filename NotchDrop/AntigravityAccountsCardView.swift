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

    /// 对称重排算法：提取当前在用账号居中（distance = 0），其余账号按配额降序在两侧对称排布
    public static func symmetricRearrange(accounts: [AntigravityAccount]) -> [(account: AntigravityAccount, logicalDistance: Int)] {
        guard !accounts.isEmpty else { return [] }
        guard accounts.count > 1 else {
            return [(accounts[0], 0)]
        }

        let current = accounts.first(where: { $0.isCurrent }) ?? accounts[0]
        let others = accounts.filter { $0.id != current.id }.sorted { $0.percentage > $1.percentage }

        if others.count == 4 {
            // 标准 5 账号池：[-2: 最低/禁用, -1: 最高额度陪衬, 0: 当前在用中心, 1: 次高额度陪衬, 2: 再次高/低额]
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            accountsRow
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
        let arranged = Self.symmetricRearrange(accounts: store.accounts)
        return HStack(spacing: 6) {
            if arranged.isEmpty {
                Text("未检测到本地 Antigravity 账号")
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
        .animation(reduceMotion ? nil : StudioAnimation.interactiveSpring, value: store.currentAccountId)
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
        let badgeColor = account.isDisabled ? Color.white.opacity(0.35) : (account.percentage == 100 ? StudioColor.emerald : StudioColor.amber)

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
                    .trim(from: 0, to: CGFloat(min(100, max(0, account.percentage))) / 100.0)
                    .stroke(
                        Self.ringColor(account.percentage, isDisabled: account.isDisabled),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 44, height: 44)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: account.percentage)

                Text("\(account.percentage)%")
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

            Text(account.isDisabled ? "已禁用" : (account.percentage == 100 ? "已就绪" : account.resetCountdownText))
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
