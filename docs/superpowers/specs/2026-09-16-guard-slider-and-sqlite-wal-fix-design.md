# 守护控制可视化滑动量程、SQLite WAL 只读修复与判定日志脱敏规格

- **日期**：2026-09-16
- **分类**：架构与交互重构（Architectural & UX）
- **覆盖范围**：
  1. `UsageStore.swift`：修复 SQLite WAL 模式下只读查询导致的 `unable to open database file (14)`，使首页与第 2 页正常显示
  2. `GuardControlZoneView.swift`：将生硬的 `dBm` 步进器重构为具有空间物理感、实时信号光标的「可视化双轨滑动标尺（Visual Range Slider）」
  3. `GuardControlZoneView.swift` & `DecisionLogger`：修复 `Messages 未授权` 假失败一直常驻的问题，判定卡片仅反映真实锁屏/解锁判定，并增加系统设置自动化权限一键跳转

---

## 1. 根本原因与解决方案

### 1.1 SQLite WAL 只读失败修复
- **根因**：`AntigravityProxyStore` 使用 `SQLITE_OPEN_READONLY` 打开 WAL 模式数据库时，SQLite 会尝试写共享内存文件（`-shm` / `-wal`），触发系统级错误 14。
- **方案**：使用 URI 文件协议 `file://<path>?immutable=1`，并配合打开标志 `SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_FULLMUTEX`。
  - `immutable=1` 明确通知 SQLite 客户端无需锁定或检查写日志，允许零锁表直接并发读取。

### 1.2 `Messages 未授权：请授权` 常驻报错修复
- **根因**：后台推送 iMessage 的异步通道报错被写入 `DecisionLogger`（`category: .system, reason: .iMessageFailed`）。控制台的 `recentJudgementCard` 盲目读取 `events.last`，导致一条旧的通知告警长期伪装成当前守护锁屏判定失败。
- **方案**：
  1. `recentJudgementCard` 过滤：仅展示核心锁屏与解锁决策事件（`category == .unlock || category == .user || (category == .system && reason != .iMessageFailed)`）。
  2. 如果存在待授权系统权限（如自动化权限），单独在卡片下方以带有操作按钮的温馨提示条展示，并附带一键直达按钮：`去设置开启授权`（调用系统设置自动化偏好面板）。

### 1.3 空间测距可视化滑动标尺（Visual Signal Slider）
- **根因**：纯负数 `dBm` 加上加减号按钮非常反人类，用户不知道加是离电脑近还是远。
- **方案设计**：
  将原本的两个按钮卡片合并为一个贯穿式的 **「信号与空间距离标尺（Distance & Signal Slider）」**：
  - **量程范围**：`-95 dBm`（最远，约 5~8 米）到 `-40 dBm`（最近，贴身 0.3 米）。
  - **视觉分段**：
    - 🔴 **离开锁屏区**（例如 `< -85 dBm`，左侧，红色微弱发光）
    - ⚪ **防抖缓冲区**（中间滞后区，防止边界震荡）
    - 🟢 **靠近解锁区**（例如 `> -60 dBm`，右侧，翡翠绿发光）
  - **实时信号光标（Live Signal Radar Needle）**：
    - 当手表处于连接态且有实时 RSSI 时（例如当前截图中的 `-43 dBm`），在标尺对应位置展示一个带脉冲光晕的小白点，直观显示：「你当前正处于解锁区深处，离电脑很近」。
  - **双滑块调节（Dual Sliders）**：
    - 提供两条精致的紧凑滑动条（或分段拖拽把手），分别调节「解锁距离（靠近）」与「锁屏距离（离开）」，拖拽时实时显示直观文案（如 `贴近 0.5米`、`离座 2.5米`）。
    - 自动维持 `解锁阈值 >= 锁屏阈值 + 3` 的安全间隔。

---

## 2. 验证与回归保证
1. 单元测试验证：
   - 验证 SQLite WAL URI 只读模式在并发状态下的稳定读取。
   - 验证 `recentJudgementCard` 对 `iMessageFailed` 过滤逻辑。
   - 验证滑动条数值互锁与安全距离限制。
2. 真实真机验收：
   - 首页底栏看板立即刷出真实的千级请求数、Tokens 与平均耗时。
   - 第二页展示真实请求列表。
   - 第三页控制台展示带有实时信号小白点的可视化量程滑动条，红字报错消失。
