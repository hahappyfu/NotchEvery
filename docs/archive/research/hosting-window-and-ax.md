# 调研：NSHostingController.sizingOptions 与 AX 窗口枚举失效

日期：2026-09-08 ｜ 环境：Xcode 26.6 / macOS 26 SDK（本机头文件为一手来源）。仓库现状：`sizingOptions = []` 已回退，改为 `NotchWindow.pinnedContentSize` 钉死 `setContentSize`（`NotchDrop/NotchWindow.swift:15-17`）；`AppDelegate.swift:31` 为 `setActivationPolicy(.accessory)`。

## 谜题 1：sizingOptions

**结论**
1. **五个 case（macOS 13.0 引入，Xcode 26.6 SDK 无增删）**：`minSize`＝创建并维护内容最小尺寸约束；`intrinsicContentSize`＝维护理想尺寸约束并反映到 hosting view 的 `intrinsicContentSize`；`maxSize`＝最大尺寸约束；`preferredContentSize`＝控制器侧把理想尺寸反映到 `preferredContentSize`（直接用 `NSHostingView` 时无效）；`standardBounds`＝min+ideal+max 三者。来源：[官方各 case 文档](https://developer.apple.com/documentation/swiftui/nshostingsizingoptions)（官方文档，高可信）。
2. **默认值是 `.standardBounds`**，即含 min/intrinsic/max 三个约束、**不含** `preferredContentSize`。官方原文："sizingOptions defaults to `.standardBounds` (which includes minSize, intrinsicContentSize, and maxSize)"（[sizingOptions](https://developer.apple.com/documentation/swiftui/nshostingcontroller/sizingoptions)，官方文档）。头文件转述一致（[Michael Tsai 2023-08-03](https://mjtsai.com/blog/2023/08/03/how-nshostingview-determines-its-sizing/)，社区转述）。
3. **"200→280 不回落"与 `[]` 变 0×0 的机制**：官方规定 `contentViewController` 赋值会让窗口"按视图控制器视图当前尺寸调整"，并随内容改写窗口 `contentMinSize/contentMaxSize`（[NSWindow.contentViewController](https://developer.apple.com/documentation/appkit/nswindow/contentviewcontroller) + sizingOptions 页，官方）。默认下 minSize 约束阻止回落；而 `[]`＝"create no constraints at all"（官方原文），无约束无 intrinsic 时 fittingSize 为 0×0，后续布局把 borderless 窗口压成 0×0、不可见（机制部分为推断；社区同类报告：[SO 79170528，2024，macOS 15](https://stackoverflow.com/questions/79170528/nswindow-with-swiftui-content-has-zero-frame-on-macos-15)）。
4. **推荐做法**：官方明确背书固定尺寸场景用小 option 集——"view always being displayed in a fixed frame" 时减少选项可省布局测量，且 frame 不匹配时"内容居中"。即 `[]` 本身合法，但**窗口尺寸必须完全自管**：赋值 `contentViewController` 之后最后一步 `setContentSize/setFrame`，并把 `contentMinSize=contentMaxSize` 在其后钉死（hosting 会改写它们）；或像本仓库一样在 NSWindow 子类拦截 `setContentSize`。当前 `pinnedContentSize` 方案即官方推荐模式（官方文档＋代码验证）。

## 谜题 2：AX 窗口枚举失效

**结论**
1. **`NSApplication.accessibilityActivationPolicy` 不存在**：Xcode 26.6 SDK AppKit 头文件、[Apple NSApplication 文档](https://developer.apple.com/documentation/appkit/nsapplication)、全网均无此符号；只有 `setActivationPolicy` 与 `accessibilityActivationPoint`（一手头文件，高可信）。`.accessory` 官方语义是"不进 Dock、无菜单栏，但可被激活、可拥有窗口"，**没有任何文档说 accessory 应用对 AX 隐藏窗口**；只有 `.prohibited`（"may not create windows"）才会连窗口都不可有（[ActivationPolicy.accessory](https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum/accessory)，官方）。"accessory 导致 AX 无窗口"缺乏依据。
2. **System Events 对快速重启同名进程的缓存问题**：无 Apple 官方承认；社区大量报告重启后旧 process 引用失效、死进程残留、新进程窗口需 delay/重试或激活后才出现，标准规避是按 `first application process whose unix id is <pid>` 重新解析（[MacScripter](https://www.macscripter.net/t/quit-idle-applications/34132)、[Keyboard Maestro 论坛](https://forum.keyboardmaestro.com/t/loading-apps-upon-start-of-macos-with-individual-desktops/8913)，社区报告，中可信）。"15 次 kill+open 后 AX 服务器残留旧 pid 状态"无直接公开报告，**不确定**。
3. **不注销的重注册手段**：`sudo killall universalaccessd`（launchd 自动拉起，重载 AX/TCC 状态；[Apple Discussions](https://discussions.apple.com/thread/8134578)、[Eclectic Light 2024-03-19](https://eclecticlight.co/2024/03/19/is-there-a-problem-in-sonomas-universalaccessd/)，社区验证）；重启 System Events；观察端按新 pid 重建 `AXUIElementCreateApplication` 与 AXObserver；TCC 辅助功能权限关-开。`AXManualAccessibility` 仅对懒加载 AX 树的应用（Electron 等）有效，对原生 AppKit 无用（[Electron 文档](https://electronjs.org/docs/latest/tutorial/accessibility)、[electron#37465](https://github.com/electron/electron/issues/37465)，社区）。

**未解**：两谜题都缺 Apple 官方 bug 记录；谜题 2 的触发条件（快速重启次数阈值、涉及哪个守护进程）建议下次复现时记录 `launchctl procinfo` 与 universalaccessd 日志。
