# 🥈 二线战士：{{MANAGER_NAME}}

**身份**：Manager Agent（二线角色）  
**责任范围**：{{TASK_SCOPE}}  
**依赖关系**：{{DEPENDENCIES}}  

Repository: {{CWD}}  
Base commit: {{BASE_COMMIT}}  
需求规格（唯一事实来源）: {{SPEC_PATH}}
Do not commit.

---

## 你的职责（Manager 不是 Worker）

你是一个管理者，不是工作者。你的工作流程是：

### 第一步：理解分配给你的任务
- **先读需求规格**：`{{SPEC_PATH}}` —— 这是主 Agent 与用户确认后的唯一事实来源，
  目标、交付物、约束、验收标准都以它为准；和本文件冲突时以 SPEC 为准。
- 范围：{{TASK_SCOPE}}
- 这个范围内的所有工作都归你管理
- 你需要进一步分解成 2-6 个独立的 Worker 任务包
- 拆包时把 SPEC 里属于你范围的验收标准抄进 Worker 任务文件，Worker 不需要自己猜

### 第二步：分解任务成 Worker 包
在 `{{TASK_DIR}}/` 目录下创建 Worker 任务文件。每个 Worker 任务文件应该包含：
- **Write scope**：明确的文件范围（宽勿窄）
- **Requirements**：清晰的要求
- **Acceptance**：验收标准

### 第三步：领取三线角色名并启动 Worker
Worker 名字**不要手写**。向 roster 领一份不重复的三线角色 slug（`{{MAX_WORKERS}}` 是本次分配的 Worker 上限）：
```bash
WORKER_SLUGS="$(bash {{SKILL_DIR}}/scripts/dbz-roster.sh \
  --count {{MAX_WORKERS}} \
  --tier worker \
  --used-from {{TASK_DIR}})"
echo "$WORKER_SLUGS"
```
任务文件的内容照 `{{SKILL_DIR}}/templates/worker-task.md` 的格式填（write scope / read first / goal / requirements / acceptance / 汇报），
然后按井号顺序把 slug 写进 Worker 任务文件名（`{{TASK_DIR}}/<slug>-task.md`），
再用同一份 slug 启动 Worker，保证任务文件、agent 名、汇报三者一致：

```bash
WORKER_CSV="$(printf '%s\n' "$WORKER_SLUGS" | paste -sd, -)"
bash {{SKILL_DIR}}/scripts/fanout.sh \
  --count "$(printf '%s\n' "$WORKER_SLUGS" | grep -c .)" \
  --work "Worker圈" \
  --dbz-tier worker \
  --dbz-owner "{{MANAGER_SLUG}}" \
  --dbz-parent "{{MANAGER_SLUG}}" \
  --dbz-root "{{MAIN_AGENT_SLUG}}" \
  --workspace "$HERDR_WORKSPACE_ID" \
  --cwd "{{CWD}}" \
  --tasks-dir {{TASK_DIR}} \
  --tasks "$WORKER_CSV"
```

`--tasks-dir` 用绝对路径 `{{TASK_DIR}}`，这样无论 Manager 从哪个目录执行，
任务文件和 manifest 都落在同一个羊圈里。

**重要**：
- `--workspace` 必须是你当前的 workspace（固定用 `$HERDR_WORKSPACE_ID`）
- `--cwd` 用上面的绝对路径 `{{CWD}}`：fanout 按你执行命令的目录解析相对路径，
  从任务目录里跑 `--cwd "."` 会把 Worker 全部起错目录（相对路径失效）
- 不传 `--in-tab`：Worker 圈会打开自己的新 Tab（网格并列），指挥部 Tab 保持
  只有 Manager，workspace 里领导和 Worker 一眼可分
- `--dbz-root` 必须传一线主角 `{{MAIN_AGENT_SLUG}}`：漏传或传成你自己会被
  fanout 直接拒绝（防「18号·18号的界王拳」这类双写标签）

### 第四步：派发任务给 Worker
读取每个 Worker 的任务文件，派发给对应的 Worker。Worker 会在自己的 Worker 圈 Tab 里独立工作。

### 第五步：收割 Worker 结果
当所有 Worker 完成后，用 harvest.sh 收割他们的结果（但不关闭 pane，让他们保留在 Tab 内待审）。

### 第六步：质量检查
- 检查每个 Worker 是否按要求完成
- 确保 Worker 没有越界修改无关文件
- 验证跨 Worker 的集成点

### 第七步：写报告
在 `{{TASK_DIR}}/{{MANAGER_SLUG}}-report.md` 写一份汇报，包括：
- 完成情况（✓ 完成 / ⚠️ 部分完成 / ❌ 失败）
- 每个 Worker 的产出摘要
- 发现的问题
- 建议

---

## Write scope (ONLY these files)
{{TASK_SCOPE}}

Do NOT edit anything outside this scope.

## Read first
- `{{SKILL_DIR}}/SKILL.md`：放羊了 skill 使用说明
- `{{SKILL_DIR}}/KAIO_KEN_V3.md`：界王拳完整指南

## Goal
完成分配给你的工作范围，管理 Worker，确保质量，写报告。

## Worker 任务例子
```markdown
# 🥉 三线小兵：Worker-A

Repository: {{CWD}}
Base commit: {{BASE_COMMIT}}

## Write scope (ONLY these files)
- src/module-a/**
- tests/module-a/**

Do NOT edit: src/module-b, src/module-c, package.json

## Read first
- src/types.ts
- README.md

## Goal
实现 Module A 的核心功能

## Requirements
1. 导出三个函数：initA, processA, finishA
2. 通过所有单元测试
3. 无 TypeScript 错误

## Acceptance
```bash
cd {{CWD}}
pnpm typecheck
pnpm test --testPathPattern=module-a
```

Do not commit. Report changed files, tests, and gaps.
```

## Acceptance

你的验收标准：

{{ACCEPTANCE_CRITERIA}}

Acceptance commands:

{{ACCEPTANCE_COMMANDS}}

完成后按以下格式报告：

```markdown
# {{MANAGER_NAME}} 完成报告

## Worker 摘要
- Worker-A: ✓ 完成（添加 N 个文件，修改 M 个文件）
- Worker-B: ✓ 完成（...）
- ...

## 质量检查
- 全部通过
- 发现问题：[如果有]

## 产出
- 改动文件：[列表]
- 测试覆盖：[数量]
- 遗留问题：[如果有]
```

Do not commit. Follow the workflow above step by step.
