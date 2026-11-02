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
    "比鲁斯"          # 破坏神
    "维斯"            # 天使，破坏神的侍从
)

# ===== 二线角色（Manager）=====
# 这些是重要配角，能独立带队
MANAGER_AGENT_NAMES=(
    "克林"
    "天津饭"
    "雅木茶"
    "乌龙"
    "布尔玛"
    "兰琪"
    "17号"
    "18号"
    "比克"
    "弗利萨"
    "沙鲁"
    "魔人布欧"
)

# ===== 三线角色（Worker）=====
# 这些是各类小角色和配角
WORKER_AGENT_NAMES=(
    "龟仙人"
    "琪琪"
    "牛魔王"
    "撒旦先生"
    "比迪丽"
    "小芳"
    "丹迪"
    "波波"
    "加林仙人"
    "亚奇洛贝"
    "普尔"
    "占卜婆婆"
    "神仙"
    "杰比特"
    "东界王神"
    "老界王神"
    "多多利亚"
    "萨博"
    "基纽"
    "巴特"
    "吉斯"
    "利库姆"
    "古杜"
    "拉蒂兹"
    "那巴"
    "巴达克"
    "布罗利"
    "排骨饭"
    "欧布"
    "皮拉夫"
    "阿修"
    "小舞"
    "桃白白"
    "鹤仙人"
    "饺子"
    "那木"
    "乌巴"
    "波拉"
)
# herdr 只接受 ASCII 小写 agent 名。展示名与运行时 slug 一一对应。
# 这里不随机化 slug，否则任务文件、监控和收割会失联。
dbz_agent_slug() {
    case "$1" in
        孙悟空) printf 'goku' ;;
        卡卡罗特) printf 'kakarot' ;;
        贝吉塔) printf 'vegeta' ;;
        孙悟饭) printf 'gohan' ;;
        孙悟天) printf 'goten' ;;
        特兰克斯) printf 'trunks' ;;
        舞空术大师|龟仙人) printf 'roshi' ;;
        比鲁斯) printf 'beerus' ;;
        维斯) printf 'whis' ;;
        克林) printf 'krillin' ;;
        天津饭) printf 'tien' ;;
        雅木茶) printf 'yamcha' ;;
        乌龙) printf 'oolong' ;;
        布尔玛) printf 'bulma' ;;
        兰琪|兰奇) printf 'launch' ;;
        17号) printf 'android17' ;;
        18号) printf 'android18' ;;
        瑟曦) printf 'cersei' ;;
        比克|短笛大魔王) printf 'piccolo' ;;
        阿布) printf 'abu' ;;
        弗利萨) printf 'frieza' ;;
        沙鲁) printf 'cell' ;;
        魔人布欧) printf 'buu' ;;
        普亚|普尔) printf 'puar' ;;
        乌布|欧布) printf 'uub' ;;
        琪琪) printf 'chichi' ;;
        牛魔王) printf 'ox-king' ;;
        撒旦先生) printf 'mr-satan' ;;
        比迪丽) printf 'videl' ;;
        小芳) printf 'pan' ;;
        丹迪) printf 'dende' ;;
        波波) printf 'popo' ;;
        加林仙人) printf 'korin' ;;
        亚奇洛贝) printf 'yajirobe' ;;
        占卜婆婆) printf 'baba' ;;
        神仙) printf 'kami' ;;
        杰比特) printf 'kibito' ;;
        东界王神) printf 'shin' ;;
        老界王神) printf 'elder-kai' ;;
        多多利亚) printf 'dodoria' ;;
        萨博) printf 'zarbon' ;;
        基纽) printf 'ginyu' ;;
        巴特) printf 'burter' ;;
        吉斯) printf 'jeice' ;;
        利库姆) printf 'recoome' ;;
        古杜) printf 'guldo' ;;
        拉蒂兹) printf 'raditz' ;;
        那巴) printf 'nappa' ;;
        巴达克) printf 'bardock' ;;
        布罗利) printf 'broly' ;;
        排骨饭) printf 'pikkon' ;;
        皮拉夫) printf 'pilaf' ;;
        阿修) printf 'shu' ;;
        小舞) printf 'mai' ;;
        桃白白) printf 'mercenary-tao' ;;
        鹤仙人) printf 'crane-hermit' ;;
        饺子) printf 'chiaotzu' ;;
        那木) printf 'nam' ;;
        兰琪|兰奇) printf 'launch' ;;
        乌巴) printf 'upa' ;;
        波拉) printf 'bora' ;;
        *)
            # 显式 ASCII slug 可直接使用；未知中文必须报错，不能生成 dbz--。
            if [[ "$1" =~ ^[a-z][a-z0-9_-]{0,31}$ ]]; then
                printf '%s' "$1"
            else
                return 1
            fi
            ;;
    esac
}

dbz_agent_display_name() {
    case "$1" in
        goku) printf '孙悟空' ;;
        kakarot) printf '卡卡罗特' ;;
        vegeta) printf '贝吉塔' ;;
        gohan) printf '孙悟饭' ;;
        goten) printf '孙悟天' ;;
        trunks) printf '特兰克斯' ;;
        roshi) printf '龟仙人' ;;
        beerus) printf '比鲁斯' ;;
        whis) printf '维斯' ;;
        krillin) printf '克林' ;;
        tien) printf '天津饭' ;;
        yamcha) printf '雅木茶' ;;
        oolong) printf '乌龙' ;;
        bulma) printf '布尔玛' ;;
        launch) printf '兰琪' ;;
        android17) printf '17号' ;;
        android18) printf '18号' ;;
        cersei) printf '瑟曦' ;;
        piccolo) printf '比克' ;;
        abu) printf '阿布' ;;
        frieza) printf '弗利萨' ;;
        cell) printf '沙鲁' ;;
        buu) printf '魔人布欧' ;;
        puar) printf '普尔' ;;
        uub) printf '欧布' ;;
        chichi) printf '琪琪' ;;
        ox-king) printf '牛魔王' ;;
        mr-satan) printf '撒旦先生' ;;
        videl) printf '比迪丽' ;;
        pan) printf '小芳' ;;
        dende) printf '丹迪' ;;
        popo) printf '波波' ;;
        korin) printf '加林仙人' ;;
        yajirobe) printf '亚奇洛贝' ;;
        baba) printf '占卜婆婆' ;;
        kami) printf '神仙' ;;
        kibito) printf '杰比特' ;;
        shin) printf '东界王神' ;;
        elder-kai) printf '老界王神' ;;
        dodoria) printf '多多利亚' ;;
        zarbon) printf '萨博' ;;
        ginyu) printf '基纽' ;;
        burter) printf '巴特' ;;
        jeice) printf '吉斯' ;;
        recoome) printf '利库姆' ;;
        guldo) printf '古杜' ;;
        raditz) printf '拉蒂兹' ;;
        nappa) printf '那巴' ;;
        bardock) printf '巴达克' ;;
        broly) printf '布罗利' ;;
        pikkon) printf '排骨饭' ;;
        pilaf) printf '皮拉夫' ;;
        shu) printf '阿修' ;;
        mai) printf '小舞' ;;
        mercenary-tao) printf '桃白白' ;;
        crane-hermit) printf '鹤仙人' ;;
        chiaotzu) printf '饺子' ;;
        nam) printf '那木' ;;
        upa) printf '乌巴' ;;
        bora) printf '波拉' ;;
        *) printf '%s' "$1" ;;
    esac
}
# 去掉撞名后缀（chichi-2 → chichi）。
# 不能用 ${slug%-[0-9]}：那会把 android17 截成 android1。
dbz_base_slug() {
    local slug="$1"
    if [[ "$slug" =~ ^(.+)-[0-9]+$ ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    else
        printf '%s' "$slug"
    fi
}

# 从 fanout 写的映射表里取展示名。
# 撞名加后缀时（chichi-2），映射表里存的是「实际 agent 名 → 中文名」，
# 直接猜 base 名会丢信息；这里优先读表，读不到才回退。
# 参数: $1=映射表路径, $2=实际 agent 名
dbz_manifest_display_name() {
    local map_file="$1"
    local slug="$2"
    local found=""
    if [[ -n "$map_file" && -f "$map_file" ]]; then
        found="$(awk -F'\t' -v s="$slug" '$1 == s { print $2; exit }' "$map_file" 2>/dev/null || true)"
    fi
    if [[ -n "$found" ]]; then
        printf '%s' "$found"
    else
        local base="$slug"
        # 只去掉撞名后缀（-2/-3）；android17 这类自带数字的 slug 必须原样保留。
        if [[ "$base" =~ ^(.+)-[0-9]+$ ]]; then
            base="${BASH_REMATCH[1]}"
        fi
        dbz_agent_display_name "$base"
    fi
}

# 获取主 Agent 名字
get_main_agent_name() {
    local idx=$(( RANDOM % ${#MAIN_AGENT_NAMES[@]} ))
    echo "${MAIN_AGENT_NAMES[$idx]}"
}

# 获取 Manager 名字（避免重复）
# 注意：macOS 自带 bash 3.2 + set -u 下 "${arr[@]}" 在空数组时直接报
# unbound variable 并退出，所以空数组展开一律加 "-」默认值。
get_manager_agent_name() {
    local used_names=("$@")
    local idx
    local name
    local found

    while true; do
        idx=$(( RANDOM % ${#MANAGER_AGENT_NAMES[@]} ))
        name="${MANAGER_AGENT_NAMES[$idx]}"

        found=0
        for used in "${used_names[@]-}"; do
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
    local found

    while true; do
        idx=$(( RANDOM % ${#WORKER_AGENT_NAMES[@]} ))
        name="${WORKER_AGENT_NAMES[$idx]}"

        found=0
        for used in "${used_names[@]-}"; do
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
    local count=${1:-0}
    local managers=()
    local i
    local name

    [[ "$count" =~ ^[0-9]+$ ]] || return 0
    (( count == 0 )) && return 0

    for (( i=0; i<count; i++ )); do
        name=$(get_manager_agent_name "${managers[@]-}")
        managers+=("$name")
    done

    printf '%s\n' "${managers[@]}"
}

# 生成 Worker 团队名字列表
generate_worker_names() {
    local count=${1:-0}
    local workers=()
    local i
    local name

    [[ "$count" =~ ^[0-9]+$ ]] || return 0
    (( count == 0 )) && return 0

    for (( i=0; i<count; i++ )); do
        name=$(get_worker_agent_name "${workers[@]-}")
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
