# NotchEvery 苹果原生级丝滑动画体系重构规格说明

- **创建日期**：2026-09-17
- **分类**：架构级规格（Architectural Spec）
- **覆盖模块**：`NotchViewModel`, `NotchView`, `NotchContentView`, `NotchRootView`, `NotchWindowController`, `DesignSystem`

---

## 1. 现状痛点与根因分析

经过对当前动画链路（展开、收起、切页、悬停）的代码走查与排查，确认导致动画不丝滑、卡顿与掉帧的 4 个根本原因：

1. **弹簧物理参数偏离苹果原生感知**：
   - 展开动画 `openAnimation` 设定为 `duration: 0.5, extraBounce: 0.1`，整体时间过长（500ms），启动初速度不足，肉眼感知迟钝；
   - 收起动画 `closeAnimation` 居然带有 `extraBounce: 0.25` 的强回弹。物理刘海是刚性贴顶黑条，向刘海收缩时产生剧烈回弹震荡在视觉上极不自然、拖沓卡顿；
   - 缺乏针对 ProMotion 120Hz 高刷屏的动态微调阻尼。

2. **动画事务触发脱节与步调不一致（撕裂感源头）**：
   - 在 `openFromGhost()` 和 `notchOpen(.click)` 中，直接赋值 `status = .opened`，缺少显式的 `withAnimation(openAnimation)` 全局事务包裹；
   - 背景 `SmoothNotchShape` 依赖 `islandSize` 内部隐式动画，而内容层 `NotchContentView` 与 `StaggeredEntry` 又在各自的局部作用域执行带 60ms delay 的次级动画，导致“黑色岛体在延展，内层卡顿半拍突然下移”，造成严重的视觉断层。

3. **切页转场不对称与突兀淡出**：
   - `zoneSlideNext` 与 `zoneSlidePrevious` 中，旧页面移除采用 150ms 纯淡出，新页面采用 24pt 偏移滑入。这导致切页中间期出现旧内容骤灭、新内容单独滑入的空窗与抖动感。

4. **AppKit 窗口帧频与无用重绘压迫主线程**：
   - `NotchWindowController` 监听 `vm.$measuredNaturalSize`，每当子视图上报尺寸或测量微调时，无条件调用 `window.setFrame(target, display: true)`。缺少坐标判等过滤，导致动画帧内多次强制重刷整个透明窗口，抢占 GPU/CPU。

---

## 2. 优化方案与技术规格

### 2.1 苹果原生物理弹簧参数对齐

在 `NotchViewModel.swift` 及 `DesignSystem.swift` 中，全面弃用已废弃或手感生硬的 `interactiveSpring(duration:extraBounce:)`，换用高精度 Spring：

- **展开弹簧（Open Spring）**：
  ```swift
  // 快速响应 + 柔和果冻感（360ms 快速展开，0.82 阻尼保留苹果标志性微回弹）
  let openAnimation: Animation = .spring(response: 0.36, dampingFraction: 0.82, blendDuration: 0.08)
  ```
- **收起弹簧（Close Spring）**：
  ```swift
  // 利落吸附 + 临界阻尼（260ms 快速缩合，1.0 阻尼确保绝对无回弹，迅速吸附进刘海）
  let closeAnimation: Animation = .spring(response: 0.26, dampingFraction: 1.0, blendDuration: 0.05)
  ```
- **切页弹簧（Page Slide Spring）**：
  ```swift
  // 高抗抖横向位移弹簧（320ms 紧凑阻尼，平稳推进）
  let pageAnimation: Animation = .spring(response: 0.32, dampingFraction: 0.86)
  ```
- **悬停 Peek 弹簧（Hover Peek Spring）**：
  ```swift
  // 微感知弹性呼吸（280ms，0.84 阻尼）
  let peekAnimation: Animation = .spring(response: 0.28, dampingFraction: 0.84)
  ```

---

### 2.2 状态驱动与全局动画事务收敛

1. **统一开合动画上下文**：
   - 在 `openFromGhost()` 和 `notchOpen(_ reason: OpenReason)` 中，统一显式包裹在 `withAnimation(openAnimation)`；
   - 在 `notchClose()` 中，显式统一包裹在 `withAnimation(closeAnimation)`；
   - `jumpToZone` / `nextZone` / `previousZone` 中统一包裹在 `withAnimation(pageAnimation)`。
2. **消灭脱节的内层延时修饰器**：
   - 彻底移除 `NotchView.swift` 中的 `StaggeredEntry(delay: 0.06)`；
   - 内容层与外壳统一采用顶锚点平滑协同伸展：
     ```swift
     .transition(.scale(scale: 0.94, anchor: .top).combined(with: .opacity))
     ```
   - 动画期间背景与前景共享同一时间基准，消灭时序冲突。

---

### 2.3 切页转场视觉连续性升级

重构 `NotchContentView.swift` 的转场定义，使切页动作具备流畅的景深与位移过渡：
- **推进与退出协同**：
  - 进入页面：横向平移 28pt + 平滑淡入（`insertion`）；
  - 退出页面：横向反向平移 20pt + 平滑淡出（`removal`），不再突然就地淡出消失；
  - 消除切页时的白色底闪和并集尺寸撑大问题。

---

### 2.4 窗口与图层渲染防抖

1. **`NotchWindowController` 增量更新机制**：
   - 在 sink 接收到尺寸与状态变更时，计算目标 `target` 矩形；
   - 增加精确判断：`if window.frame != target` 或两者的尺寸/位置差异大于 0.5pt 时才执行 `window.setFrame(target, display: true)`；
   - 避免稳态下的无意义重绘。
2. **窗口硬件加速与刷新率保证**：
   - 确保 `NotchWindow` 图层启用 CoreAnimation 离屏渲染缓冲优化（`window.contentView?.wantsLayer = true`）；
   - 允许支持 ProMotion 动态帧率（120Hz），避免被系统降频锁定在 60Hz。

---

## 3. 验收标准与测试保障

1. **测试用例保障**：
   - 保证现有的全量单元测试（445+ 个）保持稳定；
   - 更新并确保 `ZoneSizeGuardTests`, `TabMetricsTests` 等动画参数与尺寸测试通过。
2. **真机交互手感验收**：
   - **展开**：点击或鼠标移入时，灵动岛如同水滴/果冻般自然舒展，无延迟、无卡顿；
   - **收起**：鼠标移出或点击外部时，面板利落收纳进刘海，收尾平稳无反向抽搐；
   - **切页**：左右滑动手势或方向键切页时，内容平滑横向滑动推移，零掉帧。
