# 01: 切换内容模糊淡入过渡

**What to build:** 切换功能区时，旧内容模糊淡出、新内容从模糊中淡入并轻微放大落位；删除原来的方向滑入过渡。用户看到的不再是左右滑动的内容，而是柔和的模糊交接。

**Blocked by:** None (can start immediately).

**Status:** resolved (commits eace451 feat + 173e5fd fix; review clean; visual → user acceptance)

- [ ] 三个区全部使用模糊淡入过渡，方向滑入无残留
- [ ] 出现比消失慢，消失快退，无闪烁
- [ ] 减少动态效果开启时直接显示内容
- [ ] 构建通过（scheme 姿势，全新缓存）
