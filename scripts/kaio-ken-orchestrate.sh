#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SKILL_DIR/lib/dbz-characters.sh"

REQUEST=""
MAX_MANAGERS=4
MAX_WORKERS_PER_MANAGER=3
CWD="$PWD"
AUTO_MODE=1
QUALITY_THRESHOLD=0.85
MAIN_AGENT_NAME=""
LOOP_INTERVAL=30
MAX_LOOPS=60
SPEC_FILE=""
# --verify 是可选项，但后面（SPEC 起草、验收、报告）都会读它；
# 在 set -u 下不预置空串，只要用户没传就整条流水线在第 1 阶段崩掉。
VERIFY_CMD=""
MAX_GOAL_ROUNDS=2
# 先初始化：收割函数会把「本轮 Goal 轮次」写进报告，首轮收割时
# 主循环还没开始，不初始化会在 set -u 下直接报 unbound variable。
GOAL_ROUND=0


# 按「字符数」截断，而不是按字节截断。
# bash 3.2 的 ${VAR:0:20} 在 LC_CTYPE=C 下按字节切，中文需求会被切在
# 多字节字符中间，得到非法 UTF-8；这个坏字符串会被写进 workspace 标签、
# tab 标签和 herdr-*-agents.tsv 文件名，最后在 printf 重定向处报
# "Illegal byte sequence" 把整条编排打断。
# 优先用 python3 做真正的字符级截断；没有 python3 时用 perl；都不可用
# 才退回纯 ASCII 过滤，宁短不乱码。
kaio_truncate_text() {
  local text="$1" limit="${2:-20}"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys;sys.stdout.write(sys.argv[1][:int(sys.argv[2])])' "$text" "$limit" && return 0
  fi
  if command -v perl >/dev/null 2>&1; then
    perl -CSA -e 'print substr($ARGV[0],0,$ARGV[1])' -- "$text" "$limit" && return 0
  fi
  printf '%s' "$text" | LC_ALL=C tr -cd '[:alnum:][:space:]-_.'
  return 0
}


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
  --spec PATH                 主 Agent 与用户聊透后写好的需求规格 markdown
                              不传则按请求推断一份草稿，并在报告里列出「未确认维度」
  --max-goal-rounds N         Goal 模式：质量门不通过时最多自动返工几轮，0-10（默认：2）
                              每轮把缺口重新派给 Manager，跑完再验收，直到通过或轮数用尽
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
    --spec) SPEC_FILE="$2"; shift 2 ;;
    --max-goal-rounds) MAX_GOAL_ROUNDS="$2"; shift 2 ;;
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

if ! [[ "$MAX_GOAL_ROUNDS" =~ ^[0-9]+$ ]] || (( MAX_GOAL_ROUNDS > 10 )); then
  echo "Error: --max-goal-rounds must be 0-10" >&2
  exit 2
fi

if [[ ! -d "$CWD" ]]; then
  echo "Error: --cwd is not a directory: $CWD" >&2
  exit 2
fi

# 规格文件必须是可读文件：传了路径却读不到，等于把「聊透的需求」丢了，
# 后面 Manager 会照推断草稿干活，必须在这里就停。
if [[ -n "$SPEC_FILE" ]]; then
  if [[ ! -f "$SPEC_FILE" ]]; then
    echo "Error: --spec is not a readable file: $SPEC_FILE" >&2
    exit 2
  fi
  if [[ ! -s "$SPEC_FILE" ]]; then
    echo "Error: --spec file is empty: $SPEC_FILE" >&2
    exit 2
  fi
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
    echo "  [auto] ${title}：自动继续"
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
    echo "  [auto-fallback] 没有可交互终端，无法确认「${title}」，按继续处理" >&2
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
MAIN_AGENT_NAME="$(get_main_agent_name)"
MAIN_AGENT_SLUG="$(dbz_agent_slug "$MAIN_AGENT_NAME" 2>/dev/null || printf '%s' "$MAIN_AGENT_NAME")"

# 分解库先加载：类型识别既是 SPEC 的推断依据，也是阶段 2 的骨架。
source "$SKILL_DIR/lib/decompose.sh"
source "$SKILL_DIR/lib/spec.sh"

WORK_NAME="$(kaio_truncate_text "$REQUEST" 20)…"  # 按字符截取前 20 个字符作为工作名
# `git rev-parse HEAD || echo unknown` 在空仓库里会先打印 "HEAD" 再拼接
# "unknown"，报告里就变成两行；分开取值才能只拿到一个值。
BASE_COMMIT="$(cd "$CWD" && git rev-parse HEAD 2>/dev/null || true)"
[[ -z "$BASE_COMMIT" ]] && BASE_COMMIT="unknown"

TASK_TYPE="$(identify_task_type "$REQUEST" "$CWD")"

# 主 Agent 的提问清单始终落盘：没用 --spec 时，它就是「还差一次对话」的凭据。
kaio_spec_interview_prompts > "$TASK_DIR/SPEC_QUESTIONS.md"

SPEC_PATH="$TASK_DIR/SPEC.md"
if [[ -n "$SPEC_FILE" ]]; then
  if ! cp "$SPEC_FILE" "$SPEC_PATH"; then
    echo "Error: 无法复制 --spec 文件到任务目录: $SPEC_FILE" >&2
    exit 1
  fi
  echo "✓ 需求规格: 使用 --spec ${SPEC_FILE}（已复制到 ${SPEC_PATH}）"
  record_decision "需求深挖" "使用 --spec 文件（${SPEC_FILE}）"
else
  echo "  未传 --spec：按请求推断规格草稿，自动推断的维度会在报告里逐条标出"
  if ! kaio_build_spec "$REQUEST" "$CWD" "$TASK_TYPE" "$VERIFY_CMD" "" "$SPEC_PATH"; then
    echo "Error: 生成 SPEC 草稿失败" >&2
    exit 1
  fi
  echo "✓ 需求规格草稿: $SPEC_PATH"
  echo "  提问清单: $TASK_DIR/SPEC_QUESTIONS.md（下次用 --spec 传入确认结果）"
  record_decision "需求深挖" "按请求推断规格草稿（未经用户确认）"
fi

echo "✓ 工作名: $WORK_NAME"
echo "✓ 任务类型: $TASK_TYPE"
echo "✓ Base commit: $BASE_COMMIT"
echo ""

echo "【阶段 2/7】任务分解..."


# 分解为 Manager 任务：模块 scope + 二线角色名。
# 返回格式：每行 display|module-slug|scope|dependencies
MANAGER_TASKS=$(decompose_by_type "$TASK_TYPE" "$REQUEST" "$CWD" "$MAX_MANAGERS")

ACTUAL_MANAGER_COUNT=$(printf '%s\n' "$MANAGER_TASKS" | grep -c . || true)

echo "✓ 已分解为 $ACTUAL_MANAGER_COUNT 个 Manager 任务"
echo "$MANAGER_TASKS" | nl
echo ""

# 第一个关键决策点：分解结果就是整条流水线的骨架，改起来最贵。
if ! confirm_decision "确认任务分解（${TASK_TYPE}，$ACTUAL_MANAGER_COUNT 个 Manager）" \
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
MANAGER_TASK_WORKS=()
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
# 验收口径统一来自 SPEC：有 --verify 就把命令原样交给 Manager，没有就说明
# 质量门只能靠报告覆盖率，避免 Manager 自己编一套验收标准。
# 必须在下面的 sed 循环之前定义：循环里第一个 Manager 就要用到这两个变量。
if [[ -n "$VERIFY_CMD" ]]; then
  ACCEPTANCE_CMD_TEXT="$VERIFY_CMD"
  ACCEPTANCE_CRITERIA_TEXT="\`${VERIFY_CMD}\` 在 $CWD 下执行 exit 0；本模块所有 Worker 完成且无越界修改"
else
  ACCEPTANCE_CMD_TEXT="# 没有传 --verify：质量门只靠报告覆盖率，验收标准见 $SPEC_PATH"
  ACCEPTANCE_CRITERIA_TEXT="本模块所有 Worker 完成、写报告、无越界修改（未传 --verify，无法自动断言）"
fi


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
  MANAGER_TASK_WORKS+=("${module_name} · ${WORK_NAME}")

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
    -e "s|{{SPEC_PATH}}|$SPEC_PATH|g" \
    -e "s|{{MAIN_AGENT_SLUG}}|$MAIN_AGENT_SLUG|g" \
    -e "s|{{MAX_WORKERS}}|$MAX_WORKERS_PER_MANAGER|g" \
    -e "s|{{ACCEPTANCE_COMMANDS}}|${ACCEPTANCE_CMD_TEXT}|g" \
    -e "s|{{ACCEPTANCE_CRITERIA}}|$ACCEPTANCE_CRITERIA_TEXT|g" \
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


# 第二个关键决策点：这里是真正开始烧 token / 起进程的边界。
if ! confirm_decision "启动 $ACTUAL_MANAGER_COUNT 个 Manager（每人不超 $MAX_WORKERS_PER_MANAGER 个 Worker）" \
  "$(printf 'Workspace: %s\n任务目录: %s\n角色: %s\n\n启动后 Manager 会自行 fanout Worker 并写报告，中途只监控不代劳。' \
    "$WORKSPACE_ID" "$TASK_DIR" "${MANAGER_NAMES[*]:-无}")"; then
  echo "已按用户选择中止：workspace $WORKSPACE_ID 已创建但未启动任何 agent。" >&2
  echo "如需清理：herdr workspace delete $WORKSPACE_ID" >&2
  exit 3
fi


# 所有 Manager 并列在同一个「指挥部」Tab 里网格布局：workspace 结构变成
# 指挥部 Tab（全部 Manager 并列）→ 每 Manager 一个独立 Worker 圈 Tab，
# 领导和 Worker 在 tab 列表里一眼可分。一次 fanout 在新 Tab 里铺 N 格网格
# 并逐格启动 Manager；manifest 记录同一 Tab 下的全部 Manager（tier=manager，
# 不带 -workers 后缀，与 Worker 圈清单天然分流），后续派发/监控按真实
# agent 名逐个进行。
MANAGER_CSV="$(IFS=,; printf '%s' "${MANAGER_PLANNED[*]}")"
HQ_LABEL="${MAIN_AGENT_NAME}的界王拳指挥部 · ${WORK_NAME}"
MANAGER_FANOUT_OUTPUT="$(bash "$SKILL_DIR/scripts/fanout.sh" \
  --count "$ACTUAL_MANAGER_COUNT" \
  --kind auto \
  --label "$HQ_LABEL" \
  --work "${WORK_NAME} 指挥部" \
  --dbz-tier manager \
  --dbz-owner "$MAIN_AGENT_SLUG" \
  --dbz-parent "$MAIN_AGENT_SLUG" \
  --dbz-root "$MAIN_AGENT_SLUG" \
  --tasks "$MANAGER_CSV" \
  --workspace "$WORKSPACE_ID" \
  --cwd "$CWD" \
  --tasks-dir "$TASK_DIR" \
  --no-controller-rename 2>&1)" || {
  printf '%s\n' "$MANAGER_FANOUT_OUTPUT" >&2
  echo "Error: 指挥部 Tab（${HQ_LABEL}）创建失败" >&2
  exit 1
}
printf '%s\n' "$MANAGER_FANOUT_OUTPUT"

manager_manifest="$(printf '%s\n' "$MANAGER_FANOUT_OUTPUT" | sed -n 's/^manifest:[[:space:]]*//p' | tail -n 1)"
if [[ -z "$manager_manifest" || ! -f "$manager_manifest" ]]; then
  echo "Error: fanout 未返回指挥部 manifest" >&2
  exit 1
fi
MANAGER_ACTUAL_NAMES=()
while IFS=$'\t' read -r m_name _m_rest; do
  [[ -z "$m_name" || "$m_name" == "name" ]] && continue
  [[ "$m_name" == \#* ]] && continue
  MANAGER_ACTUAL_NAMES+=("$m_name")
done < "$manager_manifest"
if (( ${#MANAGER_ACTUAL_NAMES[@]} == 0 )); then
  echo "Error: 指挥部 manifest 没有已启动的 agent: $manager_manifest" >&2
  exit 1
fi
if (( ${#MANAGER_ACTUAL_NAMES[@]} != ACTUAL_MANAGER_COUNT )); then
  echo "Error: 指挥部启动的 Manager 数量不符（${#MANAGER_ACTUAL_NAMES[@]}/${ACTUAL_MANAGER_COUNT}）" >&2
  exit 1
fi
MANAGER_DBZ_MAP="${manager_manifest}.dbz-names"
echo "✓ ${#MANAGER_ACTUAL_NAMES[@]} 个 Manager 已并列进入指挥部 Tab（${HQ_LABEL}），manifest: $manager_manifest"

# ============================================================================
# 阶段 5：派发任务给 Manager
# ============================================================================
echo "【阶段 5/7】派发任务给所有 Manager..."

MODULE_SLUGS=()
while IFS=$'\t' read -r m_module _m_slug; do
  [[ -z "$m_module" ]] && continue
  MODULE_SLUGS+=("$m_module")
done < "$MANAGER_MAP_FILE"

# 每个 Manager 的 manifest、实际 agent 名、规划 slug 和模块按同一索引对齐。
# 这样即使 herdr 为某个名字追加 -2/-3，任务也不会错派到另一个 Tab。
MANIFEST_COUNT=${#MANAGER_ACTUAL_NAMES[@]}
PLANNED_COUNT=${#MANAGER_SLUGS[@]}
MODULE_COUNT=${#MODULE_SLUGS[@]}
if (( MANIFEST_COUNT != PLANNED_COUNT || MODULE_COUNT != PLANNED_COUNT )); then
  echo "Error: Manager 索引不一致（manifest=$MANIFEST_COUNT planned=$PLANNED_COUNT modules=${MODULE_COUNT}）" >&2
  exit 1
fi

for ((i = 0; i < MANIFEST_COUNT; i++)); do
  manager_slug="${MANAGER_ACTUAL_NAMES[$i]}"
  planned_slug="${MANAGER_SLUGS[$i]}"
  task_file="$TASK_DIR/${planned_slug}-task.md"
  manager_map="$MANAGER_DBZ_MAP"
  manager_name="$(dbz_manifest_display_name "$manager_map" "$manager_slug")"

  if [[ ! -f "$task_file" ]]; then
    echo "Error: Task file not found for $manager_slug: $task_file" >&2
    exit 1
  fi

  # 撞名加了后缀时，把任务文件里的规划 slug 换成真实 agent 名，
  # 这样报告路径 <真实名>-report.md 和阶段 7 的收割路径一致。
  if [[ "$manager_slug" != "$planned_slug" ]]; then
    task_tmp="$task_file.tmp.$$"
    sed -e "s|${planned_slug}|${manager_slug}|g" "$task_file" > "$task_tmp" \
      && mv "$task_tmp" "$task_file"
  fi

  echo "→ 派发任务给 $manager_name ($manager_slug) · 模块 ${MODULE_SLUGS[$i]} ..."
  herdr agent prompt "$manager_slug" \
    "Read $task_file and follow it step by step. You are a Manager, not a Worker. Your job is to decompose your task scope, create Worker task files, launch Workers using fanout.sh (each Manager's Worker flock opens its own tab; the HQ tab stays Managers-only), harvest results, verify quality, and write a report to $TASK_DIR/${manager_slug}-report.md. Do not commit."
done

# 监控与收割也要用真实 agent 名。
MANAGER_SLUGS=("${MANAGER_ACTUAL_NAMES[@]}")


echo "✓ 所有 Manager 已收到任务"
echo ""
echo ""

# ============================================================================
# 阶段 6 + 7：Loop 监控、收割与验收（函数化，Goal 模式要反复跑）
# ============================================================================
INTERVENTION_LOG="$TASK_DIR/.interventions.log"

# 跑到所有 Manager 停手，或用尽 --max-loops。
# 结果写入全局：LOOP_COUNT / LAST_STATUS / ALL_SETTLED。
kaio_monitor_managers() { # <轮次标签>
  local round_label="${1:-}"
  echo "【阶段 6/7】Loop 管理（监控 $ACTUAL_MANAGER_COUNT 个 Manager）..."
  [[ -n "$round_label" ]] && echo "  本轮: $round_label"
  echo "轮询: 每 ${LOOP_INTERVAL}s 一次，最多 ${MAX_LOOPS} 轮（--max-loops / --loop-interval 可调）"
  echo ""

  : > "$INTERVENTION_LOG"
  LOOP_COUNT=0
  LAST_STATUS=""
  ALL_SETTLED=0

  while (( LOOP_COUNT < MAX_LOOPS )); do

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
}

# 收割报告 + git 现状 + 验收命令 + 质量门。
# 结果写入全局：FINAL_REPORT / REPORT_FOUND / REPORT_TOTAL / MISSING_REPORTS /
# COVERAGE / VERIFY_RESULT / VERIFY_RC / VERIFY_OUTPUT / GATE。
kaio_harvest_and_verify() { # <轮次标签>
  local round_label="${1:-}"
  echo "【阶段 7/7】收割 Manager 报告并聚合..."
  [[ -n "$round_label" ]] && echo "  本轮: $round_label"

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
  echo "Loop 轮询: $LOOP_COUNT 轮（上限 ${MAX_LOOPS}）"
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
    echo "⚠️  验收命令失败（exit ${VERIFY_RC}），完整输出已写入报告" >&2
  fi
fi

# 质量门：报告覆盖率 + 验收命令。两者都过才算通过。
# 变量不回退到 local：Goal 模式的主循环靠它们判断要不要返工。
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
  echo "- Goal 轮次: ${GOAL_ROUND}/${MAX_GOAL_ROUNDS}"
  echo "- 报告覆盖: ${REPORT_FOUND}/${REPORT_TOTAL}（覆盖率 ${COVERAGE}，阈值 ${QUALITY_THRESHOLD}）"
  echo "- 验收命令: ${VERIFY_RESULT}"
  echo "- 质量门: ${GATE}"
  if [[ -n "$MISSING_REPORTS" ]]; then
    echo "- 缺报告的 Manager: ${MISSING_REPORTS}"
  fi
  echo
  echo "## 下一步建议"
  echo
  echo "1. 看羊圈 workspace ${WORKSPACE_ID}：指挥部 Tab 里是全部 Manager，各 Worker 圈 Tab 按经理分列"
  echo "2. 复核本报告里的 git diff 与验收输出"
  echo "3. 确认无误后再由主 Agent 决定是否 commit"
  echo
  echo "任务目录: ${TASK_DIR}"
  echo
} >> "$FINAL_REPORT"
}

# 把这一轮的质量缺口写成返工任务书：Goal 模式让 Manager 照单补，
# 而不是把整份原始需求再丢回去重做一遍。
kaio_write_gap_file() { # <轮次> <输出文件>
  local round="$1" out_file="$2"
  {
    echo "# Goal 返工任务 · 第 ${round} 轮"
    echo
    echo "任务: $REQUEST"
    echo "需求规格: $SPEC_PATH"
    echo
    echo "上一轮质量门: ${GATE}（报告覆盖 ${REPORT_FOUND}/${REPORT_TOTAL}，覆盖率 ${COVERAGE}，阈值 ${QUALITY_THRESHOLD}）"
    echo "上一轮验收: $VERIFY_RESULT"
    echo
    echo "## 必须补齐的缺口"
    echo
    if [[ -n "$MISSING_REPORTS" ]]; then
      echo "1. 以下 Manager 没有交报告（在 \$TASK_DIR 下写 <你的 agent 名>-report.md）："
      printf '   - %s\n' $MISSING_REPORTS
    fi
    if (( VERIFY_RC != 0 )); then
      echo "2. 验收命令仍未通过，失败输出（尾部）："
      echo
      echo '```'
      printf '%s\n' "$VERIFY_OUTPUT" | tail -n 80
      echo '```'
    fi
    echo
    echo "## 你要做的事"
    echo
    echo "1. 先读 ${SPEC_PATH}，确认自己模块的验收标准"
    echo "2. 只看与自己模块相关的缺口，不要重写已完成的部分"
    echo "3. 缺什么补什么，补完在 \$TASK_DIR 写 <你的 agent 名>-report.md"
    echo "4. 不要 commit，不要改本模块 write scope 以外的文件"
    echo
    echo "## 验收命令（主 Agent 会再跑一遍）"
    echo
    echo '```bash'
    echo "${VERIFY_CMD:-未传 --verify，质量门只靠报告覆盖率}"
    echo '```'
  } > "$out_file"
}

# 把所有 Manager 拉起来补缺口。
kaio_dispatch_rework() { # <轮次> <任务书路径>
  local round="$1" gap_file="$2" slug
  for slug in "${MANAGER_SLUGS[@]}"; do
    [[ -z "$slug" ]] && continue
    echo "→ 返工派发 $slug ..."
    herdr agent prompt "$slug" \
      "Goal round ${round}: 质量门未通过。Read $gap_file and $SPEC_PATH, fix ONLY the gaps in your module, then rewrite $TASK_DIR/${slug}-report.md. Do not commit." \
      || echo "Warning: 返工派发给 $slug 失败（agent 可能已退出）" >&2
  done
}

echo ""
echo "开始 Loop 管理（第 1 轮）..."
echo ""
kaio_monitor_managers "第 1 轮"
echo ""
# 首轮也必须收割：GATE/COVERAGE 只有收割后才有值，少了这步 Goal 循环
# 会拿未初始化的变量做判断，报告里也不会出现 round-0 的快照。
kaio_harvest_and_verify "第 1 轮"
cp "$FINAL_REPORT" "$TASK_DIR/FINAL_REPORT-round-0.md" 2>/dev/null || true

# ============================================================================
# Goal 模式：质量门不通过就自动返工，直到通过或用尽 --max-goal-rounds
# ============================================================================
GOAL_ROUND=0
while [[ "$GATE" != "通过" ]] && (( GOAL_ROUND < MAX_GOAL_ROUNDS )); do
  GOAL_ROUND=$((GOAL_ROUND + 1))
  echo ""
  echo "=============================================="
  echo "【Goal 模式】第 ${GOAL_ROUND}/${MAX_GOAL_ROUNDS} 轮自动返工"
  echo "  上一轮: 覆盖率 ${COVERAGE}（阈值 ${QUALITY_THRESHOLD}），验收 ${VERIFY_RESULT}"
  echo "=============================================="

  GAP_FILE="$TASK_DIR/GOAL-ROUND-${GOAL_ROUND}-GAPS.md"
  kaio_write_gap_file "$GOAL_ROUND" "$GAP_FILE"
  record_decision "Goal 轮次 ${GOAL_ROUND}" "质量门不通过（覆盖率 ${COVERAGE}，验收 ${VERIFY_RESULT}），派发返工任务书 ${GAP_FILE}"

  kaio_dispatch_rework "$GOAL_ROUND" "$GAP_FILE"
  kaio_monitor_managers "返工轮 ${GOAL_ROUND}"
  kaio_harvest_and_verify "返工轮 ${GOAL_ROUND}"
  cp "$FINAL_REPORT" "$TASK_DIR/FINAL_REPORT-round-${GOAL_ROUND}.md" 2>/dev/null || true

done

if (( GOAL_ROUND > 0 )) && [[ "$GATE" != "通过" ]]; then
  record_decision "Goal 结束" "用尽 ${MAX_GOAL_ROUNDS} 轮返工仍未通过，升级给主 Agent"
  echo ""
  echo "⚠️  Goal 模式已用尽 ${MAX_GOAL_ROUNDS} 轮返工，质量门仍不通过（需主 Agent 接管）。" >&2
fi

echo ""
echo "=== 界王拳任务完成 ==="
echo "最终报告: $FINAL_REPORT"
echo "任务目录: $TASK_DIR"
if (( GOAL_ROUND > 0 )); then
  echo "Goal 轮次: ${GOAL_ROUND}/${MAX_GOAL_ROUNDS} 轮返工"
fi
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
