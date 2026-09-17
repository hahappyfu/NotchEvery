# 第二页用量监控重构为实时请求流（Live Stream）实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 彻底重构 NotchEvery 第二页（TokenZoneView）为「纯净实时流水（Live Stream）」，去除与第一页重复的 KPI 大卡片，采用 3 栏平衡设计，呈现模型徽标、账号标识、带色彩分级的缓存命中率进度条、总 Token 及耗时。

**架构：**
- 数据层：`TokenRequest` 扩充 `cachedTokens: Int` 字段；`UsageStore` 透传 SQLite 流水中的 `cached_tokens`，并提供账号邮箱到账号名称的智能映射。
- 格式化层：`TokenFormatUtils` 提供 `friendlyModelName`（模型短名）和 `cacheRateTier`（命中率色彩分级：高效翠绿、正常青蓝、偏低暖琥珀、0 冷启灰）。
- 表现层：`TokenZoneView` 移除 `summaryBar` 和表头，用纤细微型状态栏与 3 栏网格（左身份、中用量分布、右性能时间）填充横向空间，高度压减 40% 消除下巴空黑与中间空洞。

**技术栈：** Swift 6 / SwiftUI / SQLite3 / XCTest / macOS 14+

**规格文档：** `docs/superpowers/prototypes/2026-09-17-token-page-redesign.html`（经用户审批的高保真原型）

## 全局约束

- 严格遵循 Apple Native Studio 工业级设计规范（`StudioColor`、`StudioMaterial`、`monospacedDigit()`）。
- 单元测试运行必须带编译参数 `CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` 避开环境证书限制。
- 应用构建输出严格部署至系统 `/Applications/NotchEvery.app`。

---

### 任务 1：纯函数格式化与色彩分级逻辑（TDD）

**文件：**
- 修改：`NotchDrop/TokenFormatUtils.swift`
- 测试：`Tests/TokenFormatUtilsTests.swift`

- [x] **步骤 1：在 `Tests/TokenFormatUtilsTests.swift` 编写失败的测试**
- [x] **步骤 2：运行测试验证失败**
- [x] **步骤 3：在 `NotchDrop/TokenFormatUtils.swift` 编写实现**
- [x] **步骤 4：运行测试验证通过**
- [x] **步骤 5：Commit**

---

### 任务 2：数据管道透传 `cachedTokens` 与账号别名映射

**文件：**
- 修改：`NotchDrop/TokenZoneView.swift`
- 修改：`NotchDrop/UsageStore.swift`
- 修改：`Tests/AntigravityProxyStoreTests.swift`

- [x] **步骤 1：更新 `TokenRequest` 数据结构**
- [x] **步骤 2：在 `UsageStore.swift` 中解析并填充 `cachedTokens`**
- [x] **步骤 3：运行数据层测试验证**
- [x] **步骤 4：Commit**

---

### 任务 3：`TokenZoneView` 视图层 3 栏平衡设计与去重重构

**文件：**
- 修改：`NotchDrop/TokenZoneView.swift`

- [ ] **步骤 1：移除冗余 `summaryBar` 与旧 `header`**
- [ ] **步骤 2：构建微型状态条 `liveBar`**
- [ ] **步骤 3：重构 `TokenRowView` 为 3 栏平衡布局**
- [ ] **步骤 4：运行项目构建验证编译无误**
- [ ] **步骤 5：Commit**

---

### 任务 4：全量回归测试、安装部署与真机视觉验收

**文件：**
- 修改：无代码变更（部署与验证）

- [ ] **步骤 1：运行全量单元测试**
- [ ] **步骤 2：构建 Release 归档并安装到 `/Applications/NotchEvery.app`**
- [ ] **步骤 3：请用户真机过目第二页视觉效果**
