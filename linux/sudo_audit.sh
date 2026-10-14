#!/bin/bash
# Sudo Audit Script - Audit sudo permissions and configurations
# Author: System Admin
# Usage: ./sudo_audit.sh [-o report]

VERSION="1.0"
REPORT_FILE="/var/log/sudo_audit_report.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FINDINGS=()

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$REPORT_FILE"
}

add_finding() {
    local severity="$1"
    local message="$2"
    
    case $severity in
        HIGH)
            echo -e "${RED}[HIGH]${NC} $message" | tee -a "$REPORT_FILE"
            ;;
        MEDIUM)
            echo -e "${YELLOW}[MEDIUM]${NC} $message" | tee -a "$REPORT_FILE"
            ;;
        LOW)
            echo -e "${BLUE}[LOW]${NC} $message" | tee -a "$REPORT_FILE"
            ;;
    esac
    FINDINGS+=("[$severity] $message")
}

check_sudoers_permissions() {
    log "Checking sudoers file permissions..."
    
    local sudoers_perms=$(stat -c "%a" /etc/sudoers 2>/dev/null)
    local sudoers_owner=$(stat -c "%U" /etc/sudoers 2>/dev/null)
    
    if [ "$sudoers_perms" != "440" ]; then
        add_finding HIGH "Insecure sudoers permissions: $sudoers_perms (should be 440)"
    fi
    
    if [ "$sudoers_owner" != "root" ]; then
        add_finding HIGH "Sudoers owned by: $sudoers_owner (should be root)"
    fi
    
    if [ -d /etc/sudoers.d ]; then
        # 进程替换避免 while read 子 shell 丢变量
        while read -r file; do
            add_finding MEDIUM "Insecure sudoers.d file permissions: $file"
        done < <(find /etc/sudoers.d -type f ! -perm 440 2>/dev/null)
    fi
}

list_sudo_users() {
    log "Listing users with sudo privileges..."
    
    echo "" | tee -a "$REPORT_FILE"
    echo "==========================================" | tee -a "$REPORT_FILE"
    echo "Users with Sudo Privileges" | tee -a "$REPORT_FILE"
    echo "==========================================" | tee -a "$REPORT_FILE"
    
    while read -r line; do
        if echo "$line" | grep -q "ALL=(ALL)"; then
            add_finding MEDIUM "User has full sudo access: $line"
        fi
    done < <(grep -v "^#" /etc/sudoers 2>/dev/null | grep -v "^$" | grep -E "^[a-zA-Z%]")

    if [ -d /etc/sudoers.d ]; then
        for file in /etc/sudoers.d/*; do
            if [ -f "$file" ]; then
                while read -r line; do
                    if echo "$line" | grep -q "ALL=(ALL)"; then
                        add_finding MEDIUM "User has full sudo access (from $file): $line"
                    fi
                done < <(grep -v "^#" "$file" 2>/dev/null | grep -v "^$" | grep -E "^[a-zA-Z%]")
            fi
        done
    fi
    
    local wheel_users=$(grep "^wheel:" /etc/group | cut -d: -f4)
    if [ -n "$wheel_users" ]; then
        echo -e "${GREEN}Members of wheel group:${NC} $wheel_users" | tee -a "$REPORT_FILE"
    fi
    
    local sudo_users=$(grep "^sudo:" /etc/group | cut -d: -f4)
    if [ -n "$sudo_users" ]; then
        echo -e "${GREEN}Members of sudo group:${NC} $sudo_users" | tee -a "$REPORT_FILE"
    fi
}

check_passwordless_sudo() {
    log "Checking for passwordless sudo..."
    
    local count=0
    while read -r line; do
        add_finding HIGH "Passwordless sudo configured: $line"
        count=$((count + 1))
    done < <(grep -v "^#" /etc/sudoers 2>/dev/null | grep "NOPASSWD")

    if [ -d /etc/sudoers.d ]; then
        for file in /etc/sudoers.d/*; do
            if [ -f "$file" ]; then
                while read -r line; do
                    add_finding HIGH "Passwordless sudo configured in $file: $line"
                    count=$((count + 1))
                done < <(grep -v "^#" "$file" 2>/dev/null | grep "NOPASSWD")
            fi
        done
    fi
    
    if [ $count -eq 0 ]; then
        log "[OK] No passwordless sudo configured"
    fi
}

check_command_restrictions() {
    log "Checking sudo command restrictions..."
    
    local full_access=0
    local restricted=0

    while read -r line; do
        # 覆盖 ALL=(ALL) ALL 与 ALL=(ALL:ALL) ALL 两种常见写法
        if echo "$line" | grep -qE "ALL=\(ALL(:ALL)?\) ALL"; then
            full_access=$((full_access + 1))
        elif echo "$line" | grep -q "ALL=(ALL)"; then
            restricted=$((restricted + 1))
        fi
    done < <(grep -v "^#" /etc/sudoers 2>/dev/null | grep -v "^$" | grep -E "^[a-zA-Z%]")
    
    echo -e "${GREEN}Full access users:${NC} $full_access" | tee -a "$REPORT_FILE"
    echo -e "${GREEN}Restricted command users:${NC} $restricted" | tee -a "$REPORT_FILE"
}

check_sudoers_backup() {
    log "Checking for sudoers backups..."
    
    local backup_files=$(find /etc -maxdepth 2 -name "*sudoers*" 2>/dev/null | grep -v "^/etc/sudoers$" | grep -v "^/etc/sudoers.d")
    local count=0
    [ -n "$backup_files" ] && count=$(echo "$backup_files" | wc -l)

    if [ $count -gt 0 ]; then
        echo -e "${YELLOW}Found sudoers backup files:${NC}" | tee -a "$REPORT_FILE"
        echo "$backup_files" | tee -a "$REPORT_FILE"
    fi
}

check_env_reset() {
    log "Checking environment reset configuration..."

    # Defaults 可能放在 /etc/sudoers.d/ 下（发行版默认如此），需合并检查
    local sudoers_all="/etc/sudoers"
    [ -d /etc/sudoers.d ] && sudoers_all="/etc/sudoers /etc/sudoers.d/*"

    if grep -s -h "^Defaults.*env_reset" $sudoers_all >/dev/null 2>&1; then
        log "[OK] env_reset is configured"
    else
        add_finding MEDIUM "env_reset is NOT configured (security risk)"
    fi
    
    if grep -s -h "^Defaults.*env_keep" $sudoers_all >/dev/null 2>&1; then
        local kept=$(grep -s -h "^Defaults.*env_keep" $sudoers_all | head -1)
        add_finding LOW "Environment variables kept: $kept"
    fi
}

check_secure_path() {
    log "Checking secure_path configuration..."
    
    local sudoers_all="/etc/sudoers"
    [ -d /etc/sudoers.d ] && sudoers_all="/etc/sudoers /etc/sudoers.d/*"

    if grep -s -h "^Defaults.*secure_path" $sudoers_all >/dev/null 2>&1; then
        local path=$(grep -s -h "^Defaults.*secure_path" $sudoers_all | head -1 | cut -d'"' -f2)
        log "[OK] secure_path is configured: $path"
    else
        add_finding MEDIUM "secure_path is NOT configured (security risk)"
    fi
}

audit_sudo_logs() {
    log "Auditing sudo logs..."
    
    local auth_log=""
    if [ -f /var/log/auth.log ]; then
        auth_log="/var/log/auth.log"
    elif [ -f /var/log/secure ]; then
        auth_log="/var/log/secure"
    fi
    
    if [ -n "$auth_log" ]; then
        local sudo_commands=$(grep "sudo" "$auth_log" 2>/dev/null | grep "COMMAND=" | tail -20)
        local count=0
        [ -n "$sudo_commands" ] && count=$(echo "$sudo_commands" | wc -l)
        
        echo "" | tee -a "$REPORT_FILE"
        echo "==========================================" | tee -a "$REPORT_FILE"
        echo "Recent Sudo Commands (last $count)" | tee -a "$REPORT_FILE"
        echo "==========================================" | tee -a "$REPORT_FILE"
        echo "$sudo_commands" | tee -a "$REPORT_FILE"
        
        local failed=$(grep "sudo" "$auth_log" 2>/dev/null | grep "authentication failure" | wc -l)
        if [ $failed -gt 0 ]; then
            add_finding MEDIUM "Found $failed sudo authentication failures in logs"
        fi
    else
        log "[INFO] No auth log file found"
    fi
}

check_visudo() {
    log "Checking visudo availability..."
    
    if command -v visudo >/dev/null 2>&1; then
        log "[OK] visudo is available"
    else
        add_finding MEDIUM "visudo is NOT available - direct edits to sudoers are risky"
    fi
}

generate_report() {
    echo "" | tee -a "$REPORT_FILE"
    echo "==========================================" | tee -a "$REPORT_FILE"
    echo "       SUDO AUDIT SUMMARY" | tee -a "$REPORT_FILE"
    echo "==========================================" | tee -a "$REPORT_FILE"
    echo "Date: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$REPORT_FILE"
    echo "Host: $(hostname)" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
    echo "Total findings: ${#FINDINGS[@]}" | tee -a "$REPORT_FILE"
    echo "Report saved to: $REPORT_FILE" | tee -a "$REPORT_FILE"
    echo "==========================================" | tee -a "$REPORT_FILE"
}

while getopts "o:h" opt; do
    case $opt in
        o) REPORT_FILE="$OPTARG" ;;
        h) echo "Usage: $0 [-o report_file]"; exit 0 ;;
    esac
done

echo "==========================================" | tee "$REPORT_FILE"
echo "       SUDO AUDIT SCRIPT v$VERSION" | tee -a "$REPORT_FILE"
echo "==========================================" | tee -a "$REPORT_FILE"
echo "Starting audit: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

if [ "$(id -u)" -ne 0 ]; then
    add_finding LOW "Running as non-root user - some checks may be limited"
fi

check_sudoers_permissions
list_sudo_users
check_passwordless_sudo
check_command_restrictions
check_sudoers_backup
check_env_reset
check_secure_path
audit_sudo_logs
check_visudo

generate_report