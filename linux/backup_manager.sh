#!/bin/bash
# Backup Manager - Full and incremental backup script
# Author: System Admin
# Usage: ./backup_manager.sh -s source -d dest [-t type] [-k keep]

VERSION="1.0"
BACKUP_TYPE="full"
KEEP_DAYS=7
COMPRESS="gzip"
LOG_FILE="/var/log/backup_manager.log"
EXCLUDE_PATTERNS=()

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

get_timestamp() {
    date '+%Y%m%d_%H%M%S'
}

create_full_backup() {
    local source="$1"
    local dest="$2"
    local name=$(basename "$source")
    local timestamp=$(get_timestamp)
    local backup_file="${dest}/${name}_full_${timestamp}.tar"
    
    log "Starting FULL backup: $source -> $backup_file"
    
    local exclude_args=()
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        exclude_args+=("--exclude=$pattern")
    done
    
    if tar "${exclude_args[@]}" -cf "$backup_file" -C "$(dirname "$source")" "$(basename "$source")"; then
        case $COMPRESS in
            gzip) gzip "$backup_file"; backup_file="${backup_file}.gz" ;;
            bzip2) bzip2 "$backup_file"; backup_file="${backup_file}.bz2" ;;
            xz) xz "$backup_file"; backup_file="${backup_file}.xz" ;;
        esac
        
        local size=$(du -h "$backup_file" | cut -f1)
        log "Backup completed: $backup_file ($size)"
        echo "$backup_file"
        return 0
    else
        log "[ERROR] Full backup failed: $source"
        return 1
    fi
}

create_incremental_backup() {
    local source="$1"
    local dest="$2"
    local name=$(basename "$source")
    local timestamp=$(get_timestamp)
    local snapshot_file="${dest}/${name}_snapshot.snar"
    local backup_file="${dest}/${name}_incr_${timestamp}.tar"
    
    log "Starting INCREMENTAL backup: $source -> $backup_file"
    
    if [ ! -f "$snapshot_file" ]; then
        log "Snapshot not found, creating initial full backup..."
        local full_file
        full_file=$(create_full_backup "$source" "$dest") || return 1
        mv "$full_file" "${full_file/_full_/_incr_}" || return 1
        echo "${full_file/_full_/_incr_}"
        return 0
    fi
    
    local exclude_args=()
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        exclude_args+=("--exclude=$pattern")
    done
    
    if tar "${exclude_args[@]}" --listed-incremental="$snapshot_file" -cf "$backup_file" -C "$(dirname "$source")" "$(basename "$source")"; then
        case $COMPRESS in
            gzip) gzip "$backup_file"; backup_file="${backup_file}.gz" ;;
            bzip2) bzip2 "$backup_file"; backup_file="${backup_file}.bz2" ;;
            xz) xz "$backup_file"; backup_file="${backup_file}.xz" ;;
        esac
        
        local size=$(du -h "$backup_file" | cut -f1)
        log "Incremental backup completed: $backup_file ($size)"
        echo "$backup_file"
        return 0
    else
        log "[ERROR] Incremental backup failed: $source"
        return 1
    fi
}

cleanup_old_backups() {
    local dest="$1"
    log "Cleaning backups older than ${KEEP_DAYS} days in: $dest"
    
    local count=$(find "$dest" -type f -name "*.tar*" -mtime +"$KEEP_DAYS" -delete -print | wc -l)
    log "Cleaned $count old backup files"
}

restore_backup() {
    local backup_file="$1"
    local restore_dir="$2"
    
    log "Restoring backup: $backup_file -> $restore_dir"
    
    mkdir -p "$restore_dir"
    
    case "$backup_file" in
        *.gz) tar -xzf "$backup_file" -C "$restore_dir" ;;
        *.bz2) tar -xjf "$backup_file" -C "$restore_dir" ;;
        *.xz) tar -xJf "$backup_file" -C "$restore_dir" ;;
        *.tar) tar -xf "$backup_file" -C "$restore_dir" ;;
        *) log "[ERROR] Unknown file format"; return 1 ;;
    esac
    
    if [ $? -eq 0 ]; then
        log "Restore completed successfully"
        return 0
    else
        log "[ERROR] Restore failed"
        return 1
    fi
}

list_backups() {
    local dest="$1"
    echo "=========================================="
    echo "       Backup List in: $dest"
    echo "=========================================="
    find "$dest" -type f -name "*.tar*" -printf "%TY-%Tm-%Td %TH:%TM %12s %f\n" | sort -r
    echo "=========================================="
}

while getopts "s:d:t:c:x:r:k:l:h" opt; do
    case $opt in
        s) SOURCE_DIR="$OPTARG" ;;
        d) DEST_DIR="$OPTARG" ;;
        t) BACKUP_TYPE="$OPTARG" ;;
        c) COMPRESS="$OPTARG" ;;
        x) EXCLUDE_PATTERNS+=("$OPTARG") ;;
        r) RESTORE_FILE="$OPTARG" ;;
        k) KEEP_DAYS="$OPTARG" ;;
        l) LIST_DIR="$OPTARG" ;;
        h) echo "Usage: $0 -s source -d dest [-t full|incr] [-c gzip|bzip2|xz] [-x exclude] [-r restore_file] [-k days] [-l dest]"; exit 0 ;;
        \?) echo "Unknown option: -$OPTARG. Use -h for help."; exit 2 ;;
    esac
done

if [ -n "$RESTORE_FILE" ] && [ -n "$DEST_DIR" ]; then
    restore_backup "$RESTORE_FILE" "$DEST_DIR"
    exit $?
fi

if [ -n "$LIST_DIR" ]; then
    list_backups "$LIST_DIR"
    exit 0
fi

if [ -z "$SOURCE_DIR" ] || [ -z "$DEST_DIR" ]; then
    echo "Source and destination required. Use -h for help."
    exit 1
fi

mkdir -p "$DEST_DIR"

case $BACKUP_TYPE in
    full) create_full_backup "$SOURCE_DIR" "$DEST_DIR" ;;
    incr|incremental) create_incremental_backup "$SOURCE_DIR" "$DEST_DIR" ;;
    *) log "[ERROR] Unknown backup type: $BACKUP_TYPE"; exit 1 ;;
esac || exit $?

cleanup_old_backups "$DEST_DIR"