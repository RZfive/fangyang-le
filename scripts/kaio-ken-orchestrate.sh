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
LOOP_INTERVAL=30
MAX_LOOPS=60
VERIFY_CMD=""


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
                              无 tty 时降级为自动继续并写入 .decisions.log
                              自动化场景可用环境变量 KAIO_KEN_CONFIRM_ANSWERS=y,n
                              按顺序预设每个确认点的答案（y 继续 / n 中止）
  --quality FLOAT             质量检查阈值，0.7-1.0（默认：0.85）
  --loop-interval SECS        Loop 轮询间隔秒数，1-3600（默认：30）
  --max-loops N               最多轮询多少轮，1-10000（默认：60）
  --verify CMD                最终验收命令，在 --cwd 下执行；exit 0 才算通过
                              （不传则质量门只靠报告覆盖率，报告会标注未运行）
  -h, --help                  显示帮助

Example:
  bash scripts/kaio-ken-orchestrate.sh \
    --request "开发全栈 AI 聊天应用" \
    --max-managers 3 \
    --max-workers-per-manager 4 \
    --loop-interval 30 \
    --verify "pnpm install && pnpm typecheck && pnpm test" \
    --cwd "$PWD"
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --request) REQUEST="$2"; shift 2 ;;
    --max-managers) MAX_MANAGERS="$2"; shift 2 ;;
    --max-workers-per-manager) MAX_WORKERS_PER_MANAGER="$2"; shift 2 ;;
    --cwd) CWD="$2"; shift 2 ;;
    --quality) QUALITY_THRESHOLD="$2"; shift 2 ;;
    --loop-interval) LOOP_INTERVAL="$2"; shift 2 ;;
    --max-loops) MAX_LOOPS="$2"; shift 2 ;;
    --verify) VERIFY_CMD="$2"; shift 2 ;;
    --auto-mode) AUTO_MODE="$2"; shift 2 ;;

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

if ! [[ "$MAX_WORKERS_PER_MANAGER" =~ ^[0-9]+$ ]] || (( MAX_WORKERS_PER_MANAGER < 2 || MAX_WORKERS_PER_MANAGER > 6 )); then
  echo "Error: --max-workers-per-manager must be 2-6" >&2
  exit 2
fi

if ! [[ "$LOOP_INTERVAL" =~ ^[0-9]+$ ]] || (( LOOP_INTERVAL < 1 || LOOP_INTERVAL > 3600 )); then
  echo "Error: --loop-interval must be 1-3600" >&2
  exit 2
fi

if ! [[ "$MAX_LOOPS" =~ ^[0-9]+$ ]] || (( MAX_LOOPS < 1 || MAX_LOOPS > 10000 )); then
  echo "Error: --max-loops must be 1-10000" >&2
  exit 2
fi

# 质量阈值用 awk 比较：bash 3.2 没有浮点运算，[ 0.9 -lt 0.85 ] 会报错。
if ! [[ "$QUALITY_THRESHOLD" =~ ^[0-9]+(\.[0-9]+)?$ ]] \
  || ! awk -v q="$QUALITY_THRESHOLD" 'BEGIN{ exit !(q + 0 >= 0.7 && q + 0 <= 1.0) }'; then
  echo "Error: --quality must be a float between 0.7 and 1.0" >&2
  exit 2
fi

if [[ ! -d "$CWD" ]]; then
  echo "Error: --cwd is not a directory: $CWD" >&2
  exit 2
fi

if [[ "$AUTO_MODE" != "0" && "$AUTO_MODE" != "1" ]]; then
  echo "Error: --auto-mode must be 0 or 1" >&2
  exit 2
fi

# ============================================================================
# 关键决策确认（--auto-mode 0 时启用）
# ============================================================================
# auto-mode 1：不打断，所有决策按默认值继续，并把「按默认继续」记进决策日志。
# auto-mode 0：在花钱/不可逆的动作前问一次；没有可交互终端时不能假装问过，
# 也不能卡死无人值守的脚本 —— 明确降级为自动继续，并在日志里留痕。
DECISION_LOG=""
INTERACTIVE=0
if [[ -t 0 ]] && { [[ -t 1 ]] || [[ -r /dev/tty ]]; }; then
  INTERACTIVE=1
fi

# KAIO_KEN_CONFIRM_ANSWERS=y,n：按确认点顺序预设答案（y 继续 / 其它 中止）。
# 交互分支本来只认 /dev/tty，无人值守的回归测试无法覆盖；用预设队列既能
# 断言「用户选中止」这条路径，也方便别的脚本把界王拳嵌进自己的流水线。
CONFIRM_ANSWER_QUEUE=()
CONFIRM_ANSWER_COUNT=0
CONFIRM_ANSWER_INDEX=0
if [[ -n "${KAIO_KEN_CONFIRM_ANSWERS:-}" ]]; then
  IFS=', ' read -r -a CONFIRM_ANSWER_QUEUE <<< "$KAIO_KEN_CONFIRM_ANSWERS"
  CONFIRM_ANSWER_COUNT=${#CONFIRM_ANSWER_QUEUE[@]}
  (( CONFIRM_ANSWER_COUNT > 0 )) && INTERACTIVE=1
fi

record_decision() { # <标题> <结论>
  [[ -z "${DECISION_LOG:-}" ]] && return 0
  printf '[%s] %s → %s\n' "$(date '+%H:%M:%S')" "$1" "$2" >> "$DECISION_LOG"
}
confirm_decision() { # <标题> <详情>；返回 0 继续，1 中止
  local title="$1" detail="${2:-}" answer=""
  if (( AUTO_MODE == 1 )); then
    echo "  [auto] $title：自动继续"
    record_decision "$title" "自动继续（--auto-mode 1）"
    return 0
  fi
  if (( CONFIRM_ANSWER_INDEX < CONFIRM_ANSWER_COUNT )); then
    answer="${CONFIRM_ANSWER_QUEUE[$CONFIRM_ANSWER_INDEX]}"
    CONFIRM_ANSWER_INDEX=$((CONFIRM_ANSWER_INDEX + 1))
    echo "  [preset] $title → ${answer:-Y}（KAIO_KEN_CONFIRM_ANSWERS）"
    case "${answer:-Y}" in
      [Yy]*) record_decision "$title" "预设答案继续（KAIO_KEN_CONFIRM_ANSWERS）"; return 0 ;;
      *) record_decision "$title" "预设答案中止（KAIO_KEN_CONFIRM_ANSWERS=${answer:-}）"; return 1 ;;
    esac
  fi
  if (( INTERACTIVE == 0 )); then
    echo "  [auto-fallback] 没有可交互终端，无法确认「$title」，按继续处理" >&2
    record_decision "$title" "自动继续（无 tty，降级）"
    return 0
  fi
  echo ""
  echo "──── 需要你确认：$title ────"
  printf '%s\n' "$detail"
  printf '继续？[Y/n] '
  read -r answer < /dev/tty || answer=""
  case "${answer:-Y}" in
    [Yy]*|"") record_decision "$title" "用户确认继续"; return 0 ;;
    *) record_decision "$title" "用户选择中止"; return 1 ;;
  esac
}

echo "=== 界王拳模式启动 ==="
MAIN_AGENT_NAME="$(get_main_agent_name)"
echo "一线主角（主 Agent）: $MAIN_AGENT_NAME"
echo "需求: $REQUEST"

echo "工作目录: $CWD"
echo "Manager 上限: $MAX_MANAGERS"
echo ""
# 任务目录先建好：阶段 2 的确认就要把结论写进 .decisions.log，
# 后建目录会导致最关键的「分解是否被确认」反而没有痕迹。
TIMESTAMP=$(date +%s)
KAIO_KEN_DIR="kaio-ken-$TIMESTAMP"
TASK_DIR="$CWD/.fangyang/$KAIO_KEN_DIR"
mkdir -p "$TASK_DIR"

DECISION_LOG="$TASK_DIR/.decisions.log"
: > "$DECISION_LOG"
if (( AUTO_MODE == 0 )); then
  echo "▶ 交互模式（--auto-mode 0）：关键决策点会先问你。"
  (( INTERACTIVE == 0 )) && echo "  注意：当前没有可交互终端，确认会降级为自动继续并留痕。" >&2
  record_decision "启动模式" "--auto-mode 0（交互确认）"
else
  record_decision "启动模式" "--auto-mode 1（全自动）"
fi


# ============================================================================
# 阶段 1：需求深挖
# ============================================================================
echo "【阶段 1/7】需求深挖..."

# 这里应该调用 AI 与用户对话，明确：
# - 最终目标是什么？
# - 有哪些约束？
# - 如何验收？
# 当前简化版本：直接从 REQUEST 提取
WORK_NAME="${REQUEST:0:20}..."  # 截取前 20 字符作为工作名
# `git rev-parse HEAD || echo unknown` 在空仓库里会先打印 "HEAD" 再拼接
# "unknown"，报告里就变成两行；分开取值才能只拿到一个值。
BASE_COMMIT="$(cd "$CWD" && git rev-parse HEAD 2>/dev/null || true)"
[[ -z "$BASE_COMMIT" ]] && BASE_COMMIT="unknown"

echo "✓ 工作名: $WORK_NAME"
echo "✓ Base commit: $BASE_COMMIT"
echo ""

# ============================================================================
# 阶段 2：任务分解
# ============================================================================
echo "【阶段 2/7】任务分解..."

# 调用任务分解库
source "$SKILL_DIR/lib/decompose.sh"

# 识别任务类型
TASK_TYPE=$(identify_task_type "$REQUEST" "$CWD")
echo "✓ 任务类型: $TASK_TYPE"

# 分解为 Manager 任务：模块 scope + 二线角色名。
# 返回格式：每行 display|module-slug|scope|dependencies
MANAGER_TASKS=$(decompose_by_type "$TASK_TYPE" "$REQUEST" "$CWD" "$MAX_MANAGERS")

ACTUAL_MANAGER_COUNT=$(printf '%s\n' "$MANAGER_TASKS" | grep -c . || true)

echo "✓ 已分解为 $ACTUAL_MANAGER_COUNT 个 Manager 任务"
echo "$MANAGER_TASKS" | nl
echo ""

# 第一个关键决策点：分解结果就是整条流水线的骨架，改起来最贵。
if ! confirm_decision "确认任务分解（$TASK_TYPE，$ACTUAL_MANAGER_COUNT 个 Manager）" \
  "$(printf '需求: %s\n类型: %s\n上限: %s 个 Manager × %s 个 Worker\n\n%s\n' \
    "$REQUEST" "$TASK_TYPE" "$MAX_MANAGERS" "$MAX_WORKERS_PER_MANAGER" \
    "$(echo "$MANAGER_TASKS" | nl -ba)")"; then
  echo "已按用户选择中止：未创建 workspace，未启动任何 agent。" >&2
  exit 3
fi
echo ""

# ============================================================================
# 阶段 3：创建专属 workspace
# ============================================================================
echo "【阶段 3/7】创建界王拳专属 workspace..."

WORKSPACE_LABEL="${MAIN_AGENT_NAME}的界王拳 · ${WORK_NAME}"


# 创建 workspace。herdr 把 workspace 作为对象返回在 .result.workspace，
# ID 在 .result.workspace.workspace_id；兼容个别版本直接返回字符串的形式。
# 读错字段会拿到 null，后续 --workspace null 会让所有 agent 启动失败。
WORKSPACE_CREATE_OUTPUT="$(herdr workspace create --label "$WORKSPACE_LABEL" --cwd "$CWD" --no-focus 2>&1)"
WORKSPACE_ID="$(printf '%s' "$WORKSPACE_CREATE_OUTPUT" | jq -r '
  ( .result.workspace.workspace_id
    // (if (.result.workspace | type) == "string" then .result.workspace else null end)
    // .result.workspace_id
    // empty )' 2>/dev/null || true)"

if [[ -z "$WORKSPACE_ID" || "$WORKSPACE_ID" == "null" ]]; then
  echo "Error: Failed to create workspace" >&2
  echo "$WORKSPACE_CREATE_OUTPUT" >&2
  exit 1
fi

echo "✓ Workspace 已创建: $WORKSPACE_ID ($WORKSPACE_LABEL)"
echo ""

# ============================================================================
# 阶段 4：创建 Manager 任务文件并启动 Manager
# ============================================================================
echo "【阶段 4/7】分配二线角色并准备 Manager 任务文件..."


# 为每个 Manager 创建任务文件，先按模块固定任务名，再分配二线角色。
# 角色名统一从 dbz-roster.sh 领取：它保证 ASCII slug、互不重复，
# 并把领到的名字写入 $TASK_DIR/.dbz-reserved 占位，避免并发编排撞名。
MANAGER_NAMES=()
MANAGER_SLUGS=()
# 模块 slug → Manager 角色 slug：派发时靠它找到对应任务文件，
# 不能拿角色映射表（角色 slug → 中文名）当派发表用。
MANAGER_MAP_FILE="$TASK_DIR/.manager-map"
: > "$MANAGER_MAP_FILE"

MANAGER_ROSTER="$(bash "$SKILL_DIR/scripts/dbz-roster.sh" \
  --count "$ACTUAL_MANAGER_COUNT" \
  --tier manager \
  --used-from "$TASK_DIR")"
if [[ -z "$MANAGER_ROSTER" ]]; then
  echo "Error: 二线角色分配失败（看上面 dbz-roster 的报错）" >&2
  exit 1
fi
# macOS 自带 bash 3.2 没有 mapfile，用 while-read 收集，两边都能跑。
MANAGER_ROSTER_SLUGS=()
while IFS= read -r _slug; do
  [[ -z "$_slug" ]] && continue
  MANAGER_ROSTER_SLUGS+=("$_slug")
done <<< "$MANAGER_ROSTER"

# 只保留真正分到模块的角色：roster 是「要几个给几个」，但池子余量、
# 并发占位都可能让它多给；多出来的 slug 不能交给 fanout 启动，
# 否则 --count 与 --tasks 数量对不上会直接 exit 2。
MANAGER_PLANNED=()
manager_idx=0
while IFS='|' read -r module_name module_slug task_scope dependencies; do
  [[ -z "$module_name" || -z "$module_slug" ]] && continue
  manager_slug="${MANAGER_ROSTER_SLUGS[$manager_idx]:-}"
  if [[ -z "$manager_slug" ]]; then
    echo "Error: 角色数量不足，无法为 $module_name 分配 Manager" >&2
    exit 1
  fi
  manager_idx=$((manager_idx + 1))
  manager_name="$(dbz_agent_display_name "$(dbz_base_slug "$manager_slug")")"
  MANAGER_NAMES+=("$manager_name")
  MANAGER_PLANNED+=("$manager_slug")

  sed \
    -e "s|{{MANAGER_NAME}}|$manager_name|g" \
    -e "s|{{MANAGER_SLUG}}|$manager_slug|g" \
    -e "s|{{CWD}}|$CWD|g" \
    -e "s|{{BASE_COMMIT}}|$BASE_COMMIT|g" \
    -e "s|{{SKILL_DIR}}|$SKILL_DIR|g" \
    -e "s|{{KAIO_KEN_DIR}}|$KAIO_KEN_DIR|g" \
    -e "s|{{TASK_DIR}}|$TASK_DIR|g" \
    -e "s|{{TASK_SCOPE}}|$task_scope|g" \
    -e "s|{{DEPENDENCIES}}|$dependencies|g" \
    -e "s|{{MAX_WORKERS}}|$MAX_WORKERS_PER_MANAGER|g" \
    -e "s|{{ACCEPTANCE_COMMANDS}}|# TODO: 根据项目类型填充验收命令|g" \
    -e "s|{{ACCEPTANCE_CRITERIA}}|所有 Worker 完成、测试通过、无冲突|g" \
    "$SKILL_DIR/templates/manager-task.md" > "$TASK_DIR/${manager_slug}-task.md"

  printf '%s\t%s\n' "$module_slug" "$manager_slug" >> "$MANAGER_MAP_FILE"
  echo "✓ $module_name → 二线战士 $manager_name ($manager_slug)"
done <<< "$MANAGER_TASKS"

if (( ${#MANAGER_PLANNED[@]} == 0 )); then
  echo "Error: 没有可派发的 Manager 模块" >&2
  exit 1
fi

MANAGER_SLUGS=("${MANAGER_PLANNED[@]}")
ACTUAL_MANAGER_COUNT="${#MANAGER_SLUGS[@]}"



echo ""
echo "→ 启动 $ACTUAL_MANAGER_COUNT 个 Manager..."

# 第二个关键决策点：这里是真正开始烧 token / 起进程的边界。
if ! confirm_decision "启动 $ACTUAL_MANAGER_COUNT 个 Manager（每人不超 $MAX_WORKERS_PER_MANAGER 个 Worker）" \
  "$(printf 'Workspace: %s\n任务目录: %s\n角色: %s\n\n启动后 Manager 会自行 fanout Worker 并写报告，中途只监控不代劳。' \
    "$WORKSPACE_ID" "$TASK_DIR" "${MANAGER_NAMES[*]:-无}")"; then
  echo "已按用户选择中止：workspace $WORKSPACE_ID 已创建但未启动任何 agent。" >&2
  echo "如需清理：herdr workspace delete $WORKSPACE_ID" >&2
  exit 3
fi

# 角色 slug 同时作为任务名、herdr agent 名和任务文件名。
MANAGER_TASKS_CSV=$(IFS=,; echo "${MANAGER_SLUGS[*]}")

# 界王拳专用入口：不改变普通 fanout 的西部牛仔命名。
bash "$SKILL_DIR/scripts/fanout.sh" \
  --count "$ACTUAL_MANAGER_COUNT" \
  --kind auto \
  --work "$WORK_NAME" \
  --dbz-tier manager \
  --dbz-owner "$MAIN_AGENT_NAME" \
  --tasks "$MANAGER_TASKS_CSV" \
  --workspace "$WORKSPACE_ID" \
  --cwd "$CWD" \
  --tasks-dir "$TASK_DIR"

MANAGER_MANIFEST=$(ls -1 "$TASK_DIR"/herdr-*-agents.tsv | tail -1)
MANAGER_DBZ_MAP="${MANAGER_MANIFEST}.dbz-names"
if [[ ! -f "$MANAGER_DBZ_MAP" ]]; then
  echo "Error: DBZ 名称映射缺失: $MANAGER_DBZ_MAP" >&2
  exit 1
fi

echo "✓ Manager 已启动，manifest: $MANAGER_MANIFEST"
echo ""

# ============================================================================
# 阶段 5：派发任务给 Manager
# ============================================================================
echo "【阶段 5/7】派发任务给所有 Manager..."

# 实际 agent 名以 manifest 为准：herdr 撞名时 fanout 会加 -2/-3 后缀，
# 直接用规划好的 slug 去 prompt 会在重跑时找不到 agent。
MANAGER_ACTUAL_NAMES=()
while IFS=$'\t' read -r m_name _m_pane _m_tab _m_ws; do
  [[ -z "$m_name" || "$m_name" == "name" || "$m_name" == \#* ]] && continue
  MANAGER_ACTUAL_NAMES+=("$m_name")
done < "$MANAGER_MANIFEST"

if (( ${#MANAGER_ACTUAL_NAMES[@]} == 0 )); then
  echo "Error: manifest 里没有任何已启动的 Manager: $MANAGER_MANIFEST" >&2
  exit 1
fi

MODULE_SLUGS=()
while IFS=$'\t' read -r m_module _m_slug; do
  [[ -z "$m_module" ]] && continue
  MODULE_SLUGS+=("$m_module")
done < "$MANAGER_MAP_FILE"

# 规划名单（slug → 模块）和实际名单（herdr 真实 agent 名）按启动顺序一一对应，
# 数量不一致时只派发能配对的部分，并明确告警：宁可少派，也不能把任务
# 错派到别的 Manager 的模块上。
PLANNED_SLUGS=()
if (( ${#MANAGER_SLUGS[@]} )); then
  PLANNED_SLUGS=("${MANAGER_SLUGS[@]}")
fi

MANIFEST_COUNT=${#MANAGER_ACTUAL_NAMES[@]}
PLANNED_COUNT=${#PLANNED_SLUGS[@]}
if (( MANIFEST_COUNT != PLANNED_COUNT )); then
  echo "Warning: manifest 有 $MANIFEST_COUNT 个 Manager，规划是 $PLANNED_COUNT 个；只派发可配对的部分。" >&2
fi
DISPATCH_COUNT=$MANIFEST_COUNT
(( PLANNED_COUNT < DISPATCH_COUNT )) && DISPATCH_COUNT=$PLANNED_COUNT
if (( DISPATCH_COUNT == 0 )); then
  echo "Error: 规划名单为空，无法派发任务" >&2
  exit 1
fi

for ((i = 0; i < DISPATCH_COUNT; i++)); do
  manager_slug="${MANAGER_ACTUAL_NAMES[$i]}"
  planned_slug="${PLANNED_SLUGS[$i]}"
  task_file="$TASK_DIR/${planned_slug}-task.md"
  if [[ ! -f "$task_file" && "$manager_slug" != "$planned_slug" ]]; then
    task_file="$TASK_DIR/${manager_slug}-task.md"
  fi
  manager_name="$(dbz_manifest_display_name "$MANAGER_DBZ_MAP" "$manager_slug")"

  if [[ ! -f "$task_file" ]]; then
    echo "Warning: Task file not found for $manager_slug: $task_file" >&2
    continue
  fi

  # 撞名加了后缀时，把任务文件里的规划 slug 换成真实 agent 名，
  # 这样报告路径 <真实名>-report.md 和阶段 7 的收割路径一致。
  if [[ "$manager_slug" != "$planned_slug" ]]; then
    task_tmp="$task_file.tmp.$$"
    sed -e "s|${planned_slug}|${manager_slug}|g" "$task_file" > "$task_tmp" \
      && mv "$task_tmp" "$task_file"
  fi

  echo "→ 派发任务给 $manager_name ($manager_slug)${MODULE_SLUGS[$i]:+ · 模块 ${MODULE_SLUGS[$i]}} ..."
  herdr agent prompt "$manager_slug" \
    "Read $task_file and follow it step by step. You are a Manager, not a Worker. Your job is to decompose your task scope, create Worker task files, launch Workers using fanout.sh in YOUR tab, harvest results, verify quality, and write a report to $TASK_DIR/${manager_slug}-report.md. Do not commit."
done

# 监控与收割也要用真实 agent 名。
MANAGER_SLUGS=("${MANAGER_ACTUAL_NAMES[@]}")



echo "✓ 所有 Manager 已收到任务"
echo ""

# ============================================================================
# 阶段 6：Loop 管理（持续监控 + 留证式介入）
# ============================================================================
echo "【阶段 6/7】Loop 管理（监控 $ACTUAL_MANAGER_COUNT 个 Manager）..."
echo "轮询: 每 ${LOOP_INTERVAL}s 一次，最多 ${MAX_LOOPS} 轮（--max-loops / --loop-interval 可调）"
echo ""

INTERVENTION_LOG="$TASK_DIR/.interventions.log"
: > "$INTERVENTION_LOG"

LOOP_COUNT=0
LAST_STATUS=""
ALL_SETTLED=0

while (( LOOP_COUNT < MAX_LOOPS )); do
  LOOP_COUNT=$((LOOP_COUNT + 1))
  echo "[Loop $LOOP_COUNT/$MAX_LOOPS] 检查 Manager 状态..."

  # jq 的 index() 需要数组变量：先把名字列表转成 JSON 数组再 --argjson 传入。
  # 直接把 "${MANAGER_SLUGS[@]}" 展开成多个参数，jq 会把第二个名字当成文件报错。
  MANAGER_JSON="[]"
  if (( ${#MANAGER_SLUGS[@]} )); then
    MANAGER_JSON="$(printf '%s\n' "${MANAGER_SLUGS[@]}" | jq -R . | jq -s -c . 2>/dev/null || echo '[]')"
  fi

  AGENT_STATUS="$(herdr agent list 2>/dev/null \
    | jq -r --argjson managers "$MANAGER_JSON" '
        .result.agents[]?
        | select(.name as $n | ($managers | index($n)))
        | "\(.name)\t\(.agent_status // "unknown")"' \
        2>/dev/null || true)"

  if [[ -z "$AGENT_STATUS" ]]; then
    echo "  Warning: 本轮拿不到 Manager 状态（agent 可能已退出或 herdr 报错）" >&2
  else
    TOTAL=0
    IDLE=0
    DONE=0
    WORKING=0
    BLOCKED=0
    ERROR=0

    while IFS=$'\t' read -r _name _status; do
      [[ -z "$_name" ]] && continue
      TOTAL=$((TOTAL + 1))
      case "$_status" in
        idle) IDLE=$((IDLE + 1)) ;;
        done) DONE=$((DONE + 1)) ;;
        working) WORKING=$((WORKING + 1)) ;;
        blocked) BLOCKED=$((BLOCKED + 1)) ;;
        error) ERROR=$((ERROR + 1)) ;;
      esac
    done <<< "$AGENT_STATUS"

    LAST_STATUS="idle=$IDLE done=$DONE working=$WORKING blocked=$BLOCKED error=$ERROR"
    echo "  状态: $LAST_STATUS"

    SETTLED=$((IDLE + DONE))
    if (( TOTAL > 0 && SETTLED == TOTAL )); then
      if (( BLOCKED == 0 && ERROR == 0 )); then
        ALL_SETTLED=1
        echo "✓ 所有 Manager 已停手且无 blocked/error"
      else
        echo "Warning: Manager 已停手，但仍有 blocked/error 未解决" >&2
      fi
      break
    fi

    if (( BLOCKED > 0 || ERROR > 0 )); then
      echo "  发现 blocked/error 的 Manager，读取屏幕留证..."
      while IFS=$'\t' read -r _name _status; do
        [[ -z "$_name" ]] && continue
        if [[ "$_status" == "blocked" ]] || [[ "$_status" == "error" ]]; then
          printf '[Loop %s] %s: %s\n' "$LOOP_COUNT" "$_name" "$_status" >> "$INTERVENTION_LOG"
          herdr agent read "$_name" --source visible >> "$INTERVENTION_LOG" 2>&1 || true
        fi
      done <<< "$AGENT_STATUS"
      # 自动介入的边界：这里只记录证据，不擅自 send-keys。盲目按键会让
      # 子 agent 执行用户没有同意过的动作；真正介入由主 Agent 读
      # .interventions.log 后决定，避免「无人监管」变成「无人负责」。
    fi
  fi

  # 逐秒等待：Ctrl+C 能立刻中断，测试里也能把间隔压到 1s。
  WAIT_SECS=$LOOP_INTERVAL
  (( WAIT_SECS < 1 )) && WAIT_SECS=1
  for ((w = 0; w < WAIT_SECS; w++)); do sleep 1; done
done

if (( ALL_SETTLED == 0 )); then
  echo "Warning: 达到轮询上限 ${MAX_LOOPS} 或仍有 blocked/error，Manager 可能未完成" >&2
fi

echo ""

# ============================================================================
# 阶段 7：收割报告并聚合
# ============================================================================
echo "【阶段 7/7】收割 Manager 报告并聚合..."

FINAL_REPORT="$TASK_DIR/FINAL_REPORT.md"
REPORT_TOTAL=0
REPORT_FOUND=0
MISSING_REPORTS=""

if (( ${#MANAGER_SLUGS[@]} )); then
  for slug in "${MANAGER_SLUGS[@]}"; do
    REPORT_TOTAL=$((REPORT_TOTAL + 1))
    if [[ -s "$TASK_DIR/${slug}-report.md" ]]; then
      REPORT_FOUND=$((REPORT_FOUND + 1))
    else
      MISSING_REPORTS="${MISSING_REPORTS}${slug} "
    fi
  done
fi

{
  echo "# 界王拳任务完成汇报"
  echo
  echo "任务: $REQUEST"
  echo "工作目录: $CWD"
  echo "Base commit: $BASE_COMMIT"
  echo "Workspace: $WORKSPACE_ID"
  echo "一线主 Agent: $MAIN_AGENT_NAME"
  echo "开始时间: $(date -r "$TIMESTAMP" '+%Y-%m-%d %H:%M:%S')"
  echo "完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "Loop 轮询: $LOOP_COUNT 轮（上限 $MAX_LOOPS）"
  echo "最后状态: ${LAST_STATUS:-无记录}"
  echo "报告覆盖: ${REPORT_FOUND}/${REPORT_TOTAL}"
  echo
  echo "---"
  echo
  echo "## Manager 汇报汇总"
  echo
} > "$FINAL_REPORT"

if (( ${#MANAGER_SLUGS[@]} )); then
  for slug in "${MANAGER_SLUGS[@]}"; do
    report_file="$TASK_DIR/${slug}-report.md"
    if [[ -s "$report_file" ]]; then
      echo "✓ 找到 $slug 的报告"
      {
        echo "### $slug"
        echo
        cat "$report_file"
        echo
      } >> "$FINAL_REPORT"
    else
      echo "⚠️  未找到 $slug 的报告: $report_file"
      {
        echo "### $slug: ❌ 未找到报告"
        echo
        echo "Manager 可能未完成、未写报告，或报告用的是规划名（DBZ 撞名加后缀时见 .manager-map）。"
        echo
      } >> "$FINAL_REPORT"
    fi
  done
fi

echo ""
echo "运行最终验证..."

{
  echo "---"
  echo
  echo "## 主 Agent 最终验证"
  echo
  echo "### git status"
  echo
  echo '```'
  git -C "$CWD" status --short 2>&1 || echo "git status 失败"
  echo '```'
  echo
  echo "### git diff --stat"
  echo
  echo '```'
  git -C "$CWD" diff --stat 2>&1 || echo "git diff 失败"
  echo '```'
} >> "$FINAL_REPORT"

# 验收命令是「脱离人的监管」的关键：没有可执行验收就等于没有结论。
VERIFY_RESULT="未运行（没有传 --verify）"
VERIFY_RC=0
if [[ -n "$VERIFY_CMD" ]]; then
  echo "执行验收命令: $VERIFY_CMD"
  set +e
  VERIFY_OUTPUT="$(cd "$CWD" && bash -c "$VERIFY_CMD" 2>&1)"
  VERIFY_RC=$?
  set -e
  if (( VERIFY_RC == 0 )); then
    VERIFY_RESULT="通过 (exit 0)"
  else
    VERIFY_RESULT="失败 (exit $VERIFY_RC)"
  fi
  {
    echo
    echo "### 验收命令"
    echo
    echo '```bash'
    echo "$VERIFY_CMD"
    echo '```'
    echo
    echo "结果: $VERIFY_RESULT"
    echo
    echo '```'
    printf '%s\n' "$VERIFY_OUTPUT" | tail -n 200
    echo '```'
  } >> "$FINAL_REPORT"
  if (( VERIFY_RC != 0 )); then
    echo "⚠️  验收命令失败（exit $VERIFY_RC），完整输出已写入报告" >&2
  fi
fi

# 质量门：报告覆盖率 + 验收命令。两者都过才算通过。
COVERAGE="0.00"
if (( REPORT_TOTAL > 0 )); then
  COVERAGE="$(awk -v f="$REPORT_FOUND" -v t="$REPORT_TOTAL" 'BEGIN{ printf "%.2f", f / t }')"
fi

GATE="不通过"
if awk -v c="$COVERAGE" -v q="$QUALITY_THRESHOLD" 'BEGIN{ exit !(c + 0 >= q + 0) }'; then
  if (( VERIFY_RC == 0 )); then
    GATE="通过"
  fi
fi

{
  echo
  echo "---"
  echo
  echo "## 结论"
  echo
  echo "- 报告覆盖: ${REPORT_FOUND}/${REPORT_TOTAL}（覆盖率 ${COVERAGE}，阈值 ${QUALITY_THRESHOLD}）"
  echo "- 验收命令: ${VERIFY_RESULT}"
  echo "- 质量门: ${GATE}"
  if [[ -n "$MISSING_REPORTS" ]]; then
    echo "- 缺报告的 Manager: ${MISSING_REPORTS}"
  fi
  echo
  echo "## 下一步建议"
  echo
  echo "1. 看羊圈 workspace ${WORKSPACE_ID} 里各 Manager 的 tab"
  echo "2. 复核本报告里的 git diff 与验收输出"
  echo "3. 确认无误后再由主 Agent 决定是否 commit"
  echo
  echo "任务目录: ${TASK_DIR}"
  echo
} >> "$FINAL_REPORT"

echo ""
echo "=== 界王拳任务完成 ==="
echo "最终报告: $FINAL_REPORT"
echo "任务目录: $TASK_DIR"
if [[ -f "$INTERVENTION_LOG" && -s "$INTERVENTION_LOG" ]]; then
  echo "介入留证: $INTERVENTION_LOG"
fi
echo ""

if [[ "$GATE" == "通过" ]]; then
  echo "质量门: ✅ 通过"
  exit 0
fi

echo "质量门: ❌ 不通过（报告覆盖 ${REPORT_FOUND}/${REPORT_TOTAL}，验收 ${VERIFY_RESULT}）" >&2
exit 1
