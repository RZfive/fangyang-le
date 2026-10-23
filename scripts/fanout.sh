#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

COUNT=4
KIND=opencode
LABEL=""
CWD="$PWD"
PREFIX="worker"
OWNER="主控"
WORK=""
TASKS=""
FOCUS=0
WORKSPACE="${HERDR_WORKSPACE:-}"

usage() {
  cat <<'EOF'
Usage: fanout.sh [options]

Create a herdr tab with a 2-row agent grid and start agents in every pane.

Options:
  --count N        Number of agents, 2-8 (default: 4)
  --kind KIND      herdr agent kind, e.g. codex, claude, opencode (default: opencode)
  --label LABEL    Tab label (default: "<owner>的羊圈 · <work>")
  --owner NAME     Who owns this sheepfold (default: 主控)
  --work TEXT      What the group is working on (default: 并行任务)
  --tasks LIST     Comma-separated agent names, e.g. lsp,ui,bench
  --cwd PATH       Working directory for the tab (default: current directory)
  --prefix NAME    Fallback agent name prefix (default: worker)
  --focus          Focus the new tab after creation
  --workspace ID   herdr workspace id (default: focused workspace)
  -h, --help       Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --count) COUNT="$2"; shift 2 ;;
    --kind) KIND="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    --owner) OWNER="$2"; shift 2 ;;
    --work) WORK="$2"; shift 2 ;;
    --tasks) TASKS="$2"; shift 2 ;;
    --cwd) CWD="$2"; shift 2 ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    --focus) FOCUS=1; shift ;;
    --workspace) WORKSPACE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || (( COUNT < 2 || COUNT > 8 )); then
  echo "--count must be 2-8" >&2
  exit 2
fi
if [[ ! -d "$CWD" ]]; then
  echo "--cwd is not a directory: $CWD" >&2
  exit 2
fi
WORK="${WORK:-并行任务}"
LABEL="${LABEL:-${OWNER}的羊圈 · ${WORK}}"

TASK_NAMES=()
if [[ -n "$TASKS" ]]; then
  IFS=',' read -r -a TASK_NAMES <<< "$TASKS"
  if (( ${#TASK_NAMES[@]} != COUNT )); then
    echo "--tasks must contain exactly $COUNT names (got ${#TASK_NAMES[@]})" >&2
    exit 2
  fi
fi

json_get() {
  python3 -c 'import json,sys
obj=json.load(sys.stdin)
cur=obj
for key in sys.argv[1:]:
    cur=cur[key]
print(cur)' "$@"
}

if [[ -z "$WORKSPACE" ]]; then
  WORKSPACE="$(herdr workspace list | python3 -c 'import json,sys
obj=json.load(sys.stdin)
for ws in obj["result"]["workspaces"]:
    if ws.get("focused"):
        print(ws["workspace_id"]); break')"
fi
if [[ -z "$WORKSPACE" ]]; then
  echo "Could not determine focused herdr workspace. Pass --workspace." >&2
  exit 2
fi

FOCUS_FLAG="--no-focus"
if (( FOCUS == 1 )); then FOCUS_FLAG="--focus"; fi
TAB_JSON="$(herdr tab create --workspace "$WORKSPACE" --cwd "$CWD" --label "$LABEL" "$FOCUS_FLAG")"
ROOT_PANE="$(printf '%s' "$TAB_JSON" | json_get result root_pane pane_id)"
TAB_ID="$(printf '%s' "$TAB_JSON" | json_get result tab tab_id)"
MANIFEST="/tmp/herdr-${LABEL// /_}-agents.tsv"

COLS=$(( (COUNT + 1) / 2 ))
TOP_PANES=("$ROOT_PANE")
for ((i = 1; i < COLS; i++)); do
  NEXT="$(herdr pane split "${TOP_PANES[$((i - 1))]}" --direction right --cwd "$CWD" --no-focus | json_get result pane pane_id)"
  TOP_PANES+=("$NEXT")
done

PANES=("${TOP_PANES[@]}")
BOTTOM_NEEDED=$(( COUNT - COLS ))
for ((i = 0; i < BOTTOM_NEEDED; i++)); do
  NEXT="$(herdr pane split "${TOP_PANES[$i]}" --direction down --cwd "$CWD" --no-focus | json_get result pane pane_id)"
  PANES+=("$NEXT")
done

printf 'name\tpane\ttab\n' > "$MANIFEST"
echo "workspace: $WORKSPACE"
echo "tab:       $LABEL ($TAB_ID)"
echo "manifest:  $MANIFEST"
echo "agents:"

for ((i = 0; i < COUNT; i++)); do
  if (( ${#TASK_NAMES[@]} > 0 )); then
    NAME="${TASK_NAMES[$i]// /-}"
  else
    NAME="${PREFIX}-$((i + 1))"
  fi
  PANE="${PANES[$i]}"
  if herdr agent start "$NAME" --kind "$KIND" --pane "$PANE" --timeout 120000 >/dev/null; then
    printf '  %-20s %s\n' "$NAME" "$PANE"
    printf '%s\t%s\t%s\n' "$NAME" "$PANE" "$TAB_ID" >> "$MANIFEST"
  else
    printf '  %-20s %s  (start failed)\n' "$NAME" "$PANE" >&2
  fi
done

FIRST_NAME="${PREFIX}-1"
if (( ${#TASK_NAMES[@]} > 0 )); then
  FIRST_NAME="${TASK_NAMES[0]// /-}"
fi

cat <<EOF

Harvest with:
  "$SCRIPT_DIR/harvest.sh" --manifest "$MANIFEST" --wait 1800000 --close

Next:
  herdr agent prompt ${FIRST_NAME} "Read /tmp/task-1.md and execute it exactly. Stay in scope. Do not commit."
  herdr agent wait ${FIRST_NAME} --until idle --until done --until blocked --timeout 1800000
  herdr agent read ${FIRST_NAME} --lines 160
  herdr pane close <pane-id>

If an agent is blocked on /tmp permission:
  herdr agent send-keys ${FIRST_NAME} right enter
  herdr agent send-keys ${FIRST_NAME} enter
EOF
