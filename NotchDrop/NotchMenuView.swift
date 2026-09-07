//
//  NotchMenuView.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/11.
//

import SwiftUI

struct NotchMenuView: View {
    @StateObject var vm: NotchViewModel
    @StateObject var tvm = TrayDrop.shared

    var body: some View {
        HStack(spacing: 28) {
            Spacer(minLength: 0)
            close
            settings
            clear
            ShareView(vm: vm, type: .airdrop)
            Spacer(minLength: 0)
        }
    }

    var close: some View {
        GlassButton(
            image: Image(systemName: "xmark"),
            title: "Exit",
            tint: .red,
            cornerRadius: vm.cornerRadius
        )
        .onTapGesture {
            vm.notchClose()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                NSApp.terminate(nil)
            }
        }
    }

    var clear: some View {
        GlassButton(
            image: Image(systemName: "trash"),
            title: "Clear",
            tint: .red,
            cornerRadius: vm.cornerRadius
        )
        .onTapGesture {
            tvm.removeAll()
            vm.notchClose()
        }
    }

    var settings: some View {
        GlassButton(
            image: Image(systemName: "gear"),
            title: LocalizedStringKey("Settings"),
            tint: .accentColor,
            cornerRadius: vm.cornerRadius
        )
        .onTapGesture {
            vm.showSettings()
        }
    }
}

private struct GlassButton: View {
    let image: Image
    let title: LocalizedStringKey
    let tint: Color
    let cornerRadius: CGFloat

    @State var hover: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.clear)
                .glassCard(cornerRadius: cornerRadius)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color.white.opacity(hover ? 0.25 : 0.12), lineWidth: hover ? 1 : 0.5)
                }
                .overlay { icon }
                .frame(width: 64, height: 64)
                .contentShape(Rectangle())
                .scaleEffect(hover ? 1.04 : 1)
                .animation(.spring(duration: 0.3), value: hover)
                .onHover { hover = $0 }
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(width: 76)
    }

    var icon: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.85))
                .frame(width: 32, height: 32)
                .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 15, height: 15)
                .foregroundStyle(tint)
        }
    }
}

#Preview {
    NotchMenuView(vm: .init())
        .padding()
        .frame(width: 600, height: 150, alignment: .center)
        .background(.ultraThinMaterial)
}
