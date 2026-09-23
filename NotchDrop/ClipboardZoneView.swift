//
//  ClipboardZoneView.swift
//  NotchDrop
//
//  剪贴板专区（第 2 页）：历史条目列表（文本/图片），点击即粘贴回原前台应用。
//  交互约束：点击条目绝不收起刘海面板——保持展开，供用户连续点击粘贴。
//

import AppKit
import ApplicationServices
import SwiftUI

struct ClipboardZoneView: View {
    @StateObject private var store = ClipboardStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 固定宽度：与 Token 分区同宽
    static let zoneWidth: CGFloat = 410
    /// 列表可视高度上限：超过 5 条时滚动（5 * 44 + 4 * 5 = 240pt）
    static let maxListHeight: CGFloat = 240
    /// 单卡片高度
    static let rowHeight: CGFloat = 44
    /// 卡片间距
    static let rowSpacing: CGFloat = 5

    var body: some View {
        VStack(spacing: 6) {
            topActionBar

            if store.items.isEmpty {
                emptyView
            } else {
                listView
            }
        }
        .frame(width: Self.zoneWidth)
        .padding(.vertical, 2)
        .onAppear {
            checkAndRequestAXPermission()
        }
    }

    // MARK: - 顶栏（去冗余大标题，只保留低调操作条）

    private var topActionBar: some View {
        HStack {
            Text("最近记录")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.4))

            Spacer()

            if !store.items.isEmpty {
                Button {
                    confirmClear()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                        Text("清空")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(Color.white.opacity(0.45))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("清空全部剪贴板历史")
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    // MARK: - 辅助功能权限原生弹窗申请

    /// 检查并在缺失时直接呼出 macOS 系统的原生授权提示弹窗
    private func checkAndRequestAXPermission() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - 清空确认

    private func confirmClear() {
        let alert = NSAlert()
        alert.messageText = "清空剪贴板历史？"
        alert.informativeText = "将删除全部 \(store.items.count) 条记录，此操作不可撤销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        alert.window.title = "NotchEvery"
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            store.clearAll()
        }
    }

    // MARK: - 列表容器（内容驱动高度：1条自然收拢，多条按需伸展，超限平滑滚动）

    private var listHeight: CGFloat {
        let count = store.items.count
        if count == 0 { return 80 }
        let natural = CGFloat(count) * Self.rowHeight + CGFloat(max(0, count - 1)) * Self.rowSpacing
        return min(Self.maxListHeight, natural)
    }

    private var listView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: Self.rowSpacing) {
                ForEach(store.items) { item in
                    ClipboardRowView(item: item, onPasteAttempt: {
                        checkAndRequestAXPermission()
                    })
                }
            }
            .padding(.horizontal, 1)
        }
        .frame(height: listHeight)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.02),
                    .init(color: .black, location: 0.98),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: store.items.count)
    }

    private var emptyView: some View {
        HStack(spacing: 6) {
            Image(systemName: "clipboard")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.3))
            Text("暂无剪贴板历史，按 ⌘C 复制后自动收录")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 72)
    }

    // MARK: - 相对时间

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        return formatter
    }()

    static func relativeTime(from date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 10 { return "刚刚" }
        if seconds < 60 { return "\(Int(seconds))秒前" }
        if seconds < 3600 { return "\(Int(seconds / 60))分钟前" }
        if seconds < 86400 { return "\(Int(seconds / 3600))小时前" }
        if seconds < 7 * 86400 { return "\(Int(seconds / 86400))天前" }
        return monthDayFormatter.string(from: date)
    }
}

// MARK: - 单条卡片

private struct ClipboardRowView: View {
    let item: ClipboardItem
    var onPasteAttempt: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var flashOpacity: Double = 0

    var body: some View {
        HStack(spacing: 8) {
            leadingGlyph

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryText)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 8)

            Text(ClipboardZoneView.relativeTime(from: item.copiedAt))
                .font(.system(size: 9.5).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.4))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(width: ClipboardZoneView.zoneWidth, height: ClipboardZoneView.rowHeight)
        .contentShape(Rectangle())
        .background(hovering ? StudioMaterial.cardHoverBackground : StudioMaterial.cardBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(hovering ? StudioMaterial.strokeHover : StudioMaterial.strokeNormal, lineWidth: 0.5)
        )
        // 绿闪直接置于顶层透明遮罩，点击时呼吸可见
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(StudioColor.emerald.opacity(flashOpacity))
                .allowsHitTesting(false)
        )
        .onHover { hovering = $0 }
        .onTapGesture { paste() }
    }

    @ViewBuilder
    private var leadingGlyph: some View {
        switch item.type {
        case .text:
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.6))
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .image:
            if let url = ClipboardStore.shared.imageURL(for: item),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }

    private var primaryText: String {
        switch item.type {
        case .text:
            return item.textContent ?? ""
        case .image:
            guard let width = item.imageWidth, let height = item.imageHeight else { return "截图" }
            return "截图 (\(Int(width)) × \(Int(height)))"
        }
    }

    private func paste() {
        onPasteAttempt()
        ClipboardPaster.shared.paste(item: item)

        guard !reduceMotion else { return }
        flashOpacity = 0.28
        withAnimation(.easeOut(duration: 0.25)) {
            flashOpacity = 0
        }
    }
}
