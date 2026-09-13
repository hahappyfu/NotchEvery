// NotchEvery-Bridging-Header.h
// 桥接 C 底层：锁屏/关屏/唤醒（由 FUnlock 的 FUnlock-Bridging-Header.h 拆分而来，工单 01）。
// 只暴露 lowlevel.h；MediaRemote.h 不再引入（Q13 摘除私有框架）。

#import "lowlevel.h"
