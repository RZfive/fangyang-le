#!/usr/bin/env bash
set -euo pipefail

WAIT_MS=0
LINES=160
CLOSE=0
CLOSE_TAB=0
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
  --close        Close each agent's pane after reading (use after review; panes stay open by default)
  --close-tab    Close the whole sheepfold tab(s) from the manifest after reading
                 (use only after the user has reviewed and confirmed); also
                 restores the controller tab's original label recorded by fanout
                 (#controller_tab_* metadata; old manifests without it are skipped)
  -h, --help     Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wait) WAIT_MS="$2"; shift 2 ;;
    --lines) LINES="$2"; shift 2 ;;
    --manifest) MANIFEST="$2"; shift 2 ;;
    --close) CLOSE=1; shift ;;
    --close-tab) CLOSE_TAB=1; shift ;;
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
    [[ "$name" == \#* ]] && continue   # fanout metadata (#controller_tab_*=...)
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

manifest_meta() {
  # fanout metadata value: manifest_meta controller_tab_label reads "#controller_tab_label=<value>"
  [[ -n "${MANIFEST:-}" ]] || return 0
  sed -n "s/^#$1=//p" "$MANIFEST" | head -n 1
}

ANY_WORKING=0
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

  if [[ "$status" == "working" ]]; then
    ANY_WORKING=1
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

# Default: keep the fold open for review (iron rule: harvest does not tear down the fold)
if (( CLOSE == 0 && CLOSE_TAB == 0 )); then
  echo "======================================================================"
  echo "flock kept open for review; close with:"
  if [[ -n "$MANIFEST" ]]; then
    echo "  \"$0\" --manifest \"$MANIFEST\" --close-tab   # after user confirmed"
  else
    echo "  herdr pane close <pane-id> / herdr tab close <tab-id>   # after user confirmed"
  fi
fi

# --close-tab: close the whole sheepfold tab(s), skipped if any agent is still working
if (( CLOSE_TAB == 1 )); then
  if [[ -z "$MANIFEST" ]]; then
    echo "--close-tab needs --manifest (no tab ids available)" >&2
    exit 2
  elif (( ANY_WORKING == 1 )); then
    echo "skip close-tab: at least one agent is still working" >&2
  else
    for t in $(awk -F'\t' 'NR>1 && $3!="" {print $3}' "$MANIFEST" | sort -u); do
      if herdr tab close "$t" >/dev/null 2>&1; then
        echo "closed tab: $t"
      else
        echo "warn: could not close tab $t" >&2
      fi
    done
    # Restore the controller tab's original label (renamed by fanout).
    ctrl_id="$(manifest_meta controller_tab_id)"
    ctrl_label="$(manifest_meta controller_tab_label)"
    if [[ -n "$ctrl_id" && -n "$ctrl_label" ]]; then
      if herdr tab rename "$ctrl_id" "$ctrl_label" >/dev/null 2>&1; then
        echo "restored controller tab label: $ctrl_id -> '$ctrl_label'"
      else
        echo "warn: closed the fold but could not restore controller tab $ctrl_id label '$ctrl_label'" >&2
      fi
    fi
  fi
fi