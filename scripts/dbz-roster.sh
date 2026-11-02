#!/usr/bin/env bash
# 界王拳角色名单分配器
#
# Manager 不再手写 --tasks chichi,dende,popo：每次都向本脚本要一份不重复的
# 三线/二线角色 slug 列表，避免同一 workspace 里两只羊撞同一角色。
#
# Usage: dbz-roster.sh [options]
#   --count N              需要几个角色（默认 3）
#   --tier worker|manager  角色池（默认 worker）
#   --exclude a,b,c        已经用掉的 slug（可带 -2 后缀，会自动归一）
#   --used-from DIR        读取 DIR 下所有 *.dbz-names 与 .dbz-reserved 并排除，
#                          同时把本次分配结果写进 .dbz-reserved 占位（并发安全）
#   --explain              每行输出 "slug<TAB>中文展示名"，供任务文件与汇报使用
#   --seed N               固定随机种子（测试用；默认按时间取）
#
# 输出永远是 ASCII 小写 slug（herdr 只接受这种 agent 名），且互不重复。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/dbz-characters.sh"

COUNT=3
TIER=worker
EXCLUDE=""
USED_FROM=""
EXPLAIN=0
SEED=""

usage() {
  sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --count) COUNT="${2:-}"; shift 2 ;;
    --tier) TIER="${2:-}"; shift 2 ;;
    --exclude) EXCLUDE="${2:-}"; shift 2 ;;
    --used-from) USED_FROM="${2:-}"; shift 2 ;;
    --explain) EXPLAIN=1; shift ;;
    --seed) SEED="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "dbz-roster: unknown option: $1" >&2; exit 2 ;;
  esac
done

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || (( COUNT < 1 )); then
  echo "dbz-roster: --count must be a positive integer" >&2
  exit 2
fi

case "$TIER" in
  worker) POOL=("${WORKER_AGENT_NAMES[@]}") ;;
  manager) POOL=("${MANAGER_AGENT_NAMES[@]}") ;;
  main) POOL=("${MAIN_AGENT_NAMES[@]}") ;;
  *) echo "dbz-roster: --tier must be worker, manager or main" >&2; exit 2 ;;
esac

# 去重后的候选 slug，保持角色池顺序（同一 tier 里「兰琪/兰奇」这类别名只出一个）。
CANDIDATES=""
for name in "${POOL[@]}"; do
  if ! slug="$(dbz_agent_slug "$name")"; then
    echo "dbz-roster: 角色 $name 缺少 ASCII slug 映射，拒绝派发" >&2
    exit 1
  fi
  case $'\n'"$CANDIDATES"$'\n' in
    *$'\n'"$slug"$'\n'*) continue ;;
  esac
  CANDIDATES="$(printf '%s\n%s' "$CANDIDATES" "$slug")"
done
CANDIDATES="${CANDIDATES#$'\n'}"

if [[ -n "${SEED:-}" ]] && ! [[ "$SEED" =~ ^[0-9]+$ ]]; then
  echo "dbz-roster: --seed must be a non-negative integer" >&2
  exit 2
fi

RESERVE_FILE=""
LOCK_DIR=""
cleanup() { [[ -n "$LOCK_DIR" ]] && rmdir "$LOCK_DIR" 2>/dev/null || true; }
trap cleanup EXIT

# 并发安全：两个 Manager 同时要角色时，靠目录锁串行化「读已用 → 分配 → 占位」。
acquire_lock() {
  local tries=0
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    tries=$((tries + 1))
    if (( tries > 100 )); then
      echo "dbz-roster: 等待角色锁超时: $LOCK_DIR" >&2
      exit 1
    fi
    sleep 0.05
  done
}

if [[ -n "$USED_FROM" ]]; then
  if [[ ! -d "$USED_FROM" ]]; then
    echo "dbz-roster: --used-from 不是目录: $USED_FROM" >&2
    exit 2
  fi
  RESERVE_FILE="$USED_FROM/.dbz-reserved"
  LOCK_DIR="$USED_FROM/.dbz-reserved.lock"
  acquire_lock

  # 已经真正启动的角色（fanout 写的 *.dbz-names）和已占位未启动的角色都要排除。
  USED_SLUGS="$(
    { cat "$USED_FROM"/*.dbz-names 2>/dev/null || true
      cat "$RESERVE_FILE" 2>/dev/null || true
    } | awk -F'\t' 'NF { print $1 }' | paste -sd, - || true
  )"
  if [[ -n "$USED_SLUGS" ]]; then
    EXCLUDE="${EXCLUDE:+$EXCLUDE,}$USED_SLUGS"
  fi
fi

if [[ -z "${SEED:-}" ]]; then SEED="$(date +%s)"; fi

# 洗牌 + 过滤：按 seed 打乱池子顺序，再去掉 exclude 里出现过的角色。
AVAILABLE="$(printf '%s\n' "$CANDIDATES" | awk -v seed="$SEED" -v exclude="$EXCLUDE" '
  BEGIN {
    n = split(exclude, ex, ",")
    for (i = 1; i <= n; i++) {
      e = ex[i]
      gsub(/^[ \t]+|[ \t]+$/, "", e)
      sub(/-[0-9]+$/, "", e)          # chichi-2 视作 chichi 已用
      if (e != "") used[e] = 1
    }
    srand(seed)
  }
  { if (!($0 in used)) print rand() "\t" $0 }
' | sort -n | cut -f2-)"

if [[ -z "$AVAILABLE" ]]; then
  echo "dbz-roster: $TIER 角色池已被占满（exclude=$EXCLUDE），请显式指定角色" >&2
  exit 1
fi

# 池子不够时用 -2/-3 后缀补足，和管理面 fanout 的撞名规则一致。
CHOSEN="$(printf '%s\n' "$AVAILABLE" | head -n "$COUNT")"
HAVE="$(printf '%s\n' "$CHOSEN" | grep -c . || true)"
if (( HAVE < COUNT )); then
  round=2
  while (( HAVE < COUNT )) && (( round <= 9 )); do
    while IFS= read -r base; do
      if [[ -z "$base" ]]; then continue; fi
      if (( HAVE >= COUNT )); then break; fi
      CHOSEN="$(printf '%s\n%s' "$CHOSEN" "${base}-${round}")"
      HAVE=$((HAVE + 1))
    done <<< "$AVAILABLE"
    round=$((round + 1))
  done
fi

# 先占位再输出：即使 Manager 中途崩掉，这些名字也不会被下一个 Manager 重复分配。
if [[ -n "$RESERVE_FILE" ]]; then
  printf '%s\n' "$CHOSEN" | while IFS= read -r slug; do
    [[ -z "$slug" ]] && continue
    printf '%s\n' "$slug"
  done >> "$RESERVE_FILE"
  rmdir "$LOCK_DIR" 2>/dev/null || true
  LOCK_DIR=""
fi

while IFS= read -r slug; do
  [[ -z "$slug" ]] && continue
  if (( EXPLAIN )); then
    printf '%s\t%s\n' "$slug" "$(dbz_agent_display_name "$(dbz_base_slug "$slug")")"
  else
    printf '%s\n' "$slug"
  fi
done <<< "$CHOSEN"
