//
//  SpinnerView.swift
//  NotchDrop
//
//  8 叶放射菊花（macOS 原生风）：叶条逐叶渐隐循环。
//

import SwiftUI

struct SpinnerView: View {
    var size: CGFloat = 13
    var color: Color = .white

    private let bladeCount = 8
    private let cycle: Double = 0.8

    var body: some View {
        ZStack {
            ForEach(0..<bladeCount, id: \.self) { i in
                Capsule()
                    .fill(color.opacity(0.9))
                    .frame(width: 1.5, height: size * 0.3)
                    .offset(y: -size * 0.35)
                    .rotationEffect(.degrees(Double(i) * 45))
                    .opacity(bladeOpacity)
                    .animation(
                        .linear(duration: cycle)
                            .delay(Double(i) * cycle / Double(bladeCount) * -1),
                        value: bladeOpacity
                    )
            }
        }
        .frame(width: size, height: size)
        .onAppear { bladeOpacity = 0.15 }
    }

    @State private var bladeOpacity: Double = 1
}
