# Handoff：NotchEvery 审计优化（2026-09-08 夜）

> 交接给下一个智能体/Claude 的会话总结。**事实部分已完成审计并达成四项共识**；本交接不包含实现代码，只有结论、坐标与动手路径。

## 一句话

对 NotchEvery 的 UI + 代码质量/性能审计已全部完成，四项决策用户已拍板（**A 彻底删除 settings 分区 / 保守修 UI 硬伤 / 性能全修含轻微项 / 确证死代码即删**），等待按下面的清单实现。所有改动未开始，工作区当前是夜班成果的未提交状态。

## 审计结论速览（详细见下）

- **「排版乱」指控：部分成立**。骨架规整，乱感主要来自设置死入口（点开是空白面板）+ Popover 拥挤超宽。
- **代码中上，确有浪费**：托盘持久化全量重写（含内联预览 base64）是卡顿头号嫌疑；多处死代码；常驻定时器不停。

## 用户已拍板的四项决策（共识，直接执行）

1. **Q1 设置入口 = 方案 A 彻底删除分区**：删掉 `ContentType.settings` 状态与三条死路径，右键菜单/Popover 齿轮直接打开设置 Popover，高度表剩两页（`hostedViewHeight` 284→224，需重验 ADR-0002 顶对齐）。
2. **Q2 UI = 保守修硬伤**：不动已锁定视觉（额度卡 2026-09-08 定稿、Nook 风骨架）。
3. **Q3 性能 = 全修含轻微项**。
4. **Q4 死代码 = 确证即删**。

## 实现清单（按序）

### A. P0 死交互修复（设置入口）
- 删除 `NotchWindowController.swift:76-77` **TEMP-DIAG 探针**（自注释"定案后删除"，开机自动跳空白设置区）。
- 删除 `ContentType.settings` case（[NotchViewModel.swift:116-136](NotchDrop/NotchViewModel.swift#L116)），连带 `tabTitleKey`/`tabIconName`。
- `zonePanelHeight` 删 `.settings: 284`（[NotchViewModel.swift:75-79](NotchDrop/NotchViewModel.swift#L75)）；`hostedViewHeight = 224`；窗口高度逻辑自动收窄。
- `NotchRootView.swift` `.settings: Color.clear` 分支删除。
- 右键菜单"Settings"（[NotchView.swift:123-132](NotchDrop/NotchView.swift#L123)）与 Popover 齿轮（[NotchMenuView.swift:49-58](NotchDrop/NotchMenuView.swift#L49)）改为直接 `showSettings = true`（Popover 绑定）。
- `showSettings()`（[NotchViewModel.swift:272-274](NotchDrop/NotchViewModel.swift#L272)）删除。
- 测试同步：`Tests/TabMetricsTests.swift`（含 `jumpToZone(.settings)`、`tabTitleKey` 假测试）重写。

### B. 死代码删除（确证即删，Q4）
| 候选 | 位置 |
|---|---|
| `NotchHeaderView` 整文件 | NotchHeaderView.swift |
| `mouseDraggingFile` 全局监听 + subject | EventMonitors.swift:39,44,65-69（协议成员同删，Mock 同步） |
| `tabIconName` / `headlineOpenedRect` | NotchViewModel.swift:129 / :24,149 |
| `darkGlassCard` | Glass.swift:57-71 |
| `ShareType.generic` | Share+View.swift:16,37-39 |
| `default.profraw`（仓库根，LLVM 产物）| 删 + `.gitignore` 加 `*.profraw` |

### C. 性能（全修，Q3）
1. **托盘持久化风暴（卡顿主因）**：
   - `DropItem.workspacePreviewImageData` 移出 Codable（[TrayDrop+DropItem.swift:15-26](NotchDrop/TrayDrop+DropItem.swift#L15)）；旧数据一次性迁移（读取时转存预览文件后置 nil）。
   - `TrayDrop.load` 批量：收集 succeeded 后一次 `items` 赋值（[TrayDrop.swift:102-112](NotchDrop/TrayDrop.swift#L102)），避免逐条 `updateOrInsert` 触发 N 次全量持久化。
   - `removeAll()` 批删：先删文件，再一次 `items = []`（[TrayDrop.swift:160-162](NotchDrop/TrayDrop.swift#L160)）。
   - 持久化管道：`Persist` 的 `removeDuplicates` 对多 MB Data 全量比较 → 改为值级去重或防抖（[PublishedPersist.swift:85-97](NotchDrop/PublishedPersist.swift#L85)）。
2. **启动清理移后台**：[main.swift:91](NotchDrop/main.swift#L91) `cleanExpiredFiles()` 包 `DispatchQueue.global().async`。
3. **QuotaStore 随面板启停**：[QuotaCardView.swift:38](NotchDrop/QuotaCardView.swift#L38) `onAppear start` 配对 panel 收起 `stop()`（或订阅 `vm.status`）。30s 定时器常驻归零。
4. **轻微项**：`DropItemView`/`TrayView` 的 `@StateObject` 单例订阅降级（每卡片订阅整个 TrayDrop，插一条全卡片重算）；`FileStorage.pathForKey` 目录创建缓存；`QuotaCardView.reduceMotion` 改 `@Environment` 响应式。

### D. UI 保守修复（Q2）
1. **Popover 布局**：`minWidth 300 → 360`（[NotchRootView.swift:35](NotchDrop/NotchRootView.swift#L35)）；自定义时间行（label+90picker+40field+110unit ≈ 370pt）保证不挤压，窄了换行；语言 picker 宽度 150/120 硬编码改自适应。
2. **本地化漏网**：`"Language: "`/`"File Storage Time: "`（[NotchSettingsView.swift:18,43](NotchDrop/NotchSettingsView.swift#L18)）走 LocalizedStringKey/NSLocalizedString，去尾随空格。
3. **空态文案**："Drag files here… & Press Option to delete"（[TrayDrop+View.swift:80-89](NotchDrop/TrayDrop+View.swift#L80)）拆两行。
4. **额度环中心数字溢出**："100.0%" 17pt bold ≈60pt > 内径 54（[QuotaCardView.swift:125-126](NotchDrop/QuotaCardView.swift#L125)）：缩字号或缩位（99.9%）。
5. **TokenZoneView**：耗时条 `min(1,秒/60)*44` 语义不明（[TokenZoneView.swift:70-73](NotchDrop/TokenZoneView.swift#L70)）——数据层存数值、展示层格式化，别反解析字符串；`⚡︎` 9pt 缓存标记增大/移除；[TokenZoneView.swift:124](NotchDrop/TokenZoneView.swift#L124) 代码格式破损修复。
6. **P2 顺手**：`NotchView.swift:238` 脏话注释；`glassNotchBackground` 四层同形状重复构造抽成局部变量。

## 交付/验证约束

- **本机无法做像素级验收**：屏幕录制权限未授。视觉改动依赖：CGWindowList 验几何（不需要权限）+ 用户真机验收 + 27/27 测试。
- **构建/测试**（无签名证书）：
  ```bash
  xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Debug \
    -derivedDataPath /tmp/nd_build build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
  xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
  ```
- 产物名 `NotchEvery.app`（target/scheme 叫 `NotchDrop`）；测试 `@testable import NotchEvery`。
- shell 是 zsh，含 `[` 的 grep 模式要加引号；启动 app 用 `open`，不要直 exec 二进制。
- **改动不 commit，等用户验收**（用户习惯）。
- 探针纪律：修复完成删除全部临时诊断代码，不写 /tmp 日志。

## 已定案文档（勿重复写，引用即可）

- `CONTEXT.md` 词汇表、`docs/adr/0001-0006`
- `.scratch/tab-pin/`（选项卡修复 spec+工单）
- `.scratch/codebase-health/`（架构候选 issues/02-05：NotchPanelState 状态机、mouseDown 纯函数化、PanelMetrics 几何归位、QuotaStore 注入 reader——**本次未动，用户仍未选**）
- `docs/research/hosting-window-and-ax.md`（AX 缓存与 sizingOptions 机制）
- `NIGHT-REPORT.md`（夜班成果：选项卡修复、27 测试接通、安全修复）

## suggested skills（给接手智能体）

- `/grilling`（+ `/grill-with-docs`）：本轮已共识四项；实现中有新决策（如 hostedViewHeight 284→224 顶对齐重验）仍需逐项访谈，不要自作主张
- `/domain-modeling`：删除 `.settings` 分区会改动 CONTEXT.md 词汇表（分区只剩两页、设置走 Popover 已录）与 ADR-0006 高度表——按该 skill 流程内联更新，别批量补
- `/implement-spec` 或 `/executing-plans`：按本交接清单实现
- `/verification-before-completion`：27/27 测试 + 构建绿 + CGWindowList 几何验真，像素验收留给用户
- `/zh-code-review`：实现 diff 的中文审查
