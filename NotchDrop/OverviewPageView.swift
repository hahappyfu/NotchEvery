//
//  OverviewPageView.swift
//  NotchDrop
//
import SwiftUI

/// 第一页：Antigravity 账号卡居中（暂存盘已删，ADR-0009）+ 守护卡并列（工单 03，面板结构定案 D）。
struct OverviewPageView: View {
    @StateObject var vm: NotchViewModel

    var body: some View {
        VStack(spacing: 10) {
            AntigravityAccountsCardView(vm: vm)
                // 边距加在内容上，不撑容器（容器加边距会被 520 定宽居中溢出吃掉）
                .padding(.horizontal, 14)
                // 整行展示卡：完整包裹配额数据区，左右平衡（清单 05；底从配额卡体内上提）
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            GuardCardView(vm: vm)
                .padding(.horizontal, 14)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
