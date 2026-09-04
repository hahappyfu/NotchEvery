# B 方案：微扩虚影 + 点击展开 交互规格

> 前置：四节拍动效已落地（见 `2026-09-04-four-beats-animation-design.md`）。本规格改写其入口逻辑：hover 不再自动展开，改为虚影预告，点击才展开。
> 回退策略：单 commit 交付，不过 revert 整体重做。

## 交互状态机（变更点）

| 状态 | 视觉 | 进入 | 退出 |
|------|------|------|------|
| 收起 | 刘海常态 | 默认 / 收起完成 | — |
| **虚影态**（新） | 刘海宽 +16pt、高 +6pt；底色纯黑 → `#16161a`；0.35 投影浮起感 | hover 进入热区（即时，无延迟） | 离开热区（300ms 缓冲）/ 点击（转展开）/ 拖拽（转展开） |
| 展开 | 四节拍（不变） | **仅点击虚影刘海** / 拖拽 | 现有收起节奏 |

## 代码改动

1. `NotchViewModel.swift`：
   - `preloading` 改名 `hoverGhosting`（语义：虚影态标记）
   - 删 `preloadWorkItem` 180ms 预备拍任务与 `cancelPreload()`
   - `notchOpen(.hover)` 只置 `openReason = .hover` + `hoverGhosting = true`，**不置 `status = .opened`**
   - `notchClose()` 清 `hoverGhosting`
   - 新增 `openFromGhost()`：`hoverGhosting = false; status = .opened`（供点击/拖拽调用）
2. `NotchView.swift`：
   - `notch` 宽高按 `vm.hoverGhosting` 偏移（closed 态 +16/+6）
   - closed 态底色按 ghosting 切 `#16161a`，加 0.35 投影
   - 删 `SpinnerView` 挂载；删 `SpinnerView.swift` 文件与 pbxproj 注册
3. `NotchViewModel+Events.swift`：
   - `mouseLocation` sink：`hoverGhosting` 期间离开热区 300ms 缓冲后清 ghosting（复用 scheduleHoverClose 模式，guard 改 ghosting 条件）
   - `mouseDown` sink：`.closed` 分支点击时若 `hoverGhosting` 调 `openFromGhost()`
   - 拖拽 `dragDetector`：`notchOpen(.drag)` 保持直接展开（不变）

## 不变量

深色玻璃、双弹簧、分批入场、reduceMotion、300ms hover 缓冲、防御 A/B/C 语义保留（对象从 preloading 换 hoverGhosting）。

## 验收

1. hover 即出微扩虚影（无 180ms 等待、无菊花）
2. 虚影态不展开；点击虚影 → 四节拍展开
3. 虚影态移开鼠标 300ms 后虚影消退回常态
4. 拖拽到刘海仍直接展开（无虚影环节）
5. 快速划过（<300ms）虚影闪现即消，无展开
