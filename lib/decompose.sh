#!/usr/bin/env bash
# 任务分解库：根据请求类型自动分解为 Manager 任务
#
# 输出格式（每行一个 Manager，4 个字段）：
#   display|slug|scope|dependencies
#
#   display      给人看的中文名（tab 标签、报告标题）
#   slug         ASCII 小写标识（agent 名、任务文件名、目录名）
#   scope        这个 Manager 负责的范围
#   dependencies 依赖的其它 Manager（slug 或说明，可为「无」）
#
# slug 必须由本库显式给出：中文 display 名做不出 ASCII slug，
# 早期版本在调用方用 tr 推导，导致所有 Manager 的任务文件都叫 "-task.md"。

# 识别任务类型
# 参数: $1=REQUEST, $2=CWD
# 返回: code|report|design|mixed
identify_task_type() {
  local request="$1"

  local has_code=0
  local has_report=0
  local has_design=0

  if echo "$request" | grep -qiE '(项目|代码|开发|实现|API|前端|后端|数据库|全栈|应用|app|website|service|功能|bug|重构)'; then
    has_code=1
  fi

  if echo "$request" | grep -qiE '(报告|分析|调研|总结|文档|论文|研究)'; then
    has_report=1
  fi

  if echo "$request" | grep -qiE '(设计|架构|方案|蓝图|PRD|需求|规划)'; then
    has_design=1
  fi

  local type_count=$((has_code + has_report + has_design))

  if (( type_count > 1 )); then
    echo "mixed"
  elif (( has_code == 1 )); then
    echo "code"
  elif (( has_report == 1 )); then
    echo "report"
  elif (( has_design == 1 )); then
    echo "design"
  else
    echo "code"
  fi
}

# 根据类型分解任务
# 参数: $1=TYPE, $2=REQUEST, $3=CWD, $4=MAX_MANAGERS
# 输出: 每行 "display|slug|scope|dependencies"
decompose_by_type() {
  local type="$1"
  local request="$2"
  local cwd="${3:-}"
  local max_managers="${4:-}"

  # 至少 2 个 Manager，最多 6 个（分层编排的下限/上限）
  if ! [[ "$max_managers" =~ ^[0-9]+$ ]]; then
    max_managers=3
  fi
  (( max_managers < 2 )) && max_managers=2
  (( max_managers > 6 )) && max_managers=6

  # 注意：必须按「行」读取，不能用 out=($(...)) —— 里面的 scope 文本含空格，
  # 数组 + word splitting 会把一行拆成几行，Manager 数量就错了。
  local raw=""
  case "$type" in
    code)   raw="$(decompose_code_project "$request")" ;;
    report) raw="$(decompose_report)" ;;
    design) raw="$(decompose_design)" ;;
    mixed)  raw="$(decompose_mixed)" ;;
    *)
      echo "Error: Unknown task type: $type" >&2
      return 1
      ;;
  esac

  # 按 max_managers 截断
  local i=0 line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if (( i >= max_managers )); then break; fi
    printf '%s\n' "$line"
    i=$((i + 1))
  done <<< "$raw"
}

# 分解代码项目（按架构分层，前端/后端/数据是天然独立的分片）
decompose_code_project() {
  local request="$1"

  if echo "$request" | grep -qiE '(全栈|fullstack|前端.*后端|前后端)'; then
    cat <<'EOF'
前端模块|frontend|实现前端 UI、状态管理、路由；对外只依赖后端 API 契约|后端 API 契约
后端模块|backend|实现 API 路由、业务逻辑、鉴权；先定并公开 API 契约|无
数据模块|data|设计数据库 schema、迁移脚本、种子数据|无
测试模块|tests|编写单元测试、集成测试、端到端用例|前端模块,后端模块
文档模块|docs|编写 README、API 文档、部署指南|前端模块,后端模块
EOF
  elif echo "$request" | grep -qiE '(前端|frontend|react|vue|ui|页面)'; then
    cat <<'EOF'
UI 组件|ui|实现基础 UI 组件库与样式系统|无
页面模块|pages|实现各个页面和路由|UI 组件
状态管理|state|实现全局状态、数据流、接口层|UI 组件
测试文档|tests|编写测试和文档|页面模块
EOF
  elif echo "$request" | grep -qiE '(后端|backend|api|服务|service)'; then
    cat <<'EOF'
API 路由|api|实现 HTTP 路由、中间件、错误处理|无
业务逻辑|domain|实现核心业务逻辑与校验|API 路由
数据访问|data|实现数据库 schema 与访问层|无
测试文档|tests|编写测试和文档|业务逻辑
EOF
  else
    cat <<'EOF'
核心模块|core|实现核心功能与主要数据结构|无
周边模块|support|实现辅助功能、边界处理、配置|核心模块
测试模块|tests|编写测试、修复发现的问题|核心模块
EOF
  fi
}

# 分解报告任务（按章节分片，章节之间基本独立）
decompose_report() {
  cat <<'EOF'
背景调研|background|调研背景、现状、问题定义|无
技术分析|analysis|技术方案分析、对比、选型建议|背景调研
实施方案|plan|具体实施步骤、资源与时间评估|技术分析
风险评估|risk|风险识别、应对策略|实施方案
总结建议|summary|总结全文、给出下一步建议|所有章节
EOF
}

# 分解设计任务（按架构层级分片）
decompose_design() {
  cat <<'EOF'
需求分析|requirements|功能需求、非功能需求、用户画像|无
架构设计|architecture|系统架构、组件划分、技术栈选型|需求分析
数据设计|data|数据模型、数据流、存储方案|架构设计
接口设计|api|API 契约、协议定义、错误规范|架构设计
部署方案|deploy|部署架构、运维方案、监控告警|架构设计
EOF
}

# 分解混合任务（先设计，再实现，再收尾）
decompose_mixed() {
  cat <<'EOF'
方案设计|design|需求确认、架构设计、技术选型、接口契约|无
核心实现|core|实现核心功能与主链路|方案设计
周边实现|support|实现周边功能（UI、集成、脚本）|方案设计
文档整理|docs|编写文档、部署指南、总结|核心实现,周边实现
EOF
}
