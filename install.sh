#!/usr/bin/env bash
set -euo pipefail

# Install this skill into the universal ~/.agents/skills directory and link it
# into agent-specific skill roots. Safe to run from any clone/download location.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="放羊了"
SLUG="fangyang-le"
DEST="${AGENTS_SKILLS_DIR:-$HOME/.agents/skills}/$SLUG"
LINK=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest)
      [[ $# -ge 2 ]] || { echo "--dest needs a path" >&2; exit 2; }
      DEST="$2"; shift 2 ;;
    --no-link)
      LINK=0; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: install.sh [--dest PATH] [--no-link]

  --dest PATH   Install into PATH instead of ~/.agents/skills/fangyang-le.
  --no-link     Do not create links in ~/.claude, ~/.codex, ~/.config/opencode.
EOF
      exit 0 ;;
    *)
      echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ "$DEST" == "/" || -z "$DEST" ]]; then
  echo "refusing unsafe install destination: $DEST" >&2
  exit 2
fi

install_files() {
  local src="$1"
  local dest="$2"
  mkdir -p "$dest"
  cp "$src/SKILL.md" "$dest/SKILL.md"
  cp "$src/install.sh" "$dest/install.sh"
  if [[ -f "$src/README.md" ]]; then cp "$src/README.md" "$dest/README.md"; fi
  if [[ -f "$src/bootstrap.sh" ]]; then cp "$src/bootstrap.sh" "$dest/bootstrap.sh"; fi
  if [[ -f "$src/uninstall.sh" ]]; then cp "$src/uninstall.sh" "$dest/uninstall.sh"; fi
  mkdir -p "$dest/scripts" "$dest/templates" "$dest/lib"
  cp "$src"/scripts/*.sh "$dest/scripts/"
  cp "$src"/templates/*.md "$dest/templates/"
  if compgen -G "$src/lib/*.sh" >/dev/null; then
    cp "$src"/lib/*.sh "$dest/lib/"
    chmod +x "$dest"/lib/*.sh
  fi
  # 界王拳模式的说明文档跟着 skill 一起走，SKILL.md 里引用到它们
  if compgen -G "$src/KAIO_KEN*.md" >/dev/null; then
    cp "$src"/KAIO_KEN*.md "$dest/"
  fi
  # 界王拳启动器（小写文件名）：用户说"界王拳"时的触发说明
  if [[ -f "$src/kaio-ken-starter.md" ]]; then
    cp "$src/kaio-ken-starter.md" "$dest/"
  fi
  chmod +x "$dest/install.sh" "$dest"/scripts/*.sh
  if [[ -f "$dest/bootstrap.sh" ]]; then chmod +x "$dest/bootstrap.sh"; fi
  if [[ -f "$dest/uninstall.sh" ]]; then chmod +x "$dest/uninstall.sh"; fi
}

if [[ "$ROOT" != "$DEST" ]]; then
  rm -rf "$DEST"
  install_files "$ROOT" "$DEST"
fi

if (( LINK == 1 )); then
  for base in \
    "$HOME/.claude/skills" \
    "$HOME/.codex/skills" \
    "$HOME/.config/opencode/skills"
  do
    mkdir -p "$base"
    ln -sfn "$DEST" "$base/$NAME"
    echo "linked: $base/$NAME -> $DEST"
  done
fi

echo
echo "installed: $DEST"
echo "SKILL_DIR=$DEST"
echo "Run 'herdr --skill' for current herdr syntax. Restart the agent if the skill does not appear."
