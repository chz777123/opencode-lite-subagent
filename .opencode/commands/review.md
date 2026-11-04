---
description: 用 reviewer 子 agent 审查当前代码改动
agent: reviewer
subagent: true
---
审查当前改动。范围说明：$ARGUMENTS

当前变更文件：

!`git status --short 2>/dev/null || echo "(not a git repository)"`

先跑 `git status --short -- <scope>` 找未跟踪新文件，再 `git diff -- <scope>` 精读。若工作区在本次派单前就有未提交改动，只审与目标相关的 hunk。

输出 P0-P3 Findings 与末行 `verdict:`。
