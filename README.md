# opencode-lite-subagent

轻量子 agent 套件：5 个角色 + 1 份派单协议 + 2 个快捷命令。零自建运行时，全部基于 OpenCode V2 原生的 agent / skill / command。

> 子 agent 负责产出，主 agent 负责判定。唯一不可省的两件事：回执末行的 `verdict:`，以及父 agent 亲自复跑验收。

## 包含什么

- **5 个角色**：`scout`、`worker`、`reviewer`、`oracle`、`evidence-auditor`
- **1 个 skill**：`delegate`，按需加载的派单协议（门控、TaskCard、宿主验收、续接与回滚边界）
- **2 个命令**：`/scout`、`/review`
- **5 条全局权限规则**：授权门 + 高危命令拦截
- **1 个 OpenChamber 扩展面板**：说明、安装命令、角色表

没有 MCP server、没有 ACP 桥、没有数据库、没有守护进程。

## 安装（三种方式，选一种）

### 方式 1：作为 OpenCode 插件

```sh
opencode plugin add github:chz777123/opencode-lite-subagent
```

如果客户端不接受 `github:` 简写：

```sh
opencode plugin add git+https://github.com/chz777123/opencode-lite-subagent.git
```

插件加载时：

- 把 5 个 agent 写到 `~/.config/opencode/agents/`（遵循 `XDG_CONFIG_HOME`）
- 用 `ctx.command.transform` 注册 `/scout`、`/review`
- 用 `ctx.skill.transform` 注册 `delegate`
- 已存在且被用户改过的 agent 文件不会被覆盖；安装哈希记录在 `~/.config/opencode/.opencode-lite-subagent.json`

插件**不能**修改全局权限，也不会改你的 `AGENTS.md`。需要授权门和高危命令拦截时，手动把下面的 5 条规则加入 `~/.config/opencode/opencode.json` 的 `permissions`，或改用方式 2。

### 方式 2：curl 安装器（不依赖 npm）

```sh
curl -fsSL https://raw.githubusercontent.com/chz777123/opencode-lite-subagent/main/install.sh | bash
```

安装器会：

- 复制 5 个 agent、2 个 command、1 个 skill 到 `~/.config/opencode/`
- 按 `action + resource + effect` 去重，合并 5 条权限规则
- 在 `AGENTS.md` 追加带标记的 delegate 指针
- 已存在文件默认跳过；`--force` 覆盖前先备份为 `*.bak-<时间戳>`
- 只改 `permissions` 数组，配置里的其他键原样保留

```sh
# 只看会做什么
curl -fsSL https://raw.githubusercontent.com/chz777123/opencode-lite-subagent/main/install.sh | bash -s -- --dry-run

# 覆盖已存在文件（先备份）
curl -fsSL https://raw.githubusercontent.com/chz777123/opencode-lite-subagent/main/install.sh | bash -s -- --force

# 卸载
curl -fsSL https://raw.githubusercontent.com/chz777123/opencode-lite-subagent/main/install.sh | bash -s -- --uninstall
```

### 方式 3：手动复制

```sh
git clone https://github.com/chz777123/opencode-lite-subagent.git
cd opencode-lite-subagent
cp -R config/agents/. ~/.config/opencode/agents/
cp -R config/commands/. ~/.config/opencode/commands/
mkdir -p ~/.config/opencode/skills/delegate
cp config/skills/delegate/SKILL.md ~/.config/opencode/skills/delegate/SKILL.md
```

然后按需把 5 条权限规则加入 `~/.config/opencode/opencode.json`。

> 方式 1 和方式 2 不要同时使用：两者都会提供同名的命令与 skill。二选一即可。

## 安装后得到什么

| 内容 | 方式 1（插件） | 方式 2（安装器） |
|---|---|---|
| `agents/*.md` | `setup()` 落盘 | 直接复制 |
| `/scout`、`/review` | command transform | 复制 command 文件 |
| `delegate` skill | skill transform | 复制 `SKILL.md` |
| 5 条权限规则 | 手动添加 | 自动合并 |
| `AGENTS.md` 指针 | 手动添加 | 自动追加（带标记） |

OpenCode 会监听配置文件变化并自动重载 agents / commands / skills。命令菜单没刷新时，执行 `/reload`。

## 五个角色

| 角色 | 何时用 | 写权限 | steps | 回执终态 |
|---|---|---|---|---|
| `scout` | 位置未知、跨 ≥3 文件 | 无 | 16 | `located` / `partial` / `not-found` |
| `worker` | 跨 ≥3 文件或 ≥30 行，需求已收敛 | `scope.write` 内 | 50 | `done` / `partial` / `blocked` |
| `reviewer` | 碰公共 API / 迁移 / 鉴权 / 并发 | 无（可跑测试） | 24 | `ship` / `fix-first` / `block` |
| `oracle` | 方案代价高、方向没底 | 无 | 12 | `proceed` / `change-course` / `stop` |
| `evidence-auditor` | 结论依赖外部资料 | 无（含 web 只读） | 16 | `pass` / `fail` |

模型绑定建议：

- `scout` / `evidence-auditor` 应当显式配便宜模型；未配时继承父会话模型
- `reviewer` 尽量与 `worker` 异构，消除同源盲区
- 只有 `worker` 可以留空继承父会话模型

## 协议摘要

```
门控 → TaskCard → 脏净检查 → 派单 → 回执 → 宿主验收 → 续接/交付
```

- **授权门**：用户明确要求、敲 `/scout` 或 `/review`、或先说明「派谁、干什么」并获同意。任务复杂不是授权。
- **TaskCard**：`goal` / `scope.read` / `scope.write` / `non_goals` / `context` / `constraints` / `acceptance`。禁止把聊天历史或 diff 原文粘进 brief。
- **脏净检查**：派单前只查一次 `git status --porcelain -- <scope.write>`；工作区脏时禁止自动回滚。
- **宿主验收**：父 agent 亲自复跑 `acceptance`，看 `git status` 里的新文件，精读 `git diff`，抽查一条 `path:line`。
- **续接**：第 1 次修复必须用原 `worker` 的 `sessionID`；第 2 次仍不过就停下，按脏净状态回滚或交人。
- **并发**：只读角色 ≤3 并行；`worker` 同工作区同时 1 个。

完整协议见 [`config/skills/delegate/SKILL.md`](config/skills/delegate/SKILL.md)，设计取舍见 [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)。

## 权限规则

```jsonc
{ "action": "subagent", "resource": "*", "effect": "ask" },
{ "action": "shell", "resource": "git push *", "effect": "deny" },
{ "action": "shell", "resource": "git clean *", "effect": "deny" },
{ "action": "shell", "resource": "git reset --hard *", "effect": "ask" },
{ "action": "shell", "resource": "rm -rf *", "effect": "deny" }
```

`subagent: ask` 是授权门。首次批准某角色时选 **always**，OpenCode 会按 agent ID 落一条持久 allow。

子 agent 自身是 deny-by-default：每个角色都以 `{ action: "*", resource: "*", effect: deny }` 开头，再逐条放行。这条兜底同时拦住 `external_directory`，所以子 agent 被限制在项目内；跨项目任务由主 agent 自己做，或显式放行。

`worker` 额外封禁：`edit` 的 `.git/**`、`.github/**`、`.opencode/**`、`*.env*`；`shell` 的 `git commit` / `git push` / `git clean` / `git reset --hard` / `rm -rf`。

## OpenChamber 扩展

本仓库同时是一个 OpenChamber 扩展：`package.json` 里的 `openchamber.contributes` 声明了一个侧边面板，入口是 `openchamber/panel/index.html`。

面板只做三件事：说明这个套件是什么、一键复制安装命令、展示角色表。**OpenChamber 扩展只能增加 UI，不能安装 agent**，所以面板不会假装提供「一键安装」。真正的安装仍然走上面的 CLI 命令。

## 卸载

方式 1：

```sh
opencode plugin remove opencode-lite-subagent
```

插件不会自动删除已经落盘的 agent 文件。需要彻底清理时，删除 `~/.config/opencode/agents/{scout,worker,reviewer,oracle,evidence-auditor}.md` 和 `~/.config/opencode/.opencode-lite-subagent.json`。

方式 2：

```sh
curl -fsSL https://raw.githubusercontent.com/chz777123/opencode-lite-subagent/main/install.sh | bash -s -- --uninstall
```

卸载只删除本套件安装的 8 个文件、`AGENTS.md` 里的标记块，以及那 5 条精确匹配的权限规则；不会整文件覆盖你的配置。

## 开发

`config/` 是唯一事实来源。`src/assets.js` 由脚本生成，不要手改。

```sh
node scripts/build-assets.mjs   # 从 config/ 生成 src/assets.js
node --check src/index.js       # 语法检查
bash install.sh --dry-run       # 查看安装器会做什么
```

目录：

```
config/agents/*.md              5 个角色定义
config/commands/*.md            /scout、/review
config/skills/delegate/SKILL.md 派单协议
src/index.js                    OpenCode 插件入口
src/assets.js                   生成文件（不要手改）
scripts/build-assets.mjs        资源生成器
openchamber/panel/index.html    OpenChamber 面板
docs/DEVELOPMENT.md             设计文档
install.sh                      curl 安装器
```

## License

MIT
