//
//  iOSPageIndicator.swift
//  NotchDrop
//
import SwiftUI

/// 分页指示器（grill-with-docs 重构）：macOS 原生细碎风，移除悬浮容器，直接融入卡片底部。
/// 一行「非当前」6×6 圆点（primary 0.25）+「当前」7×6 胶囊以 spring 掠过点阵标亮（primary 0.75），
/// 点间距 6pt，点击圆点直达该页；reduceMotion 下切页动画直通。
struct SmoothPageIndicator: View {
    let pageCount: Int
    @Binding var currentPage: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let point: CGFloat = 6
    private let spacing: CGFloat = 6
    /// 胶囊 ≈ 单点宽：掠过时像高亮扫过，不拉宽点阵
    private var capsuleWidth: CGFloat { 7 }
    /// 点中心步距 = 直径 + 间距
    private var stride: CGFloat { point + spacing }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<pageCount, id: \.self) { i in
                Circle()
                    .fill(Color.primary.opacity(0.25))
                    .frame(width: point, height: point)
                    // 命中区以点为中心外扩，不改变点间距布局
                    .overlay {
                        Color.clear
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                            .onTapGesture { currentPage = i }
                    }
            }
        }
        .frame(height: 10)
        .overlay {
            GeometryReader { geo in
                Capsule()
                    .fill(Color.primary.opacity(0.75))
                    .frame(width: capsuleWidth, height: point)
                    .position(
                        x: (CGFloat(currentPage) * stride) + point / 2,
                        y: geo.size.height / 2
                    )
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82),
                        value: currentPage
                    )
            }
        }
    }
}

#Preview {
    VStack(spacing: 8) {
        SmoothPageIndicator(pageCount: 2, currentPage: .constant(0))
        SmoothPageIndicator(pageCount: 2, currentPage: .constant(1))
    }
    .padding()
    .background(Color(nsColor: .windowBackgroundColor))
}