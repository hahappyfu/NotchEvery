//
//  OverviewPageView.swift
//  NotchDrop
//
import SwiftUI

/// 第一页：今日模型用量分布卡（自带定宽 410pt 与完整卡片样式，容器内居中显示）。
struct OverviewPageView: View {
    let vm: NotchViewModel

    var body: some View {
        ModelDistributionCardView()
    }
}
