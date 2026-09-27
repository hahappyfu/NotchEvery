# NotchEvery

> 把 MacBook 的刘海变成专属于 AI 开发者的灵动岛：Antigravity 账号池额度与本地反代数据一眼可见。

[简体中文 🇨🇳](./README.md)

---

## ✨ 核心特性

### 1. 🏝️ 初绽开（Peek 悬停态）双模态感知
鼠标无需点击，悬停划过刘海正中即轻盈微展开：
- **AI 核心看板**：实时显示今日 Token 消耗与调用次数（紧凑单位换算如 `125.2M · 2.4k 次`，杜绝生硬裸长数字）。
- **零延迟轻量渲染**：剥离过桥菊花旋转层与循环重绘，悬停响应极其跟手。

### 2. 📊 两大独立全景工作区分页
滑动切页或点击底部平滑指示器，两页统一 520pt 舒展等宽过渡，彻底消除尺寸跳变：
- **第一页（Antigravity 原生仪表盘）**：
  * **账号池卡**：4 账号微型环状额度 + 当前活跃高亮 + 每日重置倒计时（本地直读零延迟）。
  * **本地反代看板**：直连本地代理 SQLite 日志，展示今日请求吞吐、首字延迟、活跃模型排行与上下文缓存命中率。
- **第二页（Token 吞吐与请求审计）**：
  * 请求明细时序瀑布流、模型消耗占比饼图/环形图与缓存效率分析。

### 3. ⚙️ 原生 macOS System Settings 风格独立偏好设置
告别割裂与重复，收拢右键轻量操作的独立偏好设置窗口：
- **通用 (`General`)**：开机自启、触觉振动反馈、多语言切换、反代数据源运行状态。

---

## 🔌 数据来源说明

NotchEvery 严格保护本地隐私，所有数据均读取自本地环境：
- **账号池**：读取 `~/.antigravity_tools/accounts.json` 或 `~/.antigravity_tools/accounts/*.json`。
- **反代日志**：通过 `immutable=1` 零锁并发模式直读 `~/.antigravity_tools/logs.db`。

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
目前包含 22 个测试套件，**188 项单元测试 100% 通过**，严密覆盖几何度量、格式化管道与防抖逻辑。

---

## 📁 核心架构

```
NotchDrop/
├── NotchView.swift             # 纯黑刘海黑岛外壳与 SmoothNotchShape 贝塞尔曲面
├── NotchRootView.swift         # 顶部耳区（Ears）与三区分页路由外壳
├── OverviewPageView.swift      # 第一页：Antigravity 账号卡 + 本地反代今日看板
├── TokenZoneView.swift         # 第二页：Token 消耗明细与缓存分析
├── PreferencesWindow.swift     # 原生 macOS 风格独立偏好设置窗口
├── TokenFormatUtils.swift      # 人类易读紧凑单位格式化纯函数工具
└── DesignSystem.swift          # StudioColor、StudioMaterial 工业级设计系统
```
