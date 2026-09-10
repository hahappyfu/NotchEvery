# SwiftUI 内容宿主层 top 钉死（自管容器接管 contentView）

面板的 SwiftUI 内容自然高（最大分区 284pt）超过窗口高度（恒 200pt 贴顶条）时，`NSHostingView` 会把内容**垂直居中**于自身 bounds——设置区整个面板被抬升 42pt，选项卡跑到屏幕外，且此居中发生在宿主层，SwiftUI 内部任何 `alignment: .top` 都管不到（2026-09-08 晨间报告复测确诊：埋点实测概览头部 y=+20、设置 y=−22）。

我们决定让 `NotchWindowController` 用自管容器接管 `window.contentView`：hosting view 以约束钉死 top、宽度随容器、高度固定为最大分区高（`NotchViewModel.hostedViewHeight` = 高度表最大值）。效果是面板永远顶对齐、向下溢出窗口，窗口仍 200pt（点击区域不扩大）；分区高度动画发生在 SwiftUI 内部，宿主层不再感知。

## Consequences

- 新增分区只需更新高度表；`hostedViewHeight` 自动取最大值。
- 内容超出窗口下沿的部分可见但不可点（与历史行为一致）。
- `NotchWindow.setContentSize` 的 `pinnedContentSize` 钳制继续负责挡住 hosting 控制器的隐式窗口 resize。
- 调试提示：验证本决策用 `NotchView` 里的 HeaderProbe 埋点（`header-probe` 日志类别），AX 读数在此应用上不可靠。
