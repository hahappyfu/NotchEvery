# NotchEvery

> 把 MacBook 的刘海变成专属于 AI 开发者的灵动岛：Antigravity 账号池额度、本地反代统计与 Qoder 网关状态一眼可见。

[简体中文 🇨🇳](./README.md)

---

## ✨ 核心特性

### 1. 🏝️ 虚影 Peek：悬停即浮现
鼠标无需点击，悬停划过刘海正中即浮现虚影岛体：
- **热区覆盖整个 Peek 岛体**（含下方文案区），点击即展开完整面板。
- **Peek 提示条**实时显示「今日 tokens · 调用次数 · ⚡️ 缓存命中率」（紧凑单位换算如 `125.2M · 2.4k 次`，杜绝生硬裸长数字）。
- **零延迟轻量渲染**：弹簧驱动岛体变形，稳态下数据轮询不再触发重绘，悬停响应极其跟手。

### 2. 📊 三页工作区面板
滑动切页或点击底部平滑指示器切换：
- **第一页（概览）**：
  * **账号池卡**：多账号微型环状额度 + 当前活跃高亮 + 每日重置倒计时（本地直读零延迟）。
  * **本地反代今日看板**：直连本地反代统计，展示今日请求吞吐、Token 消耗与上下文缓存命中率。
- **第二页（Token）**：UsageStore 读取 Antigravity Tools 本地反代（`:8045`）真实统计——入/出 Token 明细、最近请求流水与模型/账号缓存率分级。
- **第三页（网关）**：Qoder 网关管理——反代用量、账号额度探测、缓存命中与今日签到（默认显示）。

展开面板后耳区常驻信息：**左耳显示当前供应商，右耳显示今日调用次数**。

### 3. ⚙️ 右键快捷菜单 + 原生偏好设置窗口
右键刘海弹出快捷菜单（退出 / 设置）；「设置」打开原生 macOS System Settings 风格独立窗口：
- **通用 (`General`)**：开机自启、触觉反馈、多语言切换、版本信息。

---

## 🔌 数据来源说明

NotchEvery 严格保护本地隐私，所有数据均读取自本地环境：
- **账号池**：读取 `~/.antigravity_tools/accounts.json` 索引与 `~/.antigravity_tools/accounts/*.json` 单账号文件。
- **反代统计**：通过 `immutable=1` 只读模式直读 `~/.antigravity_tools/proxy_logs.db`（本地反代 :8045 日志）。
- **Qoder 网关**：本地 Go 网关（`Vendor/qodercn-gateway`）随 app 打包分发，由 `QoderGatewayManager` 拉起并管理。

> **已移除的旧子系统**：FUnlock 守护、剪贴板历史、拖放文件暂存、cc-switch 双源——当前版本不再包含这些功能。

---

## 🔨 构建与安装

### 前提条件
- macOS 13.0+
- Xcode（含 Command Line Tools）

### 一键构建并安装到 Applications
```bash
git clone https://github.com/hahappyfu/NotchEvery.git
cd NotchEvery

# 编译 Release 并复制到应用程序目录
xcodebuild -project NotchDrop.xcodeproj \
  -scheme NotchDrop \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

rm -rf /Applications/NotchEvery.app ~/Applications/NotchEvery.app
cp -R build/Build/Products/Release/NotchEvery.app /Applications/
open /Applications/NotchEvery.app
```

> **提示**：首次启动若遇到 macOS Gatekeeper 安全提示，可在系统设置中允许或右键点击应用选择“打开”。

### 运行单元测试套件
```bash
xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop CODE_SIGNING_ALLOWED=NO
```
目前包含 25 个测试文件，**201 项单元测试**，严密覆盖几何度量、格式化管道与防抖逻辑。

---

## 📁 核心架构

```
NotchDrop/
├── 窗口与生命周期
│   ├── main.swift                 # 入口
│   ├── AppDelegate.swift          # 应用生命周期与状态栏接管
│   ├── NotchWindow.swift          # 无焦点悬浮窗口
│   ├── NotchWindowController.swift
│   ├── NotchViewController.swift
│   └── AppPaths.swift             # 应用内路径
├── 核心视图
│   ├── NotchView.swift            # 纯黑刘海黑岛外壳与 SmoothNotchShape 贝塞尔曲面
│   ├── NotchRootView.swift        # 顶部耳区与三区分页路由外壳
│   ├── NotchContentView.swift     # 面板内容装配
│   ├── OverviewPageView.swift     # 第一页：账号池卡 + 本地反代今日看板
│   ├── TokenZoneView.swift        # 第二页：Token 吞吐与请求审计
│   ├── GatewayZoneView.swift      # 第三页：Qoder 网关管理
│   ├── SmoothNotchShape.swift     # 贝塞尔曲面形状
│   ├── iOSPageIndicator.swift     # 底部平滑分页指示器
│   ├── DesignSystem.swift         # StudioColor、StudioMaterial 工业级设计系统
│   ├── Share.swift / Share+View.swift
│   └── Ext+*.swift                # NSScreen/NSAlert/NSImage/URL/FileProvider 扩展
├── 状态与交互
│   ├── NotchViewModel.swift       # 岛体状态机：闲置/虚影/展开/收起
│   ├── NotchViewModel+Events.swift
│   ├── EventMonitor.swift / EventMonitors.swift  # 全局事件监听
│   ├── ScrollSwipeResolver.swift  # 滑动切页手势判定
│   ├── ZoneSizeGuard.swift        # 分区尺寸保底钳制
│   ├── IslandMetrics.swift        # 岛体几何度量
│   ├── GearHapticFeedback.swift   # 触觉反馈
│   ├── ConfigStore.swift          # 持久化配置
│   ├── PublishedPersist.swift / UnfairLock.swift / Log.swift / Language.swift
├── 数据
│   ├── AntigravityStore.swift     # 账号池轮询与归一化（~/.antigravity_tools）
│   ├── UsageStore.swift           # 反代日志统计（proxy_logs.db，immutable 只读）
│   └── TokenFormatUtils.swift     # 人类易读紧凑单位格式化纯函数工具
├── Qoder 网关
│   ├── QoderGatewayManager.swift  # 本地 Go 网关进程管理（随 app 分发）
│   ├── QoderGatewayConfig.swift / QoderStore.swift / QoderLogParser.swift
│   ├── QoderPoolCredentials.swift / QoderPoolIdMatcher.swift / QoderPoolQuotaProber.swift
│   ├── QoderPoolRingView.swift / QoderAccountNicknames.swift / QoderCampaignClaimer.swift
├── 设置
│   ├── PreferencesWindow.swift    # 原生 macOS 风格独立偏好设置窗口（单「通用」Tab）
│   ├── PreferencesWindowController.swift
│   └── NotchMenuView.swift        # 右键 Popover 快捷菜单
```

> 历史交接/调研/原型文档已归档至 [`docs/archive/`](./docs/archive/)，其内容不代表当前代码。
