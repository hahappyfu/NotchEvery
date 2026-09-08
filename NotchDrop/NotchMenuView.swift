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
        HStack(spacing: 6) {
            close
            settings
            clear
            ShareView(vm: vm, type: .airdrop)
        }
    }

    var close: some View {
        GlassButton(
            image: Image(systemName: "xmark"),
            title: "Exit",
            tint: .red
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
            tint: .red
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
            tint: .accentColor
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

    @State var hover: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(hover ? 0.95 : 0.85))
                    .frame(width: 34, height: 34)
                    .shadow(color: .black.opacity(hover ? 0.15 : 0.08), radius: 4, y: 1)
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 15, height: 15)
                    .foregroundStyle(tint)
            }
            .contentShape(Circle())
            .scaleEffect(hover ? 1.06 : 1)
            .animation(.spring(duration: 0.25), value: hover)
            .onHover { hover = $0 }
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NotchMenuView(vm: .init())
        .padding()
        .frame(width: 600, height: 150, alignment: .center)
        .background(.ultraThinMaterial)
}
