# Prompt：交给 Claude 执行 NotchEvery 审计优化（2026-09-08 夜）

> 用法：把这个文件的内容整个复制给 Claude（Codex/Claude Code），工作目录指向本仓库 `/Users/fupingguo/fuhaha_workspace/NotchEvery`。先读 `docs/HANDOFF-2026-09-08-audit-optimize.md` 拿全量坐标，再按下面的清单实现。实现是主要工作，不要重新审计。

---

你在 macOS SwiftUI 项目 **NotchEvery** 仓库里执行一轮已定案的审计优化。产品 NotchEvery（Xcode target/scheme 叫 `NotchDrop`，产物 `NotchEvery.app`），常驻刘海面板应用，源码在 `NotchDrop/`，测试在 `Tests/`（`@testable import NotchEvery`）。

**先读这些建立上下文**：`docs/HANDOFF-2026-09-08-audit-optimize.md`（交接文档，含全部问题坐标）、`CONTEXT.md`（词汇表）、`docs/adr/0001-0006`、`AGENTS.md`（风格与环境约束）、`NIGHT-REPORT.md`。

四项决策用户已拍板，直接执行，不要重新访谈：

1. **Q1 设置入口：彻底删除 `ContentType.settings` 分区**（设置走 Popover 是定案，`.settings` 是残留死状态，点开是空白面板）。
2. **Q2 UI：保守修硬伤**，不动已锁定视觉（额度卡样式、Nook 风玻璃骨架）。
3. **Q3 性能：全修含轻微项**。
4. **Q4 死代码：确证即删**。

## 实现清单（按序执行）

### 1. P0 设置入口修复
- 删 `NotchWindowController.swift` 的 TEMP-DIAG 探针（约 76-77 行，自注释"定案后删除"，开机自动跳空白设置区）。
- 删 `NotchViewModel.swift` 的 `ContentType.settings` case、`tabTitleKey`、`tabIconName`、`showSettings()`。
- `zonePanelHeight` 删 `.settings: 284`，`hostedViewHeight` 改为 224，**重验 ADR-0002 的宿主层顶对齐**（窗口高度逻辑会自动收窄）。
- `NotchRootView.swift` 删 `.settings: Color.clear` 分支；右键菜单 "Settings"（NotchView）与 Popover 齿轮（NotchMenuView）改为直接弹设置 Popover（`showSettings = true`）。
- 同步改 `Tests/TabMetricsTests.swift`（含 `jumpToZone(.settings)`、`tabTitleKey` 假测试）。

### 2. 死代码删除（确证即删）
- `NotchHeaderView.swift` 整文件；`EventMonitors.swift` 的 `mouseDraggingFile` 全局监听+subject+协议成员（Mock 同步）；`headlineOpenedRect`（NotchViewModel）；`Glass.swift` 的 `darkGlassCard`；`Share+View.swift` 的 `ShareType.generic`；仓库根 `default.profraw`（并给 `.gitignore` 加 `*.profraw`）。

### 3. 性能（卡顿主因是托盘持久化全量风暴）
- `DropItem.workspacePreviewImageData`（整张 PNG Data）移出 Codable，预览已外置文件（`Config/Previews`），旧数据读取时一次性迁移后置空。
- `TrayDrop.load`：succeeded 收集后**一次** `items` 赋值，不再逐条 `updateOrInsert`（每次触发全量持久化）。
- `removeAll()` 批删：先删文件再一次 `items = []`。
- `PublishedPersist.swift` 持久化管道：`removeDuplicates` 对多 MB Data 全量比较改值级去重/防抖。
- `main.swift` 顶层 `cleanExpiredFiles()` 移后台队列。
- `QuotaStore` 30s 定时器随面板收起 `stop()`（`QuotaCardView` 配对 onAppear/收起）。
- 轻微项：`DropItemView`/`TrayView` 的 `@StateObject` 单例订阅降级（每卡片订阅整个 TrayDrop，插一条全卡片重算）；`FileStorage.pathForKey` 每次建目录改缓存；`QuotaCardView.reduceMotion` 改 `@Environment` 响应式。

### 4. UI 保守修复
- Popover `minWidth 300→360`（自定义时间行 370pt 别挤压）；语言 Picker 宽度 150/120 硬编码改自适应。
- `NotchSettingsView` 的 `"Language: "`/`"File Storage Time: "` 硬编码英文走本地化，去尾随空格。
- `TrayDrop+View.swift` 空态文案 "… & …" 拆两行。
- `QuotaCardView` 环中心 "100.0%" 17pt（≈60pt）> 内径 54pt 会溢出：缩字号或缩位。
- `TokenZoneView`：耗时条 `min(1, 秒/60)*44` 语义不明，数据层存数值、展示层格式化（别反解析 "63.2s" 字符串）；`⚡︎` 9pt 缓存标记改大或移除；`header` 行代码格式破损修复。
- P2 顺手：`NotchView.swift` 脏话注释（"fuck you apple"）改写；`glassNotchBackground` 重复构造抽局部变量。

## 验证

- 构建与测试（本机无证书，必须禁签名）：
  ```bash
  xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Debug \
    -derivedDataPath /tmp/nd_build build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
  xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
  ```
- 27 个测试全绿；CGWindowList 验面板几何（不需要权限）；**像素级视觉验收本机做不到，留给用户**。
- 若有新决策点（如 hostedViewHeight 284→224 的顶对齐重验结果），停下来问，不要自作主张翻已定案 ADR。

## 硬性约束

- 启动 app 用 `open`，不要直 exec `.app/Contents/MacOS` 二进制（pid 单例与自删除监听会干扰）。
- shell 是 zsh：grep 含 `[` 的模式加引号。
- 不要 commit，所有改动留工作区等用户验收。
- 探针纪律：不新增临时诊断代码，修复完随 fix 一起删。
