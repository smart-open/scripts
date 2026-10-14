#!/bin/bash
# System Monitor Script - Real-time monitoring with alerts
# Author: System Admin
# Usage: ./system_monitor.sh [-i interval] [-a alert]

VERSION="1.0"
INTERVAL=5
ALERT_THRESHOLD=80
ALERT_EMAIL=""
LOG_FILE="/var/log/system_monitor.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

alert() {
    local msg="$1"
    log "[ALERT] $msg"
    if [ -n "$ALERT_EMAIL" ]; then
        if command -v mail >/dev/null 2>&1; then
            echo "$msg" | mail -s "System Alert: $msg" "$ALERT_EMAIL"
        else
            log "[WARNING] mail command not available, alert not sent: $msg"
        fi
    fi
}

get_cpu_usage() {
    # /proc/stat 是开机以来的累计值，需两次采样取差值才是"当前使用率"
    local stat1 stat2
    stat1=$(awk '/^cpu / {print $2+$3+$4, $2+$4}' /proc/stat)
    sleep 1
    stat2=$(awk '/^cpu / {print $2+$3+$4, $2+$4}' /proc/stat)
    awk -v s1="$stat1" -v s2="$stat2" '{
        split(s1, a, " "); split(s2, b, " ")
        d_total = b[1] - a[1]; d_busy = b[2] - a[2]
        if (d_total <= 0) { print 0 } else { printf "%d", d_busy * 100 / d_total }
    }'
}

get_mem_usage() {
    # 优先使用 MemAvailable（内核3.14+），语义更准确且不受 free 输出格式影响
    local meminfo="/proc/meminfo"
    if grep -q "^MemAvailable:" "$meminfo" 2>/dev/null; then
        awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END {printf "%d", (t-a)*100/t}' "$meminfo"
    else
        free | awk '/Mem:/ {print int($3/$2 * 100)}'
    fi
}

get_disk_usage() {
    df -P / | awk '/\// {print $5}' | tr -d '%'
}

get_swap_usage() {
    # 检查swap是否存在，避免除零错误
    local swap_total=$(free | awk '/Swap:/ {print $2}')
    if [ -z "$swap_total" ] || [ "$swap_total" -eq 0 ]; then
        echo 0
    else
        free | awk '/Swap:/ {print int($3/$2 * 100)}'
    fi
}

get_load_avg() {
    cat /proc/loadavg | awk '{print $1, $2, $3}'
}

get_top_processes() {
    ps aux --sort=-%cpu | head -6 | tail -5
}

check_alerts() {
    local cpu=$(get_cpu_usage)
    local mem=$(get_mem_usage)
    local disk=$(get_disk_usage)
    
    # 确保变量有默认值，避免比较错误
    cpu=${cpu:-0}
    mem=${mem:-0}
    disk=${disk:-0}
    
    [ "$cpu" -gt "$ALERT_THRESHOLD" ] && alert "High CPU usage: ${cpu}%"
    [ "$mem" -gt "$ALERT_THRESHOLD" ] && alert "High Memory usage: ${mem}%"
    [ "$disk" -gt "$ALERT_THRESHOLD" ] && alert "High Disk usage: ${disk}%"
}

show_dashboard() {
    clear
    echo "=================================================="
    echo "       System Monitor v$VERSION"
    echo "=================================================="
    echo "Interval: ${INTERVAL}s | Alert: ${ALERT_THRESHOLD}%"
    echo "=================================================="
    echo ""
    
    local cpu=$(get_cpu_usage)
    local mem=$(get_mem_usage)
    local disk=$(get_disk_usage)
    local swap=$(get_swap_usage)
    local load=$(get_load_avg)
    
    # 默认值保护
    cpu=${cpu:-0}
    mem=${mem:-0}
    disk=${disk:-0}
    swap=${swap:-0}
    
    echo "--- CPU Usage ---"
    [ "$cpu" -ge "$ALERT_THRESHOLD" ] && echo -e "CPU: ${RED}${cpu}%${NC}" || echo -e "CPU: ${GREEN}${cpu}%${NC}"
    
    echo ""
    echo "--- Memory Usage ---"
    [ "$mem" -ge "$ALERT_THRESHOLD" ] && echo -e "RAM: ${RED}${mem}%${NC}" || echo -e "RAM: ${GREEN}${mem}%${NC}"
    [ "$swap" -ge "$ALERT_THRESHOLD" ] && echo -e "Swap: ${RED}${swap}%${NC}" || echo -e "Swap: ${GREEN}${swap}%${NC}"
    
    echo ""
    echo "--- Disk Usage (/) ---"
    [ "$disk" -ge "$ALERT_THRESHOLD" ] && echo -e "Disk: ${RED}${disk}%${NC}" || echo -e "Disk: ${GREEN}${disk}%${NC}"
    
    echo ""
    echo "--- Load Average ---"
    echo "1min: $(echo $load | awk '{print $1}') | 5min: $(echo $load | awk '{print $2}') | 15min: $(echo $load | awk '{print $3}')"
    
    echo ""
    echo "--- Top 5 CPU Processes ---"
    get_top_processes
    
    echo ""
    echo "=================================================="
    echo "Press Ctrl+C to exit"
}

while getopts "i:a:h" opt; do
    case $opt in
        i) INTERVAL="$OPTARG" ;;
        a) ALERT_THRESHOLD="$OPTARG" ;;
        h) echo "Usage: $0 [-i interval] [-a alert_threshold]"; exit 0 ;;
    esac
done

echo "Starting System Monitor..."
log "System Monitor started - interval: ${INTERVAL}s, threshold: ${ALERT_THRESHOLD}%"

trap "echo 'Exiting...'; log 'System Monitor stopped'; exit" SIGINT SIGTERM

while true; do
    show_dashboard
    check_alerts
    sleep "$INTERVAL"
done