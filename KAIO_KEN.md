# 界王拳模式（Kaio-Ken Mode）

放羊了 skill 的分层并行编排扩展。

## 核心思想

```
主 Agent（用户对话层）
    ↓ 需求深挖 + 任务分解
界王拳专属 workspace（独立隔离）
    ↓ fanout.sh 启动 2-6 个 Manager
Manager-A Tab（一个羊圈）
    ├── Manager-A pane（主控）
    └── Worker A1-A6 panes（网格）
Manager-B Tab（一个羊圈）
    ├── Manager-B pane（主控）
    └── Worker B1-B6 panes（网格）
...
    ↓ 主 Agent 持续 Loop 管理
最终聚合 + 验证 + 交付
```

## 与普通放羊的区别

| 维度 | 普通放羊 | 界王拳模式 |
|------|---------|-----------|
| **层级** | 单层（主控 + Worker） | 三层（主 + Manager + Worker） |
| **workspace** | 主控自己的 workspace | 专属新建 workspace |
| **Tab 布局** | 一个羊圈 tab（所有 Worker） | N 个羊圈 tab（每个 Manager 一个） |
| **启动方式** | 主控用 fanout.sh 一次性启动 | 主控启动 Manager，Manager 再启动 Worker |
| **管理模式** | 主控直接管理 Worker | 主控管理 Manager，Manager 管理 Worker |
| **适用场景** | 2-6 个独立任务 | 大型复杂任务（最多 6×6=36 个 Worker） |

## 什么时候用

**适合：**
- 超大型任务（需要 10+ 个独立工作单元）
- 任务有明确的二级分层（如：前端/后端/数据，每层内又有多个模块）
- 需要 Manager 层做进度监控、冲突调解
- 用户明确要求"界王拳" / "多层并行" / "管理层"

**不适合：**
- 任务只需 2-6 个 Agent（直接用普通放羊）
- 任务高度串行、无法二级拆分
- 用户要求简单快速（界王拳启动开销更大）

## 铁律

1. **专属 workspace**：界王拳必须新建独立 workspace，名字 `界王拳 · <任务名>`
2. **一个 Manager = 一个 Tab**：Manager 在该 tab 的第一个 pane（主控位），Worker 在同 tab 的网格 panes
3. **Manager 用放羊启动 Worker**：不能用 `spawn_subagents`，必须用 `fanout.sh`
4. **主 Agent 不直接操作 Worker**：只管理 Manager，Manager 管理 Worker
5. **状态追踪**：主 Agent 通过 manifest 文件追踪每个 Manager 的状态
6. **收割分层**：Manager 先 harvest 自己的 Worker，主 Agent 再 harvest 所有 Manager

## 文件结构

```
放羊了/
├── scripts/
│   ├── fanout.sh              # 已有（启动羊群）
│   ├── harvest.sh             # 已有（收割结果）
│   ├── kaio-ken-orchestrate.sh  # 新增（主 Agent 编排入口）
│   └── ensure-herdr.sh        # 已有（环境检查）
├── lib/
│   ├── decompose.sh           # 新增（任务分解算法）
│   ├── state-mgmt.sh          # 新增（状态管理）
│   └── conflict-detect.sh     # 新增（冲突检测）
├── templates/
│   ├── task.md                # 已有（Worker 任务模板）
│   └── manager-task.md        # 新增（Manager 任务模板）
├── SKILL.md                   # 已有（普通放羊文档）
└── KAIO_KEN.md                # 本文件（界王拳文档）
```

## 快速使用

```bash
# 在用户对话的主 Agent 里执行
bash "$SKILL_DIR/scripts/kaio-ken-orchestrate.sh" \
  --request "开发全栈 AI 聊天应用（前端 React + 后端 FastAPI + 数据库 + 部署文档）" \
  --max-managers 4 \
  --cwd "$PWD"
```

## 工作流详解

### 阶段 1：需求深挖（主 Agent）

主 Agent 与用户对话，明确：
- 最终目标是什么？
- 有哪些约束？（技术栈、时间、已有代码）
- 如何验收？（测试、构建、运行）

### 阶段 2：任务分解（主 Agent）

自动识别任务类型并分解：

**代码项目** → 按模块/文件树分片
```
前端模块 (Manager-A)
  ├── 登录页 (Worker-A1)
  ├── 聊天页 (Worker-A2)
  └── 设置页 (Worker-A3)
后端模块 (Manager-B)
  ├── API 路由 (Worker-B1)
  ├── 数据模型 (Worker-B2)
  └── WebSocket (Worker-B3)
```

**分析报告** → 按章节/主题分片
```
市场调研 (Manager-A)
  ├── 竞品分析 (Worker-A1)
  ├── 用户画像 (Worker-A2)
技术方案 (Manager-B)
  ├── 架构设计 (Worker-B1)
  ├── 技术选型 (Worker-B2)
```

**系统设计** → 按组件/层级分片
```
前端层 (Manager-A)
  ├── UI 组件库 (Worker-A1)
  ├── 状态管理 (Worker-A2)
后端层 (Manager-B)
  ├── API 网关 (Worker-B1)
  ├── 业务逻辑 (Worker-B2)
```

分解时自动运行**冲突检测**：
- 同一文件不能被多个 Worker 同时修改
- 跨 Manager 的依赖关系需要提前定义接口

### 阶段 3：启动 Manager（主 Agent）

```bash
# 1. 创建专属 workspace
WORKSPACE_ID=$(herdr workspace create \
  --label "界王拳 · $WORK_NAME" | jq -r '.result.workspace_id')

# 2. 在该 workspace 为每个 Manager 创建任务文件
mkdir -p "$PWD/.fangyang/kaio-ken-$TIMESTAMP"
for manager in manager-a manager-b manager-c; do
  cat > "$PWD/.fangyang/kaio-ken-$TIMESTAMP/$manager-task.md" <<EOF
# Manager: $manager

你是一个 Manager Agent，负责管理 2-6 个 Worker。

## 你的职责
1. 读取下面的任务范围，理解要做什么
2. 把任务进一步分解为 2-6 个具体工作包（每个 Worker 一个）
3. 为每个 Worker 写任务文件到 .fangyang/kaio-ken-$TIMESTAMP/
4. 在你自己的 tab 里用 fanout.sh 启动 Worker：
   bash "$SKILL_DIR/scripts/fanout.sh" \\
     --count <N> \\
     --work "$manager 的工作" \\
     --tasks <逗号分隔的任务名> \\
     --cwd "$PWD"
5. 等待所有 Worker 完成，用 harvest.sh 收割结果
6. 验证质量（运行测试、检查冲突）
7. 汇报给主 Agent（写入 .fangyang/kaio-ken-$TIMESTAMP/$manager-report.md）

## 你的任务范围
...（主 Agent 填充具体范围）

## 依赖接口
...（跨 Manager 的 API 契约）

## 验收标准
...

Do not commit. 完成后写 report，然后进入 idle 等主 Agent 收割。
EOF
done

# 3. 用 fanout.sh 启动所有 Manager（每个 Manager 一个 tab）
bash "$SKILL_DIR/scripts/fanout.sh" \
  --count $MANAGER_COUNT \
  --kind auto \
  --work "$WORK_NAME" \
  --tasks "manager-a,manager-b,manager-c" \
  --workspace "$WORKSPACE_ID" \
  --cwd "$PWD" \
  --tasks-dir "$PWD/.fangyang/kaio-ken-$TIMESTAMP"

# 此时创建了 N 个 tab，每个 tab 只有一个 pane（Manager 主控位）
# Manager 还未启动 Worker
```

### 阶段 4：Manager 启动 Worker（自动）

每个 Manager 醒来后（在自己的 tab 的主控 pane 里）：

```bash
# Manager-A 读取自己的任务文件
cat .fangyang/kaio-ken-$TIMESTAMP/manager-a-task.md

# Manager-A 分解任务，写 Worker 任务文件
cat > .fangyang/kaio-ken-$TIMESTAMP/worker-a1-task.md <<EOF
# Worker: A1 - 登录页

Repository: $PWD
Base commit: $(git rev-parse HEAD). Do not commit.

## Write scope (ONLY these files)
- src/pages/Login.tsx
- src/components/LoginForm.tsx

## Read first
- src/types/user.ts
- src/api/auth.ts

## Goal
实现用户登录页面...

## Acceptance
\`\`\`bash
pnpm test src/pages/Login.test.tsx
pnpm typecheck
\`\`\`
EOF

# Manager-A 在自己的 tab 里用 fanout.sh 启动 Worker
# 注意：不传 --workspace（默认当前 $HERDR_WORKSPACE_ID，就是界王拳专属 workspace）
bash "$SKILL_DIR/scripts/fanout.sh" \
  --count 3 \
  --kind auto \
  --work "前端模块" \
  --tasks "worker-a1,worker-a2,worker-a3" \
  --cwd "$PWD" \
  --tasks-dir "$PWD/.fangyang/kaio-ken-$TIMESTAMP"

# fanout.sh 会在 Manager-A 的 tab 里切分 panes，形成：
# Manager-A tab
#   ├── Manager-A pane（主控，左侧）
#   └── Worker A1-A3 panes（网格，右侧）

# Manager-A 派发任务给所有 Worker
for worker in worker-a1 worker-a2 worker-a3; do
  herdr agent prompt "$worker" \
    "Read .fangyang/kaio-ken-$TIMESTAMP/$worker-task.md and execute it exactly."
done

# Manager-A 等待所有 Worker 完成
bash "$SKILL_DIR/scripts/harvest.sh" \
  --manifest .fangyang/kaio-ken-$TIMESTAMP/herdr-前端模块-agents.tsv \
  --wait 1800000

# Manager-A 验证质量
pnpm test
pnpm typecheck

# Manager-A 写汇报
cat > .fangyang/kaio-ken-$TIMESTAMP/manager-a-report.md <<EOF
# Manager-A 完成汇报

## 完成情况
- Worker-A1: ✅ 登录页完成，2 个测试通过
- Worker-A2: ✅ 聊天页完成，3 个测试通过
- Worker-A3: ⚠️  设置页部分完成（缺少权限检查）

## 变更文件
\`\`\`
git diff --name-only
\`\`\`

## 遗留问题
- 设置页的权限检查需要后端 API 完成后补充

## 质量检查
- 测试：5/6 通过
- TypeScript：0 errors
- 冲突：无
EOF

# Manager-A 进入 idle，等主 Agent 收割
```

### 阶段 5：Loop 管理（主 Agent）

主 Agent 持续监控所有 Manager：

```bash
# 每 30 秒检查一次
while true; do
  # 读取所有 Manager 的状态
  herdr agent list | jq -r '.result.agents[] | select(.name | startswith("manager-"))'
  
  # 检查是否有 blocked/failed 的 Manager
  BLOCKED=$(herdr agent list | jq -r '.result.agents[] | 
    select(.name | startswith("manager-")) | 
    select(.agent_status == "blocked" or .agent_status == "error") | 
    .name')
  
  if [[ -n "$BLOCKED" ]]; then
    # 读取被阻塞 Manager 的屏幕
    herdr agent read "$BLOCKED" --source visible
    
    # 根据问题类型决策
    # 1. 如果是权限问题 → send-keys
    # 2. 如果是依赖未就绪 → 提示等待其他 Manager
    # 3. 如果是任务冲突 → 重新分配
  fi
  
  # 检查是否全部完成
  ALL_DONE=$(herdr agent list | jq -r '.result.agents[] | 
    select(.name | startswith("manager-")) | 
    select(.agent_status == "idle" or .agent_status == "done") | 
    .name' | wc -l)
  
  if (( ALL_DONE == MANAGER_COUNT )); then
    echo "所有 Manager 完成"
    break
  fi
  
  sleep 30
done
```

### 阶段 6：聚合验证（主 Agent）

```bash
# 1. 收割所有 Manager 的报告
for manager in manager-a manager-b manager-c; do
  cat ".fangyang/kaio-ken-$TIMESTAMP/$manager-report.md"
done

# 2. 统一跑全量验证
git status --short
pnpm test
pnpm typecheck
pnpm build

# 3. 检查跨 Manager 的集成点
# - API 接口是否匹配？
# - 数据模型是否一致？
# - 依赖关系是否正确？

# 4. 汇总结果给用户
cat > .fangyang/kaio-ken-$TIMESTAMP/FINAL_REPORT.md <<EOF
# 界王拳任务完成汇报

## 总体情况
- Manager 数量: $MANAGER_COUNT
- Worker 数量: $TOTAL_WORKERS
- 总耗时: $ELAPSED_TIME

## 各 Manager 完成情况
...

## 最终验证结果
- 测试: 45/47 通过
- TypeScript: 0 errors
- 构建: 成功

## 遗留问题
...

## 下一步建议
...
EOF
```

## 状态管理

每个 Manager 的状态存储在 manifest 文件：

```tsv
# .fangyang/kaio-ken-$TIMESTAMP/manager-a-manifest.tsv
#status=running
#started_at=1698765432
#last_heartbeat=1698765500
#worker_count=3
name    pane    tab    workspace    status
worker-a1    w1:pA    w1:t2    w1    working
worker-a2    w1:pB    w1:t2    w1    done
worker-a3    w1:pC    w1:t2    w1    blocked
```

主 Agent 通过读取这些 manifest 了解整体进度。

## Tab 布局示例

**界王拳 workspace：`w99`**

```
Tab 列表：
1. [w99:t1] Manager-A 的羊圈 · 前端模块
   - Pane 1 (w99:pA): Manager-A（主控）
   - Pane 2-7 (w99:pB-pG): Worker A1-A6（网格）

2. [w99:t2] Manager-B 的羊圈 · 后端模块
   - Pane 1 (w99:pH): Manager-B（主控）
   - Pane 2-5 (w99:pI-pL): Worker B1-B4（网格）

3. [w99:t3] Manager-C 的羊圈 · 数据模块
   - Pane 1 (w99:pM): Manager-C（主控）
   - Pane 2-4 (w99:pN-pP): Worker C1-C3（网格）
```

用户在 herdr 里看到的就是 3 个 tab，每个 tab 就是一个管理单元。

## 容错机制

### Manager 级别
- Manager blocked → 主 Agent 介入（send-keys / 重新分配）
- Manager failed → 重启 Manager（最多 1 次）
- Manager 超时 → 主 Agent 接管该 Manager 的任务

### Worker 级别
- Worker blocked → Manager 介入（send-keys）
- Worker failed → Manager 重启 Worker（最多 2 次）
- Worker 超时 → Manager 重新分配给其他 Worker

## 对比：普通放羊 vs 界王拳

**场景：开发一个 6 模块的项目**

### 普通放羊（单层）
```
主控的羊圈 tab（w1:t1）
  ├── Worker-1 (模块A)
  ├── Worker-2 (模块B)
  ├── Worker-3 (模块C)
  ├── Worker-4 (模块D)
  ├── Worker-5 (模块E)
  └── Worker-6 (模块F)
```
- 所有 Worker 在一个 tab 里
- 主控直接管理 6 个 Worker
- 适合 6 个独立任务

### 界王拳（三层）
```
界王拳 workspace (w99)
  Tab 1: Manager-A 的羊圈（前端）
    ├── Manager-A
    ├── Worker-A1 (模块A)
    └── Worker-A2 (模块B)
  
  Tab 2: Manager-B 的羊圈（后端）
    ├── Manager-B
    ├── Worker-B1 (模块C)
    └── Worker-B2 (模块D)
  
  Tab 3: Manager-C 的羊圈（基础设施）
    ├── Manager-C
    ├── Worker-C1 (模块E)
    └── Worker-C2 (模块F)
```
- 3 个 Manager tab（前端/后端/基础设施）
- 每个 Manager 管理 2 个 Worker
- 主控管理 3 个 Manager
- 适合有明确分层的大型任务

## 实现路线图

### Week 1：基础框架
- ✅ kaio-ken-orchestrate.sh（主入口）
- ✅ 任务分解逻辑（按类型识别）
- ✅ 专属 workspace 创建
- ✅ Manager 启动流程

### Week 2：Manager 逻辑
- ✅ Manager 任务模板
- ✅ Manager 内部再次调用 fanout.sh
- ✅ Worker 任务文件生成
- ✅ 状态追踪机制

### Week 3：Loop 管理 + 容错
- ✅ 主 Agent 心跳检查
- ✅ 阻塞/失败处理
- ✅ 分层 harvest
- ✅ 最终验证流程

## 下一步

选择一个实现优先级，我立即开始编码：

1. **快速验证**：实现 Week 1（能跑起来，手动管理）
2. **完整闭环**：实现 Week 1-2（Manager 能自动启动 Worker）
3. **生产就绪**：实现全部 3 周（包含自动容错）

或者你有其他优先级？
