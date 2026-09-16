# NotchEvery

> 把 MacBook 的刘海变成专属于 AI 开发者的灵动岛：Antigravity 账号池额度与本地反代数据一眼可见，近场蓝牙智能离座锁屏与靠近秒级唤醒解锁。

[简体中文 🇨🇳](./README.md)

---

## ✨ 核心特性

### 1. 🏝️ 初绽开（Peek 悬停态）双模态感知
鼠标无需点击，悬停划过刘海正中即轻盈微展开：
- **AI 核心看板**：实时显示今日 Token 消耗与调用次数（紧凑单位换算如 `125.2M · 2.4k 次`，杜绝生硬裸长数字）。
- **近场守护感知**：右侧同步显示 Apple Watch 实时信号与安全距离（`⌚️ -50 dBm · 安全` / `🛡️ 空跑` / `⏸️ 已停用`）。
- **零延迟轻量渲染**：剥离过桥菊花旋转层与循环重绘，悬停响应极其跟手。

### 2. 📊 三大独立全景工作区分页
滑动切页或点击底部平滑指示器，三页统一 520pt 舒展等宽过渡，彻底消除尺寸跳变：
- **第一页（Antigravity 原生仪表盘）**：
  * **账号池卡**：4 账号微型环状额度 + 当前活跃高亮 + 每日重置倒计时（本地直读零延迟）。
  * **本地反代看板**：直连本地代理 SQLite 日志，展示今日请求吞吐、首字延迟、活跃模型排行与上下文缓存命中率。
- **第二页（Token 吞吐与请求审计）**：
  * 请求明细时序瀑布流、模型消耗占比饼图/环形图与缓存效率分析。
- **第三页（守护控制台 Guard Control Zone）**：
  * **2×2 高频行为开关**：接近自动点亮屏幕、熄灭显示器、防误锁与远程异常推送。
  * **空间测距可视化滑动条（GuardSignalRangeSlider）**：双滑块自由调节靠近解锁（如 `-60 dBm`）与离席锁屏（如 `-80 dBm`），搭载实时雷达指针光标。
  * **判定事件卡片**：过滤非决策噪音，展示最近一条核心锁屏/解锁决策。

### 3. ⌚️ 完整原汁原味的 FUnlock 近场安全守护
- **蓝牙设备扫描与一键配对**：支持实时发现附近的 Apple Watch / iPhone 并一键配对绑定或解绑。
- **钥匙串密码托管**：通过 macOS Keychain 加密保存锁屏凭据，靠近时由状态机驱动自动唤醒并安全键入解锁。
- **智能防误触**：键盘鼠标活跃监听（敲击或滑动时强制不锁屏）、快速离开斜率判定与休眠节能协同。
- **6 步空间交互式测距校准向导**：根据工位实际物理环境引导实测，自动推荐最佳解锁与离席阈值。
- **iMessage 远程异常告警**：在密码连续错误或疑似入侵时向手机发送警报通知。

### 4. ⚙️ 原生 macOS System Settings 风格独立偏好设置
告别割裂与重复，收拢右键轻量操作，以 3 大高内聚 Tab 重构偏好大窗口：
- **通用 (`General`)**：开机自启、触觉振动反馈、多语言切换、反代数据源运行状态。
- **近场守护 (`Proximity Guard`)**：设备发现配对选择器、运行模式（真执行/空跑）、钥匙串密码托管、阈值滑块与向导、触发策略。
- **安全与日志 (`Security & Diagnostics`)**：iMessage 告警测试与配置、决策审计时序流水线（支持分类筛选与历史搜索）。

---

## 🔌 数据来源说明

NotchEvery 严格保护本地隐私，所有数据均读取自本地环境：
- **账号池**：读取 `~/.antigravity_tools/accounts.json` 或 `~/.antigravity_tools/accounts/*.json`。
- **反代日志**：通过 `immutable=1` 零锁并发模式直读 `~/.antigravity_tools/logs.db`。
- **蓝牙近场**：基于 macOS CoreBluetooth 进行本地设备广播扫描，不上传任何隐私。

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
目前包含 54 个测试套件，**439 项单元测试 100% 通过**，严密覆盖几何度量、格式化管道、决策状态机、设备配对与防抖逻辑。

---

## 📁 核心架构

```
NotchDrop/
├── NotchView.swift             # 纯黑刘海黑岛外壳与 SmoothNotchShape 贝塞尔曲面
├── NotchRootView.swift         # 顶部耳区（Ears）与三区分页路由外壳
├── OverviewPageView.swift      # 第一页：Antigravity 账号卡 + 本地反代今日看板
├── TokenZoneView.swift         # 第二页：Token 消耗明细与缓存分析
├── GuardControlZoneView.swift  # 第三页：520pt 守护控制台与空间测距滑动条
├── PreferencesWindow.swift     # 原生 macOS 风格三大 Tab 独立偏好设置窗口
├── FUn.swift / FUnManager.swift # 蓝牙扫描、近场距离测算与锁屏解锁状态机
├── GuardStore.swift            # 守护门面（单例状态机与持久化配置）
├── TokenFormatUtils.swift      # 人类易读紧凑单位格式化纯函数工具
└── DesignSystem.swift          # StudioColor、StudioMaterial 工业级设计系统
```
