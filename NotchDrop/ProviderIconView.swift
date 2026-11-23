//
//  ProviderIconView.swift
//  NotchEvery
//
//  供应商动态图标：位图（PNG/WebP/JPG）同步取，SVG 异步补；取不到画哈希渐变首字母兜底。
//

import AppKit
import SwiftUI

/// 图标请求联合 key：icon 路径 + providerID。
struct ProviderIconKey: Hashable {
    let icon: String?
    let providerID: String
}

/// 图标请求闸门：新 key 清空历史并放行；同 key 重复请求拒绝；异步回调可校验是否已过期。
struct IconRequestGate {
    private(set) var requested: Set<ProviderIconKey> = []

    /// 新 key → 清空 requested 并返回 true；同 key 且已请求过 → false。
    mutating func begin(_ key: ProviderIconKey) -> Bool {
        if requested.contains(key) { return false }
        requested = [key]
        return true
    }

    /// 异步回调校验：key 是否仍是当前请求的 key。
    func isCurrent(_ key: ProviderIconKey) -> Bool {
        requested.contains(key)
    }
}

struct ProviderIconView: View {
    let icon: String?
    let providerID: String
    let size: CGFloat

    @State private var resolved: NSImage?
    @State private var gate = IconRequestGate()

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
        .onChange(of: icon) { _ in reResolve() }
        .onChange(of: providerID) { _ in reResolve() }
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

    /// icon/providerID 变化时先清掉旧 resolved 再重发请求。
    private func reResolve() {
        resolved = nil
        resolve()
    }

    private func resolve() {
        let key = ProviderIconKey(icon: icon, providerID: providerID)
        // 先 begin 作废旧 key 的异步回调，无论后续是同步命中还是异步补图
        let started = gate.begin(key)

        // 同步位图命中直接用；key 已在上面 begin，旧异步回调自然失效
        if let synced = MagpieIconResolver.shared.image(for: icon) {
            resolved = synced
            return
        }
        // 同 key 重复请求不重发
        guard started else { return }
        MagpieIconResolver.shared.loadImage(for: icon) { [key] image in
            // 异步回调校验：仅当 key 仍是当前 key 时才写入 resolved（防止旧图残留）
            guard gate.isCurrent(key) else { return }
            if let image {
                resolved = image
            }
        }
    }
}
