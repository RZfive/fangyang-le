# 放羊了

Herdr 多 agent 并行工作流 skill。主控留在自己的 tab，worker 放到新的“羊圈”tab，按 2 行网格运行。

## 安装

不依赖固定路径。任选一种：

```bash
# 1) 已经克隆/下载到本地
./install.sh

# 2) 从 GitHub 直接安装
./bootstrap.sh https://github.com/RZfive/fangyang-le.git [git-ref]
```

安装位置默认是：

```text
~/.agents/skills/fangyang-le
```

可通过 `AGENTS_SKILLS_DIR` 覆盖父目录。

安装脚本会把 skill 链接到：

- `~/.claude/skills/放羊了`
- `~/.codex/skills/放羊了`
- `~/.config/opencode/skills/放羊了`

重启或重新加载 agent 后生效。

### 让 agent 从 GitHub 自动安装

给 agent 的口令可以是：

```text
请从 https://github.com/RZfive/fangyang-le.git 克隆「放羊了」skill 到临时目录，
执行其中的 install.sh，安装完成后删除临时目录。
不要写死任何本地固定路径。
```

或者让 agent 直接运行：

```bash
git clone --depth 1 https://github.com/RZfive/fangyang-le.git /tmp/fangyang-le
/tmp/fangyang-le/install.sh
rm -rf /tmp/fangyang-le
```

`install.sh` 会先复制到 `~/.agents/skills/fangyang-le`，再建立链接，因此临时目录删掉也不影响使用。

### 发布到 GitHub

```bash
cd <skill-source-dir>
git init
git add .
git commit -m "Add 放羊了 herdr multi-agent skill"
git branch -M main
git remote add origin https://github.com/RZfive/fangyang-le.git
git push -u origin main
```

## 快速使用

```bash
SKILL_DIR="${AGENTS_SKILLS_DIR:-$HOME/.agents/skills}/fangyang-le"

"$SKILL_DIR/scripts/fanout.sh" \
  --count 4 \
  --work "P2 补齐" \
  --tasks lsp,ui,bench,docs
```

默认行为（可省略的都省了）：

- **不跨 workspace**：羊圈 tab/pane 建在主控自己的 `$HERDR_WORKSPACE_ID` 里；在 herdr pane 外执行时自动 bootstrap（装 herdr、起 headless server、新建专属牧场 workspace），`--no-bootstrap` 可关闭并恢复直接报错。只有用户明确要求跨界时才传 `--workspace`（此时会打 WARNING）。
- **子 agent 与主控同类**：`--kind` 默认 `auto`——claude 起 claude、opencode 起 opencode、codex 起 codex。同类额度满或用户点名时才显式 `--kind <kind>`。
- **manifest 记录 workspace**：`.fangyang/herdr-<label>-agents.tsv`（落在当前仓库内，主控读写无需授权；fanout.sh 自动建目录并幂等追加 `.gitignore`）每行 4 列 `name/pane/tab/workspace`，收割时会校验。
- **西部主控名**：`--owner` 缺省时从西部牛仔名池随机分配（夜枭、响尾蛇、孤星客……），自动避开本 workspace 已占用的名字；主控 tab 已有西部名则沿用。主控 tab 同步改名 `<owner> · <work>`，原名记进 manifest `#controller_tab_*` 元数据行，`harvest.sh --close-tab` 关圈时自动恢复。不在 herdr pane 里或改名失败时只降级提示，不影响放羊。
- **外部放羊**：herdr pane 外跑 `fanout.sh` 时自动 bootstrap——`scripts/ensure-herdr.sh` 确保 herdr CLI 与 headless `herdr server` 可用（已有则复用、缺失则安装/拉起；`FANGYANG_HERDR_BIN` / `FANGYANG_HERDR_INSTALL` / `FANGYANG_HERDR_SERVER_LOG` / `FANGYANG_SERVER_START_WAIT` 可覆盖），羊圈落在专属 `<owner>的牧场 · <work>` workspace，manifest 照常记录、任何 shell 都能收割；`--kind` 缺省按环境嗅探兜底 claude，建议显式传。
- **同 workspace 多主控隔离**：每只羊自动带主控 ASCII slug 前缀（`--tasks lsp,ui` 起名 `night-owl-lsp`、`night-owl-ui`；herdr 只接受 ASCII 小写 agent 名，中文主控名映射为固定英文 slug），撞名自动 `-2/-3` 后缀，任务文件随羊名隔离；manifest 同名不覆盖（自动加 tab id 后缀）。不同主控、不同圈各自收割，互不相窜。

新 tab 名称类似 `夜枭的羊圈 · P2 补齐`，主控自己的 tab 同步变成 `夜枭 · P2 补齐`，每个 agent 名字是 `night-owl-lsp`、`night-owl-ui`、`night-owl-bench`、`night-owl-docs`（中文主控名映射为 ASCII slug，tab 标签仍显示中文）。

收割（从同一个 workspace；不一致会警告 cross-workspace harvest）。**默认保留羊圈**，方便用户点开查看每只羊的现场：

```bash
"$SKILL_DIR/scripts/harvest.sh" \
  --manifest .fangyang/herdr-主控的羊圈_·_P2_补齐-agents.tsv \
  --wait 1800000
```

主控汇报、用户审查确认后，再关整圈（关圈时会把主控 tab 恢复为放羊前的原名）：

```bash
"$SKILL_DIR/scripts/harvest.sh" \
  --manifest .fangyang/herdr-主控的羊圈_·_P2_补齐-agents.tsv \
  --close-tab
```

## 卸载

```bash
./uninstall.sh
```

## 说明

- 不要写死任何本地固定路径。
- 所有脚本都从自身所在目录解析路径。
- `herdr --skill` 可查看当前版本的 herdr AI 控制说明。
