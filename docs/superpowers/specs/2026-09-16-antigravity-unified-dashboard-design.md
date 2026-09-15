# Antigravity 全景总览与双数据源适配器架构设计规格

- **日期**：2026-09-16
- **分类**：架构级（Architectural）重塑
- **范围**：
  1. 首页底栏重塑：移除冗余的「守护卡（GuardCardView）」，新建「Antigravity 反代今日看板（AntigravityProxyCardView）」
  2. 第二页双数据源适配器（Dual-Source Adapter）：
     - 现有 `cc-switch` 逻辑原样保留为备用数据源（`CCSwitchUsageStore`）
     - 新增 `AntigravityProxyStore`，直读 `~/.antigravity_tools/proxy_logs.db` 与 `token_stats.db`
     - 门面路由提供极简切换开关，随时可一键无缝切回 `cc-switch`
  3. `TokenZoneView.swift` 适配：保持既有模板不变，数据层透明注入真实毫秒耗时、HTTP 状态与账号信息
  4. 守护控制台纯净化：第一页不再包含守护组件，守护控制全部收敛于第三页

---

## 1. 架构目标与设计原则

1. **心智统一**：
   - 首页上半部分为 5 账号 3D 舞台，下半部分替换为「Antigravity 本地反代今日看板」。
   - 第二页默认展示 Antigravity Tools 反代的真实毫秒级调用流水。
   - 第三页为独立的锁屏/解锁守护控制台。
2. **可逆与防弃用设计（Dual-Source Architecture）**：
   - 严格保留现有的 `cc-switch` 查询逻辑与模型映射，不作硬删除。
   - 采用数据源适配器模式，通过单一路由开关 `UsageDataSourceKind` 决定底层取自 `Antigravity Tools` 还是 `cc-switch`。后续若停用反代，仅需修改一行开关即可瞬间复原。

---

## 2. 模块 1：首页下半部——Antigravity 反代今日看板 (`AntigravityProxyCardView.swift`)

### 2.1 替换点
在 `NotchDrop/OverviewPageView.swift` 中：
- 移除 `GuardCardView(vm: vm)`
- 接入 `AntigravityProxyCardView(vm: vm)`

### 2.2 视觉与指标设计 (Apple Native Studio Bento)
宽度固定 360pt，内边距与上方 3D 舞台卡片保持一致（横向 18pt，纵向 12pt）。

- **顶栏 (Header)**：
  - 左侧：`🟢 本地反代 · 8045 端口`（读取配置中 `proxy.port`）
  - 右侧：`今日看板` 标签
- **主体三列 Bento 微卡 (Metric Tiles)**：
  1. **今日请求**：今日总请求数（例如 `1,284 次`）。
  2. **今日消耗**：今日总 Token（例如 `142.6M`）。
  3. **平均延迟**：今日请求平均响应耗时（例如 `280ms`）。
- **底栏微信息 (Footer)**：
  - 左侧：今日缓存命中 Token 数与命中率（例如 `缓存命中率 42.8%`）。
  - 右侧：最近一次请求时间或状态。

---

## 3. 模块 2：第二页双数据源适配器模式

### 3.1 数据源抽象与路由开关
在 `NotchDrop/UsageStore.swift`（或新建适配门面）中定义：

```swift
public enum UsageDataSourceKind: String, Codable, CaseIterable {
    case antigravityTools // 主力：Antigravity Tools 本地反代原生日志
    case ccSwitch         // 备用：旧版 cc-switch 本地日志
}
```

门面根据当前激活的数据源自动分发：
- **`AntigravityProxyStore`**：
  - 读取 `~/.antigravity_tools/proxy_logs.db`（`request_logs` 表）
  - 提供真实毫秒级响应时间、HTTP 状态码、账号邮箱绑定
  - SQLite 只读锁安全模式（`PRAGMA query_only = ON;`）
- **`CCSwitchUsageStore`**：
  - 完整封存保留既有的 `~/.cc-switch/cc-switch.db` 读取逻辑与测试用例，一字不删。

---

## 4. 模块 3：UI 展示层与耳朵联动

1. **灵动岛左耳**：
   - 当使用 `antigravityTools` 时显示：`本地反代 :8045`
   - 当切回 `ccSwitch` 时显示：旧版供应商名称（如 `claude-desktop`）
2. **灵动岛右耳**：
   - 统一展示今日请求总次数 `请求次数 \(count)`
3. **第二页列表视图**：
   - 完全复用 `TokenZoneView.swift` 现成的 UI 结构模板，零学习成本，平滑过渡。

---

## 5. 验证与回归保证

1. 全量 420 项现有单元测试无回归通过。
2. 为 `AntigravityProxyStore` 编写专属测试，验证 SQLite 只读读取性能（< 10ms）与聚合准确性。
3. 验证数据源一键切换机制有效性。
