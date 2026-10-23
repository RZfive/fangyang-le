#!/usr/bin/env bash
set -euo pipefail

WAIT_MS=0
LINES=160
CLOSE=0
MANIFEST=""
AGENTS=()

usage() {
  cat <<'EOF'
Usage: harvest.sh [options] <agent> [agent...]

Collect herdr agent output.

Options:
  --wait MS      Wait up to MS for each agent to become idle/done/blocked (default: 0 = no wait)
  --lines N      Read the last N lines (default: 160)
  --manifest P   Read agent names from a fanout manifest (tab-separated; column 4 = workspace)
  --close        Close each agent's pane after reading
  -h, --help     Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wait) WAIT_MS="$2"; shift 2 ;;
    --lines) LINES="$2"; shift 2 ;;
    --manifest) MANIFEST="$2"; shift 2 ;;
    --close) CLOSE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage; exit 2 ;;
    *) AGENTS+=("$1"); shift ;;
  esac
done

MANIFEST_WS_DATA=""
if [[ -n "$MANIFEST" ]]; then
  if [[ ! -f "$MANIFEST" ]]; then
    echo "manifest not found: $MANIFEST" >&2
    exit 2
  fi
  while IFS=$'\t' read -r name pane tab ws; do
    [[ -z "$name" || "$name" == "name" ]] && continue
    AGENTS+=("$name")
    [[ -n "${ws:-}" ]] && MANIFEST_WS_DATA="${MANIFEST_WS_DATA}${name}"$'\t'"${ws}"$'\n'
  done < "$MANIFEST"
fi

if [[ ${#AGENTS[@]} -eq 0 ]]; then
  usage
  exit 2
fi

json_get() {
  python3 -c 'import json,sys
obj=json.load(sys.stdin)
cur=obj
for key in sys.argv[1:]:
    cur=cur[key]
print(cur)' "$@"
}

manifest_ws() {
  # workspace recorded in the fanout manifest for an agent name (bash-3.2 safe lookup)
  printf '%s' "$MANIFEST_WS_DATA" | awk -F'\t' -v n="$1" '$1==n{print $2; exit}'
}

for name in "${AGENTS[@]}"; do
  echo "======================================================================"
  echo "agent: $name"

  # Cross-workspace guard: the flock must be harvested from the workspace that started it.
  mws="$(manifest_ws "$name")"
  if [[ -n "$mws" ]]; then
    if [[ -z "${HERDR_WORKSPACE_ID:-}" ]]; then
      echo "warn: manifest says workspace $mws, but HERDR_WORKSPACE_ID is unset here" >&2
    elif [[ "$mws" != "$HERDR_WORKSPACE_ID" ]]; then
      echo "warn: agent '$name' lives in workspace $mws, this shell is in $HERDR_WORKSPACE_ID — cross-workspace harvest; re-run from the workspace that started the flock" >&2
    fi
  fi

  if (( WAIT_MS > 0 )); then
    if herdr agent wait "$name" --until idle --timeout "$WAIT_MS"; then
      :
    else
      echo "wait timed out after ${WAIT_MS}ms, harvesting current output" >&2
    fi
  fi

  get_json="$(herdr agent get "$name" 2>/dev/null || true)"
  if [[ -z "$get_json" ]]; then
    echo "status: not found"
    continue
  fi
  status="$(printf '%s' "$get_json" | json_get result agent agent_status)"
  pane="$(printf '%s' "$get_json" | json_get result agent pane_id)"
  echo "status: $status"
  echo "pane:   $pane"
  echo "----------------------------------------------------------------------"

  out="$(herdr agent read "$name" --lines "$LINES" 2>/dev/null || true)"
  if [[ -z "$out" ]]; then
    out="$(herdr agent read "$name" --lines "$LINES" --source visible 2>/dev/null || true)"
  fi
  printf '%s\n' "$out"

  if (( CLOSE == 1 )) && [[ -n "$pane" ]]; then
    if [[ "$status" == "working" ]]; then
      echo "skip close: agent is still working" >&2
    else
      herdr pane close "$pane" >/dev/null || true
      echo "closed pane: $pane"
    fi
  fi
done
