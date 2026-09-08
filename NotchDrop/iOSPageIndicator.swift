//
//  iOSPageIndicator.swift
//  NotchDrop
//
import SwiftUI

/// iOS 主屏风分页指示器：胶囊外壳 + 圆点；激活页为 12pt 白胶囊，其余 5pt 点（0.3）。
struct iOSPageIndicator: View {
    let count: Int
    let current: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(i == current ? 1 : 0.3))
                    .frame(width: i == current ? 12 : 5, height: 5)
                    .onTapGesture { onSelect(i) }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.35)))
    }
}

#Preview {
    VStack(spacing: 8) {
        iOSPageIndicator(count: 2, current: 0) { _ in }
        iOSPageIndicator(count: 2, current: 1) { _ in }
    }
    .padding()
    .background(Color(nsColor: .windowBackgroundColor))
}
