#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 导入七龙珠角色命名库
source "$SKILL_DIR/lib/dbz-characters.sh"

# 默认参数
REQUEST=""
MAX_MANAGERS=4
MAX_WORKERS_PER_MANAGER=3
CWD="$PWD"
AUTO_MODE=1
QUALITY_THRESHOLD=0.85
MAIN_AGENT_NAME=""
MANAGERS_WORKSPACE=""

usage() {
  cat <<'EOF'
╔═══════════════════════════════════════════════════════════════╗
║  🥋 界王拳模式：分层并行编排系统（悟空指挥部）             ║
║  一线主角 → 二线战士 → 三线小兵                          ║
╚═══════════════════════════════════════════════════════════════╝

Usage: kaio-ken-orchestrate.sh [options]

Options:
  --request TEXT              用户的原始需求描述（必需）
  --max-managers N            Manager 数量上限，2-6（默认：4）
  --max-workers-per-manager N Worker 数量上限，2-6（默认：3）
  --cwd PATH                  工作目录（默认：当前目录）
  --auto-mode BOOL            是否完全自动运行（默认：1；0 则关键决策时询问用户）
  --quality FLOAT             质量检查阈值，0.7-1.0（默认：0.85）
  -h, --help                  显示帮助

Example:
  bash scripts/kaio-ken-orchestrate.sh \
    --request "开发全栈 AI 聊天应用" \
    --max-managers 3 \
    --max-workers-per-manager 4 \
    --cwd "$PWD"
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --request) REQUEST="$2"; shift 2 ;;
    --max-managers) MAX_MANAGERS="$2"; shift 2 ;;
    --max-workers-per-manager) MAX_WORKERS_PER_MANAGER="$2"; shift 2 ;;
    --cwd) CWD="$2"; shift 2 ;;
    --auto-mode) AUTO_MODE="$2"; shift 2 ;;
    --quality) QUALITY_THRESHOLD="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$REQUEST" ]]; then
  echo "Error: --request is required" >&2
  usage
  exit 2
fi

if ! [[ "$MAX_MANAGERS" =~ ^[0-9]+$ ]] || (( MAX_MANAGERS < 2 || MAX_MANAGERS > 6 )); then
  echo "Error: --max-managers must be 2-6" >&2
  exit 2
fi

if [[ ! -d "$CWD" ]]; then
  echo "Error: --cwd is not a directory: $CWD" >&2
  exit 2
fi

echo "=== 界王拳模式启动 ==="
echo "需求: $REQUEST"
echo "工作目录: $CWD"
echo "Manager 上限: $MAX_MANAGERS"
echo ""

# ============================================================================
# 阶段 1：需求深挖
# ============================================================================
echo "【阶段 1/6】需求深挖..."

# 这里应该调用 AI 与用户对话，明确：
# - 最终目标是什么？
# - 有哪些约束？
# - 如何验收？
# 当前简化版本：直接从 REQUEST 提取

WORK_NAME="${REQUEST:0:20}..."  # 截取前 20 字符作为工作名
BASE_COMMIT=$(cd "$CWD" && git rev-parse HEAD 2>/dev/null || echo "unknown")

echo "✓ 工作名: $WORK_NAME"
echo "✓ Base commit: $BASE_COMMIT"
echo ""

# ============================================================================
# 阶段 2：任务分解
# ============================================================================
echo "【阶段 2/6】任务分解..."

# 调用任务分解库
source "$SKILL_DIR/lib/decompose.sh"

# 识别任务类型
TASK_TYPE=$(identify_task_type "$REQUEST" "$CWD")
echo "✓ 任务类型: $TASK_TYPE"

# 分解为 Manager 任务
# 返回格式：每行一个 Manager，格式 "manager-name|task-scope|dependencies"
MANAGER_TASKS=$(decompose_by_type "$TASK_TYPE" "$REQUEST" "$CWD" "$MAX_MANAGERS")
ACTUAL_MANAGER_COUNT=$(echo "$MANAGER_TASKS" | wc -l)

echo "✓ 已分解为 $ACTUAL_MANAGER_COUNT 个 Manager 任务"
echo "$MANAGER_TASKS" | nl
echo ""

# ============================================================================
# 阶段 3：创建专属 workspace
# ============================================================================
echo "【阶段 3/6】创建界王拳专属 workspace..."

WORKSPACE_LABEL="界王拳 · ${WORK_NAME}"

# 创建 workspace
WORKSPACE_CREATE_OUTPUT=$(herdr workspace create --label "$WORKSPACE_LABEL" 2>&1)
WORKSPACE_ID=$(echo "$WORKSPACE_CREATE_OUTPUT" | jq -r '.result.workspace_id' 2>/dev/null || echo "")

if [[ -z "$WORKSPACE_ID" ]]; then
  echo "Error: Failed to create workspace" >&2
  echo "$WORKSPACE_CREATE_OUTPUT" >&2
  exit 1
fi

echo "✓ Workspace 已创建: $WORKSPACE_ID ($WORKSPACE_LABEL)"
echo ""

# ============================================================================
# 阶段 4：创建 Manager 任务文件并启动 Manager
# ============================================================================
echo "【阶段 4/6】准备 Manager 任务文件..."

TIMESTAMP=$(date +%s)
KAIO_KEN_DIR="kaio-ken-$TIMESTAMP"
TASK_DIR="$CWD/.fangyang/$KAIO_KEN_DIR"

mkdir -p "$TASK_DIR"

# 为每个 Manager 创建任务文件
MANAGER_NAMES=()
MANAGER_SLUGS=()

while IFS='|' read -r manager_name task_scope dependencies; do
  # 生成 slug（ASCII 小写）
  manager_slug=$(echo "$manager_name" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed 's/-$//')
  
  MANAGER_NAMES+=("$manager_name")
  MANAGER_SLUGS+=("$manager_slug")
  
  # 从模板生成 Manager 任务文件
  sed \
    -e "s|{{MANAGER_NAME}}|$manager_name|g" \
    -e "s|{{MANAGER_SLUG}}|$manager_slug|g" \
    -e "s|{{CWD}}|$CWD|g" \
    -e "s|{{BASE_COMMIT}}|$BASE_COMMIT|g" \
    -e "s|{{SKILL_DIR}}|$SKILL_DIR|g" \
    -e "s|{{KAIO_KEN_DIR}}|$KAIO_KEN_DIR|g" \
    -e "s|{{TASK_SCOPE}}|$task_scope|g" \
    -e "s|{{DEPENDENCIES}}|$dependencies|g" \
    -e "s|{{ACCEPTANCE_COMMANDS}}|# TODO: 根据项目类型填充验收命令|g" \
    -e "s|{{ACCEPTANCE_CRITERIA}}|所有 Worker 完成、测试通过、无冲突|g" \
    "$SKILL_DIR/templates/manager-task.md" > "$TASK_DIR/${manager_slug}-task.md"
  
  echo "✓ 已创建 Manager 任务: $manager_slug"
done <<< "$MANAGER_TASKS"

echo ""
echo "【阶段 4/6】启动 $ACTUAL_MANAGER_COUNT 个 Manager..."

# 构造任务名列表（逗号分隔）
MANAGER_TASKS_CSV=$(IFS=,; echo "${MANAGER_SLUGS[*]}")

# 用 fanout.sh 启动所有 Manager（每个 Manager 一个 tab）
bash "$SKILL_DIR/scripts/fanout.sh" \
  --count "$ACTUAL_MANAGER_COUNT" \
  --kind auto \
  --work "$WORK_NAME" \
  --tasks "$MANAGER_TASKS_CSV" \
  --workspace "$WORKSPACE_ID" \
  --cwd "$CWD" \
  --tasks-dir "$TASK_DIR"

MANAGER_MANIFEST=$(ls -1 "$TASK_DIR"/herdr-*-agents.tsv | tail -1)

echo "✓ Manager 已启动，manifest: $MANAGER_MANIFEST"
echo ""

# ============================================================================
# 阶段 5：派发任务给 Manager
# ============================================================================
echo "【阶段 5/6】派发任务给所有 Manager..."

while IFS=$'\t' read -r name pane tab ws; do
  [[ "$name" =~ ^# ]] && continue  # 跳过注释行
  [[ -z "$name" ]] && continue
  
  task_file="$TASK_DIR/${name}-task.md"
  
  if [[ ! -f "$task_file" ]]; then
    echo "Warning: Task file not found for $name: $task_file" >&2
    continue
  fi
  
  echo "→ 派发任务给 $name ..."
  herdr agent prompt "$name" \
    "Read $task_file and follow it step by step. You are a Manager, not a Worker. Your job is to decompose your task scope, create Worker task files, launch Workers using fanout.sh in YOUR tab, harvest results, verify quality, and write a report. Do not commit."
  
done < <(tail -n +2 "$MANAGER_MANIFEST")

echo "✓ 所有 Manager 已收到任务"
echo ""

# ============================================================================
# 阶段 6：Loop 管理（持续监控）
# ============================================================================
echo "【阶段 6/6】Loop 管理模式（持续监控 Manager 状态）..."
echo "提示：这是一个长时间运行的循环，按 Ctrl+C 可中断"
echo ""

LOOP_COUNT=0
MAX_LOOPS=60  # 最多检查 60 次（30 分钟，每次 30 秒）

while (( LOOP_COUNT < MAX_LOOPS )); do
  LOOP_COUNT=$((LOOP_COUNT + 1))
  echo "[Loop $LOOP_COUNT] 检查 Manager 状态..."
  
  # 读取所有 Manager 的状态
  AGENT_STATUS=$(herdr agent list 2>/dev/null | jq -r '.result.agents[] | select(.name | IN($managers[])) | "\(.name)\t\(.agent_status)"' \
    --argjson managers "$(printf '%s\n' "${MANAGER_SLUGS[@]}" | jq -R . | jq -s .)" 2>/dev/null || echo "")
  
  if [[ -z "$AGENT_STATUS" ]]; then
    echo "Warning: 无法获取 Manager 状态" >&2
    sleep 30
    continue
  fi
  
  # 统计状态
  TOTAL=0
  IDLE=0
  DONE=0
  WORKING=0
  BLOCKED=0
  ERROR=0
  
  while IFS=$'\t' read -r name status; do
    TOTAL=$((TOTAL + 1))
    case "$status" in
      idle) IDLE=$((IDLE + 1)) ;;
      done) DONE=$((DONE + 1)) ;;
      working) WORKING=$((WORKING + 1)) ;;
      blocked) BLOCKED=$((BLOCKED + 1)) ;;
      error) ERROR=$((ERROR + 1)) ;;
    esac
  done <<< "$AGENT_STATUS"
  
  echo "  状态: idle=$IDLE done=$DONE working=$WORKING blocked=$BLOCKED error=$ERROR"
  
  # 检查是否全部完成
  COMPLETED=$((IDLE + DONE))
  if (( COMPLETED == TOTAL )); then
    echo "✓ 所有 Manager 已完成！"
    break
  fi
  
  # 处理 blocked/error 的 Manager
  if (( BLOCKED > 0 || ERROR > 0 )); then
    echo "  发现 blocked 或 error 的 Manager，尝试介入..."
    
    while IFS=$'\t' read -r name status; do
      if [[ "$status" == "blocked" ]] || [[ "$status" == "error" ]]; then
        echo "  → 读取 $name 的屏幕..."
        herdr agent read "$name" --source visible || true
        
        # TODO: 智能判断问题类型并处理
        # 1. 权限问题 → send-keys
        # 2. 依赖未就绪 → 等待
        # 3. 任务冲突 → 重新分配
      fi
    done <<< "$AGENT_STATUS"
  fi
  
  # 等待 30 秒后再检查
  sleep 30
done

if (( LOOP_COUNT >= MAX_LOOPS )); then
  echo "Warning: 达到最大循环次数，部分 Manager 可能未完成" >&2
fi

echo ""

# ============================================================================
# 阶段 7：收割报告并聚合
# ============================================================================
echo "【阶段 7/6】收割 Manager 报告并聚合..."

FINAL_REPORT="$TASK_DIR/FINAL_REPORT.md"

cat > "$FINAL_REPORT" <<EOF
# 界王拳任务完成汇报

任务: $REQUEST
工作目录: $CWD
Base commit: $BASE_COMMIT
Workspace: $WORKSPACE_ID
开始时间: $(date -r "$TIMESTAMP" '+%Y-%m-%d %H:%M:%S')
完成时间: $(date '+%Y-%m-%d %H:%M:%S')

---

## Manager 汇报汇总

EOF

for slug in "${MANAGER_SLUGS[@]}"; do
  report_file="$TASK_DIR/${slug}-report.md"
  
  if [[ -f "$report_file" ]]; then
    echo "✓ 找到 $slug 的报告"
    cat "$report_file" >> "$FINAL_REPORT"
    echo "" >> "$FINAL_REPORT"
  else
    echo "⚠️  未找到 $slug 的报告: $report_file"
    cat >> "$FINAL_REPORT" <<EOF

### $slug: ❌ 未找到报告

Manager 可能未完成或未写报告文件。

EOF
  fi
done

cat >> "$FINAL_REPORT" <<EOF

---

## 主 Agent 最终验证

EOF

echo "运行全量验证..."

# 检查 git 状态
cd "$CWD"
git status --short >> "$FINAL_REPORT" 2>&1 || echo "Git status 失败" >> "$FINAL_REPORT"

# TODO: 根据项目类型运行验收测试
# - pnpm test / pnpm typecheck / pnpm build
# - cargo test / cargo clippy
# - python -m pytest

cat >> "$FINAL_REPORT" <<EOF

## 下一步建议

1. 查看各 Manager 的羊圈（在 workspace $WORKSPACE_ID 的各个 tab）
2. 运行全量测试和构建
3. 检查跨 Manager 的集成点
4. 确认无误后，决定是否 commit

羊圈 workspace: $WORKSPACE_ID
任务目录: $TASK_DIR
EOF

echo ""
echo "=== 界王拳任务完成 ==="
echo "最终报告: $FINAL_REPORT"
echo ""
cat "$FINAL_REPORT"
