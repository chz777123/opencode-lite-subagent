# 本地轻量 Sub-Agent 流程

> 基于 OpenCode V2 原生 agent / skill / command 的派单协议。零自建运行时：没有 MCP server、没有 ACP 桥、没有数据库、没有守护进程。
>
> 本目录**不再**承载旧的 Codex→OpenCode ACP 插件（已归档，见文末「历史」）。

---

## 1. 设计取舍

| 维度 | 选择 | 理由 |
|---|---|---|
| 运行时 | 用 OpenCode 原生 child session | `mode: subagent` 自带独立上下文、独立权限、独立步数上限 |
| 状态 | 文件 + git | 不引入数据库和租约 |
| 编排 | 主 agent（build）自己编排 | 不额外造一个 orchestrator agent，避免多一层上下文开销 |
| 子 agent 数量 | 5 个，按需启用 | 角色越多，选择成本越高 |
| 协议载体 | 1 个 skill | 按需加载，不常驻父会话 |

核心原则：**子 agent 负责产出，主 agent 负责判定。** 唯一不可省的两件事是回执末行的 `verdict:` 和父 agent 亲自复跑验收。

---

## 2. 文件清单

配置根目录：`~/.config/opencode`

| # | 路径 | 动作 | 作用 |
|---|---|---|---|
| 1 | `AGENTS.md` | 追加 5 行 | 派单前加载 `delegate` skill 的指针 |
| 2 | `opencode.json` | 追加 5 条权限 | 授权门与高危命令拦截 |
| 3 | `agents/scout.md` | 新建 | 只读侦察 |
| 4 | `agents/worker.md` | 新建 | 受控实现 |
| 5 | `agents/reviewer.md` | 新建 | 对抗式审查 |
| 6 | `agents/oracle.md` | 新建 | 方向第二意见（低频） |
| 7 | `agents/evidence-auditor.md` | 新建 | 证据审计（低频） |
| 8 | `commands/scout.md` | 新建 | `/scout` 快捷入口 |
| 9 | `commands/review.md` | 新建 | `/review` 快捷入口 |
| 10 | `skills/delegate/SKILL.md` | 新建 | 派单协议本体 |

项目级副本（可选，用于绕开命令懒加载）：`.opencode/commands/{scout,review}.md`

> **`opencode.json` 含真实 apiKey，已在 `.gitignore` 中排除，永不入库。** 权限改动需人工核对，见 §5。

### 版本控制

`~/.config/opencode` 是本地 git 仓库：

```
7944fd4  baseline: config before subagent v2-lite
526379c  feat: subagent v2-lite — 5 agents, delegate skill, 2 commands, 5 permission rules
a1cdade  fix: worker 补测试命令白名单；scout/worker/reviewer 支持 git -C
```

`.gitignore` 排除：`opencode.json`、`cli.json`、`service.json`、`auth.json`、`.env*`、`*.bak-*`、`*.backup`、`*.before-*`。

备份文件：`opencode.json.bak-20261105-003617`、`AGENTS.md.bak-20261105-003617`。

---

## 3. 五个角色

| 角色 | 触发条件 | 写权限 | steps | 回执终态词 |
|---|---|---|---|---|
| `scout` | 位置未知、跨 ≥3 文件 | 无 | 16 | `located / partial / not-found` |
| `worker` | 跨 ≥3 文件或 ≥30 行、需求已收敛 | 有（scope.write 内） | 50 | `done / partial / blocked` |
| `reviewer` | 碰公共 API / 迁移 / 鉴权 / 并发 | 无（可跑测试） | 24 | `ship / fix-first / block` |
| `oracle` | 方案代价高、方向没底 | 无 | 12 | `proceed / change-course / stop` |
| `evidence-auditor` | 结论依赖外部资料 | 无（含 web 只读） | 16 | `pass / fail` |

`oracle` 与 `evidence-auditor` 是低频角色。若两周内零使用，直接删掉对应文件——按模型绑定约束，它们本就不该在没配便宜模型时存在。

### 模型绑定

- `scout` / `evidence-auditor` **应当**显式配便宜模型；未配时继承父会话模型，成本会偏高
- `reviewer` 建议与 `worker` 异构，消除同源盲区
- 只有 `worker` 可以留空继承父会话模型

当前五个角色的 `model` 均为注释状态（继承父会话），先跑通流程，再按需绑定。

---

## 4. 派单流程

```
门控 → TaskCard → 脏净检查 → 派单 → 回执 → 宿主验收 → 续接/交付
```

### 4.1 门控表

| 信号 | 动作 |
|---|---|
| 位置已知、≤2 文件且 <30 行 | **不派**，自己改 |
| 位置未知、跨 ≥3 文件 | `scout` ×1（多条独立线索可 2~3 并行） |
| 方案代价高 / 方向没底 | 先 `oracle`，拿到 `proceed` 再动工 |
| 改动跨 ≥3 文件或 ≥30 行 | `worker` ×1（同工作区同时只允许 1 个） |
| 碰公共 API / 迁移 / 鉴权 / 并发 | `worker` 验收后必须 `reviewer` |
| 结论依赖外部资料 | `evidence-auditor` |
| 需求有歧义 | **不派**，先问用户 |

### 4.2 TaskCard

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

**严禁**把聊天历史或 diff 原文粘进 brief。给 reviewer 传 `scope` 让它自己 `git diff`；给 oracle / auditor 传文件路径。

### 4.3 派单前唯一一次检查

```sh
git status --porcelain -- <scope.write>
```

- **输出为空（干净）** → 可自动回滚：`git checkout -- <scope.write 文件>`，再删掉 `git status` 里 `??` 且在 `scope.write` 下的新文件
- **输出非空（脏）** → **禁止自动回滚**，只能人工 `/undo` 或逐 hunk 确认
- 本会话最近 3 步内已跑过 `git status` 且这些文件干净 → 免检

### 4.4 宿主验收（父 agent 亲自做）

1. `verdict: blocked` → 停止流转，回答 `open` 里的问题
2. 复跑 `acceptance`，确认真实 `exit 0`
3. `git status --short -- <scope.write>` 看新增文件（`git diff` 看不到 untracked）
4. `git diff -- <scope.write>` 精读，确认没越界改别的文件
5. 抽查 1 条子 agent 给的 `path:line`

### 4.5 续接与熔断

- 第 1 次修复**必须**用原 `worker` 的 `sessionID` 续接，只发具体报错或 P0/P1 项
- 续接会**重置** steps 配额，不继承上一轮已用量
- 第 2 次仍不过 → 停止，按 §4.3 回滚（脏则交人）
- `blocked` 不重试：回答它的问题，或改 brief 重派

---

## 5. 权限与边界

### 5.1 全局（`opencode.json`）

```jsonc
{ "action": "subagent", "resource": "*", "effect": "ask"  },
{ "action": "shell", "resource": "git push *",         "effect": "deny" },
{ "action": "shell", "resource": "git clean *",        "effect": "deny" },
{ "action": "shell", "resource": "git reset --hard *", "effect": "ask"  },
{ "action": "shell", "resource": "rm -rf *",           "effect": "deny" }
```

`subagent: ask` 是授权门。首次批准某角色时选 **always**，OpenCode 会按 agent ID 落一条持久 allow。

### 5.2 子 agent（deny-by-default）

每个角色都以 `{ action: "*", resource: "*", effect: deny }` 开头，再逐条放行。**这条兜底同时拦住了 `external_directory`**，因此子 agent 被限制在项目内——跨项目任务必须由主 agent 自己做，或显式放行 `external_directory`。

`worker` 额外封禁：`edit` 的 `.git/**`、`.github/**`、`.opencode/**`、`*.env*`；`shell` 的 `git commit` / `git push` / `git clean` / `git reset --hard` / `rm -rf`。

### 5.3 授权门

允许派单的三种情况：

1. 用户明确要求
2. 用户敲了 `/scout` 或 `/review`（命令即授权，不经过 `subagent: ask`）
3. 先说明「派谁、干什么」并获同意

**任务复杂不是授权。**

### 5.4 并发

- 只读角色 ≤3 并行；`worker` 同工作区同时 1 个
- `worker` 运行期间不派 `scout` 读 `scope.write` 内的文件（会读到中间态）
- `reviewer` 审查期间不改同一批文件

---

## 6. 冒烟记录（2026-11-05 实测）

用临时 git 仓库（含一个「refresh 无重试」的 bug 与两条失败测试）跑通全链路：

| # | 角色 | 输入 | 结果 |
|---|---|---|---|
| 1 | scout | 项目外路径 | `not-found`：被 `external_directory` 边界拦住，如实报告未编造 |
| 2 | scout | 项目内定位 refresh | `located`：`path:line` 全部正确 |
| 3 | worker | 加两次重试 | `done`：宿主复跑 exit 0、diff 未越界、抽查行号正确 |
| 4 | worker | `sessionID` 续接 | `done`：同一会话内加 `MAX_ATTEMPTS`，未重读上下文 |
| 5 | reviewer | 审未提交改动 | `ship`：1×P2 + 4×P3，抓到 async reject 路径零覆盖 |
| 6 | oracle | 判断方向 | `stop`：指出该改动已完成，继续是无用功 |
| 7 | evidence-auditor | 审计 2 条 claim | `fail`：抓到行号错 1 行 + 一条被来源反驳 |

回滚演练：`git checkout -- src/session.js` → 测试回到 2 fail；恢复 → 2 pass。

### 实测发现并修掉的三处

| 问题 | 现象 | 处理 |
|---|---|---|
| `* → deny` 连带拦 `external_directory` | scout 读不了项目外路径 | **保留**，子 agent 限制在项目内是正确的最小权限 |
| `worker` 缺测试命令白名单 | 跑 `node --test` 会弹 ask | 补 npm/pnpm/bun/node/pytest/go/cargo 的 allow |
| 缺 `git -C` 变体 | monorepo/worktree 里前缀不匹配 | 给 scout/worker/reviewer 补 `git -C * {status,diff,log,show}*` |

---

## 7. 回滚

```sh
cd ~/.config/opencode

# 1. 还原配置
mv opencode.json.bak-20261105-003617 opencode.json
mv AGENTS.md.bak-20261105-003617 AGENTS.md

# 2. 删掉新增文件（都是新建的，删除安全）
rm -f agents/{scout,worker,reviewer,oracle,evidence-auditor}.md
rm -rf skills/delegate commands/scout.md commands/review.md

# 3. 整体回到 baseline（opencode.json 不在版本控制，仍需手动还原）
git reset --hard 7944fd4
```

代码侧回滚见 §4.3，**不要用 `git reset --hard`**，也不要在工作区本来就脏时用 `git checkout --`。

---

## 8. 已知限制

| # | 限制 | 影响 | 现状 |
|---|---|---|---|
| 1 | 子会话没有父历史 | `sessionID` 续接的是子会话自己的历史，不等于 fork | 靠 TaskCard 指针移交补上下文 |
| 2 | 无结构化输出校验 | 只能靠固定回执 + `verdict:` 终态行 + 宿主复跑 | 已接受 |
| 3 | 无 per-child worktree | `worktree_create` 没有「启动进 worktree」入口 | 靠单写者 + 精确回滚 |
| 4 | Snapshots 不是 API | 只能人工 `/undo`，不能程序化精确回滚 | 当人工兜底 |
| 5 | 命令按 location 懒加载 | 某个目录首次查询 `/api/command` 返回 0 条，客户端可能缓存空菜单 | 重启服务或放项目级 `.opencode/commands/` |

---

## 9. 历史

旧的 Codex→OpenCode ACP 插件（MCP server + ACP 适配器 + dashboard + 文件租约）已归档：
<https://github.com/chz777123/codex-opencode-subagent-plugin>

该方案的基础设施比协议本身重，已放弃。当前方案只保留协议，运行全部交给 OpenCode 原生能力。
