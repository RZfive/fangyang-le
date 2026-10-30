#!/usr/bin/env bash
# 七龙珠角色命名池
# 主 Agent（一线主角）、Manager（二线角色）、Worker（三线角色）

# ===== 一线主角（主 Agent）=====
# 这些是系列的核心主角
MAIN_AGENT_NAMES=(
    "孙悟空"          # 大主角
    "贝吉塔"          # 前期反派，后来主要角色
    "孙悟饭"          # 新生代主角
    "孙悟天"          # 新生代
    "特兰克斯"        # 未来主角
    "卡卡罗特"        # 悟空的赛亚人名字
    "舞空术大师"      # 龟仙人
    "比鲁斯"          # 破坏神
)

# ===== 二线角色（Manager）=====
# 这些是重要配角，能独立带队
MANAGER_AGENT_NAMES=(
    "克林"
    "天津饭"
    "雅木茶"
    "乌龙"
    "布尔玛"
    "兰奇"
    "17号"
    "18号"
    "瑟曦"
    "比克"
    "阿布"
    "短笛大魔王"
    "弗利萨"
    "沙鲁"
    "魔人布欧"
    "普亚"
    "乌布"
)

# ===== 三线角色（Worker）=====
# 这些是各类小角色和配角
WORKER_AGENT_NAMES=(
    "壳中老人"
    "龟仙人弟子甲"
    "龟仙人弟子乙"
    "红丝带军队兵甲"
    "红丝带军队兵乙"
    "红丝带军队兵丙"
    "红丝带军队兵丁"
    "恐怖小子"
    "馄饨"
    "南无阿弥陀佛"
    "亚奇罗贝"
    "扎克"
    "古洛"
    "通古"
    "安迪"
    "卡塔茨"
    "多多利亚"
    "扎波斯"
    "基纽"
    "巴特"
    "基纽卫队甲"
    "基纽卫队乙"
    "基纽卫队丙"
    "基纽卫队丁"
    "安德罗依德"
    "雷电"
    "天体"
    "克隆体"
    "界王神"
    "老界王"
    "普通魔人"
    "斯波克"
)

# 获取主 Agent 名字
get_main_agent_name() {
    local count=${1:-1}
    local idx=$(( RANDOM % ${#MAIN_AGENT_NAMES[@]} ))
    echo "${MAIN_AGENT_NAMES[$idx]}"
}

# 获取 Manager 名字（避免重复）
get_manager_agent_name() {
    local used_names=("$@")
    local idx
    local name
    
    while true; do
        idx=$(( RANDOM % ${#MANAGER_AGENT_NAMES[@]} ))
        name="${MANAGER_AGENT_NAMES[$idx]}"
        
        # 检查是否已被使用
        local found=0
        for used in "${used_names[@]}"; do
            if [[ "$used" == "$name" ]]; then
                found=1
                break
            fi
        done
        
        if [[ $found -eq 0 ]]; then
            echo "$name"
            return 0
        fi
        
        # 如果已用完，返回带序号的版本
        if [[ ${#used_names[@]} -ge ${#MANAGER_AGENT_NAMES[@]} ]]; then
            echo "${name}-$(( ${#used_names[@]} + 1 ))"
            return 0
        fi
    done
}

# 获取 Worker 名字（避免重复）
get_worker_agent_name() {
    local used_names=("$@")
    local idx
    local name
    
    while true; do
        idx=$(( RANDOM % ${#WORKER_AGENT_NAMES[@]} ))
        name="${WORKER_AGENT_NAMES[$idx]}"
        
        # 检查是否已被使用
        local found=0
        for used in "${used_names[@]}"; do
            if [[ "$used" == "$name" ]]; then
                found=1
                break
            fi
        done
        
        if [[ $found -eq 0 ]]; then
            echo "$name"
            return 0
        fi
        
        # 如果已用完，返回带序号的版本
        if [[ ${#used_names[@]} -ge ${#WORKER_AGENT_NAMES[@]} ]]; then
            echo "${name}-$(( ${#used_names[@]} + 1 ))"
            return 0
        fi
    done
}

# 生成 Manager 团队名字列表
generate_manager_names() {
    local count=$1
    local managers=()
    local i
    
    for (( i=0; i<count; i++ )); do
        local name=$(get_manager_agent_name "${managers[@]}")
        managers+=("$name")
    done
    
    printf '%s\n' "${managers[@]}"
}

# 生成 Worker 团队名字列表
generate_worker_names() {
    local count=$1
    local workers=()
    local i
    
    for (( i=0; i<count; i++ )); do
        local name=$(get_worker_agent_name "${workers[@]}")
        workers+=("$name")
    done
    
    printf '%s\n' "${workers[@]}"
}

# 获取一线/二线/三线称号
get_tier_title() {
    local tier=$1
    case "$tier" in
        main) echo "🥇 一线主角" ;;
        manager) echo "🥈 二线战士" ;;
        worker) echo "🥉 三线小兵" ;;
        *) echo "？？？" ;;
    esac
}

# 获取角色描述（用于汇报）
get_character_desc() {
    local name=$1
    case "$name" in
        "孙悟空") echo "界王拳主控，能量无限" ;;
        "贝吉塔") echo "赛亚王子，威力强大" ;;
        "孙悟饭") echo "新生代主角，潜力巨大" ;;
        "克林") echo "最忠实的配角，执行力强" ;;
        "天津饭") echo "战术大师，组织能力强" ;;
        "17号") echo "安卓战士，稳定高效" ;;
        "18号") echo "完美人造人，精准执行" ;;
        *) echo "等等我，我来帮忙！" ;;
    esac
}
