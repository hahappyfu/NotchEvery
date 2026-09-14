//
//  TrayDrop+View.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/8.
//

import SwiftUI

struct TrayView: View {
    @StateObject var vm: NotchViewModel
    @StateObject var tvm = TrayDrop.shared

    @State private var targeting = false
    @State private var clearHovered = false
    @State private var packHovered = false

    var storageTime: String {
        switch tvm.selectedFileStorageTime {
        case .oneHour:
            return NSLocalizedString("an hour", comment: "")
        case .oneDay:
            return NSLocalizedString("a day", comment: "")
        case .twoDays:
            return NSLocalizedString("two days", comment: "")
        case .threeDays:
            return NSLocalizedString("three days", comment: "")
        case .oneWeek:
            return NSLocalizedString("a week", comment: "")
        case .never:
            return NSLocalizedString("forever", comment: "")
        case .custom:
            let localizedTimeUnit = NSLocalizedString(tvm.customStorageTimeUnit.localized.lowercased(), comment: "")
            return "\(tvm.customStorageTime) \(localizedTimeUnit)"
        }
    }

    var body: some View {
        panel
            .onDrop(of: [.fileURL], isTargeted: $targeting) { providers in
                guard providers.count <= 50 else {
                    NSAlert.popError(NSError(domain: "NotchDrop", code: 7, userInfo: [NSLocalizedDescriptionKey: String(format: NSLocalizedString("Too many files (max %d)", comment: ""), 50)]))
                    return false
                }
                DispatchQueue.global().async { tvm.load(providers) }
                return true
            }
    }

    var panel: some View {
        RoundedRectangle(cornerRadius: vm.cornerRadius)
            .fill(.clear)
            .overlay {
                RoundedRectangle(cornerRadius: vm.cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: targeting ? [
                                StudioColor.cyan.opacity(0.85),
                                StudioMaterial.strokeActive
                            ] : [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: targeting ? 1.5 : 0.5
                    )
                    .shadow(color: targeting ? StudioColor.cyan.opacity(0.4) : .clear, radius: targeting ? 8 : 0)
            }
            .overlay {
                content
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .overlay(loadingIndicator)
            .scaleEffect(targeting ? 1.02 : 1.0)
            .animation(StudioAnimation.interactiveSpring, value: targeting)
            .animation(vm.animation, value: tvm.items)
            .animation(vm.animation, value: tvm.isLoading)
    }

    @ViewBuilder
    private var loadingIndicator: some View {
        if tvm.isLoading > 0 {
            RoundedRectangle(cornerRadius: vm.cornerRadius)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                .opacity(0.6)
        }
    }

    var content: some View {
        Group {
            if tvm.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(targeting ? StudioColor.cyan : .secondary.opacity(0.7))
                        .shadow(color: targeting ? StudioColor.cyan.opacity(0.5) : .clear, radius: targeting ? 6 : 0)
                    VStack(spacing: 3) {
                        Text(String(format: NSLocalizedString("Drag files here to keep them for %@", comment: ""), storageTime))
                            .font(.system(.subheadline, design: .rounded))
                            .multilineTextAlignment(.center)
                        Text(LocalizedStringKey("Press Option to delete"))
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .animation(StudioAnimation.interactiveSpring, value: targeting)
            } else {
                VStack(spacing: 8) {
                    ScrollView(.horizontal) {
                        HStack(spacing: vm.spacing) {
                            ForEach(tvm.items) { item in
                                DropItemView(item: item, vm: vm, tvm: tvm)
                            }
                        }
                        .padding(vm.spacing)
                    }
                    .padding(-vm.spacing)
                    .scrollIndicators(.never)

                    HStack(spacing: 8) {
                        Spacer()

                        Button(action: {
                            let urls = tvm.items.map(\.storageURL)
                            guard !urls.isEmpty else { return }
                            let share = Share(files: urls)
                            share.begin()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "archivebox")
                                    .font(.system(size: 10, weight: .medium))
                                Text(LocalizedStringKey("Pack"))
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .studioCard(radius: 6, isHovered: packHovered)
                        }
                        .buttonStyle(.plain)
                        .onHover { packHovered = $0 }

                        Button(action: {
                            tvm.removeAll()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 10, weight: .medium))
                                Text(LocalizedStringKey("Clear"))
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                            }
                            .foregroundStyle(StudioColor.rose.opacity(0.85))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .studioCard(radius: 6, isHovered: clearHovered)
                        }
                        .buttonStyle(.plain)
                        .onHover { clearHovered = $0 }
                    }
                }
            }
        }
    }
}

#Preview {
    NotchContentView(vm: .init())
        .padding()
        .frame(width: 550, height: 150, alignment: .center)
        .background(.ultraThinMaterial)
}
