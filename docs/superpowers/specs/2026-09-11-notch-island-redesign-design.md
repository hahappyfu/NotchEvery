# 黑岛重构设计（刘海岛产品化）

日期：2026-09-11
状态：设计已批准（用户逐节确认；形态经交互原型验收）
视觉基准：`docs/superpowers/prototypes/2026-09-11-island-form.html`（三态 morph + 两页内容 + 深浅壁纸切换）、`docs/superpowers/prototypes/2026-09-11-island-form-v2.html`（+ dots 指示器样式确认，用户选定胶囊座）

## 背景

NotchEvery 现形态为「玻璃卡片悬于刘海下方」：material 刘海壳（NotchView）+ 0.55 实底玻璃面板（NotchRootView）+ 白描边。顶部条带与面板主体材质分层，观感不达标。用户决定对视觉形态做整体重构，目标「产品级刘海岛」（对标 boring.notch / NotchNook / Dynamic Lake 这类成熟产品）。

设计过程：形态三选一（纯黑岛 / 深色玻璃岛 / 跟随系统）→ 定**纯黑岛**；交互原型（三态 morph）经用户验收通过；自适应宽度策略经讨论定为实时自适应 + 钳制。

## 一、形态与状态

### 形态

- 纯黑岛（#000，不透明），从物理刘海向下长出、贴屏幕顶
- **实施修订（2026-09-11 实测）**：设计原定「凹角（concave fillet）」——排查证明 macOS 26 的 SwiftUI 对 concave 渲染（自绘 Shape 路径 / Canvas 直绘 / destinationOut 挖口 / 原版 mask 溢出）在本机**全线不可用**（连参考项目原版 NotchDrop 在此机亦失效，实测截图存档于会话账本）。最终采用 `RoundedRectangle(cornerRadius: islandBottomRadius, style: .continuous)`（凸圆角、四角同径：闲置见下、peek 13pt、展开 26pt）。
- 底部/顶部同半径圆角随状态变化：闲置 12pt / peek 13pt / 展开 26pt（数值以真机微调为准，原型为比例基准）

### 三态

| 状态 | 形态 | 内容 |
|---|---|---|
| 闲置（idle） | 与物理刘海完全一致（应用不可见） | 无 |
| 悬停（peek） | 从刘海向下/向两侧长出一截（原型约 350×82，真机内容驱动） | 今日概览小提示：绿点 + Tokens + 缓存命中率 |
| 展开（open） | 两页内容（概览 / Token） | 见「二、内容与布局」 |

### 动效

- 状态切换 = 形状 morph：spring 约 response 0.45 / damping 0.85（对应原型 0.52s cubic-bezier(0.22,1,0.36,1) 的观感）
- 内容层淡入带约 0.1s 延迟（形状先长、内容后现）；换页内容沿用现有方向性滑动过渡
- reduceMotion 降级：直切、无位移

### 交互（保持现行，仅换视觉）

- 悬停刘海 → peek；点击 → 展开；移开 / 点面板外 → 收起（现有两段式判定保留）
- 横扫 / 左右方向键 / 点 dots → 切页；右键菜单（设置 / 退出）；设置 Popover 系统样式不黑化
- 展开态记忆（本次运行内）：收起不重置分区，重启回概览

## 二、内容与布局

### 概览页

现额度卡内容（5h 大环 + 周/月条 + 状态行）黑底重排，白字系，阈值色（绿/橙/红）保留。

### Token 页

结构沿用：摘要条（Tokens / 缓存命中率 + 进度条）+ 请求表 5 行 + footer（缓存节省 / 更新于）。

耳区语义保留（ADR-0009）：当前供应商（左耳）/ 今日调用次数（右耳）位于刘海两侧条带内。

### 自适应宽度（本次新增）

- 模型列宽 = 当前 5 行中**最长模型名的实测宽度**，钳制 [100, 180]pt
- 岛宽 = 内容自然尺寸（ADR-0008 既有机制自动收敛）；列宽变化触发的岛宽变化走 morph 过渡
- 防抖动策略：**实时自适应**（不做只增不减、不取当日全局最长）；同一批 5 行通常同模型 → 宽度天然稳定，偶发变化呈「岛在适应内容」的观感

### 底部

dots 指示器保留**胶囊座现状款**（用户经原型 v2 选定）：容器白 0.08 + 描边白 0.15 + 黑投影，当前页 13×5 白 0.95、非当前页 5×5 白 0.3，spring 形变与点击直达不变。现有 `iOSPageIndicator` 已是全白色系、无系统语义色，在纯黑岛上直接成立，**无需改动**。

## 三、色彩与明暗

- **岛恒黑：不跟随系统浅色**（像硬件；浅色壁纸上同样成立，原型已验）
- 内容配色：primary 白 0.92 / secondary 白 0.55 / 卡片底白 0.06 / 分隔线白 0.07–0.12；accent 绿 #30d158；错误红沿用现状
- 应用内不再保留跟随系统的亮色分支

## 四、实现架构

### 形状层三合一

现结构：NotchView 的 material 刘海壳（zIndex 0）+ NotchRootView 的 0.55 玻璃（zIndex 1）+ `notchBackgroundMaskGroup` 的 destinationOut 凹角 hack。

**实施修订（2026-09-11）**：原计划的「单一 `IslandShape` 自绘凹角」在真机排查后废弃（concave 于 macOS 26 全线不可渲染，见「一、形态」修订注）。最终结构：

- 岛体 = `RoundedRectangle(cornerRadius: islandBottomRadius, style: .continuous)` 纯黑填充；无 material、无描边、无渐变
- 岛宽 = 内容自然宽 + 2 × islandFillet（侧边呼吸）；三态尺寸表（idle / peek / open）接入现有窗口与测量链路（NotchWindow pinnedContentSize + ZoneSizeGuard 机制不动）
- `IslandShape.swift` 及其几何测试已在排查收尾时删除（避免死代码留存）

### 内容重排

- `NotchRootView`：去玻璃底，内容直接坐黑岛；耳区条带配色随黑岛
- `QuotaCardView` / `TokenZoneView`：黑底配色重排；模型列宽改数据驱动（自适应宽度）
- `iOSPageIndicator`：无需改动（已是白色系胶囊座，纯黑岛直接成立）

## 五、删除与保留

**删除**：

- 0.55 玻璃底与 `PanelGlassShape`（形状层重写取代）
- material 刘海壳 / 白描边 / 顶部渐变高光（NotchView `glassNotchBackground` 整套）
- `notchBackgroundMaskGroup` 凹角 hack（形状层重写取代）
- 跟随系统浅色的一切假设与残留分支
- 模型列写死宽度（122pt）

**保留**：

- NotchWindow 窗口机制（pinnedContentSize）
- ADR-0008 内容驱动尺寸测量（ZoneSizeGuard / measuredNaturalSize 链路）
- 数据层全部（UsageStore / QuotaStore / PublishedPersist）
- 全部交互语义（切页 / 收起 / 右键菜单 / 设置）
- Glass.swift（仅剩 TrayDrop 一处调用，非本次范围）

## 六、验证

- 纯逻辑单测：模型列宽计算（实测 + clamp）、三态尺寸表
- 真机逐态视觉验收（以原型为基准）：闲置 / peek / 概览 / Token × 深浅壁纸
- 回归检查：切页、收起展开、数据刷新（3s 轮询下的宽度稳定）、reduceMotion
- 完成后代码审查

## 七、不做（YAGNI）

- 不动数据层与轮询逻辑
- 不新增内容页（媒体 / 日历等）
- 不做多显示器特殊处理（沿用现有几何）
- 设置 Popover 不黑化
- TrayDrop 疑似死代码清理（另行处理）

## 八、与既有文档的关系

- ADR-0008（内容驱动尺寸）：机制保留，本设计在其上增加「自适应列宽」的数据驱动
- ADR-0009（耳区 / 禁放区）：语义保留（禁放区仍是物理挖槽区、耳区仍按分区供内容），视觉随黑岛
- 本次落文档时已追加 ADR-0010 记录黑岛形态决策；实现完成后更新 CONTEXT.md「面板 / 虚影 / 耳区」词条口径
