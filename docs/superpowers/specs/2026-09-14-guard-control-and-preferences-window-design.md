# NotchEvery 第 2 期：守护控制台与独立设置大窗口设计规格

- 日期：2026-09-14
- 状态：已批准
- 目标：
  1. 将刘海第三页从冗长易读性差的诊断时间线重构为精致高效的「守护控制台」（`GuardControlZoneView.swift`）。
  2. 新增标准 macOS 侧边栏样式的独立「偏好设置」大窗口（`PreferencesWindow.swift`），彻底解决 FUnlock 核心配置缺失问题。

---

## 1. 第三页重构：守护控制台（`GuardControlZoneView.swift`）

### 1.1 尺寸与样式规范
- 宽度：固定 360pt，内边距 `horizontal: 18, vertical: 12`，背景采用 `Color.white.opacity(0.06)`，圆角 12pt。与首页概览卡片保持完全相同的视觉韵律。
- 耳区（Ears）适配：
  - 左耳：`守护控制 · [当前状态]`（如 `守护中` / `空跑观察`）。
  - 右耳：当前绑定的蓝牙设备与信号（如 `Apple Watch · -62 dBm`）。

### 1.2 页面结构与功能
1. **Header 状态行**：
   - 绿色/橙色状态小圆点 + 标题 `守护控制`。
   - 右侧显示设备名与实时 RSSI，若未绑定则显示 `尚未绑定设备`。
2. **高频行为开关（2×2 网格布局）**：
   - 接近唤醒屏幕 (`wakeOnProximity`，默认关)
   - 离开立即熄屏 (`sleepDisplay`，默认开)
   - 离开暂停音乐 (`pauseItunes`，默认关)
   - 键鼠活动保护 (`lockOnIdle`，默认开)
   - 绑定的配置读写均走 `ConfigStore.shared.defaults`。
3. **RSSI 阈值快捷调节**：
   - 解锁阈值（`unlockRSSI`）步进/滑块与数值回显（如 `-65 dBm`）。
   - 锁定阈值（`lockRSSI`）步进/滑块与数值回显（如 `-85 dBm`）。
   - 自动防倒挂保护：锁定阈值必须小于等于解锁阈值。
4. **精简最近判定卡片**：
   - 只展示最近 1~2 条判定（如 `⏱️ 16:15 🟢 解锁成功 (Apple Watch 距离 -58dBm)`），不再全量渲染长列表。
   - 失败事件标红并展示具体原因（如 `密码错误` / `键盘活动中`）。
5. **快捷操作底栏**：
   - `🎯 测距校准向导`：弹出 sheet 运行 5 步采样向导。
   - `⚙️ 偏好设置...`：打开独立侧边栏设置大窗口，并可关闭刘海。

---

## 2. 独立偏好设置大窗口（`PreferencesWindowController.swift`）

### 2.1 窗口规格
- 风格：标准 macOS 桌面级偏好设置窗口，尺寸约 680×460，支持居中显示、独立移动、记忆窗口位置。
- 架构：`NSWindowController` + `NavigationSplitView`，左侧侧边栏导航，右侧动态切换 Tab 详情。
- 入口：
  - 第三页底部 `⚙️ 偏好设置...` 按钮。
  - 右键菜单（`NotchMenuView`）的 `Settings` 按钮统一唤起该窗口。

### 2.2 侧边栏与 Tab 详情划分
1. **通用（General）**：
   - 开机自启 (`LaunchAtLogin.Toggle`)
   - 语言选择（跟随系统 / 简体中文 / English 等）
   - 触觉反馈开关 (`hapticFeedback`)
   - 文件暂存保留时长设置
2. **解锁（Unlock）**：
   - 接近唤醒屏幕 (`wakeOnProximity`)
   - 仅唤醒不解锁 (`wakeWithoutUnlocking`)
   - 使用屏幕保护替代黑屏 (`screensaver`)
   - 密码状态确认与重新录入按钮
3. **锁定（Lock）**：
   - 离开立即熄屏 (`sleepDisplay`)
   - 离开暂停媒体播放 (`pauseItunes`)
   - 键鼠活动防误锁 (`lockOnIdle`)
4. **通知与告警（Notifications）**：
   - iMessage 异常告警总开关 (`iMessageNotify`)
   - 收件人手机号/邮箱输入框与即时校验
   - 自动化权限授权状态回显
   - `发送测试通知` 按钮与即时发送结果反馈
5. **测距与校准（Calibration）**：
   - 5 步步进式空间校准向导（靠近坐下采样 -> 离开工位采样 -> 自动计算最佳解锁与锁屏阈值 -> 应用到配置）。
6. **诊断日志（Diagnostics）**：
   - 完整的时间线记录，支持按分类过滤（全部 / 解锁 / 锁屏 / 拦截 / 系统）。
   - 一键清空日志与一键导出/复制日志。
