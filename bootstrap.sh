#!/usr/bin/env bash
set -euo pipefail

# Download this skill from GitHub and install it without a fixed local path.
#
# Usage:
#   ./bootstrap.sh <git-repo-url> [git-ref] [install-options...]
#
# Examples:
#   ./bootstrap.sh https://github.com/your-org/fangyang-le.git main
#   ./bootstrap.sh https://github.com/your-org/fangyang-le.git main --no-link

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <git-repo-url> [git-ref] [install-options...]" >&2
  exit 2
fi

REPO_URL="$1"
shift
REF=""
if [[ $# -gt 0 && "$1" != --* ]]; then
  REF="$1"
  shift
fi
TMP="$(mktemp -d "${TMPDIR:-/tmp}/fangyang-le.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

echo "cloning: $REPO_URL ${REF:+(ref: $REF)}"
if [[ -n "$REF" ]]; then
  git clone --depth 1 --branch "$REF" "$REPO_URL" "$TMP/skill"
else
  git clone --depth 1 "$REPO_URL" "$TMP/skill"
fi

SRC="$TMP/skill"
if [[ ! -f "$SRC/SKILL.md" ]]; then
  FOUND="$(find "$SRC" -maxdepth 3 -name SKILL.md 2>/dev/null | head -n 1)"
  if [[ -n "$FOUND" ]]; then
    SRC="$(dirname "$FOUND")"
  fi
fi
if [[ ! -f "$SRC/SKILL.md" ]]; then
  echo "SKILL.md not found in cloned repository" >&2
  exit 2
fi

"$SRC/install.sh" "$@"
