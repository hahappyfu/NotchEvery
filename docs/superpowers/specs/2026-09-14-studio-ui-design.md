# NotchEvery 工业级 / 产品级 UI 设计规格说明书 (Apple Native Studio)

**日期**：2026-09-14  
**状态**：已批准  
**风格定位**：Apple Native Studio（高精度 macOS 原生现代美学，深色磨砂亚克力玻璃、0.5pt 双层精密描边、Bento 微卡片、物理弹簧动效）  
**覆盖范围**：灵动岛主面板三页（配额卡、托盘、守护控制台）、独立偏好设置大窗口（6 Tab）、测距校准向导弹窗

---

## 1. 架构目标与设计原则

1. **单一点设计系统 (Single Source of Design Truth)**：
   - 在 `NotchDrop/DesignSystem.swift` 中建立原生无依赖的设计系统。
   - 统一收拢颜色 (`StudioColor`)、表面材质 (`StudioMaterial`)、排版标尺 (`StudioFont`)、动效规范 (`StudioAnimation`) 与通用修饰器 (`.studioCard()`, `.studioPillBadge()` 等)。
2. **Apple Native Studio 质感**：
   - 采用深色磨砂亚克力玻璃（`Color.black.opacity(0.82)` 叠 `.ultraThinMaterial`）为基底。
   - 0.5pt 精密高光边框（外发光 `white.opacity(0.12)` + 0.5pt 内边框）。
   - 关键指标使用 `.monospacedDigit()` 消除数字变动引发的抖动，状态指示灯辅以柔和呼吸脉冲。
3. **零过度设计与轻量化 (Ponytail & Performance)**：
   - 绝不引入臃肿第三方库，纯原生 SwiftUI ViewModifier 与 Shape 实现。
   - 动画采用原生交互弹簧（`response: 0.32, dampingFraction: 0.82`），干脆利落。

---

## 2. 核心模块重塑设计

### 2.1 基础设计系统 (`DesignSystem.swift`)
- **Tokens**：
  - `StudioMaterial.islandBackground`: 灵动岛深度深空灰磨砂。
  - `StudioMaterial.cardBackground`: 0.05 亮白半透微卡片层。
  - `StudioMaterial.cardHoverBackground`: 0.09 亮白悬浮层。
  - `StudioMaterial.innerBorder`: 0.5pt 微光描边。
- **Status Colors**：
  - `emerald` (`#10B981`): 守护就绪 / 充裕健康。
  - `amber` (`#F59E0B`): 警告 / 配额紧张 / 冷静中。
  - `rose` (`#F43F5E`): 锁定 / 风险拦截。
  - `indigo` (`#6366F1`): 智能守护 / 会话脉冲。
  - `cyan` (`#06B6D4`): 动态数据流。
- **ViewModifiers**：
  - `.studioCard(radius: 12, isHovered: false)`
  - `.studioPillBadge(color: Color)`
  - `.studioSpringAnimation()`

### 2.2 灵动岛第 1 页：配额与账号池仪表盘 (`UsageView.swift`)
- **微型 Bento 布局**：
  - 4 账号卡片以微网格排布，提供即时状态感知。
  - 环形/条形进度轨加入渐变微光，色彩随余量健康度（绿 -> 黄 -> 橙）平滑渐变。
- **等宽倒计时与微交互**：
  - 刷新倒计时与余量数值统一采用 `.monospacedDigit()` 胶囊小标签。

### 2.3 灵动岛第 2 页：文件聚合托盘 (`TrayDropView.swift` & `DropItemView.swift`)
- **空态沉浸指引**：
  - 半透明悬浮卡片 + 微光下落图标，拖拽进入时触发边框柔和呼吸高光。
- **文件卡片质感升级**：
  - macOS 经典图标叠放质感，带 0.5pt 边缘高光与文件扩展名微型角标。
  - 悬停浮起动画（Lift Effect，轻微 scale + 阴影变化）。
  - 底部操作按钮微型胶囊化。

### 2.4 灵动岛第 3 页：守护控制台 (`GuardControlZoneView.swift`)
- **雷达同心圆动态呼吸指示**：
  - 状态指示灯（Armed / Active / Sleeping）外圈叠加柔和微动效呼吸环。
- **2×2 高密度微卡片开关**：
  - 原生 Toggle 封装为卡片整体点击态，选中时边缘微发光。
  - 步进器调整区采用一体化胶囊步进按钮，数值等宽居中。
- **底部快捷导航胶囊**：
  - 一键打开偏好设置大窗口与校准向导，视觉与主面板彻底融合。

### 2.5 独立偏好设置大窗口 (`PreferencesWindow.swift`)
- **左侧边栏**：
  - 原生 `.sidebar` 材质结合微渐变底板。
  - 图标采用 System Settings 风格的圆角彩色底板图标。
  - 选中态采用柔和胶囊指示器。
- **右侧 Form/Sections**：
  - 废弃简陋原生 Form 质感，重构为现代卡片式分组（`StudioSectionGroup`）。
  - 诊断日志页（Diagnostics Tab）：结构化日志时序卡片、专有色标本地化徽章、顶部微型工具栏（过滤、清理、导出）。
  - 测距校准页（Calibration Tab）：内嵌可视化雷达测距光晕图例。

### 2.6 测距校准向导弹窗 (`DistanceCalibrationWizard.swift`)
- 步骤切换采用流线型微发光进度步进条。
- 雷达探测视图实时反馈距离动态，由蓝渐变转绿，状态更鲜明。

---

## 3. 测试与验证策略

1. **编译与类型安全**：确保纯 SwiftUI 无编译警告，所有现存存储键与绑定无缝承接。
2. **布局与尺寸保护**：确保灵动岛面板自然展开尺寸在三页切换时依然满足 `ZoneSizeGuardTests` 与面板钳制规则。
3. **交互手感验证**：弹簧动效、悬停状态与真机视觉核对。
