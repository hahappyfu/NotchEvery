# 设置分区删除：设置走 Popover，不占分页

`ContentType.settings` 是残留死状态：点开是空白面板（`NotchRootView` 里只有 `.settings: Color.clear` 占位分支），而设置真正的入口早已是齿轮 Popover（右键菜单 "Settings" 与 Popover 齿轮）。我们决定彻底删除 `.settings` case 及其三条死路径（`tabTitleKey`/`tabIconName`/`showSettings()`、`zonePanelHeight[.settings]`、TEMP-DIAG 开机探针），右键菜单与齿轮改为直接弹设置 Popover（`showSettings = true`）。

## Considered Options

- 保留分区并补内容：被否——与已定案的"设置走 Popover"冲突，两套入口并存。
- 保留 case 只修空白：被否——死状态，修了也是第二套设置 UI。

## Consequences

- 高度表剩两页（`.normal: 165, .token: 224`）；`hostedViewHeight = max()` 自动收窄到 224，顶对齐（ADR-0002）不受影响——CGWindowList 实测窗口 y=0 贴顶、h=165 跟随概览分区。
- 新增分区只需在高度表加条目；设置相关改动只走 Popover（`NotchSettingsView`）。
