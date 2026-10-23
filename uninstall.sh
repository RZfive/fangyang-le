#!/usr/bin/env bash
set -euo pipefail

NAME="放羊了"
SLUG="fangyang-le"
DEST="${AGENTS_SKILLS_DIR:-$HOME/.agents/skills}/$SLUG"

for base in \
  "$HOME/.claude/skills" \
  "$HOME/.codex/skills" \
  "$HOME/.config/opencode/skills"
do
  if [[ -L "$base/$NAME" || -e "$base/$NAME" ]]; then
    rm -f "$base/$NAME"
    echo "removed: $base/$NAME"
  fi
done

rm -rf "$DEST"
echo "removed: $DEST"
