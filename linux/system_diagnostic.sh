#!/bin/bash
###############################################################################
# 脚本名称: system_diagnostic.sh
# 功能描述: Java服务全面系统诊断脚本
# 版本:     v1.0.0
# 创建日期: 2026-08-05
#
# 排查体系概要:
#   系统级四维定位法 - CPU/内存/磁盘/网络逐层排查，快速缩小瓶颈范围
#   CPU高负载四步定位法 - 进程->线程->NID->代码行精准定位
#   JVM内存与GC诊断 - 七种内存错误识别 + GC调优分析
#   综合根因分析 - 自动汇总告警，推断根因并给出处理建议
#
# 安全说明:
#   jmap等JVM工具有STW(Stop-The-World)风险，默认安全模式跳过高危操作
#   使用 --allow-jmap 可启用jmap诊断（生产环境慎用）
#
# 用法:
#   ./system_diagnostic.sh                # 交互式菜单
#   ./system_diagnostic.sh --full         # 全面诊断（执行所有检查）
#   ./system_diagnostic.sh --system       # 仅系统级诊断（CPU/内存/磁盘/网络）
#   ./system_diagnostic.sh --jvm          # 仅JVM诊断
#   ./system_diagnostic.sh --allow-jmap   # 启用jmap堆分析（有STW风险）
#   ./system_diagnostic.sh --no-install   # 禁用自动安装（可与其他参数组合）
#   ./system_diagnostic.sh --help         # 显示帮助信息
#
# 权限说明:
#   需要执行权限: chmod +x system_diagnostic.sh
#   部分检查需要root权限（如安装工具、查看某些/proc文件）
#
# 兼容性:
#   支持 CentOS / Ubuntu / Debian 等主流Linux发行版
#
# 退出码:
#   0 - 正常退出
#   1 - 参数错误
#   2 - 缺少必要工具且无法安装
###############################################################################

set -o pipefail

# 版本信息
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="system_diagnostic.sh"

# 是否自动安装缺失工具（默认开启）
AUTO_INSTALL=true

# JVM安全模式（默认开启，跳过jmap等有STW风险的操作）
# jmap -histo:live 会触发Full GC，jmap -dump 会导致应用暂停
# 安全模式下使用jcmd替代，或跳过高危操作
JVM_SAFE_MODE=true

# 报告目录和文件
REPORT_DIR="/tmp/diag_reports"
REPORT_FILE="${REPORT_DIR}/diagnostic_report_$(date +%Y%m%d_%H%M%S).md"

# 告警计数器
COUNT_INFO=0
COUNT_OK=0
COUNT_WARN=0
COUNT_CRIT=0
COUNT_FAIL=0

# 根因分析收集（关联的根因标记）
declare -A ROOT_CAUSES
MD_SKIP=false

# 颜色定义（stdout 重定向到文件/管道时自动禁用，避免日志出现转义码）
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    WHITE='\033[1;37m'
    PURPLE='\033[0;35m'
    NC='\033[0m' # No Color
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' WHITE='' PURPLE='' NC=''
fi

# 统一计数助手：grep -c 无匹配时输出 "0" 且退出码为 1，
# 不能写 "$(grep -c ... || echo 0)"（无匹配时会输出两行 "0\n0"）
count_of() {
    local count
    count=$(grep -c "$@" 2>/dev/null) || true
    echo "${count:-0}"
}

# ===========================================================================
# 预警阈值统一定义
# ===========================================================================
# Load Average 阈值（负载/核心比）
LOAD_WARN_RATIO=0.7
LOAD_CRIT_RATIO=1.0

# CPU 阈值
CPU_US_WARN=70
CPU_US_CRIT=90
CPU_SY_WARN=30
CPU_WA_WARN=20
CPU_CS_WARN=100000

# 内存阈值
MEM_AVAIL_WARN=20
MEM_AVAIL_CRIT=10

# 磁盘阈值
DISK_SPACE_WARN=70
DISK_SPACE_CRIT=90
DISK_UTIL_WARN=70
DISK_UTIL_CRIT=90
DISK_AWAIT_SSD=1
DISK_AWAIT_HDD=15

# 网络阈值
TIME_WAIT_WARN=5000
TCP_RETRANS_WARN=1
TCP_RETRANS_CRIT=5

# JVM 阈值
JVM_OLD_GEN_CRIT=90
JVM_METASPACE_CRIT=95
JVM_FGC_TIME_CRIT=1000
JVM_GC_RATIO_CRIT=10
JVM_THREAD_WARN=1000
JVM_BLOCKED_WARN=10
JVM_BLOCKED_CRIT=50

# ===========================================================================
# 基础工具函数
# ===========================================================================
is_root() { [ "$(id -u)" -eq 0 ]; }

detect_pkg_manager() {
    if command -v yum &>/dev/null; then echo "yum"
    elif command -v dnf &>/dev/null; then echo "dnf"
    elif command -v apt-get &>/dev/null; then echo "apt-get"
    elif command -v apk &>/dev/null; then echo "apk"
    else echo ""; fi
}

install_package() {
    local pkg="$1"
    local pm; pm=$(detect_pkg_manager)
    if [ -z "$pm" ]; then
        print_fail "无法检测到包管理器(yum/dnf/apt-get/apk)，请手动安装 $pkg"
        return 1
    fi
    print_warn "正在通过 $pm 自动安装 $pkg ..."
    if is_root; then
        case "$pm" in
            yum)     yum install -y "$pkg" ;;
            dnf)     dnf install -y "$pkg" ;;
            apt-get) apt-get update -y && apt-get install -y "$pkg" ;;
            apk)     apk add --no-cache "$pkg" ;;
        esac
    else
        case "$pm" in
            yum)     sudo yum install -y "$pkg" ;;
            dnf)     sudo dnf install -y "$pkg" ;;
            apt-get) sudo apt-get update -y && sudo apt-get install -y "$pkg" ;;
            apk)     sudo apk add --no-cache "$pkg" ;;
        esac
    fi
    return $?
}

ensure_cmd() {
    local cmd="$1"; local pkg="${2:-$1}"
    if command -v "$cmd" &>/dev/null; then return 0; fi
    if [ "$AUTO_INSTALL" = true ]; then
        install_package "$pkg"
        if command -v "$cmd" &>/dev/null; then
            print_ok "已成功安装 $cmd"; return 0
        else
            print_fail "安装 $cmd 失败，请手动安装 $pkg"; return 1
        fi
    else
        print_warn "命令 $cmd 不可用（已禁用自动安装）"; return 1
    fi
}

# ===========================================================================
# 输出与日志函数
# ===========================================================================
strip_color() { echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g'; }

# Markdown 代码块开始
md_code_start() {
    [ "$MD_SKIP" = false ] && echo '```text' >> "$REPORT_FILE"
}

# Markdown 代码块结束
md_code_end() {
    [ "$MD_SKIP" = false ] && echo '```' >> "$REPORT_FILE"
    [ "$MD_SKIP" = false ] && echo '' >> "$REPORT_FILE"
}

# 写入命令输出到 Markdown 代码块
log_cmd_output() {
    if [ "$MD_SKIP" = false ]; then
        echo '```text' >> "$REPORT_FILE"
        strip_color "$1" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
        echo '' >> "$REPORT_FILE"
    fi
}

log() {
    local msg="$1"
    echo -e "$msg"
    [ "$MD_SKIP" = false ] && strip_color "$msg" >> "$REPORT_FILE"
}

log_only() {
    [ "$MD_SKIP" = false ] && strip_color "$1" >> "$REPORT_FILE"
}

print_info()  { echo -e "${CYAN}[INFO]${NC} $1"; ((COUNT_INFO++)); [ "$MD_SKIP" = false ] && echo "**[INFO]** $1" >> "$REPORT_FILE"; }
print_ok()    { echo -e "${GREEN}[OK]${NC}   $1"; ((COUNT_OK++)); [ "$MD_SKIP" = false ] && echo "**[OK]** $1" >> "$REPORT_FILE"; }
print_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; ((COUNT_WARN++)); [ "$MD_SKIP" = false ] && echo "> **[WARN]** $1" >> "$REPORT_FILE"; }
print_crit()  { echo -e "${RED}[CRIT]${NC} $1"; ((COUNT_CRIT++)); [ "$MD_SKIP" = false ] && echo "> **[CRIT]** $1" >> "$REPORT_FILE"; }
print_fail()  { echo -e "${PURPLE}[FAIL]${NC} $1"; ((COUNT_FAIL++)); [ "$MD_SKIP" = false ] && echo "> **[FAIL]** $1" >> "$REPORT_FILE"; }

print_separator() {
    echo -e "${BLUE}================================================================================${NC}"
    [ "$MD_SKIP" = false ] && echo "---" >> "$REPORT_FILE"
}
print_sub_separator() {
    echo -e "${BLUE}--------------------------------------------------------------------------------${NC}"
}
print_section() {
    echo ""
    print_separator
    echo -e "${WHITE} $1 ${NC}"
    print_separator
    [ "$MD_SKIP" = false ] && { echo "" >> "$REPORT_FILE"; echo "## $1" >> "$REPORT_FILE"; echo "" >> "$REPORT_FILE"; }
}
print_subsection() {
    echo ""
    echo -e "${CYAN}>> $1${NC}"
    print_sub_separator
    [ "$MD_SKIP" = false ] && { echo "" >> "$REPORT_FILE"; echo "### $1" >> "$REPORT_FILE"; echo "" >> "$REPORT_FILE"; }
}

add_root_cause() {
    local key="$1"; local desc="$2"; local advice="$3"
    if [ -z "${ROOT_CAUSES[$key]}" ]; then
        ROOT_CAUSES[$key]="$desc|$advice"
    fi
}

init_report() {
    # 交互式菜单连续执行多项诊断时重置计数器与根因列表，避免摘要数字累加失真
    COUNT_WARN=0
    COUNT_CRIT=0
    unset ROOT_CAUSES
    declare -gA ROOT_CAUSES
    mkdir -p "$REPORT_DIR"
    cat > "$REPORT_FILE" <<EOF
# Java 服务系统诊断报告

> **脚本版本**: $SCRIPT_VERSION  
> **生成时间**: $(date '+%Y-%m-%d %H:%M:%S')  
> **主机名**: $(hostname)  
> **操作系统**: $(uname -srm)  
> **执行用户**: $(whoami)

---
EOF
}

# ===========================================================================
# 工具自检与安装
# ===========================================================================
check_and_install_tools() {
    print_section "工具自检与自动安装"
    local pm; pm=$(detect_pkg_manager)
    if [ -n "$pm" ]; then print_info "检测到包管理器: $pm"
    else print_warn "未检测到支持的包管理器(yum/dnf/apt-get/apk)"; fi

    print_subsection "系统工具检查"
    local sys_tools=("vmstat|sysstat" "iostat|sysstat" "mpstat|sysstat" "sar|sysstat" \
        "ss|iproute2" "netstat|net-tools" "lsof|lsof" "curl|curl" "bc|bc" "top|procps" \
        "free|procps" "df|coreutils" "dmesg|util-linux")
    for entry in "${sys_tools[@]}"; do
        local cmd="${entry%%|*}"; local pkg="${entry##*|}"
        if command -v "$cmd" &>/dev/null; then
            echo -e "  ${CYAN}$(printf '%-12s' "$cmd")${NC} ${GREEN}[已安装]${NC}"
            log_only "  $(printf '%-12s' "$cmd") [已安装]"
        else
            echo -e "  ${CYAN}$(printf '%-12s' "$cmd")${NC} ${YELLOW}[缺失]${NC}"
            log_only "  $(printf '%-12s' "$cmd") [缺失]"
            [ "$AUTO_INSTALL" = true ] && ensure_cmd "$cmd" "$pkg"
        fi
    done

    print_subsection "JDK工具检查"
    local jdk_tools=("jps" "jstat" "jstack" "jmap" "jcmd")
    local jdk_missing=0
    for cmd in "${jdk_tools[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            echo -e "  ${CYAN}$(printf '%-12s' "$cmd")${NC} ${GREEN}[已安装]${NC}"
            log_only "  $(printf '%-12s' "$cmd") [已安装]"
        else
            echo -e "  ${CYAN}$(printf '%-12s' "$cmd")${NC} ${YELLOW}[缺失]${NC}"
            log_only "  $(printf '%-12s' "$cmd") [缺失]"
            ((jdk_missing++))
            print_warn "$cmd 不可用，JVM诊断功能将受限（请确保JDK已安装且在PATH中）"
        fi
    done

    print_sub_separator
    if [ "$jdk_missing" -gt 0 ]; then
        print_warn "JDK工具有 $jdk_missing 个缺失，JVM诊断可能不完整"
        add_root_cause "JDK_MISSING" "JDK工具不完整" "安装完整JDK（非JRE），确保jps/jstat/jstack/jmap/jcmd在PATH中"
    else
        print_ok "所有JDK工具均可用"
    fi
    log ""
    log "提示: sysstat包包含 vmstat/iostat/mpstat/sar 工具"
}

# ===========================================================================
# 系统概览诊断
# ===========================================================================
diagnose_system_overview() {
    print_section "系统概览诊断"

    print_subsection "系统基本信息"
    local hostname_val kernel_val os_val arch_val uptime_str
    hostname_val=$(hostname)
    kernel_val=$(uname -r)
    arch_val=$(uname -m)
    os_val=$(grep '^PRETTY_NAME' /etc/os-release 2>/dev/null | cut -d'"' -f2)
    [ -z "$os_val" ] && os_val="未知"
    uptime_str=$(uptime -p 2>/dev/null || uptime)
    printf "  %-20s %s\n" "主机名:" "$hostname_val"
    printf "  %-20s %s\n" "操作系统:" "$os_val"
    printf "  %-20s %s\n" "内核版本:" "$kernel_val"
    printf "  %-20s %s\n" "系统架构:" "$arch_val"
    printf "  %-20s %s\n" "运行时间:" "$uptime_str"
    log_only "$(printf '  %-20s %s\n' '主机名:' "$hostname_val")"
    log_only "$(printf '  %-20s %s\n' '操作系统:' "$os_val")"
    log_only "$(printf '  %-20s %s\n' '内核版本:' "$kernel_val")"
    log_only "$(printf '  %-20s %s\n' '系统架构:' "$arch_val")"
    log_only "$(printf '  %-20s %s\n' '运行时间:' "$uptime_str")"

    print_subsection "CPU信息"
    local cpu_cores cpu_model sockets physical_cpus
    cpu_cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)
    cpu_model=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d':' -f2 | sed 's/^ //')
    [ -z "$cpu_model" ] && cpu_model="未知"
    physical_cpus=$(grep -c ^processor /proc/cpuinfo 2>/dev/null)
    sockets=$(grep 'physical id' /proc/cpuinfo 2>/dev/null | sort -u | wc -l)
    [ "$sockets" -eq 0 ] && sockets=1
    printf "  %-20s %s\n" "CPU型号:" "$cpu_model"
    printf "  %-20s %s\n" "CPU核心数:" "$cpu_cores"
    printf "  %-20s %s\n" "物理CPU数:" "$sockets"
    printf "  %-20s %s\n" "逻辑CPU数:" "$physical_cpus"
    log_only "$(printf '  %-20s %s\n' 'CPU型号:' "$cpu_model")"
    log_only "$(printf '  %-20s %s\n' 'CPU核心数:' "$cpu_cores")"
    log_only "$(printf '  %-20s %s\n' '物理CPU数:' "$sockets")"
    log_only "$(printf '  %-20s %s\n' '逻辑CPU数:' "$physical_cpus")"

    print_subsection "Load Average 负载分析"
    local load1 load5 load15
    read -r load1 load5 load15 _ < <(cat /proc/loadavg 2>/dev/null)
    if [ -z "$load1" ]; then
        load1=$(awk -F'load average:' '{print $2}' <(uptime) | awk -F',' '{print $1}' | tr -d ' ')
        load5=$(awk -F'load average:' '{print $2}' <(uptime) | awk -F',' '{print $2}' | tr -d ' ')
        load15=$(awk -F'load average:' '{print $2}' <(uptime) | awk -F',' '{print $3}' | tr -d ' ')
    fi
    printf "  %-20s %s\n" "1分钟负载:" "$load1"
    printf "  %-20s %s\n" "5分钟负载:" "$load5"
    printf "  %-20s %s\n" "15分钟负载:" "$load15"
    printf "  %-20s %s\n" "CPU核心数:" "$cpu_cores"
    log_only "$(printf '  %-20s %s\n' '1分钟负载:' "$load1")"
    log_only "$(printf '  %-20s %s\n' '5分钟负载:' "$load5")"
    log_only "$(printf '  %-20s %s\n' '15分钟负载:' "$load15")"
    log_only "$(printf '  %-20s %s\n' 'CPU核心数:' "$cpu_cores")"

    print_subsection "负载趋势分析"
    local l1 l5 l15
    l1=$(echo "$load1" | awk '{printf "%.2f", $1}')
    l5=$(echo "$load5" | awk '{printf "%.2f", $1}')
    l15=$(echo "$load15" | awk '{printf "%.2f", $1}')
    if command -v bc &>/dev/null; then
        if (( $(echo "$l1 > $l5" | bc -l) )) && (( $(echo "$l5 > $l15" | bc -l) )); then
            print_warn "负载呈上升趋势(1min > 5min > 15min)，系统负载正在增加"
        elif (( $(echo "$l1 < $l5" | bc -l) )) && (( $(echo "$l5 < $l15" | bc -l) )); then
            print_info "负载呈下降趋势(1min < 5min < 15min)，系统负载正在缓解"
        else
            print_info "负载相对平稳"
        fi
        local ratio; ratio=$(echo "scale=2; $l1 / $cpu_cores" | bc -l)
        printf "  %-20s %s\n" "负载/核心比(1min):" "$ratio"
        log_only "$(printf '  %-20s %s\n' '负载/核心比(1min):' "$ratio")"
        if (( $(echo "$ratio > $LOAD_CRIT_RATIO" | bc -l) )); then
            print_crit "负载/核心比 ${ratio} > ${LOAD_CRIT_RATIO}，系统严重过载！"
            add_root_cause "CPU_OVERLOAD" "系统负载过高(负载/核心比=${ratio})" "排查高CPU进程，考虑扩容或限流"
        elif (( $(echo "$ratio > $LOAD_WARN_RATIO" | bc -l) )); then
            print_warn "负载/核心比 ${ratio} > ${LOAD_WARN_RATIO}，系统负载偏高"
            add_root_cause "CPU_OVERLOAD" "系统负载偏高(负载/核心比=${ratio})" "排查高CPU进程，关注CPU使用趋势"
        else
            print_ok "负载/核心比 ${ratio} 在正常范围内(< ${LOAD_WARN_RATIO})"
        fi
    else
        print_warn "bc工具不可用，无法进行精确负载比较"
    fi
}
# ===========================================================================
# CPU维度诊断
# ===========================================================================
diagnose_cpu() {
    print_section "CPU维度诊断"

    print_subsection "CPU使用率分解 (top)"
    if command -v top &>/dev/null; then
        local top_output cpu_line
        top_output=$(top -bn1 2>/dev/null)
        cpu_line=$(echo "$top_output" | grep '^%Cpu' | head -1)
        if [ -n "$cpu_line" ]; then
            echo "  $cpu_line"
            log_only "  $cpu_line"
            # 解析各项指标 (us,sy,ni,id,wa,hi,si,st)
            local us sy id wa si st
            us=$(echo "$cpu_line" | awk -F',' '{for(i=1;i<=NF;i++) if($i~/us/){split($i,a," ");for(j in a) if(a[j]~/^[0-9.]+$/){print a[j];break};break}}')
            sy=$(echo "$cpu_line" | awk -F',' '{for(i=1;i<=NF;i++) if($i~/sy/){split($i,a," ");for(j in a) if(a[j]~/^[0-9.]+$/){print a[j];break};break}}')
            id=$(echo "$cpu_line" | awk -F',' '{for(i=1;i<=NF;i++) if($i~/id/){split($i,a," ");for(j in a) if(a[j]~/^[0-9.]+$/){print a[j];break};break}}')
            wa=$(echo "$cpu_line" | awk -F',' '{for(i=1;i<=NF;i++) if($i~/wa/){split($i,a," ");for(j in a) if(a[j]~/^[0-9.]+$/){print a[j];break};break}}')
            si=$(echo "$cpu_line" | awk -F',' '{for(i=1;i<=NF;i++) if($i~/si/){split($i,a," ");for(j in a) if(a[j]~/^[0-9.]+$/){print a[j];break};break}}')
            st=$(echo "$cpu_line" | awk -F',' '{for(i=1;i<=NF;i++) if($i~/st/){split($i,a," ");for(j in a) if(a[j]~/^[0-9.]+$/){print a[j];break};break}}')
            [ -z "$us" ] && us="0"; [ -z "$sy" ] && sy="0"; [ -z "$id" ] && id="0"
            [ -z "$wa" ] && wa="0"; [ -z "$si" ] && si="0"; [ -z "$st" ] && st="0"
            log ""
            printf "  %-30s %s%%\n" "us (用户态):" "$us"
            printf "  %-30s %s%%\n" "sy (内核态):" "$sy"
            printf "  %-30s %s%%\n" "id (空闲):" "$id"
            printf "  %-30s %s%%\n" "wa (I/O等待):" "$wa"
            printf "  %-30s %s%%\n" "si (软中断):" "$si"
            printf "  %-30s %s%%\n" "st (偷取):" "$st"
            log_only "$(printf '  %-30s %s%%\n' 'us (用户态):' "$us")"
            log_only "$(printf '  %-30s %s%%\n' 'sy (内核态):' "$sy")"
            log_only "$(printf '  %-30s %s%%\n' 'id (空闲):' "$id")"
            log_only "$(printf '  %-30s %s%%\n' 'wa (I/O等待):' "$wa")"
            log_only "$(printf '  %-30s %s%%\n' 'si (软中断):' "$si")"
            log_only "$(printf '  %-30s %s%%\n' 'st (偷取):' "$st")"

            print_subsection "CPU指标预警检查"
            if command -v bc &>/dev/null; then
                if (( $(echo "$us > $CPU_US_CRIT" | bc -l) )); then
                    print_crit "用户态CPU us=${us}% > ${CPU_US_CRIT}%，CPU严重不足"
                    add_root_cause "CPU_INTENSIVE" "用户态CPU使用率严重过高(us=${us}%)" "排查高CPU线程(四步定位法)，检查死循环/频繁Full GC/正则回溯/计算密集任务"
                elif (( $(echo "$us > $CPU_US_WARN" | bc -l) )); then
                    print_warn "用户态CPU us=${us}% > ${CPU_US_WARN}%，CPU使用偏高"
                    add_root_cause "CPU_INTENSIVE" "用户态CPU使用率偏高(us=${us}%)" "排查高CPU线程(四步定位法)"
                else
                    print_ok "用户态CPU us=${us}% 正常(< ${CPU_US_WARN}%)"
                fi
                if (( $(echo "$sy > $CPU_SY_WARN" | bc -l) )); then
                    print_warn "内核态CPU sy=${sy}% > ${CPU_SY_WARN}%，内核开销过大"
                    add_root_cause "KERNEL_HIGH" "内核态CPU过高(sy=${sy}%)" "检查系统调用/锁竞争/上下文切换/网络中断"
                else
                    print_ok "内核态CPU sy=${sy}% 正常(< ${CPU_SY_WARN}%)"
                fi
                if (( $(echo "$wa > $CPU_WA_WARN" | bc -l) )); then
                    print_crit "I/O等待 wa=${wa}% > ${CPU_WA_WARN}%，存在I/O瓶颈"
                    add_root_cause "IO_BOTTLENECK" "I/O等待过高(wa=${wa}%)" "检查磁盘I/O性能(iostat)，排查慢查询/大文件读写/磁盘故障"
                else
                    print_ok "I/O等待 wa=${wa}% 正常(< ${CPU_WA_WARN}%)"
                fi
                if (( $(echo "$si > 30" | bc -l) )); then
                    print_warn "软中断 si=${si}% 偏高，可能网络或I/O中断过多"
                fi
                if (( $(echo "$st > 5" | bc -l) )); then
                    print_warn "CPU偷取 st=${st}% > 5%，虚拟化环境下宿主机资源争抢"
                fi
            fi
        else
            print_warn "无法从top获取CPU使用率信息"
        fi
    else
        print_fail "top命令不可用"
    fi

    print_subsection "vmstat 采样分析 (vmstat 1 5)"
    if command -v vmstat &>/dev/null; then
        local vmstat_output
        vmstat_output=$(vmstat 1 5 2>/dev/null)
        echo "$vmstat_output" | while IFS= read -r line; do echo "  $line"; done
        log_cmd_output "$vmstat_output"
        # 标准列: r b swpd free buff cache si so bi bo in cs us sy id wa st
        local last_line r b si_vm so_vm cs us_cpu sy_cpu wa_cpu
        last_line=$(echo "$vmstat_output" | tail -1)
        r=$(echo "$last_line" | awk '{print $1}')
        b=$(echo "$last_line" | awk '{print $2}')
        si_vm=$(echo "$last_line" | awk '{print $7}')
        so_vm=$(echo "$last_line" | awk '{print $8}')
        cs=$(echo "$last_line" | awk '{print $12}')
        us_cpu=$(echo "$last_line" | awk '{print $13}')
        sy_cpu=$(echo "$last_line" | awk '{print $14}')
        wa_cpu=$(echo "$last_line" | awk '{print $16}')
        log ""
        printf "  %-30s %s\n" "r (运行队列):" "$r"
        printf "  %-30s %s\n" "b (阻塞进程):" "$b"
        printf "  %-30s %s%%\n" "us (用户态):" "$us_cpu"
        printf "  %-30s %s%%\n" "sy (内核态):" "$sy_cpu"
        printf "  %-30s %s%%\n" "wa (I/O等待):" "$wa_cpu"
        printf "  %-30s %s/s\n" "cs (上下文切换):" "$cs"
        printf "  %-30s %s\n" "si (swap入):" "$si_vm"
        printf "  %-30s %s\n" "so (swap出):" "$so_vm"
        log_only "$(printf '  %-30s %s\n' 'r (运行队列):' "$r")"
        log_only "$(printf '  %-30s %s\n' 'b (阻塞进程):' "$b")"
        log_only "$(printf '  %-30s %s%%\n' 'us (用户态):' "$us_cpu")"
        log_only "$(printf '  %-30s %s%%\n' 'sy (内核态):' "$sy_cpu")"
        log_only "$(printf '  %-30s %s%%\n' 'wa (I/O等待):' "$wa_cpu")"
        log_only "$(printf '  %-30s %s/s\n' 'cs (上下文切换):' "$cs")"
        log_only "$(printf '  %-30s %s\n' 'si (swap入):' "$si_vm")"
        log_only "$(printf '  %-30s %s\n' 'so (swap出):' "$so_vm")"
        local cpu_cores; cpu_cores=$(nproc 2>/dev/null || echo 1)
        if [ "$r" -gt "$cpu_cores" ] 2>/dev/null; then
            print_warn "运行队列 r=${r} > CPU核心数 ${cpu_cores}，CPU可能过载"
            add_root_cause "CPU_OVERLOAD" "运行队列大于CPU核心数(r=${r})" "排查高CPU进程，考虑扩容"
        fi
        if [ "$b" -gt 0 ] 2>/dev/null; then
            print_warn "阻塞进程 b=${b} > 0，存在不可中断I/O等待"
            add_root_cause "IO_BOTTLENECK" "存在D状态阻塞进程(b=${b})" "检查磁盘I/O性能和慢I/O操作"
        fi
        if [ -n "$cs" ] && [ "$cs" -gt "$CPU_CS_WARN" ] 2>/dev/null; then
            print_crit "上下文切换 cs=${cs}/s > ${CPU_CS_WARN}/s，上下文切换风暴"
            add_root_cause "CS_STORM" "上下文切换过多(cs=${cs}/s)" "减少线程数/使用线程池/检查锁竞争导致的频繁切换"
        fi
        if [ -n "$si_vm" ] && [ "$si_vm" -gt 0 ] 2>/dev/null; then
            print_warn "swap si=${si_vm} > 0，系统正在从swap读取数据，内存不足"
            add_root_cause "MEM_INSUFFICIENT" "发生swap in(si=${si_vm})" "增加物理内存或检查内存泄漏"
        fi
        if [ -n "$so_vm" ] && [ "$so_vm" -gt 0 ] 2>/dev/null; then
            print_warn "swap so=${so_vm} > 0，系统正在向swap写入数据，内存不足"
            add_root_cause "MEM_INSUFFICIENT" "发生swap out(so=${so_vm})" "增加物理内存或检查内存泄漏"
        fi
    else
        print_fail "vmstat命令不可用"
    fi

    print_subsection "CPU占用 TOP 10 进程"
    if command -v ps &>/dev/null; then
        printf "  %-8s %-8s %-8s %s\n" "PID" "CPU%" "MEM%" "COMMAND"
        log_only "$(printf '  %-8s %-8s %-8s %s' 'PID' 'CPU%' 'MEM%' 'COMMAND')"
        ps -eo pid,pcpu,pmem,comm --sort=-pcpu 2>/dev/null | head -11 | tail -10 | while IFS= read -r line; do
            printf "  %s\n" "$line"; log_only "  $line"
        done
    fi

    print_subsection "Java进程CPU占用"
    local java_pids
    java_pids=$(pgrep -f java 2>/dev/null || echo "")
    if [ -n "$java_pids" ]; then
        printf "  %-8s %-8s %-8s %s\n" "PID" "CPU%" "MEM%" "COMMAND(截断)"
        log_only "$(printf '  %-8s %-8s %-8s %s' 'PID' 'CPU%' 'MEM%' 'COMMAND(截断)')"
        for pid in $java_pids; do
            local cpu_pct mem_pct cmd
            cpu_pct=$(ps -p "$pid" -o pcpu= 2>/dev/null | tr -d ' ')
            mem_pct=$(ps -p "$pid" -o pmem= 2>/dev/null | tr -d ' ')
            cmd=$(ps -p "$pid" -o args= 2>/dev/null | cut -c1-60)
            [ -z "$cpu_pct" ] && continue
            printf "  %-8s %-8s %-8s %s\n" "$pid" "$cpu_pct" "$mem_pct" "$cmd"
            log_only "$(printf '  %-8s %-8s %-8s %s' "$pid" "$cpu_pct" "$mem_pct" "$cmd")"
            if command -v bc &>/dev/null; then
                if (( $(echo "$cpu_pct > 80" | bc -l) )); then
                    print_crit "Java进程 PID=$pid CPU使用率 ${cpu_pct}% 过高(>80%)"
                    add_root_cause "JAVA_HIGH_CPU" "Java进程CPU过高(PID=$pid, ${cpu_pct}%)" "使用四步定位法排查: top -H -> printf %x -> jstack nid匹配"
                elif (( $(echo "$cpu_pct > 50" | bc -l) )); then
                    print_warn "Java进程 PID=$pid CPU使用率 ${cpu_pct}% 偏高(>50%)"
                fi
            fi
        done
    else
        print_info "未检测到运行中的Java进程"
    fi
}

# ===========================================================================
# 内存维度诊断
# ===========================================================================
diagnose_memory() {
    print_section "内存维度诊断"

    print_subsection "内存概览 (free -h)"
    if command -v free &>/dev/null; then
        local free_output
        free_output=$(free -h 2>/dev/null)
        echo "$free_output" | while IFS= read -r line; do echo "  $line"; done
        log_only "$free_output"
        local total_mem avail_mem total_swap used_swap
        total_mem=$(free 2>/dev/null | awk '/^Mem:/{print $2}')
        avail_mem=$(free 2>/dev/null | awk '/^Mem:/{print $7}')
        if [ -z "$avail_mem" ] || [ "$avail_mem" -eq 0 ] 2>/dev/null; then
            avail_mem=$(free 2>/dev/null | awk '/^Mem:/{print $4}')
        fi
        total_swap=$(free 2>/dev/null | awk '/^Swap:/{print $2}')
        used_swap=$(free 2>/dev/null | awk '/^Swap:/{print $3}')

        print_subsection "内存可用性检查"
        if [ -n "$total_mem" ] && [ "$total_mem" -gt 0 ] 2>/dev/null && command -v bc &>/dev/null; then
            local avail_pct; avail_pct=$(echo "scale=1; $avail_mem * 100 / $total_mem" | bc -l)
            printf "  %-30s %s%%\n" "可用内存占比:" "$avail_pct%"
            log_only "$(printf '  %-30s %s%%\n' '可用内存占比:' "$avail_pct%")"
            if (( $(echo "$avail_pct < $MEM_AVAIL_CRIT" | bc -l) )); then
                print_crit "可用内存 ${avail_pct}% < ${MEM_AVAIL_CRIT}%，内存严重不足！"
                add_root_cause "MEM_INSUFFICIENT" "可用内存严重不足(${avail_pct}%)" "检查内存泄漏(jmap/MAT)，增加物理内存，调整JVM堆大小"
            elif (( $(echo "$avail_pct < $MEM_AVAIL_WARN" | bc -l) )); then
                print_warn "可用内存 ${avail_pct}% < ${MEM_AVAIL_WARN}%，内存偏低"
                add_root_cause "MEM_INSUFFICIENT" "可用内存偏低(${avail_pct}%)" "监控内存使用趋势，排查内存泄漏"
            else
                print_ok "可用内存 ${avail_pct}% 充足(> ${MEM_AVAIL_WARN}%)"
            fi
        fi
    else
        print_fail "free命令不可用"
    fi

    print_subsection "Swap使用检查"
    if [ -n "$total_swap" ] && [ "$total_swap" -gt 0 ] 2>/dev/null && command -v bc &>/dev/null; then
        local swap_pct; swap_pct=$(echo "scale=1; $used_swap * 100 / $total_swap" | bc -l)
        printf "  %-30s %s%%\n" "Swap使用率:" "$swap_pct%"
        log_only "$(printf '  %-30s %s%%\n' 'Swap使用率:' "$swap_pct%")"
        if (( $(echo "$swap_pct > 50" | bc -l) )); then
            print_warn "Swap使用率 ${swap_pct}% > 50%，物理内存不足导致频繁换页"
            add_root_cause "MEM_INSUFFICIENT" "Swap使用率高(${swap_pct}%)" "增加物理内存，检查内存泄漏，调整swappiness参数"
        elif (( $(echo "$swap_pct > 20" | bc -l) )); then
            print_warn "Swap使用率 ${swap_pct}% 偏高"
        else
            print_ok "Swap使用率 ${swap_pct}% 正常"
        fi
    else
        print_info "Swap未启用或为0"
    fi

    print_subsection "内存占用 TOP 10 进程"
    if command -v ps &>/dev/null; then
        printf "  %-8s %-8s %-10s %s\n" "PID" "MEM%" "RSS(KB)" "COMMAND"
        log_only "$(printf '  %-8s %-8s %-10s %s' 'PID' 'MEM%' 'RSS(KB)' 'COMMAND')"
        ps -eo pid,pmem,rss,comm --sort=-rss 2>/dev/null | head -11 | tail -10 | while IFS= read -r line; do
            printf "  %s\n" "$line"; log_only "  $line"
        done
    fi

    print_subsection "OOM Killer 历史记录检查"
    if command -v dmesg &>/dev/null; then
        local oom_count; oom_count=$(dmesg 2>/dev/null | count_of -i 'out of memory\|oom-killer\|killed process')
        if [ "$oom_count" -gt 0 ] 2>/dev/null; then
            print_crit "检测到 ${oom_count} 条OOM Killer记录！系统曾因内存不足杀死进程"
            add_root_cause "OOM_KILLER" "系统发生过OOM Killer事件(${oom_count}次)" "检查被杀进程内存配置，限制单进程内存上限，增加系统内存"
            log ""
            log "  最近的OOM记录:"
            dmesg 2>/dev/null | grep -i 'out of memory\|oom-killer\|killed process' | tail -5 | while IFS= read -r line; do
                echo "    $line"; log_only "    $line"
            done
        else
            print_ok "未检测到OOM Killer记录"
        fi
    else
        print_warn "dmesg命令不可用或无权限，跳过OOM检查"
    fi

    print_subsection "HugePages 配置检查"
    if [ -f /proc/meminfo ]; then
        local hp_total hp_rsvd hp_free
        hp_total=$(grep HugePages_Total /proc/meminfo 2>/dev/null | awk '{print $2}')
        hp_rsvd=$(grep HugePages_Rsvd /proc/meminfo 2>/dev/null | awk '{print $2}')
        hp_free=$(grep HugePages_Free /proc/meminfo 2>/dev/null | awk '{print $2}')
        printf "  %-30s %s\n" "HugePages_Total:" "$hp_total"
        printf "  %-30s %s\n" "HugePages_Rsvd:" "$hp_rsvd"
        printf "  %-30s %s\n" "HugePages_Free:" "$hp_free"
        log_only "$(printf '  %-30s %s\n' 'HugePages_Total:' "$hp_total")"
        log_only "$(printf '  %-30s %s\n' 'HugePages_Rsvd:' "$hp_rsvd")"
        log_only "$(printf '  %-30s %s\n' 'HugePages_Free:' "$hp_free")"
        if [ "$hp_total" -gt 0 ] 2>/dev/null; then
            print_info "已启用HugePages，若使用JVM请确保-XX:+UseLargePages配置正确"
        fi
    fi
}

# ===========================================================================
# 磁盘I/O维度诊断
# ===========================================================================
diagnose_disk() {
    print_section "磁盘I/O维度诊断"

    print_subsection "磁盘空间使用率 (df -h)"
    if command -v df &>/dev/null; then
        df -h 2>/dev/null | while IFS= read -r line; do echo "  $line"; log_only "  $line"; done
        log ""
        print_subsection "磁盘空间预警检查"
        df -h 2>/dev/null | awk 'NR>1 && $5 ~ /%/ {
            use=$5; gsub(/%/,"",use);
            if(use+0 > 90) print "CRIT " $5 " " $6;
            else if(use+0 > 70) print "WARN " $5 " " $6;
        }' | while IFS=' ' read -r lvl pct mount; do
            if [ "$lvl" = "CRIT" ]; then
                print_crit "磁盘 ${mount} 使用率 ${pct} > 90%，空间严重不足！"
                add_root_cause "DISK_FULL" "磁盘空间严重不足(${mount} ${pct})" "清理日志/临时文件，扩容磁盘，配置日志轮转"
            elif [ "$lvl" = "WARN" ]; then
                print_warn "磁盘 ${mount} 使用率 ${pct} > 70%，空间偏高"
                add_root_cause "DISK_FULL" "磁盘空间偏高(${mount} ${pct})" "关注磁盘使用趋势，清理不必要文件"
            fi
        done
    fi

    print_subsection "磁盘I/O统计 (iostat -x 1 3)"
    if command -v iostat &>/dev/null; then
        local iostat_output; iostat_output=$(iostat -x 1 3 2>/dev/null)
        echo "$iostat_output" | tail -20 | while IFS= read -r line; do echo "  $line"; done
        log_cmd_output "$iostat_output"
        print_subsection "磁盘I/O预警检查"
        iostat -x 1 2 2>/dev/null | awk 'BEGIN{found=0} /^Device/{found++} found>=2 && /^sd|^vd|^nvme|^xvd|^dm/ {
            util=$NF; gsub(/%/,"",util); await=$(NF-6);
            if(util+0 > 90) print "CRIT_UTIL " $1 " " util " " await;
            else if(util+0 > 70) print "WARN_UTIL " $1 " " util " " await;
            if(await+0 > 15) print "WARN_AWAIT " $1 " " util " " await;
        }' | while IFS=' ' read -r type dev util await; do
            case "$type" in
                CRIT_UTIL)
                    print_crit "磁盘 ${dev} %util=${util}% > 90%，I/O严重饱和！"
                    add_root_cause "IO_BOTTLENECK" "磁盘I/O饱和(${dev} %util=${util}%)" "排查高I/O进程，使用SSD替换，优化I/O模式(随机转顺序/批量写)"
                    ;;
                WARN_UTIL)
                    print_warn "磁盘 ${dev} %util=${util}% > 70%，I/O压力较大"
                    add_root_cause "IO_BOTTLENECK" "磁盘I/O压力较大(${dev} %util=${util}%)" "监控I/O趋势，排查高I/O进程"
                    ;;
                WARN_AWAIT)
                    print_warn "磁盘 ${dev} await=${await}ms 偏高(>15ms)，响应延迟较大"
                    # await 为小数，[ ] 不支持浮点比较，用 awk 判断
                    if awk -v a="$await" 'BEGIN{exit !(a>50)}'; then
                        add_root_cause "IO_BOTTLENECK" "磁盘响应延迟高(${dev} await=${await}ms)" "检查磁盘健康状态，考虑使用SSD"
                    fi
                    ;;
            esac
        done
    else
        print_fail "iostat命令不可用(需安装sysstat包)"
    fi

    print_subsection "D状态(不可中断睡眠)进程检查"
    local d_state_count; d_state_count=$(ps -eo state 2>/dev/null | count_of '^D')
    if [ "$d_state_count" -gt 0 ] 2>/dev/null; then
        print_warn "检测到 ${d_state_count} 个D状态进程(不可中断I/O等待)"
        add_root_cause "IO_BOTTLENECK" "存在D状态进程(${d_state_count}个)" "检查磁盘I/O瓶颈和硬件问题"
        log ""
        log "  D状态进程列表:"
        ps -eo pid,state,comm 2>/dev/null | awk '$2=="D"' | head -10 | while IFS= read -r line; do
            echo "    $line"; log_only "    $line"
        done
    else
        print_ok "未检测到D状态进程"
    fi
}

# ===========================================================================
# 网络维度诊断
# ===========================================================================
diagnose_network() {
    print_section "网络维度诊断"

    print_subsection "套接字统计 (ss -s)"
    if command -v ss &>/dev/null; then
        ss -s 2>/dev/null | while IFS= read -r line; do echo "  $line"; log_only "  $line"; done
    elif command -v netstat &>/dev/null; then
        print_warn "ss不可用，使用netstat替代"
        netstat -s 2>/dev/null | head -20 | while IFS= read -r line; do echo "  $line"; log_only "  $line"; done
    else
        print_fail "ss和netstat均不可用"
    fi

    print_subsection "TCP连接状态分布"
    local tcp_states=""
    if command -v ss &>/dev/null; then
        tcp_states=$(ss -ant 2>/dev/null | awk 'NR>1{print $1}' | sort | uniq -c | sort -rn)
    elif command -v netstat &>/dev/null; then
        tcp_states=$(netstat -ant 2>/dev/null | awk 'NR>2{print $6}' | sort | uniq -c | sort -rn)
    fi
    if [ -n "$tcp_states" ]; then
        printf "  %-10s %-20s\n" "数量" "状态"
        log_only "$(printf '  %-10s %-20s' '数量' '状态')"
        echo "$tcp_states" | while IFS= read -r line; do printf "  %s\n" "$line"; log_only "  $line"; done
        local time_wait_count; time_wait_count=$(echo "$tcp_states" | grep -i 'TIME-WAIT\|TIME_WAIT' | awk '{print $1}')
        [ -z "$time_wait_count" ] && time_wait_count=0
        log ""
        printf "  %-30s %s\n" "TIME-WAIT连接数:" "$time_wait_count"
        log_only "$(printf '  %-30s %s\n' 'TIME-WAIT连接数:' "$time_wait_count")"
        if [ "$time_wait_count" -gt "$TIME_WAIT_WARN" ] 2>/dev/null; then
            print_warn "TIME-WAIT连接数 ${time_wait_count} > ${TIME_WAIT_WARN}，连接回收压力大"
            add_root_cause "NETWORK_ISSUE" "TIME-WAIT连接过多(${time_wait_count})" "调整net.ipv4.tcp_tw_reuse=1，检查短连接是否过多，使用连接池"
        else
            print_ok "TIME-WAIT连接数 ${time_wait_count} 正常(< ${TIME_WAIT_WARN})"
        fi
    else
        print_warn "无法获取TCP连接状态"
    fi

    print_subsection "TCP重传率检查"
    if [ -f /proc/net/snmp ]; then
        local snmp_tcp_header snmp_tcp_value retrans_idx outsegs_idx retrans segs
        snmp_tcp_header=$(grep '^Tcp:' /proc/net/snmp 2>/dev/null | head -1)
        snmp_tcp_value=$(grep '^Tcp:' /proc/net/snmp 2>/dev/null | tail -1)
        retrans_idx=$(echo "$snmp_tcp_header" | awk '{for(i=1;i<=NF;i++) if($i=="RetransSegs") print i}')
        outsegs_idx=$(echo "$snmp_tcp_header" | awk '{for(i=1;i<=NF;i++) if($i=="OutSegs") print i}')
        if [ -n "$retrans_idx" ] && [ -n "$outsegs_idx" ]; then
            retrans=$(echo "$snmp_tcp_value" | awk -v idx="$retrans_idx" '{print $idx}')
            segs=$(echo "$snmp_tcp_value" | awk -v idx="$outsegs_idx" '{print $idx}')
            if [ -n "$segs" ] && [ "$segs" -gt 0 ] 2>/dev/null && command -v bc &>/dev/null; then
                local retrans_rate; retrans_rate=$(echo "scale=2; $retrans * 100 / $segs" | bc -l)
                printf "  %-30s %s\n" "TCP重传段数:" "$retrans"
                printf "  %-30s %s\n" "TCP发送段数:" "$segs"
                printf "  %-30s %s%%\n" "TCP重传率:" "$retrans_rate"
                log_only "$(printf '  %-30s %s\n' 'TCP重传段数:' "$retrans")"
                log_only "$(printf '  %-30s %s\n' 'TCP发送段数:' "$segs")"
                log_only "$(printf '  %-30s %s%%\n' 'TCP重传率:' "$retrans_rate")"
                if (( $(echo "$retrans_rate > $TCP_RETRANS_CRIT" | bc -l) )); then
                    print_crit "TCP重传率 ${retrans_rate}% > ${TCP_RETRANS_CRIT}%，网络质量严重恶化！"
                    add_root_cause "NETWORK_ISSUE" "TCP重传率严重过高(${retrans_rate}%)" "检查网络带宽/网卡/交换机，排查网络拥塞和丢包"
                elif (( $(echo "$retrans_rate > $TCP_RETRANS_WARN" | bc -l) )); then
                    print_warn "TCP重传率 ${retrans_rate}% > ${TCP_RETRANS_WARN}%，网络存在丢包"
                    add_root_cause "NETWORK_ISSUE" "TCP重传率偏高(${retrans_rate}%)" "检查网络链路质量，排查丢包原因"
                else
                    print_ok "TCP重传率 ${retrans_rate}% 正常(< ${TCP_RETRANS_WARN}%)"
                fi
            else
                print_info "无法计算TCP重传率"
            fi
        fi
    else
        print_warn "/proc/net/snmp 不可用，跳过TCP重传率检查"
    fi

    print_subsection "网络接口信息"
    if command -v ip &>/dev/null; then
        ip -s link 2>/dev/null | grep -E '^[0-9]+:|RX:|TX:' | while IFS= read -r line; do echo "  $line"; log_only "  $line"; done
    elif command -v ifconfig &>/dev/null; then
        ifconfig 2>/dev/null | head -30 | while IFS= read -r line; do echo "  $line"; log_only "  $line"; done
    fi

    print_subsection "连接队列溢出检查"
    if [ -f /proc/net/netstat ]; then
        local overflow dropped
        overflow=$(awk '/^TcpExt:/{for(i=1;i<=NF;i++) if($i=="ListenOverflows") idx=i; getline; print $idx}' /proc/net/netstat 2>/dev/null)
        dropped=$(awk '/^TcpExt:/{for(i=1;i<=NF;i++) if($i=="ListenDrops") idx=i; getline; print $idx}' /proc/net/netstat 2>/dev/null)
        [ -z "$overflow" ] && overflow=0
        [ -z "$dropped" ] && dropped=0
        printf "  %-40s %s\n" "ListenOverflows(全连接队列溢出):" "$overflow"
        printf "  %-40s %s\n" "ListenDrops(连接丢弃):" "$dropped"
        log_only "$(printf '  %-40s %s\n' 'ListenOverflows(全连接队列溢出):' "$overflow")"
        log_only "$(printf '  %-40s %s\n' 'ListenDrops(连接丢弃):' "$dropped")"
        if [ "$overflow" -gt 0 ] 2>/dev/null; then
            print_warn "全连接队列溢出 ${overflow} 次，服务端accept能力不足或连接突增"
            add_root_cause "NETWORK_ISSUE" "全连接队列溢出(${overflow}次)" "增大somaxconn和应用层backlog，优化accept速度"
        fi
        if [ "$dropped" -gt 0 ] 2>/dev/null; then
            print_warn "连接丢弃 ${dropped} 次"
        fi
    fi
}
# ===========================================================================
# JVM深度诊断
# ===========================================================================
get_java_pids() {
    if command -v jps &>/dev/null; then
        jps -l 2>/dev/null | awk '{print $1}'
    else
        pgrep -f java 2>/dev/null || echo ""
    fi
}

get_java_name() {
    local pid="$1"
    if command -v jps &>/dev/null; then
        jps -l 2>/dev/null | awk -v p="$pid" '$1==p{$1=""; print substr($0,2)}'
    else
        ps -p "$pid" -o comm= 2>/dev/null
    fi
}

diagnose_jvm_all() {
    print_section "JVM深度诊断"
    if command -v jps &>/dev/null; then
        print_subsection "所有Java进程列表 (jps -lv)"
        jps -lv 2>/dev/null | while IFS= read -r line; do echo "  $line"; log_only "  $line"; done
    else
        print_warn "jps不可用，使用pgrep检测Java进程"
    fi

    local pids; pids=$(get_java_pids)
    if [ -z "$pids" ]; then
        print_info "未检测到运行中的Java进程，跳过JVM诊断"
        return
    fi

    local count; count=$(echo "$pids" | wc -w)
    print_info "检测到 ${count} 个Java进程，开始逐一诊断..."

    for pid in $pids; do
        diagnose_single_jvm "$pid"
    done
}

diagnose_single_jvm() {
    local pid="$1"
    local jname; jname=$(get_java_name "$pid")
    [ -z "$jname" ] && jname="未知"

    print_section "JVM诊断 - PID=$pid ($jname)"

    # 进程基本信息
    print_subsection "进程基本信息"
    local cpu_pct mem_pct rss_kb thread_count start_time
    cpu_pct=$(ps -p "$pid" -o pcpu= 2>/dev/null | tr -d ' ')
    mem_pct=$(ps -p "$pid" -o pmem= 2>/dev/null | tr -d ' ')
    rss_kb=$(ps -p "$pid" -o rss= 2>/dev/null | tr -d ' ')
    thread_count=$(ps -p "$pid" -o nlwp= 2>/dev/null | tr -d ' ')
    [ -z "$thread_count" ] && thread_count=$(ls /proc/$pid/task 2>/dev/null | wc -l)
    start_time=$(ps -p "$pid" -o lstart= 2>/dev/null)
    printf "  %-20s %s\n" "进程PID:" "$pid"
    printf "  %-20s %s\n" "进程名称:" "$jname"
    printf "  %-20s %s%%\n" "CPU使用率:" "$cpu_pct"
    printf "  %-20s %s%%\n" "内存使用率:" "$mem_pct"
    printf "  %-20s %s KB\n" "RSS内存:" "$rss_kb"
    printf "  %-20s %s\n" "线程数:" "$thread_count"
    printf "  %-20s %s\n" "启动时间:" "$start_time"
    log_only "$(printf '  %-20s %s\n' '进程PID:' "$pid")"
    log_only "$(printf '  %-20s %s\n' '进程名称:' "$jname")"
    log_only "$(printf '  %-20s %s%%\n' 'CPU使用率:' "$cpu_pct")"
    log_only "$(printf '  %-20s %s%%\n' '内存使用率:' "$mem_pct")"
    log_only "$(printf '  %-20s %s KB' 'RSS内存:' "$rss_kb")"
    log_only "$(printf '  %-20s %s\n' '线程数:' "$thread_count")"
    log_only "$(printf '  %-20s %s\n' '启动时间:' "$start_time")"
    if [ -n "$thread_count" ] && [ "$thread_count" -gt "$JVM_THREAD_WARN" ] 2>/dev/null; then
        print_warn "线程数 ${thread_count} > ${JVM_THREAD_WARN}，线程数过多"
        add_root_cause "TOO_MANY_THREADS" "线程数过多(PID=$pid, ${thread_count}个)" "检查线程池配置，排查线程泄漏，使用jstack分析线程状态"
    fi

    # jstat -gcutil
    print_subsection "GC统计 (jstat -gcutil)"
    if command -v jstat &>/dev/null; then
        local gc_output; gc_output=$(jstat -gcutil "$pid" 2>/dev/null)
        if [ -n "$gc_output" ]; then
            echo "$gc_output" | while IFS= read -r line; do echo "  $line"; done
            log_cmd_output "$gc_output"
            local s0 s1 e o m ygc fgc ygct fgct gct
            s0=$(echo "$gc_output" | tail -1 | awk '{print $1}')
            s1=$(echo "$gc_output" | tail -1 | awk '{print $2}')
            e=$(echo "$gc_output" | tail -1 | awk '{print $3}')
            o=$(echo "$gc_output" | tail -1 | awk '{print $4}')
            m=$(echo "$gc_output" | tail -1 | awk '{print $5}')
            ygc=$(echo "$gc_output" | tail -1 | awk '{print $6}')
            fgc=$(echo "$gc_output" | tail -1 | awk '{print $7}')
            ygct=$(echo "$gc_output" | tail -1 | awk '{print $8}')
            fgct=$(echo "$gc_output" | tail -1 | awk '{print $9}')
            gct=$(echo "$gc_output" | tail -1 | awk '{print $10}')
            log ""
            printf "  %-20s %s%%\n" "S0 (Survivor0):" "$s0"
            printf "  %-20s %s%%\n" "S1 (Survivor1):" "$s1"
            printf "  %-20s %s%%\n" "E (Eden):" "$e"
            printf "  %-20s %s%%\n" "O (Old):" "$o"
            printf "  %-20s %s%%\n" "M (Metaspace):" "$m"
            printf "  %-20s %s\n" "YGC (Young GC次数):" "$ygc"
            printf "  %-20s %s\n" "FGC (Full GC次数):" "$fgc"
            printf "  %-20s %s s\n" "YGCT (Young GC耗时):" "$ygct"
            printf "  %-20s %s s\n" "FGCT (Full GC耗时):" "$fgct"
            printf "  %-20s %s s\n" "GCT (总GC耗时):" "$gct"
            log_only "$(printf '  %-20s %s%%\n' 'S0 (Survivor0):' "$s0")"
            log_only "$(printf '  %-20s %s%%\n' 'S1 (Survivor1):' "$s1")"
            log_only "$(printf '  %-20s %s%%\n' 'E (Eden):' "$e")"
            log_only "$(printf '  %-20s %s%%\n' 'O (Old):' "$o")"
            log_only "$(printf '  %-20s %s%%\n' 'M (Metaspace):' "$m")"
            log_only "$(printf '  %-20s %s\n' 'YGC (Young GC次数):' "$ygc")"
            log_only "$(printf '  %-20s %s\n' 'FGC (Full GC次数):' "$fgc")"
            log_only "$(printf '  %-20s %s s\n' 'YGCT (Young GC耗时):' "$ygct")"
            log_only "$(printf '  %-20s %s s\n' 'FGCT (Full GC耗时):' "$fgct")"
            log_only "$(printf '  %-20s %s s\n' 'GCT (总GC耗时):' "$gct")"

            print_subsection "GC预警检查"
            # 老年代使用率
            if [ -n "$o" ] && [ "$o" -gt "$JVM_OLD_GEN_CRIT" ] 2>/dev/null; then
                print_crit "老年代使用率 ${o}% > ${JVM_OLD_GEN_CRIT}%，老年代即将耗尽！"
                add_root_cause "MEM_LEAK" "老年代使用率过高(PID=$pid, ${o}%)" "使用jmap -histo/MAT分析堆对象，排查内存泄漏，考虑扩堆或Full GC后分析"
            elif [ -n "$o" ] && [ "$o" -gt 80 ] 2>/dev/null; then
                print_warn "老年代使用率 ${o}% 偏高(>80%)"
                add_root_cause "MEM_LEAK" "老年代使用率偏高(PID=$pid, ${o}%)" "监控老年代增长趋势，准备堆dump分析"
            fi
            # Metaspace使用率
            if [ -n "$m" ] && [ "$m" -gt "$JVM_METASPACE_CRIT" ] 2>/dev/null; then
                print_crit "Metaspace使用率 ${m}% > ${JVM_METASPACE_CRIT}%，元空间即将耗尽！"
                add_root_cause "METASPACE_OOM" "Metaspace使用率过高(PID=$pid, ${m}%)" "检查动态类加载/反射/CGLIB，调大MaxMetaspaceSize，使用jcmd VM.metaspace查看"
            elif [ -n "$m" ] && [ "$m" -gt 85 ] 2>/dev/null; then
                print_warn "Metaspace使用率 ${m}% 偏高(>85%)"
            fi
            # Full GC平均耗时
            if [ -n "$fgc" ] && [ "$fgc" -gt 0 ] && [ -n "$fgct" ] && command -v bc &>/dev/null; then
                local fgc_avg; fgc_avg=$(echo "scale=2; $fgct * 1000 / $fgc" | bc -l)
                printf "  %-30s %s ms\n" "Full GC平均耗时:" "$fgc_avg"
                log_only "$(printf '  %-30s %s ms\n' 'Full GC平均耗时:' "$fgc_avg")"
                if (( $(echo "$fgc_avg > $JVM_FGC_TIME_CRIT" | bc -l) )); then
                    print_crit "Full GC平均耗时 ${fgc_avg}ms > ${JVM_FGC_TIME_CRIT}ms，STW严重！"
                    add_root_cause "FREQUENT_GC" "Full GC平均耗时过长(PID=$pid, ${fgc_avg}ms)" "优化GC: 调整堆大小/GC算法(G1/ZGC)，排查大对象直接进老年代，减少Full GC频率"
                fi
            fi
            # GC时间占比
            if [ -n "$gct" ] && command -v bc &>/dev/null; then
                local gc_ratio; gc_ratio=$(echo "scale=2; $gct * 100 / ($ygct + $fgct + 0.001)" | bc -l)
                # 使用进程运行时间计算GC占比更准确
                local uptime_sec; uptime_sec=$(ps -p "$pid" -o etimes= 2>/dev/null | tr -d ' ')
                if [ -n "$uptime_sec" ] && [ "$uptime_sec" -gt 0 ] 2>/dev/null; then
                    gc_ratio=$(echo "scale=2; $gct * 100 / $uptime_sec" | bc -l)
                    printf "  %-30s %s%%\n" "GC时间占比:" "$gc_ratio%"
                    log_only "$(printf '  %-30s %s%%\n' 'GC时间占比:' "$gc_ratio%")"
                    if (( $(echo "$gc_ratio > $JVM_GC_RATIO_CRIT" | bc -l) )); then
                        print_crit "GC时间占比 ${gc_ratio}% > ${JVM_GC_RATIO_CRIT}%，GC开销过大！"
                        add_root_cause "FREQUENT_GC" "GC时间占比过高(PID=$pid, ${gc_ratio}%)" "优化GC参数，排查内存泄漏导致频繁GC，考虑更换GC算法"
                    fi
                fi
            fi
            # Full GC次数过多
            if [ -n "$fgc" ] && [ "$fgc" -gt 10 ] 2>/dev/null; then
                print_warn "Full GC次数 ${fgc} > 10，频繁Full GC"
                add_root_cause "FREQUENT_GC" "Full GC频繁(PID=$pid, ${fgc}次)" "排查内存泄漏/大对象，优化堆大小和GC策略"
            fi
        else
            print_warn "无法获取jstat -gcutil数据（进程可能已退出或权限不足）"
        fi
    else
        print_fail "jstat命令不可用，跳过GC分析"
    fi

    # jstack线程状态分析
    print_subsection "线程状态分析 (jstack)"
    local jstack_file="${REPORT_DIR}/jstack_${pid}_$(date +%Y%m%d_%H%M%S).txt"
    if command -v jstack &>/dev/null; then
        local jstack_output
        jstack_output=$(jstack "$pid" 2>/dev/null)
        if [ -n "$jstack_output" ]; then
            # 保存jstack输出到文件
            echo "$jstack_output" > "$jstack_file"
            print_info "jstack输出已保存到: $jstack_file"

            # 线程状态统计
            local runnable blocked waiting timed_waiting total_threads deadlocked
            runnable=$(echo "$jstack_output" | count_of 'java.lang.Thread.State: RUNNABLE')
            blocked=$(echo "$jstack_output" | count_of 'java.lang.Thread.State: BLOCKED')
            waiting=$(echo "$jstack_output" | count_of 'java.lang.Thread.State: WAITING')
            timed_waiting=$(echo "$jstack_output" | count_of 'java.lang.Thread.State: TIMED_WAITING')
            total_threads=$((runnable + blocked + waiting + timed_waiting))
            printf "  %-25s %s\n" "RUNNABLE (运行中):" "$runnable"
            printf "  %-25s %s\n" "BLOCKED (阻塞):" "$blocked"
            printf "  %-25s %s\n" "WAITING (等待):" "$waiting"
            printf "  %-25s %s\n" "TIMED_WAITING (限时等待):" "$timed_waiting"
            printf "  %-25s %s\n" "总线程数:" "$total_threads"
            log_only "$(printf '  %-25s %s\n' 'RUNNABLE (运行中):' "$runnable")"
            log_only "$(printf '  %-25s %s\n' 'BLOCKED (阻塞):' "$blocked")"
            log_only "$(printf '  %-25s %s\n' 'WAITING (等待):' "$waiting")"
            log_only "$(printf '  %-25s %s\n' 'TIMED_WAITING (限时等待):' "$timed_waiting")"
            log_only "$(printf '  %-25s %s\n' '总线程数:' "$total_threads")"

            # BLOCKED线程预警
            print_subsection "BLOCKED线程预警"
            if [ "$blocked" -gt "$JVM_BLOCKED_CRIT" ] 2>/dev/null; then
                print_crit "BLOCKED线程数 ${blocked} > ${JVM_BLOCKED_CRIT}，严重锁竞争！"
                add_root_cause "LOCK_CONTENTION" "BLOCKED线程过多(PID=$pid, ${blocked}个)" "使用jstack分析锁等待关系，优化锁粒度，排查死锁，考虑使用并发容器"
            elif [ "$blocked" -gt "$JVM_BLOCKED_WARN" ] 2>/dev/null; then
                print_warn "BLOCKED线程数 ${blocked} > ${JVM_BLOCKED_WARN}，存在锁竞争"
                add_root_cause "LOCK_CONTENTION" "BLOCKED线程较多(PID=$pid, ${blocked}个)" "分析锁竞争热点，优化同步策略"
            else
                print_ok "BLOCKED线程数 ${blocked} 正常(< ${JVM_BLOCKED_WARN})"
            fi

            # 死锁检测
            print_subsection "死锁检测"
            local deadlock_found
            deadlock_found=$(echo "$jstack_output" | grep -i 'Found .* deadlock\|Deadlock Detection' || echo "")
            if [ -n "$deadlock_found" ]; then
                print_crit "检测到死锁！"
                add_root_cause "DEADLOCK" "检测到死锁(PID=$pid)" "分析jstack死锁详情，优化锁获取顺序，使用tryLock避免死锁"
                log ""
                log "  死锁详情:"
                echo "$jstack_output" | grep -A 50 -i 'Found .* deadlock' | head -55 | while IFS= read -r line; do
                    echo "    $line"; log_only "    $line"
                done
            else
                print_ok "未检测到死锁"
            fi

            # BLOCKED线程锁等待分析
            if [ "$blocked" -gt 0 ] 2>/dev/null; then
                print_subsection "BLOCKED线程锁等待分析 (TOP 5)"
                echo "$jstack_output" | awk '/java.lang.Thread.State: BLOCKED/{found=1} found && /waiting to lock/{print; found=0}' | \
                    sed 's/^ *//' | sort | uniq -c | sort -rn | head -5 | while IFS= read -r line; do
                    echo "    $line"; log_only "    $line"
                done
            fi
        else
            print_warn "无法获取jstack输出（进程可能已退出或权限不足）"
        fi
    else
        print_fail "jstack命令不可用，跳过线程状态分析"
    fi

    # 四步定位法 - 高CPU时自动执行
    if command -v bc &>/dev/null && [ -n "$cpu_pct" ] && (( $(echo "$cpu_pct > 50" | bc -l) )); then
        print_subsection "CPU四步定位法 (自动触发: CPU=${cpu_pct}%>50%)"
        cpu_four_step_locate "$pid"
    fi

    # 堆对象统计 - jmap安全模式处理
    print_subsection "堆对象统计 TOP 20"
    # 安全说明: jmap -histo:live 会触发Full GC导致STW
    #           jmap -dump 会导致应用暂停，生产环境慎用
    #           安全模式优先使用 jcmd GC.class_histogram（JDK9+，影响更小）
    if [ "$JVM_SAFE_MODE" = true ]; then
        print_info "安全模式: 跳过jmap高危操作（jmap -histo:live会触发Full GC）"
        echo -e "  ${YELLOW}jmap安全风险说明:${NC}"
        echo "    - jmap -histo:live  会触发Full GC，导致应用短暂暂停"
        echo "    - jmap -dump        会暂停整个JVM，大堆可能停顿数十秒"
        echo "    - 生产环境建议使用Arthas heapdump或配置OOM自动dump"
        log_only "  [安全模式] 跳过jmap操作(jmap -histo:live会触发Full GC)"
        log_only "    jmap -histo:live  -> 会触发Full GC"
        log_only "    jmap -dump        -> 会暂停整个JVM"
        log_only "    建议替代方案: Arthas heapdump / -XX:+HeapDumpOnOutOfMemoryError"
        # 尝试使用jcmd GC.class_histogram（影响较小的替代方案）
        if command -v jcmd &>/dev/null; then
            print_info "尝试使用jcmd GC.class_histogram（影响更小的替代方案）..."
            local jcmd_histo
            jcmd_histo=$(jcmd "$pid" GC.class_histogram 2>/dev/null | head -25)
            if [ -n "$jcmd_histo" ]; then
                echo "$jcmd_histo" | while IFS= read -r line; do echo "  $line"; done
                log_cmd_output "$jcmd_histo"
                local top_class top_count
                top_class=$(echo "$jcmd_histo" | grep -v '^[: ]' | grep -v '^ num' | head -2 | tail -1 | awk '{print $4}')
                top_count=$(echo "$jcmd_histo" | grep -v '^[: ]' | grep -v '^ num' | head -2 | tail -1 | awk '{print $2}')
                if [ -n "$top_count" ] && [ "$top_count" -gt 1000000 ] 2>/dev/null; then
                    print_warn "堆中存在大量对象: ${top_class} (${top_count}个)，可能有内存泄漏"
                    add_root_cause "MEM_LEAK" "堆对象过多(PID=$pid, ${top_class} ${top_count}个)" "配置-XX:+HeapDumpOnOutOfMemoryError自动dump，用MAT分析对象引用链"
                fi
            else
                print_warn "jcmd GC.class_histogram不可用（可能JDK版本过低或权限不足）"
            fi
        fi
        echo ""
        echo -e "  ${CYAN}如需启用jmap完整分析，请使用: --allow-jmap 参数（注意STW风险）${NC}"
        log_only "  如需启用jmap完整分析，请使用 --allow-jmap 参数（注意STW风险）"
    else
        # 非安全模式: 使用jmap但避免:live（:live会触发Full GC）
        print_warn "已启用jmap分析（--allow-jmap），注意STW风险"
        echo -e "  ${YELLOW}注意: 使用jmap -histo（不含:live）以避免触发Full GC${NC}"
        log_only "  [非安全模式] 使用jmap -histo（不含:live以避免Full GC）"
        if command -v jmap &>/dev/null; then
            local histo_output
            # 使用jmap -histo而非jmap -histo:live，避免触发Full GC
            histo_output=$(jmap -histo "$pid" 2>/dev/null | head -25)
            if [ -n "$histo_output" ]; then
                echo "$histo_output" | while IFS= read -r line; do echo "  $line"; done
                log_cmd_output "$histo_output"
                local top_class top_count
                top_class=$(echo "$histo_output" | grep -v '^[: ]' | grep -v '^ num' | head -2 | tail -1 | awk '{print $4}')
                top_count=$(echo "$histo_output" | grep -v '^[: ]' | grep -v '^ num' | head -2 | tail -1 | awk '{print $2}')
                if [ -n "$top_count" ] && [ "$top_count" -gt 1000000 ] 2>/dev/null; then
                    print_warn "堆中存在大量对象: ${top_class} (${top_count}个)，可能有内存泄漏"
                    add_root_cause "MEM_LEAK" "堆对象过多(PID=$pid, ${top_class} ${top_count}个)" "使用jmap -dump导出heap dump(注意STW)，用MAT分析对象引用链，或配置-XX:+HeapDumpOnOutOfMemoryError"
                fi
            else
                print_warn "无法获取jmap -histo数据（进程可能已退出或权限不足）"
            fi
        else
            print_fail "jmap命令不可用，跳过堆对象分析"
        fi
    fi

    # JVM启动参数分析
    print_subsection "JVM启动参数分析"
    local jvm_args
    jvm_args=$(ps -p "$pid" -o args= 2>/dev/null)
    if [ -n "$jvm_args" ]; then
        # 提取JVM参数
        echo "$jvm_args" | tr ' ' '\n' | grep '^\-X\|^\-XX:\|^\-D' | while IFS= read -r arg; do
            echo "    $arg"; log_only "    $arg"
        done
        log ""
        # 检查关键JVM参数
        print_subsection "JVM参数建议检查"
        if ! echo "$jvm_args" | grep -q 'HeapDumpOnOutOfMemoryError'; then
            print_warn "未配置 -XX:+HeapDumpOnOutOfMemoryError，OOM时无法自动生成dump"
            log "    建议: 添加 -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/path/to/dump"
        fi
        if ! echo "$jvm_args" | grep -q '\-Xmx'; then
            print_warn "未显式配置 -Xmx 最大堆大小"
        fi
        if ! echo "$jvm_args" | grep -q '\-Xms'; then
            print_info "未配置 -Xms 初始堆大小(建议Xms=Xmx避免堆扩张)"
        fi
        if echo "$jvm_args" | grep -q 'UseSerialGC\|UseParallelGC' && ! echo "$jvm_args" | grep -q 'UseG1GC\|UseZGC'; then
            print_info "使用Serial/Parallel GC，大堆场景建议考虑G1/ZGC"
        fi
    fi
}

# ===========================================================================
# CPU四步定位法 (四步定位法核心)
# ===========================================================================
cpu_four_step_locate() {
    local target_pid="$1"
    if [ -z "$target_pid" ]; then
        print_fail "未指定目标Java进程PID"
        return 1
    fi

    print_subsection "CPU四步定位法 - PID=$target_pid"
    log "${CYAN}文章9核心: CPU打满四步定位法${NC}"
    print_sub_separator

    # 第一步: top找到目标进程PID (已提供)
    log "${YELLOW}第一步: 确认目标进程 (PID=${target_pid})${NC}"
    local main_cpu
    main_cpu=$(ps -p "$target_pid" -o pcpu= 2>/dev/null | tr -d ' ')
    local main_name
    main_name=$(get_java_name "$target_pid")
    printf "    PID=%s  CPU=%s%%  名称=%s\n" "$target_pid" "$main_cpu" "$main_name"
    log_only "$(printf '    PID=%s  CPU=%s%%  名称=%s' "$target_pid" "$main_cpu" "$main_name")"

    # 第二步: top -H -p PID 找到高CPU线程TID
    log ""
    log "${YELLOW}第二步: top -H 找到高CPU线程TID${NC}"
    if ! command -v top &>/dev/null; then
        print_fail "top命令不可用，无法执行四步定位法"
        return 1
    fi
    local top_h_output top_threads
    top_h_output=$(top -H -bn1 -p "$target_pid" 2>/dev/null)
    echo "$top_h_output" | head -20 | while IFS= read -r line; do echo "    $line"; done
    log_only "$top_h_output"

    # 提取CPU最高的线程TID (跳过表头行)
    local top_tid top_tid_cpu
    top_tid=$(echo "$top_h_output" | awk 'NR>7 {print $1; exit}')
    top_tid_cpu=$(echo "$top_h_output" | awk 'NR>7 {print $9; exit}')
    if [ -z "$top_tid" ]; then
        print_warn "未找到高CPU线程(进程可能已退出或CPU使用率低)"
        # 尝试从 ps 获取线程信息
        top_tid=$(ps -L -p "$target_pid" -o tid,pcpu --sort=-pcpu 2>/dev/null | awk 'NR==2{print $1}')
        top_tid_cpu=$(ps -L -p "$target_pid" -o tid,pcpu --sort=-pcpu 2>/dev/null | awk 'NR==2{print $2}')
        if [ -z "$top_tid" ]; then
            print_fail "无法获取线程信息"
            return 1
        fi
    fi
    printf "    >> 高CPU线程TID=%s  CPU=%s%%\n" "$top_tid" "$top_tid_cpu"
    log_only "$(printf '    >> 高CPU线程TID=%s  CPU=%s%%' "$top_tid" "$top_tid_cpu")"

    # 第三步: printf '%x\n' TID 转十六进制NID
    log ""
    log "${YELLOW}第三步: 将TID转换为十六进制NID${NC}"
    local nid
    nid=$(printf '%x\n' "$top_tid" 2>/dev/null)
    printf "    TID(十进制)=%s  ->  NID(十六进制)=0x%s\n" "$top_tid" "$nid"
    log_only "$(printf '    TID(十进制)=%s  ->  NID(十六进制)=0x%s' "$top_tid" "$nid")"
    if [ -z "$nid" ]; then
        print_fail "TID转十六进制失败"
        return 1
    fi

    # 第四步: jstack查找nid=NID的线程堆栈
    log ""
    log "${YELLOW}第四步: jstack查找nid=0x${nid}的线程堆栈${NC}"
    if ! command -v jstack &>/dev/null; then
        print_fail "jstack命令不可用，无法查看线程堆栈"
        return 1
    fi
    local jstack_output thread_stack
    jstack_output=$(jstack "$target_pid" 2>/dev/null)
    if [ -z "$jstack_output" ]; then
        print_warn "无法获取jstack输出"
        return 1
    fi
    # 查找匹配nid的线程堆栈
    thread_stack=$(echo "$jstack_output" | awk -v nid="0x$nid" '
        /"/{found=0}
        $0 ~ nid {found=1}
        found {print}
        found && /^$/{exit}
    ')
    if [ -z "$thread_stack" ]; then
        # 尝试不区分大小写匹配
        thread_stack=$(echo "$jstack_output" | grep -i -A 30 "nid=0x$nid\|nid=$nid" | head -35)
    fi
    if [ -n "$thread_stack" ]; then
        log ""
        log "${GREEN}>> 定位到高CPU线程堆栈:${NC}"
        echo "$thread_stack" | while IFS= read -r line; do
            echo "    $line"; log_only "    $line"
        done
        log ""
        print_ok "四步定位法执行完成，请检查上述堆栈中的代码行"
        log "${CYAN}常见根因参考:${NC}"
        log "  - 死循环/无限递归: 检查循环条件和递归终止条件"
        log "  - 频繁Full GC: 查看GC日志，jstat -gcutil确认"
        log "  - 正则回溯灾难: 检查正则表达式，使用预编译Pattern"
        log "  - 锁竞争与伪共享: 检查synchronized/Lock使用"
        log "  - 计算密集型任务缺乏限流: 添加限流/异步处理"
        log "${CYAN}Arthas替代命令:${NC}"
        log "  thread -n 5          # 查看CPU占用最高的5个线程"
        log "  thread <tid>         # 查看指定线程堆栈"
        log "  thread --state BLOCKED  # 查看所有BLOCKED线程"
        log "  thread -b            # 查看阻塞其他线程的线程"
        add_root_cause "JAVA_HIGH_CPU" "Java线程CPU过高(PID=$target_pid, TID=$top_tid)" "检查上述线程堆栈代码行，排查死循环/频繁GC/正则回溯/锁竞争/计算密集任务"
    else
        print_warn "未找到nid=0x${nid}的线程(可能线程已结束)"
    fi
}

# ===========================================================================
# 综合根因分析
# ===========================================================================
analyze_root_causes() {
    print_section "综合根因分析"
    log "${CYAN}根据所有诊断结果自动推断问题根因${NC}"
    print_sub_separator

    if [ ${#ROOT_CAUSES[@]} -eq 0 ]; then
        print_ok "未检测到明显异常，系统运行状态良好"
        log ""
        log "${GREEN}当前系统各项指标均在正常范围内，建议定期巡检以保持系统健康。${NC}"
        return
    fi

    log ""
    log "${YELLOW}检测到以下潜在根因 (共 ${#ROOT_CAUSES[@]} 项):${NC}"
    log ""
    local idx=1
    for key in "${!ROOT_CAUSES[@]}"; do
        local value="${ROOT_CAUSES[$key]}"
        local desc="${value%%|*}"
        local advice="${value#*|}"
        print_separator
        log "${RED}根因${idx}: ${desc}${NC}"
        print_sub_separator
        log "${CYAN}类型:${NC} $key"
        log "${CYAN}描述:${NC} $desc"
        log "${GREEN}处理建议:${NC} $advice"
        log ""
        # 根因类型详细建议
        case "$key" in
            IO_BOTTLENECK)
                log "  [详细分析] I/O瓶颈可能原因:"
                log "    - 磁盘性能不足(SSD应await<1ms, HDD<15ms)"
                log "    - 随机I/O过多(考虑顺序化/批量写)"
                log "    - 慢SQL/大文件读写"
                log "    - 磁盘硬件故障"
                ;;
            CPU_INTENSIVE|JAVA_HIGH_CPU)
                log "  [详细分析] CPU密集型可能原因(五大根因):"
                log "    1. 死循环/无限递归 - 检查循环和递归终止条件"
                log "    2. 频繁Full GC - jstat确认,优化GC参数"
                log "    3. 正则回溯灾难 - 检查正则表达式复杂度"
                log "    4. 锁竞争与伪共享 - 检查synchronized使用"
                log "    5. 计算密集型任务缺乏限流 - 添加限流/线程池"
                ;;
            MEM_LEAK|MEM_INSUFFICIENT)
                log "  [详细分析] 内存问题可能原因:"
                log "    - 堆内存OOM: jmap -histo/MAT分析对象引用链"
                log "    - Metaspace OOM: 检查动态类加载/反射"
                log "    - 线程资源OOM: 检查线程数和ulimit"
                log "    - 直接内存OOM: VM.native_memory查看"
                log "    - GC效率OOM: 调整GC策略"
                log "    - 数组大小超限: 检查大数组分配"
                log "    - 栈溢出: jstack查看调用深度"
                ;;
            FREQUENT_GC)
                log "  [详细分析] GC频繁可能原因:"
                log "    - 内存泄漏导致老年代快速填满"
                log "    - 堆大小设置不合理"
                log "    - 大对象直接进入老年代"
                log "    - GC算法选择不当(建议G1/ZGC)"
                log "    - GC参数: -Xms/-Xmx, MaxMetaspaceSize, HeapDumpOnOutOfMemoryError"
                ;;
            LOCK_CONTENTION|DEADLOCK)
                log "  [详细分析] 锁竞争可能原因:"
                log "    - 锁粒度过大(细化锁范围)"
                log "    - 锁获取顺序不一致(死锁)"
                log "    - 伪共享(@Contended/缓存行填充)"
                log "    - 使用synchronized而非并发容器"
                log "    - Arthas: thread -b 查看阻塞源"
                ;;
            CS_STORM)
                log "  [详细分析] 上下文切换风暴可能原因:"
                log "    - 线程数过多(减少线程/使用线程池)"
                log "    - 锁竞争导致频繁切换"
                log "    - I/O阻塞线程过多"
                log "    - 频繁的系统调用"
                ;;
            NETWORK_ISSUE)
                log "  [详细分析] 网络问题可能原因:"
                log "    - TIME-WAIT过多: 开启tcp_tw_reuse,使用连接池"
                log "    - TCP重传高: 检查网络链路质量"
                log "    - 连接队列溢出: 增大somaxconn和backlog"
                log "    - 带宽不足/网卡瓶颈"
                ;;
            TOO_MANY_THREADS)
                log "  [详细分析] 线程数过多可能原因:"
                log "    - 线程池配置不当(核心线程数过大)"
                log "    - 线程泄漏(未正确关闭)"
                log "    - 每请求一线程模式(改为线程池)"
                log "    - ulimit -u 限制检查"
                ;;
            DISK_FULL)
                log "  [详细分析] 磁盘空间不足可能原因:"
                log "    - 日志文件过大(配置logrotate)"
                log "    - 临时文件未清理"
                log "    - 堆dump文件堆积"
                log "    - 考虑扩容磁盘"
                ;;
            CPU_OVERLOAD)
                log "  [详细分析] 系统负载过高可能原因:"
                log "    - CPU计算密集型任务过多"
                log "    - I/O等待导致负载升高"
                log "    - 进程数/线程数过多"
                log "    - 考虑扩容CPU或限流降级"
                ;;
        esac
        log ""
        ((idx++))
    done
    print_separator
    log "${CYAN}根因分析完成。建议优先处理标记为 CRIT 的严重问题。${NC}"
}
# ===========================================================================
# 诊断执行封装
# ===========================================================================
run_system_diagnosis() {
    diagnose_system_overview
    diagnose_cpu
    diagnose_memory
    diagnose_disk
    diagnose_network
}

run_jvm_diagnosis() {
    diagnose_jvm_all
}

run_full_diagnosis() {
    check_and_install_tools
    run_system_diagnosis
    run_jvm_diagnosis
    analyze_root_causes
}

run_quick_overview() {
    print_section "快速概览"
    print_subsection "Load Average"
    cat /proc/loadavg 2>/dev/null | while IFS= read -r line; do echo "  $line"; log_only "  $line"; done
    local load1 load5 load15
    read -r load1 load5 load15 _ < <(cat /proc/loadavg 2>/dev/null)
    local cpu_cores; cpu_cores=$(nproc 2>/dev/null || echo 1)
    if command -v bc &>/dev/null; then
        local ratio; ratio=$(echo "scale=2; $load1 / $cpu_cores" | bc -l)
        if (( $(echo "$ratio > 1.0" | bc -l) )); then
            print_crit "负载/核心比 ${ratio} > 1.0，系统过载！"
        elif (( $(echo "$ratio > 0.7" | bc -l) )); then
            print_warn "负载/核心比 ${ratio} > 0.7，负载偏高"
        else
            print_ok "负载/核心比 ${ratio} 正常"
        fi
    fi
    print_subsection "Top 进程"
    if command -v top &>/dev/null; then
        top -bn1 2>/dev/null | head -15 | while IFS= read -r line; do echo "  $line"; log_only "  $line"; done
    fi
    print_subsection "内存概览"
    if command -v free &>/dev/null; then
        free -h 2>/dev/null | while IFS= read -r line; do echo "  $line"; log_only "  $line"; done
    fi
}

# ===========================================================================
# 报告摘要
# ===========================================================================
print_report_summary() {
    print_section "诊断摘要"
    echo -e "${CYAN}告警统计:${NC}"
    printf "  %-15s %s\n" "[INFO] 信息:" "$COUNT_INFO"
    printf "  %-15s %s\n" "[OK] 正常:" "$COUNT_OK"
    printf "  %-15s %s\n" "[WARN] 警告:" "$COUNT_WARN"
    printf "  %-15s %s\n" "[CRIT] 严重:" "$COUNT_CRIT"
    printf "  %-15s %s\n" "[FAIL] 失败:" "$COUNT_FAIL"
    [ "$MD_SKIP" = false ] && cat >> "$REPORT_FILE" <<MDEOF

| 状态 | 数量 |
|------|------|
| INFO (信息) | $COUNT_INFO |
| OK (正常) | $COUNT_OK |
| WARN (警告) | $COUNT_WARN |
| CRIT (严重) | $COUNT_CRIT |
| FAIL (失败) | $COUNT_FAIL |

MDEOF
    print_sub_separator
    if [ "$COUNT_CRIT" -gt 0 ]; then
        print_crit "存在 ${COUNT_CRIT} 个严重问题，请立即处理！"
    elif [ "$COUNT_WARN" -gt 0 ]; then
        print_warn "存在 ${COUNT_WARN} 个警告，建议尽快排查。"
    else
        print_ok "系统状态良好，无告警。"
    fi
    echo ""
    echo -e "完整诊断报告已保存到: ${CYAN}${REPORT_FILE}${NC}"
    [ "$MD_SKIP" = false ] && echo "" >> "$REPORT_FILE"
    [ "$MD_SKIP" = false ] && echo "---" >> "$REPORT_FILE"
    [ "$MD_SKIP" = false ] && echo "**报告文件**: \`${REPORT_FILE}\`" >> "$REPORT_FILE"
}

# ===========================================================================
# 交互式菜单 - CPU四步定位法选择进程
# ===========================================================================
select_java_pid_for_cpu() {
    local pids; pids=$(get_java_pids)
    if [ -z "$pids" ]; then
        print_info "未检测到运行中的Java进程"
        return 1
    fi
    log ""
    log "${CYAN}请选择要诊断的Java进程:${NC}"
    local array=()
    local i=1
    for pid in $pids; do
        local name cpu_pct
        name=$(get_java_name "$pid")
        cpu_pct=$(ps -p "$pid" -o pcpu= 2>/dev/null | tr -d ' ')
        printf "  %d) PID=%-8s CPU=%-6s%% %s\n" "$i" "$pid" "$cpu_pct" "$name"
        array[i]=$pid
        ((i++))
    done
    printf "  0) 返回主菜单\n"
    log ""
    read -r -p "请输入序号 [0-$((i-1))]: " choice
    if [ "$choice" = "0" ] || [ -z "$choice" ]; then
        return 0
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        echo "无效输入: $choice"
        return 1
    fi
    if [ -n "${array[choice]}" ]; then
        local sel_pid="${array[choice]}"
        print_section "CPU四步定位法 - PID=$sel_pid"
        cpu_four_step_locate "$sel_pid"
        print_report_summary
    else
        print_fail "无效的选择"
    fi
}

# ===========================================================================
# 交互式菜单
# ===========================================================================
show_menu() {
    while true; do
        echo ""
        print_separator
        log "${WHITE}  Java服务系统诊断脚本 v${SCRIPT_VERSION}${NC}"
        print_separator
        echo -e "  ${CYAN}1)${NC} 全面诊断（执行所有检查）"
        echo -e "  ${CYAN}2)${NC} 仅系统级诊断（CPU/内存/磁盘/网络）"
        echo -e "  ${CYAN}3)${NC} 仅JVM诊断"
        echo -e "  ${CYAN}4)${NC} CPU四步定位法（选择Java进程后执行）"
        echo -e "  ${CYAN}5)${NC} 快速概览（仅load average和top）"
        echo -e "  ${CYAN}6)${NC} 工具检查与安装"
        echo -e "  ${CYAN}0)${NC} 退出"
        print_sub_separator
        read -r -p "请选择 [0-6]: " menu_choice
        case "$menu_choice" in
            1)
                init_report
                run_full_diagnosis
                print_report_summary
                ;;
            2)
                init_report
                check_and_install_tools
                run_system_diagnosis
                analyze_root_causes
                print_report_summary
                ;;
            3)
                init_report
                run_jvm_diagnosis
                analyze_root_causes
                print_report_summary
                ;;
            4)
                init_report
                select_java_pid_for_cpu
                ;;
            5)
                init_report
                run_quick_overview
                print_report_summary
                ;;
            6)
                init_report
                check_and_install_tools
                print_report_summary
                ;;
            0)
                log "${GREEN}感谢使用，再见！${NC}"
                break
                ;;
            *)
                echo -e "${RED}无效选择，请重新输入${NC}"
                ;;
        esac
        echo ""
        read -r -p "按回车键继续..." dummy
    done
}

# ===========================================================================
# 帮助信息
# ===========================================================================
show_help() {
    cat <<EOF
${SCRIPT_NAME} v${SCRIPT_VERSION}
Java服务全面系统诊断脚本

用法:
  ./${SCRIPT_NAME} [选项]

选项:
  --full        全面诊断（执行所有检查: 系统级 + JVM + 根因分析）
  --system      仅系统级诊断（CPU/内存/磁盘/网络）
  --jvm         仅JVM诊断（对所有Java进程执行深度诊断）
  --allow-jmap  启用jmap堆分析（有STW风险，生产环境慎用）
  --no-install  禁用自动安装缺失工具
  --help        显示此帮助信息

交互模式:
  不带参数运行将进入交互式菜单

权限:
  需要执行权限: chmod +x ${SCRIPT_NAME}
  部分检查需要root权限

JVM安全模式:
  默认开启安全模式，跳过jmap -histo:live（会触发Full GC）和jmap -dump（会暂停JVM）
  安全模式使用jcmd GC.class_histogram作为替代方案（影响更小）
  使用 --allow-jmap 可禁用安全模式，启用jmap完整分析

报告:
  诊断报告自动保存到: /tmp/diag_reports/diagnostic_report_YYYYMMDD_HHMMSS.md
  jstack输出保存到:   /tmp/diag_reports/jstack_<pid>_<timestamp>.txt

排查体系:
  系统级四维定位法 - CPU/内存/磁盘/网络逐层排查
  CPU高负载四步定位法 - 进程->线程->NID->代码行精准定位
  JVM内存与GC诊断 - 七种内存错误识别 + GC调优分析
  综合根因分析 - 自动汇总告警，推断根因并给出处理建议
EOF
}

# ===========================================================================
# 主函数
# ===========================================================================
main() {
    local mode=""
    # 解析命令行参数
    while [ $# -gt 0 ]; do
        case "$1" in
            --full)
                mode="full"
                ;;
            --system)
                mode="system"
                ;;
            --jvm)
                mode="jvm"
                ;;
            --no-install)
                AUTO_INSTALL=false
                ;;
            --allow-jmap)
                JVM_SAFE_MODE=false
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}未知参数: $1${NC}"
                show_help
                exit 1
                ;;
        esac
        shift
    done

    # 检查bash版本 (需要4.0+以支持关联数组)
    if [ "${BASH_VERSINFO[0]}" -lt 4 ] 2>/dev/null; then
        echo -e "${YELLOW}警告: 当前bash版本可能不支持关联数组(需要4.0+)，根因分析功能可能受限${NC}"
    fi

    # 根据模式执行
    if [ -z "$mode" ]; then
        # 交互式菜单
        show_menu
    else
        init_report
        case "$mode" in
            full)
                run_full_diagnosis
                ;;
            system)
                check_and_install_tools
                run_system_diagnosis
                analyze_root_causes
                ;;
            jvm)
                run_jvm_diagnosis
                analyze_root_causes
                ;;
        esac
        print_report_summary
    fi

    exit 0
}

# 执行主函数
main "$@"