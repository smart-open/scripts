#!/bin/bash
# Docker Cleaner Script - Cleanup containers, images, volumes, networks
# Author: System Admin
# Usage: ./docker_cleaner.sh [-a all] [-i images] [-v volumes] [-o networks] [-c containers] [-n unused_images] [-b build_cache] [-d dry_run] [-s status]

VERSION="1.0"
LOG_FILE="/var/log/docker_cleaner.log"
DRY_RUN=false

# 非 root 时 /var/log 通常不可写，降级避免日志函数自身报错
if ! touch "$LOG_FILE" 2>/dev/null; then
    LOG_FILE="/dev/null"
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TOTAL_CLEANED=0

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_docker_running() {
    # 检查docker命令是否存在
    if ! command -v docker >/dev/null 2>&1; then
        log "[ERROR] Docker command not found. Please install Docker first."
        return 1
    fi
    
    # 检查能否连接docker daemon
    if ! docker info >/dev/null 2>&1; then
        log "[ERROR] Cannot connect to Docker daemon."
        log "  - If running as non-root, add user to docker group: sudo usermod -aG docker $USER"
        log "  - Or run this script with sudo"
        return 1
    fi
    return 0
}

get_size() {
    local size="$1"
    if [ -z "$size" ] || [ "$size" = "0B" ]; then
        echo "0B"
    else
        echo "$size"
    fi
}

clean_stopped_containers() {
    log "Cleaning stopped containers..."
    local stopped=$(docker ps -q -f status=exited 2>/dev/null | wc -l)
    
    if [ "$stopped" -gt 0 ]; then
        log "Found $stopped stopped containers"
        if [ "$DRY_RUN" = false ]; then
            local cleaned=$(docker rm $(docker ps -q -f status=exited) 2>/dev/null | wc -l)
            log "Removed $cleaned stopped containers"
            ((TOTAL_CLEANED += cleaned))
        else
            log "[DRY RUN] Would remove $stopped containers"
        fi
    else
        log "No stopped containers to remove"
    fi
}

clean_dangling_images() {
    log "Cleaning dangling images..."
    local dangling=$(docker images -q -f dangling=true 2>/dev/null | wc -l)
    
    if [ "$dangling" -gt 0 ]; then
        log "Found $dangling dangling images"
        if [ "$DRY_RUN" = false ]; then
            local space_saved=$(docker rmi $(docker images -q -f dangling=true) 2>&1 | tail -1)
            log "Removed dangling images: $(get_size "$space_saved")"
            ((TOTAL_CLEANED += dangling))
        else
            log "[DRY RUN] Would remove $dangling images"
        fi
    else
        log "No dangling images to remove"
    fi
}

clean_unused_images() {
    log "Cleaning unused images (older than 7 days)..."
    local images=$(docker images --format "{{.ID}} {{.CreatedAt}}" | awk -v cutoff=$(date -d "7 days ago" +%s) '{
        cmd = "date -d \"" $2 " " $3 "\" +%s"
        cmd | getline created
        close(cmd)
        if (created < cutoff) print $1
    }' 2>/dev/null | wc -l)
    
    if [ "$images" -gt 0 ]; then
        log "Found $images images older than 7 days"
        if [ "$DRY_RUN" = false ]; then
            docker images --format "{{.ID}} {{.CreatedAt}}" | while read id date time rest; do
                created=$(date -d "$date $time" +%s 2>/dev/null)
                cutoff=$(date -d "7 days ago" +%s)
                if [ "$created" -lt "$cutoff" ]; then
                    docker rmi "$id" 2>/dev/null
                fi
            done
            log "Removed unused images"
        else
            log "[DRY RUN] Would remove $images images"
        fi
    else
        log "No unused images older than 7 days"
    fi
}

clean_dangling_volumes() {
    log "Cleaning dangling volumes..."
    local dangling=$(docker volume ls -q -f dangling=true 2>/dev/null | wc -l)
    
    if [ "$dangling" -gt 0 ]; then
        log "Found $dangling dangling volumes"
        if [ "$DRY_RUN" = false ]; then
            docker volume rm $(docker volume ls -q -f dangling=true) 2>/dev/null
            log "Removed $dangling dangling volumes"
            ((TOTAL_CLEANED += dangling))
        else
            log "[DRY RUN] Would remove $dangling volumes"
        fi
    else
        log "No dangling volumes to remove"
    fi
}

clean_unused_networks() {
    log "Cleaning unused networks..."
    local used=0
    local unused_list=()

    for net in $(docker network ls -q 2>/dev/null); do
        # 跳过系统内置网络
        case "$net" in bridge|host|none) continue ;; esac
        # 直接取容器数量：{{.Containers}} 为空 map 时输出 map[]，grep -v "{}" 判断会全部误判为"在用"
        local cnt
        cnt=$(docker network inspect -f '{{len .Containers}}' "$net" 2>/dev/null)
        if [ "${cnt:-0}" -gt 0 ]; then
            used=$((used + 1))
        else
            unused_list+=("$net")
        fi
    done

    local unused=${#unused_list[@]}
    if [ "$unused" -gt 0 ]; then
        log "Found $unused unused networks"
        if [ "$DRY_RUN" = false ]; then
            for net in "${unused_list[@]}"; do
                docker network rm "$net" 2>/dev/null
            done
            log "Removed $unused unused networks"
            TOTAL_CLEANED=$((TOTAL_CLEANED + unused))
        else
            log "[DRY RUN] Would remove $unused networks"
        fi
    else
        log "No unused networks to remove"
    fi
}

clean_build_cache() {
    log "Cleaning build cache..."
    if [ "$DRY_RUN" = false ]; then
        docker builder prune -f 2>/dev/null
        log "Build cache cleaned"
    else
        log "[DRY RUN] Would clean build cache"
    fi
}

clean_all() {
    log "=========================================="
    log "Running FULL Docker cleanup"
    log "=========================================="

    clean_stopped_containers
    clean_dangling_images
    clean_unused_images
    clean_dangling_volumes
    clean_unused_networks
    clean_build_cache

    log "=========================================="
    log "Full cleanup completed. Total items cleaned: $TOTAL_CLEANED"
    log "=========================================="
}

show_disk_usage() {
    echo "=========================================="
    echo "Docker Disk Usage"
    echo "=========================================="
    
    if command -v df >/dev/null 2>&1; then
        local docker_root=$(docker info -f '{{.DockerRootDir}}' 2>/dev/null)
        if [ -n "$docker_root" ]; then
            echo "Docker directory: $docker_root"
            du -sh "$docker_root" 2>/dev/null
        fi
    fi
    
    echo ""
    echo "Images:"
    docker images --format "{{.Size}} {{.Repository}}:{{.Tag}}" | sort -hr | head -10
    
    echo ""
    echo "Volumes:"
    docker system df -v 2>/dev/null | head -20
}

show_summary() {
    echo ""
    echo "=========================================="
    echo "Docker Cleaner Summary"
    echo "=========================================="
    echo "Total items cleaned: $TOTAL_CLEANED"
    echo "Log file: $LOG_FILE"
    echo "=========================================="
}

usage() {
    echo "Usage: $0 [-a all] [-i images] [-v volumes] [-o networks] [-c containers]"
    echo "                [-n unused_images] [-b build_cache] [-d dry_run] [-s status]"
    echo ""
    echo "  -a  full cleanup (containers + images + volumes + networks + build cache)"
    echo "  -d  dry run: only show what would be cleaned, remove nothing"
    echo "  -s  show docker disk usage"
    echo "  -h  show this help"
}

# 动作标记统一先收集再执行：保证 -d dry-run 不受选项顺序影响，
# 且带任何动作选项时都能先通过 Docker 环境检查（原实现动作在检查前直接执行并退出）
DO_ALL=false; DO_IMAGES=false; DO_VOLUMES=false; DO_NETWORKS=false
DO_CONTAINERS=false; DO_UNUSED_IMAGES=false; DO_BUILD_CACHE=false
SHOW_STATUS=false

while getopts ":aicvonbdsh" opt; do
    case $opt in
        a) DO_ALL=true ;;
        i) DO_IMAGES=true ;;
        v) DO_VOLUMES=true ;;
        o) DO_NETWORKS=true ;;
        c) DO_CONTAINERS=true ;;
        n) DO_UNUSED_IMAGES=true ;;
        b) DO_BUILD_CACHE=true ;;
        d) DRY_RUN=true ;;
        s) SHOW_STATUS=true ;;
        h) usage; exit 0 ;;
        \?) echo "Unknown option: -$OPTARG"; usage; exit 2 ;;
    esac
done

# 状态查看仅需要 Docker 连接
if [ "$SHOW_STATUS" = true ]; then
    check_docker_running || exit 1
    show_disk_usage
    exit 0
fi

if ! $DO_ALL && ! $DO_IMAGES && ! $DO_VOLUMES && ! $DO_NETWORKS \
   && ! $DO_CONTAINERS && ! $DO_UNUSED_IMAGES && ! $DO_BUILD_CACHE; then
    echo "Docker Cleaner Script v$VERSION"
    usage
    echo ""
    echo "[提示] 未指定清理动作，未执行任何操作"
    exit 1
fi

if ! check_docker_running; then
    exit 1
fi

# 全量清理属危险操作，dry-run 之外需二次确认
if [ "$DO_ALL" = true ] && [ "$DRY_RUN" = false ]; then
    read -r -p "[确认] 即将对本机 Docker 执行全量清理，是否继续? [y/N]: " answer
    case "$answer" in
        y|Y|yes|YES) log "Full cleanup confirmed by user" ;;
        *) echo "已取消"; exit 0 ;;
    esac
fi

if [ "$DO_ALL" = true ]; then
    clean_all
else
    $DO_CONTAINERS && clean_stopped_containers
    $DO_IMAGES && clean_dangling_images
    $DO_UNUSED_IMAGES && clean_unused_images
    $DO_VOLUMES && clean_dangling_volumes
    $DO_NETWORKS && clean_unused_networks
    $DO_BUILD_CACHE && clean_build_cache
fi

show_summary