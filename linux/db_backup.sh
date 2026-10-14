#!/bin/bash
# Database Backup Script - MySQL/PostgreSQL backup with rotation
# Author: System Admin
# Usage: ./db_backup.sh -t mysql|pgsql -d database [-u user] [-p pass]

VERSION="1.0"
DB_TYPE="mysql"
DB_HOST="localhost"
DB_PORT=""
DB_USER="root"
DB_PASS=""
DB_NAME=""
BACKUP_DIR="/var/backups/databases"
KEEP_DAYS=7
COMPRESS="gzip"
LOG_FILE="/var/log/db_backup.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

get_timestamp() {
    date '+%Y%m%d_%H%M%S'
}

backup_mysql() {
    local timestamp=$(get_timestamp)
    local backup_file="${BACKUP_DIR}/${DB_TYPE}_${DB_NAME}_${timestamp}.sql"
    
    log "Starting MySQL backup: $DB_NAME"
    
    # 使用MYSQL_PWD环境变量避免命令行密码暴露
    local mysql_opts="-h $DB_HOST -u $DB_USER"
    [ -n "$DB_PORT" ] && mysql_opts="$mysql_opts -P $DB_PORT"
    export MYSQL_PWD="$DB_PASS"
    
    if mysqldump $mysql_opts "$DB_NAME" > "$backup_file" 2>> "$LOG_FILE"; then
        unset MYSQL_PWD
        compress_file "$backup_file"
        return 0
    else
        unset MYSQL_PWD
        log "[ERROR] MySQL backup failed"
        rm -f "$backup_file"
        return 1
    fi
}

backup_postgresql() {
    local timestamp=$(get_timestamp)
    local backup_file="${BACKUP_DIR}/${DB_TYPE}_${DB_NAME}_${timestamp}.sql"
    
    log "Starting PostgreSQL backup: $DB_NAME"
    
    export PGPASSWORD="$DB_PASS"
    local pg_opts="-h $DB_HOST -U $DB_USER"
    [ -n "$DB_PORT" ] && pg_opts="$pg_opts -p $DB_PORT"
    
    if pg_dump $pg_opts "$DB_NAME" > "$backup_file" 2>> "$LOG_FILE"; then
        compress_file "$backup_file"
        unset PGPASSWORD
        return 0
    else
        log "[ERROR] PostgreSQL backup failed"
        unset PGPASSWORD
        rm -f "$backup_file"
        return 1
    fi
}

backup_all_mysql() {
    local timestamp=$(get_timestamp)
    local backup_file="${BACKUP_DIR}/${DB_TYPE}_all_${timestamp}.sql"
    
    log "Starting MySQL backup: all databases"
    
    # 使用MYSQL_PWD环境变量避免命令行密码暴露
    local mysql_opts="-h $DB_HOST -u $DB_USER"
    [ -n "$DB_PORT" ] && mysql_opts="$mysql_opts -P $DB_PORT"
    export MYSQL_PWD="$DB_PASS"
    
    if mysqldump $mysql_opts --all-databases > "$backup_file" 2>> "$LOG_FILE"; then
        unset MYSQL_PWD
        compress_file "$backup_file"
        return 0
    else
        unset MYSQL_PWD
        log "[ERROR] MySQL all databases backup failed"
        rm -f "$backup_file"
        return 1
    fi
}

compress_file() {
    local file="$1"
    
    case $COMPRESS in
        gzip) gzip "$file"; file="${file}.gz" ;;
        bzip2) bzip2 "$file"; file="${file}.bz2" ;;
        xz) xz "$file"; file="${file}.xz" ;;
    esac
    
    local size=$(du -h "$file" | cut -f1)
    log "Backup completed: $file ($size)"
}

cleanup_old_backups() {
    log "Cleaning backups older than ${KEEP_DAYS} days"
    find "$BACKUP_DIR" -type f -name "*.sql*" -mtime +"$KEEP_DAYS" -delete -print | wc -l | while read count; do
        log "Cleaned $count old backup files"
    done
}

restore_backup() {
    local backup_file="$1"
    log "Restoring database: $backup_file"
    
    if [ ! -f "$backup_file" ]; then
        log "[ERROR] Backup file not found: $backup_file"
        return 1
    fi
    
    local temp_sql=$(mktemp)
    
    case "$backup_file" in
        *.gz) gunzip -c "$backup_file" > "$temp_sql" ;;
        *.bz2) bunzip2 -c "$backup_file" > "$temp_sql" ;;
        *.xz) xz -d -c "$backup_file" > "$temp_sql" ;;
        *.sql) cp "$backup_file" "$temp_sql" ;;
        *) log "[ERROR] Unsupported backup file format: $backup_file"; rm -f "$temp_sql"; return 1 ;;
    esac

    local rc=1
    if [ "$DB_TYPE" = "mysql" ]; then
        if [ -z "$DB_NAME" ]; then
            log "[ERROR] Restore requires database name (-d)"
            rm -f "$temp_sql"
            return 1
        fi
        # 使用MYSQL_PWD环境变量避免命令行密码暴露
        local mysql_opts="-h $DB_HOST -u $DB_USER"
        [ -n "$DB_PORT" ] && mysql_opts="$mysql_opts -P $DB_PORT"
        export MYSQL_PWD="$DB_PASS"
        mysql $mysql_opts "$DB_NAME" < "$temp_sql" 2>> "$LOG_FILE"
        rc=$?
        unset MYSQL_PWD
    elif [ "$DB_TYPE" = "pgsql" ]; then
        if [ -z "$DB_NAME" ]; then
            log "[ERROR] Restore requires database name (-d)"
            rm -f "$temp_sql"
            return 1
        fi
        export PGPASSWORD="$DB_PASS"
        local pg_opts="-h $DB_HOST -U $DB_USER"
        psql $pg_opts "$DB_NAME" < "$temp_sql" 2>> "$LOG_FILE"
        rc=$?
        unset PGPASSWORD
    else
        log "[ERROR] Unsupported database type: $DB_TYPE"
        rm -f "$temp_sql"
        return 1
    fi

    rm -f "$temp_sql"

    if [ $rc -eq 0 ]; then
        log "Restore completed successfully"
        return 0
    else
        log "[ERROR] Restore failed"
        return 1
    fi
}

list_backups() {
    echo "=========================================="
    echo "       Database Backup List"
    echo "=========================================="
    find "$BACKUP_DIR" -type f -name "*.sql*" -printf "%TY-%Tm-%Td %TH:%TM %12s %f\n" | sort -r
    echo "=========================================="
}

usage() {
    echo "Usage: $0 -t mysql|pgsql [-h host] [-u user] [-p pass] -d db [-r restore_file] [-k days] [-a]"
    echo "       -a backup all databases (mysql only), -l list backups, -r restore from file"
}

if [ $# -eq 0 ]; then
    usage
    exit 1
fi

while getopts "t:h:P:u:p:d:c:r:k:lah" opt; do
    case $opt in
        t) DB_TYPE="$OPTARG" ;;
        h) DB_HOST="$OPTARG" ;;
        P) DB_PORT="$OPTARG" ;;
        u) DB_USER="$OPTARG" ;;
        p) DB_PASS="$OPTARG" ;;
        d) DB_NAME="$OPTARG" ;;
        c) COMPRESS="$OPTARG" ;;
        r) RESTORE_FILE="$OPTARG" ;;
        k) KEEP_DAYS="$OPTARG" ;;
        l) list_backups; exit 0 ;;
        a) BACKUP_ALL=true ;;
        \?) echo "Unknown option: -$OPTARG"; usage; exit 2 ;;
    esac
done

mkdir -p "$BACKUP_DIR"

if [ -n "$RESTORE_FILE" ]; then
    restore_backup "$RESTORE_FILE"
    exit $?
fi

if [ -z "$DB_NAME" ] && [ -z "$BACKUP_ALL" ]; then
    echo "Database name required. Use -d or -a for all databases."
    exit 1
fi

if [ "$BACKUP_ALL" = true ]; then
    if [ "$DB_TYPE" = "pgsql" ]; then
        log "[ERROR] -a (all databases) is only supported for mysql"
        exit 1
    fi
    backup_all_mysql
else
    case $DB_TYPE in
        mysql) backup_mysql ;;
        pgsql|postgresql) DB_TYPE="pgsql"; backup_postgresql ;;
        *) log "[ERROR] Unsupported database type: $DB_TYPE"; exit 1 ;;
    esac
fi

cleanup_old_backups