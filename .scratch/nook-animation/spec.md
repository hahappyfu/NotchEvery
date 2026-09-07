Status: ready-for-agent

## Problem Statement

刘海面板的动画还是老一套弹簧加缩放，展开生硬、切换靠方向滑入，用户对照 Nook 录屏后认为不好看，要求整套动画语言向 Nook 对齐：选项卡滑动胶囊、切换内容模糊淡入、面板跟随内容胀缩。

## Solution

以功能区类型变更这一个接缝为单一动画事务，一次变更同时驱动三处：顶栏选项卡黑胶囊滑动、内容区模糊淡入淡出、面板高度胀缩。选项卡可点且与触控板手势、键盘双向联动。展开收起弹簧与入场延迟重调。验收以真机手感为准。

## User Stories

1. As a user, I want to click a tab in the header tab bar, so that I can jump to that zone with the pill sliding to it.
2. As a user, I want to swipe left or right on the trackpad, so that the tab pill follows the zone change.
3. As a user, I want the outgoing zone content to blur and fade out on switch, so that the transition feels soft instead of sliding away.
4. As a user, I want the incoming zone content to fade in from blur with a slight scale-up, so that it appears to settle into place.
5. As a user, I want the panel height to grow or shrink to fit each zone with animation, so that switching feels like inflation rather than a fixed box swapping content.
6. As a user, I want the panel width to stay fixed across zones, so that layout stays stable.
7. As a user, I want the overview zone to keep its current size, so that quota and tray layout does not move.
8. As a user, I want the notch panel to grow out of the notch on open, so that expansion feels rooted rather than dropping in.
9. As a user, I want header and content to enter in stagger after the panel starts growing, so that motion has a readable order.
10. As a user, I want closing to be quick with no overshoot, so that dismissal feels decisive.
11. As a user, I want reduced-motion settings to bypass transitions and show content directly, so that the UI stays accessible.
12. As a user, I want tab titles localized, so that the tab bar reads correctly in my language.

## Implementation Decisions

- 单一接缝：功能区类型变更是唯一的动画事务触发点，胶囊滑动、内容过渡、面板尺寸三处挂同一事务，不各自另起事务。
- 选项卡条与标题（已合并）：分段控件加滑动胶囊效果，标题三键已本地化；顶栏居左接入，点选经由已有直跳接口，防双切标记继续有效。
- 内容过渡：方向滑入过渡删除，换成可动画的模糊淡入修饰符过渡，出现与消失不对称（消失快退）。
- 分区尺寸：宽锁定，分区高度查表，概览高度锁定；面板 frame 与已打开区域几何跟随当前区；被替代的固定尺寸常量删除，不留孤儿。
- 展开收起：两条弹簧以起点值重调，允许按手感微调一轮（只改数字，不换曲线类型）；顶栏与内容入场延迟收紧；虚影、拖放、守卫、手势解析逻辑不动。
- 手势与键盘联动保持：触控板滑动、鼠标横滚、键盘左右键继续驱动同一类型变更，胶囊自动跟随。

## Testing Decisions

- 只测外部行为：分区高度表覆盖全部区、概览尺寸锁定、标题键去重；过渡与弹簧只做构建验证加真机手感，不做数值断言。
- 测试沿用仓库 Tests 目录的 XCTest 风格；工程暂无测试 target，用例随目标现状执行，构建命令以 scheme 姿势为准。
- 真机手感清单（点选滑动、手势联动、模糊无闪烁、胀缩跟手、展开生长、提示、右键菜单）由验收者在真机逐项确认。

## Out of Scope

- 面板整体长宽比例向 Nook 调整（宽与概览尺寸锁定不动）。
- 弹簧参数之外的动画体系重写；后续苹果风顺滑打磨单独立项。
- 测试 target 搭建；跨手势小幅累积超时、浮层消失动画、圆点尺寸等已延后项。
- 虚影舌头形态、拖放行为、右键菜单改动。

## Further Notes

- 参考材料为本地 Nook 录屏逐帧结论：刘海小黑舌长成面板、选项卡黑胶囊滑动、切换内容模糊、面板跟随胀缩。
- 胶囊灰黑取舍留给手感验收时定。
- 详细文件级步骤见计划文档（历史记录，非执行依据）。
