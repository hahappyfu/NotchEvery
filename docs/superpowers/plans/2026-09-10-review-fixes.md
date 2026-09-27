# Code Review 修复实现计划（cached 死字段 + footerTime 提 static）

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 落实中文 code review 的 2 项结论：删 `TokenRequest.cached` 死字段（含 mock 同步），`footerTime` 的 DateFormatter 提为 static 缓存。

**架构：** 2 个任务都在 `NotchDrop/TokenZoneView.swift` 内、互不依赖（删字段不碰 footer，提 static 不碰结构），顺序可任意；每任务独立构建验证 + 独立 commit。

**技术栈：** SwiftUI（macOS 13+），构建验证：`xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Debug -derivedDataPath /tmp/nDD build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO`

**规格：** 本次会话中文 code review 结论（2026-09-10）：[必须修复] cached 死字段（结构 `TokenZoneView.swift:21` + mock 5 处传参无人引用，bolt 图标已删）；[建议修改] footerTime 每次求值 new DateFormatter（`TokenZoneView.swift:203-207`）。测试口径说明：纯视图死代码删除/常量提升，无行为变更，项目内无对应单测 harness（Tests/ 覆盖 ViewModel/Quota），以构建通过 + 用户截图验收为通过标准，不写无断言的形式测试。

## 全局约束

- 部署目标 macOS 13：不用 macOS 14+ API；多段异色文本用 HStack 包独立 Text（本次不碰文本，仅重申）。
- 只动 `NotchDrop/TokenZoneView.swift`，不碰数据流、切页、设置入口、埋点。
- 构建产物进 `-derivedDataPath /tmp/nDD`；构建完杀老进程重启 `/tmp/nDD` 产物；视觉验收靠用户截图。

---

## 文件结构

- 修改：`NotchDrop/TokenZoneView.swift`——任务 1 删 struct 属性 + 5 处 mock 参数；任务 2 加 static formatter + 改 footerTime 取用。单文件承载两处无关改动，按任务拆 commit。

---

### 任务 1：删除 cached 死字段

**文件：**
- 修改：`NotchDrop/TokenZoneView.swift:11-30`
- 测试：构建命令（见步骤 2）+ 用户截图（Token 页表格正常）

- [ ] **步骤 1：删除 struct 属性与 5 处 mock 参数**

删除第 21 行：

```swift
    let cached: Bool
```

5 处 mock 构造逐行删除尾部参数（以第 24 行为例，其余 4 行同理只删 `, cached: true/false`）：

```swift
        .init(time: "14:46", model: "opus-5", inputTokens: 524, outputTokens: 283, durationSeconds: 26.8, cost: "未定价", status: 200),
```

5 行改后形态（逐字）：

```swift
        .init(time: "14:46", model: "opus-5", inputTokens: 524, outputTokens: 283, durationSeconds: 26.8, cost: "未定价", status: 200),
        .init(time: "14:45", model: "opus-5", inputTokens: 538, outputTokens: 185, durationSeconds: 19.3, cost: "未定价", status: 200),
        .init(time: "14:44", model: "opus-5", inputTokens: 2977, outputTokens: 638, durationSeconds: 40.1, cost: "未定价", status: 200),
        .init(time: "14:39", model: "opus-5", inputTokens: 0, outputTokens: 0, durationSeconds: 6.1, cost: "$0.00", status: 429),
        .init(time: "14:37", model: "opus-5", inputTokens: 1126, outputTokens: 372, durationSeconds: 63.2, cost: "未定价", status: 200),
```

- [ ] **步骤 2：构建验证通过**

运行：`xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Debug -derivedDataPath /tmp/nDD build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | head -10`
预期：`BUILD SUCCEEDED`，无 `error:` 行（若有 `cached` 相关 error 说明漏删，用报错行号定位补删）。

- [ ] **步骤 3：Commit**

```bash
git add NotchDrop/TokenZoneView.swift
git commit -m "refactor: 删除 TokenRequest.cached 死字段（含 mock 同步）"
```

### 任务 2：footerTime 提 static formatter

**文件：**
- 修改：`NotchDrop/TokenZoneView.swift:203-207`
- 测试：构建命令（同任务 1 步骤 2）+ 用户截图（底部栏"更新于 HH:mm"正常）

- [ ] **步骤 1：static 缓存 formatter 并改取用**

改前（逐字）：

```swift
    private static var footerTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }
```

改后（逐字）：

```swift
    private static let footerFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static var footerTime: String {
        footerFormatter.string(from: Date())
    }
```

说明：`footerFormatter` 只读使用（`string(from:)` 不改 formatter 状态），static 延迟初始化一次，无并发写入风险；macOS 13 可用 API，无版本问题。

- [ ] **步骤 2：构建验证通过**

运行：同任务 1 步骤 2 命令。
预期：`BUILD SUCCEEDED`。

- [ ] **步骤 3：Commit**

```bash
git add NotchDrop/TokenZoneView.swift
git commit -m "perf: footerTime 的 DateFormatter 提为 static 缓存"
```
