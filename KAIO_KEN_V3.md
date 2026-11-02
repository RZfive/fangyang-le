# 界王拳模式 V3 —— 放羊了 Skill 的分层并行编排

## 概述

界王拳模式是建立在放羊了 Skill 框架之上的**三层分级 Agent 编排系统**：

```
┌─ 主 Agent ────────────────────────────────────────────┐
│  • 需求深挖                                             │
│  • 任务分解（自动按类型拆分）                           │
│  • 创建专属 workspace                                  │
│  • 启动 Manager 层（用 fanout.sh）                      │
│  • Loop 管理（持续监控所有 Manager）                   │
│  • 最终聚合与交付                                       │
└──────────────────────────────────────────────────────┘
         ↓ fanout.sh（在专属 workspace 里）
┌─────────────────────────────────────────────────────┐
│ 界王拳 Workspace                                      │
├─────────────────────────────────────────────────────┤
│                                                      │
│  Tab 1: Manager-A 的羊圈                             │
│  ├─ 左侧 pane: Manager-A 主控                        │
│  └─ 右侧网格: Worker-A1 ~ Worker-A6 panes           │
│                                                      │
│  Tab 2: Manager-B 的羊圈                             │
│  ├─ 左侧 pane: Manager-B 主控                        │
│  └─ 右侧网格: Worker-B1 ~ Worker-B6 panes           │
│                                                      │
│  Tab 3: Manager-C 的羊圈                             │
│  ├─ 左侧 pane: Manager-C 主控                        │
│  └─ 右侧网格: Worker-C1 ~ Worker-C6 panes           │
│                                                      │
└─────────────────────────────────────────────────────┘
     ↓ (各 Manager 内部用 fanout.sh)
```

## 为什么这样设计

| 设计决策 | 原因 |
|---------|------|
| **专属 workspace** | 隔离界王拳模式的所有 Agent，避免污染其他 workspace；便于用户管理所有相关 tab |
| **一个 Manager 一个 Tab** | 清晰的职权边界；用户可以一眼看出"谁在带哪群羊、干什么活" |
| **Manager 也用 fanout.sh** | 保持一致性和简洁性；复用放羊了已有的 pane 切分、agent 启动、manifest 管理机制 |
| **Worker 在 Manager 的 Tab 内** | 一个 Tab 内完整展示一个 Manager 的全部工作；便于观察 Manager 与其 Worker 的交互 |
| **主 Agent Loop 管理** | 脱离人工监管；自动检测 Manager 状态、处理阻塞、收集报告 |

## 工作流程

### 阶段 1：需求深挖（主 Agent）

主 Agent 与用户充分沟通，获取：
- 最终目标是什么？
- 有哪些约束？（技术栈、时间、已有代码）
- 优先级如何？
- 质量标准是什么？

### 阶段 2：任务分解（主 Agent）

主 Agent 根据**请求类型**自动选择分解策略：

#### 代码项目
- 按模块 / 语言 / 组件分片
- 构建依赖图，避免冲突
- 每个 Manager 分配一个模块或多个独立文件

#### 分析报告
- 按章节 / 主题分片
- 通常无依赖（报告章节独立）
- 每个 Manager 分配一个或多个章节

#### 系统设计
- 按架构层级分片（前端、后端、数据、基础设施）
- 每个 Manager 分配一个子系统

#### 混合任务
- 按依赖关系和冲突规避分片
- 识别关键路径

### 阶段 3：创建专属 Workspace（主 Agent）

```bash
herdr workspace create --label "界王拳 · <任务名>"
```

所有 Manager 和 Worker 都在这个 workspace 里。

### 阶段 4：启动 Manager 层（主 Agent）

用 `fanout.sh` 启动 2-6 个 Manager，**每个 Manager 一个 Tab**：

```bash
bash scripts/fanout.sh \
  --count 3 \
  --work "全栈 AI 应用开发" \
  --tasks "backend,frontend,infra" \
  --workspace "$WORKSPACE_ID" \
  --cwd "$PWD"
```

结果：
- 3 个 Tab 被创建，每个 Tab 里有 1 个 Manager pane（左侧）
- 等待 Manager 的后续操作（他们会在自己的 Tab 里启动 Worker）

### 阶段 5：Manager 工作流（每个 Manager）

在自己的 Tab 里：

1. **读取任务** — 理解要做什么
2. **分解为 Worker** — 2-6 个具体工作包
3. **写 Worker 任务文件** — 到 `.fangyang/<kaio-ken-dir>/`
4. **用 fanout.sh 启动 Worker** — 在自己的 Tab 里创建右侧网格 panes
5. **派发任务** — 用 `herdr agent prompt` 给每个 Worker 派发任务
6. **等待并收割** — `harvest.sh --wait` 等待完成，`harvest.sh`（无 `--close`）收割
7. **验证质量** — 运行测试、检查冲突
8. **写汇报** — `.fangyang/<kaio-ken-dir>/<manager>-report.md`
9. **进入 idle** — 等待主 Agent

**Manager 的 Tab 结构：**
```
Manager-A 的羊圈
├─ 左侧 pane（Manager-A，你在这里运行命令）
└─ 右侧网格 panes（Worker-A1 ~ A6，在这里执行任务）
```

### 阶段 6：Worker 工作流（每个 Worker）

1. **读取任务文件** — 理解 write scope、requirements、acceptance
2. **不要越界** — 严格只改 write scope 内的文件
3. **完成任务** — 修改代码、实现功能
4. **运行验收命令** — 确保所有验收命令通过
5. **检查变更** — `git status --short`，确认没有超出 scope
6. **汇报** — 输出详细的完成报告
7. **保持 idle** — 等待 Manager 收割

### 阶段 7：Loop 管理（主 Agent）

主 Agent 定期检查所有 Manager 的状态：

```bash
每 30 秒检查一次：
  ├─ 所有 Manager 的状态（idle/done/working/blocked/error）
  ├─ 统计完成进度
  ├─ 发现 blocked/error → 尝试介入（读屏幕、分析问题）
  └─ 检查依赖关系（跨 Manager 的接口是否就绪）

当所有 Manager 都完成时：
  → 转到阶段 8（收割 + 质量门）
```


### 阶段 8：收割 + 质量门（主 Agent）

1. **收割所有 Manager** — `harvest.sh`（不带 `--close`，羊圈保留待审）
2. **算报告覆盖率** — 交了 `<manager>-report.md` 的 Manager 数 / Manager 总数，与 `--quality`（默认 0.85）比较
3. **跑验收命令** — `--verify` 给的命令在 `--cwd` 下执行一次，exit 0 才算过
4. **合并成最终报告** — `.fangyang/<kaio-ken-dir>/FINAL_REPORT.md`，并快照一份 `FINAL_REPORT-round-0.md`
5. **判定质量门** — 覆盖率达标 **且** 验收通过 → 交付；否则进入阶段 9

### 阶段 9：Goal 模式自动返工（主 Agent）

质量门不通过时不再直接甩给用户，而是自己再来一轮：

1. **写缺口任务书** — `GOAL-ROUND-N-GAPS.md`，只列「谁没交报告」「verify 失败输出的尾部」，不重发原始需求
2. **派发返工** — 逐个 `herdr agent prompt <manager-slug>` 指向缺口文件 + `SPEC.md`，要求只补自己模块的缺口并重写报告
3. **重新 Loop + 收割 + 重跑 verify** — 与首轮同一套流程
4. **快照** — `FINAL_REPORT-round-N.md`，便于对比轮次差异
5. **轮次上限** — `--max-goal-rounds`（0–10，默认 2）；用尽仍不通过则写 `.decisions.log` 并 `exit 1`，明确「需主 Agent 接管」，不会假装成功

每个决策（启动模式、分解确认、Goal 轮次、升级）都落进 `.decisions.log`，事后可追溯为什么这么判。

### 主 Agent 的职责清单

- [ ] 与用户深入沟通需求（用 `SPEC_QUESTIONS.md` 逐条问，把结论写成 `SPEC.md`）
- [ ] 自动识别请求类型（代码/报告/设计/混合）
- [ ] 创建专属 workspace
- [ ] 用 fanout.sh 启动 Manager 层
- [ ] 派发 Manager 任务文件
- [ ] 启动 Loop 管理循环
- [ ] 定期检查每个 Manager 的进度
- [ ] 处理阻塞和冲突
- [ ] 收集所有 Manager 报告
- [ ] 跑质量门（报告覆盖率 + `--verify`），不通过就 Goal 返工
- [ ] 生成最终汇报（含每轮快照与升级说明）
  --verify "pnpm typecheck && pnpm test && pnpm build" \
  --max-managers 3 \
  --max-goal-rounds 2 \
  --cwd "$PWD"
```

产物都在 `.fangyang/kaio-ken-<ts>/`：`SPEC.md`、`SPEC_QUESTIONS.md`、`.decisions.log`、`.manager-map`、`manager-<slug>-task.md`、`FINAL_REPORT.md` + 每轮 `FINAL_REPORT-round-N.md`、`GOAL-ROUND-N-GAPS.md`。

### 参数速查

| 参数 | 说明 |
|---|---|
| `--spec PATH` | 聊透后的需求规格，作为唯一事实来源；不传则按 request 推断草稿并在报告里标注「未确认维度」 |
| `--verify CMD` | 最终验收命令，exit 0 才算过；不传则质量门只靠报告覆盖率，报告标注「未运行」 |
| `--max-goal-rounds N` | 0–10，质量门不通过时最多自动返工几轮（默认 2） |
| `--quality FLOAT` | 报告覆盖率阈值 0.7–1.0（默认 0.85） |
| `--max-managers` / `--max-workers-per-manager` | 2–6，控制两层宽度 |
| `--auto-mode 0` | 关键决策点先问用户；无 tty 时降级为自动继续并写 `.decisions.log` |

### 主 Agent 的职责清单

- [ ] 与用户深入沟通需求
- [ ] 自动识别请求类型（代码/报告/设计/混合）
- [ ] 创建专属 workspace
- [ ] 用 fanout.sh 启动 Manager 层
- [ ] 派发 Manager 任务文件
- [ ] 启动 Loop 管理循环
- [ ] 定期检查每个 Manager 的进度
- [ ] 处理阻塞和冲突
- [ ] 收集所有 Manager 报告
- [ ] 运行全量验证
- [ ] 生成最终汇报

### Manager 的职责清单

├── scripts/
│   ├── fanout.sh               # 启动 Agent 网格（复用现有；--dbz-tier 走七龙珠命名）
│   ├── harvest.sh              # 收割 Agent 结果（复用现有）
│   ├── ensure-herdr.sh         # 确保 herdr 可用（复用现有）
│   ├── dbz-roster.sh           # 按层级领七龙珠角色 slug（新增）
│   └── kaio-ken-orchestrate.sh # 主编排脚本（SPEC → 分解 → 开圈 → Loop → 质量门 → 返工）
│
├── lib/
│   ├── decompose.sh            # 任务分解库
│   ├── spec.sh                 # SPEC 推断 / 提问清单 / 质量门判据
│   └── dbz-characters.sh       # 三线角色名池
│
- [ ] 读取任务文件和 acceptance 标准
- [ ] 严格在 write scope 内修改文件
- [ ] 完成所有 requirements
- [ ] 运行所有 acceptance 命令并通过
- [ ] 检查没有超出 scope
- [ ] 输出详细汇报
- [ ] 保持 idle，等待 Manager 收割

---

## 文件结构

```
fangyang-le/
├── SKILL.md                    # 放羊了的原始文档
├── KAIO_KEN.md                 # 界王拳 V1（初版方案）
├── KAIO_KEN_V2.md              # 界王拳 V2（增强方案）
├── KAIO_KEN_V3.md              # 界王拳 V3（本文档）
│
├── scripts/
│   ├── fanout.sh               # 启动 Agent 网格（复用现有）
│   ├── harvest.sh              # 收割 Agent 结果（复用现有）
│   ├── ensure-herdr.sh         # 确保 herdr 可用（复用现有）
│   └── kaio-ken-orchestrate.sh # 主编排脚本（新增）
│
├── lib/
│   └── decompose.sh            # 任务分解库（新增）
│
├── templates/
│   ├── task.md                 # 原始 Worker 任务模板（复用）
│   ├── manager-task.md         # Manager 任务模板（新增/改进）
│   └── worker-task.md          # Worker 任务模板（新增）
│
└── tests/
    └── run-tests.sh            # 测试套件（复用）
```

---

## 关键设计原则

### 1. 严格的 Workspace 隔离

- 界王拳创建**专属 workspace**
- 所有 Manager 和 Worker 都在这个 workspace 里
- 其他 workspace 完全不受影响

### 2. 清晰的层级结构

- **主 Agent** — 总指挥，负责编排和管理
- **Manager** — 中层指挥，负责分片和质检
- **Worker** — 执行者，专注完成分配的具体任务

### 3. 一致的工具链

- 都用 **fanout.sh** 启动下一层 Agent
- 都用 **harvest.sh** 收割结果
- 都用 **herdr agent** 命令派发和监控

### 4. 不超越边界

- Worker **严格** 只在 write scope 内修改
- Manager **只负责** 自己分配的 Manager 任务
- 主 Agent **不直接修改** 代码，只协调和验证

### 5. 可观测性

- 每一层都有明确的汇报
- 每一层的 panes/tabs 都可视
- 用户可以随时查看任何 Agent 的现场

### 6. 自救机制

- Worker 遇到问题 → 向 Manager 汇报
- Manager 遇到问题 → 向主 Agent 汇报
- 主 Agent 可以干预（读屏幕、重新分配、提示用户）

---

## 性能指标

### 并行度

| 层级 | 数量 | 说明 |
|-----|------|------|
| 主 Agent | 1 | 全局协调 |
| Manager | 2-6 | 中层指挥 |
| Worker | 2-6 x Manager | 最多 36 个并行执行单元 |

### 时间复杂度

- **单 Agent 线性执行**：O(n)，其中 n 是任务数
- **界王拳分层执行**：O(n / Manager 数)，假设任务均衡分配

### 容错

- **单 Agent 失败** → 全部重做：1 个失败 = 全部失败
- **界王拳一个 Manager 失败** → 只重做该 Manager：隔离失败

---

## 常见场景

### 场景 1：开发全栈应用

```
需求：开发一个 AI 聊天应用

主 Agent 分解为：
├─ Manager-Backend: Python FastAPI + LLM 集成
├─ Manager-Frontend: Next.js UI + 实时通信
├─ Manager-Infra: Docker + 部署 + 监控

每个 Manager 再分配 Worker：
├─ Manager-Backend
│  ├─ Worker-1: API 端点实现
│  ├─ Worker-2: LLM 调用集成
│  └─ Worker-3: 数据库 schema
├─ Manager-Frontend
│  ├─ Worker-1: 组件库
│  ├─ Worker-2: 聊天 UI
│  └─ Worker-3: 实时通信（WebSocket）
└─ Manager-Infra
   ├─ Worker-1: Docker 编排
   └─ Worker-2: CI/CD Pipeline

预期并行度：3 Manager × 3 Worker ≈ 9 个并行单元
预期加速：相比单 Agent 线性执行，快 3-6 倍
```

### 场景 2：编写技术调研报告

```
需求：评估 3 个向量数据库方案

主 Agent 分解为：
├─ Manager-Pinecone: Pinecone 调研
├─ Manager-Weaviate: Weaviate 调研
└─ Manager-Milvus: Milvus 调研

每个 Manager 的 Worker：
├─ Manager-Pinecone
│  ├─ Worker-1: 功能对标
│  ├─ Worker-2: 性能测试
│  ├─ Worker-3: 成本分析
│  └─ Worker-4: 案例调研
├─ ... (Weaviate、Milvus 类似)

预期并行度：3 Manager × 4 Worker ≈ 12 个并行单元
预期加速：快 6-10 倍
```

### 场景 3：系统设计

```
需求：设计微服务架构

主 Agent 分解为：
├─ Manager-Frontend: API Gateway + CDN
├─ Manager-Services: 微服务核心（用户、订单、支付）
├─ Manager-Data: 数据层（数据库、缓存、消息队列）
└─ Manager-Infra: 基础设施（监控、日志、容错）

每个 Manager 的 Worker：
├─ Manager-Services
│  ├─ Worker-1: 用户服务设计
│  ├─ Worker-2: 订单服务设计
│  └─ Worker-3: 支付服务设计

预期并行度：4 Manager × 3 Worker ≈ 12 个并行单元
预期加速：快 4-8 倍
```

---

## 故障处理

### 问题 1：Manager 一直 blocked

**症状**：某个 Manager 不动了

**排查**：
```bash
# 主 Agent 执行
herdr agent read <manager-name> --source visible
```

**常见原因**：
- 权限弹窗（Always allow）
- Worker 启动失败
- 依赖 Manager 还没完成

**解决**：
- 如果是权限弹窗 → `send-keys` 处理
- 如果是 Worker 失败 → 读 Worker 输出诊断
- 如果是依赖 → 等待或重新分配

### 问题 2：Worker 越界（改了不该改的文件）

**症状**：Manager 报告中发现无关文件被修改

**处理**：
```bash
# 主 Agent 或 Manager 执行
git checkout -- <unrelated-files>  # 恢复
# 或重新分配任务给其他 Manager/Worker
```

### 问题 3：跨 Manager 依赖冲突

**症状**：Manager-A 依赖 Manager-B 的输出，但 B 还没完成

**设计原则**：
- 阶段 7（Loop 管理）会追踪依赖关系
- 优先完成被依赖的 Manager
- 如果有循环依赖 → 重新分解任务

### 问题 4：质量检查失败

**症状**：最终验证（pnpm test、cargo test 等）失败

**处理**：
1. 定位失败在哪个 Manager 的范围内
2. 该 Manager 重新分配 Worker 修复
3. 重新收割该 Manager 的结果
4. 重新运行全量验证

---

## 下一步

1. **测试最小化流程** — 用一个小项目验证整个工作流
2. **调优分片算法** — 根据实际任务优化 decompose.sh
3. **增强自救逻辑** — 更智能的 blocked 处理和重试策略
4. **集成质量检查** — 自动识别项目类型并运行对应的验收命令
5. **成本控制** — 添加 token 预算管理，避免成本爆炸

---

## 总结

界王拳模式是对放羊了 Skill 的自然延伸：

| 维度 | 放羊了 | 界王拳 |
|-----|-------|-------|
| **Agent 层级** | 1 层（主控 + Worker） | 3 层（主 Agent + Manager + Worker） |
| **并行度** | 最多 6 个 Agent | 最多 36 个 Agent（6 × 6） |
| **工作流** | 主控手动派发 + 等待 | 主 Agent 自动管理 + Loop 循环 |
| **容错** | 单点失败影响全部 | 故障隔离，只重做失败单元 |
| **可观测性** | 一个 Tab 里看全部 | 分散的多个 Tab，结构清晰 |
| **适用场景** | 2-6 个独立任务 | 10-36 个任务 + 复杂分片 |

当一个项目足够复杂、任务足够多、依赖足够清晰时，界王拳模式会显著加快开发速度，同时保持质量和可控性。
