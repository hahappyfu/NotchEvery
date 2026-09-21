# Qoder 网关分区 UI 视觉重构设计规格

## 1. 背景与现状审视（Pain Points）

当前实现虽已打通底层链路（进程启停、账号池轮询、额度读取全部正常），但视觉呈现粗糙，与 NotchEvery 现有的高端工业风（Apple Native Studio）设计系统严重脱节：

1. **红圈警告感过强**：探针未通过时，4 个高饱和度大红圈（`StudioColor.rose`）加红色三角警报图标，造成严重的视觉焦虑和“系统灾难”错觉。
2. **圆环缺乏物理层次**：当前就是一个单层 `Circle().stroke()` + 纯色字，缺少第一页卡片具备的“背槽、深度、内陷阴影、微质感光晕”。
3. **两张卡片呆板堆叠**：上下各一个 360pt 的孤立黑色块，卡片间距 10pt，整体显得松散，缺乏主次呼吸。
4. **状态与启停按钮突兀**：红色的「■ 停止」胶囊按钮过于抢眼，喧宾夺主。

---

## 2. 设计哲学与对齐标准（Design Principles）

严格继承第一页（`AntigravityAccountsCardView` + `AntigravityProxyCardView`）的设计精髓：
- **Dark Tech / Apple Native Studio 工业质感**：纯黑/极深灰底岛（`#0D0D0E`），配合 1px 细微发光边框（`white.opacity(0.08)`）。
- **众星捧月环形舞台（3D Ring Stage）**：当前活跃/粘性账号居中凸显（微放大 1.08x、柔和光晕浮出、Z 轴微提），两翼账号自然微退后并微带透视。
- **克制且高雅的状态色彩体系**：
  - **活跃中（Active/In-Use）**：苹果薄荷绿（`#30D158` / `StudioColor.emerald`），带极微量发光，绝不刺眼。
  - **冷却中（Cooled）**：温暖深琥珀金（`#FF9F0A` / `StudioColor.amber`），搭配雪花或沙漏微图标。
  - **备用就绪/普通就绪**：沉稳石墨灰白微光（`white.opacity(0.35)`），正常工作态，**禁止滥用刺眼警报大红**！
  - **粘性主力号**：双层微光环，内嵌翠绿微点，明确标注当前请求通道。

---

## 3. 核心视觉组件重构蓝图

### 组件 A：账号池“星轨”舞台（QoderPoolStageView）

每个账号不再是粗暴的红圈，重构为一个**多层复合圆形胶囊徽章（Circular Orb Capsule）**：

1. **外轨道槽（Outer Track）**：
   - 48×48pt 直径圆形底座。
   - 背景采用深色半透槽体：`Color.white.opacity(0.04)` 配合 1px 内边框 `Color.white.opacity(0.08)`。
2. **状态光环（Status Arc / Ring）**：
   - 使用双层柔和环形条（`lineWidth: 2.5`）：
     - 主力/粘性活跃：薄荷绿外圈（`StudioColor.emerald`）+ 外围柔和绿晕（`blur: 4, opacity: 0.25`）。
     - 普通备用（正常工作）：沉稳蓝灰/冰白渐变环（`white.opacity(0.35)`），平滑不抢戏。
     - 冷却中（Cooled）：暗琥珀色环（`StudioColor.amber.opacity(0.7)`）。
     - 彻底失效/退役：深石墨灰（`white.opacity(0.12)`）。
3. **中心核（Core Area）**：
   - 上排：4 位十六进制尾号（如 `a057`），采用 `.system(size: 11, weight: .semibold, design: .monospaced)`，白色透明度按活跃度分级（`0.95` vs `0.55`）。
   - 下排：精致的微型状态点或极简符号（6pt 字号）：
     - 主力号显示 `● 活跃` 或绿点微标。
     - 冷却号显示迷你琥珀雪花 `snowflake`。
     - 备用号显示微小灰白点，保持呼吸感。

### 组件 B：卡片顶栏与控制按钮融合（Header & Micro-Actions）

- **左侧**：状态呼吸灯（running: 绿点；stopped: 灰点）+ 标题「Qoder 账号池」，右侧紧跟一个次级副标「4 节点可用」。
- **右侧**：极简高阶的启停控件。不要刺眼的红色大方块，采用与系统控制中心一致的**微型圆角动作胶囊（Micro Action Capsule）**：
  - 运行中时：深暗灰底（`white.opacity(0.08)`）+ 柔和白字「停止」，悬停时轻微泛红，不抢走整个卡片的视觉焦点。
  - 停止时：低饱和度翡翠绿文字「▶ 启动」+ 极淡绿背景。

### 组件 C：第二张卡片：度量看板（QoderMetricsCardView）

完全对齐第一页 `AntigravityProxyCardView` 的**三个内嵌小卡片（Studio Metric Cells）**：
- 采用 `.studioCard(radius: 8)` 质感。
- **Cell 1**：`今日请求`，大字 `0`，小字单位 `次`。
- **Cell 2**：`消耗 Credits`，大字 `0.00`，精炼数字显示。
- **Cell 3**：`剩余配额`，大字 `300`，右上角角标 `Credits`。
- **底部状态条（Footer Bar）**：
  - 左侧：重置日期（例如 `重置: 10-04 17:07`），采用低饱和字体。
  - 右侧：如果存在缓存，显示绿色胶囊徽章 `缓存率 xx%`。
