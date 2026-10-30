# 界王拳模式快速参考

## 三句话总结

1. **主 Agent 创建专属 workspace，用 fanout.sh 启动 2-6 个 Manager**
2. **每个 Manager 在自己的 Tab 里，再用 fanout.sh 启动 2-6 个 Worker**
3. **主 Agent Loop 管理，所有 Manager 完成后聚合报告并交付**

## 架构图

```
主 Agent（协调者）
  ↓
  ├─ 创建专属 workspace
  ├─ 用 fanout.sh 启动 Manager 层
  │
  └─ Loop 管理（每 30 秒检查一次）
       ↓
       Manager-A (Tab 1)          Manager-B (Tab 2)          Manager-C (Tab 3)
       ├─ 主控 pane               ├─ 主控 pane               ├─ 主控 pane
       └─ 用 fanout.sh 启动       └─ 用 fanout.sh 启动       └─ 用 fanout.sh 启动
          Worker panes              Worker panes              Worker panes
          ├─ W-A1                   ├─ W-B1                   ├─ W-C1
          ├─ W-A2                   ├─ W-B2                   ├─ W-C2
          └─ W-A3                   └─ W-B3                   └─ W-C3
```

## 启动界王拳

```bash
cd /path/to/project

bash /path/to/fangyang-le/scripts/kaio-ken-orchestrate.sh \
  --request "你的项目需求" \
  --max-managers 3 \
  --cwd "$PWD"
```

## 主 Agent 需要做的事

| 步骤 | 命令 | 说明 |
|------|------|------|
| 1 | 与用户沟通 | 理解需求、约束、优先级 |
| 2 | 自动分解 | 按代码/报告/设计类型拆分 |
| 3 | 创建 workspace | `herdr workspace create` |
| 4 | 启动 Manager | `fanout.sh --count 3 ...` |
| 5 | 派发任务 | `herdr agent prompt <manager>` |
| 6 | Loop 管理 | 每 30 秒检查 `herdr agent list` |
| 7 | 收割报告 | 从 `.fangyang/<dir>/*.md` |
| 8 | 交付用户 | 生成最终报告 |

## Manager 需要做的事

| 步骤 | 命令 | 说明 |
|------|------|------|
| 1 | 读任务 | 理解 task scope 和 dependencies |
| 2 | 分解 Worker | 分成 2-6 个工作包 |
| 3 | 写任务文件 | 每个 Worker 一个 `worker-*-task.md` |
| 4 | 启动 Worker | `fanout.sh --count N ...` |
| 5 | 派发任务 | `herdr agent prompt <worker>` |
| 6 | 等待并收割 | `harvest.sh --wait` 和 `harvest.sh` |
| 7 | 验证质量 | 运行测试、检查 git diff |
| 8 | 写汇报 | `.fangyang/<dir>/<manager>-report.md` |
| 9 | 进入 idle | 等待主 Agent 收割 |

## Worker 需要做的事

| 步骤 | 说明 |
|------|------|
| 1 | 读任务文件（understanding write scope） |
| 2 | 完成代码改动（仅在 write scope 内） |
| 3 | 运行 acceptance 命令（全部通过） |
| 4 | 检查 git diff（确保没超出 scope） |
| 5 | 输出汇报（格式见 templates/worker-task.md） |
| 6 | 保持 idle（等待 Manager 收割） |

## 文件清单

### 脚本

| 文件 | 用途 |
|------|------|
| `scripts/kaio-ken-orchestrate.sh` | **主编排脚本**（主 Agent 执行） |
| `scripts/fanout.sh` | 启动 Agent 网格（所有层都用） |
| `scripts/harvest.sh` | 收割 Agent 结果（所有层都用） |

### 模板

| 文件 | 用途 |
|------|------|
| `templates/manager-task.md` | Manager 任务模板 |
| `templates/worker-task.md` | Worker 任务模板 |

### 文档

| 文件 | 内容 |
|------|------|
| `KAIO_KEN.md` | 初版方案（已过时） |
| `KAIO_KEN_V2.md` | 增强方案（已过时） |
| `KAIO_KEN_V3.md` | **当前版本**（推荐阅读） |
| `SKILL.md` | 放羊了原始文档 |
| `README.md` | 项目说明 |

## 常见问题

### 主 Agent 相关

**Q: 怎么创建专属 workspace？**
```bash
herdr workspace create --label "界王拳 · 任务名"
```

**Q: 怎么启动 Manager？**
```bash
bash scripts/fanout.sh \
  --count 3 \
  --work "任务描述" \
  --tasks "manager1,manager2,manager3" \
  --workspace "$WS_ID" \
  --cwd "$PWD"
```

**Q: 怎么检查所有 Manager 的状态？**
```bash
herdr agent list --workspace "$WS_ID"
```

### Manager 相关

**Q: 怎么在自己的 Tab 里启动 Worker？**
```bash
bash scripts/fanout.sh \
  --count 3 \
  --work "Manager 的任务" \
  --tasks "worker1,worker2,worker3" \
  --cwd "$PWD"
```

**Q: fanout.sh 后，panes 在哪里？**
A: 直接在你当前 Tab 的右侧被切分成网格。你的 pane 在左侧，Worker panes 在右侧。

**Q: manifest 文件在哪里？**
A: 在 `.fangyang/<kaio-ken-dir>/herdr-*-agents.tsv`

**Q: 怎么派发任务给 Worker？**
```bash
herdr agent prompt <worker-name> "Read .fangyang/.../task.md and execute it..."
```

**Q: 怎么等待所有 Worker 完成？**
```bash
harvest.sh --manifest <path> --wait 1800000
```

**Q: 怎么收割结果（不关闭 panes）？**
```bash
harvest.sh --manifest <path>
# 不加 --close，panes 保留
```

### Worker 相关

**Q: 我能改哪些文件？**
A: 只能改 write scope 里列出的文件。其他都不能改。

**Q: 我改的文件超出 scope 了怎么办？**
A: 停止工作，立即向 Manager 汇报。Manager 会处理。

**Q: 验收命令失败了怎么办？**
A: 继续修改代码直到通过。不要交给 Manager 失败的工作。

**Q: 我完成了，然后呢？**
A: 按模板格式输出汇报。保持 idle，等待 Manager 用 `harvest.sh` 读你的输出。

## 工作流速览

```bash
# ========== 主 Agent 做 ==========

# 1. 创建 workspace
WS_ID=$(herdr workspace create --label "界王拳 · AI应用" | jq -r '.result.workspace_id')

# 2. 启动 Manager 层
bash scripts/kaio-ken-orchestrate.sh \
  --request "开发全栈AI应用" \
  --max-managers 3 \
  --workspace "$WS_ID"

# 3. Loop 管理（自动）
# kaio-ken-orchestrate.sh 会每 30 秒检查一次

# 4. 收割报告（自动）
# 所有 Manager 完成后，自动生成 FINAL_REPORT.md
```

```bash
# ========== Manager 做（在自己的 Tab 里） ==========

# 1. 读任务
cat .fangyang/kaio-ken-*/manager-*.md

# 2. 写 Worker 任务文件
cat > .fangyang/kaio-ken-1730196472/worker-manager-a-1-task.md <<'EOF'
# Worker: manager-a-1 - 实现后端 API
...
EOF

# 3. 启动 Worker
bash /path/to/scripts/fanout.sh \
  --count 3 \
  --tasks "worker-a-1,worker-a-2,worker-a-3" \
  --cwd "$PWD"

# 4. 派发任务
for w in worker-a-1 worker-a-2 worker-a-3; do
  herdr agent prompt "$w" "Read .fangyang/.../task.md..."
done

# 5. 等待并收割
bash /path/to/scripts/harvest.sh --manifest .fangyang/.../herdr-*.tsv --wait 1800000

# 6. 验证质量
git status --short
pnpm test

# 7. 写汇报
cat > .fangyang/kaio-ken-1730196472/manager-a-report.md <<'EOF'
# manager-a 完成汇报
...
EOF
```

```bash
# ========== Worker 做（在自己的 pane 里） ==========

# 1. 完成任务
# 修改代码，实现功能...

# 2. 运行验收命令
pnpm test
pnpm typecheck

# 3. 检查变更
git status --short
git diff --name-only <base-commit>

# 4. 输出汇报
cat <<'EOF'
=== Worker worker-a-1 完成汇报 ===

任务: 实现后端 API
状态: ✅ 完成

## 变更文件
...

## 验收命令结果
✅ pnpm test: 5 tests passed
✅ pnpm typecheck: no errors

## 自检清单
- ☑️ 所有变更都在 write scope 内
- ☑️ 没有修改禁止列表中的文件
- ☑️ 所有验收命令都通过了
EOF
```

## 性能参数

| 参数 | 值 | 说明 |
|------|-----|------|
| 最大 Manager 数 | 6 | 更多的话管理成本上升 |
| 最大 Worker 数/Manager | 6 | 网格布局 2×3 |
| 总 Agent 数上限 | 43 | 1 + 6 + 36 |
| Loop 检查间隔 | 30 秒 | 可配置 |
| Loop 最大次数 | 60 次 | 30 分钟，防止死循环 |
| 单个 harvest 超时 | 1800000 ms | 30 分钟 |

## 快速诊断

| 问题 | 症状 | 排查方式 |
|------|------|---------|
| Manager blocked | 不动了 | `herdr agent read <manager> --source visible` |
| Worker 卡住 | Manager 报错 | `herdr agent read <worker> --source visible` |
| 权限弹窗 | pane 卡住 | `herdr agent send-keys <agent> right enter` |
| 文件冲突 | git status 显示异常 | `git diff --name-only <base>` |
| 测试失败 | Worker 汇报失败 | 让 Worker 重新运行验收命令 |

## 下一步

- [ ] 阅读完整文档 `KAIO_KEN_V3.md`
- [ ] 查看 Manager 任务模板 `templates/manager-task.md`
- [ ] 查看 Worker 任务模板 `templates/worker-task.md`
- [ ] 用一个小项目测试整个流程
- [ ] 根据需要调整 `lib/decompose.sh` 的分片策略

## 相关文件

- **主编排脚本**: `scripts/kaio-ken-orchestrate.sh`
- **完整文档**: `KAIO_KEN_V3.md`
- **Manager 模板**: `templates/manager-task.md`
- **Worker 模板**: `templates/worker-task.md`
- **原始 Skill 文档**: `SKILL.md`
