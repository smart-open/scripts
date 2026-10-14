#!/bin/bash
# Docker & Docker Compose Auto Installer for CentOS and Ubuntu
# Detects OS, installs latest stable Docker Engine + Compose plugin
# Usage: ./docker_install.sh [-y] [--mirror china|default]
# Author: System Admin

set -e

VERSION="2.0"
AUTO_YES=false
MIRROR="default"
LOG_FILE="/var/log/docker_install.log"

# 非 root 时 /var/log 通常不可写，降级避免日志函数自身报错（root 检查在此之前打印）
if ! touch "$LOG_FILE" 2>/dev/null; then
    LOG_FILE="/dev/null"
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 写日志统一无色（ANSI 码不进入日志文件），终端输出按 TTY 决定是否带色
_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

_term() {
    if [ -t 1 ]; then echo -e "$1"; else echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g'; fi
}

info()  { _term "${BLUE}[INFO]${NC} $1"; _log "[INFO] $1"; }
ok()    { _term "${GREEN}[OK]${NC} $1"; _log "[OK] $1"; }
warn()  { _term "${YELLOW}[WARN]${NC} $1"; _log "[WARN] $1"; }
error() { _term "${RED}[ERROR]${NC} $1" >&2; _log "[ERROR] $1"; }

# Check root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root"
        echo "  sudo $0 $@"
        exit 1
    fi
}

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
        OS_NAME="$PRETTY_NAME"
    elif [ -f /etc/redhat-release ]; then
        OS_ID="centos"
        OS_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | head -1)
        OS_NAME=$(cat /etc/redhat-release)
    else
        error "Unsupported OS. Only CentOS and Ubuntu are supported."
        exit 1
    fi

    case "$OS_ID" in
        centos|rhel|rocky|almalinux|fedora)
            OS_FAMILY="rhel"
            ;;
        ubuntu|debian)
            OS_FAMILY="debian"
            ;;
        *)
            error "Unsupported OS: $OS_ID"
            exit 1
            ;;
    esac

    info "Detected OS: $OS_NAME ($OS_ID $OS_VERSION)"
}

# Get latest Docker version from API
get_latest_docker_version() {
    local version=""
    # Try GitHub API
    version=$(curl -sL "https://api.github.com/repos/moby/moby/releases/latest" 2>/dev/null | grep '"tag_name"' | head -1 | sed -E 's/.*"v?([^"]+)".*/\1/')
    
    if [ -z "$version" ]; then
        # Fallback: query package manager
        if [ "$OS_FAMILY" = "rhel" ]; then
            version=$(yum list docker-ce --showduplicates 2>/dev/null | grep docker-ce | tail -1 | awk '{print $2}' | cut -d'-' -f1)
        else
            version=$(apt-cache madison docker-ce 2>/dev/null | tail -1 | awk '{print $3}' | cut -d'-' -f1)
        fi
    fi
    
    if [ -z "$version" ]; then
        version="unknown"
    fi
    echo "$version"
}

# Get latest Docker Compose version
get_latest_compose_version() {
    local version=""
    version=$(curl -sL "https://api.github.com/repos/docker/compose/releases/latest" 2>/dev/null | grep '"tag_name"' | head -1 | sed -E 's/.*"v?([^"]+)".*/\1/')
    
    if [ -z "$version" ]; then
        version="unknown"
    fi
    echo "$version"
}

# Remove old Docker installations
remove_old_docker() {
    info "Removing old Docker installations..."

    if [ "$OS_FAMILY" = "rhel" ]; then
        yum remove -y docker \
            docker-client \
            docker-client-latest \
            docker-common \
            docker-latest \
            docker-latest-logrotate \
            docker-logrotate \
            docker-engine \
            docker-ce \
            docker-ce-cli \
            containerd.io 2>/dev/null || true
    else
        apt remove -y docker docker-engine docker.io containerd runc \
            docker-ce docker-ce-cli containerd.io \
            docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
    fi

    ok "Old Docker packages removed"
}

# Install Docker on RHEL-based systems
install_docker_rhel() {
    info "Installing Docker on RHEL-based system..."

    # Install prerequisites
    yum install -y yum-utils device-mapper-persistent-data lvm2

    # Add Docker repository
    if [ "$MIRROR" = "china" ]; then
        info "Using China mirror for Docker repository"
        yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
        sed -i 's|https://download.docker.com|https://mirrors.aliyun.com/docker-ce|g' /etc/yum.repos.d/docker-ce.repo
    else
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    fi

    # Install Docker
    info "Installing docker-ce, docker-ce-cli, containerd.io, docker-compose-plugin..."
    yum install -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin

    ok "Docker packages installed"
}

# Install Docker on Debian-based systems
install_docker_debian() {
    info "Installing Docker on Debian-based system..."

    # Install prerequisites
    apt update
    apt install -y ca-certificates curl gnupg lsb-release

    # Add Docker GPG key
    install -m 0755 -d /etc/apt/keyrings

    # 发行版分仓库路径：ubuntu 与 debian 的 apt 源不同，不能硬编码 ubuntu
    local distro="${OS_ID:-ubuntu}"
    if [[ "$distro" != "ubuntu" && "$distro" != "debian" ]]; then
        distro="ubuntu"
    fi

    if [ "$MIRROR" = "china" ]; then
        info "Using China mirror for Docker repository"
        curl -fsSL "https://mirrors.aliyun.com/docker-ce/linux/$distro/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/$distro $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    else
        curl -fsSL "https://download.docker.com/linux/$distro/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$distro $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    fi

    chmod a+r /etc/apt/keyrings/docker.gpg

    # Install Docker
    apt update
    info "Installing docker-ce, docker-ce-cli, containerd.io, docker-compose-plugin..."
    apt install -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin

    ok "Docker packages installed"
}

# Configure Docker daemon
configure_docker() {
    info "Configuring Docker daemon..."

    mkdir -p /etc/docker

    # 已有配置先备份，避免覆盖用户自定义的镜像源/日志配置
    if [ -f /etc/docker/daemon.json ]; then
        local backup="/etc/docker/daemon.json.bak.$(date +%Y%m%d%H%M%S)"
        cp /etc/docker/daemon.json "$backup"
        warn "Existing daemon.json backed up to: $backup"
    fi

    if [ "$MIRROR" = "china" ]; then
        cat > /etc/docker/daemon.json << 'EOF'
{
    "registry-mirrors": [
        "https://docker.1ms.run",
        "https://docker.xuanyuan.me"
    ],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    },
    "live-restore": true,
    "storage-driver": "overlay2"
}
EOF
    else
        cat > /etc/docker/daemon.json << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    },
    "live-restore": true,
    "storage-driver": "overlay2"
}
EOF
    fi

    ok "Docker daemon configured"
}

# Start and enable Docker
start_docker() {
    info "Starting Docker service..."
    systemctl enable docker
    systemctl daemon-reload
    systemctl restart docker

    if systemctl is-active --quiet docker; then
        ok "Docker service is running"
    else
        error "Docker service failed to start"
        exit 1
    fi
}

# Verify installation
verify_installation() {
    info "Verifying Docker installation..."

    local docker_ver=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
    local compose_ver=$(docker compose version --short 2>/dev/null || echo "unknown")

    echo ""
    echo "==========================================" | tee -a "$LOG_FILE"
    echo "       Docker Installation Summary" | tee -a "$LOG_FILE"
    echo "==========================================" | tee -a "$LOG_FILE"
    echo "OS:           $OS_NAME" | tee -a "$LOG_FILE"
    echo "Docker:       $docker_ver" | tee -a "$LOG_FILE"
    echo "Compose:      $compose_ver" | tee -a "$LOG_FILE"
    echo "Containerd:   $(containerd --version 2>/dev/null | awk '{print $3}')" | tee -a "$LOG_FILE"
    echo "==========================================" | tee -a "$LOG_FILE"
    echo ""

    # Run hello-world test
    if docker run --rm hello-world >/dev/null 2>&1; then
        ok "Docker is working correctly (hello-world test passed)"
    else
        warn "hello-world test failed (may be network issue). Docker is installed but please verify manually."
    fi
}

# Add current user to docker group
add_user_to_docker_group() {
    local user="${SUDO_USER:-$USER}"
    if [ "$user" != "root" ]; then
        info "Adding user '$user' to docker group..."
        usermod -aG docker "$user"
        ok "User '$user' added to docker group (re-login required)"
    fi
}

# Show usage
show_help() {
    echo "Docker & Docker Compose Auto Installer v$VERSION"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -y                Auto-confirm all prompts"
    echo "  --mirror china    Use China mirrors (Aliyun)"
    echo "  --mirror default  Use official Docker repos (default)"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  sudo $0 -y                    # Quick install with defaults"
    echo "  sudo $0 -y --mirror china     # Install with China mirrors"
    echo ""
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)
            AUTO_YES=true
            shift
            ;;
        --mirror)
            if [[ -z "${2:-}" || ! "$2" =~ ^(china|default)$ ]]; then
                error "--mirror requires a value: china|default"
                exit 1
            fi
            MIRROR="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main
echo "==========================================" | tee "$LOG_FILE"
echo "Docker & Docker Compose Auto Installer v$VERSION" | tee -a "$LOG_FILE"
echo "==========================================" | tee -a "$LOG_FILE"

check_root "$@"
detect_os

# Get latest versions
info "Checking latest Docker version..."
LATEST_DOCKER=$(get_latest_docker_version)
LATEST_COMPOSE=$(get_latest_compose_version)
info "Latest Docker Engine: $LATEST_DOCKER"
info "Latest Docker Compose: $LATEST_COMPOSE"

# Confirm
if [ "$AUTO_YES" = false ]; then
    echo ""
    read -p "Proceed with installation? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Installation cancelled"
        exit 0
    fi
fi

# Execute
remove_old_docker

if [ "$OS_FAMILY" = "rhel" ]; then
    install_docker_rhel
else
    install_docker_debian
fi

configure_docker
start_docker
verify_installation
add_user_to_docker_group

echo ""
ok "Docker installation completed successfully!"
echo ""
echo "Next steps:"
echo "  1. Log out and log back in (for docker group to take effect)"
echo "  2. Verify: docker --version && docker compose version"
echo "  3. Run a container: docker run -it --rm hello-world"
echo ""