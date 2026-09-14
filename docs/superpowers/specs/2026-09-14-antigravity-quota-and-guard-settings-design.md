# NotchEvery 首页配额换源与守护控制台重构设计规格

- 日期：2026-09-14
- 状态：已批准（头脑风暴完成）
- 实施分期：
  - 第 1 期：首页配额卡换源（OpenCodeGo → Antigravity Tools 4账号池仪表盘）
  - 第 2 期：第三页改造（诊断页 → 守护控制台）与 FUnlock 独立偏好设置窗口接入

---

## 第 1 期：首页配额卡换源（Antigravity Tools 账号池）

### 1. 目标与背景
用户已转向使用 Gemini 进行反代，旧的 `OpenCodeGo` 配额监控（读取 `~/.clawd/opencode-go-bridge-cache.json`）已过时。由于 Gemini 体系中所有模型共享同账号的统一额度池，用户需要直观监控本地 4 个 Gemini 反代账号的额度健康状态、轮换就绪情况及重置倒计时。

### 2. 数据源与模型设计
- **配置与账号文件**：
  - 主配置索引：`~/.antigravity_tools/accounts.json`
    - `current_account_id`: 当前活跃账号 UUID。
    - `accounts`: 账号概要列表（ID、邮箱、显示名称、启用/禁用状态等）。
  - 详情数据：`~/.antigravity_tools/accounts/<account_id>.json`
    - `name` / `email`
    - `proxy_disabled`: 是否禁用反代。
    - `quota.models`: 读取首个 Gemini 模型（或遍历取最小百分比/最早重置时间），提取：
      - `percentage`: 剩余额度百分比（Int，0~100）。
      - `reset_time`: ISO8601 格式的重置时间戳（如 `2026-09-14T12:27:35Z`）。
- **新建 `AntigravityStore.swift`**：
  - 职责：单例 ObservableObject，提供本地文件轮询读取与内存去重。
  - 轮询间隔：15 秒（仅在刘海面板展开状态轮询，收起时自动暂停）。
  - 数据模型 `AntigravityAccount`:
    - `id`: String
    - `name`: String
    - `email`: String
    - `isCurrent`: Bool
    - `isDisabled`: Bool
    - `geminiPercentage`: Int
    - `resetTime`: Date?
    - `resetCountdownText`: String（如 "1h24m"、"已就绪"）

### 3. UI 设计（`AntigravityAccountsCardView.swift`）
- 宽度：固定 360pt，内边距 horizontal 18, vertical 12，与下方的 `GuardCardView` 保持完全一致的视觉韵律与背景（`Color.white.opacity(0.06)`）。
- 顶部 Header：
  - 绿色圆点 + 标题 `Antigravity 账号池`
  - 右侧副标题：`当前: 傅哈哈`（高亮显示当前活跃账号）
- 中间 4 账号横向分布（HStack + Spacer）：
  - 每个账号垂直布局：
    - 账号名（小字，单行省略）
    - 小型圆形进度环（直径约 36pt，线宽 4pt，带百分比数字）
      - 色彩规范：`percentage >= 70`: 绿色；`30 <= percentage < 70`: 橙色；`< 30`: 红色；禁用/冷冻：半透明灰色。
      - 当前活跃账号：环周带有轻微微光外框或强调点。
    - 底部重置标签：重置倒计时（如 `2h15m`）或 `就绪`（100% 满血时显示就绪）。

### 4. 替换与清理
- 彻底移除废弃的 OpenCodeGo 相关文件：
  - `NotchDrop/QuotaSnapshot.swift`
  - `NotchDrop/QuotaStore.swift`
  - `NotchDrop/QuotaCardView.swift`
- 更新 `NotchDrop/OverviewPageView.swift`，使用 `AntigravityAccountsCardView`。
- 新增单元测试 `Tests/AntigravityStoreTests.swift` 覆盖 JSON 解析与倒计时格式化逻辑。

---

## 第 2 期：第三页守护控制台与独立设置窗口（后续执行）

### 1. 目标与背景
上次将 FUnlock 合并入 NotchEvery 后，第三页诊断时间线（`DiagZoneView`）信息密集且不易阅读；同时 FUnlock 的诸多核心配置（如接近自动唤醒、离开熄屏、暂停音乐、键鼠防误锁、RSSI 阈值调节、iMessage 报警配置、多预设）在刘海中无处设置。

### 2. 第三页改造（`GuardControlZoneView.swift`）
- 替换现有第三页 `DiagZoneView` 为「守护控制台」：
  - 4 项常用锁屏行为开关：
    - 接近唤醒屏幕 (`wakeOnProximity`)
    - 离开暂停音乐 (`pauseItunes`)
    - 离开立即熄屏 (`sleepDisplay`)
    - 键鼠活动防误锁 (`lockOnIdle`)
  - 2 个快捷滑块/步进调节：
    - 解锁信号阈值 (`unlockRSSI`)
    - 锁屏信号阈值 (`lockRSSI`)
  - 2 个重要操作入口按钮：
    - `启动距离校准向导`
    - `打开完整设置窗口...`

### 3. 独立偏好设置窗口
- 在菜单栏 / 右键菜单 / 第三页底部提供入口，打开标准 macOS 多 Tab 偏好设置窗口：
  - Tab 1：常规设置（开机启动、语言、触觉反馈）
  - Tab 2：解锁设置（唤醒机制、屏幕保护、iMessage 通知与报警配置）
  - Tab 3：锁定设置（显示器休眠、媒体控制、延迟防误锁）
  - Tab 4：距离与校准（向导式 RSSI 校准）
  - Tab 5：配置预设（家 / 办公室 / 会议模式切换与管理）
  - Tab 6：诊断日志（带分类过滤 chip、可复制导出的完整历史日志）
