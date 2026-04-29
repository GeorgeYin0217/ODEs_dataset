# ODEs_dataset

这个仓库的主入口是 `docs/`，不是 `README`。

对人类读者来说，通常只需要阅读 `docs/`。该目录已经包含这个项目的整体目标、工程结构、规范、任务记录与说明文档；`README` 只保留最小导航。

## 推荐用法

建议直接让代码 AGENT 接管这个仓库，例如 Codex、Claude Code 等，而不是手动从源码层逐个文件阅读。

对 AGENT，推荐入口顺序如下：

1. `docs/project guide/`
2. `docs/spec/`
3. `docs/notes/code explanation/`
4. `docs/notes/file explanation/`
5. `docs/notes/mathematical explanation/`

这个顺序的含义是：

- `project guide` 提供项目目标、工程路线和顶层约束；
- `spec` 提供当前项目登记、对象注册和任务清单；
- 三个 `explanation` 文件夹共同覆盖项目的具体说明、生成文件解释和数学背景。

## 给人类读者的最小说明

如果你只是想理解这个项目，请直接从 `docs/` 开始，不需要先读源码。

如果你只是想让 AGENT 工作，请把上面的入口顺序明确告诉它；通常不需要再单独为它解释仓库结构。

## 仓库定位

`ODEs_dataset` 是一个 ODE 测试数据集工程仓库。它的完整说明已经放在 `docs/` 中维护，这里不再重复展开。
