# 🥈 二线战士：{{MANAGER_NAME}}

**身份**：Manager Agent（二线角色）  
**责任范围**：{{TASK_SCOPE}}  
**依赖关系**：{{DEPENDENCIES}}  

Repository: {{CWD}}  
Base commit: {{BASE_COMMIT}}  
Do not commit.

---

## 你的职责（Manager 不是 Worker）

你是一个管理者，不是工作者。你的工作流程是：

### 第一步：理解分配给你的任务
- 范围：{{TASK_SCOPE}}
- 这个范围内的所有工作都归你管理
- 你需要进一步分解成 2-6 个独立的 Worker 任务包

### 第二步：分解任务成 Worker 包
在 `{{KAIO_KEN_DIR}}/` 目录下创建 Worker 任务文件。每个 Worker 任务文件应该包含：
- **Write scope**：明确的文件范围（宽勿窄）
- **Requirements**：清晰的要求
- **Acceptance**：验收标准

### 第三步：在你的 Tab 里启动 Worker
使用 fanout.sh 在你的 Tab（当前 Tab）里启动 2-6 个 Worker Agent。
```bash
cd {{CWD}}
bash {{SKILL_DIR}}/scripts/fanout.sh \
  --count 3 \
  --work "{{MANAGER_NAME}} 的工作" \
  --tasks worker-a,worker-b,worker-c \
  --workspace "$HERDR_WORKSPACE_ID" \
  --cwd "." \
  --tasks-dir {{KAIO_KEN_DIR}}
```

**重要**：
- `--workspace` 必须是你当前的 workspace（固定用 `$HERDR_WORKSPACE_ID`）
- Worker 会在你的 Tab 里作为网格 pane 出现
- 这样所有 Worker 都汇聚在你这个 Manager Tab 内，用户可以清晰看到组织结构

### 第四步：派发任务给 Worker
读取每个 Worker 的任务文件，派发给对应的 Worker。Worker 会在你的网格 pane 里独立工作。

### 第五步：收割 Worker 结果
当所有 Worker 完成后，用 harvest.sh 收割他们的结果（但不关闭 pane，让他们保留在 Tab 内待审）。

### 第六步：质量检查
- 检查每个 Worker 是否按要求完成
- 确保 Worker 没有越界修改无关文件
- 验证跨 Worker 的集成点

### 第七步：写报告
在 `{{KAIO_KEN_DIR}}/{{MANAGER_SLUG}}-report.md` 写一份汇报，包括：
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
