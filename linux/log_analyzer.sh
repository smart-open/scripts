#!/bin/bash
# Log Analyzer Script - Analyze various log files for errors and patterns
# Author: System Admin
# Usage: ./log_analyzer.sh -l log_type [-f log_file] [-n lines]

VERSION="1.0"
LOG_TYPE=""
LOG_FILE=""
NUM_LINES=50
OUTPUT_FILE=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TOTAL_ERRORS=0
TOTAL_WARNINGS=0

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# grep -c 无匹配时输出 "0" 且退出码为 1，不能写 "|| echo 0"（会输出两行 0）
count_matches() {
    local count
    count=$(grep -c "$@" 2>/dev/null) || true
    echo "${count:-0}"
}

analyze_auth_log() {
    local log_file="$1"
    [ -z "$log_file" ] && log_file="/var/log/auth.log"
    [ ! -f "$log_file" ] && log_file="/var/log/secure"
    
    echo "=========================================="
    echo "Auth Log Analysis: $log_file"
    echo "=========================================="
    
    if [ ! -f "$log_file" ]; then
        echo -e "${RED}Log file not found: $log_file${NC}"
        return 1
    fi
    
    local failed_logins=$(grep -c "Failed password" "$log_file" 2>/dev/null); failed_logins=${failed_logins:-0}
    local accepted_logins=$(grep -c "Accepted password" "$log_file" 2>/dev/null); accepted_logins=${accepted_logins:-0}
    local sudo_commands=$(grep -c "sudo.*COMMAND=" "$log_file" 2>/dev/null); sudo_commands=${sudo_commands:-0}
    local root_logins=$(grep -c "session opened for user root" "$log_file" 2>/dev/null); root_logins=${root_logins:-0}
    local invalid_users=$(grep -c "Invalid user" "$log_file" 2>/dev/null); invalid_users=${invalid_users:-0}
    
    echo -e "${GREEN}Successful logins:${NC} $accepted_logins"
    echo -e "${YELLOW}Failed logins:${NC} $failed_logins"
    echo -e "${BLUE}Sudo commands executed:${NC} $sudo_commands"
    echo -e "${YELLOW}Root logins:${NC} $root_logins"
    echo -e "${RED}Invalid user attempts:${NC} $invalid_users"
    
    echo ""
    echo "Recent failed login attempts:"
    grep "Failed password" "$log_file" | tail -n "$NUM_LINES" | awk '{print $1, $2, $3, $11}'
    
    ((TOTAL_ERRORS += failed_logins + invalid_users))
    ((TOTAL_WARNINGS += root_logins))
}

analyze_nginx_log() {
    local log_file="$1"
    [ -z "$log_file" ] && log_file="/var/log/nginx/access.log"
    
    echo "=========================================="
    echo "Nginx Log Analysis: $log_file"
    echo "=========================================="
    
    if [ ! -f "$log_file" ]; then
        echo -e "${RED}Log file not found: $log_file${NC}"
        return 1
    fi
    
    local total_requests=$(wc -l < "$log_file")
    local errors_4xx=$(grep -E " 4[0-9]{2} " "$log_file" | wc -l)
    local errors_5xx=$(grep -E " 5[0-9]{2} " "$log_file" | wc -l)
    local unique_ips=$(awk '{print $1}' "$log_file" | sort -u | wc -l)
    
    echo -e "${GREEN}Total requests:${NC} $total_requests"
    echo -e "${YELLOW}4xx errors:${NC} $errors_4xx"
    echo -e "${RED}5xx errors:${NC} $errors_5xx"
    echo -e "${BLUE}Unique IPs:${NC} $unique_ips"
    
    echo ""
    echo "Top 10 requested URLs:"
    awk '{print $7}' "$log_file" | sort | uniq -c | sort -rn | head -10
    
    echo ""
    echo "Top 10 IP addresses:"
    awk '{print $1}' "$log_file" | sort | uniq -c | sort -rn | head -10
    
    echo ""
    echo "Top user agents:"
    awk -F'"' '{print $6}' "$log_file" | sort | uniq -c | sort -rn | head -5
    
    ((TOTAL_ERRORS += errors_5xx))
    ((TOTAL_WARNINGS += errors_4xx))
}

analyze_system_log() {
    local log_file="$1"
    [ -z "$log_file" ] && log_file="/var/log/syslog"
    [ ! -f "$log_file" ] && log_file="/var/log/messages"
    
    echo "=========================================="
    echo "System Log Analysis: $log_file"
    echo "=========================================="
    
    if [ ! -f "$log_file" ]; then
        echo -e "${RED}Log file not found: $log_file${NC}"
        return 1
    fi
    
    local total_errors=$(count_matches -i "error" "$log_file")
    local total_warnings=$(count_matches -i "warn" "$log_file")
    local total_critical=$(count_matches -i "critical\|fatal\|panic" "$log_file")
    local oom_kills=$(count_matches "oom-killer" "$log_file")
    
    echo -e "${RED}Critical errors:${NC} $total_critical"
    echo -e "${RED}Total errors:${NC} $total_errors"
    echo -e "${YELLOW}Total warnings:${NC} $total_warnings"
    echo -e "${YELLOW}OOM kills:${NC} $oom_kills"
    
    echo ""
    echo "Recent critical errors:"
    grep -i "critical\|fatal\|panic" "$log_file" | tail -n "$NUM_LINES"
    
    ((TOTAL_ERRORS += total_errors + total_critical + oom_kills))
    ((TOTAL_WARNINGS += total_warnings))
}

analyze_kernel_log() {
    local log_file="$1"
    [ -z "$log_file" ] && log_file="/var/log/kern.log"
    [ ! -f "$log_file" ] && log_file="/var/log/messages"
    
    echo "=========================================="
    echo "Kernel Log Analysis: $log_file"
    echo "=========================================="
    
    if [ ! -f "$log_file" ]; then
        echo -e "${RED}Log file not found: $log_file${NC}"
        return 1
    fi
    
    local oom=$(count_matches "Out of memory" "$log_file")
    local segfaults=$(count_matches "segfault" "$log_file")
    local i_errors=$(count_matches -i "I/O error\|disk error" "$log_file")
    local hw_errors=$(count_matches -i "hardware error\|machine check" "$log_file")
    
    echo -e "${RED}OOM events:${NC} $oom"
    echo -e "${RED}Segfaults:${NC} $segfaults"
    echo -e "${RED}I/O errors:${NC} $i_errors"
    echo -e "${YELLOW}Hardware errors:${NC} $hw_errors"
    
    echo ""
    echo "Recent kernel errors:"
    grep -i "error\|segfault\|oom" "$log_file" | tail -n "$NUM_LINES"
    
    ((TOTAL_ERRORS += oom + segfaults + i_errors + hw_errors))
}

analyze_dmesg() {
    echo "=========================================="
    echo "dmesg Analysis"
    echo "=========================================="
    
    local errors=$(dmesg 2>/dev/null | count_matches -i "error\|fail\|warn")
    local hw_err=$(dmesg 2>/dev/null | count_matches -i "hardware\|thermal\|machine check")
    
    echo -e "${YELLOW}Errors/Warnings:${NC} $errors"
    echo -e "${YELLOW}Hardware-related messages:${NC} $hw_err"
    
    echo ""
    echo "Recent error messages:"
    dmesg 2>/dev/null | grep -i "error\|warn\|fail" | tail -n "$NUM_LINES" | sed 's/\[[^]]*\] //'
    
    ((TOTAL_ERRORS += errors + hw_err))
}

analyze_custom_log() {
    local log_file="$1"
    local pattern="$2"
    
    echo "=========================================="
    echo "Custom Log Analysis: $log_file"
    echo "=========================================="
    
    if [ ! -f "$log_file" ]; then
        echo -e "${RED}Log file not found: $log_file${NC}"
        return 1
    fi
    
    local total_lines=$(wc -l < "$log_file")
    local total_errors=$(count_matches -i "error" "$log_file")
    
    echo "Total lines: $total_lines"
    echo "Total errors (case-insensitive): $total_errors"
    
    if [ -n "$pattern" ]; then
        echo ""
        echo "Pattern matches for '$pattern':"
        grep -ci "$pattern" "$log_file"
        grep -i "$pattern" "$log_file" | tail -5
    fi
    
    ((TOTAL_ERRORS += total_errors))
}

generate_html_report() {
    local html_file="$1"
    
    cat > "$html_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Log Analysis Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        .summary { background: #f5f5f5; padding: 15px; border-radius: 5px; }
        .error { color: #dc3545; font-weight: bold; }
        .warning { color: #ffc107; font-weight: bold; }
        .success { color: #28a745; font-weight: bold; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #4CAF50; color: white; }
    </style>
</head>
<body>
    <h1>Log Analysis Report</h1>
    <p><strong>Generated:</strong> $(date '+%Y-%m-%d %H:%M:%S')</p>
    <p><strong>Host:</strong> $(hostname)</p>
    
    <div class="summary">
        <h2>Summary</h2>
        <p class="error">Total Errors: $TOTAL_ERRORS</p>
        <p class="warning">Total Warnings: $TOTAL_WARNINGS</p>
    </div>
</body>
</html>
EOF
    
    log "HTML report generated: $html_file"
}

while getopts "l:f:n:o:h" opt; do
    case $opt in
        l) LOG_TYPE="$OPTARG" ;;
        f) LOG_FILE="$OPTARG" ;;
        n) NUM_LINES="$OPTARG" ;;
        o) OUTPUT_FILE="$OPTARG" ;;
        h) echo "Usage: $0 -l auth|nginx|system|kernel|dmesg|all [-f log_file] [-n lines] [-o output.html]"; exit 0 ;;
    esac
done

echo "Log Analyzer v$VERSION"
echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

case "$LOG_TYPE" in
    auth)
        analyze_auth_log "$LOG_FILE"
        ;;
    nginx|apache|httpd)
        analyze_nginx_log "$LOG_FILE"
        ;;
    system|syslog)
        analyze_system_log "$LOG_FILE"
        ;;
    kernel)
        analyze_kernel_log "$LOG_FILE"
        ;;
    dmesg)
        analyze_dmesg
        ;;
    all)
        analyze_auth_log
        echo ""
        analyze_system_log
        echo ""
        analyze_kernel_log
        echo ""
        analyze_dmesg
        echo ""
        analyze_nginx_log "$LOG_FILE"
        ;;
    *)
        if [ -n "$LOG_FILE" ]; then
            analyze_custom_log "$LOG_FILE"
        else
            echo "Please specify a log type with -l"
            echo "Available types: auth, nginx, system, kernel, dmesg, all"
            exit 1
        fi
        ;;
esac

echo ""
echo "=========================================="
echo "Analysis Summary"
echo "=========================================="
echo -e "${RED}Total Errors:${NC} $TOTAL_ERRORS"
echo -e "${YELLOW}Total Warnings:${NC} $TOTAL_WARNINGS"
echo "=========================================="

if [ -n "$OUTPUT_FILE" ]; then
    generate_html_report "$OUTPUT_FILE"
fi