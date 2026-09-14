# NotchEvery

把 MacBook 的刘海变成状态栏：OpenCode Go 额度一眼可见，文件随手暂存。

[简体中文 🇨🇳](./Resources/i18n/zh-Hans/README.md)

## 👀 这是什么

- **额度卡**：5h 大环 + 周/月小行 + 重置倒计时，鼠标划过刘海即展开查看（30 秒自动刷新）
- **蓝牙守护与自动解锁**：监测 Apple Watch / BLE 设备信号，离席自动锁屏、靠近自动解锁唤醒（集成 FUnlock 守护能力与诊断时间线）
- **Token 监控**：调用请求列表与缓存命中率 KPI 展示
- **文件暂存**：拖文件到刘海存起来，可配置保留时长，点击打开，Option + 点击删除
- **AirDrop**：从菜单一键发送

## 🔌 额度数据来源

额度卡读取本机 bridge 缓存，不碰网络：

```
~/.clawd/opencode-go-bridge-cache.json
```

没有这个文件时额度卡显示 `--%` 占位，文件暂存不受影响。

## 🔨 从源码构建

### 前提

- macOS + Xcode（含 Command Line Tools）

### 构建并安装到应用文件夹

```bash
git clone https://github.com/hahappyfu/NotchEvery.git
cd NotchEvery

xcodebuild -project NotchDrop.xcodeproj \
  -scheme NotchDrop \
  -configuration Release \
  -derivedDataPath /tmp/NotchEvery-build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

cp -R /tmp/NotchEvery-build/Build/Products/Release/NotchEvery.app ~/Applications/
open ~/Applications/NotchEvery.app
```

说明：

- **Release**：优化构建，可直接日常使用
- **自签名**：ad-hoc 签名，不需要 Apple Developer 账号
- 首次启动 macOS 可能弹安全提示：右键 `NotchEvery.app` → 打开 → 确认，之后正常启动

### 开发

```bash
open NotchDrop.xcodeproj
```

⌘R 构建运行。注意 Xcode target 名仍为 `NotchDrop`（历史原因），显示名与 Bundle ID 已是 NotchEvery。

### 测试

```bash
xcodebuild test -project NotchDrop.xcodeproj -scheme NotchDrop \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

覆盖分区几何契约、额度归一化、手势解析、路径消毒等 27 个用例（2026-09-08 起接入 `NotchEveryTests` target）。

## 📁 项目结构

- `NotchDrop/`：应用源码（target 名沿用历史命名）
  - `NotchView/NotchContentView/NotchTabBar`：面板与选项卡（结构上钉死不动，见 `docs/adr/0001`）
  - `NotchViewModel(+Events)`：状态机与事件接线
  - `TrayDrop*`：文件暂存；`Quota*`：额度卡
- `Tests/`：XCTest 单元测试
- `docs/`：ADR 与调研笔记；`CONTEXT.md`：领域词汇表
- `.scratch/`：工单跟踪（每功能一目录）

## ⌨️ 用法速查

| 动作 | 效果 |
|------|------|
| 鼠标划过刘海 | 虚影展开，点击后完整展开面板 |
| 点选项卡（概览｜设置） | 切换分区，选项卡位置钉死不动 |
| 触控板横扫 / 鼠标横滚 / ←→ 方向键 | 循环切换分区 |
| 点击面板顶栏（刘海高度那条） | 切到下一分区 |
| 拖文件到刘海 | 暂存 |
| Option + 点击 × | 删除文件 |

设置里可调：语言、开机自启、触觉反馈、文件保留时长。

## 🧑‍⚖️ License

[MIT License](./LICENSE)

Fork 自 [NotchDrop](https://github.com/Lakr233/NotchDrop)，已私有化独立演进。致谢 [NotchNook](https://lo.cafe/notchnook) 的最初灵感。

---

Copyright © 2026 hahappyfu. All Rights Reserved.
