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
                Text("Language: ")
                    .font(.system(size: 13))
                Spacer()
                Picker("", selection: $vm.selectedLanguage) {
                    ForEach(Language.allCases) { language in
                        Text(language.localized).tag(language)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .controlSize(.small)
                .frame(width: vm.selectedLanguage == .simplifiedChinese || vm.selectedLanguage == .traditionalChinese ? 150 : 120)
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
            HStack {
                Text("File Storage Time: ")
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
                if tvm.selectedFileStorageTime == .custom {
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
