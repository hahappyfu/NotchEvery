# 移植策略：测试整组随行、注入链原样、空跑验证后再接管

> **Status: Superseded** — 2026-09 起 FUnlock 子系统整体移除，见 docs/superpowers/plans/2026-09-17-remove-funlock-module.md 与本审计计划 docs/superpowers/plans/2026-09-27-audit-fixes.md。

搬运 FUnlock 时**把有测试覆盖的被搬模块，其用例一律随行当回归网**（386 例中约 318 例；扣除测已砍模块的 52 例与测额度卡的 `QuotaTests` 16 例），**不趁机重构密码注入链**——三级降级注入（`SystemInteractionService.swift:110-155,199-251`）、`CGEvent` 合成 ⌃⌘Q 锁屏（`lowlevel.c:48-102`）、`IORegistry` 私有属性（靠近唤醒，`wakeOnProximity = 1` 在用）一律原样保留。理由是**移植本身就是最大的风险源**：把逻辑从菜单栏壳里剥出来塞进刘海壳，`FUnManager`（929 行）与状态机一定会被碰，而这批用例是唯一的保险。接管方式为**空跑优先**：搬进来的自动执行默认关闭，先只跑 BLE 扫描与状态判定、用诊断页确认「该解时判成解、该锁时判成锁」，再打开真执行、重授权、重录密码、卸载 FUnlock。

## Considered Options

- 借移植机会把注入链收敛成一条主路径并补测试：收益是更干净，代价是动一条每天在干活、失败还静默降级的锁屏控制链；本次动机是「少一个 app」而非「重做 FUnlock」，否决。
- 私有 API 先隔离成可开关的实验特性：会制造两套行为（开关开/关表现不同），解锁这种安全敏感行为最忌状态分叉。只在验证出 `hardened-process` 与私有框架确实冲突时再单独开一刀——目前该冲突仍是待验证项，不预先劈。
- 直接接管（搬完就开、当天切换）：它的失败模式是「你以为锁上了，其实没锁」，不会立刻咬人而是安静地攒着；且 `CGEvent` 真实注入、TCC 授权行为、真实 BLE 距离判定**全部没有测试覆盖**，无法自动化验证。

## Consequences

- **私有 API 面收缩一处**：摘除私有 `MediaRemote`。其唯一用途是「锁屏暂停播放、解锁后恢复播放」（`SystemInteractionService.swift:305-322`），而本机 FUnlock 配置里 `pauseItunes` 键根本不存在（`LockSettingsView.swift:5` 的 `@AppStorage` 默认 `false`）——**从未开启，摘除零行为损失**。随之去掉 `MediaRemote.framework` 链接与 `SYSTEM_FRAMEWORK_SEARCH_PATHS = $(SYSTEM_LIBRARY_DIR)/PrivateFrameworks`（`project.pbxproj:99,793-796`），同时消掉「`hardened-process` 与私有框架冲突」这一待验证风险中的一项。残留私有依赖：`IORegistry` 私有属性与 `SACLockScreenImmediate`。
- 验收标准含「连续 3 天不打开 FUnlock」与「卸载 FUnlock 后仍能完成完整的离开锁定 → 靠近解锁循环」。
- 移植期**不允许删除任何搬入模块的既有用例**；新写的用例只增不减。测已砍模块的用例类不随行（它们测的东西在新 app 里不存在）。

> **修订（2026-09-13，`/to-spec` 接缝确认）**：为 `SystemInteractionService` **新增注入接缝**——把系统副作用边界（锁屏 / 唤醒 / 密码注入与验证 / 告警 / 通知 / 屏幕状态查询）抽成一个协议，`FUnManager` 改为经构造注入接收实现，`SystemInteractionService` 作为 live 实现继续存在。因此上文「不趁机重构」的范围收窄为：**不重构注入实现本身**——三级降级注入、`CGEvent` 合成 ⌃⌘Q、`IORegistry` 私有属性的实现一字不动，改动的只是调用点从硬编码单例（15+ 处）换成可替换引用。
>
> 收益：`FUnManager` 的「真实执行」链路（注入 → 双验证 → 失败降级 → 告警）终于可以用假的系统副作用实现走完，这是原本没有测试覆盖的那一段。代价：动的是 ADR 里刚刚圈为禁区的那个文件，且 929 行的 `FUnManager` 调用点全要改。**既有的 386 个用例恰好成为这次重构本身的回归网**——它们必须在不修改断言的前提下继续全绿，这是本次接缝改动的验收条件。

