//
//  OverviewPageView.swift
//  NotchDrop
//
import SwiftUI

/// 第一页：配额卡（收窄）+ 暂存盘并排。
struct OverviewPageView: View {
    @StateObject var vm: NotchViewModel

    var body: some View {
        HStack(spacing: 12) {
            QuotaCardView(vm: vm)
                .frame(width: 150)
            Divider()
            TrayView(vm: vm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
