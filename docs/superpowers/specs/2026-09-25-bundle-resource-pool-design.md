# 液态资源池重构设计规格

日期：2026-09-25
状态：头脑风暴产出，待用户审查
原型基准：`.superpowers/brainstorm/32564-1790345157/content/pool-final-b.html`（变体 B 终版，含视觉规格与 SwiftUI 映射要点）

## 背景

本地 `llm-bundle`（127.0.0.1:8080）已聚合 4 个上游反代：

| 上游 | 端口 | 内容 |
|---|---|---|
| antigravity | 8045 | Gemini 多账号（傅谷歌 / 傅吼吼等，5h + 周额度） |
| qodercn | 8097 | Qoder 托管网关（多账号 credits 池、每日签到） |
| zcode | 8098 | 智谱 BigModel / DeepSeek（Start-Plan，无余额接口） |
| opencode | 8099 | OpenCode Zen 免密通道（MiMo 等免费模型） |

现状四页：第一页 Antigravity 双卡、第二页 Token 流水（antigravity-tools 源）、第三页 Qoder 网关、第四页剪贴板。问题：第一/三页同为「账号池」重复；第二页只显示单一供应商接口；第四页剪贴板不再需要；第三页的手动任务（签到等）需要人守着。

## 目标

1. **第一页 + 第三页合并**为「液态资源池」——4 上游节点气泡池，承载请求的节点浮顶，消耗时向上蒸发消散（视觉变体 B 定稿）。
2. **第二页数据源切换**到 CC Switch（`~/.cc-switch/cc-switch.db`），聚合全部走集束的供应商请求。
3. **第四页剪贴板整体下线**（页面 + 监控 + 存储 + 测试）。
4. **Qoder 手动任务全自动化**：应用启动即执行（网关拉起、每日签到、配额探测）；签到失败弹**粘性气泡通知，必须用户手动关闭**；成功静默。

## 页面终态

- 分页数：**2 页**（资源池 / Token 流水），页序 `[.normal, .token]`。
- `ContentType` 删除 `.clipboard`、`.gateway` 两个 case；`baseZoneOrder` 相应更新；`showGatewayZone` 设置项移除。
- Qoder 网关进程控制（启停/重试/端口）保留在设置页，不进分页。

## 第一页：液态资源池（新组件 `PoolZoneView`）

### 结构（自顶向下）

1. 双层嵌套面板（Double-Bezel）：外托盘 R22 / 白 5% / padding 5 + 内核心 R17 / 渐变 #0C0F14→#07090C / 顶部内高光。
2. eyebrow 行：左侧节点状态点 + `LLM-BUNDLE · 4 NODES · :8080`；右侧当前延迟。
3. 模型透视条：当前执行模型（等宽字体 chip）+ 上游来源标签。
4. 池面舞台（高 226）：4 个气泡（主角 88pt 顶中，3 节点 52pt 池面线 y=146 三槽）、池面线、主角额度胶囊、池面倒影、蒸发层。
5. 统计三卡：今日跨源请求 / 总消耗 Tokens / 缓存命中率。

### 视觉与动效规格

以原型 `pool-final-b.html` 头部注释为准，要点：

- 色板：底 #050507；发丝线白 7–9%；节点色 antigravity #10B981 / zcode #A78BFA / qoder #22D3EE / opencode #FBBF24。
- 气泡：细进度环（主角 r=40 宽 2，节点 r=24 宽 1.5）+ 玻璃球体 + 左上镜面高光 + 池面倒影（径向渐变 + blur + 向下渐隐 mask）。
- 主角：内部流体对流（radialGradient 漂移，7s 循环）+ 呼吸（3.8s）。
- **物理对调**（已确认的核心逻辑）：目标节点升顶、原主角沉入目标槽，双向同时位移，0.5s spring `(0.34, 1.3, 0.64, 1)` 带过冲；同节点连续调用只轻颤。
- 蒸发：命中时从主角喷 1 胶囊（`-N tok · model`）+ 2 光粒，1.25s 上升 88pt 淡出。
- 文字防溢出：orb 内文字 `lineLimit(1)` + `minimumScaleFactor(0.7)` + 定宽容器。
- **0 功耗**：面板收起/隐藏时动画与对流全部暂停（全局 `isPaused`），仅展开时渲染循环。

### 数据流

- **主角判定**：`UsageStore.recentRequests`（CC Switch 源）最新一条的 model → 上游映射（gemini*→antigravity、glm*/deepseek*→zcode、qfmodel→qoder、mimo*/nemotron*→opencode）。新请求到达即触发对调 + 蒸发。
- **节点状态**：
  - antigravity：`AntigravityStore`（当前账号名 / 额度百分比 / 5h 重置）。
  - qoder：`QoderStore`（池 credits 余额、签到状态；失败计数 → 胶囊琥珀色警示）。
  - zcode / opencode：新组件 `BundleNodeMonitor`——端口探活（`isPortOpen`，已有纯函数）+ CC Switch 日志最近活跃时间派生；无余额接口，显示定性状态（如「就绪」「免密」）。
- **统计三卡**：`UsageStore.summary`（ccSwitch 源：calls / totalTokens / cacheRateFraction）。
- **蒸发数据**：新 `TokenRequest` 的 token 增量与模型名。

### 新组件

| 组件 | 职责 |
|---|---|
| `PoolZoneView` | 第一页视图（结构见上） |
| `BundleNodeMonitor` | zcode/opencode 探活 + 最近活跃；60s 轮询，测试可注入 |
| `ModelUpstreamMapper` | model 名 → 上游纯函数（单测覆盖） |
| `PoolSlotState` | 槽位分配状态机（4 槽对调逻辑，纯逻辑可单测） |
| `StickyAlertWindow` | 粘性失败气泡（见下） |

## Qoder 任务自动化与失败通知

### 自动化（应用启动即执行）

- 现有：`AppDelegate` 启动即 `runCampaignClaim()` + `refreshPoolQuotas()`（保留）。
- 新增：启动时托管网关未运行则自动 `QoderGatewayManager.start()`（8097 托管实例；8096 独立实例不受影响）。
- 签到幂等（claimer 按账号当天去重），重复触发无副作用；每日活动日 10:00 翻新后自动覆盖新一轮。

### 失败通知（粘性气泡）

- 触发条件：一轮自动签到存在 `.failure` 结果（全部成功/幂等 → 静默）。
- 形态：新组件 `StickyAlertWindow`——无边框非激活 NSPanel，位于刘海正下方（顶部中央），深色玻璃质感，红点 + 「Qoder 签到失败」摘要（失败账号数/原因）+ 关闭按钮。
- **粘性规则：必须用户手动点击关闭才消失**；不随面板收起/鼠标移开消失；再次失败再弹（合并显示最新一轮结果）。
- 联动：Qoder 节点额度胶囊显示「签到失败 ×N」琥珀色警示，直到下一轮成功。

## 第二页：Token 流水

- `UsageStore.activeSource` 默认值改为 `.ccSwitch`；`.antigravityTools` 保留为可选开关（设置页新增「流水数据源」选项，`@PublishedPersist` 持久化）。
- `TokenZoneView` UI 不变；耳朵区（左耳供应商名）自动跟随新源。
- 行增强（小改）：每行按 model 附上游标签（复用 `ModelUpstreamMapper`），让流水一眼看出走的是哪个池。

## 第四页：剪贴板下线

删除清单（含测试）：

- 视图/存储/监控/粘贴：`ClipboardZoneView`、`ClipboardStore`、`ClipboardMonitor`、`ClipboardPaster` 及对应测试文件。
- 启动挂载：`AppDelegate` 中 `ClipboardMonitor.shared.start()`。
- 分页：`NotchRootView` 的 `.clipboard` case 与 `@StateObject clipboard`；`ContentType.clipboard`。

## 旧组件清理

- 第一页旧卡：`AntigravityAccountsCardView`、`AntigravityProxyCardView` 删除（对称重排算法如需保留，迁入池节点排序）。
- 第三页：`GatewayZoneView`、`QoderPoolRingView` 删除（`QoderPoolIdMatcher`、`QoderCampaignClaimer` 等数据层保留，被池与自动化复用）。
- 设置页：`showGatewayZone` 开关移除；网关控制保留；新增流水数据源开关。

## 测试策略

- 新增：`ModelUpstreamMapperTests`、`PoolSlotStateTests`（对调状态机）、`BundleNodeMonitorTests`（注入探活）、`StickyAlertWindowTests`（粘性状态）。
- 更新：`TabMetricsTests` / `ContentZoneSwitcherTests`（页序 2 页）、涉及 `ContentType` 的既有测试、`UsageStore` 默认源断言。
- UI 验收：构建重启后**用户真机过目**（项目惯例：UI 改动须视觉验收再提交）。

## 实现顺序（供 writing-plans 展开）

1. 数据层：`ModelUpstreamMapper` + `BundleNodeMonitor` + `UsageStore` 默认源切换（纯逻辑，sonnet 可做）。
2. 自动化：网关自动拉起 + `StickyAlertWindow` + 失败检测接线。
3. 池 UI：`PoolZoneView` 全套视觉与动效（**opus**，按原型规格）。
4. 下线：剪贴板全删 + 旧页组件删除 + 页序更新。
5. 设置与测试更新 + 全量回归。
6. 用户真机视觉验收。

## 子智能体分工（派发时简报）

- UI/视觉/动效（池视图、粘性气泡样式）：**opus**。
- 数据层/状态机/自动化接线/测试：sonnet（纯逻辑，无视觉）。
