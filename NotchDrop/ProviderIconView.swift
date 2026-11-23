//
//  ProviderIconView.swift
//  NotchEvery
//
//  供应商动态图标：位图（PNG/WebP/JPG）同步取，SVG 异步补；取不到画哈希渐变首字母兜底。
//

import AppKit
import SwiftUI

struct ProviderIconView: View {
    let icon: String?
    let providerID: String
    let size: CGFloat

    @State private var resolved: NSImage?
    @State private var requestedIcons: Set<String> = []

    init(icon: String?, providerID: String, size: CGFloat = 14) {
        self.icon = icon
        self.providerID = providerID
        self.size = size
    }

    var body: some View {
        ZStack {
            if let resolved {
                Image(nsImage: resolved)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .onAppear(perform: resolve)
    }

    private var fallback: some View {
        let hue = MagpieIconResolver.shared.fallbackHue(for: providerID)
        return ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hue: hue, saturation: 0.55, brightness: 0.7),
                            Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1.0), saturation: 0.6, brightness: 0.5)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(MagpieIconResolver.shared.initial(for: providerID))
                .font(.system(size: size * 0.52, weight: .bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
        }
    }

    private func resolve() {
        // 同步位图命中直接用；否则异步补 SVG，且对同一 icon 只发一次异步请求
        if let synced = MagpieIconResolver.shared.image(for: icon) {
            resolved = synced
            return
        }
        let key = icon ?? ""
        guard !requestedIcons.contains(key) else { return }
        requestedIcons.insert(key)
        MagpieIconResolver.shared.loadImage(for: icon) { image in
            if let image {
                resolved = image
            }
        }
    }
}
