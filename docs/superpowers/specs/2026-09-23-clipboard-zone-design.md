# 剪贴板历史专区（Clipboard Zone）设计规格说明

## 1. 目标与用户体验

在 NotchEvery 刘海面板中集成专用的「剪贴板历史」专区，解决用户无系统级轻量剪贴板历史工具的痛点。

### 核心体验流程
1. **自动静默记录**：在后台低开销监听系统剪贴板（`changeCount` 机制），捕获文字和截图，自动去重，保留最新 50 条。
2. **刘海展开查看**：鼠标移动到刘海处展开面板，切到「剪贴板」分页，呈现最近历史卡片（文字显示摘要、图片显示微缩图）。
3. **连续点击注入**：
   - 用户在外部应用（微信、VSCode、浏览器等）聚焦输入框；
   - 鼠标移入刘海，点击剪贴板条目；
   - **触控板发出清脆物理触觉反馈**（`NSHapticFeedbackManager`）；
   - 卡片出现轻微高亮反馈；
   - 自动唤醒先前的输入应用，通过 `CGEvent` 注入 `Cmd + V` 粘贴；
   - **刘海面板保持展开状态**，允许用户立即连续点击第 2、第 3 条条目进行多次粘贴；
   - 鼠标离开刘海区域时，刘海按照既有逻辑平滑收拢回屏幕顶部。

---

## 2. 界面与视觉规范

遵循 NotchEvery 原生 Studio 视觉系统：

1. **尺寸边界与限高**：
   - 宽度：固定 `410pt`（与 TokenZone 宽度严格一致，分页横滑无晃动）。
   - 高度：最大高度限定在 `310pt` 左右，刚好默认展示 5 条完整卡片。
   - 滚动容器：超出 5 条时在限高内垂直滚动，上下附带 2% 透明渐变遮罩（Fade Mask），滑动不突兀。
2. **卡片视觉排版**：
   - 单卡片高度：约 `44pt`。
   - 背景与材质：`StudioMaterial.cardBackground`，悬停触发 `StudioMaterial.cardHoverBackground`。
   - 文本条目：左侧 `doc.on.clipboard` 图标，中间 1~2 行内容摘要，右侧相对时间（如“12秒前”）。
   - 图片条目：左侧 `34×34` 圆角缩略图，中间显示分辨率/文件大小，右侧相对时间。
3. **顶栏信息栏**：
   - 左侧：小绿点 + “剪贴板历史 · X条”。
   - 右侧：清空全部按钮（带防误触确认）。

---

## 3. 系统架构与关键组件

### 3.1 剪贴板监听器（`ClipboardMonitor`）
- **机制**：通过 `Timer` 每 0.6 秒轮询 `NSPasteboard.general.changeCount`，无复制时仅进行一次轻量整数比对，CPU 消耗趋于零。
- **内部标记防回环**：当用户在面板内点击条目写入剪贴板时，设置 `isInternalCopy = true`，避免自身写入被二次收录。
- **去重逻辑**：比较新内容的哈希值与当前栈顶项，内容完全一致时直接跳过。

### 3.2 数据模型与持久化（`ClipboardStore`）
- **数据结构**：
  ```swift
  struct ClipboardItem: Identifiable, Codable, Equatable {
      let id: UUID
      let type: ItemType // .text, .image
      let textContent: String?
      let imageFileName: String? // 独立图片文件，不直接内联 Base64
      let charCount: Int
      let imageSize: CGSize?
      let copiedAt: Date
  }
  ```
- **存储方案**：
  - 元数据及文本保存在应用支持目录 `Config/clipboard.json`。
  - 图片另存缩略图到 `Config/ClipboardImages/{id}.png`，不占常驻内存。
  - 上限维护：保留最新 50 条。第 51 条写入时，淘汰最老一条并移除其磁盘图片文件。

### 3.3 外部应用焦点追踪与按键注入（`ClipboardPaster`）
- **焦点应用追踪**：
  - 监听 `NSWorkspace.didActivateApplicationNotification`，持续更新 `lastTargetApp: NSRunningApplication?`（排除 NotchEvery 自身）。
- **按键模拟（Auto Paste）**：
  - 激活目标应用：`lastTargetApp?.activate(options: .activateIgnoringOtherApps)`。
  - 注入按键：调用 `CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true)`（按键 V）带 `mask = .maskCommand`，随后发送 keyUp。
  - 权限要求：macOS 辅助功能（Accessibility）权限。未授权时平滑降级为“仅写入剪贴板”并提示。
- **触觉反馈（Haptic Feedback）**：
  - 每次点击触发：`NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)`。

---

## 4. 分区管理与路由整合

1. **`ContentType` 枚举扩充**：
   ```swift
   enum ContentType: Int, Codable, Hashable, Equatable {
       case normal
       case clipboard // 新增剪贴板分页
       case token
       case gateway
   }
   ```
2. **`zoneOrder` 顺序**：
   - 默认循环：`[.normal, .clipboard, .token, .gateway]`。
   - 保留设置项开关（支持在设置中开启/关闭剪贴板分页）。
3. **刘海常驻防收起**：
   - 点击卡片执行粘贴时，不调用 `notchClose()`，让刘海保持在 `opened` 状态。
   - 仅当光标完全离开 `notchOpenedRect` 时触发 `scheduleHoverClose()`。

---

## 5. 错误处理与降级策略

1. **无辅助功能权限**：弹出轻量提示“已复制到剪贴板，请手动 Cmd+V；授予辅助功能权限可开启一键自动粘贴”。
2. **大图与异常数据**：剪贴板复制几百兆大图时，限制最大加载尺寸并压缩为最大 800px 长宽的本地缩略图，防止卡顿与 OOM。
3. **目标应用已退出**：若 `lastTargetApp` 已失效，仅将内容拷贝到系统剪贴板。

---

## 6. 测试与验证计划

1. **单元测试**：
   - `ClipboardStoreTests`：测试 50 条上限淘汰、连续内容去重、JSON 读写持久化。
   - `ZoneOrderTests`：验证添加 `.clipboard` 后分页索引与滑动手势逻辑正常。
2. **手动/集成验证**：
   - 复制富文本、普通代码、截图，观察刘海剪贴板专区是否毫秒级响应并展示。
   - 在 Safari、VSCode、微信输入框中测试连续点击粘贴，确认光标处连续打出内容且刘海不关闭。
   - 感受 Mac 触控板物理触觉回弹。
