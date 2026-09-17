//
//  DesignSystem.swift
//  NotchEvery
//
//  Apple Native Studio 工业级设计系统：材质、调色盘、微光边框与弹簧动效。
//

import SwiftUI

public enum StudioColor {
    public static let emerald = Color(red: 16/255, green: 185/255, blue: 129/255) // #10B981
    public static let amber   = Color(red: 245/255, green: 158/255, blue: 11/255)  // #F59E0B
    public static let rose    = Color(red: 244/255, green: 63/255, blue: 94/255)   // #F43F5E
    public static let indigo  = Color(red: 99/255, green: 102/255, blue: 241/255)  // #6366F1
    public static let cyan    = Color(red: 6/255, green: 182/255, blue: 212/255)   // #06B6D4
}

public enum StudioMaterial {
    public static let cardBackground = Color.white.opacity(0.05)
    public static let cardHoverBackground = Color.white.opacity(0.09)
    public static let cardSelectedBackground = Color.white.opacity(0.12)
    public static let strokeNormal = Color.white.opacity(0.10)
    public static let strokeHover = Color.white.opacity(0.24)
    public static let strokeActive = Color.white.opacity(0.35)
}

public enum StudioAnimation {
    public static let springResponse: Double = 0.32
    public static let springDamping: Double = 0.86
    public static var interactiveSpring: Animation {
        .spring(response: springResponse, dampingFraction: springDamping)
    }
}

public struct StudioCardModifier: ViewModifier {
    var radius: CGFloat
    var isHovered: Bool
    var isSelected: Bool

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(isSelected ? StudioMaterial.cardSelectedBackground : (isHovered ? StudioMaterial.cardHoverBackground : StudioMaterial.cardBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        isSelected ? StudioMaterial.strokeActive : (isHovered ? StudioMaterial.strokeHover : StudioMaterial.strokeNormal),
                        lineWidth: 0.5
                    )
            )
    }
}

public extension View {
    func studioCard(radius: CGFloat = 10, isHovered: Bool = false, isSelected: Bool = false) -> some View {
        modifier(StudioCardModifier(radius: radius, isHovered: isHovered, isSelected: isSelected))
    }

    func studioPillBadge(color: Color) -> some View {
        self
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.32), lineWidth: 0.5))
            .foregroundStyle(color)
    }
}
