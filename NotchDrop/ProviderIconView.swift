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

/// 图标解析顺序契约（可测 seam）：先 begin 作废旧 key，再查同步图。
/// 返回 `synced` 有值即同步命中；否则按 `shouldRequestAsync` 决定是否补异步请求。
/// 闭包收到 begin 之后的 gate 副本，因此能在查图时刻观测 gate 状态。
func planResolution(
    key: ProviderIconKey,
    syncImage: (IconRequestGate) -> NSImage?,
    gate: inout IconRequestGate
) -> (synced: NSImage?, shouldRequestAsync: Bool) {
    let started = gate.begin(key)
    if let image = syncImage(gate) { return (image, false) }
    return (nil, started)
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
        // seam 内先 begin 作废旧 key，再查同步图：任何新请求都会作废旧异步回调
        let plan = planResolution(key: key, syncImage: { _ in MagpieIconResolver.shared.image(for: icon) }, gate: &gate)

        if let synced = plan.synced {
            resolved = synced
            return
        }
        // 同 key 重复请求不重发
        guard plan.shouldRequestAsync else { return }
        MagpieIconResolver.shared.loadImage(for: icon) { [key] image in
            // 异步回调校验：仅当 key 仍是当前 key 时才写入 resolved（防止旧图残留）
            guard gate.isCurrent(key) else { return }
            if let image {
                resolved = image
            }
        }
    }
}
