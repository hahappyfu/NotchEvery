//
//  OverviewPageView.swift
//  NotchDrop
//
import SwiftUI

/// 第一页：配额卡（收窄）+ 暂存盘并排。
struct OverviewPageView: View {
    @StateObject var vm: NotchViewModel

    var body: some View {
        HStack(spacing: 16) {
            // 小方块自定尺寸（宽随高），不再定宽 240，多余宽度让给暂存盘（清单 08）
            QuotaCardView(vm: vm)
            TrayView(vm: vm)
        }
        // 边距加在内容上：压弹性 Tray，不撑容器（容器加边距会被 520 定宽居中溢出吃掉）
        // 页面级垂直内边距去掉：顶部留白只剩安全区+外层 top 10（02 票）
        .padding(.horizontal, 14)
        // 整行展示卡：完整包裹配额数据区 + 拖拽交互区，左右平衡（清单 05；底从配额卡体内上提）
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
