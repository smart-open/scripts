#!/bin/bash
# Service Deployment Script - One-click deployment with rollback support
# Author: System Admin
# Usage: ./service_deploy.sh -n service_name -v version -a deploy|rollback

VERSION="1.0"
SERVICE_NAME=""
SERVICE_VERSION=""
ACTION=""
BACKUP_DIR="/var/backups/deployments"
DEPLOY_DIR="/opt"
ROLLBACK_VERSION=""
LOG_FILE="/var/log/deployment.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_service_exists() {
    if [ ! -d "$DEPLOY_DIR/$SERVICE_NAME" ]; then
        log "[INFO] Service directory does not exist, will create"
        return 1
    fi
    return 0
}

backup_current_version() {
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_file="${BACKUP_DIR}/${SERVICE_NAME}_${timestamp}.tar.gz"
    
    log "Backing up current version to: $backup_file"
    mkdir -p "$BACKUP_DIR"
    
    if check_service_exists; then
        tar -czf "$backup_file" -C "$DEPLOY_DIR" "$SERVICE_NAME"
        
        if [ $? -eq 0 ]; then
            local size=$(du -h "$backup_file" | cut -f1)
            log "Backup completed: $backup_file ($size)"
            echo "$backup_file" > "${BACKUP_DIR}/${SERVICE_NAME}_last_backup.txt"
            return 0
        else
            log "[ERROR] Backup failed"
            return 1
        fi
    else
        log "[INFO] No existing version to backup"
        return 0
    fi
}

download_package() {
    local package_url="$1"
    local package_file="${BACKUP_DIR}/${SERVICE_NAME}_${SERVICE_VERSION}.tar.gz"
    
    log "Downloading package from: $package_url"
    
    local rc=1
    if command -v wget >/dev/null 2>&1; then
        wget -q --timeout=60 "$package_url" -O "$package_file"
        rc=$?
    elif command -v curl >/dev/null 2>&1; then
        # -f: HTTP 4xx/5xx 时返回非 0，避免把错误页当包保存
        curl -fsSL --max-time 120 "$package_url" -o "$package_file"
        rc=$?
    else
        log "[ERROR] Neither wget nor curl available"
        return 1
    fi

    if [ $rc -eq 0 ] && [ -f "$package_file" ]; then
        log "Download completed: $package_file"
        echo "$package_file"
        return 0
    else
        rm -f "$package_file"
        log "[ERROR] Download failed"
        return 1
    fi
}

extract_package() {
    local package_file="$1"
    local temp_dir=$(mktemp -d)
    
    log "Extracting package: $package_file"
    
    if tar -xzf "$package_file" -C "$temp_dir"; then
        log "Extracted to: $temp_dir"
        echo "$temp_dir"
        return 0
    else
        log "[ERROR] Extraction failed"
        rm -rf "$temp_dir"
        return 1
    fi
}

stop_service() {
    log "Stopping service: $SERVICE_NAME"
    
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl stop "$SERVICE_NAME"
        sleep 3
        if ! systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
            log "Service stopped successfully"
            return 0
        fi
    fi
    
    if pgrep -f "$SERVICE_NAME" >/dev/null 2>&1; then
        pkill -f "$SERVICE_NAME"
        sleep 2
    fi
    
    log "Service stopped (or not running)"
    return 0
}

start_service() {
    log "Starting service: $SERVICE_NAME"
    
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        log "Service is already running"
        return 0
    fi
    
    if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
        systemctl start "$SERVICE_NAME"
        sleep 3
        
        if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
            log "Service started successfully"
            return 0
        fi
    fi
    
    if [ -f "$DEPLOY_DIR/$SERVICE_NAME/start.sh" ]; then
        cd "$DEPLOY_DIR/$SERVICE_NAME" && bash start.sh &
        sleep 3
        
        if pgrep -f "$SERVICE_NAME" >/dev/null 2>&1; then
            log "Service started successfully via start.sh"
            return 0
        fi
    fi
    
    log "[WARNING] Service may not have started properly"
    return 1
}

deploy_new_version() {
    local source_dir="$1"
    
    log "Deploying new version: $SERVICE_VERSION"
    
    mkdir -p "$DEPLOY_DIR/$SERVICE_NAME"
    
    if cp -r "$source_dir"/* "$DEPLOY_DIR/$SERVICE_NAME/"; then
        log "Files copied successfully"
        
        if [ -d "$DEPLOY_DIR/$SERVICE_NAME" ]; then
            echo "$SERVICE_VERSION" > "$DEPLOY_DIR/$SERVICE_NAME/VERSION"
            log "Version file created: $SERVICE_VERSION"
        fi
        
        return 0
    else
        log "[ERROR] File copy failed"
        return 1
    fi
}

health_check() {
    local health_url="$1"
    local max_retries=5
    local retry_delay=3
    
    log "Running health check: $health_url"
    
    for ((i=1; i<=max_retries; i++)); do
        if [ -n "$health_url" ]; then
            # 精确匹配 200，避免 1200/2001/5200 误判为通过
            if curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$health_url" | grep -q "^200$"; then
                log "Health check passed (attempt $i/$max_retries)"
                return 0
            fi
        else
            if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
                log "Health check passed: service is running"
                return 0
            fi
            
            if pgrep -f "$SERVICE_NAME" >/dev/null 2>&1; then
                log "Health check passed: process is running"
                return 0
            fi
        fi
        
        log "Health check failed (attempt $i/$max_retries), retrying in ${retry_delay}s..."
        sleep "$retry_delay"
    done
    
    log "[ERROR] Health check failed after $max_retries attempts"
    return 1
}

rollback() {
    local backup_file=""
    
    if [ -n "$ROLLBACK_VERSION" ] && [ -f "$ROLLBACK_VERSION" ]; then
        backup_file="$ROLLBACK_VERSION"
    elif [ -f "${BACKUP_DIR}/${SERVICE_NAME}_last_backup.txt" ]; then
        backup_file=$(cat "${BACKUP_DIR}/${SERVICE_NAME}_last_backup.txt")
    else
        log "[ERROR] No backup file found for rollback"
        return 1
    fi
    
    log "Starting rollback from: $backup_file"
    
    stop_service
    
    if [ -f "$backup_file" ]; then
        rm -rf "$DEPLOY_DIR/$SERVICE_NAME"
        mkdir -p "$DEPLOY_DIR/$SERVICE_NAME"
        
        if tar -xzf "$backup_file" -C "$DEPLOY_DIR"; then
            log "Rollback extraction completed"
            
            start_service
            
            if health_check; then
                log "Rollback completed successfully"
                return 0
            fi
        fi
    fi
    
    log "[ERROR] Rollback failed"
    return 1
}

deploy() {
    local package_url="$1"
    local health_url="$2"
    
    log "=========================================="
    log "Starting deployment: $SERVICE_NAME v$SERVICE_VERSION"
    log "=========================================="
    
    backup_current_version || return 1
    
    local package_file=$(download_package "$package_url")
    if [ -z "$package_file" ]; then
        return 1
    fi
    
    local source_dir=$(extract_package "$package_file")
    if [ -z "$source_dir" ]; then
        return 1
    fi
    
    stop_service
    
    if ! deploy_new_version "$source_dir"; then
        rm -rf "$source_dir"
        rollback
        return 1
    fi
    
    rm -rf "$source_dir"
    
    start_service
    
    if health_check "$health_url"; then
        log "=========================================="
        log "Deployment completed successfully!"
        log "=========================================="
        return 0
    else
        log "[ERROR] Health check failed, initiating rollback..."
        rollback
        return 1
    fi
}

list_backups() {
    echo "=========================================="
    echo "Available Backups for: $SERVICE_NAME"
    echo "=========================================="
    find "$BACKUP_DIR" -name "${SERVICE_NAME}_*.tar.gz" -printf "%TY-%Tm-%Td %TH:%TM %12s %f\n" | sort -r
    echo "=========================================="
}

show_current_version() {
    if [ -f "$DEPLOY_DIR/$SERVICE_NAME/VERSION" ]; then
        echo "Current version: $(cat "$DEPLOY_DIR/$SERVICE_NAME/VERSION")"
    else
        echo "No version file found"
    fi
}

while getopts "n:v:a:u:H:r:lh" opt; do
    case $opt in
        n) SERVICE_NAME="$OPTARG" ;;
        v) SERVICE_VERSION="$OPTARG" ;;
        a) ACTION="$OPTARG" ;;
        u) PACKAGE_URL="$OPTARG" ;;
        H) HEALTH_CHECK_URL="$OPTARG" ;;
        r) ROLLBACK_VERSION="$OPTARG" ;;
        l) LIST_BACKUPS=true ;;
        h) echo "Usage: $0 -n service -v version -a deploy|rollback [-u url] [-H health_url] [-r backup_file] [-l]"; exit 0 ;;
        \?) echo "Unknown option: -$OPTARG. Use -h for help."; exit 2 ;;
    esac
done

if [ -z "$SERVICE_NAME" ]; then
    echo "Service name required. Use -n service_name"
    exit 1
fi

if [ "$LIST_BACKUPS" = true ]; then
    list_backups
    exit 0
fi

if [ "$ACTION" = "version" ]; then
    show_current_version
    exit 0
fi

case "$ACTION" in
    deploy)
        if [ -z "$PACKAGE_URL" ]; then
            echo "Package URL required. Use -u url"
            exit 1
        fi
        if [ -z "$SERVICE_VERSION" ]; then
            echo "Service version required for deploy. Use -v version"
            exit 1
        fi
        deploy "$PACKAGE_URL" "$HEALTH_CHECK_URL"
        ;;
    rollback)
        rollback
        ;;
    *)
        echo "Service Deployment Script v$VERSION"
        echo ""
        echo "Usage: $0 -n service_name -a action [options]"
        echo ""
        echo "Actions:"
        echo "  deploy       Deploy new version"
        echo "  rollback     Rollback to previous version"
        echo "  version      Show current version"
        echo ""
        echo "Options:"
        echo "  -n name      Service name (required)"
        echo "  -v version   Version being deployed"
        echo "  -u url       Package URL (tar.gz)"
        echo "  -H url       Health check URL (HTTP 200 required after deploy)"
        echo "  -r file      Rollback from specific backup file"
        echo "  -l           List available backups"
        ;;
esac