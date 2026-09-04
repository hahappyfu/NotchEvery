# NotchEvery 四节拍动效重构设计

> 参考源：NotchNook 视频（PixPin_2026-09-04_16-25-20.mp4，71 帧逐帧分析）+ Gemini 视频感知规格。二者冲突处以视频实测为准。
> 回退策略：每个节拍独立 commit，任一节拍用户审核不过，revert 该节拍单独重做，不影响其他节拍。

## 0. 范围与不变量

**只动时间轴与材质，不动布局与形状架构。**

不变量（全程锁死）：
- 展开尺寸 `notchOpenedSize = 600 × 160`（现状）
- 外壳形状：现有 `notchBackgroundMaskGroup` 反角遮罩组产生的运行形态（现状，不做肩部下切、不做新矩形）
- 内容布局：额度卡（196pt）+ 托盘并排（现状）
- 状态机：`Status {closed/opened/popping}` + `OpenReason` + `ContentType`（现状）
- hover 展开防抖、拖拽吸纳、Option 删除等既有交互逻辑（现状）

## 1. 材质基底（节拍 0）

外壳底色从 `glassCard`（Material 在浅色壁纸下提亮透底）换为深色沉浸玻璃：

```
Color(red: 0.08, green: 0.08, blue: 0.09).opacity(0.75)   // rgba(20,20,24,0.75) 等效
+ .ultraThinMaterial                                       // 高斯模糊层
+ 内描边 white.opacity(0.08) × 1pt                          // 高光
+ 投影 0 20 40 -10 rgba(0,0,0,0.6)（展开态）
```

实现：`Glass.swift` 新增 `darkGlassCard(cornerRadius:)` 修饰符，旧 `glassCard` 保留不动。`NotchView` 的 `glassNotchBackground` 换用之。内卡片（额度卡/托盘）**本轮不动**。

## 2. 四节拍时间轴

### 节拍 1 · 预备拍（180ms）

- 触发：hover 进入热区（`.hover` openReason）。**点击与拖拽触发不加菊花**（点击是确定性意图，拖拽讲究即时反馈）。
- 表现：刘海热区视觉微扩（180→190 等效 +5pt），刘海内中心偏下出现 **8 叶放射菊花**（每叶 1.5×4pt 圆角条，逐叶 -22.5° 旋转 + 0.8s 渐隐循环），转 180ms。
- 新增 ViewModel 状态：`Status` 保持三态不动，菊花可见性由新 `@Published var preloading: Bool` 驱动（`notchOpen(.hover)` 时先置 true，180ms 后置 false 并进 `.opened`）。

### 节拍 2 · 弹性生长（380ms 主时长）

- 参数真值：`spring(response: 0.32, dampingFraction: 0.86)`（对应 Framer stiffness 380 / damping 30 / mass 0.8 的换算结果，轻微过冲回稳）。
- 替换点：`vm.animation` 用于外壳展开的部分换成新 `openAnimation` 常量；内容 transition 与外壳共用同一动画。
- 预备微扩：展开起始帧外壳先 +5pt 再弹开（合并进 spring 首帧，无需独立动画）。

### 节拍 3 · 内容分批入场

外壳起势后内容才开始进，三个批次：

| 批次 | 延迟 | 动效 |
|------|------|------|
| 顶栏 | +120ms | opacity 0→1 + translateY(-6→0)，200ms |
| 额度卡 | +240ms | 同上 + scale 0.92→1 |
| 托盘 | +360ms | 同上 |

实现：`NotchView` body 的内容 Group 拆出 `contentEntryDelay(_:)` 修饰符（按批次给 delay），`reduceMotion` 环境下全部跳过直接显示。

### 节拍 4 · 收起（双曲线逆向）

- 内容先退：150ms，仅 opacity（不位移，退场利落）。
- +80ms 后外壳收：320ms，`spring(response: 0.24, dampingFraction: 1.0)`（无过冲快退，对应 Gemini 收起曲线的实测等效）。
- 收起完成后摄像头区域回到刘海态（现状遮罩自动覆盖，无需额外处理）。
- 鼠标移出 300ms 延迟收起（现状 150ms，对齐 NotchNook 缓冲上调至 300ms）。

## 3. 文件改动清单

| 文件 | 改动 | 节拍 |
|------|------|------|
| `Glass.swift` | 新增 `darkGlassCard`（+15 行） | 0 |
| `NotchView.swift` | `glassNotchBackground` 换材质；内容 Group 拆分批入场 | 0, 3 |
| `NotchViewModel.swift` | 新增 `preloading` 发布属性 + `openAnimation`/`closeAnimation` 常量 + hover 收起延迟 150→300ms | 1, 2, 4 |
| `NotchViewModel+Events.swift` | `mouseLocation` sink 中 `scheduleHoverClose` 路径不变，`notchOpen(.hover)` 走预备拍 | 1 |
| `SpinnerView.swift`（新建） | 8 叶放射菊花（~40 行） | 1 |

## 4. 验收标准

1. hover 展开能看到菊花→外壳弹开→内容分批进的完整节奏；点击/拖拽展开无菊花。
2. 浅色壁纸下外壳深色不透底，无摄像头黑斑。
3. 展开带轻微过冲回稳，收起无过冲、内容先退外壳后收。
4. reduceMotion 下全部直接显示无动画。
5. 每节拍独立 commit，可单独 revert。
