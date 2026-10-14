#!/bin/bash
# Port Scanner - Network port scanning and service discovery
# Author: System Admin
# Usage: ./port_scanner.sh -t target [-p ports] [-T type]

VERSION="1.0"
TARGET=""
PORT_RANGE="1-1024"
SCAN_TYPE="tcp"
TIMEOUT=1
OUTPUT_FORMAT="pretty"
LOG_FILE="/var/log/port_scanner.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

declare -A COMMON_PORTS=(
    [21]="FTP" [22]="SSH" [23]="Telnet" [25]="SMTP" [53]="DNS"
    [80]="HTTP" [110]="POP3" [111]="RPC" [135]="MSRPC" [139]="NetBIOS"
    [143]="IMAP" [443]="HTTPS" [445]="SMB" [993]="IMAPS" [995]="POP3S"
    [3306]="MySQL" [3389]="RDP" [5432]="PostgreSQL" [5900]="VNC" [6379]="Redis"
    [8080]="HTTP-Proxy" [8443]="HTTPS-Alt" [27017]="MongoDB"
)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

scan_tcp_port() {
    local host="$1"
    local port="$2"
    
    if command -v nc >/dev/null 2>&1; then
        nc -z -w "$TIMEOUT" "$host" "$port" 2>/dev/null
        return $?
    else
        (echo > /dev/tcp/"$host"/"$port") > /dev/null 2>&1
        return $?
    fi
}

scan_udp_port() {
    local host="$1"
    local port="$2"
    
    if command -v nc >/dev/null 2>&1; then
        nc -z -u -w "$TIMEOUT" "$host" "$port" 2>/dev/null
        return $?
    else
        # 仅提示一次，避免逐端口刷屏
        if [ "${UDP_NC_WARNED:-0}" -eq 0 ]; then
            echo "[WARNING] netcat(nc) required for UDP scanning, results will be unreliable"
            UDP_NC_WARNED=1
        fi
        return 1
    fi
}

get_service_name() {
    local port="$1"
    if [ -n "${COMMON_PORTS[$port]}" ]; then
        echo "${COMMON_PORTS[$port]}"
    else
        local service=$(grep -E "^$port/" /etc/services 2>/dev/null | head -1 | awk '{print $1}' | cut -d/ -f1)
        if [ -n "$service" ]; then
            echo "$service"
        else
            echo "Unknown"
        fi
    fi
}

expand_port_range() {
    local range="$1"
    local ports=()
    
    IFS=',' read -ra PARTS <<< "$range"
    for part in "${PARTS[@]}"; do
        if [[ "$part" == *-* ]]; then
            local start=${part%-*}
            local end=${part#*-}
            for ((p=start; p<=end; p++)); do
                ports+=("$p")
            done
        else
            ports+=("$part")
        fi
    done
    
    echo "${ports[@]}"
}

scan_host() {
    local host="$1"
    local ports=($(expand_port_range "$PORT_RANGE"))
    if [ ${#ports[@]} -eq 0 ]; then
        echo "[ERROR] Invalid port range: $PORT_RANGE (expected N or N-M)"
        exit 1
    fi
    local open_ports=()
    local total_ports=${#ports[@]}
    local current=0
    
    echo "=========================================="
    echo "Port Scanner v$VERSION"
    echo "=========================================="
    echo "Target: $host"
    echo "Port Range: $PORT_RANGE ($total_ports ports)"
    echo "Scan Type: $SCAN_TYPE"
    echo "Timeout: ${TIMEOUT}s"
    echo "=========================================="
    echo ""
    echo "Starting scan... (this may take a while)"
    echo ""
    
    for port in "${ports[@]}"; do
        ((current++))
        
        local opened=1
        if [ "$SCAN_TYPE" = "tcp" ]; then
            scan_tcp_port "$host" "$port" && opened=0
        else
            scan_udp_port "$host" "$port" && opened=0
        fi

        if [ $opened -eq 0 ]; then
            local service=$(get_service_name "$port")
            open_ports+=("$port/$service")
            log "OPEN $SCAN_TYPE port $port on $host ($service)"
        fi
        
        printf "\rProgress: %d/%d (%d%%)" "$current" "$total_ports" "$((current * 100 / total_ports))"
    done
    
    echo ""
    echo ""
    echo "=========================================="
    echo "Scan Results for: $host"
    echo "=========================================="
    
    if [ ${#open_ports[@]} -eq 0 ]; then
        echo -e "${YELLOW}No open ports found.${NC}"
    else
        echo -e "${GREEN}Found ${#open_ports[@]} open ports:${NC}"
        echo ""
        printf "%-10s %-20s %s\n" "PORT" "SERVICE" "STATUS"
        printf "%-10s %-20s %s\n" "----" "-------" "------"
        
        for entry in "${open_ports[@]}"; do
            local port=${entry%/*}
            local service=${entry#*/}
            printf "%-10s %-20s %s\n" "$port/$SCAN_TYPE" "$service" "${GREEN}OPEN${NC}"
        done
    fi
    
    echo ""
    echo "=========================================="
    echo "Scan completed: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=========================================="
}

ping_sweep() {
    local subnet="$1"
    # 仅支持 x.x.x.0 形式的网段（不支持 CIDR）
    if ! echo "$subnet" | grep -qE "^[0-9]+\.[0-9]+\.[0-9]+\.0$"; then
        echo "[ERROR] Invalid subnet: $subnet (expected format: 192.168.1.0, CIDR not supported)"
        exit 1
    fi
    echo "=========================================="
    echo "Ping Sweep: $subnet"
    echo "=========================================="

    local alive=0
    for i in {1..254}; do
        local ip="${subnet%.0}.$i"
        if ping -c 1 -W 1 "$ip" >/dev/null 2>&1; then
            local resolved_name
            resolved_name=$(getent hosts "$ip" 2>/dev/null | awk '{print $2}' | head -1)
            [ -z "$resolved_name" ] && resolved_name=$(nslookup "$ip" 2>/dev/null | grep "name =" | awk '{print $4}' | head -1 | sed 's/\.$//')
            if [ -n "$resolved_name" ]; then
                echo -e "${GREEN}[ALIVE]${NC} $ip ($resolved_name)"
            else
                echo -e "${GREEN}[ALIVE]${NC} $ip"
            fi
            ((alive++))
        fi
        printf "\rProgress: %d/254" "$i"
    done
    
    echo ""
    echo "Alive hosts: $alive"
}

service_discovery() {
    local host="$1"
    echo "=========================================="
    echo "Service Discovery: $host"
    echo "=========================================="
    
    if command -v nmap >/dev/null 2>&1; then
        nmap -sV -p 1-1024 "$host"
    else
        echo "nmap is required for detailed service discovery"
        echo "Running basic TCP port scan..."
        scan_host "$host"
    fi
}

while getopts "t:p:T:o:s:dh" opt; do
    case $opt in
        t) TARGET="$OPTARG" ;;
        p) PORT_RANGE="$OPTARG" ;;
        T) SCAN_TYPE="$OPTARG" ;;
        o) TIMEOUT="$OPTARG" ;;
        s) SUBNET="$OPTARG" ;;
        d) SERVICE_DISCOVERY=true ;;
        h) echo "Usage: $0 -t target [-p port_range] [-T tcp|udp] [-o timeout] | -s subnet [-d]"; exit 0 ;;
        \?) echo "Unknown option: -$OPTARG. Use -h for help."; exit 2 ;;
    esac
done

if [ -n "$SUBNET" ] && [ -n "$TARGET" ]; then
    echo "[ERROR] -s and -t are mutually exclusive"
    exit 2
fi

if [ -n "$SUBNET" ]; then
    ping_sweep "$SUBNET"
    exit 0
fi

if [ -z "$TARGET" ]; then
    echo "Target required. Use -t hostname/IP"
    exit 1
fi

if [ "$SERVICE_DISCOVERY" = true ]; then
    service_discovery "$TARGET"
else
    scan_host "$TARGET"
fi