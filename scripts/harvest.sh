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
  --manifest P   Read agent names from a fanout manifest (tab-separated)
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

if [[ -n "$MANIFEST" ]]; then
  if [[ ! -f "$MANIFEST" ]]; then
    echo "manifest not found: $MANIFEST" >&2
    exit 2
  fi
  while IFS=$'\t' read -r name pane tab; do
    [[ -z "$name" || "$name" == "name" ]] && continue
    AGENTS+=("$name")
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

for name in "${AGENTS[@]}"; do
  echo "======================================================================"
  echo "agent: $name"

  if (( WAIT_MS > 0 )); then
    if ! herdr agent wait "$name" --until idle --until done --until blocked --timeout "$WAIT_MS" >/dev/null; then
      echo "wait: timeout or error"
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

  if ! herdr agent read "$name" --lines "$LINES" 2>/dev/null; then
    herdr agent read "$name" --source visible 2>/dev/null || echo "(no readable output)"
  fi

  if (( CLOSE == 1 )) && [[ -n "$pane" ]]; then
    if [[ "$status" == "working" ]]; then
      echo "skip close: agent is still working" >&2
    else
      herdr pane close "$pane" >/dev/null || true
      echo "closed pane: $pane"
    fi
  fi
done
