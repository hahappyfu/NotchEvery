# 审计后修复计划（进行中）

> 基于 audit-2026-09-27-summary.md（16 Critical / 40 Important / 45 Minor + ponytail 精简审计待合入）
> 状态：收集决策中，ponytail 审查者跑完后定稿

## 已确认的产品决策（用户拍板）

### 决策 1：整条剪贴板链删除（2026-09-27 确认，范围=整链）
第四页 UI + ClipboardMonitor + ClipboardStore + ClipboardPaster + 相关测试 + 设置项全删。
- 理由：剪贴板第四页无价值；剪贴板历史是隐私重灾区（审计发现密码明文落盘、目录非 0700）
- 消解问题：审计 Important 剪贴板隐私链 5 条（ClipboardMonitor.swift:47-94 明文、ClipboardStore.swift:91 无 0700、ClipboardPaster.swift:95-111 paste 清空、ClipboardMonitor.swift:52-56 isInternalCopy 竞态、ClipboardStore.swift:180-189 vs 223-234 幽灵条目）+ UI Important 2 条（ClipboardZoneView.swift:224-228 3D 滚轮、:277,322-324 置顶击穿）+ Tests 相关缺口（ClipboardMonitor 文件分支、ClipboardPaster isTerminated）
- 牵连改动：
  - NotchViewModel.swift:237-241 baseZoneOrder 四页→三页（[.normal,.token,.gateway]）
  - NotchRootView.swift:133-152 四 case→三 case；ContentType.clipboard 枚举删
  - 删除文件：ClipboardZoneView.swift、ClipboardMonitor.swift、ClipboardStore.swift、ClipboardPaster.swift、ClipboardZoneView 相关（GatewayZoneView 不受影响）
  - Tests：ClipboardStoreTests / ClipboardMonitorTests / ClipboardPasterTests 及 Fixtures 相关清理
  - 设置项：PreferencesWindow/NotchSettingsView 中剪贴板相关选项（如有）
  - 文档：CONTEXT.md「分区」词条按三页写（原 R-C2 改口径）；「拖放区/展示卡」措辞同步
  - ConfigStore 里剪贴板相关 key（如有）清理解析
- 注意：删除后「横扫切页」的测试（ContentZoneSwitcherTests 等）若有 clipboard 用例需同步调整

## 已确认决策（用户拍板，2026-09-27）
1. **剪贴板整链删除**：第四页+ClipboardMonitor/Store/Paster+测试+设置项（~1,200 行 + 3 测试文件）
2. **FUnlock 十件套整链删除**：1,620 行（含 lowlevel.c/funlock、Info.plist 蓝牙描述、iMessage 通知链、PermissionGuide）；ADR-0011/0012 加 Superseded、README 清理
3. **cc-switch 分支删除**：activeSource 路由 + CCSwitchUsageStore 235 行 + .ccSwitch 分支 + 相关测试；ADR-0005 补修订注记；CONTEXT.md 数据源口径改「antigravityTools 单源」（消解 R-I1）

## 复杂度/精简清单（ponytail，net -2930 lines，已并入汇总第六节）
- delete 整文件：FUnlock 十件套 1,620 行、appleDeviceNames 221、TimingLog 60、DebugLog 50、NotchSettingsView 125、PermissionGuide 68、Glass 51、RingBuffer 56、SpinnerView 38（约 2,290 行，含 FUnlock）
- delete 文件内：CCSwitchUsageStore 235+、AntigravityProxyStore 177、ConfigStore 死 API 80、savedUSD、islandFillet、bridgeSpinning、resetTime、studioPillBadge、configDir 等（约 600 行）
- yagni：PreferencesWindow 单 tab 侧边栏 40 行、ShareType 单 case、withMutation、Guard×2（Guard 删除需权衡可测性，倾向保留）
- stdlib/shrink：DateFormatter 1 行、RingView 9→1、邮箱前缀 7 行
- **用户决策消解项**：剪贴板整链约 1,200+ 行 + 3 测试文件（另计）

## 修复路线草稿（待定稿）
- P0 用户数据/隐私/核心交互：D-C1 → W-C2 →（剪贴板链按决策 1 整体删除）→ U-C3/W-C1 方向键 → U-C1 贝塞尔 → U-C2 虚影热区 → U-C4 高度锁死 → U-C5 设置幽灵弹窗
- P1 架构决策与文档债：FUnlock 去留 → activeSource 去留 → 死代码批量删除（ponytail delete 清单，约 2,890 行）→ 文档回写（R-C2~C5 按三页+新决策改口径）→ 测试三件套（T-C1 随剪贴板/TrayDrop 决策调整）
- P2 体验与健壮性 + yagni/stdlib/shrink 精简 + Minor 批量

---

# 分步执行计划（定稿）

> 分支：audit-fixes-2026-09-27（从 main 开出，superpowers using-git-worktrees）
> 每批验证：xcodebuild test 优先；本机构建受阻（证书）时退静态核对 + grep 零引用断言

## 批次 A：纯删除（决策 1/2/3 + ponytail delete，零行为影响）
- [x] A1 剪贴板链：删 ClipboardZoneView/ClipboardMonitor/ClipboardStore/ClipboardPaster + pbxproj 引用 + Tests 3 文件 + 设置项；baseZoneOrder 四页→三页、NotchRootView 四 case→三 case、ContentType.clipboard 删；ConfigStore 剪贴板 key 清（pbxproj 结构已用 xcodebuild -list 验证）
- [x] A2 FUnlock：删十件套 + lowlevel.c/h + Bridging-Header + pbxproj 引用（-36 行）+ Info.plist 蓝牙/AppleEvents 描述 + entitlements apple-events + 相关 Tests 5 文件；ADR-0011/0012 加 Superseded、README 清理；UnfairLock 迁新文件保活（QoderPoolQuotaProber/QoderCampaignClaimer 引用未断）。新增 UnfairLock.swift，共删 18 文件（agent-a2 执行，四项验证全过）
- [x] A3 cc-switch：UsageStore 579→301 行（删 CCSwitchUsageStore 235 行/activeSource/.ccSwitch 分支/init(dbPath:)/死门面/savedUSD）；UsageStoreTests 整删（12 用例全为 cc-switch 门面测试）；AntigravityProxyStoreTests 删 1 用例保 4；ADR-0005 修订注记（agent-a3 执行）。**审计修正**：ponytail 报的「AntigravityProxyStore prod 零引用」是误报——UsageStore.refresh() 的 antigravityTools 活跃路径直接调用它，是唯一数据路径，已按任务预案保留
- [x] A4 ponytail delete 清单（agent-a4 执行）：8 整文件删除 669 行 + ConfigStore 死 API -101 行 + islandFillet/bridgeSpinning/resetTime（有读者，改用 displayResetTime）/studioPillBadge/configDir/feedVertical + yagni（PreferencesWindow 单 tab/ShareType/withMutation）+ stdlib/shrink + MockEventMonitors 迁 Tests + README 数字修正。**TEST BUILD SUCCEEDED，188 tests 0 failures**
- [x] 批次 A 提交：a9c83f4（80 文件，+1470/−5642，净删 4172 行）
- [ ] A5 TrayDrop 僵尸链决策：复活 or 删干净（待用户确认，倾向删；牵连 PreferencesWindow 托盘卡、设置保留时长、main.swift:93）

## 批次 B：行为修复（P0，每条改完需构建/真机验证）
- [x] B1 D-C1 PublishedPersist 解码失败备份（agent-b1：FileStorage.backupCorruptFile，+1 测试）
- [x] B2 W-C2 cleanExpiredFiles 补 removeFiles(of:)（agent-b2，+1 测试；**遗留发现**：removeFiles 从不删 Config/Previews/<id>.png，delete/removeAll/容量淘汰均漏预览文件，修法一行，另开工单）
- [x] B3 U-C3/W-C1 方向键接线（agent-b678 commit 5289392：vm.handleArrowKey 统一映射，+3 测试；守卫保留防误截全局按键）
- [x] B4 U-C1 SmoothNotchShape 等比钳制（agent-b4：scale=height/totalH 压缩 blendH+bRadius，大高度逐点不变，+6 测试）
- [x] B5 U-C2 虚影热区扩大（agent-b678 commit 03ca48f：NotchGeometry.peekRect/hoverActiveRect 纯函数，+3 测试；拖拽路径未影响）
- [x] B6 U-C4 切页高度完整恢复（agent-b678 commit 5315397：lastZoneSize 存取完整 CGSize，+2 测试）
- [x] B7 U-C5 设置 Popover 常驻宿主+收起重置（agent-b678 commit cb2feb4，+1 测试）
- [x] 批次 B 提交：a9c83f4 后 4 个独立 commit + 093a7dc 打包 B1/B2/B4；**201 tests 0 failures**（基线 188 + 新增 13）
- [x] 批次 B 真机验收：用户 2026-09-27 确认六场景全部正常

## 批次 C：文档回写（R-C1~C5 + 口径）
- [x] C1 CONTEXT.md：分区词条三页、删「拖放区」词条、指示器词条按 SmoothPageIndicator 实况、删过桥菊花词条、删顶栏词条、数据源改 antigravityTools 单源、耳区/展示卡措辞
- [x] C2 README 重写：特性/架构/测试三节按现状
- [x] C3 ADR 补状态：0001/0004/0006/0011/0012 Superseded；0005/0008/0009/0010 修订注记（钳制数值、SmoothNotchShape、耳区口径、cc-switch 移除）
- [x] C4 归档旧文档：NIGHT-REPORT/HANDOFF×3/PROMPT-FOR-CLAUDE/research → docs/archive/

## 批次 D：数据/UI Important 修复（P1/P2 主体）
- [ ] D1 数据层：I1 selectAccount 竞争、I3 轮转翻倍、I4 GatewayManager 线程收敛、I6 isInternalCopy（若剪贴板未删）、I11 JSONEncoder 隔离、I12 DebugLog（若未删）、M 批（URL 强解包、userQuota 路径等）
- [ ] D2 UI 层：I1 peek 文本自适应、I2 耳区宽度策略、I3 边距二次叠加、I4 Token 行溢出、I5 连扫动画竞争、I7 置顶击穿（若未删）、I8 双重动画、I9 tertiary 对比度、I10 makeKey 抢焦点
- [ ] D3 测试补齐：T-C1 补真断言（若 TrayDrop 复活）、补 I3/I7/I8 测试

## 验收
- 每批：grep 零引用断言 + 编译静态核对（构建受阻时）+ 用户真机过目（UI 改动）
- 全部完成：测试全绿、净删 ~4,000+ 行、文档与代码一致、汇总报告逐条销号
