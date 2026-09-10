//
//  Glass.swift
//  NotchDrop
//
//  控制中心风格玻璃材质封装。
//  macOS 26+ 用原生 Liquid Glass (glassEffect)，旧系统回落到 Material。
//

import SwiftUI

// MARK: - 对外接口

extension View {
    /// 玻璃卡片效果：macOS 26+ 用 Liquid Glass，其余用 Material
    func glassCard(cornerRadius: CGFloat) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, tint: nil))
    }

    /// 带 tint 的玻璃卡片（用于 hover/强调）
    func glassCard(cornerRadius: CGFloat, tint: Color?) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, tint: tint))
    }
}

// MARK: - 内部实现

private struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            let base = content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            if let tint {
                base.tint(tint)
            } else {
                base
            }
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
    }
}
