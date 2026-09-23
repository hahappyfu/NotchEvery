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
    /// 辅助功能授权：粘贴注入依赖它；未授权时顶栏展示提示胶囊
    @State private var axTrusted = AXIsProcessTrusted()

    /// 固定宽度：与 Token 分区同宽，卡片排版对齐
    static let zoneWidth: CGFloat = 410
    /// 列表可视高度上限：视野内完整容纳约 5 条 44pt 卡片
    static let maxListHeight: CGFloat = 260
    /// 外壳高度上限：防内容撑爆面板（超限由内部 ScrollView 消化）
    static let maxZoneHeight: CGFloat = 310
    /// 单卡片高度
    static let rowHeight: CGFloat = 44
    /// 卡片间距
    static let rowSpacing: CGFloat = 5

    var body: some View {
        VStack(spacing: 0) {
            topBar

            if store.items.isEmpty {
                Text("暂无剪贴板记录")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                list
            }
        }
        .frame(width: Self.zoneWidth)
        .frame(maxHeight: Self.maxZoneHeight)
        .padding(.vertical, 4)
        .onAppear { axTrusted = AXIsProcessTrusted() }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(StudioColor.emerald)
                .frame(width: 6, height: 6)
            Text("剪贴板历史")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
            Text("\(store.items.count)")
                .studioPillBadge(color: StudioColor.emerald)

            Spacer()

            if !axTrusted {
                permissionPill
            }
            clearButton
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(StudioMaterial.strokeNormal)
                .frame(height: 0.5)
        }
        .padding(.bottom, 4)
    }

    /// 无辅助功能权限时的轻量提示：粘贴注入会静默失效，此处只说事实
    private var permissionPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 8))
            Text("需辅助功能权限")
                .font(.system(size: 9.5, weight: .medium))
        }
        .foregroundStyle(StudioColor.amber)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(StudioColor.amber.opacity(0.16), in: Capsule())
        .overlay(Capsule().strokeBorder(StudioColor.amber.opacity(0.32), lineWidth: 0.5))
        .help("未授予辅助功能权限时，点击条目仅写回剪贴板，无法向原应用自动注入 ⌘V")
    }

    private var clearButton: some View {
        Button {
            confirmClear()
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(store.items.isEmpty ? Color.white.opacity(0.25) : Color.white.opacity(0.7))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.items.isEmpty)
        .help("清空剪贴板历史")
    }

    /// 防误触确认（规格 2.3）：清空前经系统警告框二次确认；沿用仓库既有 NSAlert 惯例
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

    // MARK: - 列表

    /// 列表定高（非弹性）：min(内容自然高, 上限)。
    /// 用显式高度替代 ScrollView 的弹性高度，测量上报的才是真实内容尺寸（见 ZoneSizeGuard 语义）。
    private var listHeight: CGFloat {
        let count = CGFloat(store.items.count)
        let natural = count * Self.rowHeight + max(0, count - 1) * Self.rowSpacing
        return min(Self.maxListHeight, natural)
    }

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: Self.rowSpacing) {
                ForEach(store.items) { item in
                    ClipboardRowView(item: item)
                        .transition(reduceMotion ? .identity : .opacity)
                }
            }
        }
        .frame(height: listHeight)
        // 上下渐隐遮罩：与 TokenZoneView 同参（2% 处开始/收尾）
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: store.items)
    }

    // MARK: - 相对时间（规格 2.2：如「刚刚」「12秒前」「2分钟前」）

    static func relativeTime(from date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 10 { return "刚刚" }
        if seconds < 60 { return "\(Int(seconds))秒前" }
        if seconds < 3600 { return "\(Int(seconds / 60))分钟前" }
        if seconds < 86400 { return "\(Int(seconds / 3600))小时前" }
        if seconds < 7 * 86400 { return "\(Int(seconds / 86400))天前" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - 单条卡片

private struct ClipboardRowView: View {
    let item: ClipboardItem
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    /// 点击后的绿闪反馈透明度
    @State private var flashOpacity: Double = 0

    var body: some View {
        HStack(spacing: 8) {
            leadingGlyph

            Text(primaryText)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 8)

            Text(ClipboardZoneView.relativeTime(from: item.copiedAt))
                .font(.system(size: 9.5).monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(width: ClipboardZoneView.zoneWidth, height: ClipboardZoneView.rowHeight)
        .contentShape(Rectangle())
        .studioCard(radius: 9, isHovered: hovering)
        // 绿闪呼吸：叠加在卡片底层，点击后 0.2s 渐隐
        .background(StudioColor.emerald.opacity(flashOpacity), in: RoundedRectangle(cornerRadius: 9))
        .onHover { hovering = $0 }
        .onTapGesture { paste() }
    }

    @ViewBuilder
    private var leadingGlyph: some View {
        switch item.type {
        case .text:
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
                .frame(width: 22, height: 22)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
        case .image:
            // 34×34 缩略图：本地小文件按需读取（LazyVStack 只渲染可视行）
            if let url = ClipboardStore.shared.imageURL(for: item),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.55))
                    )
            }
        }
    }

    /// 文本：原始内容（两行截断）；图片：尺寸规格
    private var primaryText: String {
        switch item.type {
        case .text:
            return item.textContent ?? ""
        case .image:
            guard let width = item.imageWidth, let height = item.imageHeight else { return "图片" }
            return "图片 · \(Int(width)) × \(Int(height))"
        }
    }

    private func paste() {
        // 触觉反馈 + 写回剪贴板 + 注入 ⌘V 均在 ClipboardPaster 内；此处绝不调用任何收起面板逻辑
        ClipboardPaster.shared.paste(item: item)

        guard !reduceMotion else { return }
        flashOpacity = 0.22
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) { flashOpacity = 0 }
        }
    }
}

#Preview {
    ClipboardZoneView()
        .padding()
        .frame(width: 600)
        .background(.ultraThinMaterial)
}
