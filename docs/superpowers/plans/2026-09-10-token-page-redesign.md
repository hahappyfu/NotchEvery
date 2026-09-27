# Token 第二页重设计实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** Token 第二页按 `macos.html` 布局重做（汇总栏 + 表格微调 + 底部状态栏 + 耳区两耳 + dots 胶囊换皮），颜色沿用 App 深色体系。

**架构：** 5 个任务全部落在 3 个现存视图文件内，不改数据结构、不改切页逻辑；每任务独立构建验证，最后统一部署重启、用户截图验收 5 处。

**技术栈：** SwiftUI（macOS 13+，`Task`/`DispatchWorkItem` 原生并发），构建验证：`xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Debug -derivedDataPath /tmp/nDD build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO`

**规格：** 本次 brainstorming 对话内设计方案（§0–§7，2026-09-10）：配色映射表 + 6 节组件规格 + 待拍板默认值（chip 文字 `Token`、表格要 hover 高亮）。执行者以该方案为论证依据。

## 全局约束

- 部署目标 macOS 13：不用 macOS 14+ API；`Text` 上的 `.foregroundStyle` 合并写法（`Text + Text`）会编译失败——多段异色文本必须用 HStack 包独立 `Text`、以 View 修饰符形式写（2026-09-10 已踩坑）。
- 颜色只用现存体系：`white.opacity(0.04~0.10)` 底、`separatorColor` 描边/分隔线、`.green`/`.secondary`/`.primary`、`tokenStatusColor` 红绿；不引入稿的亮 emerald/rose 十六进制。
- 构建产物必须进 `-derivedDataPath /tmp/nDD`（运行目录），构建完杀老进程并重启，否则用户看到的是旧 UI（2026-09-10 已踩坑）。
- 视觉验收靠用户截图（执行者无权截图），每任务注明验收点。
- 不碰：`TokenRequest`/`TokenSummary` 结构、`NotchViewModel` 切页逻辑、设置入口（右键菜单）、`StaggeredEntry`。

---

## 文件结构

- 修改：`NotchDrop/TokenZoneView.swift`——新增 `summaryBar`（汇总栏）、`footer`（底部状态栏）；表格字号下调 + 行 hover；`body` 内按 汇总栏 → header → 行 → 底部栏 顺序组装。
- 修改：`NotchDrop/NotchRootView.swift`——删除 `earLabel`，重写 `leftEarPill`（绿点 + 主模型名 + `Token` chip）、`rightEarPill`（`实时调用流`纯文本）。
- 修改：`NotchDrop/iOSPageIndicator.swift`——滑动胶囊机制退役，改双槽 morph（当前 16×6 白胶囊 / 非当前 6×6 半透明点，spring 形变），外包深色 dock 胶囊；点击直达与 reduceMotion 旁路保留。

---

### 任务 1：汇总栏

**文件：**
- 修改：`NotchDrop/TokenZoneView.swift`（新增 `summaryBar`，`body` 首行插入）

- [ ] **步骤 1：新增 summaryBar 并组装进 body**

```swift
private var summaryBar: some View {
    HStack {
        HStack(spacing: 6) {
            Text("Tokens")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(TokenSummary.mock.totalTokens)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
        }
        Spacer()
        HStack(spacing: 6) {
            Text("缓存命中率")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.green)
            Text(TokenSummary.mock.cacheRate)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.green)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 64, height: 6)
                Capsule()
                    .fill(Color.green)
                    .frame(width: 64 * 0.946, height: 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.green.opacity(0.20), lineWidth: 1))
        Spacer()
        HStack(spacing: 6) {
            Text("调用量")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(TokenSummary.mock.calls)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
        }
    }
    .monospacedDigit()
    .lineLimit(1)
    .minimumScaleFactor(0.85)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1))
    .padding(.bottom, 10)
}
```

说明（非占位符，是有意简化，执行者照做不发挥）：进度条填充比 `0.946` 与 `cacheRate "94.6%"` 手工同构（mock 策略，接数据源时替换构造处）；`调用量` 的 `次` 与数字同字号（稿里 `次` 更小，此处简化，差距可忽略）。

body 组装（`VStack(spacing: 0)` 首行加 `summaryBar`，其余不动）：

```swift
VStack(spacing: 0) {
    summaryBar
    header
    ForEach(requests.prefix(5)) { row in
    // …以下不动
```

- [ ] **步骤 2：构建验证通过**

运行：`xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Debug -derivedDataPath /tmp/nDD build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | head -20`
预期：`BUILD SUCCEEDED`，无 `error:` 行。

- [ ] **步骤 3：Commit**

```bash
git add NotchDrop/TokenZoneView.swift
git commit -m "feat: Token 页新增汇总栏（Tokens/缓存命中率胶囊/调用量）"
```

验收点（用户截图）：汇总栏三段 + 中间绿胶囊 + 进度条。

### 任务 2：表格字号 + 行 hover

**文件：**
- 修改：`NotchDrop/TokenZoneView.swift`（抽 `TokenRowView` 子视图，header 字号）

- [ ] **步骤 1：抽行子视图并加 hover，header 字号 10→11**

```swift
private struct TokenRowView: View {
    let row: TokenRequest
    let timeW: CGFloat
    let modelW: CGFloat
    let durationW: CGFloat
    let statusW: CGFloat
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(row.time)
                .frame(width: timeW, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(row.model)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .frame(width: modelW, alignment: .leading)
            Text("\(row.inputTokens.formatted()) / \(row.outputTokens.formatted())")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(String(format: "%.1fs", row.durationSeconds))
                .frame(width: durationW, alignment: .trailing)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Circle()
                    .fill(tokenStatusColor(row.status))
                    .frame(width: 6, height: 6)
                Text("\(row.status)")
                    .foregroundStyle(row.status >= 400 ? tokenStatusColor(row.status) : .secondary)
            }
            .frame(width: statusW, alignment: .trailing)
        }
        .font(.system(size: 11))
        .monospacedDigit()
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(hovering ? Color.white.opacity(0.04) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.5))
                .frame(height: 0.5)
        }
    }
}
```

`body` 内 `ForEach` 改为：

```swift
ForEach(requests.prefix(5)) { row in
    TokenRowView(row: row, timeW: timeW, modelW: modelW, durationW: durationW, statusW: statusW)
}
```

header 字号单改一行：`.font(.system(size: 10, weight: .semibold))` → `.font(.system(size: 11, weight: .medium))`。列宽常量、圆点状态、对齐方式一行不许动。

- [ ] **步骤 2：构建验证通过**

运行：同任务 1 步骤 2 命令。
预期：`BUILD SUCCEEDED`。

- [ ] **步骤 3：Commit**

```bash
git add NotchDrop/TokenZoneView.swift
git commit -m "feat: Token 表格抽行视图加 hover，字号向样式稿看齐"
```

验收点（用户截图）：行 11 号、`入 / 出` 10 号灰字、鼠标悬停行有淡底。

### 任务 3：底部状态栏

**文件：**
- 修改：`NotchDrop/TokenZoneView.swift`（新增 `footer`，`body` 末尾插入）

- [ ] **步骤 1：新增 footer 并组装进 body**

```swift
private var footer: some View {
    VStack(spacing: 10) {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.5))
            .frame(height: 0.5)
        HStack {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
            Text("上下文缓存命中已开启 (Prompt Cache 10%)")
            Spacer()
            Text("更新于 \(Self.footerTime)")
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }
    .padding(.top, 10)
}

private static var footerTime: String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f.string(from: Date())
}
```

body 组装（`ForEach` 之后、`VStack` 闭合之前加 `footer` 一行）：

```swift
        ForEach(requests.prefix(5)) { row in
            TokenRowView(row: row, timeW: timeW, modelW: modelW, durationW: durationW, statusW: statusW)
        }
        footer
    }
```

说明：文案与 `(Prompt Cache 10%)` 为 mock 常量，`footerTime` 取渲染时当前时间（与 `TokenRequest.mock` 同策略，接数据源时替换构造处）。

- [ ] **步骤 2：构建验证通过**

运行：同任务 1 步骤 2 命令。
预期：`BUILD SUCCEEDED`。

- [ ] **步骤 3：Commit**

```bash
git add NotchDrop/TokenZoneView.swift
git commit -m "feat: Token 页新增底部状态栏（缓存开启/更新于）"
```

验收点（用户截图）：底部分隔线 + 左绿点文案 + 右更新时间。

### 任务 4：耳区两耳按稿重写

**文件：**
- 修改：`NotchDrop/NotchRootView.swift`（删除 `earLabel`，重写 `leftEarPill`/`rightEarPill`）

- [ ] **步骤 1：替换耳区实现**

删除 `earLabel` 整个函数（全局约束：多段异色文本用 HStack 包独立 Text，禁止 `Text + Text` 合并写法）。替换为：

```swift
@ViewBuilder
private var leftEarPill: some View {
    if vm.contentType == .token {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
            Text(TokenRequest.mock.first?.model ?? "opus-5")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Token")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Color.white.opacity(0.10), in: Capsule())
        }
        .monospacedDigit()
        .lineLimit(1)
        .truncationMode(.tail)
        .minimumScaleFactor(0.8)
    }
}

@ViewBuilder
private var rightEarPill: some View {
    if vm.contentType == .token {
        Text("实时调用流")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}
```

`earsRow` 的三段注释里 `左耳胶囊/右耳胶囊` 字样若还在，顺手改为 `左耳/右耳`（自己上一轮留的尾巴，不动其他注释）。模型名取 mock 首行（接数据源自动对，不写死）；chip 文字 `Token` 为已定默认值。

- [ ] **步骤 2：构建验证通过**

运行：同任务 1 步骤 2 命令。
预期：`BUILD SUCCEEDED`。

- [ ] **步骤 3：Commit**

```bash
git add NotchDrop/NotchRootView.swift
git commit -m "feat: 耳区按稿重写（绿点+主模型+Token chip/实时调用流）"
```

验收点（用户截图）：左耳三段、右耳文字、无胶囊底、无截断。

### 任务 5：dots 换 HTML dock 胶囊皮

**文件：**
- 修改：`NotchDrop/iOSPageIndicator.swift`（body 重写，保留点击直达与 reduceMotion 旁路）

- [ ] **步骤 1：重写 body 为双槽 morph + dock 容器**

```swift
var body: some View {
    HStack(spacing: 6) {
        ForEach(0..<pageCount, id: \.self) { i in
            Capsule()
                .fill(Color.white.opacity(i == currentPage ? 0.95 : 0.3))
                .frame(width: i == currentPage ? 16 : 6, height: 6)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82),
                    value: currentPage
                )
                .overlay {
                    Color.clear
                        .frame(width: 20, height: 16)
                        .contentShape(Rectangle())
                        .onTapGesture { currentPage = i }
                }
        }
    }
    .padding(.horizontal, 10)
    .frame(height: 22)
    .background(Color.white.opacity(0.06), in: Capsule())
    .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
}
```

说明：滑动胶囊机制（`GeometryReader` + `position` + `stride`）退役——双页下槽 morph 行为等价且更简单；`point`/`spacing`/`capsuleWidth`/`stride` 私有量随旧 body 一起删除；点击直达（`currentPage = i`）、reduceMotion 直通、spring 参数 `(0.28, 0.82)` 原样保留。文件顶部注释按新实现重写一行（旧注释描述滑动机制，留着会误导）。

- [ ] **步骤 2：构建验证通过**

运行：同任务 1 步骤 2 命令。
预期：`BUILD SUCCEEDED`。

- [ ] **步骤 3：Commit**

```bash
git add NotchDrop/iOSPageIndicator.swift
git commit -m "feat: dots 换深色 dock 胶囊皮（双槽 morph）"
```

验收点（用户截图）：深色小胶囊、当前页白长条、切页形变。

### 任务 6：部署重启与总验收

**文件：** 无（流程任务）

- [ ] **步骤 1：杀老进程并重启新构建**

```bash
pkill -x NotchEvery; sleep 1; open /tmp/nDD/Build/Products/Debug/NotchEvery.app; sleep 2; ps aux | grep "nDD.*NotchEvery" | grep -v grep | head -3
```

预期：`ps` 输出中新 PID（启动时间为当前），且 `grep` 不再含旧进程。`pkill` 若报 `no matching processes` 属正常（App 未在跑），继续执行 `open`。

- [ ] **步骤 2：向用户索取 5 处截图验收**

5 处：汇总栏、表格（含 hover）、底部状态栏、耳区两耳、dots 胶囊。有一处不符即按系统化调试流程回查（先确认进程是否为新构建，再查代码），不猜测式修复。

---

## 自检记录（编写者已执行）

1. **规格覆盖度：** 汇总栏→任务 1；表格字号/hover→任务 2；底部栏→任务 3；耳区→任务 4；dots→任务 5；配色映射→各任务代码内数值；macOS 13 约束→全局约束 + 任务 4 说明；部署重启→任务 6。无遗漏。
2. **占位符扫描：** 全文无"待定/TODO/适当/类似任务 N"；两处有意简化（调用量 `次` 同字号、进度条比例手写 `0.946`）已在任务内写明做法与理由。
3. **类型一致性：** `TokenSummary.mock.totalTokens/cacheRate/calls`（String）与 `TokenZoneView.swift:33-40` 一致；`TokenRequest.mock.first?.model`（String?，`?? "opus-5"` 兜底）与 `TokenZoneView.swift:11-30` 一致；列宽常量名 `timeW/modelW/durationW/statusW` 与当前 `TokenZoneView` 内定义一致；`currentPage` 为 `Binding<Int>`（`iOSPageIndicator.swift:12`），任务 5 内 `i == currentPage` 类型正确。
