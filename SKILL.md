---
name: fangyang-le
description: 放羊了 —— 用 herdr 并行放养多个 coding agent（Codex / Claude Code / OpenCode / Gemini / Cursor / Copilot / Qwen / Kimi / Droid 等）。当用户要求“多开 agent / 并发做 / 分工 / 放羊 / 快速并行推进”，或任务可以按文件或模块拆成多个独立 workstream 时使用。主控负责拆任务、开 pane、派发、处理权限、收割结果、统一验证和 checkpoint；agent 不提交代码。
---

# 放羊了

一个 herdr 多 agent 并行工作流。核心不是“多开几个窗口”，而是：

> 主控拆任务 → 每只羊一个任务文件 → 并行执行 → 主控统一验证 → 只提交干净结果。

本 skill 不绑定任何固定目录。下文用 `SKILL_DIR` 表示本文件所在目录；安装后通常在：

```bash
export SKILL_DIR="${AGENTS_SKILLS_DIR:-$HOME/.agents/skills}/fangyang-le"
```

如果还没安装，可以直接用克隆/下载目录里的 `install.sh`。也可以让 agent 从 GitHub 自动安装：

```bash
git clone --depth 1 https://github.com/RZfive/fangyang-le.git /tmp/fangyang-le
/tmp/fangyang-le/install.sh
rm -rf /tmp/fangyang-le
```

`install.sh` 会复制到稳定目录后再建链接，临时目录可以删除。

## 什么时候用

适合：

- 多个独立模块、语言、测试、文档、UI、基准可以并行
- 每个任务有明确文件边界
- 需要 2–6 个 agent 同时推进
- 需要主控保持集成和提交权

不适合：

- 所有 agent 必须改同一个热文件
- 任务高度串行、强依赖上一步结果
- 还没定义验收标准
- 用户明确要求单 agent 顺序执行

## 铁律

1. **主控不跟 agent 抢同一文件。**
2. **每只羊一个任务文件**：写清 write scope、read first、要求、验收命令、禁止 commit。
3. **热文件单 owner**：`agent.rs`、`lib.rs`、`types.rs`、`ChatPanelContainer.vue`、`package.json` 等同一时间只给一个 agent。
4. **默认 2–4 只羊，确认独立后再加到 6。**
5. **agent 不 commit、不 push、不擅自扩大 scope。**
6. **主控统一跑全量验证后再提交。**
7. **只有用户明确说“提交”时才 commit。**
8. 任务文件放**仓库内** `$PWD/.fangyang/<name>-task.md`（`fanout.sh` 自动建目录并加入 `.gitignore`），不要放 `/tmp`——cwd 外读取会触发每个 agent 的授权弹窗；也不要把任务说明塞进 prompt 正文。
9. **不跨 workspace 放羊。** 羊圈 tab/pane 一律建在主控自己的 `$HERDR_WORKSPACE_ID` 里；绝不用“当前 focus 所在”的 workspace（focus 可能停在别的控制方的羊圈上）。`fanout.sh` 默认锁定主控 workspace；只有用户明确要求跨界时才显式 `--workspace`。
10. **子 agent 与主控同类。** Claude Code 起的羊就是 claude，OpenCode 起的羊就是 opencode：`--kind` 默认 `auto`，自动取主控自己的 kind。只有同类额度耗尽或用户点名要别的模型时，才显式换 kind，并在汇报时说明。
11. **收割后保留羊圈。** 任务结束先不关 pane/tab，让用户随时点开羊圈查看每只羊的现场和产出；主控完成审查、统一验证、汇报之后，**提示用户羊圈还开着**，等用户确认审查完毕才关闭羊圈。绝不收割完就悄悄拆圈。
12. **同 workspace 多主控隔离，互不相窜。** 羊名一律自动带主控前缀 `<owner>-<任务名>`（如 `夜枭-lsp`），不同主控的羊永不重名；撞名（同主控二圈同名任务、或显式 `--owner` 撞车）自动加 `-2/-3` 后缀；manifest 同名不覆盖（自动加 tab id 后缀）。prompt/wait/read/收割全部走 manifest 里记录的带前缀羊名，不会读到别的圈的羊。

## 快速口令

用户说“放羊”或“并发做”时，按这个顺序执行：

1. 先调查代码，列 2–6 个独立 workstream。
2. 给每个 workstream 写 `$PWD/.fangyang/<name>-task.md`（仓库内，羊读它不需要授权）。
3. 在**主控自己的 workspace**（`$HERDR_WORKSPACE_ID`）里新建 herdr tab + 网格 pane。
4. 每个 pane `agent start`，kind 默认 `auto`（与主控同类：claude 起 claude、opencode 起 opencode）；仅当同类额度满或用户点名时才显式换 kind。
5. 每个 agent `prompt` 指向自己的任务文件。
6. 派发后等待；任务文件在仓库内时通常全程无授权弹窗。
7. 从**同一个 workspace** 收割结果（**不带 `--close`，羊圈保留**），主控跑门禁。
8. 汇报（含各羊完成情况），并提示用户：羊圈还开着，可自行查看。
9. 用户确认审查完毕后，再关闭羊圈；用户明确要求时才 commit。

## Herdr 常用命令速查

> 不确定当前版本语法时，先运行 `herdr --skill`，它会输出给 AI 使用的 herdr 控制说明。

### 环境与查看

```bash
herdr status
herdr workspace list
herdr tab list --workspace "$HERDR_WORKSPACE_ID"
herdr pane list --workspace "$HERDR_WORKSPACE_ID"
herdr pane layout
herdr pane current

# 当前 agent 自己的身份
echo "$HERDR_WORKSPACE_ID"
echo "$HERDR_TAB_ID"
echo "$HERDR_PANE_ID"
```

结构化查看：

```bash
herdr agent list | jq -r '.result.agents[] | [.name // "(unnamed)", .pane_id, .tab_id, .agent_status] | @tsv'
herdr tab list --workspace "$HERDR_WORKSPACE_ID" | jq -r '.result.tabs[] | [.tab_id, .label, .pane_count, .focused] | @tsv'
```

### Tab

```bash
# 新建羊圈 tab
herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$PWD" --label "主控的羊圈 · 任务名" --no-focus

# 改名
herdr tab rename <tab-id> "主控的羊圈 · 新任务名"

# 关闭
herdr tab close <tab-id>
```

### Pane

```bash
# 从当前 pane 向右/向下切
herdr pane split "$HERDR_PANE_ID" --direction right --cwd "$PWD" --no-focus
herdr pane split <pane-id> --direction down --cwd "$PWD" --no-focus

# 查看/聚焦/关闭
herdr pane list --workspace "$HERDR_WORKSPACE_ID"
herdr pane layout
herdr pane focus --pane <pane-id>
herdr pane close <pane-id>
```

### Agent

```bash
# 在已有 shell pane 启动 agent
herdr agent start <name> --kind <codex|claude|opencode|gemini|...> --pane <pane-id> --timeout 120000

# 派发任务（任务文件在仓库 .fangyang/ 内，读取无需授权）
herdr agent prompt <name> "Read .fangyang/task.md and execute it exactly. Stay in scope. Do not commit."

# 等待完成
herdr agent wait <name> --until idle --until done --until blocked --timeout 1800000

# 读取输出
herdr agent read <name> --lines 160
herdr agent read <name> --source visible   # working/blocked 时看当前屏幕

# 权限兜底：仅当仍触发授权弹窗时（Always allow）
herdr agent send-keys <name> right enter
herdr agent send-keys <name> enter

# 改名/聚焦/状态
herdr agent rename <name> <new-name>
herdr agent focus <name>
herdr agent get <name>
herdr agent explain <name>
```

## 1. 调查与拆分

先确认：

```bash
git status --short
git log --oneline -5
herdr status
herdr workspace list
herdr tab list --workspace <workspace>
```

拆分原则：

- 一个 agent 一个可独立验收的交付
- 文件 scope 尽量不重叠
- 新文件优先，热文件后置或单 owner
- 每个任务必须有验收命令
- 需要集成的部分留给主控

常见拆分：

- Rust crate / 语言支持 / 解析器 / 验证器
- Electron UI / 事件链路 / 设置页
- 测试与基准 / 文档 / CI
- 依赖修复 / LSP / 命令执行
- 独立语言：Python / Go / Rust / Java

## 2. 写任务文件

复制模板（落到仓库内 `.fangyang/` 目录，子 agent 读取时**不会触发授权弹窗**）：

```bash
mkdir -p "$PWD/.fangyang"
cp "$SKILL_DIR/templates/task.md" "$PWD/.fangyang/<name>-task.md"
```

fanout.sh 也会自动创建 `.fangyang/` 并把 manifest 写在里面，同时在 `.gitignore` 里幂等追加 `.fangyang/`（不会误提交任务文件）。

必须包含：

```markdown
# Worker: <任务名>

Repository: /path/to/repo
Base commit: <sha>. Do not commit.

## Write scope (ONLY these files)
- ...

Do NOT edit: ...

## Read first
- ...

## Goal
...

## Requirements
...

## Acceptance
```bash
...
```

Do not commit. Report changed files, tests, and gaps.
```

写 scope 时宁窄勿宽。需要共享文件时，让主控做，不要让两只羊同时改。

## 3. 开 tab 和 pane

推荐布局：主控在左，右侧 2×N 网格。

用脚本快速开（`--kind` 省略时默认 `auto`，与主控同类）：

```bash
"$SKILL_DIR/scripts/fanout.sh" \
  --count 6 \
  --work "P2 补齐" \
  --tasks lsp,ui,bench,docs,rust,python \
  --cwd "$PWD"
```

脚本会创建 tab、网格 pane、启动 agent，并打印每个 agent 的名字和 pane id。羊圈建在主控自己的 `$HERDR_WORKSPACE_ID` 里，不跨 workspace；不在 herdr pane 里执行会直接报错。

主控留在原 tab；新 tab 的标签默认是：

```text
<owner>的羊圈 · <work>
```

例如：`夜枭的羊圈 · P2 补齐`。`--owner` 缺省时从内置西部牛仔名池随机分配（孤星客、响尾蛇、夜枭、快枪手、荒野狼、金马刺……），自动避开本 workspace 已被其他 tab 占用的名字；主控 tab 上已有的西部名会沿用（同一主控再开一圈同名）。传 `--owner 主控` 可用回旧命名。人可以直接在 herdr 的 tab 列表里看到“谁在带哪群羊、干什么活”。

同时 `fanout.sh` 会把**主控自己的 tab** 同步改名为 `<owner> · <work>`（如 `夜枭 · P2 补齐`），原名写入 manifest 元数据；`harvest.sh --close-tab` 关圈时自动恢复。多个主控并行时，谁的 tab 对应哪个羊圈一眼可辨。改名失败或不在 herdr pane 里时只降级提示，不影响放羊。

查看 tab：

```bash
herdr tab list --workspace "$HERDR_WORKSPACE_ID"
```

需要改名字时：

```bash
herdr tab rename <tab-id> "主控的羊圈 · 新任务名"
```

手工方式：

```bash
herdr tab create --workspace <ws> --cwd "$PWD" --label coding-6 --no-focus
herdr pane split <root-pane> --direction right --cwd "$PWD" --no-focus
herdr pane split <right-pane> --direction down --cwd "$PWD" --no-focus
herdr agent start worker-a --kind codex --pane <pane-id>
herdr agent start worker-b --kind opencode --pane <pane-id>
```

`agent start` 要求 pane 停在交互式 shell prompt。

支持的 kind 以当前 herdr 为准：

```bash
herdr agent start --help
```

常见：`codex`、`claude`、`opencode`、`gemini`、`cursor`、`copilot`、`qwen`、`kimi`、`droid`、`cline`、`amp`、`grok`。

选择顺序：

1. 默认 `--kind auto`：与主控同类。claude 起 claude，opencode 起 opencode，codex 起 codex——同种 agent 的行为、权限、配置最一致
2. 同类额度耗尽 → 按用户偏好降级到 `claude` / `opencode`，并在汇报时说明用了什么 kind
3. 需要不同模型能力时混用，但同一文件仍只能一个 owner

Workspace 纪律：

1. 羊圈 tab、所有 pane、所有 agent 都建在主控自己的 `$HERDR_WORKSPACE_ID`
2. `fanout.sh` 不带 `--workspace` 时自动锁定主控 workspace；不在 herdr pane 里（环境变量缺失）会直接报错，而不是猜一个
3. 显式 `--workspace` 与主控 workspace 不同时会打 WARNING——仅限用户明确要求跨界时使用
4. `harvest.sh` 发现 manifest 记录的 workspace 与当前 shell 不一致时会警告跨 workspace 收割，应回到起羊的 workspace 重新收割

### 网格怎么摆

默认让主控占一列，agent 在右侧排成 2 行网格：

| agent 数 | 布局 |
|---|---|
| 2 | 1 行 × 2 列 |
| 3 | 2 行 × 2 列（右下空一格） |
| 4 | 2 × 2 |
| 5 | 2 行 × 3 列（右下空一格） |
| 6 | 2 行 × 3 列 |

手工给 4 只羊开网格：

```bash
# 主控 pane 在左；先向右分出 agent 区
A=$(herdr pane split "$HERDR_PANE_ID" --direction right --cwd "$PWD" --no-focus | jq -r '.result.pane.pane_id')
# agent 区再分一列
B=$(herdr pane split "$A" --direction right --cwd "$PWD" --no-focus | jq -r '.result.pane.pane_id')
# 两列各自向下分，得到 2×2
C=$(herdr pane split "$A" --direction down --cwd "$PWD" --no-focus | jq -r '.result.pane.pane_id')
D=$(herdr pane split "$B" --direction down --cwd "$PWD" --no-focus | jq -r '.result.pane.pane_id')
```

6 只羊同理：先分出 3 列，再把 3 列各向下分一次。

如果不想让主控和羊挤在同一 tab：主控留在原 tab，另开一个 tab 专门做 2 行网格（`fanout.sh` 默认这样做）。

### 怎么找到“自己的羊”

**从主控视角：**

```bash
herdr agent list
herdr agent get worker-a
herdr pane list --workspace "$HERDR_WORKSPACE_ID"
```

`agent list` 会返回每个 agent 的 `name`、`pane_id`、`tab_id`、`cwd`、`agent_status`。用 agent 名字操作最稳：

```bash
herdr agent prompt worker-a "..."
herdr agent wait worker-a --until done --timeout 1800000
herdr agent read worker-a --lines 160
```

**从 agent 自己视角：**

```bash
echo "$HERDR_PANE_ID"
echo "$HERDR_TAB_ID"
echo "$HERDR_WORKSPACE_ID"
herdr pane current
```

`HERDR_PANE_ID` 是当前进程所在 pane，最可靠。`herdr pane current` 返回的是当前**焦点** pane；如果别的 pane 被点中，它可能不是你自己，所以优先用环境变量。

**从脚本视角：**

`fanout.sh` 会写 manifest（落在 `$PWD/.fangyang/`，主控读写无需授权）：

```text
.fangyang/herdr-<label>-agents.tsv
#controller_tab_id=w7:t3
#controller_tab_label=1
name    pane    tab    workspace
worker-1 w7:pB  w7:t5  w7
...
```

第 4 列记录这群羊所在的 workspace；`#` 开头是元数据行（主控 tab 配对信息），`harvest.sh` 读 agent 时会跳过，`--close-tab` 用它恢复主控 tab 原名——旧 manifest 没有这些行也能正常收割。收割时直接（**不带 `--close`，羊圈保留待审**）：

```bash
"$SKILL_DIR/scripts/harvest.sh" \
  --manifest .fangyang/herdr-主控的羊圈_·_P2_补齐-agents.tsv \
  --wait 1800000
```

审查完毕、用户确认后再关整圈：

```bash
"$SKILL_DIR/scripts/harvest.sh" \
  --manifest .fangyang/herdr-主控的羊圈_·_P2_补齐-agents.tsv \
  --close-tab
```

`--tasks` 按逗号拆分作为任务名，脚本自动给每只羊加主控前缀：`--tasks lsp-tool,ui-persist` 实际起名 `夜枭-lsp-tool`、`夜枭-ui-persist`（同 workspace 多圈隔离；撞名自动 `-2/-3` 后缀）。任务文件同名跟随：`.fangyang/夜枭-lsp-tool-task.md`。直接用任务语义命名即可，不要手动加主控前缀。

## 4. 派发

```bash
herdr agent prompt worker-a \
  "Read .fangyang/my-task-a.md and execute it exactly. Stay strictly within the listed write scope. Do not commit. Run every acceptance command and report changed files, tests, and gaps."
```

一次派发所有 agent；不要等第一只完成再派第二只。

## 5. 权限卡住怎么办

任务文件和 manifest 都已放在仓库内 `.fangyang/`，正常流程**不会**触发目录授权弹窗。仅当 agent 去读仓库外的路径（如 `/tmp`、`~/Downloads`）时才可能出现：

```text
Permission required: Access external directory /tmp
Allow once | Allow always | Reject
```

处理（兜底手段，不要预先批量发）：

```bash
# 选中 Always allow
herdr agent send-keys worker-a right enter
# 再确认一次
herdr agent send-keys worker-a enter
```

如果已选到 `Confirm`，直接 `enter`。

查看当前画面：

```bash
herdr agent read worker-a --source visible
```

`agent read` 报 `agent_not_idle` 时：

```bash
# 看当前可见屏幕
herdr agent read worker-a --source visible
# 或等 agent 进入 idle
herdr agent wait worker-a --until idle --timeout 300000
```

## 6. 等待与收割

```bash
herdr agent list
herdr agent wait worker-a --until idle --until done --until blocked --timeout 1800000
```

注意：`wait` 可能匹配到中间 idle。看到完成汇报前，再检查一次：

```bash
herdr agent list
herdr agent read worker-a --lines 160
```

如果还在 working，`read` 可能失败；用：

```bash
herdr agent read worker-a --source visible
```

收割后检查每只羊的最终报告：

- 改了什么文件
- 测试数量/结果
- 是否越界
- 是否把无关文件格式化了
- 有没有未完成项

**收割 ≠ 拆圈。** `harvest.sh` 不带 `--close` 时只读输出、不动 pane——羊圈原样保留，用户随时可以点开 tab 查看每只羊的现场。主控完成审查和验证后，在汇报里明确提示"羊圈还开着"，等用户确认审查完毕再执行关闭。

## 7. 主控统一验证

不要只相信 agent 的“测试通过”。主控至少跑：

```bash
git status --short
git diff --check
```

按仓库门禁跑：

```bash
# Rust
cargo test --manifest-path harness-rs/Cargo.toml --workspace
cargo clippy --manifest-path harness-rs/Cargo.toml -p <crate> --all-targets --no-deps -- -D warnings

# Electron
pnpm --dir apps/electron typecheck
pnpm --dir apps/electron build
pnpm --dir apps/electron test:rust-harness-host-callbacks
pnpm --dir apps/electron test:renderer-navigation

# 如果仓库提供统一脚本
bash scripts/verify-coding.sh
pnpm coding:check
```

如果 agent 跑了 `rustfmt lib.rs` 导致其他模块被递归格式化：

```bash
git checkout -- <unrelated-files>
```

只保留任务 scope 内的 diff。

## 8. 关闭羊圈（审查完毕后）

关闭的时机：**主控已汇报、用户已查看并确认审查完毕**。不是收割完就关。

汇报时提示用户（示例话术）：

> 羊圈「主控的羊圈 · P2 补齐」还开着，你可以点开 herdr 里这个 tab 查看每只羊的现场和产出。确认没问题后我就把圈关掉；要保留也行，说一声即可。

用户确认后，整圈一次关掉（推荐，manifest 第 3 列就是 tab id）：

```bash
"$SKILL_DIR/scripts/harvest.sh" --manifest .fangyang/herdr-<label>-agents.tsv --close-tab
# 或手工
herdr tab close <tab-id>
```

只想关单个 pane：

```bash
herdr pane close <pane-id>
```

确认没有 agent 还在 working 再关（`--close-tab`/`--close` 遇 working 会自动跳过并提示）。`--close-tab` 关圈后还会按 manifest 里的 `#controller_tab_*` 元数据把主控 tab 恢复为放羊前的原名。

## 9. 提交

只有用户明确要求提交时：

```bash
git status --short
git diff --check
git add <intended-files>
git diff --cached --stat
git commit -m "<type>(<scope>): <summary>"
```

不要把以下内容混进提交：

- 过期的根目录重复文档
- agent 留下的临时脚本/调试文件
- 无关的格式化噪音
- 未跟踪的截图、日志、benchmark 输出

## 任务模板

见 `templates/task.md`。

## 脚本

- `scripts/fanout.sh`：创建 tab、网格 pane、启动 N 个 agent；同步把主控 tab 改名 `<owner> · <work>`
- `scripts/harvest.sh`：查看状态、等待、读取最终输出、可选关闭 pane；`--close-tab` 关圈时恢复主控 tab 原名
- `tests/run-tests.sh`：离线 stub 测试（伪 herdr CLI），覆盖 fanout/harvest 的主控 tab 配对行为
- `install.sh`：安装到 `~/.agents/skills/fangyang-le` 并链接到 agent skill 目录
- `bootstrap.sh`：从 GitHub 克隆后自动安装
- `uninstall.sh`：卸载

## 故障排查

| 现象 | 处理 |
|---|---|
| `pane not found` | 重新 `herdr pane list`，不要手写不存在的 pane id |
| `agent start` 卡住 | pane 必须在 shell prompt，不能在 agent/editor 里 |
| agent 一直 blocked | `read --source visible`，通常是 `/tmp` 或命令权限 |
| `wait` 很快返回 done 但还在跑 | 再 `wait` 一次或 `agent list` 确认 |
| `agent read` 报 working | 用 `--source visible` 或等 idle |
| 两个 agent 改同一文件 | 立刻停一个，主控接管该文件 |
| cargo file lock 等待 | 正常，让它们排队；不要并行跑同一 target 的重型构建 |
| agent 格式化无关文件 | 主控 revert 无关文件，只保留 scope 内 diff |
| `fanout.sh` 报 `HERDR_WORKSPACE_ID is unset` | 不在 herdr pane 里跑脚本了；回到主控 pane 执行，或仅在用户明确要求跨界时传 `--workspace` |
| `fanout.sh` 报检测不到 agent kind | 控制方 pane 不是已注册 agent，或无 `$HERDR_PANE_ID`；显式传 `--kind claude / opencode / codex` |
| `harvest.sh` 警告 cross-workspace harvest | 当前 shell 与起羊时的 workspace 不一致；`echo $HERDR_WORKSPACE_ID` 确认后，回到原 workspace 重新收割 |

## 一句话

**先拆干净，再放出去；羊只负责吃自己那片草，主控负责收网、验证和提交。**
