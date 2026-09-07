# Issue tracker: Local Markdown

此仓库的 issue 和规格说明以 markdown 文件形式存放在 `.scratch/` 中。

## 约定

- 每个功能一个目录：`.scratch/<feature-slug>/`
- 规格说明为 `.scratch/<feature-slug>/spec.md`
- 实现 issue 为每个工单一个文件，位于 `.scratch/<feature-slug>/issues/<NN>-<slug>.md`，从 `01` 开始编号，绝不使用单个合并的 tickets 文件
- triage 状态记录在每个 issue 文件顶部的 `Status:` 行（角色字符串见 `triage-labels.md`）
- 评论和对话历史追加到文件底部的 `## Comments` 标题下

## 当技能说"发布到 issue tracker"

在 `.scratch/<feature-slug>/` 下创建新文件（如果需要则创建目录）。

## 当技能说"获取相关工单"

读取引用路径处的文件。用户通常会直接传递路径或 issue 编号。

## 路径查找操作

供 `/wayfinder` 使用。**地图（map）** 是一个文件，每个工单一个**子（child）** 文件。

- **地图**：`.scratch/<effort>/map.md`（Notes / Decisions-so-far / Fog 正文）。
- **子工单**：`.scratch/<effort>/issues/NN-<slug>.md`，从 `01` 开始编号，正文中包含问题。`Type:` 行记录工单类型（`research`/`prototype`/`grilling`/`task`）；`Status:` 行记录 `claimed`/`resolved`。
- **阻塞**：顶部的 `Blocked by: NN, NN` 行。当其列出的每个文件都为 `resolved` 时，工单解除阻塞。
- **frontier**：扫描 `.scratch/<effort>/issues/` 中开放、未阻塞、未认领的文件；编号最小的优先。
- **认领**：设置 `Status: claimed` 并在任何工作之前保存。
- **解决**：在 `## Answer` 标题下追加答案，设置 `Status: resolved`，然后在 `map.md` 的 Decisions-so-far 中追加上下文指针（gist + 链接）。
