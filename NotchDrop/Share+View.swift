//
//  Share+View.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/8.
//  Last Modified by 冷月 on 2025/5/5.
//

import Pow
import SwiftUI
import UniformTypeIdentifiers

struct ShareView: View {
    enum ShareType {
        case airdrop
        case generic

        var imageName: String {
            switch self {
            case .airdrop: "airplayaudio"
            case .generic: "arrow.up.circle"
            }
        }

        var title: String {
            switch self {
            case .airdrop: NSLocalizedString("AirDrop", comment: "AirDrop sharing title")
            case .generic: NSLocalizedString("Share", comment: "Generic sharing title")
            }
        }

        var service: ([URL]) -> Share {
            switch self {
            case .airdrop:
                { urls in Share(files: urls, serviceName: .sendViaAirDrop) }
            case .generic:
                { urls in Share(files: urls) }
            }
        }
    }

    @StateObject var vm: NotchViewModel
    let type: ShareType

    @State var trigger: UUID = .init()
    @State var targeting = false

    var body: some View {
        dropArea
            .onDrop(of: [.fileURL], isTargeted: $targeting) { providers in
                guard providers.count <= 50 else {
                    NSAlert.popError(NSError(domain: "NotchDrop", code: 7, userInfo: [NSLocalizedDescriptionKey: String(format: NSLocalizedString("Too many files (max %d)", comment: ""), 50)]))
                    return false
                }
                trigger = .init()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    vm.notchClose()
                }
                DispatchQueue.global().async { beginDrop(providers) }
                return true
            }
    }

    var dropArea: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(targeting ? 0.9 : 0.75))
                    .frame(width: 34, height: 34)
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                Image(systemName: type.imageName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .contentShape(Circle())
            .scaleEffect(targeting ? 1.06 : 1.0)
            .animation(vm.animation, value: targeting)
            .modifier(SprayEffectModifier(trigger: trigger))
            Text(type.title)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            trigger = .init()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                vm.notchClose()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let picker = NSOpenPanel()
                picker.allowsMultipleSelection = true
                picker.canChooseDirectories = true
                picker.canChooseFiles = true
                picker.begin { response in
                    if response == .OK {
                        let drop = type.service(picker.urls)
                        drop.begin()
                    }
                }
            }
        }
    }

    func beginDrop(_ providers: [NSItemProvider]) {
        assert(!Thread.isMainThread)
        guard let urls = providers.interfaceConvert() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let drop = type.service(urls)
            drop.begin()
        }
    }
}

private struct SprayEffectModifier: ViewModifier {
    let trigger: UUID
    func body(content: Content) -> some View {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            content
        } else if #available(macOS 14.0, *) {
            content.changeEffect(
                .spray(origin: UnitPoint(x: 0.5, y: 0.5)) {
                    Image(systemName: "paperplane").foregroundStyle(.white)
                },
                value: trigger
            )
        } else {
            content
        }
    }
}
