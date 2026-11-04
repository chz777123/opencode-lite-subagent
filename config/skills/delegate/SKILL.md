---
name: Subagent Delegation
description: 派单给子 agent (scout/worker/reviewer/oracle/evidence-auditor) 的极简协议：门控、TaskCard、宿主验收、sessionID 续接与回滚边界。
---

# 派单协议

## 0. 授权门

仅在三种情况下派单：

1. 用户明确要求（「查一下」「审一下」「问问 oracle」）
2. 用户敲了 `/scout` 或 `/review` —— **命令即授权**，不经过 `subagent: ask`
3. 你先用一句话说明「派谁、干什么」并获同意

任务复杂**不是**授权。

## 1. 门控表

| 信号 | 动作 |
|---|---|
| 位置已知、≤2 文件且 <30 行 | **不派**，自己改 |
| 位置未知、跨 ≥3 文件 | `scout` ×1（多条独立线索可 2~3 并行） |
| 方案代价高 / 方向没底 | 先 `oracle`，拿到 `proceed` 再动工 |
| 改动跨 ≥3 文件或 ≥30 行 | `worker` ×1（同工作区同时只允许 1 个） |
| 碰公共 API / 迁移 / 鉴权 / 并发 | `worker` 验收后必须 `reviewer` |
| 结论依赖外部资料 | `evidence-auditor` |
| 需求有歧义 | **不派**，先问用户 |

## 2. 模型绑定（硬约束）

- `scout` / `evidence-auditor` 应当显式配便宜模型；未配时它们继承父会话模型，成本会偏高，只在必要时启用
- `reviewer` 尽量与 `worker` 异构，消除同源盲区
- 只有 `worker` 可以留空继承父会话模型

## 3. TaskCard（直接作子 agent 的 prompt）

```yaml
goal: "<一句话可验证>"
scope:
  read: ["src/auth/**", "path/to/file.ts:10-80"]
  write: ["path/to/file.ts"]        # 只读角色写 []
non_goals: ["<最便宜的防跑偏手段，别省>"]
context:
  - "path:line — 已确认的事实（背景 >30 行就存文件，只传路径）"
constraints: ["<禁改边界与兼容要求>"]
acceptance: ["<命令，约定一律期望 exit 0>"]
```

严禁粘贴聊天历史或 diff 原文。

## 4. 派单前唯一一次检查

```sh
git status --porcelain -- <scope.write>
```

- **输出为空（干净）** → 可自动回滚：`git checkout -- <scope.write 文件>`，再删掉 `git status` 里 `??` 且在 `scope.write` 下的新文件
- **输出非空（脏）** → **禁止自动回滚**。回滚只能人工 `/undo` 或逐 hunk 确认，否则会抹掉用户派单前的改动
- 本会话最近 3 步内已跑过 `git status` 且这些文件干净 → 免检

## 5. 宿主验收（父 agent 亲自做）

1. `verdict: blocked` → 停止流转，回答 `open` 里的问题
2. 复跑 `acceptance`，确认真实 `exit 0`
3. `git status --short -- <scope.write>` 看新增文件（`git diff` 看不到 untracked）
4. `git diff -- <scope.write>` 精读，确认没越界改别的文件
5. 抽查 1 条子 agent 给的 `path:line`

## 6. 续接与熔断

- 第 1 次修复**必须**用原 `worker` 的 `sessionID` 续接，只发具体报错或 P0/P1 项
- 续接会**重置** steps 配额，不会继承上一轮已用量
- 第 2 次仍不过 → 停止，按 §4 回滚（脏则交人），把两次记录交给用户
- `blocked` 不重试：回答它的问题，或改 brief 重派

## 7. steps 的语义

`steps` 是**模型步数**，不是工具调用次数；一步可以并行多个工具。50 步是防死循环的保险丝，不是成本预算。成本靠门控表 + 最多 1 次续接控制。

## 8. 并发

- 只读角色 ≤3 并行；`worker` 同工作区同时 1 个
- `worker` 运行期间，不派 `scout` 读 `scope.write` 内的文件（会读到中间态）
- `reviewer` 审查期间不改同一批文件

## 9. 账本（条件触发，不是每单）

- 本会话派单 ≤3 次：**不写**
- 第 4 次起，或本会话已发生一次 compaction：每次追加一行

```sh
printf '%s\n' "- <ISO> | <role> | <sessionID> | <verdict> | <note>" >> .opencode/runs/ledger.md
```

## 10. 反模式

- 把整段对话或 diff 贴进 brief
- 信任 `evidence` 不复跑
- 用 `git commit` 当检查点
- 工作区脏时自动 `git checkout --` 回滚
- 让 `scout` 继承贵模型
- 把「子 agent 说完成了」当完成
