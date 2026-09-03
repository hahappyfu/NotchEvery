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
        Group {
            if #available(macOS 26.0, *) {
                RoundedRectangle(cornerRadius: vm.cornerRadius)
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: vm.cornerRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: vm.cornerRadius)
                            .strokeBorder(Color.white.opacity(targeting ? 0.3 : 0.12), lineWidth: targeting ? 1.5 : 0.5)
                    }
                    .overlay {
                        content
                            .padding()
                    }
                    .scaleEffect(targeting ? 1.02 : 1.0)
                    .animation(vm.animation, value: targeting)
            } else {
                RoundedRectangle(cornerRadius: vm.cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: vm.cornerRadius)
                            .strokeBorder(Color.white.opacity(targeting ? 0.4 : 0.15), lineWidth: targeting ? 1.5 : 0.5)
                    }
                    .overlay {
                        content
                            .padding()
                    }
                    .scaleEffect(targeting ? 1.02 : 1.0)
                    .animation(vm.animation, value: targeting)
            }
        }
        .overlay(loadingIndicator)
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

    var text: String {
        [
            String(
                format: NSLocalizedString("Drag files here to keep them for %@", comment: ""),
                storageTime
            ),
            "&",
            NSLocalizedString("Press Option to delete", comment: ""),
        ].joined(separator: " ")
    }

    var content: some View {
        Group {
            if tvm.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                    Text(text)
                        .multilineTextAlignment(.center)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.primary)
                }
            } else {
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
