//
//  iOSPageIndicator.swift
//  NotchDrop
//
import SwiftUI

/// 分页指示器：深色 dock 胶囊容器，双槽 morph——当前页 13×5 白 0.95、非当前 5×5 白 0.3，
/// 切页以 spring 形变，点击槽直达该页；reduceMotion 下动画直通。
/// 收进面板后缩一档（约 0.8×），命中区保持易点。
struct SmoothPageIndicator: View {
    let pageCount: Int
    @Binding var currentPage: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<pageCount, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(i == currentPage ? 0.95 : 0.3))
                    .frame(width: i == currentPage ? 13 : 5, height: 5)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82),
                        value: currentPage
                    )
                    .overlay {
                        Color.clear
                            .frame(width: 18, height: 14)
                            .contentShape(Rectangle())
                            .onTapGesture { currentPage = i }
                    }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 18)
        .background(Color.white.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
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