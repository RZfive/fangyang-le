#!/usr/bin/env bash
# Stub-based tests for the controller-tab pairing feature in fanout.sh / harvest.sh.
#
# Runs fully offline: a fake `herdr` is put on PATH, records every invocation to a
# log file and returns canned JSON. No live herdr session is touched.
#
# Covered:
#   T1  fanout renames the controller tab to "<owner> · <work>" and records
#       #controller_tab_* metadata in the manifest
#   T2  harvest ignores "#"-metadata lines when reading agents from a manifest
#   T3  harvest --close-tab closes the pen tab and restores the controller label
#   T4  old manifests without metadata still close fine, no restore attempted
#   T5  fanout outside a herdr pane (no HERDR_TAB_ID) skips renaming silently
#   T6  if `herdr tab rename` fails, fanout still succeeds without metadata
set -u

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$TESTS_DIR")"

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fangyang-test.XXXXXX")"
export TEST_DIR
STUB_BIN="$TEST_DIR/bin"
LOG="$TEST_DIR/herdr-calls.log"
export LOG
mkdir -p "$STUB_BIN"

FAIL=0

cleanup() {
  if [ "$FAIL" -eq 0 ]; then
    rm -rf "$TEST_DIR"
  else
    echo "kept for debugging: $TEST_DIR" >&2
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------------- fake herdr
cat > "$STUB_BIN/herdr" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$LOG"
case "$1 $2" in
  "tab create")
    echo '{"result":{"tab":{"tab_id":"wT:tPEN"},"root_pane":{"pane_id":"wT:pROOT"}}}'
    ;;
  "tab get")
    echo "{\"result\":{\"tab\":{\"tab_id\":\"$3\",\"label\":$(cat "$TEST_DIR/ctrl_label")}}}"
    ;;
  "pane split")
    n="$(cat "$TEST_DIR/paneseq" 2>/dev/null || echo 0)"
    n=$((n + 1))
    echo "$n" > "$TEST_DIR/paneseq"
    echo "{\"result\":{\"pane\":{\"pane_id\":\"wT:pS$n\"}}}"
    ;;
  "agent get")
    if [ -n "${HERDR_PANE_ID:-}" ] && [ "$3" = "$HERDR_PANE_ID" ]; then
      echo '{"result":{"agent":{"agent":"claude"}}}'
    else
      echo "{\"result\":{\"agent\":{\"agent\":\"$3\",\"agent_status\":\"idle\",\"pane_id\":\"wT:pA1\"}}}"
    fi
    ;;
  "agent start")
    echo '{"result":{"agent":{"agent":"x"}}}'
    ;;
  "agent wait")
    exit 0
    ;;
  "agent read")
    echo "[stub output of $3]"
    ;;
  "tab rename")
    [ -f "$TEST_DIR/rename_fails" ] && exit 1
    exit 0
    ;;
  "tab close"|"pane close")
    exit 0
    ;;
  *)
    echo "stub: unhandled command: $*" >&2
    exit 64
    ;;
esac
STUB
chmod +x "$STUB_BIN/herdr"

# The controller tab's "original" label, as a JSON string.
printf '"1"\n' > "$TEST_DIR/ctrl_label"

PATH="$STUB_BIN:$PATH"
export PATH

export HERDR_WORKSPACE_ID=wT
export HERDR_PANE_ID=wT:pCTRL
export HERDR_TAB_ID=wT:tCTRL

# ---------------------------------------------------------------- assertions
pass() { echo "ok:   $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }

assert_contains() { # <desc> <file> <needle>
  if grep -qF -- "$3" "$2"; then pass "$1"; else fail "$1 — expected in $2: $3"; fi
}
assert_not_contains() { # <desc> <file> <needle>
  if grep -qF -- "$3" "$2"; then fail "$1 — unexpected in $2: $3"; else pass "$1"; fi
}

echo "== T1: fanout renames the controller tab and records metadata =="
mkdir -p "$TEST_DIR/repo"
: > "$LOG"
if bash "$REPO_DIR/scripts/fanout.sh" --cwd "$TEST_DIR/repo" --count 2 \
     --owner 主控 --work 试点A --tasks a1,a2 > "$TEST_DIR/t1-out.txt" 2>&1; then
  pass "fanout exits 0"
else
  fail "fanout exited non-zero"; cat "$TEST_DIR/t1-out.txt"
fi
T1_MANIFEST="$(find "$TEST_DIR/repo/.fangyang" -name '*-agents.tsv' | head -n 1)"
[ -n "$T1_MANIFEST" ] && pass "manifest created" || fail "manifest missing"

assert_contains "queries controller tab id"        "$LOG" "tab get wT:tCTRL"
assert_contains "renames controller tab"           "$LOG" "tab rename wT:tCTRL 主控 · 试点A"
assert_contains "records controller tab id"        "$T1_MANIFEST" "#controller_tab_id=wT:tCTRL"
assert_contains "records original label"           "$T1_MANIFEST" "#controller_tab_label=1"
assert_contains "prints ctrl tab note"             "$TEST_DIR/t1-out.txt" "ctrl tab:"
assert_contains "manifest still lists agents"      "$T1_MANIFEST" "a1	wT:pROOT	wT:tPEN	wT"

echo "== T2: harvest skips # metadata lines when parsing the manifest =="
: > "$LOG"
bash "$REPO_DIR/scripts/harvest.sh" --manifest "$T1_MANIFEST" > "$TEST_DIR/t2-out.txt" 2>&1
assert_contains "harvests agent a1"    "$LOG" "agent get a1"
assert_contains "harvests agent a2"    "$LOG" "agent get a2"
assert_not_contains "metadata not treated as agent" "$LOG" "agent get #controller"

echo "== T3: harvest --close-tab restores the controller tab label =="
: > "$LOG"
bash "$REPO_DIR/scripts/harvest.sh" --manifest "$T1_MANIFEST" --close-tab \
  > "$TEST_DIR/t3-out.txt" 2>&1
assert_contains "closes the pen tab"       "$LOG" "tab close wT:tPEN"
assert_contains "restores original label"  "$LOG" "tab rename wT:tCTRL 1"
assert_contains "prints restore note"      "$TEST_DIR/t3-out.txt" "restored controller tab label"

echo "== T4: old manifest without metadata still closes, no restore =="
OLD_MANIFEST="$TEST_DIR/old-agents.tsv"
printf 'name\tpane\ttab\tworkspace\nold1\twT:p1\twT:tOLD\twT\n' > "$OLD_MANIFEST"
: > "$LOG"
bash "$REPO_DIR/scripts/harvest.sh" --manifest "$OLD_MANIFEST" --close-tab \
  > "$TEST_DIR/t4-out.txt" 2>&1
assert_contains "closes the old pen tab"  "$LOG" "tab close wT:tOLD"
assert_not_contains "no rename on old manifest" "$LOG" "tab rename"

echo "== T5: fanout outside a herdr pane skips renaming silently =="
mkdir -p "$TEST_DIR/repo2"
: > "$LOG"
if (unset HERDR_TAB_ID;
     bash "$REPO_DIR/scripts/fanout.sh" --cwd "$TEST_DIR/repo2" --count 2 \
       --owner 主控 --work 试点B --tasks b1,b2 > "$TEST_DIR/t5-out.txt" 2>&1); then
  pass "fanout exits 0 without HERDR_TAB_ID"
else
  fail "fanout failed without HERDR_TAB_ID"; cat "$TEST_DIR/t5-out.txt"
fi
T5_MANIFEST="$(find "$TEST_DIR/repo2/.fangyang" -name '*-agents.tsv' | head -n 1)"
assert_not_contains "no tab get attempted"   "$LOG" "tab get"
assert_not_contains "no rename attempted"    "$LOG" "tab rename"
assert_not_contains "no metadata recorded"   "$T5_MANIFEST" "#controller_tab"

echo "== T6: rename failure degrades gracefully =="
mkdir -p "$TEST_DIR/repo3"
touch "$TEST_DIR/rename_fails"
: > "$LOG"
if bash "$REPO_DIR/scripts/fanout.sh" --cwd "$TEST_DIR/repo3" --count 2 \
     --owner 主控 --work 试点C --tasks c1,c2 > "$TEST_DIR/t6-out.txt" 2>&1; then
  pass "fanout exits 0 despite rename failure"
else
  fail "fanout failed when rename failed"; cat "$TEST_DIR/t6-out.txt"
fi
T6_MANIFEST="$(find "$TEST_DIR/repo3/.fangyang" -name '*-agents.tsv' | head -n 1)"
assert_contains "warns about failed rename"  "$TEST_DIR/t6-out.txt" "could not rename controller tab"
assert_not_contains "no metadata on failure" "$T6_MANIFEST" "#controller_tab"
rm -f "$TEST_DIR/rename_fails"

echo
if [ "$FAIL" -eq 0 ]; then
  echo "ALL TESTS PASSED"
else
  echo "SOME TESTS FAILED"
fi
exit "$FAIL"
