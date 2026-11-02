#!/usr/bin/env bash
# 需求深挖库：把「主 Agent 和用户聊透」的结论固化成 SPEC.md
#
# 界王拳的主 Agent 应该在对话里问透这 7 件事，再把答案写成 markdown 传给
# `--spec`。本库负责三件事：
#   1. 打印提问清单（kaio_spec_interview_prompts），供主 Agent 照着聊；
#   2. 没有 --spec 时按请求推断一份草稿（kaio_build_spec），并在 OPEN QUESTIONS
#      里列出必须找人确认的点 —— 草稿只是起点，不是已确认需求；
#   3. 给回归测试一个预设入口（KAIO_KEN_SPEC_ANSWERS），用 `|` 分隔 7 个答案。
#
# 之所以不在这里直接 read /dev/tty 逐条问：界王拳脚本通常由 AI agent 在 herdr
# pane 里非交互调用，弹问题只会卡死无人值守的运行。真正的「聊透」发生在对话里，
# shell 只负责落盘和标记假设。

# 7 个需求维度（顺序即答案顺序）
kaio_spec_dimensions() {
  cat <<'EOF'
goal
deliverables
constraints
acceptance
boundaries
priority
open_questions
EOF
}

# 给主 Agent 的提问清单：照这些问，用户答完再写 --spec
kaio_spec_interview_prompts() {
  cat <<'EOF'
需求深挖 · 7 个必问点（问透再开工，缺一项就会在返工轮里补学费）
1. 最终目标：做完之后用户在什么场景用什么方式感受到「成了」？
2. 交付物：代码 / 文档 / 部署包 / 演示脚本，具体要哪些，放在哪些目录？
3. 约束：技术栈、版本、目录边界、不能动的东西、时间与额度上限？
4. 验收标准：用什么命令或操作能判定通过？（能给可执行命令最好）
5. 拆分边界：哪几块可以互不重叠地并行？哪些是共享热文件只能单线改？
6. 优先级与取舍：时间不够时先保什么、砍什么？
7. 开放问题：目前还不确定、必须由用户拍板的点。
结论请写成 markdown 传给 --spec；不传就按请求推断草稿，草稿里的假设会被
Manager 当成事实执行，返工成本更高。
EOF
}

# 按请求类型推断交付物
kaio_spec_default_deliverables() {
  local type="$1"
  case "$type" in
    code)  echo "可运行代码 + 通过验收的测试 + README（如何启动/如何验收）" ;;
    report) echo "结构化报告正文（markdown）+ 引用来源清单" ;;
    design) echo "设计文档：目标、架构、数据模型、接口契约、落地步骤" ;;
    mixed)  echo "设计文档 + 可运行代码 + 测试 + 交付说明" ;;
    *)      echo "可直接交付的产物 + 验收说明" ;;
  esac
}

# 按请求类型推断验收标准
kaio_spec_default_acceptance() {
  local type="$1" verify="$2"
  if [[ -n "$verify" ]]; then
    echo "\`${verify}\` 在仓库根目录执行 exit 0（界王拳每轮结束都会跑）"
    return 0
  fi
  case "$type" in
    code)  echo "构建/类型检查/测试全部通过；主 Agent 复核 diff 无越界修改" ;;
    report) echo "章节齐全、结论有依据、无 TODO 占位" ;;
    design) echo "五份文档互相自洽，接口契约可直接照着实现" ;;
    *)      echo "所有 Manager 报告齐全且主 Agent 复核通过" ;;
  esac
}

# 生成 SPEC.md 草稿
# 参数: $1=请求  $2=CWD  $3=任务类型  $4=验收命令  $5=模块边界(可空)  $6=目标文件
# 返回: 0 写出成功；1 参数/写入失败
kaio_build_spec() {
  local request="$1"
  local cwd="$2"
  local task_type="$3"
  local verify_cmd="$4"
  local boundaries="${5:-}"
  local out_file="$6"

  if [[ -z "$out_file" ]]; then
    echo "kaio_build_spec: 缺少输出文件" >&2
    return 1
  fi

  local dimensions=() dim
  while IFS= read -r dim; do
    [[ -n "$dim" ]] && dimensions+=("$dim")
  done <<< "$(kaio_spec_dimensions)"

  local answers=()
  local i
  for ((i = 0; i < ${#dimensions[@]}; i++)); do answers+=(""); done

  # 预设答案（测试 / 其它脚本把界王拳嵌进流水线时用）：`|` 分隔，空段保留默认
  if [[ -n "${KAIO_KEN_SPEC_ANSWERS:-}" ]]; then
    local preset=() part
    IFS='|' read -r -a preset <<< "$KAIO_KEN_SPEC_ANSWERS"
    for ((i = 0; i < ${#preset[@]} && i < ${#answers[@]}; i++)); do
      part="${preset[$i]}"
      [[ -n "$part" ]] && answers[$i]="$part"
    done
  fi

  local d_goal="$request"
  local d_deliverables
  d_deliverables="$(kaio_spec_default_deliverables "$task_type")"
  local d_constraints="工作目录 ${cwd}；不 commit；不改与本任务无关的文件；热文件（如 package.json / 共享类型定义）只由主 Agent 或单个 Manager 持有"
  local d_acceptance
  d_acceptance="$(kaio_spec_default_acceptance "$task_type" "$verify_cmd")"
  local d_boundaries="$boundaries"
  [[ -z "$d_boundaries" ]] && d_boundaries="按 Manager 任务文件的 write scope 划分，模块之间不重叠"
  local d_priority="先把主链路跑通并通过验收；周边美化、额外优化放最后，时间不够就砍"
  local d_open="无（已在对话中确认完毕）"

  local defaults=("$d_goal" "$d_deliverables" "$d_constraints" "$d_acceptance" "$d_boundaries" "$d_priority" "$d_open")

  local assumed=()
  for ((i = 0; i < ${#answers[@]}; i++)); do
    if [[ -z "${answers[$i]}" ]]; then
      answers[$i]="${defaults[$i]}"
      # goal 就是用户原话，不算假设；其余未确认项都要留痕
      (( i == 0 )) || assumed+=("${dimensions[$i]}")
    fi
  done

  {
    echo "# 界王拳任务规格（需求深挖结论）"
    echo
    echo "> 请求原文：${request}"
    echo "> 任务类型：${task_type}"
    echo "> 工作目录：${cwd}"
    echo
    echo "## 1. 最终目标"
    echo
    echo "${answers[0]}"
    echo
    echo "## 2. 交付物"
    echo
    echo "${answers[1]}"
    echo
    echo "## 3. 约束（技术栈 / 目录 / 不做的事）"
    echo
    echo "${answers[2]}"
    echo
    echo "## 4. 验收标准"
    echo
    echo "${answers[3]}"
    echo
    echo "## 5. 拆分边界（模块之间不重叠）"
    echo
    echo "${answers[4]}"
    echo
    echo "## 6. 优先级与取舍"
    echo
    echo "${answers[5]}"
    echo
    echo "## 7. 开放问题（必须由用户确认）"
    echo
    echo "${answers[6]}"
    if (( ${#assumed[@]} > 0 )); then
      echo
      echo "## ⚠️ 自动推断的维度（未与用户确认，Manager 会当事实执行）"
      echo
      local a
      for a in "${assumed[@]}"; do
        echo "- ${a}"
      done
    fi
  } > "$out_file" || {
    echo "kaio_build_spec: 写入失败: $out_file" >&2
    return 1
  }

  # 把必须确认的点打到 stdout：主 Agent 看到就知道还差一次对话
  if (( ${#assumed[@]} > 0 )); then
    echo "  ⚠️ 以下需求维度是自动推断，未经用户确认：" >&2
    printf '     - %s\n' "${assumed[@]}" >&2
    echo "     建议在主 Agent 对话里确认后，用 --spec 传入正式规格。" >&2
  fi
  return 0
}
