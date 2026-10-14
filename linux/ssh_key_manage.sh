#!/bin/bash
# SSH Key Management Script - Batch SSH key distribution and management
# Author: System Admin
# Usage: ./ssh_key_manage.sh -a add|remove|list|generate|test|info [-k key_file] [-u user] [-h hosts_file] [-p port]

VERSION="1.0"
ACTION=""
SSH_USER="$USER"
SSH_PORT=22
KEY_FILE="$HOME/.ssh/id_rsa.pub"
HOSTS_FILE=""
SSH_DIR=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SUCCESS_COUNT=0
FAIL_COUNT=0

generate_key() {
    local key_type=${1:-rsa}
    local key_bits=${2:-4096}
    
    echo "Generating SSH key pair..."
    ssh-keygen -t "$key_type" -b "$key_bits" -f "$HOME/.ssh/id_$key_type" -N ""
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[OK]${NC} SSH key generated: $HOME/.ssh/id_$key_type"
        KEY_FILE="$HOME/.ssh/id_$key_type.pub"
        return 0
    else
        echo -e "${RED}[FAIL]${NC} Failed to generate SSH key"
        return 1
    fi
}

add_key_to_host() {
    local host="$1"
    local user="$2"
    local key="$3"

    echo "Adding key to $user@$host..."

    # key 内容通过 stdin 传递，避免拼进远程命令导致引号/注释字符注入
    if ssh -p "$SSH_PORT" -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$user@$host" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && cat >> ~/.ssh/authorized_keys && sort -u ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp && mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys" < "$KEY_FILE" 2>/dev/null; then
        echo -e "${GREEN}[SUCCESS]${NC} Key added to $user@$host"
        ((SUCCESS_COUNT++))
        return 0
    else
        echo -e "${RED}[FAILED]${NC} Could not connect to $user@$host"
        ((FAIL_COUNT++))
        return 1
    fi
}

remove_key_from_host() {
    local host="$1"
    local user="$2"
    local key="$3"

    echo "Removing key from $user@$host..."

    # 用固定字符串整行匹配删除，避免按注释 sed 删除（会误删同注释的所有 key，且注释含特殊字符时注入 sed 命令）
    if ssh -p "$SSH_PORT" -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$user@$host" "grep -v -F '$key' ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp && mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys" < /dev/null 2>/dev/null; then
        echo -e "${GREEN}[SUCCESS]${NC} Key removed from $user@$host"
        ((SUCCESS_COUNT++))
        return 0
    else
        echo -e "${RED}[FAILED]${NC} Could not connect to $user@$host"
        ((FAIL_COUNT++))
        return 1
    fi
}

list_keys_on_host() {
    local host="$1"
    local user="$2"
    
    echo "Listing keys on $user@$host:"
    
    if ssh -p "$SSH_PORT" -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$user@$host" "cat ~/.ssh/authorized_keys" 2>/dev/null; then
        echo -e "${GREEN}[SUCCESS]${NC} Listed keys on $user@$host"
        ((SUCCESS_COUNT++))
        return 0
    else
        echo -e "${RED}[FAILED]${NC} Could not connect to $user@$host"
        ((FAIL_COUNT++))
        return 1
    fi
}

batch_operation() {
    local operation="$1"
    
    if [ ! -f "$HOSTS_FILE" ]; then
        echo -e "${RED}[ERROR]${NC} Hosts file not found: $HOSTS_FILE"
        return 1
    fi
    
    if [ "$operation" != "list" ] && [ ! -f "$KEY_FILE" ]; then
        echo -e "${RED}[ERROR]${NC} Key file not found: $KEY_FILE"
        return 1
    fi
    
    local key_content=$(cat "$KEY_FILE" 2>/dev/null)
    local total_hosts=$(grep -v "^#" "$HOSTS_FILE" | grep -v "^$" | wc -l)
    
    echo "=========================================="
    echo "Starting batch $operation operation"
    echo "Total hosts: $total_hosts"
    echo "User: $SSH_USER"
    echo "=========================================="
    
    while IFS= read -r host; do
        [[ -z "$host" || "$host" =~ ^# ]] && continue
        
        case "$operation" in
            add) add_key_to_host "$host" "$SSH_USER" "$key_content" ;;
            remove) remove_key_from_host "$host" "$SSH_USER" "$key_content" ;;
            list) list_keys_on_host "$host" "$SSH_USER" ;;
        esac
    done < "$HOSTS_FILE"
    
    echo ""
    echo "=========================================="
    echo "Operation Summary:"
    echo -e "${GREEN}Success: $SUCCESS_COUNT${NC}"
    echo -e "${RED}Failed:  $FAIL_COUNT${NC}"
    echo "Total:    $total_hosts"
    echo "=========================================="
}

test_connection() {
    local host="$1"
    echo "Testing connection to $host..."
    
    if ssh -p "$SSH_PORT" -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$SSH_USER@$host" "echo 'Connection successful'" 2>/dev/null; then
        echo -e "${GREEN}[SUCCESS]${NC} Connection to $SSH_USER@$host OK"
        return 0
    else
        echo -e "${RED}[FAILED]${NC} Connection to $SSH_USER@$host failed"
        return 1
    fi
}

show_key_info() {
    if [ -f "$KEY_FILE" ]; then
        echo "=========================================="
        echo "SSH Key Information"
        echo "=========================================="
        echo "File: $KEY_FILE"
        echo "Fingerprint:"
        ssh-keygen -lf "$KEY_FILE"
        echo ""
        echo "Key content (first 50 chars):"
        cut -c 1-50 "$KEY_FILE"
        echo "=========================================="
    else
        echo -e "${YELLOW}[WARNING]${NC} No key file found at $KEY_FILE"
    fi
}

while getopts "a:k:u:p:h:t:H" opt; do
    case $opt in
        a) ACTION="$OPTARG" ;;
        k) KEY_FILE="$OPTARG" ;;
        u) SSH_USER="$OPTARG" ;;
        p) SSH_PORT="$OPTARG" ;;
        h) HOSTS_FILE="$OPTARG" ;;
        t) TEST_HOST="$OPTARG" ;;
        H) show_key_info; exit 0 ;;
    esac
done

case "$ACTION" in
    generate)
        generate_key
        ;;
    add|remove|list)
        if [ -z "$HOSTS_FILE" ]; then
            echo "Hosts file required for batch operation. Use -h hosts_file"
            exit 1
        fi
        batch_operation "$ACTION"
        ;;
    test)
        if [ -z "$TEST_HOST" ]; then
            echo "Host required for test. Use -t hostname"
            exit 1
        fi
        test_connection "$TEST_HOST"
        ;;
    info)
        show_key_info
        ;;
    *)
        echo "SSH Key Management Script v$VERSION"
        echo ""
        echo "Usage: $0 -a action [options]"
        echo ""
        echo "Actions:"
        echo "  generate     Generate new SSH key pair"
        echo "  add          Add SSH key to multiple hosts"
        echo "  remove       Remove SSH key from multiple hosts"
        echo "  list         List SSH keys on hosts"
        echo "  test         Test SSH connection"
        echo "  info         Show key information"
        echo ""
        echo "Options:"
        echo "  -k key_file  Path to public key file (default: ~/.ssh/id_rsa.pub)"
        echo "  -u user      SSH username (default: current user)"
        echo "  -p port      SSH port (default: 22)"
        echo "  -h file      Hosts file (one per line)"
        echo "  -t host      Test host"
        echo "  -H           Show key info"
        ;;
esac