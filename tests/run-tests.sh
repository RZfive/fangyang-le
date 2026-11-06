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
#   T13 ensure-herdr.sh installs the CLI via brew when herdr is missing,
#       then starts the headless server and waits for readiness
#   T14 ensure-herdr.sh detects a running server and does not start another
#   T15 fanout from an external shell (no HERDR_* envs) bootstraps herdr,
#       creates a dedicated ranch workspace, defaults kind to claude,
#       skips controller-tab renaming, and records the ranch in the manifest
#   T16 fanout --no-bootstrap outside a herdr pane fails fast with exit 2
#   T17 界王拳 Manager uses 二线 role slugs verbatim; normal flocks keep the
#       western owner prefix
#   T18 Worker tier collision suffixes stay ASCII and map back to 中文名
#   T19 explicit 界王拳 slugs are validated (Chinese slug -> exit 2)
#   T20 every pooled DBZ character has an ASCII slug and a display name
#   T21 dbz-roster never repeats a slug and avoids slugs reserved in the dir
#   T22 display-name fallback does not truncate slugs that end in digits
#   T23 kaio-ken-orchestrate.sh rejects bad args (--cwd/--auto-mode/--request)
#   T24 --auto-mode 1 runs the whole pipeline unattended and records decisions
#   T25 --auto-mode 0 without a tty degrades to "continue" and logs it
#   T26 KAIO_KEN_CONFIRM_ANSWERS=n aborts at the breakdown gate (exit 3)
#   T27 the same variable lets the second gate (before Manager launch) abort
#   T28 --spec must point at a readable, non-empty file; bad input exits 2
#   T29 --max-goal-rounds is validated to 0-10
#   T30 --spec becomes SPEC.md in the task dir and every Manager task cites it
#   T31 Goal mode reworks failing rounds, writes a gap file, and stops at the cap
#   T32 a long CJK request is truncated by characters (LC_ALL=C) so workspace
#       labels, tab labels and manifest filenames stay valid UTF-8
#   T33 Manager task files are named after DBZ role slugs and match
#       .manager-map, the manifest and the display-name map one to one
#   T33 Manager task files are named after DBZ role slugs and all managers land
#       in ONE explicit-label HQ tab with a single shared manifest (no -workers
#       suffix); the manager task sheet launches workers in their own tab with
#       an absolute --cwd and never --in-tab / --cwd "."
#   T34 fanout rejects --dbz-tier worker when --dbz-root equals --dbz-owner (the
#       “18号·18号的界王拳” double-write guard) with exit 2 before any agent start
#   T35 worker-flock manifests carry the -workers suffix; manager manifests don't
#   T36 an explicit --label beats the dbz parent-chain auto label
#   T37 a label derived from free text containing "/" (kaio-ken work names are
#       truncated from the request, which can begin with "docs/…") never leaks
#       into the manifest path: the stem is sanitized to one filename component
#   T38 fanout never renames a caller tab whose label contains 指挥部 (the
#       shared kaio-ken HQ tab), and the manager task sheet pins
#       --no-controller-rename so every Manager's worker fanout is explicit
#   T39 no file under scripts/ or lib/ leaves $IDENT directly followed by a
#       non-ASCII byte: bash 3.2 glues the continuation bytes into the variable
#       name and dies with "<VAR><garbage>: unbound variable" under set -u
#   T40 kaio-ken renames the hero's OWN workspace (not the tab) to
#       “<主角> · <work>” at startup, persists the original label
#       in .origin-workspace, restores it via the EXIT trap on abort, stays
#       idempotent on kaio-ken labels (nested guard), survives rename
#       failures, and skips silently outside a herdr pane
#   T41 manager task sheets pin --label “<Manager> · <模块名>” so every
#       worker pen tab names its manager and the module work — the pen is
#       identifiable from the tab/agents list without opening it
#   T42 no doc may teach single-condition `wait --until done`: claude agents
#       settle on `idle` after finishing (verified live on w1C), so a done-only
#       wait stalls until timeout — the root cause of “监控不及时唤起”;
#       the manager sheet must teach idle+done+blocked multi-state waits
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
    elif [ -f "$TEST_DIR/track_agents" ]; then
      # Agent-tracking mode (orchestrator tests): report the agents this run
      # started, so loop monitoring sees real names instead of a static list.
      python3 - "$TEST_DIR" <<'PY'
import json, os, sys
d = sys.argv[1]
names = []
p = os.path.join(d, "started_agents")
if os.path.exists(p):
    for line in open(p):
        n = line.strip()
        if n and n not in names:
            names.append(n)
default = "done"
sp = os.path.join(d, "agent_status")
if os.path.exists(sp):
    default = open(sp).read().strip() or default
agents = []
for n in names:
    per = os.path.join(d, "status_" + n)
    st = default
    if os.path.exists(per):
        st = open(per).read().strip() or default
    agents.append({"name": n, "agent_status": st})
print(json.dumps({"result": {"agents": agents}}))
PY
    else
      echo '{"result":{"agents":[]}}'
    fi
    ;;
  "agent start")
    if [ -f "$TEST_DIR/track_agents" ]; then
      printf '%s\n' "$3" >> "$TEST_DIR/started_agents"
    fi
    echo '{"result":{"agent":{"agent":"x"}}}'
    ;;
  "agent wait")
    exit 0
    ;;
  "agent prompt")
    # Report-writing mode: the orchestrator asks each Manager to write
    # <task_dir>/<slug>-report.md; emulate a Manager that actually does it.
    if [ -f "$TEST_DIR/write_reports" ]; then
      for a in "$@"; do
        target="$(printf '%s' "$a" | grep -oE '[^[:space:]]+-report\.md' | head -n 1)"
        if [ -n "$target" ]; then
          mkdir -p "$(dirname "$target")"
          printf '# %s report\n\nstub report\n' "$3" > "$target"
        fi
      done
    fi
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
  "workspace create")
    echo '{"result":{"workspace":{"workspace_id":"wRANCH"},"tab":{"tab_id":"wRANCH:t0"},"root_pane":{"pane_id":"wRANCH:p0"}}}'
    ;;
  "workspace get")
    # The origin workspace's current label, as a JSON string; kaio-ken uses
    # this both to snapshot the original label and to probe idempotency.
    if [ -f "$TEST_DIR/ws_label" ]; then
      echo "{\"result\":{\"workspace\":{\"workspace_id\":\"$3\",\"label\":$(cat "$TEST_DIR/ws_label")}}}"
    else
      echo "{\"result\":{\"workspace\":{\"workspace_id\":\"$3\",\"label\":\"1\"}}}"
    fi
    ;;
  "workspace rename")
    [ -f "$TEST_DIR/ws_rename_fails" ] && exit 1
    # Persist the new label so a follow-up `workspace get` sees the rename.
    shift 3
    printf '"%s"\n' "$*" > "$TEST_DIR/ws_label"
    exit 0
    ;;
  "status server")
    [ -f "$TEST_DIR/server_up" ] && exit 0
    exit 1
    ;;
  "server"*)
    # bare `herdr server` (headless start): simulate a server becoming ready
    touch "$TEST_DIR/server_up"
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

# Hermeticity: this suite is often launched from inside a real herdr pane
# (agents/WorldBase run there), whose HERDR_* env vars would leak into the
# stub-based tests. The workspace/pane/tab vars are re-exported below; scrub
# every other herdr marker so results never depend on the launching shell.
unset HERDR_ENV HERDR_SOCKET_PATH HERDR_BIN_PATH

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

echo "== T13: ensure-herdr installs the missing CLI (brew) and starts the server =="
# PATH hides the stub herdr; a stub brew drops the herdr "binary" into a dir
# that IS on PATH, simulating a real install.
mkdir -p "$TEST_DIR/t13bin" "$TEST_DIR/t13install"
cp "$STUB_BIN/herdr" "$TEST_DIR/herdr-template"
cat > "$TEST_DIR/t13bin/brew" <<EOS
#!/usr/bin/env bash
cp "$TEST_DIR/herdr-template" "$TEST_DIR/t13install/herdr"
chmod +x "$TEST_DIR/t13install/herdr"
EOS
chmod +x "$TEST_DIR/t13bin/brew"
rm -f "$TEST_DIR/server_up"
: > "$LOG"
if (PATH="$TEST_DIR/t13bin:$TEST_DIR/t13install:/usr/bin:/bin:/usr/sbin:/sbin" \
     FANGYANG_HERDR_SERVER_LOG="$TEST_DIR/t13-server.log" \
     bash "$REPO_DIR/scripts/ensure-herdr.sh" > "$TEST_DIR/t13-out.txt" 2>&1); then
  pass "ensure-herdr exits 0"
else
  fail "ensure-herdr exited non-zero"; cat "$TEST_DIR/t13-out.txt"
fi
[ -x "$TEST_DIR/t13install/herdr" ] && pass "brew was invoked and installed herdr" \
  || fail "brew stub never installed herdr"
assert_contains "reports installing"      "$TEST_DIR/t13-out.txt" "installing"
assert_contains "reports installed path"  "$TEST_DIR/t13-out.txt" "installed:"
assert_contains "reports server ready"    "$TEST_DIR/t13-out.txt" "ready"
[ -f "$TEST_DIR/server_up" ] && pass "headless server started" \
  || fail "server never came up"

echo "== T14: ensure-herdr is a no-op when the server already runs =="
mkdir -p "$TEST_DIR/repo14"
# server_up marker still exists from T13 -> server considered running
: > "$LOG"
if FANGYANG_HERDR_SERVER_LOG="$TEST_DIR/t14-server.log" \
   bash "$REPO_DIR/scripts/ensure-herdr.sh" > "$TEST_DIR/t14-out.txt" 2>&1; then
  pass "ensure-herdr exits 0 with running server"
else
  fail "ensure-herdr failed with running server"; cat "$TEST_DIR/t14-out.txt"
fi
assert_contains   "reports already running" "$TEST_DIR/t14-out.txt" "already running"
if grep -qx "server" "$LOG"; then
  fail "bare 'herdr server' started although server was already up"
else
  pass "no bare server start when already running"
fi

echo "== T15: external fanout bootstraps a ranch workspace =="
mkdir -p "$TEST_DIR/repo15"
rm -f "$TEST_DIR/server_up" "$TEST_DIR/agents.json"
: > "$LOG"
if (unset HERDR_WORKSPACE_ID HERDR_PANE_ID HERDR_TAB_ID \
        CLAUDECODE CLAUDE_CODE_ENTRYPOINT CODEX_HOME CODEX_SANDBOX \
        OPENCODE_BIN OPENCODE_CONFIG_DIR;
     FANGYANG_HERDR_SERVER_LOG="$TEST_DIR/t15-server.log" \
     bash "$REPO_DIR/scripts/fanout.sh" --cwd "$TEST_DIR/repo15" --count 2 \
       --work 外部试点 --tasks x1,x2 > "$TEST_DIR/t15-out.txt" 2>&1); then
  pass "external fanout exits 0"
else
  fail "external fanout failed"; cat "$TEST_DIR/t15-out.txt"
fi
T15_MANIFEST="$(find "$TEST_DIR/repo15/.fangyang" -name '*-agents.tsv' | head -n 1)"
assert_contains "bootstrapped the server"        "$TEST_DIR/t15-out.txt" "ensure-herdr: herdr server ready"
assert_contains "prints external note"           "$TEST_DIR/t15-out.txt" "external:"
assert_contains "creates a ranch workspace"      "$LOG" "workspace create --cwd"
assert_contains "ranch label uses 牧场"           "$LOG" "的牧场 · 外部试点"
assert_contains "pen tab inside the ranch ws"    "$LOG" "tab create --workspace wRANCH"
assert_contains "kind falls back to claude"      "$TEST_DIR/t15-out.txt" "external fallback"
assert_contains "starts claude sheep"            "$LOG" "x1 --kind claude"
assert_not_contains "no controller tab rename"   "$LOG" "tab rename"
assert_not_contains "no controller tab metadata" "$T15_MANIFEST" "#controller_tab"
assert_contains "manifest records ranch ws"      "$T15_MANIFEST" "wRANCH"

echo "== T16: --no-bootstrap outside a herdr pane fails fast =="
mkdir -p "$TEST_DIR/repo16"
rm -f "$TEST_DIR/server_up"
: > "$LOG"
if (unset HERDR_WORKSPACE_ID HERDR_PANE_ID HERDR_TAB_ID;
     bash "$REPO_DIR/scripts/fanout.sh" --cwd "$TEST_DIR/repo16" --count 2 \
       --no-bootstrap > "$TEST_DIR/t16-out.txt" 2>&1); then
  fail "--no-bootstrap outside herdr unexpectedly succeeded"
else
  rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "--no-bootstrap exits 2"
  else
    fail "--no-bootstrap exited $rc, expected 2"
  fi
fi
assert_contains "explains --no-bootstrap" "$TEST_DIR/t16-out.txt" "--no-bootstrap"
assert_not_contains "no bootstrap attempted" "$LOG" "workspace create"

echo "== T17: 界王拳 Manager 使用二线角色，普通放羊不受影响 =="
mkdir -p "$TEST_DIR/repo17"
rm -f "$TEST_DIR/agents.json"
: > "$LOG"
bash "$REPO_DIR/scripts/fanout.sh" --cwd "$TEST_DIR/repo17" --count 2 \
  --owner 孙悟空 --work 界王拳 --dbz-tier manager --dbz-owner 孙悟空 \
  --tasks krillin,tien > "$TEST_DIR/t17-out.txt" 2>&1
assert_contains "uses exact krillin slug" "$LOG" "agent start krillin --kind claude"
assert_contains "uses exact tien slug" "$LOG" "agent start tien --kind claude"
assert_not_contains "no western prefix" "$LOG" "goku-"
T17_MANIFEST="$(find "$TEST_DIR/repo17/.fangyang" -name '*-agents.tsv' | head -n 1)"
assert_contains "manifest tier metadata" "$T17_MANIFEST" "#dbz_tier=manager"
assert_contains "manifest owner metadata" "$T17_MANIFEST" "#dbz_owner=孙悟空"
assert_contains "display map has 克林" "$T17_MANIFEST.dbz-names" $'krillin\t克林'
assert_contains "display map has 天津饭" "$T17_MANIFEST.dbz-names" $'tien\t天津饭'

echo "== T18: 界王拳 Worker 重名后缀与中文映射 =="
mkdir -p "$TEST_DIR/repo18"
: > "$LOG"
bash "$REPO_DIR/scripts/fanout.sh" --cwd "$TEST_DIR/repo18" --count 3 \
  --owner 克林 --work 修炼 --dbz-tier worker --dbz-owner 克林 \
  --dbz-parent 克林 --dbz-root 孙悟空 \
  --tasks chichi,dende,chichi > "$TEST_DIR/t18-out.txt" 2>&1
assert_contains "worker keeps manager prefix" "$LOG" "agent start krillin-chichi --kind claude"
assert_contains "worker uses dende with manager prefix" "$LOG" "agent start krillin-dende --kind claude"
assert_contains "duplicate gets parent-prefixed suffix" "$LOG" "agent start krillin-chichi-2 --kind claude"
T18_MANIFEST="$(find "$TEST_DIR/repo18/.fangyang" -name '*-agents.tsv' | head -n 1)"
assert_contains "actual suffix mapped" "$T18_MANIFEST.dbz-names" $'krillin-chichi-2\t琪琪'
assert_contains "worker owner metadata" "$T18_MANIFEST" "#dbz_owner=克林"
assert_contains "worker parent metadata" "$T18_MANIFEST" "#dbz_parent=krillin"
assert_contains "worker root metadata" "$T18_MANIFEST" "#dbz_root=goku"

echo "== T19: 界王拳显式 slug 校验，不用西部命名 =="
mkdir -p "$TEST_DIR/repo19"
: > "$LOG"
if bash "$REPO_DIR/scripts/fanout.sh" --cwd "$TEST_DIR/repo19" --count 1 \
  --owner 夜枭 --work 非法 --dbz-tier manager --dbz-owner 孙悟空 \
  --tasks 克林 > "$TEST_DIR/t19-out.txt" 2>&1; then
  fail "Chinese runtime slug should be rejected"
else
  [ "$?" -eq 2 ] && pass "invalid slug exits 2" || fail "wrong invalid-slug exit"
fi
assert_contains "explains ASCII slug" "$TEST_DIR/t19-out.txt" "ASCII"
mkdir -p "$TEST_DIR/repo19-normal"
: > "$LOG"
bash "$REPO_DIR/scripts/fanout.sh" --cwd "$TEST_DIR/repo19-normal" --count 2 \
  --owner 夜枭 --work 普通 --tasks ui,api > "$TEST_DIR/t19-normal-out.txt" 2>&1
assert_contains "normal flock still prefixed" "$LOG" "agent start night-owl-ui --kind claude"
assert_contains "normal second task" "$LOG" "agent start night-owl-api --kind claude"

echo "== T20: 七龙珠角色库双向映射覆盖 =="
if bash -c 'source "$1"; for name in "${MAIN_AGENT_NAMES[@]}" "${MANAGER_AGENT_NAMES[@]}" "${WORKER_AGENT_NAMES[@]}"; do slug=$(dbz_agent_slug "$name") || exit 1; [[ "$slug" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || exit 1; display=$(dbz_agent_display_name "$slug"); [[ -n "$display" && "$display" != dbz-- ]] || exit 1; done' _ "$REPO_DIR/lib/dbz-characters.sh"; then
  pass "all pooled characters have ASCII slugs and display names"
else
  fail "pooled character mapping incomplete"
fi
if bash -c 'source "$1"; [[ $(dbz_agent_slug 兰奇) == launch && $(dbz_agent_slug 普亚) == puar && $(dbz_agent_slug 乌布) == uub ]]' _ "$REPO_DIR/lib/dbz-characters.sh"; then
  pass "legacy Chinese aliases map to canonical slugs"
else
  fail "legacy aliases broken"
fi

echo "== T21: dbz-roster 分配不重复角色并避开已用 slug =="
mkdir -p "$TEST_DIR/roster21"
ROSTER_FIRST="$(bash "$REPO_DIR/scripts/dbz-roster.sh" --count 3 --tier worker \
  --seed 7 --used-from "$TEST_DIR/roster21" 2>"$TEST_DIR/t21-err-1.txt")"
FIRST_LINE_COUNT="$(printf '%s\n' "$ROSTER_FIRST" | grep -c . || true)"
if [ "$FIRST_LINE_COUNT" -eq 3 ]; then
  pass "roster returns exactly 3 slugs"
else
  fail "roster returned $FIRST_LINE_COUNT slugs, expected 3"
fi
FIRST_UNIQUE="$(printf '%s\n' "$ROSTER_FIRST" | sort -u | grep -c . || true)"
[ "$FIRST_UNIQUE" -eq "$FIRST_LINE_COUNT" ] && pass "roster slugs are unique" || fail "roster produced duplicate slugs"
if printf '%s\n' "$ROSTER_FIRST" | grep -qvE '^[a-z][a-z0-9_-]{0,31}$'; then
  fail "roster emitted a non-ASCII slug"
else
  pass "roster slugs are ASCII"
fi
assert_contains "roster reserves allocated slugs" "$TEST_DIR/roster21/.dbz-reserved" "$(printf '%s\n' "$ROSTER_FIRST" | head -n 1)"

ROSTER_SECOND="$(bash "$REPO_DIR/scripts/dbz-roster.sh" --count 3 --tier worker \
  --seed 7 --used-from "$TEST_DIR/roster21" 2>"$TEST_DIR/t21-err-2.txt")"
ROSTER_OVERLAP="$(comm -12 <(printf '%s\n' "$ROSTER_FIRST" | sort -u) <(printf '%s\n' "$ROSTER_SECOND" | sort -u) | grep -c . || true)"
if [ "$ROSTER_OVERLAP" -eq 0 ]; then
  pass "second roster avoids slugs already taken in the same task dir"
else
  fail "second roster re-issued $ROSTER_OVERLAP slug(s)"
fi

ROSTER_EXPLAIN="$(bash "$REPO_DIR/scripts/dbz-roster.sh" --count 2 --tier manager \
  --seed 3 --explain)"
if printf '%s\n' "$ROSTER_EXPLAIN" | grep -qE '^[a-z][a-z0-9_-]*\t[^[:space:]]+$'; then
  pass "--explain prints slug<TAB>display name"
else
  fail "--explain output missing display names: $ROSTER_EXPLAIN"
fi
if printf '%s\n' "$ROSTER_EXPLAIN" | grep -q 'dbz--'; then
  fail "--explain produced a broken display name"
else
  pass "--explain never emits dbz-- placeholders"
fi

echo "== T22: 展示名回退不会被自带数字的 slug 截断 =="
: > "$TEST_DIR/empty-map.tsv"
if bash -c '
  source "$1"
  [[ "$(dbz_base_slug android17)" == android17 ]] || exit 1
  [[ "$(dbz_base_slug android17-2)" == android17 ]] || exit 1
  [[ "$(dbz_base_slug chichi-2)" == chichi ]] || exit 1
  [[ "$(dbz_manifest_display_name "$2" android17)" == 17号 ]] || exit 1
  [[ "$(dbz_manifest_display_name "$2" android17-2)" == 17号 ]] || exit 1
  [[ "$(dbz_manifest_display_name "$2" chichi-3)" == 琪琪 ]] || exit 1
' _ "$REPO_DIR/lib/dbz-characters.sh" "$TEST_DIR/empty-map.tsv"; then
  pass "display-name fallback strips only collision suffixes"
else
  fail "display-name fallback truncates numeric slugs"
fi

echo "== T23: 界王拳编排参数校验（--cwd / --auto-mode / --request / 数量边界）=="
KAIO="$REPO_DIR/scripts/kaio-ken-orchestrate.sh"
mkdir -p "$TEST_DIR/kaio23"
if bash "$KAIO" --request "测试" --cwd "$TEST_DIR/kaio23-missing" \
  > "$TEST_DIR/t23a-out.txt" 2>&1; then
  fail "nonexistent --cwd should fail"
else
  [ "$?" -eq 2 ] && pass "nonexistent --cwd exits 2" || fail "nonexistent --cwd wrong exit"
fi
assert_contains "explains --cwd" "$TEST_DIR/t23a-out.txt" "--cwd is not a directory"
if bash "$KAIO" --request "测试" --cwd "$TEST_DIR/kaio23" --auto-mode 2 \
  > "$TEST_DIR/t23b-out.txt" 2>&1; then
  fail "--auto-mode 2 should fail"
else
  [ "$?" -eq 2 ] && pass "invalid --auto-mode exits 2" || fail "invalid --auto-mode wrong exit"
fi
assert_contains "explains --auto-mode" "$TEST_DIR/t23b-out.txt" "--auto-mode must be 0 or 1"
if bash "$KAIO" --cwd "$TEST_DIR/kaio23" > "$TEST_DIR/t23c-out.txt" 2>&1; then
  fail "missing --request should fail"
else
  [ "$?" -eq 2 ] && pass "missing --request exits 2" || fail "missing --request wrong exit"
fi
assert_contains "explains --request" "$TEST_DIR/t23c-out.txt" "--request is required"
if bash "$KAIO" --request "测试" --cwd "$TEST_DIR/kaio23" --max-managers 1 \
  > "$TEST_DIR/t23d-out.txt" 2>&1; then
  fail "--max-managers 1 should fail"
else
  [ "$?" -eq 2 ] && pass "--max-managers out of range exits 2" || fail "--max-managers wrong exit"
fi
if [ -d "$TEST_DIR/kaio23/.fangyang" ]; then
  fail "parameter validation must not create .fangyang"
else
  pass "parameter validation leaves cwd untouched"
fi

echo "== T24: 界王拳 --auto-mode 1 全自动跑通并自动继续所有决策 =="
WS24="$TEST_DIR/kaio24/ws"
mkdir -p "$WS24"
( cd "$WS24" && git init -q >/dev/null 2>&1 ) || true
touch "$TEST_DIR/track_agents" "$TEST_DIR/write_reports"
: > "$TEST_DIR/started_agents"
: > "$LOG"
if bash "$KAIO" --request "开发一个全栈 AI 聊天应用" --max-managers 2 \
  --max-workers-per-manager 2 --auto-mode 1 --loop-interval 1 --max-loops 3 \
  --cwd "$WS24" --verify "true" > "$TEST_DIR/t24-out.txt" 2>&1; then
  pass "auto-mode 1 orchestration exits 0"
else
  fail "auto-mode 1 orchestration failed"; tail -n 40 "$TEST_DIR/t24-out.txt"
fi
T24_TASK_DIR="$(ls -d "$WS24"/.fangyang/kaio-ken-* 2>/dev/null | head -n 1)"
assert_contains "auto decisions recorded" "$T24_TASK_DIR/.decisions.log" "自动继续（--auto-mode 1）"
assert_contains "final report says gate passed" "$T24_TASK_DIR/FINAL_REPORT.md" "质量门: 通过"
assert_contains "report coverage is complete" "$T24_TASK_DIR/FINAL_REPORT.md" "报告覆盖: 2/2"
assert_contains "verify command ran" "$T24_TASK_DIR/FINAL_REPORT.md" "通过 (exit 0)"
T24_STARTED="$(grep -c . "$TEST_DIR/started_agents" 2>/dev/null || true)"
[ "${T24_STARTED:-0}" -eq 2 ] && pass "two DBZ managers started" \
  || fail "expected 2 started agents, got ${T24_STARTED:-0}"
assert_not_contains "no interactive prompts in auto mode" "$TEST_DIR/t24-out.txt" "[preset]"

echo "== T25: --auto-mode 0 无 tty 时降级为自动继续并留痕 =="
WS25="$TEST_DIR/kaio25"
mkdir -p "$WS25"
: > "$TEST_DIR/started_agents"
: > "$LOG"
bash "$KAIO" --request "写一份竞品分析报告" --max-managers 2 --auto-mode 0 \
  --loop-interval 1 --max-loops 2 --cwd "$WS25" --verify "true" \
  > "$TEST_DIR/t25-out.txt" 2>&1 < /dev/null || true
T25_TASK_DIR="$(ls -d "$WS25"/.fangyang/kaio-ken-* 2>/dev/null | head -n 1)"
assert_contains "warns about missing tty" "$TEST_DIR/t25-out.txt" "没有可交互终端"
assert_contains "decision log records fallback" "$T25_TASK_DIR/.decisions.log" "无 tty，降级"
assert_contains "decision log records interactive mode" "$T25_TASK_DIR/.decisions.log" "--auto-mode 0（交互确认）"

WS26="$TEST_DIR/kaio26"
mkdir -p "$WS26"
: > "$TEST_DIR/started_agents"
: > "$LOG"
if KAIO_KEN_CONFIRM_ANSWERS=n bash "$KAIO" --request "开发一个全栈应用" \
  --max-managers 2 --auto-mode 0 --cwd "$WS26" < /dev/null \
  > "$TEST_DIR/t26-out.txt" 2>&1; then
  fail "preset 'n' should abort the run"
else
  [ "$?" -eq 3 ] && pass "preset 'n' exits 3" || fail "preset 'n' wrong exit"
fi
T26_TASK_DIR="$(ls -d "$WS26"/.fangyang/kaio-ken-* 2>/dev/null | head -n 1)"
assert_contains "abort explained" "$TEST_DIR/t26-out.txt" "未创建 workspace"
assert_contains "decision log records abort" "$T26_TASK_DIR/.decisions.log" "预设答案中止"
assert_not_contains "no workspace created after abort" "$LOG" "workspace create"
assert_not_contains "no agent started after abort" "$LOG" "agent start"

WS27="$TEST_DIR/kaio27"
mkdir -p "$WS27"
: > "$TEST_DIR/started_agents"
: > "$LOG"
if KAIO_KEN_CONFIRM_ANSWERS=y,n bash "$KAIO" --request "开发一个全栈应用" \
  --max-managers 2 --auto-mode 0 --cwd "$WS27" < /dev/null \
  > "$TEST_DIR/t27-out.txt" 2>&1; then
  fail "second confirmation 'n' should abort"
else
  [ "$?" -eq 3 ] && pass "second confirmation abort exits 3" || fail "second abort wrong exit"
fi
assert_contains "workspace created before second gate" "$LOG" "workspace create"
assert_not_contains "no manager started after second gate" "$LOG" "agent start"
assert_contains "second gate abort explained" "$TEST_DIR/t27-out.txt" "未启动任何 agent"
T27_TASK_DIR="$(ls -d "$WS27"/.fangyang/kaio-ken-* 2>/dev/null | head -n 1)"
T27_ABORTS="$(grep -c '预设答案中止' "$T27_TASK_DIR/.decisions.log" 2>/dev/null || true)"
[ "${T27_ABORTS:-0}" -eq 1 ] && pass "exactly one aborted decision recorded" \
  || fail "expected 1 aborted decision, got ${T27_ABORTS:-0}"
echo "== T28: --spec 必须是可读且非空文件 =="
mkdir -p "$TEST_DIR/kaio28"
if bash "$KAIO" --request "测试" --cwd "$TEST_DIR/kaio28" \
  --spec "$TEST_DIR/nope-spec.md" > "$TEST_DIR/t28a-out.txt" 2>&1; then
  fail "missing --spec file should fail"
else
  [ "$?" -eq 2 ] && pass "missing --spec exits 2" || fail "missing --spec wrong exit"
fi
assert_contains "explains missing --spec" "$TEST_DIR/t28a-out.txt" "--spec is not a readable file"
: > "$TEST_DIR/empty-spec.md"
if bash "$KAIO" --request "测试" --cwd "$TEST_DIR/kaio28" \
  --spec "$TEST_DIR/empty-spec.md" > "$TEST_DIR/t28b-out.txt" 2>&1; then
  fail "empty --spec should fail"
else
  [ "$?" -eq 2 ] && pass "empty --spec exits 2" || fail "empty --spec wrong exit"
fi
assert_contains "explains empty --spec" "$TEST_DIR/t28b-out.txt" "--spec file is empty"
if [ -d "$TEST_DIR/kaio28/.fangyang" ]; then
  fail "--spec validation must not create .fangyang"
else
  pass "--spec validation leaves cwd untouched"
fi

echo "== T29: --max-goal-rounds 边界校验 =="
for bad in 11 abc -1; do
  if bash "$KAIO" --request "测试" --cwd "$TEST_DIR/kaio28" \
    --max-goal-rounds "$bad" > "$TEST_DIR/t29-$bad-out.txt" 2>&1; then
    fail "--max-goal-rounds $bad should fail"
  else
    [ "$?" -eq 2 ] && pass "--max-goal-rounds $bad exits 2" \
      || fail "--max-goal-rounds $bad wrong exit"
  fi
done
assert_contains "explains --max-goal-rounds" "$TEST_DIR/t29-11-out.txt" "--max-goal-rounds must be 0-10"

echo "== T30: --spec 生效：复制成 SPEC.md 并作为唯一事实来源下发 =="
WS30="$TEST_DIR/kaio30/ws"
mkdir -p "$WS30"
( cd "$WS30" && git init -q >/dev/null 2>&1 ) || true
cat > "$TEST_DIR/spec30.md" <<'SPEC'
# 需求规格（已和用户聊透）

## 目标
做一个只读的静态文档站。

## 验收
`true` 必须 exit 0。
SPEC
touch "$TEST_DIR/track_agents" "$TEST_DIR/write_reports"
: > "$TEST_DIR/started_agents"
: > "$LOG"
if bash "$KAIO" --request "做一个静态文档站" --max-managers 2 \
  --max-workers-per-manager 2 --auto-mode 1 --loop-interval 1 --max-loops 3 \
  --cwd "$WS30" --spec "$TEST_DIR/spec30.md" --verify "true" \
  > "$TEST_DIR/t30-out.txt" 2>&1; then
  pass "--spec run exits 0"
else
  fail "--spec run failed"; tail -n 40 "$TEST_DIR/t30-out.txt"
fi
T30_TASK_DIR="$(ls -d "$WS30"/.fangyang/kaio-ken-* 2>/dev/null | head -n 1)"
assert_contains "spec copied into task dir" "$T30_TASK_DIR/SPEC.md" "已和用户聊透"
assert_not_contains "spec draft not inferred over user spec" "$T30_TASK_DIR/SPEC.md" "未经用户确认"
assert_contains "decision log records --spec" "$T30_TASK_DIR/.decisions.log" "使用 --spec 文件"
assert_contains "spec path mention in output" "$TEST_DIR/t30-out.txt" "使用 --spec"
T30_TASK_FILE="$(ls -1 "$T30_TASK_DIR"/*-task.md 2>/dev/null | head -n 1)"
assert_contains "manager task points at spec" "$T30_TASK_FILE" "$T30_TASK_DIR/SPEC.md"
assert_not_contains "manager task has no placeholder left" "$T30_TASK_FILE" "{{SPEC_PATH}}"
assert_not_contains "manager task has no acceptance placeholder" "$T30_TASK_FILE" "{{ACCEPTANCE_"

rm -f "$TEST_DIR/track_agents" "$TEST_DIR/write_reports"

echo "== T31: Goal 模式自动返工，写缺口任务书并在轮数用尽后升级 =="
# 验收命令始终失败 + 质量阈值 1.0 保证首轮质量门不通过，Goal 循环必然要跑。
WS31="$TEST_DIR/kaio31/ws"
mkdir -p "$WS31"
( cd "$WS31" && git init -q >/dev/null 2>&1 ) || true
touch "$TEST_DIR/track_agents" "$TEST_DIR/write_reports"
: > "$TEST_DIR/started_agents"
: > "$LOG"
if bash "$KAIO" --request "开发一个全栈应用" --max-managers 2 \
  --max-workers-per-manager 2 --auto-mode 1 --loop-interval 1 --max-loops 2 \
  --quality 1.0 --max-goal-rounds 1 --cwd "$WS31" --verify "false" \
  > "$TEST_DIR/t31-out.txt" 2>&1; then
  fail "Goal run with failing verify should exit non-zero"
else
  [ "$?" -eq 1 ] && pass "failing gate exits 1 after Goal rounds" \
    || fail "Goal run wrong exit"
fi
T31_TASK_DIR="$(ls -d "$WS31"/.fangyang/kaio-ken-* 2>/dev/null | head -n 1)"
assert_contains "goal round announced" "$TEST_DIR/t31-out.txt" "【Goal 模式】第 1/1 轮自动返工"
assert_contains "gap file written" "$T31_TASK_DIR/GOAL-ROUND-1-GAPS.md" "必须补齐的缺口"
assert_contains "gap file carries failing verify" "$T31_TASK_DIR/GOAL-ROUND-1-GAPS.md" "失败 (exit"
assert_contains "rework dispatched to managers" "$TEST_DIR/t31-out.txt" "返工派发"
assert_contains "round snapshot kept" "$T31_TASK_DIR/FINAL_REPORT-round-0.md" "界王拳任务完成汇报"
assert_contains "escalation logged" "$T31_TASK_DIR/.decisions.log" "用尽 1 轮返工仍未通过"
assert_contains "final report shows goal rounds" "$T31_TASK_DIR/FINAL_REPORT.md" "Goal 轮次: 1/1"

echo "== T32: 中文需求的工作名按字符截断，不产生非法 UTF-8 =="
# 回归点：bash 的 ${VAR:0:20} 在 LC_CTYPE=C 下按字节切中文，坏字节会写进
# workspace 标签、tab 标签和 herdr-*-agents.tsv 文件名，最后在 printf 重定向处
# 报 "Illegal byte sequence" 把整条编排打断。这里故意用 LC_ALL=C 复现原环境。
WS32="$TEST_DIR/kaio32/ws"
mkdir -p "$WS32"
( cd "$WS32" && git init -q >/dev/null 2>&1 ) || true
touch "$TEST_DIR/track_agents" "$TEST_DIR/write_reports"
: > "$TEST_DIR/started_agents"
: > "$LOG"
LONG_CJK_REQUEST="开发一个支持多租户的智能客服工单系统并集成知识库检索与自动分派"
if LC_ALL=C bash "$KAIO" --request "$LONG_CJK_REQUEST" --max-managers 2 \
  --max-workers-per-manager 2 --auto-mode 1 --loop-interval 1 --max-loops 2 \
  --cwd "$WS32" --verify "true" > "$TEST_DIR/t32-out.txt" 2>&1; then
  pass "LC_ALL=C + CJK request runs to completion"
else
  fail "CJK request crashed under LC_ALL=C"; tail -n 20 "$TEST_DIR/t32-out.txt"
fi
assert_contains "work name keeps 20 full characters" "$TEST_DIR/t32-out.txt" \
  "✓ 工作名: 开发一个支持多租户的智能客服工单系统并集…"
assert_contains "workspace label uses the same work name" "$LOG" \
  "界王拳 · 开发一个支持多租户的智能客服工单系统并集…"
if python3 - "$LOG" <<'PY'
import sys
open(sys.argv[1], "rb").read().decode("utf-8")
PY
then
  pass "recorded herdr calls are valid UTF-8"
else
  fail "invalid UTF-8 leaked into herdr calls"
fi
T32_MANIFEST="$(find "$WS32/.fangyang" -name '*-agents.tsv' | head -n 1)"
if python3 - "$T32_MANIFEST" <<'PY'
import sys
open(sys.argv[1], "rb").read().decode("utf-8")
PY
then
  pass "manifest filename and content are valid UTF-8"
else
  fail "manifest path/content is not valid UTF-8"
fi

rm -f "$TEST_DIR/track_agents" "$TEST_DIR/write_reports"

echo "== T33: Manager 任务文件按角色 slug 命名，与 manager-map、manifest 三方一致 =="
WS33="$TEST_DIR/kaio33/ws"
mkdir -p "$WS33"
( cd "$WS33" && git init -q >/dev/null 2>&1 ) || true
touch "$TEST_DIR/track_agents" "$TEST_DIR/write_reports"
: > "$TEST_DIR/started_agents"
: > "$LOG"
bash "$KAIO" --request "开发一个全栈 AI 聊天应用" --max-managers 2 \
  --max-workers-per-manager 2 --auto-mode 1 --loop-interval 1 --max-loops 2 \
  --cwd "$WS33" --verify "true" > "$TEST_DIR/t33-out.txt" 2>&1 || true
T33_TASK_DIR="$(ls -d "$WS33"/.fangyang/kaio-ken-* 2>/dev/null | head -n 1)"
T33_MAP_COUNT="$(grep -c . "$T33_TASK_DIR/.manager-map" 2>/dev/null || true)"
T33_TASK_COUNT="$(ls -1 "$T33_TASK_DIR"/*-task.md 2>/dev/null | grep -c . || true)"
[ "${T33_MAP_COUNT:-0}" -eq 2 ] && pass "manager-map lists both modules" \
  || fail "manager-map has ${T33_MAP_COUNT:-0} entries, expected 2"
[ "${T33_TASK_COUNT:-0}" -eq 2 ] && pass "one task file per manager" \
  || fail "found ${T33_TASK_COUNT:-0} task files, expected 2"
# 每个 task 文件名必须就是一个七龙珠角色 slug（ASCII），且能反查中文展示名。
if bash -c '
  source "$1"; shift
  for f in "$@"; do
    slug="$(basename "$f" -task.md)"
    [[ "$slug" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || exit 1
    display="$(dbz_agent_display_name "$(dbz_base_slug "$slug")")"
    [[ -n "$display" && "$display" != dbz-- ]] || exit 1
  done
' _ "$REPO_DIR/lib/dbz-characters.sh" "$T33_TASK_DIR"/*-task.md; then
  pass "task files are named after real DBZ role slugs"
else
  fail "task file naming does not map back to DBZ roles"
fi
# 任务书里 Manager 拉起 Worker 必须走界王拳入口，不能退回西部 owner 前缀。
T33_TASK_FILE="$(ls -1 "$T33_TASK_DIR"/*-task.md 2>/dev/null | head -n 1)"
assert_contains "manager task tells workers to use worker tier" "$T33_TASK_FILE" "--dbz-tier worker"
assert_contains "manager task passes its own display name as owner" "$T33_TASK_FILE" "--dbz-owner "
assert_contains "manager task cites the roster script" "$T33_TASK_FILE" "dbz-roster.sh"
# 断言只约束 bash 命令块，不影响正文里的教学文字（如「不传 --in-tab」的说明）。
T33_CODE_BLOCK="$(awk '/^```bash/{f=1;next} /^```/{f=0} f' "$T33_TASK_FILE")"
if printf '%s\n' "$T33_CODE_BLOCK" | grep -qF -- '--in-tab'; then
  fail "manager task stops nesting workers in its own tab"
else
  pass "manager task stops nesting workers in its own tab"
fi
T33_REL_CWD="$(printf '%s\n' "$T33_CODE_BLOCK" | grep -E -- '--cwd +"' | grep -vE -- '--cwd +"/' || true)"
[ -z "$T33_REL_CWD" ] && pass "manager task stops using a relative cwd" \
  || fail "relative --cwd leaked into fanout call: $T33_REL_CWD"
assert_contains "output names managers as 二线战士" "$TEST_DIR/t33-out.txt" "二线战士"
assert_contains "output announces the HQ tab" "$TEST_DIR/t33-out.txt" "指挥部"
T33_MANIFESTS="$(find "$WS33/.fangyang" -name '*-agents.tsv' -print | sort)"
T33_MANIFEST_COUNT="$(printf '%s\n' "$T33_MANIFESTS" | grep -c . || true)"
# 新布局：全部 Manager 并列同一个指挥部 Tab，一次 fanout 只产出一份 manifest
# （tier=manager 不带 -workers 后缀）；「每 Manager 一份 manifest」的旧断言废除。
[ "${T33_MANIFEST_COUNT:-0}" -eq 1 ] && pass "managers share one HQ manifest" \
  || fail "found ${T33_MANIFEST_COUNT:-0} manager manifests, expected 1"
assert_contains "HQ tab is created with the explicit label" "$LOG" "界王拳指挥部"
T33_HQ_MANIFEST="$(printf '%s\n' "$T33_MANIFESTS" | head -n 1)"
if [ "${T33_MANIFEST_COUNT:-0}" -eq 1 ]; then
  T33_HQ_AGENTS="$(awk -F '\t' '$1 != "" && $1 != "name" && $1 !~ /^#/ { n++ } END { print n + 0 }' "$T33_HQ_MANIFEST")"
  [ "${T33_HQ_AGENTS:-0}" -eq 2 ] && pass "HQ manifest lists both managers" \
    || fail "HQ manifest lists ${T33_HQ_AGENTS:-0} agents, expected 2"
  assert_contains "HQ manifest records manager tier" "$T33_HQ_MANIFEST" "#dbz_tier=manager"
  T33_HQ_MAP="${T33_HQ_MANIFEST}.dbz-names"
  T33_MAP_LINES="$(wc -l < "$T33_HQ_MAP" 2>/dev/null | tr -d ' ' || echo 0)"
  [ "${T33_MAP_LINES:-0}" -eq 2 ] && pass "HQ dbz-names maps both managers" \
    || fail "HQ dbz-names has ${T33_MAP_LINES:-0} entries, expected 2"
  case "$T33_HQ_MANIFEST" in
    *-workers-agents.tsv) fail "manager manifest must not carry the -workers suffix" ;;
    *) pass "manager manifest has no -workers suffix" ;;
  esac
fi


echo "== T34: worker 圈 root==owner 防呆（防「18号·18号的界王拳」）=="
mkdir -p "$TEST_DIR/repo34"
: > "$LOG"
if bash "$REPO_DIR/scripts/fanout.sh" --cwd "$TEST_DIR/repo34" --count 1 \
  --owner 克林 --work 修炼 --dbz-tier worker --dbz-owner 克林 \
  --dbz-parent 克林 --dbz-root 克林 --tasks dende \
  > "$TEST_DIR/t34-out.txt" 2>&1; then
  fail "worker tier with root == owner should fail"
else
  rc=$?
  [ "$rc" -eq 2 ] && pass "root == owner exits 2" || fail "root == owner exited $rc, expected 2"
fi
assert_contains "explains the root guard" "$TEST_DIR/t34-out.txt" "distinct from --dbz-owner"
assert_not_contains "no agent started before the guard" "$LOG" "agent start"

echo "== T35: worker 圈 manifest 固定 -workers 后缀，manager 圈不带 =="
mkdir -p "$TEST_DIR/repo35"
: > "$LOG"
bash "$REPO_DIR/scripts/fanout.sh" --cwd "$TEST_DIR/repo35" --count 2 \
  --owner 克林 --work 修炼 --dbz-tier worker --dbz-owner 克林 \
  --dbz-parent 克林 --dbz-root 孙悟空 --tasks dende,puar \
  > "$TEST_DIR/t35-out.txt" 2>&1
T35_WORKER_MANIFEST="$(find "$TEST_DIR/repo35/.fangyang" -name '*-agents.tsv' | head -n 1)"
case "$T35_WORKER_MANIFEST" in
  *-workers-agents.tsv) pass "worker flock manifest carries -workers suffix" ;;
  *) fail "worker manifest missing -workers suffix: $T35_WORKER_MANIFEST" ;;
esac
mkdir -p "$TEST_DIR/repo35b"
: > "$LOG"
bash "$REPO_DIR/scripts/fanout.sh" --cwd "$TEST_DIR/repo35b" --count 2 \
  --owner 孙悟空 --work 指挥部 --dbz-tier manager --dbz-owner 孙悟空 \
  --dbz-parent 孙悟空 --dbz-root 孙悟空 --tasks krillin,tien \
  > "$TEST_DIR/t35b-out.txt" 2>&1
T35_MANAGER_MANIFEST="$(find "$TEST_DIR/repo35b/.fangyang" -name '*-agents.tsv' | head -n 1)"
case "$T35_MANAGER_MANIFEST" in
  *-workers-agents.tsv) fail "manager manifest must not carry -workers suffix" ;;
  *) pass "manager manifest keeps the plain stem" ;;
esac

echo "== T36: 显式 --label 优先于 dbz 父子链自动标签 =="
mkdir -p "$TEST_DIR/repo36"
: > "$LOG"
bash "$REPO_DIR/scripts/fanout.sh" --cwd "$TEST_DIR/repo36" --count 1 \
  --label "孙悟空的界王拳指挥部 · 试点" --work 指挥部 \
  --dbz-tier manager --dbz-owner 孙悟空 --dbz-parent 孙悟空 \
  --dbz-root 孙悟空 --tasks tien > "$TEST_DIR/t36-out.txt" 2>&1
assert_contains "explicit label wins" "$LOG" "孙悟空的界王拳指挥部 · 试点"
assert_not_contains "auto dbz chain label not applied" "$LOG" "孙悟空·孙悟空的界王拳"

echo "== T37: 含 / 的标签不污染 manifest 路径 =="
# 回归点：kaio-ken 工作名截自用户请求（可以以 "docs/…" 开头），标签照抄进
# manifest 文件名后内嵌 / 会把路径变成不存在的子目录，set -e 下 printf
# 重定向 ENOENT 直接杀死整个 fold。茎干必须收敛回单个文件名。
mkdir -p "$TEST_DIR/repo37"
: > "$LOG"
if bash "$REPO_DIR/scripts/fanout.sh" --cwd "$TEST_DIR/repo37" --count 1 \
     --owner 主控 --work 试点G --label "docs/billing-diff 框架对照" \
     --tasks g1 > "$TEST_DIR/t37-out.txt" 2>&1; then
  pass "fanout exits 0 with a slash in the label"
else
  fail "fanout failed on slash label"; cat "$TEST_DIR/t37-out.txt"
fi
T37_MANIFEST="$(find "$TEST_DIR/repo37/.fangyang" -name '*-agents.tsv' | head -n 1)"
[ -n "$T37_MANIFEST" ] && pass "manifest created despite slash label" \
  || fail "manifest missing for slash label"
T37_BASE="$(basename "$T37_MANIFEST")"
case "$T37_BASE" in
  */*|*:*) fail "manifest filename still carries a path separator: $T37_BASE" ;;
  *docs_billing-diff*) pass "manifest filename is one component, slash sanitized: $T37_BASE" ;;
  *) fail "manifest stem missing the sanitized label: $T37_BASE" ;;
esac

echo "== T38: 共享指挥部 Tab 不被 Worker fanout 改名 =="
# 回归点：界王拳三层模式下全部 Manager 共用一个指挥部 Tab；Manager 各自的
# Worker fanout 若照常改名调用方 Tab，指挥部标签会被第一个 Manager 覆写成
# 「<owner> · Worker圈」。fanout 对含「指挥部」的调用方 Tab 兜底拒改名，
# Manager 任务书同时显式传 --no-controller-rename。
mkdir -p "$TEST_DIR/repo38"
printf '"孙悟空的界王拳指挥部 · 试点H"\n' > "$TEST_DIR/ctrl_label"
: > "$LOG"
bash "$REPO_DIR/scripts/fanout.sh" --cwd "$TEST_DIR/repo38" --count 1 \
  --owner 克林 --work Worker圈 --dbz-tier worker --dbz-owner 克林 \
  --dbz-parent 克林 --dbz-root 孙悟空 --tasks dende \
  > "$TEST_DIR/t38-out.txt" 2>&1
assert_not_contains "HQ tab not renamed"     "$LOG" "tab rename"
assert_contains   "skip note printed"        "$TEST_DIR/t38-out.txt" "指挥部"
T38_MANIFEST="$(find "$TEST_DIR/repo38/.fangyang" -name '*-agents.tsv' | head -n 1)"
assert_not_contains "no controller metadata" "$T38_MANIFEST" "#controller_tab"
printf '"1"\n' > "$TEST_DIR/ctrl_label"
assert_contains   "manager sheet pins --no-controller-rename" \
  "$REPO_DIR/templates/manager-task.md" "--no-controller-rename"

echo "== T39: bash 3.2 多字节邻接扫描（\$IDENT 直接跟非 ASCII 字节）=="
# 回归点：macOS /usr/bin/env bash = 3.2，双引号里 "$VAR（" 这种变量名紧贴
# 多字节字符的写法会把后续字节粘进变量名，set -u 下报
# 「TASK_TYPE…: unbound variable」杀死编排（2026-11-05 实发于 310 行）。
# 统一改写成 "${VAR}（"；按字节扫描防止回归。
if python3 - "$REPO_DIR" <<'PY'
import glob, os, re, sys
repo = sys.argv[1]
pat = re.compile(rb'\$[A-Za-z_][A-Za-z0-9_]*[\x80-\xff]')
bad = []
paths = sorted(glob.glob(os.path.join(repo, 'scripts', '*.sh'))
               + glob.glob(os.path.join(repo, 'lib', '*.sh')))
for path in paths:
    data = open(path, 'rb').read()
    for m in pat.finditer(data):
        lineno = data[:m.start()].count(b'\n') + 1
        line = data.splitlines()[lineno - 1]
        if line.lstrip().startswith(b'#'):
            continue  # comment-only lines are not parsed by bash
        bad.append('%s:%d: %s' % (os.path.relpath(path, repo), lineno,
                                  line.decode('utf-8', 'replace').strip()))
if bad:
    print('raw $IDENT directly followed by a non-ASCII byte — brace it as ${IDENT}:')
    print('\n'.join(bad))
    sys.exit(1)
PY
then
  pass "no raw \$IDENT adjacent to non-ASCII bytes under scripts/ lib/"
else
  fail "bash 3.2 multibyte adjacency regression found (see listing above)"
fi

echo "== T40: 界王拳主角 workspace 改名（标记/恢复/幂等/失败降级/无 pane）=="
# 编排启动时把主角所在的当前 workspace 改名为「<主角>本尊 · 界王拳 · <工作名>」，
# 原标签落盘 .origin-workspace，EXIT trap 兜底恢复。主角名是随机抽卡，
# 断言按标签模式而不是具体人名。
printf '"origin-ws"\n' > "$TEST_DIR/ws_label"
WS40="$TEST_DIR/kaio40"
mkdir -p "$WS40"
: > "$LOG"
if HERDR_WORKSPACE_ID=w0 KAIO_KEN_CONFIRM_ANSWERS=n bash "$KAIO" \
  --request "开发一个全栈应用" --max-managers 2 --auto-mode 0 \
  --cwd "$WS40" < /dev/null > "$TEST_DIR/t40-out.txt" 2>&1; then
  fail "preset 'n' should abort the T40 run"
else
  [ "$?" -eq 3 ] && pass "T40 abort still exits 3" || fail "T40 abort wrong exit code"
fi
assert_contains "queries origin workspace label" "$LOG" "workspace get w0"
assert_contains "renames to <hero> · <work> pairing" "$LOG" " · 开发一个全栈应用"
assert_contains "EXIT trap restores original label" "$LOG" "workspace rename w0 origin-ws"
T40_TASK_DIR="$(ls -d "$WS40"/.fangyang/kaio-ken-* 2>/dev/null | head -n 1)"
assert_contains "origin metadata persisted" \
  "$T40_TASK_DIR/.origin-workspace" "#origin_workspace_label=origin-ws"
T40_RENAMES="$(grep -c '^workspace rename w0 ' "$LOG" 2>/dev/null || true)"
[ "${T40_RENAMES:-0}" -eq 2 ] && pass "mark + restore rename exactly twice" \
  || fail "expected 2 workspace renames, got ${T40_RENAMES:-0}"

# 幂等：当前 workspace 标签已带「界王拳」（嵌套/上次未恢复）时不再改。
WS40B="$TEST_DIR/kaio40b"
mkdir -p "$WS40B"
printf '"孙悟空的界王拳 · 旧活"\n' > "$TEST_DIR/ws_label"
: > "$LOG"
HERDR_WORKSPACE_ID=w0 KAIO_KEN_CONFIRM_ANSWERS=n bash "$KAIO" \
  --request "开发一个全栈应用" --max-managers 2 --auto-mode 0 \
  --cwd "$WS40B" < /dev/null > "$TEST_DIR/t40b-out.txt" 2>&1 || true
assert_contains "idempotent skip is explained" "$TEST_DIR/t40b-out.txt" "无需改名"
assert_not_contains "no rename on existing kaio-ken label" "$LOG" "workspace rename"

# 改名失败只警告，不阻断：仍走到第一个确认点正常中止。
WS40C="$TEST_DIR/kaio40c"
mkdir -p "$WS40C"
printf '"origin-ws"\n' > "$TEST_DIR/ws_label"
touch "$TEST_DIR/ws_rename_fails"
: > "$LOG"
if HERDR_WORKSPACE_ID=w0 KAIO_KEN_CONFIRM_ANSWERS=n bash "$KAIO" \
  --request "开发一个全栈应用" --max-managers 2 --auto-mode 0 \
  --cwd "$WS40C" < /dev/null > "$TEST_DIR/t40c-out.txt" 2>&1; then
  fail "T40c should still abort at the breakdown gate"
else
  [ "$?" -eq 3 ] && pass "rename failure does not block orchestration" \
    || fail "T40c wrong exit code"
fi
assert_contains "rename failure is only a warning" "$TEST_DIR/t40c-out.txt" "改名失败"
rm -f "$TEST_DIR/ws_rename_fails"

# 外部 shell（无 HERDR_WORKSPACE_ID）：只提示、不查询、不改名。
WS40D="$TEST_DIR/kaio40d"
mkdir -p "$WS40D"
: > "$LOG"
# 台架全局 export 了 HERDR_WORKSPACE_ID=wT（模拟 pane 内），这里显式剥掉模拟外部 shell。
env -u HERDR_WORKSPACE_ID KAIO_KEN_CONFIRM_ANSWERS=n bash "$KAIO" --request "开发一个全栈应用" \
  --max-managers 2 --auto-mode 0 --cwd "$WS40D" < /dev/null \
  > "$TEST_DIR/t40d-out.txt" 2>&1 || true
assert_contains "skip note outside a herdr pane" "$TEST_DIR/t40d-out.txt" "跳过主角 workspace 改名"
assert_not_contains "no workspace probe without pane" "$LOG" "workspace get"

echo "== T41: Worker 圈标签写「<Manager> · <模块>」，不点圈可对应 =="
# 回归点：Worker 圈 tab 原来走 dbz 父子链自动标签（<主角>·<经理>的界王拳 · Worker圈），
# 全是「界王拳」字样，分不清哪个圈是谁的。模板和生成后的任务书都必须固定
# --label "<Manager名> · <模块名>"，与主角 workspace「<主角> · <工作名>」同名系。
assert_contains "template pins pen label" \
  "$REPO_DIR/templates/manager-task.md" '--label "{{MANAGER_NAME}} · {{MODULE_NAME}}"'
assert_contains "orchestrator fills the module placeholder" \
  "$REPO_DIR/scripts/kaio-ken-orchestrate.sh" 's|{{MODULE_NAME}}|$module_name|g'
# T24 全流程生成的任务书：占位符已被替换成「<角色名> · 前端模块/后端模块」。
T24_TASK_FILE="$(ls "$T24_TASK_DIR"/*-task.md 2>/dev/null | head -n 1)"
assert_contains "generated sheet keeps an explicit pen label" "$T24_TASK_FILE" '--label "'
T41_PENS="$(grep -h -- '--label "' "$T24_TASK_DIR"/*-task.md 2>/dev/null \
  | sed 's/.*--label "//;s/".*//' | sort -u)"
echo "$T41_PENS" | grep -q ' · 前端模块$' && pass "front-end pen labeled 「X · 前端模块」" \
  || fail "front-end pen label missing, got: $(echo "$T41_PENS" | tr '\n' '|')"
echo "$T41_PENS" | grep -q ' · 后端模块$' && pass "back-end pen labeled 「X · 后端模块」" \
  || fail "back-end pen label missing, got: $(echo "$T41_PENS" | tr '\n' '|')"

echo "== T42: 监控等待必须多条件（claude 干完停在 idle，不是 done）=="
# 回归点（2026-11-06 实测 w1C）：Manager/Worker 完成后 agent_status 停在 idle
# （completion_seq 有值），只有少数停在 done。主控照「wait --until done」单条件
# 挂监控会白等满超时——「监控总是不及时唤起」的根因。herdr wait 的重复
# --until 是任一命中即返回，必须 idle+done+blocked 三条件。
if grep -Eq 'wait [^ ]+ --until done --timeout' "$REPO_DIR/SKILL.md"; then
  fail "SKILL.md still teaches single-condition --until done waits (monitor stalls until timeout)"
else
  pass "no single-condition done-only waits in SKILL.md"
fi
assert_contains "manager sheet teaches multi-state wait" \
  "$REPO_DIR/templates/manager-task.md" "--until idle --until done --until blocked"

rm -f "$TEST_DIR/track_agents" "$TEST_DIR/write_reports"
echo
if [ "$FAIL" -eq 0 ]; then
  echo "ALL TESTS PASSED"
else
  echo "SOME TESTS FAILED"
fi
exit "$FAIL"