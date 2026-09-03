# NotchEvery

把 MacBook 的刘海变成状态栏：OpenCode Go 额度一眼可见，文件随手暂存。

[简体中文 🇨🇳](./Resources/i18n/zh-Hans/README.md)

## 👀 这是什么

- **额度卡**：5h 大环 + 周/月小行 + 重置倒计时，鼠标划过刘海即展开查看（30 秒自动刷新）
- **文件暂存**：拖文件到刘海存起来，可配置保留时长，点击打开，Option + 点击删除
- **AirDrop**：从菜单一键发送
- **玻璃质感**：Liquid Glass / Material 自适应明暗外观

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
  -derivedDataPath /tmp/NotchDrop-build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

cp -R /tmp/NotchDrop-build/Build/Products/Release/NotchDrop.app ~/Applications/
open ~/Applications/NotchDrop.app
```

说明：

- **Release**：优化构建，可直接日常使用
- **自签名**：ad-hoc 签名，不需要 Apple Developer 账号
- 首次启动 macOS 可能弹安全提示：右键 `NotchDrop.app` → 打开 → 确认，之后正常启动

### 开发

```bash
open NotchDrop.xcodeproj
```

⌘R 构建运行。注意 Xcode target 名仍为 `NotchDrop`（历史原因），显示名与 Bundle ID 已是 NotchEvery。

## ⌨️ 用法速查

| 动作 | 效果 |
|------|------|
| 鼠标划过刘海 | 展开面板（额度 + 文件） |
| 鼠标移开 | 自动收起 |
| 拖文件到刘海 | 暂存 |
| 点击 `...` | 菜单（退出 / 设置 / 清空 / AirDrop） |
| 按住 Option 点击 × | 删除文件 |

设置里可调：语言、开机自启、触觉反馈、文件保留时长。

## 🧑‍⚖️ License

[MIT License](./LICENSE)

Fork 自 [NotchDrop](https://github.com/Lakr233/NotchDrop)，已私有化独立演进。致谢 [NotchNook](https://lo.cafe/notchnook) 的最初灵感。

---

Copyright © 2026 hahappyfu. All Rights Reserved.
