# 夜班成果报告（2026-09-08 00:00 – 02:10；09:00 晨间补遗见文末）

> 应你要求：把可用的 skills 都用了一遍，项目从头到尾能优化的都优化了。**所有改动都在工作区，未 commit**——你验收后说一声我再提交。

## 一句话总结

昨晚的「选项卡跳动」bug 已修复并升级为结构保证 + 自动守卫；顺手把**写了从未运行过的测试套件接通并跑绿（27/27）**；安全审计修掉一个「输入 0 会清空全部暂存文件」的真 bug；架构扫描产出 4 个候选重构等你挑。

## 主线：选项卡跳动修复（tab-pin）

- **根因**（三重证据：录屏像素 / 实机 AX / 等高对照实验）：面板 `.frame(600, 高度)` 垂直居中内容，各区内容自然高不同 → 选项卡随区垂直漂移 15pt，被过冲弹簧放大成"一上一下"。
- **修复**（你拍板的 A 方案）：面板重构为「29pt 固定头部槽 + 仅内容区随高度表动画」，选项卡位置由结构保证恒定。
- **守卫**：内容自然高实时测量，Debug `assert` + Release `.clipped()`。守卫上岗当天抓到三处真实脱节：概览 160 装不下额度卡（实测 105 > 72，你拍板表改 **195**）、设置区差 2pt（表改 **284**）、头部槽位实为 29 不是 28。
- **已定案文档**：`CONTEXT.md`（词汇表）、`docs/adr/0001`、`.scratch/tab-pin/`（spec + 4 工单）。

## 按你要求跑的 skills 及产出

| Skill | 产出 |
|---|---|
| `/code-review` | 双轴审查 tab-pin diff。已修：失效回退值 `?? 160`、恒真测试公式、守卫语义注释、头部槽对称守卫；跟进项落工单 03 |
| `/security-audit` | 0 高危。**当场修**：自定义保存天数输 0/负数会启动清空全部暂存（钳制下界 1 分钟）；持久化文件名回读/导出二次消毒。**待你拍板**（工单 04）：entitlements 里有 4 个非标准键待清理、暂存目录在 ~/Documents 会被 iCloud 同步 |
| `/research`（后台） | 解开两个悬案 → `docs/research/hosting-window-and-ax.md`：`sizingOptions=[]` 让窗口塌 0×0 的机制（默认值是 `.standardBounds`，我们的钳制方案正是官方推荐）；AX 枚举失效 = System Events 对快速重启进程的缓存问题 |
| `/improve-codebase-architecture` | 探索完成，**HTML 报告已生成并打开**（`$TMPDIR/architecture-review-1788803727.html`）。4 个候选：② NotchPanelState 纯状态机（Strong）③ mouseDown 决策纯函数化 ④ PanelMetrics 几何归位 ⑤ QuotaStore 注入 reader。工单在 `.scratch/codebase-health/issues/02-05` |
| `/zh-readme` | README 修正三处过时：安装命令的产物名（NotchDrop.app→NotchEvery.app）、用法表（菜单分区已消失→选项卡交互）、新增测试一节 |
| `/retro` | 环境改进沉淀进 `AGENTS.md`「Agent 环境备注」：命名陷阱、构建/测试命令、本机可用的测量通道（log stream/CGWindowList/sample）、zsh glob 坑 |

## 里程碑：测试史上第一次运行

`Tests/` 目录写了 6 个文件但**从未接进任何 target**。今晚接通了 `NotchEveryTests`（pbxproj + scheme TestAction），修掉 3 处历史遗留（旧模块名 import、Optional 断言），现在：

```
Executed 27 tests, with 0 failures
```

## 需要你做的

1. **真机点几下概览↔设置**：选项卡应该焊死原位（应用已在跑最终构建）。这是唯一没闭环的验收项——半夜 AX 测量通道抽风，视觉确认只能靠你。
2. **挑架构候选**：HTML 报告在屏幕上；选中的说编号，我按流程走 grilling → 实现。
3. **两个待拍板工单**：`.scratch/tab-pin/issues/03`（守卫升级真自然高）、`.scratch/codebase-health/issues/02-05`、`.scratch/tab-pin/issues/04`（entitlements + 存储目录迁移）。
4. **验收后提交**：工作区 15 文件改动 + 6 个新文件，`git status` 一目了然。

## 已知残留（非阻塞）

- 概览面板底边比之前低 ~35pt（额度卡不再贴底，你拍板的高度表修正的预期视觉变化）。
- 直启 `.app/Contents/MacOS` 二进制会静默退出（pid 单例/自删除监听与直接 exec 的相互作用，`open` 启动一切正常）——已写进 AGENTS.md 备注，未深挖。
- 系统 AX 通道对本机连续重启的进程会抽风（System Events 缓存），重启 System Events 或注销可恢复。

---

## 晨间补遗（09:00–09:10）：你早上报的 bug，真根因比昨晚的更深

你发来的两截图经核实来自 **/Applications 里 9月7日23:51 的旧二进制**（修复一直只在 /tmp 调试构建里，从没装进去过）——但按 systematic-debugging 对**修复版**复测（HeaderProbe 埋点实测屏幕全局坐标），发现了比昨晚更深的第二层根因：

| 状态 | 头部槽全局 y（埋点实测） |
|---|---|
| 概览落定 | +20.0 ✓ |
| 设置落定（修复前） | **−22.0**（整个面板骨架被抬到屏幕外上方） |
| 设置落定（修复后） | **+20.0** ✓ |

**机制**：窗口恒 200pt 高，设置区 SwiftUI 内容自然高 284pt 超出窗口——`NSHostingView` 对超出自身 bounds 的内容**垂直居中**，整个面板上溢 (284−200)/2 = 42pt。这发生在宿主层，SwiftUI 内部任何 `alignment: .top` 都管不到，所以昨晚的结构修复治标层没治到这一层。

**修复**（ADR-0002）：`NotchWindowController` 用自管容器接管 `window.contentView`，hosting view 约束钉死 top、高度固定为最大分区高——面板永远顶对齐、向下溢出窗口。**已验证**：概览→设置→概览来回切换 headerY 恒 20.0；27/27 测试全绿；**修复版 Release 已装入 /Applications**（旧副本备份在 /tmp/NotchEvery-app-backup-20260908.app），你现在从 Dock/启动台打开的就是修好的版本。

遗留（无害）：同进程存在 4 个 1470×33 离屏辅助窗口（onscreen=false），AppKit 内部产物，不挡点击不显示，暂不处理。`NotchView` 里的 HeaderProbe 埋点为 FIXME 标记的临时诊断，你确认修复后随下个 fix 删除。
