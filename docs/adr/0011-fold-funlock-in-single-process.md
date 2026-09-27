# FUnlock 并入 NotchEvery：单进程嵌入，刘海为唯一入口

> **Status: Superseded** — 2026-09 起 FUnlock 子系统整体移除，见 docs/superpowers/plans/2026-09-17-remove-funlock-module.md 与本审计计划 docs/superpowers/plans/2026-09-27-audit-fixes.md。

把旧软件 FUnlock（macOS 菜单栏 BLE 自动锁屏/解锁，41 文件 / 9270 行）并入 NotchEvery：BLE 扫描、信号判定、状态机、密码注入**全部跑在 `NotchEvery.app` 进程内**，FUnlock 不再作为独立 app 存在；交互入口只有刘海面板，**不新增菜单栏图标**（NotchEvery 本来也没有，无 `NSStatusItem`，`AppDelegate.swift:31` 只设 `.accessory`）。守护状态平时不显示，异常时主动通报——因为解锁失败的那一刻屏幕正被锁屏占据、刘海面板整个不可见，**「常驻显示状态」在最需要它的时刻恰恰失效**，有效通道只剩 iMessage 推送（推到手表）与解锁后在刘海里回显失败原因。旧仓库冻结归档。

## Considered Options

- 保留 FUnlock 作无 UI 的后台登录项 agent，刘海只当控制面板：本质仍是两个 app，与「不想装两个 app」的动机直接冲突，否决。
- 先双进程共存过渡、再逐步收编：把上述代价分期支付，且两个 app 会同时判 BLE 距离并注入密码、互相打架，否决。
- 保留一个极简菜单栏状态图标：与「刘海为唯一入口」冲突，且其价值被锁屏遮挡这一硬约束抵消，否决。

## Consequences

- **TCC 权限不可继承**：权限按签名身份记账，NotchEvery（team `964G86XT2P`）与 FUnlock（`JJYCS98SHK`）不同团队，合并后须重新授予辅助功能、蓝牙与完全磁盘访问（实测证据：本机无 FDA 时读 `/Library/Bluetooth` 返回 EPERM）。
- **Keychain 密码拿不过来**：FUnlock 条目的 `kSecAttrService` 就是 `Bundle.main.bundleIdentifier`（`SecurityService.swift:34`），换 app 后系统层面不可达，必须重录一次；可达性为 `AfterFirstUnlockThisDeviceOnly`。
- **崩溃隔离消失**：BLE 与注入链同进程，一侧崩溃带走另一侧。这是为「少一个 app」明确接受的代价。
- 配置**无需迁移代码即可沿用**：FUnlock 的 `ConfigStore` 用固定 suite 域 `com.fuhahah.Funlock.config`（与 bundle id 解耦，注释即为「覆盖安装后配置不丢失」）；但本次仍决定换命名空间，写一次性迁移搬运。
- 登录项沿用 NotchEvery 既有的 `LaunchAtLogin` 依赖，不需要把 FUnlock 的 `SMAppService` 那套重写一遍。
