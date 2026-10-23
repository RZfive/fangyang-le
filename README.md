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
  --owner 主控 \
  --work "P2 补齐" \
  --tasks lsp,ui,bench,docs
```

默认行为（可省略的都省了）：

- **不跨 workspace**：羊圈 tab/pane 建在主控自己的 `$HERDR_WORKSPACE_ID` 里；不在 herdr pane 里执行会报错，绝不猜。只有用户明确要求跨界时才传 `--workspace`（此时会打 WARNING）。
- **子 agent 与主控同类**：`--kind` 默认 `auto`——claude 起 claude、opencode 起 opencode、codex 起 codex。同类额度满或用户点名时才显式 `--kind <kind>`。
- **manifest 记录 workspace**：`/tmp/herdr-<label>-agents.tsv` 每行 4 列 `name/pane/tab/workspace`，收割时会校验。

新 tab 名称类似 `主控的羊圈 · P2 补齐`，每个 agent 名字是 `lsp`、`ui`、`bench`、`docs`。

收割（从同一个 workspace；不一致会警告 cross-workspace harvest）。**默认保留羊圈**，方便用户点开查看每只羊的现场：

```bash
"$SKILL_DIR/scripts/harvest.sh" \
  --manifest /tmp/herdr-主控的羊圈_·_P2_补齐-agents.tsv \
  --wait 1800000
```

主控汇报、用户审查确认后，再关整圈：

```bash
"$SKILL_DIR/scripts/harvest.sh" \
  --manifest /tmp/herdr-主控的羊圈_·_P2_补齐-agents.tsv \
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
