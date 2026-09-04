# 四节拍动效重构 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 刘海展开对标 NotchNook 四节拍编排——深色玻璃外壳 + hover 预备拍菊花 + 弹性生长 + 内容分批入场 + 双曲线收起，附三条边界防御。

**架构：** 状态机零新增（`Status` 三态不动），预备拍用 `@Published preloading` 驱动；分批入场用 ViewModel 持有的 `Task` 链（可 cancel）；材质走 `Glass.swift` 新修饰符；每节拍独立 commit 可单独 revert。

**技术栈：** SwiftUI（macOS 13+，`Task`/`DispatchWorkItem` 原生并发），构建验证：`xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Debug -derivedDataPath /tmp/nDD build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO`

**规格来源：** `docs/superpowers/specs/2026-09-04-four-beats-animation-design.md`

---

## 文件结构

- 修改：`NotchDrop/Glass.swift`——新增 `darkGlassCard` 深色沉浸玻璃修饰符
- 创建：`NotchDrop/SpinnerView.swift`——8 叶放射菊花（纯绘制，无依赖）
- 修改：`NotchDrop/NotchViewModel.swift`——`preloading`、`entryTask`、双动画常量、预备拍任务
- 修改：`NotchDrop/NotchViewModel+Events.swift`——`mouseLocation` sink 补快速划过取消
- 修改：`NotchDrop/NotchView.swift`——外壳换材质、内容拆分批入场、挂命中穿透
- 注册：`NotchDrop.xcodeproj/project.pbxproj`——新文件进编译列表（手动 pbxproj，无同步组）

## 顺序依赖

任务 1（材质）与任务 2（菊花组件）无依赖可并行；任务 3（状态机）依赖任务 2 的组件存在；任务 4（视图装配）依赖全部；任务 5（事件防御）依赖任务 3。

---

### 任务 1：深色玻璃材质

**文件：**
- 修改：`NotchDrop/Glass.swift`（末尾追加）

- [ ] **步骤 1：在 `Glass.swift` 末尾追加修饰符**

```swift
// MARK: - 深色沉浸玻璃（NotchNook 风外壳）

extension View {
    /// 深色高透背景 + 磨砂模糊 + 细内描边高光
    func darkGlassCard(cornerRadius: CGFloat) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.09).opacity(0.75))
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}
```

- [ ] **步骤 2：`NotchView.swift` 的 `glassNotchBackground` 换用（仅此一处，节拍 0 装配提前到本任务闭环）**

```swift
    /// 玻璃刘海背景：深色沉浸玻璃
    private var glassNotchBackground: some View {
        Rectangle()
            .fill(.clear)
            .darkGlassCard(cornerRadius: notchCornerRadius)
    }
```

- [ ] **步骤 3：构建验证**

运行：`xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Debug -derivedDataPath /tmp/nDD build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E "error:|BUILD" | head -n 5`
预期：BUILD SUCCEEDED

- [ ] **步骤 4：Commit**

```bash
git add NotchDrop/Glass.swift NotchDrop/NotchView.swift
git commit -m "feat: 刘海外壳换深色沉浸玻璃（节拍0）"
```

---

### 任务 2：8 叶放射菊花组件

**文件：**
- 创建：`NotchDrop/SpinnerView.swift`
- 修改：`NotchDrop.xcodeproj/project.pbxproj`（注册新文件）

- [ ] **步骤 1：创建 `NotchDrop/SpinnerView.swift`**

```swift
//
//  SpinnerView.swift
//  NotchDrop
//
//  8 叶放射菊花（macOS 原生风）：叶条逐叶渐隐循环。
//

import SwiftUI

struct SpinnerView: View {
    var size: CGFloat = 13
    var color: Color = .white

    private let bladeCount = 8
    private let cycle: Double = 0.8

    var body: some View {
        ZStack {
            ForEach(0..<bladeCount, id: \.self) { i in
                Capsule()
                    .fill(color.opacity(0.9))
                    .frame(width: 1.5, height: size * 0.3)
                    .offset(y: -size * 0.35)
                    .rotationEffect(.degrees(Double(i) * 45))
                    .opacity(bladeOpacity)
                    .animation(
                        .linear(duration: cycle)
                            .delay(Double(i) * cycle / Double(bladeCount) * -1),
                        value: bladeOpacity
                    )
            }
        }
        .frame(width: size, height: size)
        .onAppear { bladeOpacity = 0.15 }
    }

    @State private var bladeOpacity: Double = 1
}
```

注：每叶透明度在 1→0.15 循环，delay 为负值实现逐叶相位错开（`-i × 0.1s`），纯 SwiftUI 无定时器。

- [ ] **步骤 2：注册进 `project.pbxproj`**

在 `PBXBuildFile` 区加（ID 沿用本项目手工编号风格）：

```
		A1B2C3D4E5F6071829304053 /* SpinnerView.swift in Sources */ = {isa = PBXBuildFile; fileRef = A1B2C3D4E5F6071829304052 /* SpinnerView.swift */; };
```

在 `PBXFileReference` 区加：

```
		A1B2C3D4E5F6071829304052 /* SpinnerView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SpinnerView.swift; sourceTree = "<group>"; };
```

在 NotchDrop group 的 children 里（`504381872C3A86EC000ED325 /* Assets.xcassets */` 附近）加：

```
				A1B2C3D4E5F6071829304052 /* SpinnerView.swift */,
```

在 `PBXSourcesBuildPhase` 的 files 列表加：

```
				A1B2C3D4E5F6071829304053 /* SpinnerView.swift in Sources */,
```

- [ ] **步骤 3：构建验证**

运行：同任务 1 步骤 3 命令
预期：BUILD SUCCEEDED

- [ ] **步骤 4：Commit**

```bash
git add NotchDrop/SpinnerView.swift NotchDrop.xcodeproj/project.pbxproj
git commit -m "feat: 8 叶放射菊花组件（节拍1组件）"
```

---

### 任务 3：预备拍状态机与双动画常量

**文件：**
- 修改：`NotchDrop/NotchViewModel.swift`

- [ ] **步骤 1：加发布属性与动画常量**

`@Published var notchVisible: Bool = true` 之后追加：

```swift
    @Published var preloading: Bool = false

    /// 展开弹簧（380/30/0.8 换算真值，轻微过冲）
    let openAnimation: Animation = .spring(response: 0.32, dampingFraction: 0.86)
    /// 收起弹簧（无过冲快退）
    let closeAnimation: Animation = .spring(response: 0.24, dampingFraction: 1.0)
```

- [ ] **步骤 2：加预备拍任务与可取消的入场任务字段**

`hoverCloseWorkItem` 声明之后追加：

```swift
    /// 预备拍任务（180ms 菊花期，快速划过时可取消）
    private var preloadWorkItem: DispatchWorkItem?
    /// 内容分批入场任务链（收起时立即取消，防残留半透明层）
    var entryTask: Task<Void, Never>?
```

- [ ] **步骤 3：改造 `notchOpen`，hover 走预备拍**

```swift
    func notchOpen(_ reason: OpenReason) {
        openReason = reason
        contentType = .normal
        if reason == .hover {
            // 预备拍：菊花 180ms 后进展开态
            preloading = true
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                preloading = false
                status = .opened
                NSApp.activate(ignoringOtherApps: true)
            }
            preloadWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
        } else {
            preloadWorkItem?.cancel()
            preloadWorkItem = nil
            preloading = false
            status = .opened
            NSApp.activate(ignoringOtherApps: true)
        }
    }
```

- [ ] **步骤 4：`notchClose` 补取消链**

```swift
    func notchClose() {
        preloadWorkItem?.cancel()
        preloadWorkItem = nil
        preloading = false
        entryTask?.cancel()
        entryTask = nil
        openReason = .unknown
        status = .closed
        contentType = .normal
    }
```

- [ ] **步骤 5：构建验证**

运行：同任务 1 步骤 3 命令
预期：BUILD SUCCEEDED

- [ ] **步骤 6：Commit**

```bash
git add NotchDrop/NotchViewModel.swift
git commit -m "feat: 预备拍状态机与双动画常量（节拍1/2/4）"
```

---

### 任务 4：视图装配——菊花、分批入场、命中穿透

**文件：**
- 修改：`NotchDrop/NotchView.swift`

- [ ] **步骤 1：内容 Group 换为分批入场版（替换 body 中第 49-68 行的 Group）**

```swift
            Group {
                if vm.status == .opened {
                    VStack(spacing: vm.spacing) {
                        NotchHeaderView(vm: vm)
                            .modifier(StaggeredEntry(delay: 0.12))
                        NotchContentView(vm: vm)
                            .modifier(StaggeredEntry(delay: 0.24))
                    }
                    .padding(vm.spacing)
                    .frame(maxWidth: vm.notchOpenedSize.width, maxHeight: vm.notchOpenedSize.height)
                    .zIndex(1)
                }
            }
            .allowsHitTesting(vm.status == .opened && !vm.preloading)
            .transition(
                .scale.combined(
                    with: .opacity
                ).combined(
                    with: .offset(y: -vm.notchOpenedSize.height / 2)
                ).animation(vm.closeAnimation)
            )
            .animation(vm.openAnimation, value: vm.status)
```

说明：顶栏 +120ms、内容 +240ms（托盘在 `NotchContentView` 内部与额度卡并排，整体一批进场；规格的分批批次 2/3 合并为主内容一批，减少参数面）。`allowsHitTesting` 覆盖防御 C。

- [ ] **步骤 2：刘海内加菊花（`body` 的 ZStack 里 `notch` 之后追加）**

```swift
            if vm.preloading {
                SpinnerView(size: 13)
                    .frame(width: vm.deviceNotchRect.width, height: vm.deviceNotchRect.height)
                    .offset(y: 6)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.12), value: vm.preloading)
                    .zIndex(2)
            }
```

- [ ] **步骤 3：文件末尾（struct 外）追加 StaggeredEntry 修饰符**

```swift
/// 分批入场修饰符：延迟后 opacity 0→1 + 下移入场；reduceMotion 直接显示
struct StaggeredEntry: ViewModifier {
    let delay: TimeInterval
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : -6)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.2).delay(delay)) {
                    shown = true
                }
            }
    }
}
```

注：`onAppear` 只在展开插入时触发一次，收起时整个 Group 移除，无残留。

- [ ] **步骤 4：构建验证**

运行：同任务 1 步骤 3 命令
预期：BUILD SUCCEEDED

- [ **步骤 5：目视验证（构建过即 commit，体感由用户验收）**

- [ ] **步骤 6：Commit**

```bash
git add NotchDrop/NotchView.swift
git commit -m "feat: 菊花预备拍与内容分批入场装配（节拍1/3）"
```

---

### 任务 5：快速划过取消（边界防御 A）

**文件：**
- 修改：`NotchDrop/NotchViewModel+Events.swift`

- [ ] **步骤 1：`mouseLocation` sink 补取消分支**

现 sink 中 `if status == .closed, aboutToOpen { notchOpen(.hover) }` 与 `if status == .popping, !aboutToOpen { notchClose() }` 两行之间，追加：

```swift
                // 边界防御 A：预备拍期间光标离开热区，立即取消（防幽灵展开）
                if preloading, !aboutToOpen {
                    cancelPreload()
                }
```

- [ ] **步骤 2：`NotchViewModel.swift` 补 `cancelPreload()`**

```swift
    func cancelPreload() {
        preloadWorkItem?.cancel()
        preloadWorkItem = nil
        preloading = false
    }
```

- [ ] **步骤 3：构建验证**

运行：同任务 1 步骤 3 命令
预期：BUILD SUCCEEDED

- [ ] **步骤 4：Commit**

```bash
git add NotchDrop/NotchViewModel+Events.swift NotchDrop/NotchViewModel.swift
git commit -m "feat: 快速划过取消预备拍（防御A）"
```

---

### 任务 6：收起节奏装配与全量验收

**文件：**
- 修改：`NotchDrop/NotchView.swift`
- 修改：`NotchDrop/NotchViewModel+Events.swift`

- [ ] **步骤 1：收起动画改 `closeAnimation` 并拆先退后收**

`NotchView.swift` body 的 `.animation(vm.animation, value: vm.status)`（内容 Group 上的）已在任务 4 换为 `openAnimation`；此处把 `notch` 的 frame 变化动画改用 close 曲线——在 `body` 的 ZStack 上追加：

```swift
        .animation(vm.closeAnimation, value: vm.status)
```

并在 `NotchViewModel+Events.swift` 的 mouseLocation sink 中，hover 延迟收起常量 `scheduleHoverClose` 里的 `0.15` 改 `0.3`：

```swift
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
```

- [ ] **步骤 2：Release 双配置构建**

运行：`xcodebuild -project NotchDrop.xcodeproj -scheme NotchDrop -configuration Release -derivedDataPath /tmp/nDDR build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E "error:|BUILD" | head -n 5`
预期：BUILD SUCCEEDED（Debug 已在前面任务验过）

- [ ] **步骤 3：逐项目视核对规格验收标准 1-6**

1. hover 展开看到菊花→弹开→分批进；点击/拖拽无菊花
2. 浅色壁纸外壳深色不透底
3. 展开轻微过冲、收起先退后收无过冲
4. reduceMotion 全直显
5. 每节拍独立 commit（git log 应有 6 个新 commit）
6. 防御三项：快速划过无展开/中断收起无残留/预备拍点击不误关

- [ ] **步骤 4：Commit（如有微调）**

```bash
git add -A
git commit -m "feat: 收起双曲线与 hover 缓冲对齐（节拍4）"
```

---

## 自检

1. **规格覆盖度：** 材质（任务 1）→ 8 叶菊花（任务 2）→ 预备拍状态机 + 防御 A 的取消函数（任务 3、5）→ 弹性生长参数（任务 3 步骤 1 常量 + 任务 4 装配）→ 分批入场（任务 4）→ 防御 C 命中穿透（任务 4 步骤 1 的 allowsHitTesting）→ 双曲线收起 + hover 300ms 缓冲（任务 6）→ 防御 B 的 `entryTask` 取消链（任务 3 步骤 2/4 定义、收起时取消；SwiftUI 状态驱动动画天然可打断）→ 验收标准 6 条（任务 6 步骤 3）。无遗漏。
2. **占位符扫描：** 无待定/TODO；所有代码块完整可粘贴；构建命令为可执行完整命令。
3. **类型一致性：** `preloading`/`preloadWorkItem`/`cancelPreload`/`entryTask`/`openAnimation`/`closeAnimation`（任务 3 定义）→ 任务 4 引用 `vm.preloading`/`vm.openAnimation`/`vm.closeAnimation` → 任务 5 引用 `cancelPreload` 与 `preloading` → 任务 6 引用 `closeAnimation` 与 `scheduleHoverClose` 的 0.3——全链一致。`SpinnerView(size:)` 初始化参数与任务 2 定义一致。
