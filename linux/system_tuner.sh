#!/bin/bash
# System Tuner Script - Kernel and system performance optimization
# Author: System Admin
# Usage: ./system_tuner.sh -p profile -a apply|check|restore

VERSION="1.0"
PROFILE="server"
ACTION="check"
BACKUP_DIR="/var/backups/sysctl"
LOG_FILE="/var/log/system_tuner.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

APPLIED=0
SKIPPED=0
FAILED=0

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

backup_current_config() {
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_file="${BACKUP_DIR}/sysctl_${timestamp}.conf"
    
    log "Backing up current sysctl configuration..."
    mkdir -p "$BACKUP_DIR"
    sysctl -a > "$backup_file" 2>/dev/null
    log "Backup saved: $backup_file"
    echo "$backup_file" > "${BACKUP_DIR}/last_backup.txt"
}

apply_network_tuning() {
    log "Applying network tuning settings..."
    
    local settings=(
        "net.core.somaxconn=65535"
        "net.core.netdev_max_backlog=32768"
        "net.core.rmem_default=262144"
        "net.core.wmem_default=262144"
        "net.core.rmem_max=16777216"
        "net.core.wmem_max=16777216"
        "net.ipv4.tcp_syncookies=1"
        "net.ipv4.tcp_tw_reuse=1"
        "net.ipv4.tcp_fin_timeout=30"
        "net.ipv4.tcp_keepalive_time=1200"
        "net.ipv4.tcp_max_syn_backlog=8192"
        "net.ipv4.ip_forward=0"
        "net.ipv4.icmp_echo_ignore_broadcasts=1"
        "net.ipv4.icmp_ignore_bogus_error_responses=1"
    )
    
    for setting in "${settings[@]}"; do
        local key=${setting%%=*}
        local value=${setting#*=}
        
        # 检查参数是否存在（兼容不同内核版本）
        if ! sysctl -n "$key" >/dev/null 2>&1; then
            log "  [SKIP] $key not supported on this kernel"
            ((SKIPPED++))
            continue
        fi
        
        if sysctl -w "$key=$value" >/dev/null 2>&1; then
            log "  [OK] $key = $value"
            ((APPLIED++))
        else
            log "  [FAIL] Could not set $key = $value"
            ((FAILED++))
        fi
    done
}

apply_memory_tuning() {
    log "Applying memory tuning settings..."
    
    local total_memory=$(free -m | awk '/Mem:/ {print $2}')
    local settings=(
        "vm.swappiness=10"
        "vm.dirty_ratio=15"
        "vm.dirty_background_ratio=5"
        "vm.overcommit_memory=1"
        "vm.vfs_cache_pressure=50"
        "vm.min_free_kbytes=65536"
    )
    
    for setting in "${settings[@]}"; do
        local key=${setting%%=*}
        local value=${setting#*=}
        
        if sysctl -w "$key=$value" >/dev/null 2>&1; then
            log "  [OK] $key = $value"
            ((APPLIED++))
        else
            log "  [FAIL] Could not set $key = $value"
            ((FAILED++))
        fi
    done
}

apply_file_system_tuning() {
    log "Applying file system tuning settings..."
    
    local settings=(
        "fs.file-max=65535"
        "fs.inotify.max_user_watches=131072"
        "fs.inotify.max_user_instances=256"
    )
    
    for setting in "${settings[@]}"; do
        local key=${setting%%=*}
        local value=${setting#*=}
        
        if sysctl -w "$key=$value" >/dev/null 2>&1; then
            log "  [OK] $key = $value"
            ((APPLIED++))
        else
            log "  [FAIL] Could not set $key = $value"
            ((FAILED++))
        fi
    done
}

apply_kernel_security() {
    log "Applying kernel security settings..."
    
    local settings=(
        "kernel.sysrq=0"
        "kernel.core_uses_pid=1"
        "kernel.kptr_restrict=2"
        "kernel.dmesg_restrict=1"
    )
    
    for setting in "${settings[@]}"; do
        local key=${setting%%=*}
        local value=${setting#*=}
        
        if sysctl -w "$key=$value" >/dev/null 2>&1; then
            log "  [OK] $key = $value"
            ((APPLIED++))
        else
            log "  [FAIL] Could not set $key = $value"
            ((FAILED++))
        fi
    done
}

apply_vm_tuning() {
    log "Applying VM-specific tuning..."
    
    local settings=(
        "vm.dirty_expire_centisecs=3000"
        "vm.dirty_writeback_centisecs=500"
    )
    
    for setting in "${settings[@]}"; do
        local key=${setting%%=*}
        local value=${setting#*=}
        
        if sysctl -w "$key=$value" >/dev/null 2>&1; then
            log "  [OK] $key = $value"
            ((APPLIED++))
        else
            log "  [FAIL] Could not set $key = $value"
            ((FAILED++))
        fi
    done
}

apply_desktop_profile() {
    log "Applying desktop profile settings..."
    
    local settings=(
        "vm.swappiness=1"
        "vm.dirty_ratio=20"
        "vm.dirty_background_ratio=10"
    )
    
    for setting in "${settings[@]}"; do
        local key=${setting%%=*}
        local value=${setting#*=}
        
        if sysctl -w "$key=$value" >/dev/null 2>&1; then
            log "  [OK] $key = $value"
            ((APPLIED++))
        else
            log "  [FAIL] Could not set $key = $value"
            ((FAILED++))
        fi
    done
}

apply_database_profile() {
    log "Applying database profile settings..."
    
    local total_memory=$(free -m | awk '/Mem:/ {print $2}')
    
    local settings=(
        "vm.swappiness=1"
        "vm.dirty_ratio=80"
        "vm.dirty_background_ratio=5"
        "vm.overcommit_memory=2"
        "vm.overcommit_ratio=95"
    )
    
    for setting in "${settings[@]}"; do
        local key=${setting%%=*}
        local value=${setting#*=}
        
        if sysctl -w "$key=$value" >/dev/null 2>&1; then
            log "  [OK] $key = $value"
            ((APPLIED++))
        else
            log "  [FAIL] Could not set $key = $value"
            ((FAILED++))
        fi
    done
}

save_sysctl_config() {
    local config_file="/etc/sysctl.d/99-custom-tuning.conf"
    log "Saving configuration to: $config_file"

    # 从系统当前值生成持久化配置，确保与刚应用的 profile 一致（而非硬编码 server 默认值）
    local keys=(
        net.core.somaxconn net.core.netdev_max_backlog net.core.rmem_default
        net.core.wmem_default net.core.rmem_max net.core.wmem_max
        net.ipv4.tcp_syncookies net.ipv4.tcp_tw_reuse net.ipv4.tcp_fin_timeout
        net.ipv4.tcp_keepalive_time net.ipv4.tcp_max_syn_backlog net.ipv4.ip_forward
        vm.swappiness vm.dirty_ratio vm.dirty_background_ratio
        vm.overcommit_memory vm.vfs_cache_pressure
        fs.file-max fs.inotify.max_user_watches kernel.sysrq kernel.core_uses_pid
    )

    {
        echo "# Custom system tuning configuration"
        echo "# Generated by system_tuner.sh v$VERSION (profile: $PROFILE)"
        echo "# Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        local key value
        for key in "${keys[@]}"; do
            value=$(sysctl -n "$key" 2>/dev/null)
            [ -n "$value" ] && echo "$key = $value"
        done
    } > "$config_file"

    log "Configuration saved"
}

check_system() {
    echo "=========================================="
    echo "System Information"
    echo "=========================================="
    echo "Hostname: $(hostname)"
    echo "Kernel: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo ""
    echo "CPU cores: $(nproc)"
    echo "Total Memory: $(free -h | awk '/Mem:/ {print $2}')"
    echo ""
    
    echo "=========================================="
    echo "Current Key Settings"
    echo "=========================================="
    
    local keys=(
        "vm.swappiness"
        "vm.dirty_ratio"
        "net.core.somaxconn"
        "fs.file-max"
        "kernel.sysrq"
    )
    
    for key in "${keys[@]}"; do
        local value=$(sysctl -n "$key" 2>/dev/null)
        if [ -n "$value" ]; then
            printf "%-30s = %s\n" "$key" "$value"
        fi
    done
}

restore_backup() {
    local backup_file=""
    
    if [ -f "${BACKUP_DIR}/last_backup.txt" ]; then
        backup_file=$(cat "${BACKUP_DIR}/last_backup.txt")
    fi
    
    if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
        log "[ERROR] No backup file found"
        return 1
    fi
    
    log "Restoring from backup: $backup_file"
    
    if sysctl -p "$backup_file" >/dev/null 2>&1; then
        log "Backup restored successfully"
        return 0
    else
        log "[ERROR] Restore failed"
        return 1
    fi
}

list_backups() {
    echo "=========================================="
    echo "Available Backups"
    echo "=========================================="
    find "$BACKUP_DIR" -name "sysctl_*.conf" -printf "%TY-%Tm-%Td %TH:%TM %f\n" | sort -r
    echo "=========================================="
}

while getopts "p:a:slrh" opt; do
    case $opt in
        p) PROFILE="$OPTARG" ;;
        a) ACTION="$OPTARG" ;;
        s) save_sysctl_config; exit 0 ;;
        l) list_backups; exit 0 ;;
        r) restore_backup; exit $? ;;
        h) echo "Usage: $0 -p desktop|server|database -a apply|check|restore [-s save] [-l list]"; exit 0 ;;
        \?) echo "Unknown option: -$OPTARG. Use -h for help."; exit 2 ;;
    esac
done

echo "=========================================="
echo "System Tuner Script v$VERSION"
echo "=========================================="
echo "Profile: $PROFILE"
echo "Action: $ACTION"
echo "=========================================="
echo ""

case "$ACTION" in
    check)
        check_system
        ;;
    apply)
        backup_current_config
        
        apply_network_tuning
        apply_memory_tuning
        apply_file_system_tuning
        apply_kernel_security
        apply_vm_tuning
        
        case "$PROFILE" in
            desktop) apply_desktop_profile ;;
            database) apply_database_profile ;;
        esac
        
        save_sysctl_config
        
        echo ""
        echo "=========================================="
        echo "Tuning Summary"
        echo "=========================================="
        echo "Applied: $APPLIED settings"
        echo "Failed:  $FAILED settings"
        echo "=========================================="
        ;;
    restore)
        restore_backup
        ;;
    *)
        echo "Unknown action: $ACTION"
        echo "Use -a apply|check|restore"
        exit 1
        ;;
esac