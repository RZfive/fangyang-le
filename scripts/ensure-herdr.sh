#!/usr/bin/env bash
set -euo pipefail

# Bootstrap a herdr environment from an external (non-herdr) shell:
#   1. install the herdr CLI when it is missing (brew, else the official installer)
#   2. start the headless background server when it is not running
#   3. wait until the server answers, then exit 0
#
# Idempotent: exits 0 immediately when everything is already in place.
# Never launches the interactive `herdr` TUI from here — only `herdr server`
# (the documented headless form), so this is safe to call from scripts/agents.
#
# Env overrides (used by tests / unusual setups):
#   FANGYANG_HERDR_BIN          herdr binary to drive (default: herdr)
#   FANGYANG_HERDR_INSTALL      custom install command (default: auto brew/curl)
#   FANGYANG_HERDR_SERVER_LOG   server log path (default: ~/.config/herdr/)
#   FANGYANG_SERVER_START_WAIT  seconds to wait for readiness (default: 30)

HERDR="${FANGYANG_HERDR_BIN:-herdr}"
WAIT_S="${FANGYANG_SERVER_START_WAIT:-30}"

log() { printf 'ensure-herdr: %s\n' "$*"; }

herdr_on_path() { command -v "$HERDR" >/dev/null 2>&1; }

# Already inside a herdr pane: nothing to bootstrap (herdr blocks nested
# launches anyway, and the server is obviously up).
if [[ -n "${HERDR_ENV:-}" ]]; then
  log "already inside a herdr pane (HERDR_ENV=1); nothing to do"
  exit 0
fi

# --- 1) CLI -----------------------------------------------------------------
if ! herdr_on_path; then
  log "herdr CLI not found; installing"
  if [[ -n "${FANGYANG_HERDR_INSTALL:-}" ]]; then
    # shellcheck disable=SC2086
    if ! $FANGYANG_HERDR_INSTALL; then
      log "FANGYANG_HERDR_INSTALL failed" >&2
      exit 1
    fi
  elif command -v brew >/dev/null 2>&1; then
    if ! brew install herdr; then
      log "brew install herdr failed; see https://herdr.dev/docs/install/ for alternatives" >&2
      exit 1
    fi
  elif command -v curl >/dev/null 2>&1; then
    if ! curl -fsSL https://herdr.dev/install.sh | sh; then
      log "official installer failed; see https://herdr.dev/docs/install/ for alternatives" >&2
      exit 1
    fi
  else
    log "no brew and no curl available; install herdr manually: https://herdr.dev/docs/install/" >&2
    exit 1
  fi

  # The installer may place the binary somewhere this shell's PATH has not
  # picked up yet; probe the usual locations before giving up.
  if ! herdr_on_path; then
    for d in "$HOME/.local/bin" /opt/homebrew/bin /usr/local/bin; do
      if [[ -x "$d/herdr" ]]; then
        export PATH="$d:$PATH"
        break
      fi
    done
  fi
  if ! herdr_on_path; then
    log "herdr was installed but is still not on PATH; open a new shell and retry, or add it manually" >&2
    exit 1
  fi
  log "herdr installed: $(command -v "$HERDR")"
else
  log "herdr CLI found: $(command -v "$HERDR")"
fi

# --- 2) server ---------------------------------------------------------------
# `herdr status server` fails (non-zero) when the server is down.
server_up() {
  "$HERDR" status server >/dev/null 2>&1
}

if server_up; then
  log "herdr server already running"
  exit 0
fi

LOG="${FANGYANG_HERDR_SERVER_LOG:-$HOME/.config/herdr/fangyang-bootstrap-server.log}"
if ! mkdir -p "$(dirname "$LOG")" 2>/dev/null; then
  LOG="${TMPDIR:-/tmp}/fangyang-herdr-server.log"
fi

# --- 3) headless start + readiness poll --------------------------------------
log "starting headless herdr server (log: $LOG)"
nohup "$HERDR" server >>"$LOG" 2>&1 &
SERVER_PID=$!

elapsed=0
while (( elapsed < WAIT_S )); do
  if server_up; then
    log "herdr server ready (pid $SERVER_PID)"
    log "attach interactively any time with: herdr"
    exit 0
  fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    # The process exited fast. Give wrapper/shim launches a moment, re-probe
    # once, and only then treat it as a real failure.
    sleep 1
    if server_up; then
      log "herdr server ready"
      log "attach interactively any time with: herdr"
      exit 0
    fi
    log "server process exited before becoming ready; last log lines:" >&2
    tail -n 20 "$LOG" >&2 || true
    log "if this was first-run onboarding, run 'herdr' once in a terminal, complete it, and retry" >&2
    exit 1
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done

log "server not ready after ${WAIT_S}s; last log lines:" >&2
tail -n 20 "$LOG" >&2 || true
exit 1
