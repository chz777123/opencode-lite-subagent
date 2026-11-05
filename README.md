# opencode-lite-subagent

给 OpenCode V2 用的轻量协作套件：5 个子 agent、1 个按需加载的委派规则、2 个快捷命令。不需要额外服务、数据库或常驻进程。

> 子 agent 负责做事，主 agent 负责判断。每个子 agent 的最后一行必须给出 `verdict:` 结论，主 agent 必须自己再跑一遍验收命令。

## 包含什么

- **5 个子 agent**：`scout`、`worker`、`reviewer`、`oracle`、`evidence-auditor`
- **1 个 skill**：`delegate`，需要时才加载，讲清楚什么时候该委派、任务怎么描述、主 agent 怎么验收、失败后怎么继续原来的会话或回滚
- **2 个命令**：`/scout`、`/review`
- **5 条全局权限规则**：委派前先询问，并拦截高危命令
- **1 个 OpenChamber 面板**：说明、安装命令、角色表

## 安装（三种方式，选一种）

### 方式 1：作为 OpenCode 插件

```sh
opencode plugin add github:chz777123/opencode-lite-subagent
```

如果客户端不接受 `github:` 简写：

```sh
opencode plugin add git+https://github.com/chz777123/opencode-lite-subagent.git
```

插件加载后会：

- 把 5 个子 agent 写入 `~/.config/opencode/agents/`（遵循 `XDG_CONFIG_HOME`）
- 注册 `/scout`、`/review`
- 注册 `delegate` skill
- 不会覆盖你已经改过的 agent 文件；安装记录保存在 `~/.config/opencode/.opencode-lite-subagent.json`

插件不会修改全局权限，也不会改你的 `AGENTS.md`。如果你需要“委派前先询问”和“拦截高危命令”，请手动把「权限规则」一节里的 5 条规则加到 `~/.config/opencode/opencode.json` 的 `permissions` 里，或者改用方式 2。

### 方式 2：curl 安装器（不依赖 npm）

```sh
curl -fsSL https://raw.githubusercontent.com/chz777123/opencode-lite-subagent/main/install.sh | bash
```

安装器会：

- 把 5 个子 agent、2 个命令、1 个 skill 复制到 `~/.config/opencode/`
- 合并 5 条权限规则，已经存在的不会重复添加
- 在 `AGENTS.md` 里追加一段带标记的提示
- 已存在的文件默认跳过；加 `--force` 覆盖前会先备份成 `*.bak-<时间戳>`
- 只改 `permissions` 数组，配置里的其他内容保持不变

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

> 方式 1 和方式 2 不要同时使用：两者都会提供同名的命令和 skill。二选一即可。

## 安装后得到什么

| 内容 | 方式 1（插件） | 方式 2（安装器） |
|---|---|---|
| `agents/*.md` | 插件启动时写入文件 | 直接复制 |
| `/scout`、`/review` | 通过插件接口注册 | 复制命令文件 |
| `delegate` skill | 通过插件接口注册 | 复制 `SKILL.md` |
| 5 条权限规则 | 手动添加 | 自动合并 |
| `AGENTS.md` 提示 | 手动添加 | 自动追加（带标记） |

OpenCode 会监听配置文件变化并自动重新加载。如果命令菜单没有刷新，执行 `/reload`。

## 五个角色

| 角色 | 什么时候用 | 写权限 | 步数上限 | 结束时的结论 |
|---|---|---|---|---|
| `scout` | 位置未知、跨 ≥3 文件 | 无 | 16 | `located` / `partial` / `not-found` |
| `worker` | 跨 ≥3 文件或 ≥30 行，需求已经明确 | 只改任务指定的文件 | 50 | `done` / `partial` / `blocked` |
| `reviewer` | 碰公共 API / 迁移 / 鉴权 / 并发 | 无（可以跑测试） | 24 | `ship` / `fix-first` / `block` |
| `oracle` | 方案代价高、方向没底 | 无 | 12 | `proceed` / `change-course` / `stop` |
| `evidence-auditor` | 结论依赖外部资料 | 无（可以联网只读） | 16 | `pass` / `fail` |

模型配置建议：

- `scout` / `evidence-auditor` 最好显式配一个便宜模型；不配就会继承主会话的模型
- `reviewer` 尽量和 `worker` 用不同模型，避免同一个盲区
- 只有 `worker` 可以留空，直接继承主会话模型

## 协作流程

```
判断是否需要委派 → 写任务卡 → 检查工作区 → 交给子 agent → 读取结果 → 主 agent 验收 → 继续原来的会话或交付
```

- **判断是否需要委派**：用户明确要求、敲了 `/scout` 或 `/review`、或者你先说明“让谁做什么”并得到同意。任务复杂本身不算授权。
- **写任务卡**：写清楚目标、可读范围、可写范围、不做什么、背景、限制条件和验收命令。不要把聊天记录或完整 diff 粘进去。
- **检查工作区**：交给子 agent 之前，只看一次 `git status --porcelain -- <可写范围>`。如果工作区本来就有未提交改动，不要自动回滚。
- **主 agent 验收**：主 agent 自己再跑一遍验收命令，检查 `git status` 里的新文件，读一遍 `git diff`，再抽查一条子 agent 给的 `path:line`。
- **继续同一个子 agent 会话**：第一次修复必须回到原来那个子 agent 的 `sessionID` 继续；第二次还不过就停下来，根据工作区状态决定回滚还是交给人。
- **同时运行**：只读角色最多 3 个并行；`worker` 在同一个工作区同时只能有 1 个。

完整规则见 [`config/skills/delegate/SKILL.md`](config/skills/delegate/SKILL.md)，设计取舍见 [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)。

## 权限规则

```jsonc
{ "action": "subagent", "resource": "*", "effect": "ask" },
{ "action": "shell", "resource": "git push *", "effect": "deny" },
{ "action": "shell", "resource": "git clean *", "effect": "deny" },
{ "action": "shell", "resource": "git reset --hard *", "effect": "ask" },
{ "action": "shell", "resource": "rm -rf *", "effect": "deny" }
```

`subagent: ask` 是委派前的确认。第一次批准某个角色时选 **always**，OpenCode 会按 agent ID 记住这个选择。

每个子 agent 默认拒绝所有操作，再逐条放行。这条默认拒绝规则也会拦住项目外目录访问，所以子 agent 只能在自己的项目里工作；跨项目任务由主 agent 自己做，或者显式放行。

`worker` 还额外禁止：

- 修改 `.git/**`、`.github/**`、`.opencode/**`、`*.env*`
- 执行 `git commit`、`git push`、`git clean`、`git reset --hard`、`rm -rf`

## OpenChamber 面板

这个仓库同时是一个 OpenChamber 扩展：`package.json` 里的 `openchamber.contributes` 声明了一个侧边面板，入口是 `openchamber/panel/index.html`。

面板只做三件事：说明这个套件是什么、一键复制安装命令、展示角色表。**OpenChamber 扩展只能增加界面，不能安装 agent**，所以面板不会提供“一键安装”按钮。真正的安装仍然走上面的命令行。

## 卸载

方式 1：

```sh
opencode plugin remove github:chz777123/opencode-lite-subagent
```

插件不会自动删除已经写入的 agent 文件。需要彻底清理时，删除 `~/.config/opencode/agents/{scout,worker,reviewer,oracle,evidence-auditor}.md` 和 `~/.config/opencode/.opencode-lite-subagent.json`。

方式 2：

```sh
curl -fsSL https://raw.githubusercontent.com/chz777123/opencode-lite-subagent/main/install.sh | bash -s -- --uninstall
```

卸载只删除本套件安装的 8 个文件、`AGENTS.md` 里的标记段，以及那 5 条精确匹配的权限规则；不会覆盖你的其他配置。

## 实现方式

- 插件入口是 `src/index.js`，用 `Plugin.define({ id, setup })` 定义
- `setup()` 负责把 5 个子 agent 写入 `~/.config/opencode/agents/`
- `/scout`、`/review` 通过 `ctx.command.transform` 注册（OpenCode 提供的命令注册接口）
- `delegate` 通过 `ctx.skill.transform` 注册（OpenCode 提供的 skill 注册接口）
- 所有内容都以 `config/` 为准，`src/assets.js` 由 `scripts/build-assets.mjs` 生成，不要手改

## 开发

```sh
node scripts/build-assets.mjs   # 从 config/ 生成 src/assets.js
node --check src/index.js       # 语法检查
bash install.sh --dry-run       # 查看安装器会做什么
```

目录：

```
config/agents/*.md              5 个角色定义
config/commands/*.md            /scout、/review
config/skills/delegate/SKILL.md 委派规则
src/index.js                    OpenCode 插件入口
src/assets.js                   生成文件（不要手改）
scripts/build-assets.mjs        资源生成器
openchamber/panel/index.html    OpenChamber 面板
docs/DEVELOPMENT.md             设计文档
install.sh                      curl 安装器
```

## License

MIT
