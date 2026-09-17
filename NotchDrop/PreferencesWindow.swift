//
//  PreferencesWindow.swift
//  NotchEvery
//
//  偏好设置窗口：通用配置。
//  适配 macOS 原生系统偏好设置设计规范（圆角分组浮岛卡片 + 安全边距）。
//

import SwiftUI
import LaunchAtLogin
import AppKit

enum PreferencesTab: String, CaseIterable, Identifiable {
    case general = "通用"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        }
    }
}

struct PreferencesWindow: View {
    @State private var selectedTab: PreferencesTab = .general

    var body: some View {
        NavigationSplitView {
            List(PreferencesTab.allCases, selection: $selectedTab) { tab in
                NavigationLink(value: tab) {
                    Label(tab.rawValue, systemImage: tab.icon)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.vertical, 4)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            detailContent
                .frame(minWidth: 480, minHeight: 450)
                .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .general:
            GeneralSettingsTab()
        }
    }
}

// MARK: - Native macOS Settings Section Group Component

struct SettingsSectionGroup<Content: View, Trailing: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    init(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                trailing()
            }
            .padding(.horizontal, 20)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
        }
    }
}

extension SettingsSectionGroup where Trailing == EmptyView {
    init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title, subtitle: subtitle, trailing: { EmptyView() }, content: content)
    }
}

// MARK: - Tab 1: 通用

struct GeneralSettingsTab: View {
    @State private var hapticFeedback: Bool = {
        if let data = FileStorage().data(forKey: "hapticFeedback"),
           let val = try? JSONDecoder().decode(Bool.self, from: data) {
            return val
        }
        return true
    }()
    @StateObject private var tvm = TrayDrop.shared
    @State private var selectedLanguage: Language = {
        if let data = FileStorage().data(forKey: "selectedLanguage"),
           let val = try? JSONDecoder().decode(Language.self, from: data) {
            return val
        }
        return .system
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SettingsSectionGroup("基本选项") {
                    VStack(spacing: 0) {
                        LaunchAtLogin.Toggle {
                            Text("开机自启动")
                                .font(.system(size: 13))
                        }
                        .toggleStyle(.switch)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        Divider().padding(.leading, 16)

                        Toggle(isOn: $hapticFeedback) {
                            Text("触觉反馈")
                                .font(.system(size: 13))
                        }
                        .toggleStyle(.switch)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .onChange(of: hapticFeedback) { newValue in
                            if let vm = (NSApp.delegate as? AppDelegate)?.mainWindowController?.vm {
                                vm.hapticFeedback = newValue
                            }
                        }

                        Divider().padding(.leading, 16)

                        HStack {
                            Text("语言")
                                .font(.system(size: 13))
                            Spacer()
                            Picker("", selection: $selectedLanguage) {
                                ForEach(Language.allCases) { lang in
                                    Text(lang.localized).tag(lang)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                            .onChange(of: selectedLanguage) { newValue in
                                if let vm = (NSApp.delegate as? AppDelegate)?.mainWindowController?.vm {
                                    vm.selectedLanguage = newValue
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }

                SettingsSectionGroup("托盘存储") {
                    VStack(spacing: 0) {
                        HStack {
                            Text("文件保留时长")
                                .font(.system(size: 13))
                            Spacer()
                            Picker("", selection: $tvm.selectedFileStorageTime) {
                                ForEach(TrayDrop.FileStorageTime.allCases) { time in
                                    Text(time.localized).tag(time)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        if tvm.selectedFileStorageTime == .custom {
                            Divider().padding(.leading, 16)
                            HStack {
                                Text("自定义时长")
                                    .font(.system(size: 13))
                                Spacer()
                                HStack(spacing: 6) {
                                    TextField("天数", value: $tvm.customStorageTime, formatter: NumberFormatter())
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .controlSize(.small)
                                        .frame(width: 50)
                                    Picker("", selection: $tvm.customStorageTimeUnit) {
                                        ForEach(TrayDrop.CustomStorageTimeUnit.allCases) { unit in
                                            Text(unit.localized).tag(unit)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 80)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                    }
                }

                SettingsSectionGroup("关于与状态") {
                    VStack(spacing: 0) {
                        HStack {
                            Text("当前版本")
                                .font(.system(size: 13))
                            Spacer()
                            Text(appVersion)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        Divider().padding(.leading, 16)

                        HStack {
                            Text("反代数据源")
                                .font(.system(size: 13))
                            Spacer()
                            Text("Antigravity Tools")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 30)
            .onAppear {
                if let vm = (NSApp.delegate as? AppDelegate)?.mainWindowController?.vm {
                    hapticFeedback = vm.hapticFeedback
                    selectedLanguage = vm.selectedLanguage
                }
            }
        }
    }
}
