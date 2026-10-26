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
#   T7  --owner omitted: a random western name is assigned and used for both
#       the controller tab ("<name> · work") and the pen ("<name>的羊圈 · work")
#   T8  a western name already on the controller's tab is kept on re-fanout
#   T9  western names already used by other tabs in the workspace are skipped
#   T10 agent names carry the ASCII owner-slug prefix (herd-a1 / night-owl-lsp)
#       — herdr only accepts ASCII lowercase agent names — so flocks never mix
#   T11 a second fold with the same owner+work gets -2/-3 sheep names and a
#       tab-id-suffixed manifest; the old manifest is never overwritten
#   T12 duplicate task names inside one flock also get unique suffixes
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
  "tab list")
    if [ -f "$TEST_DIR/ws_labels" ]; then
      python3 - "$TEST_DIR/ws_labels" <<'PY'
import json, sys
labels = [l.rstrip("\n") for l in open(sys.argv[1]) if l.strip()]
print(json.dumps({"result": {"tabs": [{"label": l} for l in labels]}}))
PY
    else
      echo '{"result":{"tabs":[]}}'
    fi
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
  "agent list")
    if [ -f "$TEST_DIR/agents.json" ]; then
      cat "$TEST_DIR/agents.json"
    else
      echo '{"result":{"agents":[]}}'
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
assert_contains "manifest still lists agents"      "$T1_MANIFEST" "herd-a1	wT:pROOT	wT:tPEN	wT"
assert_contains "starts prefixed agent names"       "$LOG" "agent start herd-a1"

echo "== T2: harvest skips # metadata lines when parsing the manifest =="
: > "$LOG"
bash "$REPO_DIR/scripts/harvest.sh" --manifest "$T1_MANIFEST" > "$TEST_DIR/t2-out.txt" 2>&1
assert_contains "harvests agent a1"    "$LOG" "agent get herd-a1"
assert_contains "harvests agent a2"    "$LOG" "agent get herd-a2"
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

echo "== T7: auto owner picks a random western name =="
mkdir -p "$TEST_DIR/repo7"
: > "$LOG"
if bash "$REPO_DIR/scripts/fanout.sh" --cwd "$TEST_DIR/repo7" --count 2 \
     --work 试点D --tasks d1,d2 > "$TEST_DIR/t7-out.txt" 2>&1; then
  pass "fanout exits 0 with auto owner"
else
  fail "fanout failed with auto owner"; cat "$TEST_DIR/t7-out.txt"
fi
T7_OWNER="$(sed -n 's/^owner:     \(.*\) (western.*/\1/p' "$TEST_DIR/t7-out.txt" | head -n 1)"
if [ -n "$T7_OWNER" ]; then
  pass "assigned western owner: $T7_OWNER"
else
  fail "no western owner line in output"
fi
if printf '%s\n' 孤星客 响尾蛇 夜枭 快枪手 荒野狼 金马刺 龙卷风 铁蹄 尘暴 仙人掌 野玫瑰 蓝靴 老警长 赏金客 风滚草 白鬃马 牧羊犬 烈酒 双枪 荒漠之鹰 星尘 响雷 野牛比尔 峡谷回声 | grep -qx "$T7_OWNER"; then
  pass "owner comes from the western pool"
else
  fail "owner '$T7_OWNER' is not in the western pool"
fi
assert_contains "renames controller tab with western name" "$LOG" "tab rename wT:tCTRL $T7_OWNER · 试点D"
assert_contains "pen label uses western name"              "$LOG" "--label ${T7_OWNER}的羊圈 · 试点D"
T7_MANIFEST="$(find "$TEST_DIR/repo7/.fangyang" -name '*-agents.tsv' | head -n 1)"
assert_contains "records original label"                   "$T7_MANIFEST" "#controller_tab_label=1"

echo "== T8: a western name already on the tab is kept =="
mkdir -p "$TEST_DIR/repo8"
printf '"夜枭 · 旧活"' > "$TEST_DIR/ctrl_label"
: > "$LOG"
bash "$REPO_DIR/scripts/fanout.sh" --cwd "$TEST_DIR/repo8" --count 2 \
  --work 新活 --tasks e1,e2 > "$TEST_DIR/t8-out.txt" 2>&1
assert_contains "keeps the existing western name"  "$LOG" "tab rename wT:tCTRL 夜枭 · 新活"
assert_contains "pen reuses the same western name" "$LOG" "--label 夜枭的羊圈 · 新活"
assert_contains "owner source says kept"           "$TEST_DIR/t8-out.txt" "western, kept from this tab"
T8_MANIFEST="$(find "$TEST_DIR/repo8/.fangyang" -name '*-agents.tsv' | head -n 1)"
assert_contains "records pre-fanout label"         "$T8_MANIFEST" "#controller_tab_label=夜枭 · 旧活"
printf '"1"' > "$TEST_DIR/ctrl_label"

echo "== T9: names already used in the workspace are skipped =="
mkdir -p "$TEST_DIR/repo9"
for n in 孤星客 响尾蛇 夜枭 快枪手 荒野狼 金马刺 龙卷风 铁蹄 尘暴 仙人掌 野玫瑰 蓝靴 老警长 赏金客 风滚草 白鬃马 牧羊犬 烈酒 双枪 荒漠之鹰 星尘 响雷 野牛比尔; do
  echo "$n 的羊圈 · 占用" >> "$TEST_DIR/ws_labels"
done
: > "$LOG"
bash "$REPO_DIR/scripts/fanout.sh" --cwd "$TEST_DIR/repo9" --count 2 \
  --work 试点E --tasks f1,f2 > "$TEST_DIR/t9-out.txt" 2>&1
assert_contains "picks the only unused western name" "$LOG" "tab rename wT:tCTRL 峡谷回声 · 试点E"
rm -f "$TEST_DIR/ws_labels"

echo "== T10: agent names carry the owner prefix =="
mkdir -p "$TEST_DIR/repo10"
rm -f "$TEST_DIR/agents.json"
: > "$LOG"
if bash "$REPO_DIR/scripts/fanout.sh" --cwd "$TEST_DIR/repo10" --count 2 \
     --owner 夜枭 --work 隔离A --tasks lsp,ui > "$TEST_DIR/t10-out.txt" 2>&1; then
  pass "fanout exits 0"
else
  fail "fanout exited non-zero"; cat "$TEST_DIR/t10-out.txt"
fi
assert_contains "starts night-owl-lsp"     "$LOG" "agent start night-owl-lsp --kind claude"
assert_contains "starts night-owl-ui"      "$LOG" "agent start night-owl-ui --kind claude"
T10_MANIFEST="$TEST_DIR/repo10/.fangyang/herdr-夜枭的羊圈_·_隔离A-agents.tsv"
assert_contains "manifest lists prefixed names" "$T10_MANIFEST" "night-owl-lsp	wT:pROOT	wT:tPEN	wT"
assert_contains "first task file is prefixed"    "$TEST_DIR/t10-out.txt" ".fangyang/night-owl-lsp-task.md"

echo "== T11: a second fold with the same owner+work stays isolated =="
cat > "$TEST_DIR/agents.json" <<'JSON'
{"result":{"agents":[{"name":"night-owl-lsp"},{"name":"night-owl-ui"}]}}
JSON
: > "$LOG"
if bash "$REPO_DIR/scripts/fanout.sh" --cwd "$TEST_DIR/repo10" --count 2 \
     --owner 夜枭 --work 隔离A --tasks lsp,ui > "$TEST_DIR/t11-out.txt" 2>&1; then
  pass "second fanout exits 0"
else
  fail "second fanout exited non-zero"; cat "$TEST_DIR/t11-out.txt"
fi
assert_contains "suffixed sheep lsp"    "$LOG" "agent start night-owl-lsp-2 --kind claude"
assert_contains "suffixed sheep ui"     "$LOG" "agent start night-owl-ui-2 --kind claude"
assert_contains "prints manifest note"   "$TEST_DIR/t11-out.txt" "already exists"
T11_MANIFEST="$TEST_DIR/repo10/.fangyang/herdr-夜枭的羊圈_·_隔离A-wT:tPEN-agents.tsv"
[ -f "$T11_MANIFEST" ] && pass "tab-id-suffixed manifest created" || fail "suffixed manifest missing"
assert_contains "old manifest keeps flock 1"   "$T10_MANIFEST" "night-owl-lsp	wT:pROOT	wT:tPEN	wT"
assert_not_contains "old manifest untouched"   "$T10_MANIFEST" "-2"

echo "== T12: duplicate task names inside one flock get unique names =="
mkdir -p "$TEST_DIR/repo12"
rm -f "$TEST_DIR/agents.json"
: > "$LOG"
bash "$REPO_DIR/scripts/fanout.sh" --cwd "$TEST_DIR/repo12" --count 2 \
  --owner 夜枭 --work 隔离B --tasks a1,a1 > "$TEST_DIR/t12-out.txt" 2>&1
assert_contains "first keeps plain name"  "$LOG" "agent start night-owl-a1 --kind claude"
assert_contains "second gets a suffix"     "$LOG" "agent start night-owl-a1-2 --kind claude"

echo
if [ "$FAIL" -eq 0 ]; then
  echo "ALL TESTS PASSED"
else
  echo "SOME TESTS FAILED"
fi
exit "$FAIL"
