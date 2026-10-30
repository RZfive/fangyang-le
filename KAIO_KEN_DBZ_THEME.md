───────────────────────────────────────────────────────
🥋 界王拳模式完全指南 — 七龙珠角色名系统
───────────────────────────────────────────────────────

# 界王拳模式使用指南

## 🌟 什么是界王拳模式？

界王拳是七龙珠中孙悟空学到的必杀技：**在短时间内四倍提升战斗力**。

在这里，界王拳模式把这个概念应用到 Agent 分工：

- **🥇 一线主角**（主 Agent，如"孙悟空"）：掌控全局，决策指挥
- **🥈 二线战士**（Manager Agent 2-6 个，如"克林""天津饭"）：战术执行，分头作战
- **🥉 三线小兵**（Worker Agent 每层 2-6 个，如"龟仙人弟子"）：前线执行，完成具体任务

这样设计的好处：
- **并行度高**：最多 36 个 Agent（1 主 + 6 Manager + 6×6 Worker）同时工作
- **层级清晰**：每级有明确的职责边界，避免混乱
- **容错能力强**：一个 Worker 出错只影响自己，不会波及整个团队
- **易于观察**：用户在 Herdr workspace 里可以看到清晰的组织结构

---

## 🎯 快速开始

### 第一步：启动界王拳模式

```bash
bash scripts/kaio-ken-orchestrate.sh \
  --request "开发一个全栈 AI 聊天应用" \
  --max-managers 4 \
  --max-workers-per-manager 3 \
  --cwd "$PWD"
```

### 第二步：看什么发生了

主脚本会：

1. **📝 需求深挖**：理解用户需求，确定最终目标
2. **🔪 任务分解**：按任务类型（代码/报告/设计）分解为多个 Manager 任务
3. **🗺️ 创建专属 workspace**：`界王拳 · 用户需求`
4. **👥 启动 Manager 队伍**：用 `fanout.sh` 在该 workspace 内启动 2-6 个 Manager
   - 每个 Manager 占一个 Tab（Tab 标签：`克林的羊圈 · AI 聊天`之类）
   - 每个 Tab 内，Manager 是主控 pane，右侧是 Worker 网格
5. **📢 派发任务**：告诉每个 Manager 你要做什么
6. **🔄 Loop 管理**：主 Agent 持续监控所有 Manager，检查进度、处理问题
7. **📊 聚合交付**：所有完成后，聚合报告并交付给用户

### 第三步：观察过程

打开 Herdr 应用，选择 `界王拳 · 用户需求` workspace，你会看到：

```
Tab 1: 克林的羊圈 · AI 聊天
  ├─ 左侧 pane: 克林（Manager，在这里主控）
  └─ 右侧网格: Worker-1, Worker-2, Worker-3
     （都在实时工作）

Tab 2: 天津饭的羊圈 · AI 聊天
  ├─ 左侧 pane: 天津饭（Manager）
  └─ 右侧网格: Worker-1, Worker-2, Worker-3, ...

Tab 3: ...
```

每个 Tab 内的结构完全相同，彼此独立。这就是**分层编排**的可视化体现。

---

## 👥 七龙珠角色分配

### 🥇 一线主角（主 Agent）

这些是系列的绝对主角，决定全局走向：

| 角色 | 特点 |
|------|------|
| **孙悟空** | 大主角，能量无限，战斗直觉超强 |
| **贝吉塔** | 赛亚王子，力量强大，威严十足 |
| **孙悟饭** | 新生代主角，潜力巨大 |
| **孙悟天** | 天赋惊人 |
| **特兰克斯** | 未来战士，使命感强 |
| **舞空术大师** | 龟仙人，经验丰富 |
| **比鲁斯** | 破坏神，力量无上 |

**主 Agent 的职责**：
- 与用户深度沟通，理解完整需求
- 分解任务给 Manager 们
- 持续管理和协调 Manager 层
- 最终验收所有工作成果

### 🥈 二线战士（Manager Agent 2-6 个）

这些是能独立指挥一支队伍的配角：

| 角色 | 特点 | 适合的 Manager 角色 |
|------|------|---|
| **克林** | 最忠实的配角，执行力强 | 前端开发 Manager |
| **天津饭** | 战术大师，组织能力强 | 后端开发 Manager |
| **雅木茶** | 游侠，独立性强 | 数据库 Manager |
| **乌龙** | 聪慧，见多识广 | 测试/工具 Manager |
| **布尔玛** | 天才发明家，技术高超 | 基础设施 Manager |
| **兰奇** | 务实派 | 文档/部署 Manager |
| **17号** | 完美人造人，稳定高效 | 集成测试 Manager |
| **18号** | 精准执行 | 性能优化 Manager |

**Manager 的职责**：
- 接收主 Agent 分配的任务范围
- 进一步分解成 2-6 个 Worker 任务
- 在自己的 Tab 里用 fanout.sh 启动 Worker
- 等待所有 Worker 完成
- 验证质量，汇报给主 Agent

### 🥉 三线小兵（Worker 每层 2-6 个）

这些是大量的各类小角色：

| 角色 | 特点 |
|------|------|
| **龟仙人弟子甲/乙** | 基础工作者 |
| **红丝带军队兵甲/乙/丙/丁** | 执行力强 |
| **亚奇罗贝** | 小助手 |
| **基纽卫队甲/乙/丙/丁** | 团队执行 |
| **众多小魔人** | 具体任务实施 |

**Worker 的职责**：
- 接收 Manager 分配的具体任务
- 严格在自己的 write scope 内工作
- 按要求完成功能/文档/测试
- 运行验收命令
- 汇报完成情况

---

## 📋 任务类型与分片策略

### 代码项目 (Code)

**识别**：包含"开发" "实现" "代码" "项目" "API" 等关键词

**分片方式**：按**模块/层级**分片
```
主任务：开发 AI 聊天应用
│
├─ Manager 克林：前端（React 页面、UI 组件）
│  ├─ Worker: 聊天界面
│  ├─ Worker: 消息组件
│  └─ Worker: 设置页
│
├─ Manager 天津饭：后端（Node.js/Python API）
│  ├─ Worker: 认证系统
│  ├─ Worker: 聊天 API
│  └─ Worker: 数据处理
│
└─ Manager 乌龙：数据库 + 测试
   ├─ Worker: 数据库迁移
   ├─ Worker: 单元测试
   └─ Worker: 集成测试
```

**避免冲突**：同一个文件只能被一个 Worker 拥有

### 分析报告 (Report)

**识别**：包含"报告" "分析" "调研" "总结" "文档" 等关键词

**分片方式**：按**章节/主题**分片
```
主任务：写 AI 行业调研报告（3000 字）
│
├─ Manager 克林：历史与现状（1000 字）
│  ├─ Worker: 写 AI 发展历史 (300 字)
│  ├─ Worker: 写当前应用现状 (400 字)
│  └─ Worker: 写市场规模 (300 字)
│
├─ Manager 天津饭：技术趋势（1000 字）
│  ├─ Worker: 写大模型进展 (350 字)
│  ├─ Worker: 写成本与效率 (350 字)
│  └─ Worker: 写应用模式 (300 字)
│
└─ Manager 乌龙：未来展望 + 编辑（1000 字）
   ├─ Worker: 写挑战与机遇 (400 字)
   ├─ Worker: 写建议 (300 字)
   └─ Worker: 全文审校、排版、最终统稿 (300 字)
```

**避免冲突**：每个 Worker 写独立的章节，由编辑 Worker 负责协调

### 系统设计 (Design)

**识别**：包含"设计" "架构" "方案" "蓝图" "PRD" 等关键词

**分片方式**：按**组件/层级**分片
```
主任务：设计分布式消息队列系统
│
├─ Manager 克林：前端消费端
│  ├─ Worker: 消费者库设计
│  └─ Worker: 监控面板设计
│
├─ Manager 天津饭：核心引擎
│  ├─ Worker: 队列存储设计
│  ├─ Worker: 分片策略设计
│  └─ Worker: 副本机制设计
│
└─ Manager 乌龙：运维与兼容
   ├─ Worker: 高可用方案
   ├─ Worker: 迁移路径
   └─ Worker: 监控告警
```

**避免冲突**：确保各组件的接口定义清晰，提前交换 API 契约

---

## 🔄 工作流程详解

### 主 Agent 的六阶段工作

```
1️⃣ 需求深挖
   ↓ 与用户对话，列出所有需求点
   ↓

2️⃣ 任务分解
   ↓ 识别类型 → 按规则分片 → 检查冲突
   ↓

3️⃣ 创建专属 workspace
   ↓ 界王拳 · 用户需求
   ↓

4️⃣ 启动 Manager 队伍
   ↓ 用 fanout.sh 启动 N 个 Manager（每个 Manager 一个 Tab）
   ↓

5️⃣ 派发任务给 Manager
   ↓ 每个 Manager 收到一份明确的任务文件
   ↓

6️⃣ Loop 管理 & 聚合交付
   ↓ 主 Agent 持续检查 Manager 状态
   ↓ 当所有 Manager 完成时，收割报告
   ↓ 聚合产出，交付用户
```

### Manager 的七步工作

```
1️⃣ 理解分配的任务
   ↓ 范围是什么？依赖是什么？
   ↓

2️⃣ 分解任务成 Worker 包
   ↓ 2-6 个独立的 Worker 任务
   ↓

3️⃣ 创建 Worker 任务文件
   ↓ 写进 .fangyang/kaio-ken-*/ 目录
   ↓

4️⃣ 在自己 Tab 里启动 Worker
   ↓ fanout.sh --workspace $HERDR_WORKSPACE_ID
   ↓ Worker 会在你的 Tab 右侧作为网格 panes
   ↓

5️⃣ 派发任务给 Worker
   ↓ 每个 Worker 读取自己的任务文件
   ↓

6️⃣ 等待 Worker 完成 & 收割
   ↓ harvest.sh（不要 --close，留下 panes）
   ↓

7️⃣ 质量检查 & 汇报
   ↓ 运行验收命令
   ↓ 写 Manager 报告文件
   ↓ 进入 idle，等待主 Agent 收割
```

### Worker 的简单步骤

```
1️⃣ 读任务文件，理解目标
   ↓

2️⃣ 在 write scope 内工作
   ↓

3️⃣ 运行验收命令，确保通过
   ↓

4️⃣ 检查范围，确保没有越界
   ↓

5️⃣ 输出完成报告
   ↓

6️⃣ 保持 idle，等待 Manager 收割
```

---

## 🎪 可视化架构

### Workspace 全景

```
╔═══════════════════════════════════════════════════════════════╗
║                    界王拳 workspace                          ║
║                   (专属于此任务)                              ║
╠═══════════════════════════════════════════════════════════════╣
║                                                               ║
║ ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
║ │ 克林的羊圈      │  │ 天津饭的羊圈    │  │ 乌龙的羊圈      │
║ │ · AI 聊天       │  │ · AI 聊天       │  │ · AI 聊天       │
║ ├─────────────────┤  ├─────────────────┤  ├─────────────────┤
║ │ 克林 (主控)     │  │ 天津饭 (主控)   │  │ 乌龙 (主控)     │
║ │  \              │  │  \              │  │  \              │
║ │   ├─W1 W2      │  │   ├─W1 W2 W3   │  │   ├─W1 W2      │
║ │   └─W3 W4      │  │   └─W4 W5 W6   │  │   └─W3         │
║ │                 │  │                 │  │                 │
║ │ (Worker 网格)   │  │ (Worker 网格)   │  │ (Worker 网格)   │
║ └─────────────────┘  └─────────────────┘  └─────────────────┘
║        Tab 1               Tab 2               Tab 3         ║
║     (前端 Manager)    (后端 Manager)    (测试 Manager)      ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
```

### Tab 内部结构（以克林的羊圈为例）

```
╔═════════════════════════════════════════════════════════════╗
║         克林的羊圈 · AI 聊天 (Manager 克林的 Tab)          ║
╠═════════════════════════════════════════════════════════════╣
║                                                             ║
║ ┌──────────────┬──────────────┬──────────────┐            ║
║ │              │              │              │            ║
║ │  克林主控    │  Worker-1    │  Worker-2    │            ║
║ │  (pane)      │  (W1)        │  (W2)        │            ║
║ │              │              │              │            ║
║ │  在这里运行  │  实时执行    │  实时执行    │            ║
║ │  fanout.sh   │  聊天界面    │  消息组件    │            ║
║ │  派发任务    │  开发        │  开发        │            ║
║ │  收割结果    │              │              │            ║
║ │  等等        │              │              │            ║
║ │              │              │              │            ║
║ ├──────────────┼──────────────┼──────────────┤            ║
║ │              │              │              │            ║
║ │  (空着等分) │  Worker-3    │  Worker-4    │            ║
║ │              │  (W3)        │  (W4)        │            ║
║ │              │  实时执行    │  实时执行    │            ║
║ │              │  设置页      │  样式整理    │            ║
║ │              │  开发        │  开发        │            ║
║ │              │              │              │            ║
║ └──────────────┴──────────────┴──────────────┘            ║
║                                                             ║
║  用户可以实时看到每个 Worker 的进度和输出                  ║
║  可以点进 Worker panes 查看详细的错误日志                  ║
║                                                             ║
╚═════════════════════════════════════════════════════════════╝
```

---

## ⚡ 最佳实践

### 1️⃣ 任务分解的黄金法则

- **宽勿窄**：宁可一个 Worker 的范围宽一点，也不要划分太细导致跨文件依赖
- **不要共享热文件**：`package.json`、`types.ts`、`README.md` 只给一个 owner
- **依赖提前交换**：Manager 之间的 API 契约要清晰定义
- **独立可验收**：每个 Worker 的工作必须能独立验收（运行 acceptance 命令）

### 2️⃣ 命名规范

```
Manager 名字：来自七龙珠二线角色（克林、天津饭等）
Manager slug：ASCII 小写（"克林" → "klin"）
Worker 命名：manager-slug + "-" + 序号 + "-" + 任务简称
  例子：klin-1-ui、klin-2-message、klin-3-settings

任务文件位置：.fangyang/kaio-ken-<timestamp>/
  例子：.fangyang/kaio-ken-1703123456/
        ├─ klin-1-ui-task.md
        ├─ klin-2-message-task.md
        └─ ...

报告位置：
  Manager 报告：.fangyang/kaio-ken-<timestamp>/klin-report.md
  最终报告：.fangyang/kaio-ken-<timestamp>/FINAL_REPORT.md
```

### 3️⃣ 进度监控

主 Agent 会定期检查 Manager 的状态：

```bash
# 每 30 秒检查一次
herdr agent list | grep -E "manager|worker"

# 查看卡住的 Agent
herdr agent read <name> --source visible
```

如果 Manager 卡住（blocked），主 Agent 会：
1. 读取其屏幕
2. 判断问题类型（权限、依赖、冲突）
3. 尝试自救（发送按键、等待、重分配）

### 4️⃣ 质量检查清单

Manager 在汇报前必须检查：

```
☑️ 所有 Worker 都完成了
☑️ 所有 Worker 的 acceptance 命令都通过了
☑️ 没有文件被多个 Worker 修改（冲突检测）
☑️ 没有 Worker 修改了禁止列表里的文件
☑️ git diff 里的文件都在各 Worker 的 write scope 内
☑️ 跨 Manager 的接口点都已验证
☑️ 报告文件已生成并包含所有必要信息
```

---

## 🚀 高级用法

### 智能重试

如果某个 Manager 失败，主 Agent 会：

1. **第一次尝试**：等待 5 秒，重新派发同样的任务
2. **第二次尝试**：等待 15 秒，可能调整任务范围或重分配给另一个 Manager
3. **放弃**：如果两次都失败，标记为"需要人工介入"

### 跨 Manager 依赖

如果任务间有依赖（如前端依赖后端 API），Manager 可以：

1. 在任务文件里声明依赖：`Depends on: Manager-天津饭`
2. 主 Agent 会按依赖顺序调度
3. 依赖完成后，通知后续 Manager

### 成本控制

主 Agent 会追踪总 token 消耗，如果接近预算上限，会：

1. 减少 Worker 数量（从 6 个改为 3 个）
2. 简化 Manager 任务范围
3. 提前收敛，交付中间结果

---

## 📚 命令参考

### 启动界王拳

```bash
bash scripts/kaio-ken-orchestrate.sh \
  --request "需求描述" \
  --max-managers 4 \
  --max-workers-per-manager 3 \
  --cwd "$PWD"
```

### Manager 在 Tab 内启动 Worker

```bash
bash scripts/fanout.sh \
  --count 3 \
  --work "Manager 的任务名" \
  --tasks "worker-a,worker-b,worker-c" \
  --workspace "$HERDR_WORKSPACE_ID" \
  --cwd "." \
  --tasks-dir ".fangyang/kaio-ken-<timestamp>"
```

### Manager 派发任务

```bash
herdr agent prompt "worker-name" \
  "Read .fangyang/kaio-ken-<timestamp>/worker-name-task.md and execute it."
```

### Manager 收割 Worker

```bash
bash scripts/harvest.sh \
  --manifest ".fangyang/kaio-ken-<timestamp>/herdr-*-agents.tsv"
```

### 主 Agent 监控

```bash
# 查看所有 Manager 状态
herdr agent list | jq '.result.agents[] | select(.name | test("manager"))'

# 查看特定 Manager 的输出
herdr agent read "manager-name" --lines 100

# 检查被阻塞的 Manager
herdr agent read "manager-name" --source visible
```

---

## 🎯 常见场景

### 场景 1：后端 API 尚未完成，前端 Worker 卡住

```
前端 Manager（克林）
└─ Worker-UI 需要调用后端 API，但后端 Manager（天津饭）还没完成

解决：
1. 主 Agent 发现依赖失败
2. 检查天津饭是否完成了 API
3. 如果未完成，告诉克林"稍等"，继续监控天津饭
4. 天津饭完成后，重新派发克林的 Worker
```

### 场景 2：某个 Worker 的验收命令失败

```
克林的 Worker-UI：测试失败

处理流程：
1. Manager 克林运行了验收命令，发现失败
2. 克林检查错误，修改代码
3. 再次运行验收命令
4. 全部通过后，汇报完成
5. 如果克林自己也无法修复，向主 Agent 报告，主 Agent 可能重新分配
```

### 场景 3：两个 Manager 都需要修改 `types.ts`

```
冲突！这是任务分解的错误。

处理方案：
1. 其中一个 Manager（如天津饭）作为 owner，专门负责 types.ts
2. 另一个 Manager（克林）需要修改时，让天津饭代为修改
3. 或者提前协调好 types.ts 的最终形态，两个 Manager 各自实现自己的部分类型
```

---

## 🎓 学习路径

1. **理解架构**：先读本文档的前三部分
2. **查看示例**：查看 `templates/manager-task.md` 和 `templates/worker-task.md`
3. **小规模测试**：用简单的任务试跑 2 个 Manager，每个 2 个 Worker
4. **逐步扩大**：成功后增加到 4-6 个 Manager，3-6 个 Worker
5. **监控优化**：观察 Loop 管理的日志，优化任务分解策略

---

## 💡 故障排查

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| Manager 一直 blocked | 权限弹窗或卡在某一步 | `herdr agent read --source visible` 查看屏幕，按 Always allow |
| Worker 超出 write scope | 任务分解不清晰 | 重新分解，确保每个文件只有一个 owner |
| 多个 Manager 改同一文件 | 冲突了 | 指定一个 owner Manager，其他不要碰 |
| fanout.sh 报 HERDR_WORKSPACE_ID unset | 不在 herdr pane 里 | 确保在正确的 workspace 和 tab 里执行 |
| 验收命令全部通过，但 Manager 说失败 | Worker 理解有误 | 重新读任务文件，澄清需求 |

---

## 📞 更多信息

- 完整 Skill 说明：`SKILL.md`
- 原始放羊了说明：`README.md`
- 界王拳实现细节：`KAIO_KEN_V3.md`

祝界王拳模式运行顺利！🥋⚡

───────────────────────────────────────────────────────
