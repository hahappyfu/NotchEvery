//
//  AntigravityAccountsCardView.swift
//  NotchDrop
//
//  首页 Antigravity 4 账号池仪表盘（替换旧 OpenCodeGo 配额卡）。
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
        HStack(spacing: 8) {
            if store.accounts.isEmpty {
                Text("未检测到本地 Antigravity 账号")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(store.accounts) { account in
                    accountColumn(account)
                }
            }
        }
    }

    private func accountColumn(_ account: AntigravityAccount) -> some View {
        VStack(spacing: 5) {
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
                .studioPillBadge(color: account.isDisabled ? Color.white.opacity(0.35) : (account.percentage == 100 ? StudioColor.emerald : StudioColor.amber))
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
