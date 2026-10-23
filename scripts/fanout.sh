#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

COUNT=4
KIND=auto
LABEL=""
CWD="$PWD"
PREFIX="worker"
OWNER="主控"
WORK=""
TASKS=""
FOCUS=0
WORKSPACE="${HERDR_WORKSPACE_ID:-}"
TASKS_DIR=""

usage() {
  cat <<'EOF'
Usage: fanout.sh [options]

Create a herdr tab with a 2-row agent grid and start agents in every pane.

Options:
  --count N        Number of agents, 2-8 (default: 4)
  --kind KIND      Agent kind; "auto" = same kind as this pane's agent,
                   e.g. claude spawns claude, opencode spawns opencode (default: auto)
  --label LABEL    Tab label (default: "<owner>的羊圈 · <work>")
  --owner NAME     Who owns this sheepfold (default: 主控)
  --work TEXT      What the group is working on (default: 并行任务)
  --tasks LIST     Comma-separated agent names, e.g. lsp,ui,bench
  --cwd PATH       Working directory for the tab (default: current directory)
  --tasks-dir PATH Directory for task files + manifest (default: <cwd>/.fangyang).
                   Keeping task files inside the repo avoids per-agent /tmp permission
                   prompts; the directory is auto-added to .gitignore when possible.
  --prefix NAME    Fallback agent name prefix (default: worker)
  --focus          Focus the new tab after creation
  --workspace ID   herdr workspace id (default: this pane's $HERDR_WORKSPACE_ID;
                   passing a different id is a deliberate cross-workspace override
                   and prints a warning)
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
    --tasks-dir) TASKS_DIR="$2"; shift 2 ;;
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

# Rule 1: sheep stay in the controller's own workspace.
# Never fall back to the "focused" workspace — focus may point at another
# controller's sheepfold, which would silently cross workspaces.
if [[ -z "$WORKSPACE" ]]; then
  if [[ -z "${HERDR_WORKSPACE_ID:-}" ]]; then
    echo "Not running inside a herdr pane (HERDR_WORKSPACE_ID is unset)." >&2
    echo "Run fanout.sh from the controller's pane so sheep land in the same workspace." >&2
    echo "Only pass --workspace explicitly when crossing workspaces is truly intended." >&2
    exit 2
  fi
  WORKSPACE="$HERDR_WORKSPACE_ID"
fi
if [[ -n "${HERDR_WORKSPACE_ID:-}" && "$WORKSPACE" != "$HERDR_WORKSPACE_ID" ]]; then
  echo "WARNING: --workspace '$WORKSPACE' differs from this pane's workspace '$HERDR_WORKSPACE_ID'." >&2
  echo "WARNING: cross-workspace fanout — these sheep will NOT stay in the controller's workspace." >&2
fi

# Rule 2: spawn the same agent kind as the controller.
# claude spawns claude, opencode spawns opencode, codex spawns codex.
KIND_AUTO=0
if [[ -z "$KIND" || "$KIND" == "auto" ]]; then
  KIND_AUTO=1
  SELF_KIND=""
  if [[ -n "${HERDR_PANE_ID:-}" ]]; then
    SELF_KIND="$(herdr agent get "$HERDR_PANE_ID" 2>/dev/null | python3 -c 'import json,sys
try:
    a = json.load(sys.stdin)["result"]["agent"]
    print(a.get("agent") or a.get("agent_kind") or "")
except Exception:
    print("")' || true)"
  fi
  if [[ -z "$SELF_KIND" ]]; then
    echo "Could not detect this pane's agent kind (is the controller a recognized herdr agent?)." >&2
    echo "Pass --kind explicitly, e.g. --kind claude / --kind opencode / --kind codex." >&2
    exit 2
  fi
  KIND="$SELF_KIND"
fi

# Rule 3: task files live INSIDE the repo (cwd), not /tmp.
# Agents prompt for permission on paths outside their cwd; keeping task files
# under <cwd>/.fangyang makes fanout painless to start — zero permission dialogs.
if [[ -z "$TASKS_DIR" ]]; then
  TASKS_DIR="$CWD/.fangyang"
fi
mkdir -p "$TASKS_DIR"
if [[ -d "$CWD/.git" ]] && ! grep -qs '^\.fangyang/$' "$CWD/.gitignore" 2>/dev/null; then
  printf '\n# fangyang (放羊) task files and manifests\n.fangyang/\n' >> "$CWD/.gitignore"
  echo "gitignore: added .fangyang/ to $CWD/.gitignore"
fi

MANIFEST="$TASKS_DIR/herdr-${LABEL// /_}-agents.tsv"
FOCUS_FLAG="--no-focus"
if (( FOCUS == 1 )); then FOCUS_FLAG="--focus"; fi
TAB_JSON="$(herdr tab create --workspace "$WORKSPACE" --cwd "$CWD" --label "$LABEL" "$FOCUS_FLAG")"
ROOT_PANE="$(printf '%s' "$TAB_JSON" | json_get result root_pane pane_id)"
TAB_ID="$(printf '%s' "$TAB_JSON" | json_get result tab tab_id)"

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

printf 'name\tpane\ttab\tworkspace\n' > "$MANIFEST"
KIND_SRC="explicit"
if (( KIND_AUTO )); then KIND_SRC="same as controller"; fi
echo "workspace: $WORKSPACE"
echo "kind:      $KIND ($KIND_SRC)"
echo "tab:       $LABEL ($TAB_ID)"
echo "manifest:  $MANIFEST"
echo "tasks:     write per-agent task files to $TASKS_DIR/<name>-task.md (repo-relative; avoids /tmp permission prompts)"
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
    printf '%s\t%s\t%s\t%s\n' "$NAME" "$PANE" "$TAB_ID" "$WORKSPACE" >> "$MANIFEST"
  else
    printf '  %-20s %s  (start failed)\n' "$NAME" "$PANE" >&2
  fi
done

FIRST_NAME="${PREFIX}-1"
if (( ${#TASK_NAMES[@]} > 0 )); then
  FIRST_NAME="${TASK_NAMES[0]// /-}"
fi

# Path referenced in the first-sheep prompt: repo-relative when the tasks dir
# lives under --cwd (cleaner prompt), absolute otherwise (still unambiguous).
FIRST_TASK_FILE="$TASKS_DIR/${FIRST_NAME}-task.md"
case "$FIRST_TASK_FILE" in
  "$CWD"/*) FIRST_TASK_FILE="${FIRST_TASK_FILE#"$CWD"/}" ;;
esac

cat <<EOF

Harvest with (flock stays open for review):
  "$SCRIPT_DIR/harvest.sh" --manifest "$MANIFEST" --wait 1800000

After the user has reviewed and confirmed, close the whole fold:
  "$SCRIPT_DIR/harvest.sh" --manifest "$MANIFEST" --close-tab

Next:
  herdr agent prompt ${FIRST_NAME} "Read ${FIRST_TASK_FILE} and execute it exactly. Stay in scope. Do not commit."
  herdr agent wait ${FIRST_NAME} --until idle --until done --until blocked --timeout 1800000
  herdr agent read ${FIRST_NAME} --lines 160

If an agent still hits an external-directory permission prompt (only when task
files were placed outside the repo, e.g. /tmp):
  herdr agent send-keys ${FIRST_NAME} right enter
  herdr agent send-keys ${FIRST_NAME} enter
EOF
