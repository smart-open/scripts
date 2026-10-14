#!/bin/bash
# Process Watchdog - Monitor and restart critical processes
# Author: System Admin
# Usage: ./process_watchdog.sh -c process_name -c process2 [-e email]

VERSION="1.0"
CONFIG_FILE="/etc/watchdog.conf"
LOG_FILE="/var/log/watchdog.log"
CHECK_INTERVAL=30
ALERT_EMAIL=""
declare -a PROCESSES

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
            echo "$msg" | mail -s "Watchdog Alert: $msg" "$ALERT_EMAIL"
        else
            log "[WARNING] mail command not available, alert not sent: $msg"
        fi
    fi
}

is_process_running() {
    local proc="$1"
    # pgrep -f 会匹配到 watchdog 自身命令行中的进程名，需排除自身 PID
    if pgrep -f "$proc" 2>/dev/null | grep -qv "^$$\$"; then
        return 0
    fi
    pidof "$proc" > /dev/null 2>&1 && return 0
    systemctl is-active --quiet "$proc" 2>/dev/null && return 0
    return 1
}

restart_process() {
    local proc="$1"
    log "Attempting to restart: $proc"
    
    # 方式1: systemctl
    if systemctl list-unit-files 2>/dev/null | grep -q "$proc"; then
        systemctl restart "$proc" 2>/dev/null
        if [ $? -eq 0 ]; then
            log "Successfully restarted via systemctl: $proc"
            return 0
        fi
    fi
    
    # 方式2: service命令
    if command -v service >/dev/null 2>&1; then
        service "$proc" restart 2>/dev/null
        if [ $? -eq 0 ]; then
            log "Successfully restarted via service: $proc"
            return 0
        fi
    fi
    
    # 方式3: 直接启动（kill 残留旧实例时排除自身，避免误杀 watchdog）
    for pid in $(pgrep -f "$proc" 2>/dev/null); do
        [ "$pid" != "$$" ] && kill "$pid" 2>/dev/null
    done
    sleep 1
    log "[WARNING] No service unit found, starting '$proc' directly (not supervised)"
    nohup "$proc" > /dev/null 2>&1 &
    sleep 2
    
    if is_process_running "$proc"; then
        log "Successfully started: $proc"
        return 0
    else
        alert "Failed to restart: $proc"
        return 1
    fi
}

monitor_processes() {
    for proc in "${PROCESSES[@]}"; do
        if is_process_running "$proc"; then
            log "[OK] $proc is running"
        else
            alert "[DOWN] $proc is NOT running!"
            restart_process "$proc"
        fi
    done
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        while IFS= read -r line; do
            [[ -z "$line" || "$line" =~ ^# ]] && continue
            if [[ "$line" =~ ^process= ]]; then
                PROCESSES+=("${line#*=}")
            elif [[ "$line" =~ ^interval= ]]; then
                CHECK_INTERVAL="${line#*=}"
            elif [[ "$line" =~ ^email= ]]; then
                ALERT_EMAIL="${line#*=}"
            fi
        done < "$CONFIG_FILE"
    fi
}

show_status() {
    echo "=========================================="
    echo "       Process Watchdog v$VERSION"
    echo "=========================================="
    echo "Check Interval: ${CHECK_INTERVAL}s"
    [ -n "$ALERT_EMAIL" ] && echo "Alert Email: $ALERT_EMAIL"
    echo "Monitored Processes:"
    for proc in "${PROCESSES[@]}"; do
        if is_process_running "$proc"; then
            echo -e "  ${GREEN}[RUNNING]${NC} $proc"
        else
            echo -e "  ${RED}[DOWN]${NC} $proc"
        fi
    done
    echo "=========================================="
}

SHOW_STATUS=false

while getopts "c:i:e:lsh" opt; do
    case $opt in
        c) PROCESSES+=("$OPTARG") ;;
        i) CHECK_INTERVAL="$OPTARG" ;;
        e) ALERT_EMAIL="$OPTARG" ;;
        l) load_config ;;
        s) SHOW_STATUS=true ;;
        h) echo "Usage: $0 [-c process] [-i interval] [-e email] [-l load_config] [-s status]"; exit 0 ;;
        \?) echo "Unknown option: -$OPTARG. Use -h for help."; exit 2 ;;
    esac
done

# -s 需在所有参数解析完（含 -l 加载配置）后再执行，否则状态为空
if [ "$SHOW_STATUS" = true ]; then
    show_status
    exit 0
fi

if [ ${#PROCESSES[@]} -eq 0 ]; then
    echo "No processes to monitor. Use -c or -l to load config."
    exit 1
fi

log "Watchdog started - monitoring: ${PROCESSES[*]}"
trap "log 'Watchdog stopped'; exit" SIGINT SIGTERM

while true; do
    monitor_processes
    sleep "$CHECK_INTERVAL"
done