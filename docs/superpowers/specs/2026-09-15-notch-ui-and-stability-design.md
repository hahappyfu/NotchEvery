# NotchEvery UI 适配、边缘渲染瑕疵与主线程死锁修复设计规格

**日期**：2026-09-15  
**状态**：已批准（Approved）  
**影响模块**：`FUnManager`, `NotchView`, `NotchViewModel`, `IslandMetrics`, `GuardControlZoneView`, `NotchRootView`

---

## 1. 背景与目标

近期使用与测试中暴露出四个直接影响可用性与视觉体验的关键问题：
1. **主线程死锁卡死**：后台蓝牙无感自动解锁失败时弹出模态弹窗，阻塞主 RunLoop 导致应用无响应（Spin/Hang）。
2. **左侧边缘渲染瑕疵**：刘海双耳外延切角目前采用白色图形与反向挖切遮罩（`destinationOut`），透明窗口边缘抗锯齿与预乘 Alpha 产生严重的白色亮边漏光伪影。
3. **内容小、黑框大（不相适应）**：原 `minPanelSize = 320×120` 配合 1.75 的长宽比保底，在内容较少时横纵向强制撑开空旷的纯黑背景。
4. **第三页（守护控制台）文本截断**：定宽 360pt（内宽仅 324pt）导致 Header 7 个控件冲突挤压、2×2 开关 6 字中文频繁触发省略号（...）、判定记录详情被腰斩。

**目标**：
- 根除后台静默流程中的任何模态弹窗，保障主线程绝对流畅；
- 采用连续闭合的正向平滑贝塞尔形状一次性成型填充纯黑，消灭边缘白边；
- 建立智能贴合物理底线的紧凑尺寸自适应策略（物理刘海保底，外接屏极致收紧，降低高度门槛，放宽长宽比）；
- 舒展重构第三页守护控制台，彻底杜绝任何文本省略截断。

---

## 2. 详细设计规格

### 模块 1：后台解锁主线程死锁根除 (`FUnManager.swift`)
- **根因**：`FUnManager.swift:658` 调用了 `self.system.fetchPassword(warn: true)`。一旦密码获取失败（如冷启动无交互权限），在主线程调用了 `UIHelper.errorModal()` -> `NSAlert.runModal()`，陷入死锁。
- **改动**：
  - 将调用改为 `self.system.fetchPassword(warn: false)`；
  - 遇到 `.failure(let error)` 时仅通过 `Log.sm.debug` 输出日志，并以 `recordUnlock(reason: .keychainColdBoot)` 登记到状态机，绝对不调用任何阻塞 UI。

### 模块 2：正向贝塞尔平滑岛体消除白边 (`NotchView.swift` & `SmoothNotchShape`)
- **根因**：`notchBackgroundMaskGroup` 使用白色椭圆配合 `.blendMode(.destinationOut)` 与 `+0.5, -0.5` 亚像素偏移反向抠图，透明窗口外缘留下半透明白色像素。
- **改动**：
  - 创建 `SmoothNotchShape: Shape`：
    - 正向从顶边中点向两侧延伸；
    - 左上角：外展反曲贝塞尔曲线平滑过渡至 `islandSize.width` 外侧；
    - 左下/右下：标准连续平滑圆角（`islandBottomRadius`）；
    - 右上角：对称的外展反曲贝塞尔曲线闭合回顶边；
  - 废弃 `notchBackgroundMaskGroup`，直接以 `SmoothNotchShape().fill(.black)` 作为岛体背景；
  - 消除白边伪影与多余的离屏渲染 Pass。

### 模块 3：紧凑自适应与物理刘海对齐 (`NotchViewModel.swift` & `IslandMetrics.swift`)
- **自适应规则**：
  - **高度下限**：`minPanelHeight` 从 120pt 降至 60pt；
  - **宽度下限**：
    - 若 `deviceNotchRect.width > 0`（MacBook 物理刘海屏），宽度下限设为 `max(deviceNotchRect.width + 16, natural.width)`；
    - 若 `deviceNotchRect.width == 0`（无刘海屏幕或外接显示器），宽度下限仅为自然内容宽（安全保底 160pt）；
  - **长宽比放宽**：取消 1.75 的强制长宽比横向拉伸，让小内容紧凑包裹；
  - **内边距**：保持 14~16pt 呼吸边距，兼具精致与圆润感。

### 模块 4：第三页（守护控制台）舒展重构 (`GuardControlZoneView.swift`)
- **宽度与边距**：
  - 容器定宽调整为自适应或适度放宽至 `390pt`；
- **Header 分层重构**：
  - 状态指示（呼吸绿点 + 状态名）居左；
  - 设备摘要与 RSSI 居中弹性展示，给予充足空间；
  - 运行控制（真执行/启用）紧凑居右，避免挤占设备名称；
- **2×2 开关优化**：
  - 开关卡片宽度提升至 175pt+；
  - 标题字号调整为 11.5pt，内边距微调，确保“接近唤醒屏幕”、“离开立即熄屏”、“屏保替代熄屏”、“键鼠活动保护”全部完整显示不被省略；
- **判定记录卡片支持上下双行**：
  - 上行：时间 + 判定结果徽章；
  - 下行：完整判定原因及 RSSI 详情，允许文本完整呈现。

---

## 3. 验证与验收标准
1. **死锁回归验证**：在未解锁钥匙串状态下触发 `attemptAutoUnlock`，确认无 `NSAlert.runModal` 调用，主线程不卡死。
2. **渲染回归验证**：在深色与浅色背景下观察刘海左右切角，无任何白色毛边或亮弧。
3. **尺寸自适应验证**：在有刘海屏与无刘海屏分别打开，确认尺寸紧贴内容且不露物理刘海底。
4. **文字截断验证**：打开第三页（守护控制台），确认所有中文标题、设备名及判定详情无 `...` 截断。
5. **单元测试**：`xcodebuild test` 全量通过。
