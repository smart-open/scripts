#!/bin/bash
# Security Audit Script - System security scanner
# Author: System Admin
# Usage: ./security_audit.sh [-o report_file]

VERSION="1.0"
REPORT_FILE="/var/log/security_audit_report.log"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SEVERITY_HIGH=0
SEVERITY_MEDIUM=0
SEVERITY_LOW=0

add_finding() {
    local severity="$1"
    local category="$2"
    local message="$3"
    
    case $severity in
        HIGH)
            echo -e "${RED}[HIGH]${NC} [$category] $message" | tee -a "$REPORT_FILE"
            ((SEVERITY_HIGH++))
            ;;
        MEDIUM)
            echo -e "${YELLOW}[MEDIUM]${NC} [$category] $message" | tee -a "$REPORT_FILE"
            ((SEVERITY_MEDIUM++))
            ;;
        LOW)
            echo -e "${BLUE}[LOW]${NC} [$category] $message" | tee -a "$REPORT_FILE"
            ((SEVERITY_LOW++))
            ;;
    esac
}

check_open_ports() {
    echo "--- Checking Open Ports ---" | tee -a "$REPORT_FILE"
    
    local dangerous_ports="21 23 111 2049"
    local listening=""
    if command -v ss >/dev/null 2>&1; then
        listening=$(ss -tuln 2>/dev/null | awk '$1=="LISTEN" {print $5}' | sed 's/.*://' | sort -n | uniq)
    elif command -v netstat >/dev/null 2>&1; then
        listening=$(netstat -tuln 2>/dev/null | grep LISTEN | awk '{print $4}' | grep -E ':([0-9]+)$' | sed 's/.*://' | sort -n | uniq)
    else
        echo -e "${YELLOW}[SKIP]${NC} Neither ss nor netstat available" | tee -a "$REPORT_FILE"
        return
    fi

    for port in $dangerous_ports; do
        if echo "$listening" | grep -q "^$port$"; then
            add_finding HIGH "Ports" "Dangerous port $port is open"
        fi
    done

    local open_count=0
    [ -n "$listening" ] && open_count=$(echo "$listening" | wc -l)
    add_finding LOW "Ports" "$open_count ports are listening"
    
    echo -e "${GREEN}[OK]${NC} Port check completed" | tee -a "$REPORT_FILE"
}

check_suid_files() {
    echo "--- Checking SUID Files ---" | tee -a "$REPORT_FILE"
    
    local allowed_suid="/bin/ping /usr/bin/passwd /usr/bin/sudo"
    local suid_files=$(find / -type f -perm -4000 2>/dev/null | head -50)

    for file in $suid_files; do
        # -F 整词精确匹配，避免路径子串误放行
        if ! echo "$allowed_suid" | grep -qF "$file"; then
            add_finding MEDIUM "SUID" "SUID file found: $file"
        fi
    done

    local count=0
    [ -n "$suid_files" ] && count=$(echo "$suid_files" | wc -l)
    add_finding LOW "SUID" "Total SUID files: $count"
    
    echo -e "${GREEN}[OK]${NC} SUID file check completed" | tee -a "$REPORT_FILE"
}

check_weak_permissions() {
    echo "--- Checking Weak Permissions ---" | tee -a "$REPORT_FILE"
    
    if [ -w /etc/passwd ]; then
        add_finding HIGH "Permissions" "/etc/passwd is world-writable"
    fi
    
    if [ -w /etc/shadow ]; then
        add_finding HIGH "Permissions" "/etc/shadow is world-writable"
    fi
    
    if [ -d /tmp ] && [ ! -k /tmp ]; then
        add_finding MEDIUM "Permissions" "/tmp does not have sticky bit"
    fi
    
    if [ -f ~/.ssh/id_rsa ] && [ "$(stat -c %a ~/.ssh/id_rsa 2>/dev/null)" != "600" ]; then
        add_finding MEDIUM "Permissions" "SSH private key has weak permissions"
    fi
    
    echo -e "${GREEN}[OK]${NC} Permission check completed" | tee -a "$REPORT_FILE"
}

check_user_accounts() {
    echo "--- Checking User Accounts ---" | tee -a "$REPORT_FILE"
    
    local uid0_users=$(awk -F: '$3 == 0 {print $1}' /etc/passwd)
    local uid0_count=$(echo "$uid0_users" | wc -l)
    
    if [ "$uid0_count" -gt 1 ]; then
        add_finding HIGH "Accounts" "Multiple UID 0 users found: $uid0_users"
    fi
    
    local no_password_users=$(awk -F: '($2 == "" || $2 == "*") {print $1}' /etc/shadow 2>/dev/null)
    for user in $no_password_users; do
        add_finding HIGH "Accounts" "User '$user' has no password"
    done
    
    local sudoers=$(grep -v "^#" /etc/sudoers 2>/dev/null | grep -v "^$" | grep -v "^Defaults" | grep -v "^root" | wc -l)
    add_finding LOW "Accounts" "$sudoers users with sudo privileges"
    
    echo -e "${GREEN}[OK]${NC} User account check completed" | tee -a "$REPORT_FILE"
}

check_ssh_config() {
    echo "--- Checking SSH Configuration ---" | tee -a "$REPORT_FILE"
    
    if [ -f /etc/ssh/sshd_config ]; then
        if grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config; then
            add_finding MEDIUM "SSH" "Root login via SSH is permitted"
        fi
        
        if grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config; then
            add_finding LOW "SSH" "Password authentication is enabled (consider keys only)"
        fi
        
        if ! grep -q "^Protocol 2" /etc/ssh/sshd_config; then
            add_finding MEDIUM "SSH" "SSH protocol version is not enforced to 2"
        fi
    fi
    
    local ssh_key_users=0
    for home in $(awk -F: '$6 != "" {print $6}' /etc/passwd); do
        if [ -d "$home/.ssh" ] && [ -f "$home/.ssh/authorized_keys" ]; then
            ((ssh_key_users++))
        fi
    done
    add_finding LOW "SSH" "$ssh_key_users users with SSH keys"
    
    echo -e "${GREEN}[OK]${NC} SSH config check completed" | tee -a "$REPORT_FILE"
}

check_cron_jobs() {
    echo "--- Checking Cron Jobs ---" | tee -a "$REPORT_FILE"
    
    # -perm -0002 检查 other 可写（root 下 -writable 恒真会全部误报）
    local world_writable=$(find /etc/cron* -type f -perm -0002 2>/dev/null | wc -l)
    if [ "$world_writable" -gt 0 ]; then
        add_finding MEDIUM "Cron" "$world_writable world-writable cron files found"
    fi
    
    local root_crons=$(crontab -l 2>/dev/null | grep -v "^#" | grep -v "^$" | wc -l)
    add_finding LOW "Cron" "$root_crons crontab entries for root"
    
    echo -e "${GREEN}[OK]${NC} Cron job check completed" | tee -a "$REPORT_FILE"
}

check_kernel_hardening() {
    echo "--- Checking Kernel Hardening ---" | tee -a "$REPORT_FILE"
    
    if [ -f /proc/sys/net/ipv4/ip_forward ] && [ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)" = "1" ]; then
        add_finding LOW "Kernel" "IP forwarding is enabled"
    fi
    
    if [ -f /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts ] && [ "$(cat /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts 2>/dev/null)" != "1" ]; then
        add_finding LOW "Kernel" "ICMP broadcast response is not disabled"
    fi
    
    if [ -f /proc/sys/kernel/sysrq ] && [ "$(cat /proc/sys/kernel/sysrq 2>/dev/null)" != "0" ]; then
        add_finding LOW "Kernel" "SysRq is enabled"
    fi
    
    echo -e "${GREEN}[OK]${NC} Kernel hardening check completed" | tee -a "$REPORT_FILE"
}

check_updates() {
    echo "--- Checking Security Updates ---" | tee -a "$REPORT_FILE"
    
    if command -v apt-get >/dev/null 2>&1; then
        local updates=$(apt-get -s upgrade 2>/dev/null | grep -c "^Inst")
        add_finding LOW "Updates" "$updates packages available for upgrade"
    elif command -v yum >/dev/null 2>&1; then
        local updates=$(yum check-update 2>/dev/null | grep -c "^\w")
        add_finding LOW "Updates" "$updates packages available for upgrade"
    fi
    
    echo -e "${GREEN}[OK]${NC} Update check completed" | tee -a "$REPORT_FILE"
}

generate_summary() {
    echo "" | tee -a "$REPORT_FILE"
    echo "==========================================" | tee -a "$REPORT_FILE"
    echo "       SECURITY AUDIT SUMMARY" | tee -a "$REPORT_FILE"
    echo "==========================================" | tee -a "$REPORT_FILE"
    echo "Date: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$REPORT_FILE"
    echo "Host: $(hostname)" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
    echo "Findings by severity:" | tee -a "$REPORT_FILE"
    echo -e "${RED}HIGH:   $SEVERITY_HIGH${NC}" | tee -a "$REPORT_FILE"
    echo -e "${YELLOW}MEDIUM: $SEVERITY_MEDIUM${NC}" | tee -a "$REPORT_FILE"
    echo -e "${BLUE}LOW:    $SEVERITY_LOW${NC}" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
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
echo "       SECURITY AUDIT SCRIPT v$VERSION" | tee -a "$REPORT_FILE"
echo "==========================================" | tee -a "$REPORT_FILE"
echo "Starting audit: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

if [ "$(id -u)" -ne 0 ]; then
    add_finding LOW "General" "Running as non-root user - some checks may be limited"
fi

check_open_ports
check_suid_files
check_weak_permissions
check_user_accounts
check_ssh_config
check_cron_jobs
check_kernel_hardening
check_updates

generate_summary