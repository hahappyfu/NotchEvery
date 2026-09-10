//
//  NotchSettingsView.swift
//  NotchDrop
//
//  Created by 曹丁杰 on 2024/7/29.
//

import LaunchAtLogin
import SwiftUI

struct NotchSettingsView: View {
    @StateObject var vm: NotchViewModel
    @StateObject var tvm: TrayDrop = .shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(LocalizedStringKey("Language"))
                    .font(.system(size: 13))
                Spacer()
                Picker("", selection: $vm.selectedLanguage) {
                    ForEach(Language.allCases) { language in
                        Text(language.localized).tag(language)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .controlSize(.small)
                // 语言名宽度各异，随内容自适应（不再硬编码 150/120）
                .fixedSize()
            }
            .padding(.vertical, 2)
            Divider()
            LaunchAtLogin.Toggle {
                Text(NSLocalizedString("Launch at Login", comment: ""))
                    .font(.system(size: 13))
            }
            .padding(.vertical, 2)
            Divider()
            Toggle("Haptic Feedback ", isOn: $vm.hapticFeedback)
                .font(.system(size: 13))
                .padding(.vertical, 2)
            Divider()
            // 自定义时 field+unit 换第二行右对齐：一行摆不下 240pt 三件套+label（360 Popover 可用仅 336）
            VStack(alignment: .trailing, spacing: 4) {
                HStack {
                    Text(LocalizedStringKey("File Storage Time"))
                        .font(.system(size: 13))
                    Spacer()
                    Picker(String(), selection: $tvm.selectedFileStorageTime) {
                        ForEach(TrayDrop.FileStorageTime.allCases) { time in
                            Text(time.localized).tag(time)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .controlSize(.small)
                    .frame(width: 90)
                }
                if tvm.selectedFileStorageTime == .custom {
                    HStack {
                        TextField("Days", value: $tvm.customStorageTime, formatter: NumberFormatter())
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .controlSize(.small)
                            .frame(width: 40)
                        Picker("Time Unit", selection: $tvm.customStorageTimeUnit) {
                            ForEach(TrayDrop.CustomStorageTimeUnit.allCases) { unit in
                                Text(unit.localized).tag(unit)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .controlSize(.small)
                        .frame(width: 110)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

#Preview {
    NotchSettingsView(vm: .init())
        .padding()
        .frame(width: 600, height: 150, alignment: .center)
        .background(.ultraThinMaterial)
}
