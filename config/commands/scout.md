---
description: 用 scout 子 agent 快速定位代码入口与数据流
agent: scout
subagent: true
---
定位以下目标并返回 path:line 索引、数据流与风险点：

$ARGUMENTS

若上面目标为空，改为输出当前目录两层内的结构概览，并提示用户补充具体目标。
