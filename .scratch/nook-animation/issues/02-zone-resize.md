# 02: 面板跟随分区胀缩

**What to build:** 每个功能区有自己的面板高度，切换时面板高度胀缩到当前区的尺寸，全程动画；宽锁定不变，概览区尺寸锁定不动；鼠标守卫与拖放区域跟随新尺寸。

**Blocked by:** None (can start immediately).

**Status:** resolved (commit cb86c5a; dual review clean — 1 parked minor: notchOpenedRect naming; heights + guards → user acceptance)

- [ ] 三个区高度查表，概览区尺寸与现有保持一致
- [ ] 切换时面板高度胀缩动画无跳变，宽不变
- [ ] 面板外的滑动不切换（守卫跟随新尺寸）
- [ ] 被替代的固定尺寸常量删除，无孤儿代码
- [ ] 构建通过（scheme 姿势，全新缓存）

## Comments

- Spec 审查逐条裁定（调度器，依据代码现状）：
  - 守卫跟随：`geometry` 为无缓存计算属性，事件处理每次现算，断言成立，无需改代码；守卫行为本身走真机验收。
  - 同一事务：frame、内容、胶囊三处同为 `.animation(vm.animation, value: vm.contentType)`，同一事务成立。
  - 构建证据：实现者报告全新缓存真目录通过；合并门禁由 04 全新双构建重验，此处不再单独跑。
  - 高度估算：工单已知风险，裁剪与留白由真机验收定夺。
  - `notchOpenedRect` 旧名：Minor，记账不进循环（改名牵连多处调用点，性价比低）。
- Standards 审查待回。
