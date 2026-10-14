#!/bin/bash
# Docker Compose Infrastructure Deployer
# Deploy common dev/test infrastructure components via docker-compose
# Supports: Redis, MySQL, PostgreSQL, pgvector, MinIO, RustFS, Elasticsearch, MongoDB, Nacos,
#   OpenResty, RabbitMQ, Kafka, RocketMQ, ZooKeeper, Pulsar, Kong,
#   OpenSearch, SkyWalking, Prometheus, Alertmanager, Grafana, Loki, Promtail, Logstash, Kibana,
#   Keycloak, XXL-Job, PowerJob, Sentinel Dashboard
#
# Usage: ./docker_compose_deploy.sh [command] [options]
# Author: System Admin

set -e

# Bash-only (uses declare -A, [[ ]], <(...)); guard against `sh script.sh`
if [ -z "${BASH_VERSION:-}" ]; then
    echo "Error: this script requires bash. Run: bash $0 ... (or ./$0)" >&2
    exit 1
fi

VERSION="2.0"
BASE_DIR="${HOME}/docker-stack"
DATA_DIR="${BASE_DIR}/data"
CONFIG_DIR="${BASE_DIR}/config"
COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"
ENV_FILE="${BASE_DIR}/.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Component versions (latest stable as of 2026-08)
declare -A COMPONENTS=(
    ["redis"]="redis:8.0-alpine"
    ["mysql"]="mysql:8.4"
    ["postgresql"]="postgres:17-alpine"
    ["pgvector"]="pgvector/pgvector:pg17"
    ["minio"]="minio/minio:RELEASE.2025-10-15T17-29-55Z"
    ["elasticsearch"]="docker.elastic.co/elasticsearch/elasticsearch:8.19.16"
    ["mongodb"]="mongo:8.0"
    ["nacos"]="nacos/nacos-server:v3.2.3"
    ["openresty"]="openresty/openresty:1.27.1.2-alpine"
    ["rabbitmq"]="rabbitmq:4.3.3-management"
    ["kafka"]="confluentinc/cp-kafka:8.3.0"
    ["rocketmq"]="apache/rocketmq:5.5.0"
    ["zookeeper"]="zookeeper:3.9.5"
    ["pulsar"]="apachepulsar/pulsar:4.2.3"
    ["kong"]="kong:3.9.3"
    ["opensearch"]="opensearchproject/opensearch:2.19.6"
    ["skywalking"]="apache/skywalking-oap-server:10.4.0"
    ["prometheus"]="prom/prometheus:v3.13.1"
    ["alertmanager"]="prom/alertmanager:v0.29.0"
    ["grafana"]="grafana/grafana-oss:12.4.7"
    ["loki"]="grafana/loki:3.7.2"
    ["promtail"]="grafana/promtail:3.7.2"
    ["logstash"]="docker.elastic.co/logstash/logstash:8.19.19"
    ["kibana"]="docker.elastic.co/kibana/kibana:8.19.16"
    ["keycloak"]="quay.io/keycloak/keycloak:26.6.2"
    ["xxljob"]="xuxueli/xxl-job-admin:3.4.2"
    ["powerjob"]="powerjob/powerjob-server:v5.1.2"
    ["sentinel"]="bladex/sentinel-dashboard:1.8.9"
    ["rustfs"]="rustfs/rustfs:1.0.0-alpha.69"
)

# Component descriptions
declare -A DESCRIPTIONS=(
    ["redis"]="Redis 8.0 - In-memory cache/message broker"
    ["mysql"]="MySQL 8.4 LTS - Relational database"
    ["postgresql"]="PostgreSQL 17 - Advanced relational database"
    ["pgvector"]="pgvector 0.8 (PG 17) - Vector similarity search database"
    ["minio"]="MinIO - S3-compatible object storage"
    ["elasticsearch"]="Elasticsearch 8.19 - Search & analytics engine"
    ["mongodb"]="MongoDB 8.0 - Document database"
    ["nacos"]="Nacos 3.2 - Service discovery & config center"
    ["openresty"]="OpenResty 1.27 - NGINX + Lua web platform"
    ["rabbitmq"]="RabbitMQ 4.3 - Message broker (with management UI)"
    ["kafka"]="Kafka (Confluent 8.3) - Distributed streaming platform"
    ["rocketmq"]="RocketMQ 5.5 - Distributed message queue"
    ["zookeeper"]="ZooKeeper 3.9 - Distributed coordination service"
    ["pulsar"]="Apache Pulsar 4.2 - Cloud-native messaging"
    ["kong"]="Kong 3.9 - API Gateway"
    ["opensearch"]="OpenSearch 2.19 - Search & analytics (fork of ES)"
    ["skywalking"]="SkyWalking 10.4 - APM & service mesh observability"
    ["prometheus"]="Prometheus 3.13 - Monitoring & alerting"
    ["alertmanager"]="Alertmanager 0.29 - Alert routing & notification hub"
    ["grafana"]="Grafana 12.4 - Visualization & dashboards"
    ["loki"]="Loki 3.7 - Log aggregation system"
    ["promtail"]="Promtail 3.7 - Log collection agent for Loki"
    ["logstash"]="Logstash 8.19 - Log processing pipeline"
    ["kibana"]="Kibana 8.19 - Elasticsearch visualization UI"
    ["keycloak"]="Keycloak 26.6 - Identity & access management"
    ["xxljob"]="XXL-Job 3.4 - Distributed task scheduler"
    ["powerjob"]="PowerJob 5.1 - Distributed computing framework"
    ["sentinel"]="Sentinel 1.8 - Flow control & circuit breaker dashboard"
    ["rustfs"]="RustFS - High-performance distributed object storage (S3-compatible)"
)

# Component categories
declare -A CATEGORIES=(
    ["redis"]="Cache/MQ"
    ["mysql"]="Database"
    ["postgresql"]="Database"
    ["pgvector"]="Database"
    ["mongodb"]="Database"
    ["elasticsearch"]="Search"
    ["opensearch"]="Search"
    ["minio"]="Storage"
    ["nacos"]="Config/Registry"
    ["openresty"]="Gateway"
    ["kong"]="Gateway"
    ["rabbitmq"]="Message Queue"
    ["kafka"]="Message Queue"
    ["rocketmq"]="Message Queue"
    ["pulsar"]="Message Queue"
    ["zookeeper"]="Coordination"
    ["skywalking"]="Monitoring"
    ["prometheus"]="Monitoring"
    ["alertmanager"]="Monitoring"
    ["grafana"]="Monitoring"
    ["loki"]="Monitoring"
    ["promtail"]="Logging"
    ["logstash"]="Logging"
    ["kibana"]="Logging"
    ["keycloak"]="Security"
    ["xxljob"]="Scheduler"
    ["powerjob"]="Scheduler"
    ["sentinel"]="Resilience"
    ["rustfs"]="Storage"
)

# Port assignments
declare -A PORTS=(
    ["redis"]="6379"
    ["mysql"]="3306"
    ["postgresql"]="5432"
    ["pgvector"]="5435:5432"
    ["minio"]="9000:9000 9001:9001"
    ["elasticsearch"]="9200:9200 9300:9300"
    ["mongodb"]="27017"
    ["nacos"]="8848:8848 9848:9848"
    ["openresty"]="80:80 443:443"
    ["rabbitmq"]="5672:5672 15672:15672"
    ["kafka"]="9092:9092"
    ["rocketmq"]="8080:8080 9876:9876 10911:10911"
    ["zookeeper"]="2181:2181"
    ["pulsar"]="6650:6650 8080:8080"
    ["kong"]="8000:8000 8443:8443 8001:8001 8444:8444"
    ["opensearch"]="9200:9200 9600:9600"
    ["skywalking"]="11800:11800 12800:12800"
    ["prometheus"]="9090:9090"
    ["alertmanager"]="9093:9093"
    ["grafana"]="3000:3000"
    ["loki"]="3100:3100"
    ["promtail"]="9080:9080"
    ["logstash"]="5044:5044 9600:9600"
    ["kibana"]="5601:5601"
    ["keycloak"]="8080:8080"
    ["xxljob"]="8089:8080"
    ["powerjob"]="7700:7700 10086:10086"
    ["sentinel"]="8858:8858"
    ["rustfs"]="9002:9000 9003:9001"
)

# Default passwords
REDIS_PASS="Redis123!"
MYSQL_ROOT_PASS="Root123!"
POSTGRES_PASS="Postgres123!"
MONGO_ROOT_PASS="Mongo123!"
MINIO_ROOT_USER="admin"
MINIO_ROOT_PASS="Minio123!"
ES_PASS="Elastic123!"
NACOS_PASS="Nacos123!"
RABBIT_USER="admin"
RABBIT_PASS="Rabbit123!"
RABBIT_ERLANG_COOKIE="rabbitmq_cluster_cookie"
KEYCLOAK_ADMIN="admin"
KEYCLOAK_PASS="Keycloak123!"
XXLJOB_USER="admin"
XXLJOB_PASS="123456"
RUSTFS_ACCESS_KEY="rustfs"
RUSTFS_SECRET_KEY="Rustfs123!"

# Compose service name prefixes per component (for per-service start/stop/restart/remove)
# Cluster modes generate multiple services (e.g. kafka1/kafka2/kafka3, es-node1..3, pg-primary/replica)
declare -A SERVICE_PREFIXES=(
    ["redis"]="redis"
    ["mysql"]="mysql"
    ["postgresql"]="postgresql pg-"
    ["pgvector"]="pgvector"
    ["mongodb"]="mongodb mongo"
    ["minio"]="minio"
    ["elasticsearch"]="elasticsearch es-"
    ["kibana"]="kibana"
    ["logstash"]="logstash"
    ["nacos"]="nacos"
    ["openresty"]="openresty"
    ["rabbitmq"]="rabbitmq"
    ["kafka"]="kafka"
    ["rocketmq"]="rocketmq"
    ["zookeeper"]="zookeeper"
    ["pulsar"]="pulsar"
    ["kong"]="kong"
    ["opensearch"]="opensearch"
    ["skywalking"]="skywalking"
    ["prometheus"]="prometheus"
    ["alertmanager"]="alertmanager"
    ["grafana"]="grafana"
    ["loki"]="loki"
    ["promtail"]="promtail"
    ["keycloak"]="keycloak"
    ["xxljob"]="xxl-job"
    ["powerjob"]="powerjob"
    ["sentinel"]="sentinel"
    ["rustfs"]="rustfs"
)

# Network
NETWORK_NAME="docker-stack-net"

# ==============================================================================
# Helper functions
# ==============================================================================

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║     Docker Compose Infrastructure Deployer v$VERSION            ║"
    echo "║     Deploy dev/test infrastructure with one command        ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log()   { echo -e "[$(date '+%H:%M:%S')] $1"; }
info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        error "Docker is not installed. Run docker_install.sh first."
        exit 1
    fi
    if ! docker info >/dev/null 2>&1; then
        error "Cannot connect to Docker daemon. Is Docker running?"
        exit 1
    fi
    if ! docker compose version >/dev/null 2>&1; then
        error "Docker Compose plugin not found. Run docker_install.sh first."
        exit 1
    fi
}

init_dirs() {
    mkdir -p "$DATA_DIR" "$CONFIG_DIR"
    info "Base directory: $BASE_DIR"
    info "Data directory: $DATA_DIR"
}

# ==============================================================================
# Component template generators
# ==============================================================================

gen_redis() {
    local mode="${1:-standalone}"
    cat << 'EOF'

  redis:
    image: redis:8.0-alpine
    container_name: redis
    restart: unless-stopped
    ports:
      - "6379:6379"
    environment:
      - REDIS_PASSWORD=${REDIS_PASS}
    command: redis-server --requirepass ${REDIS_PASS} --appendonly yes --maxmemory 512mb --maxmemory-policy allkeys-lru
    volumes:
      - redis-data:/data
    networks:
      - docker-stack-net
EOF
}

gen_redis_sentinel() {
    cat << 'EOF'

  redis-master:
    image: redis:8.0-alpine
    container_name: redis-master
    restart: unless-stopped
    ports:
      - "6379:6379"
    environment:
      - REDIS_PASSWORD=${REDIS_PASS}
    command: redis-server --requirepass ${REDIS_PASS} --appendonly yes
    volumes:
      - redis-master-data:/data
    networks:
      - docker-stack-net

  redis-slave1:
    image: redis:8.0-alpine
    container_name: redis-slave1
    restart: unless-stopped
    ports:
      - "6380:6379"
    command: redis-server --slaveof redis-master 6379 --masterauth ${REDIS_PASS} --requirepass ${REDIS_PASS}
    depends_on:
      - redis-master
    networks:
      - docker-stack-net

  redis-slave2:
    image: redis:8.0-alpine
    container_name: redis-slave2
    restart: unless-stopped
    ports:
      - "6381:6379"
    command: redis-server --slaveof redis-master 6379 --masterauth ${REDIS_PASS} --requirepass ${REDIS_PASS}
    depends_on:
      - redis-master
    networks:
      - docker-stack-net

  redis-sentinel1:
    image: redis:8.0-alpine
    container_name: redis-sentinel1
    restart: unless-stopped
    ports:
      - "26379:26379"
    command: >
      sh -c "echo 'sentinel monitor mymaster redis-master 6379 2' > /tmp/sentinel.conf &&
             echo 'sentinel auth-pass mymaster ${REDIS_PASS}' >> /tmp/sentinel.conf &&
             echo 'sentinel down-after-milliseconds mymaster 5000' >> /tmp/sentinel.conf &&
             echo 'port 26379' >> /tmp/sentinel.conf &&
             redis-server /tmp/sentinel.conf --sentinel"
    depends_on:
      - redis-master
    networks:
      - docker-stack-net
EOF
}

gen_redis_cluster() {
    cat << 'EOF'

  redis-node1:
    image: redis:8.0-alpine
    container_name: redis-node1
    restart: unless-stopped
    ports:
      - "7001:6379"
      - "17001:16379"
    command: redis-server --requirepass ${REDIS_PASS} --masterauth ${REDIS_PASS} --appendonly yes --cluster-enabled yes --cluster-config-file nodes.conf --cluster-node-timeout 5000
    volumes:
      - redis-node1-data:/data
    networks:
      - docker-stack-net

  redis-node2:
    image: redis:8.0-alpine
    container_name: redis-node2
    restart: unless-stopped
    ports:
      - "7002:6379"
      - "17002:16379"
    command: redis-server --requirepass ${REDIS_PASS} --masterauth ${REDIS_PASS} --appendonly yes --cluster-enabled yes --cluster-config-file nodes.conf --cluster-node-timeout 5000
    volumes:
      - redis-node2-data:/data
    networks:
      - docker-stack-net

  redis-node3:
    image: redis:8.0-alpine
    container_name: redis-node3
    restart: unless-stopped
    ports:
      - "7003:6379"
      - "17003:16379"
    command: redis-server --requirepass ${REDIS_PASS} --masterauth ${REDIS_PASS} --appendonly yes --cluster-enabled yes --cluster-config-file nodes.conf --cluster-node-timeout 5000
    volumes:
      - redis-node3-data:/data
    networks:
      - docker-stack-net

  redis-node4:
    image: redis:8.0-alpine
    container_name: redis-node4
    restart: unless-stopped
    ports:
      - "7004:6379"
      - "17004:16379"
    command: redis-server --requirepass ${REDIS_PASS} --masterauth ${REDIS_PASS} --appendonly yes --cluster-enabled yes --cluster-config-file nodes.conf --cluster-node-timeout 5000
    volumes:
      - redis-node4-data:/data
    networks:
      - docker-stack-net

  redis-node5:
    image: redis:8.0-alpine
    container_name: redis-node5
    restart: unless-stopped
    ports:
      - "7005:6379"
      - "17005:16379"
    command: redis-server --requirepass ${REDIS_PASS} --masterauth ${REDIS_PASS} --appendonly yes --cluster-enabled yes --cluster-config-file nodes.conf --cluster-node-timeout 5000
    volumes:
      - redis-node5-data:/data
    networks:
      - docker-stack-net

  redis-node6:
    image: redis:8.0-alpine
    container_name: redis-node6
    restart: unless-stopped
    ports:
      - "7006:6379"
      - "17006:16379"
    command: redis-server --requirepass ${REDIS_PASS} --masterauth ${REDIS_PASS} --appendonly yes --cluster-enabled yes --cluster-config-file nodes.conf --cluster-node-timeout 5000
    volumes:
      - redis-node6-data:/data
    networks:
      - docker-stack-net
EOF
}

gen_mysql() {
    cat << 'EOF'

  mysql:
    image: mysql:8.4
    container_name: mysql
    restart: unless-stopped
    ports:
      - "3306:3306"
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASS}
      MYSQL_DATABASE: appdb
      TZ: Asia/Shanghai
    command: --default-authentication-plugin=mysql_native_password --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci
    volumes:
      - mysql-data:/var/lib/mysql
    networks:
      - docker-stack-net
EOF
}

gen_mysql_master_slave() {
    cat << 'EOF'

  mysql-master:
    image: mysql:8.4
    container_name: mysql-master
    restart: unless-stopped
    ports:
      - "3306:3306"
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASS}
      MYSQL_DATABASE: appdb
      TZ: Asia/Shanghai
    command: >
      --default-authentication-plugin=mysql_native_password
      --character-set-server=utf8mb4
      --collation-server=utf8mb4_unicode_ci
      --server-id=1
      --log-bin=mysql-bin
      --binlog-format=ROW
      --gtid-mode=ON
      --enforce-gtid-consistency=ON
      --log-slave-updates=ON
    volumes:
      - mysql-master-data:/var/lib/mysql
    networks:
      - docker-stack-net

  mysql-slave:
    image: mysql:8.4
    container_name: mysql-slave
    restart: unless-stopped
    ports:
      - "3307:3306"
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASS}
      TZ: Asia/Shanghai
    command: >
      --default-authentication-plugin=mysql_native_password
      --character-set-server=utf8mb4
      --collation-server=utf8mb4_unicode_ci
      --server-id=2
      --log-bin=mysql-bin
      --binlog-format=ROW
      --gtid-mode=ON
      --enforce-gtid-consistency=ON
      --log-slave-updates=ON
      --read-only=ON
    depends_on:
      - mysql-master
    volumes:
      - mysql-slave-data:/var/lib/mysql
    networks:
      - docker-stack-net
EOF
}

gen_mysql_dual_master() {
    cat << 'EOF'

  mysql-master1:
    image: mysql:8.4
    container_name: mysql-master1
    restart: unless-stopped
    ports:
      - "3306:3306"
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASS}
      MYSQL_DATABASE: appdb
      TZ: Asia/Shanghai
    command: >
      --default-authentication-plugin=mysql_native_password
      --character-set-server=utf8mb4
      --collation-server=utf8mb4_unicode_ci
      --server-id=1
      --log-bin=mysql-bin
      --binlog-format=ROW
      --gtid-mode=ON
      --enforce-gtid-consistency=ON
      --log-slave-updates=ON
      --auto-increment-increment=2
      --auto-increment-offset=1
    volumes:
      - mysql-master1-data:/var/lib/mysql
    networks:
      - docker-stack-net

  mysql-master2:
    image: mysql:8.4
    container_name: mysql-master2
    restart: unless-stopped
    ports:
      - "3307:3306"
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASS}
      MYSQL_DATABASE: appdb
      TZ: Asia/Shanghai
    command: >
      --default-authentication-plugin=mysql_native_password
      --character-set-server=utf8mb4
      --collation-server=utf8mb4_unicode_ci
      --server-id=2
      --log-bin=mysql-bin
      --binlog-format=ROW
      --gtid-mode=ON
      --enforce-gtid-consistency=ON
      --log-slave-updates=ON
      --auto-increment-increment=2
      --auto-increment-offset=2
    depends_on:
      - mysql-master1
    volumes:
      - mysql-master2-data:/var/lib/mysql
    networks:
      - docker-stack-net
EOF
}

gen_postgresql() {
    cat << 'EOF'

  postgresql:
    image: postgres:17-alpine
    container_name: postgresql
    restart: unless-stopped
    ports:
      - "5432:5432"
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASS}
      POSTGRES_DB: appdb
      TZ: Asia/Shanghai
    volumes:
      - postgresql-data:/var/lib/postgresql/data
    networks:
      - docker-stack-net
EOF
}

gen_postgresql_ha() {
    cat << 'EOF'

  pg-primary:
    image: postgres:17-alpine
    container_name: pg-primary
    restart: unless-stopped
    ports:
      - "5432:5432"
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASS}
      POSTGRES_DB: appdb
      TZ: Asia/Shanghai
    command: >
      postgres
      -c wal_level=replica
      -c max_wal_senders=10
      -c max_replication_slots=10
      -c hot_standby=on
    volumes:
      - pg-primary-data:/var/lib/postgresql/data
    networks:
      - docker-stack-net

  pg-replica:
    image: postgres:17-alpine
    container_name: pg-replica
    restart: unless-stopped
    ports:
      - "5433:5432"
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASS}
      PG_PRIMARY_HOST: pg-primary
      PG_PRIMARY_PORT: 5432
      TZ: Asia/Shanghai
    entrypoint: >
      sh -c "
      until pg_isready -h pg-primary -p 5432; do sleep 2; done &&
      if [ ! -f /var/lib/postgresql/data/PG_VERSION ]; then
        PGPASSWORD=${POSTGRES_PASS} pg_basebackup -h pg-primary -U postgres -D /var/lib/postgresql/data -Fp -Xs -P -R &&
        chmod 700 /var/lib/postgresql/data;
      fi &&
      exec postgres -c hot_standby=on
      "
    depends_on:
      - pg-primary
    volumes:
      - pg-replica-data:/var/lib/postgresql/data
    networks:
      - docker-stack-net
EOF
}

gen_pgvector() {
    cat << 'EOF'

  pgvector:
    image: pgvector/pgvector:pg17
    container_name: pgvector
    restart: unless-stopped
    ports:
      - "5435:5432"
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASS}
      POSTGRES_DB: appdb
      TZ: Asia/Shanghai
    volumes:
      - pgvector-data:/var/lib/postgresql/data
    networks:
      - docker-stack-net
EOF
}

gen_mongodb() {
    cat << 'EOF'

  mongodb:
    image: mongo:8.0
    container_name: mongodb
    restart: unless-stopped
    ports:
      - "27017:27017"
    environment:
      MONGO_INITDB_ROOT_USERNAME: root
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_ROOT_PASS}
    volumes:
      - mongodb-data:/data/db
    networks:
      - docker-stack-net
EOF
}

gen_mongodb_rs() {
    cat << 'EOF'

  mongo-primary:
    image: mongo:8.0
    container_name: mongo-primary
    restart: unless-stopped
    ports:
      - "27017:27017"
    environment:
      MONGO_INITDB_ROOT_USERNAME: root
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_ROOT_PASS}
    command: mongod --replSet rs0 --bind_ip_all
    volumes:
      - mongo-primary-data:/data/db
    networks:
      - docker-stack-net

  mongo-secondary1:
    image: mongo:8.0
    container_name: mongo-secondary1
    restart: unless-stopped
    ports:
      - "27018:27017"
    command: mongod --replSet rs0 --bind_ip_all
    volumes:
      - mongo-secondary1-data:/data/db
    networks:
      - docker-stack-net

  mongo-secondary2:
    image: mongo:8.0
    container_name: mongo-secondary2
    restart: unless-stopped
    ports:
      - "27019:27017"
    command: mongod --replSet rs0 --bind_ip_all
    volumes:
      - mongo-secondary2-data:/data/db
    networks:
      - docker-stack-net
EOF
}

gen_minio() {
    cat << 'EOF'

  minio:
    image: minio/minio:RELEASE.2025-10-15T17-29-55Z
    container_name: minio
    restart: unless-stopped
    ports:
      - "9000:9000"
      - "9001:9001"
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASS}
    command: server /data --console-address ":9001"
    volumes:
      - minio-data:/data
    networks:
      - docker-stack-net
EOF
}

gen_minio_distributed() {
    cat << 'EOF'

  minio1:
    image: minio/minio:RELEASE.2025-10-15T17-29-55Z
    container_name: minio1
    restart: unless-stopped
    ports:
      - "9000:9000"
      - "9001:9001"
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASS}
    command: server http://minio{1...4}/data --console-address ":9001"
    volumes:
      - minio1-data:/data
    networks:
      - docker-stack-net

  minio2:
    image: minio/minio:RELEASE.2025-10-15T17-29-55Z
    container_name: minio2
    restart: unless-stopped
    ports:
      - "9002:9000"
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASS}
    command: server http://minio{1...4}/data --console-address ":9001"
    volumes:
      - minio2-data:/data
    networks:
      - docker-stack-net

  minio3:
    image: minio/minio:RELEASE.2025-10-15T17-29-55Z
    container_name: minio3
    restart: unless-stopped
    ports:
      - "9003:9000"
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASS}
    command: server http://minio{1...4}/data --console-address ":9001"
    volumes:
      - minio3-data:/data
    networks:
      - docker-stack-net

  minio4:
    image: minio/minio:RELEASE.2025-10-15T17-29-55Z
    container_name: minio4
    restart: unless-stopped
    ports:
      - "9004:9000"
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASS}
    command: server http://minio{1...4}/data --console-address ":9001"
    volumes:
      - minio4-data:/data
    networks:
      - docker-stack-net
EOF
}

gen_elasticsearch() {
    cat << 'EOF'

  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.19.16
    container_name: elasticsearch
    restart: unless-stopped
    ports:
      - "9200:9200"
      - "9300:9300"
    environment:
      - discovery.type=single-node
      - ELASTIC_PASSWORD=${ES_PASS}
      - xpack.security.enabled=true
      - ES_JAVA_OPTS=-Xms512m -Xmx512m
      - cluster.name=es-cluster
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536
    volumes:
      - elasticsearch-data:/usr/share/elasticsearch/data
    networks:
      - docker-stack-net
EOF
}

gen_elasticsearch_cluster() {
    cat << 'EOF'

  es-node1:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.19.16
    container_name: es-node1
    restart: unless-stopped
    ports:
      - "9200:9200"
      - "9300:9300"
    environment:
      - node.name=es-node1
      - cluster.name=es-cluster
      - discovery.seed_hosts=es-node2,es-node3
      - cluster.initial_master_nodes=es-node1,es-node2,es-node3
      - ELASTIC_PASSWORD=${ES_PASS}
      - xpack.security.enabled=true
      - xpack.security.transport.ssl.enabled=true
      - ES_JAVA_OPTS=-Xms512m -Xmx512m
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536
    volumes:
      - es-node1-data:/usr/share/elasticsearch/data
    networks:
      - docker-stack-net

  es-node2:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.19.16
    container_name: es-node2
    restart: unless-stopped
    ports:
      - "9201:9200"
    environment:
      - node.name=es-node2
      - cluster.name=es-cluster
      - discovery.seed_hosts=es-node1,es-node3
      - cluster.initial_master_nodes=es-node1,es-node2,es-node3
      - ELASTIC_PASSWORD=${ES_PASS}
      - xpack.security.enabled=true
      - ES_JAVA_OPTS=-Xms512m -Xmx512m
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536
    volumes:
      - es-node2-data:/usr/share/elasticsearch/data
    networks:
      - docker-stack-net

  es-node3:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.19.16
    container_name: es-node3
    restart: unless-stopped
    ports:
      - "9202:9200"
    environment:
      - node.name=es-node3
      - cluster.name=es-cluster
      - discovery.seed_hosts=es-node1,es-node2
      - cluster.initial_master_nodes=es-node1,es-node2,es-node3
      - ELASTIC_PASSWORD=${ES_PASS}
      - xpack.security.enabled=true
      - ES_JAVA_OPTS=-Xms512m -Xmx512m
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536
    volumes:
      - es-node3-data:/usr/share/elasticsearch/data
    networks:
      - docker-stack-net
EOF
}

gen_kibana() {
    cat << 'EOF'

  kibana:
    image: docker.elastic.co/kibana/kibana:8.19.16
    container_name: kibana
    restart: unless-stopped
    ports:
      - "5601:5601"
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
      - ELASTICSEARCH_USERNAME=elastic
      - ELASTICSEARCH_PASSWORD=${ES_PASS}
    depends_on:
      - elasticsearch
    networks:
      - docker-stack-net
EOF
}

gen_logstash() {
    cat << 'EOF'

  logstash:
    image: docker.elastic.co/logstash/logstash:8.19.19
    container_name: logstash
    restart: unless-stopped
    ports:
      - "5044:5044"
      - "9600:9600"
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
      - ELASTICSEARCH_PASSWORD=${ES_PASS}
    depends_on:
      - elasticsearch
    networks:
      - docker-stack-net
EOF
}

gen_nacos() {
    cat << 'EOF'

  nacos:
    image: nacos/nacos-server:v3.2.3
    container_name: nacos
    restart: unless-stopped
    ports:
      - "8848:8848"
      - "9848:9848"
    environment:
      - MODE=standalone
      - NACOS_AUTH_ENABLE=true
      - NACOS_AUTH_TOKEN=${NACOS_PASS}
      - JVM_XMS=256m
      - JVM_XMX=512m
    volumes:
      - nacos-data:/home/nacos/data
    networks:
      - docker-stack-net
EOF
}

gen_nacos_cluster() {
    cat << 'EOF'

  nacos1:
    image: nacos/nacos-server:v3.2.3
    container_name: nacos1
    restart: unless-stopped
    ports:
      - "8848:8848"
      - "9848:9848"
    environment:
      - MODE=cluster
      - NACOS_SERVERS=nacos1:8848 nacos2:8848 nacos3:8848
      - NACOS_AUTH_ENABLE=true
      - NACOS_AUTH_TOKEN=${NACOS_PASS}
      - JVM_XMS=256m
      - JVM_XMX=512m
    volumes:
      - nacos1-data:/home/nacos/data
    networks:
      - docker-stack-net

  nacos2:
    image: nacos/nacos-server:v3.2.3
    container_name: nacos2
    restart: unless-stopped
    ports:
      - "8849:8848"
      - "9849:9848"
    environment:
      - MODE=cluster
      - NACOS_SERVERS=nacos1:8848 nacos2:8848 nacos3:8848
      - NACOS_AUTH_ENABLE=true
      - NACOS_AUTH_TOKEN=${NACOS_PASS}
      - JVM_XMS=256m
      - JVM_XMX=512m
    volumes:
      - nacos2-data:/home/nacos/data
    networks:
      - docker-stack-net

  nacos3:
    image: nacos/nacos-server:v3.2.3
    container_name: nacos3
    restart: unless-stopped
    ports:
      - "8850:8848"
      - "9850:9848"
    environment:
      - MODE=cluster
      - NACOS_SERVERS=nacos1:8848 nacos2:8848 nacos3:8848
      - NACOS_AUTH_ENABLE=true
      - NACOS_AUTH_TOKEN=${NACOS_PASS}
      - JVM_XMS=256m
      - JVM_XMX=512m
    volumes:
      - nacos3-data:/home/nacos/data
    networks:
      - docker-stack-net
EOF
}

gen_openresty() {
    cat << 'EOF'

  openresty:
    image: openresty/openresty:1.27.1.2-alpine
    container_name: openresty
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - openresty-conf:/usr/local/openresty/nginx/conf
      - openresty-logs:/usr/local/openresty/nginx/logs
      - openresty-html:/usr/local/openresty/nginx/html
    networks:
      - docker-stack-net
EOF
}

gen_rabbitmq() {
    cat << 'EOF'

  rabbitmq:
    image: rabbitmq:4.3.3-management
    container_name: rabbitmq
    restart: unless-stopped
    ports:
      - "5672:5672"
      - "15672:15672"
    environment:
      RABBITMQ_DEFAULT_USER: ${RABBIT_USER}
      RABBITMQ_DEFAULT_PASS: ${RABBIT_PASS}
    volumes:
      - rabbitmq-data:/var/lib/rabbitmq
    networks:
      - docker-stack-net
EOF
}

gen_rabbitmq_cluster() {
    cat << 'EOF'

  rabbitmq1:
    image: rabbitmq:4.3.3-management
    container_name: rabbitmq1
    restart: unless-stopped
    hostname: rabbitmq1
    ports:
      - "5672:5672"
      - "15672:15672"
    environment:
      RABBITMQ_DEFAULT_USER: ${RABBIT_USER}
      RABBITMQ_DEFAULT_PASS: ${RABBIT_PASS}
      RABBITMQ_ERLANG_COOKIE: ${RABBIT_ERLANG_COOKIE}
    volumes:
      - rabbitmq1-data:/var/lib/rabbitmq
    networks:
      - docker-stack-net

  rabbitmq2:
    image: rabbitmq:4.3.3-management
    container_name: rabbitmq2
    restart: unless-stopped
    hostname: rabbitmq2
    ports:
      - "5673:5672"
      - "15673:15672"
    environment:
      RABBITMQ_DEFAULT_USER: ${RABBIT_USER}
      RABBITMQ_DEFAULT_PASS: ${RABBIT_PASS}
      RABBITMQ_ERLANG_COOKIE: ${RABBIT_ERLANG_COOKIE}
    depends_on:
      - rabbitmq1
    volumes:
      - rabbitmq2-data:/var/lib/rabbitmq
    networks:
      - docker-stack-net

  rabbitmq3:
    image: rabbitmq:4.3.3-management
    container_name: rabbitmq3
    restart: unless-stopped
    hostname: rabbitmq3
    ports:
      - "5674:5672"
      - "15674:15672"
    environment:
      RABBITMQ_DEFAULT_USER: ${RABBIT_USER}
      RABBITMQ_DEFAULT_PASS: ${RABBIT_PASS}
      RABBITMQ_ERLANG_COOKIE: ${RABBIT_ERLANG_COOKIE}
    depends_on:
      - rabbitmq1
    volumes:
      - rabbitmq3-data:/var/lib/rabbitmq
    networks:
      - docker-stack-net
EOF
}

gen_kafka() {
    cat << 'EOF'

  kafka:
    image: confluentinc/cp-kafka:8.3.0
    container_name: kafka
    restart: unless-stopped
    ports:
      - "9092:9092"
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://localhost:9092
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: "true"
    depends_on:
      - zookeeper
    volumes:
      - kafka-data:/var/lib/kafka/data
    networks:
      - docker-stack-net
EOF
}

gen_kafka_cluster() {
    cat << 'EOF'

  kafka1:
    image: confluentinc/cp-kafka:8.3.0
    container_name: kafka1
    restart: unless-stopped
    ports:
      - "9092:9092"
    environment:
      KAFKA_NODE_ID: 1
      KAFKA_PROCESS_ROLES: "broker,controller"
      KAFKA_CONTROLLER_QUORUM_VOTERS: "1@kafka1:9093,2@kafka2:9093,3@kafka3:9093"
      KAFKA_LISTENERS: "PLAINTEXT://:9092,CONTROLLER://:9093"
      KAFKA_ADVERTISED_LISTENERS: "PLAINTEXT://kafka1:9092"
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT"
      KAFKA_CONTROLLER_LISTENER_NAMES: "CONTROLLER"
      KAFKA_INTER_BROKER_LISTENER_NAME: "PLAINTEXT"
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 3
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 3
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 2
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: "true"
      CLUSTER_ID: "MkU3OEVBNTcwNTJENDM2Qk"
    volumes:
      - kafka1-data:/var/lib/kafka/data
    networks:
      - docker-stack-net

  kafka2:
    image: confluentinc/cp-kafka:8.3.0
    container_name: kafka2
    restart: unless-stopped
    ports:
      - "9093:9092"
    environment:
      KAFKA_NODE_ID: 2
      KAFKA_PROCESS_ROLES: "broker,controller"
      KAFKA_CONTROLLER_QUORUM_VOTERS: "1@kafka1:9093,2@kafka2:9093,3@kafka3:9093"
      KAFKA_LISTENERS: "PLAINTEXT://:9092,CONTROLLER://:9093"
      KAFKA_ADVERTISED_LISTENERS: "PLAINTEXT://kafka2:9092"
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT"
      KAFKA_CONTROLLER_LISTENER_NAMES: "CONTROLLER"
      KAFKA_INTER_BROKER_LISTENER_NAME: "PLAINTEXT"
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 3
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 3
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 2
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: "true"
      CLUSTER_ID: "MkU3OEVBNTcwNTJENDM2Qk"
    volumes:
      - kafka2-data:/var/lib/kafka/data
    networks:
      - docker-stack-net

  kafka3:
    image: confluentinc/cp-kafka:8.3.0
    container_name: kafka3
    restart: unless-stopped
    ports:
      - "9094:9092"
    environment:
      KAFKA_NODE_ID: 3
      KAFKA_PROCESS_ROLES: "broker,controller"
      KAFKA_CONTROLLER_QUORUM_VOTERS: "1@kafka1:9093,2@kafka2:9093,3@kafka3:9093"
      KAFKA_LISTENERS: "PLAINTEXT://:9092,CONTROLLER://:9093"
      KAFKA_ADVERTISED_LISTENERS: "PLAINTEXT://kafka3:9092"
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT"
      KAFKA_CONTROLLER_LISTENER_NAMES: "CONTROLLER"
      KAFKA_INTER_BROKER_LISTENER_NAME: "PLAINTEXT"
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 3
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 3
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 2
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: "true"
      CLUSTER_ID: "MkU3OEVBNTcwNTJENDM2Qk"
    volumes:
      - kafka3-data:/var/lib/kafka/data
    networks:
      - docker-stack-net
EOF
}

gen_zookeeper() {
    cat << 'EOF'

  zookeeper:
    image: zookeeper:3.9.5
    container_name: zookeeper
    restart: unless-stopped
    ports:
      - "2181:2181"
    environment:
      ZOO_4LW_COMMANDS_WHITELIST: "*"
    volumes:
      - zookeeper-data:/data
      - zookeeper-logs:/datalog
    networks:
      - docker-stack-net
EOF
}

gen_zookeeper_cluster() {
    cat << 'EOF'

  zookeeper1:
    image: zookeeper:3.9.5
    container_name: zookeeper1
    restart: unless-stopped
    hostname: zookeeper1
    ports:
      - "2181:2181"
    environment:
      ZOO_MY_ID: 1
      ZOO_SERVERS: server.1=zookeeper1:2888:3888;2181 server.2=zookeeper2:2888:3888;2181 server.3=zookeeper3:2888:3888;2181
      ZOO_4LW_COMMANDS_WHITELIST: "*"
    volumes:
      - zookeeper1-data:/data
      - zookeeper1-logs:/datalog
    networks:
      - docker-stack-net

  zookeeper2:
    image: zookeeper:3.9.5
    container_name: zookeeper2
    restart: unless-stopped
    hostname: zookeeper2
    ports:
      - "2182:2181"
    environment:
      ZOO_MY_ID: 2
      ZOO_SERVERS: server.1=zookeeper1:2888:3888;2181 server.2=zookeeper2:2888:3888;2181 server.3=zookeeper3:2888:3888;2181
      ZOO_4LW_COMMANDS_WHITELIST: "*"
    volumes:
      - zookeeper2-data:/data
      - zookeeper2-logs:/datalog
    networks:
      - docker-stack-net

  zookeeper3:
    image: zookeeper:3.9.5
    container_name: zookeeper3
    restart: unless-stopped
    hostname: zookeeper3
    ports:
      - "2183:2181"
    environment:
      ZOO_MY_ID: 3
      ZOO_SERVERS: server.1=zookeeper1:2888:3888;2181 server.2=zookeeper2:2888:3888;2181 server.3=zookeeper3:2888:3888;2181
      ZOO_4LW_COMMANDS_WHITELIST: "*"
    volumes:
      - zookeeper3-data:/data
      - zookeeper3-logs:/datalog
    networks:
      - docker-stack-net
EOF
}

gen_rocketmq() {
    cat << 'EOF'

  rocketmq-namesrv:
    image: apache/rocketmq:5.5.0
    container_name: rocketmq-namesrv
    restart: unless-stopped
    ports:
      - "9876:9876"
    command: sh mqnamesrv
    volumes:
      - rocketmq-namesrv-logs:/home/rocketmq/logs
    networks:
      - docker-stack-net

  rocketmq-broker:
    image: apache/rocketmq:5.5.0
    container_name: rocketmq-broker
    restart: unless-stopped
    ports:
      - "10911:10911"
      - "10909:10909"
    environment:
      NAMESRV_ADDR: "rocketmq-namesrv:9876"
    command: sh mqbroker -n rocketmq-namesrv:9876 --enable-proxy
    depends_on:
      - rocketmq-namesrv
    volumes:
      - rocketmq-broker-data:/home/rocketmq/store
      - rocketmq-broker-logs:/home/rocketmq/logs
    networks:
      - docker-stack-net
EOF
}

gen_rocketmq_cluster() {
    cat << 'EOF'

  rocketmq-namesrv1:
    image: apache/rocketmq:5.5.0
    container_name: rocketmq-namesrv1
    restart: unless-stopped
    ports:
      - "9876:9876"
    command: sh mqnamesrv
    volumes:
      - rocketmq-namesrv1-logs:/home/rocketmq/logs
    networks:
      - docker-stack-net

  rocketmq-namesrv2:
    image: apache/rocketmq:5.5.0
    container_name: rocketmq-namesrv2
    restart: unless-stopped
    ports:
      - "9877:9876"
    command: sh mqnamesrv
    volumes:
      - rocketmq-namesrv2-logs:/home/rocketmq/logs
    networks:
      - docker-stack-net

  rocketmq-broker1:
    image: apache/rocketmq:5.5.0
    container_name: rocketmq-broker1
    restart: unless-stopped
    ports:
      - "10911:10911"
    environment:
      NAMESRV_ADDR: "rocketmq-namesrv1:9876;rocketmq-namesrv2:9876"
    command: sh mqbroker -n rocketmq-namesrv1:9876;rocketmq-namesrv2:9876 --enable-proxy -c /home/rocketmq/rocketmq/conf/broker.conf
    depends_on:
      - rocketmq-namesrv1
      - rocketmq-namesrv2
    volumes:
      - rocketmq-broker1-data:/home/rocketmq/store
      - rocketmq-broker1-logs:/home/rocketmq/logs
    networks:
      - docker-stack-net

  rocketmq-broker2:
    image: apache/rocketmq:5.5.0
    container_name: rocketmq-broker2
    restart: unless-stopped
    ports:
      - "10912:10911"
    environment:
      NAMESRV_ADDR: "rocketmq-namesrv1:9876;rocketmq-namesrv2:9876"
    command: sh mqbroker -n rocketmq-namesrv1:9876;rocketmq-namesrv2:9876 --enable-proxy -c /home/rocketmq/rocketmq/conf/broker.conf
    depends_on:
      - rocketmq-namesrv1
      - rocketmq-namesrv2
    volumes:
      - rocketmq-broker2-data:/home/rocketmq/store
      - rocketmq-broker2-logs:/home/rocketmq/logs
    networks:
      - docker-stack-net

  rocketmq-broker3:
    image: apache/rocketmq:5.5.0
    container_name: rocketmq-broker3
    restart: unless-stopped
    ports:
      - "10913:10911"
    environment:
      NAMESRV_ADDR: "rocketmq-namesrv1:9876;rocketmq-namesrv2:9876"
    command: sh mqbroker -n rocketmq-namesrv1:9876;rocketmq-namesrv2:9876 --enable-proxy -c /home/rocketmq/rocketmq/conf/broker.conf
    depends_on:
      - rocketmq-namesrv1
      - rocketmq-namesrv2
    volumes:
      - rocketmq-broker3-data:/home/rocketmq/store
      - rocketmq-broker3-logs:/home/rocketmq/logs
    networks:
      - docker-stack-net
EOF
}

gen_pulsar() {
    cat << 'EOF'

  pulsar:
    image: apachepulsar/pulsar:4.2.3
    container_name: pulsar
    restart: unless-stopped
    ports:
      - "6650:6650"
      - "8080:8080"
    command: bin/pulsar standalone
    volumes:
      - pulsar-data:/pulsar/data
    networks:
      - docker-stack-net
EOF
}

gen_kong() {
    cat << 'EOF'

  kong-database:
    image: postgres:17-alpine
    container_name: kong-database
    restart: unless-stopped
    ports:
      - "5433:5432"
    environment:
      POSTGRES_USER: kong
      POSTGRES_DB: kong
      POSTGRES_PASSWORD: kong
    volumes:
      - kong-db-data:/var/lib/postgresql/data
    networks:
      - docker-stack-net

  kong:
    image: kong:3.9.3
    container_name: kong
    restart: unless-stopped
    ports:
      - "8000:8000"
      - "8443:8443"
      - "8001:8001"
      - "8444:8444"
    environment:
      KONG_DATABASE: postgres
      KONG_PG_HOST: kong-database
      KONG_PG_USER: kong
      KONG_PG_PASSWORD: kong
      KONG_PG_DATABASE: kong
      KONG_PROXY_ACCESS_LOG: /dev/stdout
      KONG_ADMIN_ACCESS_LOG: /dev/stdout
      KONG_PROXY_ERROR_LOG: /dev/stderr
      KONG_ADMIN_ERROR_LOG: /dev/stderr
      KONG_ADMIN_LISTEN: 0.0.0.0:8001, 0.0.0.0:8444 ssl
    depends_on:
      - kong-database
    networks:
      - docker-stack-net
EOF
}

gen_opensearch() {
    cat << 'EOF'

  opensearch:
    image: opensearchproject/opensearch:2.19.6
    container_name: opensearch
    restart: unless-stopped
    ports:
      - "9201:9200"
      - "9600:9600"
    environment:
      - discovery.type=single-node
      - bootstrap.memory_lock=true
      - OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m
      - "DISABLE_SECURITY_PLUGIN=false"
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - opensearch-data:/usr/share/opensearch/data
    networks:
      - docker-stack-net
EOF
}

gen_opensearch_cluster() {
    cat << 'EOF'

  opensearch-node1:
    image: opensearchproject/opensearch:2.19.6
    container_name: opensearch-node1
    restart: unless-stopped
    ports:
      - "9201:9200"
      - "9600:9600"
    environment:
      - cluster.name=opensearch-cluster
      - node.name=opensearch-node1
      - discovery.seed_hosts=opensearch-node1,opensearch-node2,opensearch-node3
      - cluster.initial_cluster_manager_nodes=opensearch-node1,opensearch-node2,opensearch-node3
      - bootstrap.memory_lock=true
      - OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m
      - "DISABLE_SECURITY_PLUGIN=false"
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - opensearch-node1-data:/usr/share/opensearch/data
    networks:
      - docker-stack-net

  opensearch-node2:
    image: opensearchproject/opensearch:2.19.6
    container_name: opensearch-node2
    restart: unless-stopped
    ports:
      - "9202:9200"
    environment:
      - cluster.name=opensearch-cluster
      - node.name=opensearch-node2
      - discovery.seed_hosts=opensearch-node1,opensearch-node2,opensearch-node3
      - cluster.initial_cluster_manager_nodes=opensearch-node1,opensearch-node2,opensearch-node3
      - bootstrap.memory_lock=true
      - OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m
      - "DISABLE_SECURITY_PLUGIN=false"
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - opensearch-node2-data:/usr/share/opensearch/data
    networks:
      - docker-stack-net

  opensearch-node3:
    image: opensearchproject/opensearch:2.19.6
    container_name: opensearch-node3
    restart: unless-stopped
    ports:
      - "9203:9200"
    environment:
      - cluster.name=opensearch-cluster
      - node.name=opensearch-node3
      - discovery.seed_hosts=opensearch-node1,opensearch-node2,opensearch-node3
      - cluster.initial_cluster_manager_nodes=opensearch-node1,opensearch-node2,opensearch-node3
      - bootstrap.memory_lock=true
      - OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m
      - "DISABLE_SECURITY_PLUGIN=false"
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - opensearch-node3-data:/usr/share/opensearch/data
    networks:
      - docker-stack-net
EOF
}

gen_skywalking() {
    cat << 'EOF'

  skywalking-oap:
    image: apache/skywalking-oap-server:10.4.0
    container_name: skywalking-oap
    restart: unless-stopped
    ports:
      - "11800:11800"
      - "12800:12800"
    environment:
      SW_STORAGE: elasticsearch
      SW_STORAGE_ES_CLUSTER_NODES: elasticsearch:9200
      SW_HEALTH_CHECKER: default
      SW_TELEMETRY: prometheus
      JAVA_OPTS: "-Xms512m -Xmx512m"
    depends_on:
      - elasticsearch
    networks:
      - docker-stack-net

  skywalking-ui:
    image: apache/skywalking-ui:10.4.0
    container_name: skywalking-ui
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      SW_OAP_ADDRESS: http://skywalking-oap:12800
    depends_on:
      - skywalking-oap
    networks:
      - docker-stack-net
EOF
}

gen_prometheus() {
    cat << 'EOF'

  prometheus:
    image: prom/prometheus:v3.13.1
    container_name: prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
      - '--web.enable-lifecycle'
    volumes:
      - prometheus-data:/prometheus
      - prometheus-conf:/etc/prometheus
    networks:
      - docker-stack-net
EOF
}

gen_alertmanager() {
    cat << 'EOF'

  alertmanager:
    image: prom/alertmanager:v0.29.0
    container_name: alertmanager
    restart: unless-stopped
    ports:
      - "9093:9093"
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
      - '--storage.path=/alertmanager'
      - '--web.enable-lifecycle'
    volumes:
      - alertmanager-data:/alertmanager
      - alertmanager-conf:/etc/alertmanager
    networks:
      - docker-stack-net
EOF
}

gen_grafana() {
    cat << 'EOF'

  grafana:
    image: grafana/grafana-oss:12.4.7
    container_name: grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: admin
      GF_INSTALL_PLUGINS: grafana-piechart-panel
    volumes:
      - grafana-data:/var/lib/grafana
    networks:
      - docker-stack-net
EOF
}

gen_loki() {
    cat << 'EOF'

  loki:
    image: grafana/loki:3.7.2
    container_name: loki
    restart: unless-stopped
    ports:
      - "3100:3100"
    command: -config.file=/etc/loki/local-config.yaml
    volumes:
      - loki-data:/loki
    networks:
      - docker-stack-net
EOF
}

gen_promtail() {
    cat << 'EOF'

  promtail:
    image: grafana/promtail:3.7.2
    container_name: promtail
    restart: unless-stopped
    ports:
      - "9080:9080"
    # 读取容器日志需要挂载 docker.sock 与容器日志目录；
    # 如遇 permission denied，可在本服务下增加 user: "0"
    command: -config.file=/etc/promtail/config.yml
    volumes:
      - promtail-conf:/etc/promtail
      - promtail-data:/promtail
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
    networks:
      - docker-stack-net
EOF
}

gen_keycloak() {
    cat << 'EOF'

  keycloak:
    image: quay.io/keycloak/keycloak:26.6.2
    container_name: keycloak
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      KEYCLOAK_ADMIN: ${KEYCLOAK_ADMIN}
      KEYCLOAK_ADMIN_PASSWORD: ${KEYCLOAK_PASS}
    command: start-dev
    volumes:
      - keycloak-data:/opt/keycloak/data
    networks:
      - docker-stack-net
EOF
}

gen_keycloak_cluster() {
    cat << 'EOF'

  keycloak-db:
    image: postgres:17-alpine
    container_name: keycloak-db
    restart: unless-stopped
    ports:
      - "5434:5432"
    environment:
      POSTGRES_DB: keycloak
      POSTGRES_USER: keycloak
      POSTGRES_PASSWORD: ${POSTGRES_PASS}
    volumes:
      - keycloak-db-data:/var/lib/postgresql/data
    networks:
      - docker-stack-net

  keycloak1:
    image: quay.io/keycloak/keycloak:26.6.2
    container_name: keycloak1
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      KEYCLOAK_ADMIN: ${KEYCLOAK_ADMIN}
      KEYCLOAK_ADMIN_PASSWORD: ${KEYCLOAK_PASS}
      KC_DB: postgres
      KC_DB_URL: jdbc:postgresql://keycloak-db:5432/keycloak
      KC_DB_USERNAME: keycloak
      KC_DB_PASSWORD: ${POSTGRES_PASS}
      KC_HOSTNAME: keycloak1
      KC_CACHE: ispn
      KC_CACHE_STACK: kubernetes
    command: start --optimized --hostname=keycloak1 --http-enabled=true
    depends_on:
      - keycloak-db
    networks:
      - docker-stack-net

  keycloak2:
    image: quay.io/keycloak/keycloak:26.6.2
    container_name: keycloak2
    restart: unless-stopped
    ports:
      - "8081:8080"
    environment:
      KEYCLOAK_ADMIN: ${KEYCLOAK_ADMIN}
      KEYCLOAK_ADMIN_PASSWORD: ${KEYCLOAK_PASS}
      KC_DB: postgres
      KC_DB_URL: jdbc:postgresql://keycloak-db:5432/keycloak
      KC_DB_USERNAME: keycloak
      KC_DB_PASSWORD: ${POSTGRES_PASS}
      KC_HOSTNAME: keycloak2
      KC_CACHE: ispn
      KC_CACHE_STACK: kubernetes
    command: start --optimized --hostname=keycloak2 --http-enabled=true
    depends_on:
      - keycloak-db
    networks:
      - docker-stack-net
EOF
}

gen_xxljob() {
    cat << 'EOF'

  xxl-job-admin:
    image: xuxueli/xxl-job-admin:3.4.2
    container_name: xxl-job-admin
    restart: unless-stopped
    ports:
      - "8089:8080"
    environment:
      PARAMS: "--spring.datasource.url=jdbc:mysql://mysql:3306/xxl_job?Unicode=true&characterEncoding=UTF-8 --spring.datasource.username=root --spring.datasource.password=${MYSQL_ROOT_PASS}"
    depends_on:
      - mysql
    networks:
      - docker-stack-net
EOF
}

gen_powerjob() {
    cat << 'EOF'

  powerjob-server:
    image: powerjob/powerjob-server:v5.1.2
    container_name: powerjob-server
    restart: unless-stopped
    ports:
      - "7700:7700"
      - "10086:10086"
    environment:
      PARAMS: "--spring.datasource.core.url=jdbc:mysql://mysql:3306/powerjob?Unicode=true&characterEncoding=UTF-8 --spring.datasource.core.username=root --spring.datasource.core.password=${MYSQL_ROOT_PASS} --oms.container.retention=1 --oms.instanceinfo.retention=1"
    depends_on:
      - mysql
    networks:
      - docker-stack-net
EOF
}

gen_sentinel() {
    cat << 'EOF'

  sentinel-dashboard:
    image: bladex/sentinel-dashboard:1.8.9
    container_name: sentinel-dashboard
    restart: unless-stopped
    ports:
      - "8858:8858"
    networks:
      - docker-stack-net
EOF
}

gen_rustfs() {
    cat << 'EOF'

  rustfs:
    image: rustfs/rustfs:1.0.0-alpha.69
    container_name: rustfs
    restart: unless-stopped
    ports:
      - "9002:9000"
      - "9003:9001"
    environment:
      - RUSTFS_ADDRESS=:9000
      - RUSTFS_CONSOLE_ENABLE=true
      - RUSTFS_CONSOLE_ADDRESS=0.0.0.0:9001
      - RUSTFS_ACCESS_KEY=${RUSTFS_ACCESS_KEY}
      - RUSTFS_SECRET_KEY=${RUSTFS_SECRET_KEY}
    volumes:
      - rustfs-data:/data
      - rustfs-logs:/logs
    networks:
      - docker-stack-net
EOF
}

# ==============================================================================
# Volume name collector
# ==============================================================================
VOLUME_NAMES=""

add_volume() {
    if [ -n "$VOLUME_NAMES" ]; then
        VOLUME_NAMES="${VOLUME_NAMES},$1"
    else
        VOLUME_NAMES="$1"
    fi
}

# Write a default config file; existing files are never overwritten.
# Usage: write_default_config <path> << 'EOF' ... EOF
write_default_config() {
    local file="$1"
    mkdir -p "$(dirname "$file")"
    if [ -f "$file" ]; then
        info "Config already exists, keeping it: $file"
        return 0
    fi
    cat > "$file"
    ok "Default config generated: $file"
}

# ==============================================================================
# Generate docker-compose.yml
# ==============================================================================

generate_compose() {
    local selected="$1"
    local redis_mode="$2"

    info "Generating docker-compose.yml..."

    # Build header
    cat > "$COMPOSE_FILE" << EOF
# Docker Compose for Dev/Test Infrastructure
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# Selected: $selected

services:
EOF

    # Build .env file
    cat > "$ENV_FILE" << EOF
# Environment variables for docker-stack
REDIS_PASS=${REDIS_PASS}
MYSQL_ROOT_PASS=${MYSQL_ROOT_PASS}
POSTGRES_PASS=${POSTGRES_PASS}
MONGO_ROOT_PASS=${MONGO_ROOT_PASS}
MINIO_ROOT_USER=${MINIO_ROOT_USER}
MINIO_ROOT_PASS=${MINIO_ROOT_PASS}
ES_PASS=${ES_PASS}
NACOS_PASS=${NACOS_PASS}
RABBIT_USER=${RABBIT_USER}
RABBIT_PASS=${RABBIT_PASS}
RABBIT_ERLANG_COOKIE=${RABBIT_ERLANG_COOKIE}
KEYCLOAK_ADMIN=${KEYCLOAK_ADMIN}
KEYCLOAK_PASS=${KEYCLOAK_PASS}
XXLJOB_USER=${XXLJOB_USER}
XXLJOB_PASS=${XXLJOB_PASS}
RUSTFS_ACCESS_KEY=${RUSTFS_ACCESS_KEY}
RUSTFS_SECRET_KEY=${RUSTFS_SECRET_KEY}
EOF

    VOLUME_NAMES=""

    # Generate services
    for comp in $selected; do
        case "$comp" in
            redis)
                case "$redis_mode" in
                    sentinel)
                        gen_redis_sentinel >> "$COMPOSE_FILE"
                        add_volume "redis-master-data"
                        ;;
                    cluster)
                        gen_redis_cluster >> "$COMPOSE_FILE"
                        for i in 1 2 3 4 5 6; do add_volume "redis-node${i}-data"; done
                        ;;
                    *)
                        gen_redis >> "$COMPOSE_FILE"
                        add_volume "redis-data"
                        ;;
                esac
                ;;
            mysql)
                gen_mysql >> "$COMPOSE_FILE"
                add_volume "mysql-data"
                ;;
            mysql:master-slave)
                gen_mysql_master_slave >> "$COMPOSE_FILE"
                add_volume "mysql-master-data"
                add_volume "mysql-slave-data"
                ;;
            mysql:dual-master)
                gen_mysql_dual_master >> "$COMPOSE_FILE"
                add_volume "mysql-master1-data"
                add_volume "mysql-master2-data"
                ;;
            postgresql)
                gen_postgresql >> "$COMPOSE_FILE"
                add_volume "postgresql-data"
                ;;
            postgresql:ha)
                gen_postgresql_ha >> "$COMPOSE_FILE"
                add_volume "pg-primary-data"
                add_volume "pg-replica-data"
                ;;
            pgvector)
                gen_pgvector >> "$COMPOSE_FILE"
                add_volume "pgvector-data"
                ;;
            mongodb)
                gen_mongodb >> "$COMPOSE_FILE"
                add_volume "mongodb-data"
                ;;
            mongodb-rs)
                gen_mongodb_rs >> "$COMPOSE_FILE"
                add_volume "mongo-primary-data"
                add_volume "mongo-secondary1-data"
                add_volume "mongo-secondary2-data"
                ;;
            minio)
                gen_minio >> "$COMPOSE_FILE"
                add_volume "minio-data"
                ;;
            minio:distributed)
                gen_minio_distributed >> "$COMPOSE_FILE"
                add_volume "minio1-data"
                add_volume "minio2-data"
                add_volume "minio3-data"
                add_volume "minio4-data"
                ;;
            elasticsearch)
                gen_elasticsearch >> "$COMPOSE_FILE"
                add_volume "elasticsearch-data"
                ;;
            elasticsearch:cluster)
                gen_elasticsearch_cluster >> "$COMPOSE_FILE"
                add_volume "es-node1-data"
                add_volume "es-node2-data"
                add_volume "es-node3-data"
                ;;
            kibana)
                gen_kibana >> "$COMPOSE_FILE"
                ;;
            logstash)
                gen_logstash >> "$COMPOSE_FILE"
                ;;
            nacos)
                gen_nacos >> "$COMPOSE_FILE"
                add_volume "nacos-data"
                ;;
            nacos:cluster)
                gen_nacos_cluster >> "$COMPOSE_FILE"
                add_volume "nacos1-data"
                add_volume "nacos2-data"
                add_volume "nacos3-data"
                ;;
            openresty)
                gen_openresty >> "$COMPOSE_FILE"
                add_volume "openresty-conf"
                add_volume "openresty-logs"
                add_volume "openresty-html"
                ;;
            rabbitmq)
                gen_rabbitmq >> "$COMPOSE_FILE"
                add_volume "rabbitmq-data"
                ;;
            rabbitmq:cluster)
                gen_rabbitmq_cluster >> "$COMPOSE_FILE"
                add_volume "rabbitmq1-data"
                add_volume "rabbitmq2-data"
                add_volume "rabbitmq3-data"
                ;;
            kafka)
                gen_kafka >> "$COMPOSE_FILE"
                add_volume "kafka-data"
                ;;
            kafka:cluster)
                gen_kafka_cluster >> "$COMPOSE_FILE"
                add_volume "kafka1-data"
                add_volume "kafka2-data"
                add_volume "kafka3-data"
                ;;
            zookeeper)
                gen_zookeeper >> "$COMPOSE_FILE"
                add_volume "zookeeper-data"
                add_volume "zookeeper-logs"
                ;;
            zookeeper:cluster)
                gen_zookeeper_cluster >> "$COMPOSE_FILE"
                add_volume "zookeeper1-data"
                add_volume "zookeeper1-logs"
                add_volume "zookeeper2-data"
                add_volume "zookeeper2-logs"
                add_volume "zookeeper3-data"
                add_volume "zookeeper3-logs"
                ;;
            rocketmq)
                gen_rocketmq >> "$COMPOSE_FILE"
                add_volume "rocketmq-namesrv-logs"
                add_volume "rocketmq-broker-data"
                add_volume "rocketmq-broker-logs"
                ;;
            rocketmq:cluster)
                gen_rocketmq_cluster >> "$COMPOSE_FILE"
                add_volume "rocketmq-namesrv1-logs"
                add_volume "rocketmq-namesrv2-logs"
                add_volume "rocketmq-broker1-data"
                add_volume "rocketmq-broker1-logs"
                add_volume "rocketmq-broker2-data"
                add_volume "rocketmq-broker2-logs"
                add_volume "rocketmq-broker3-data"
                add_volume "rocketmq-broker3-logs"
                ;;
            pulsar)
                gen_pulsar >> "$COMPOSE_FILE"
                add_volume "pulsar-data"
                ;;
            kong)
                gen_kong >> "$COMPOSE_FILE"
                add_volume "kong-db-data"
                ;;
            opensearch)
                gen_opensearch >> "$COMPOSE_FILE"
                add_volume "opensearch-data"
                ;;
            opensearch:cluster)
                gen_opensearch_cluster >> "$COMPOSE_FILE"
                add_volume "opensearch-node1-data"
                add_volume "opensearch-node2-data"
                add_volume "opensearch-node3-data"
                ;;
            skywalking)
                gen_skywalking >> "$COMPOSE_FILE"
                ;;
            prometheus)
                write_default_config "${DATA_DIR}/prometheus-conf/prometheus.yml" << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager:9093

rule_files:
  # - /etc/prometheus/rules/*.yml

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'alertmanager'
    static_configs:
      - targets: ['alertmanager:9093']

  - job_name: 'loki'
    static_configs:
      - targets: ['loki:3100']

  - job_name: 'promtail'
    static_configs:
      - targets: ['promtail:9080']
EOF
                gen_prometheus >> "$COMPOSE_FILE"
                add_volume "prometheus-data"
                add_volume "prometheus-conf"
                ;;
            alertmanager)
                write_default_config "${DATA_DIR}/alertmanager-conf/alertmanager.yml" << 'EOF'
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'default'
  routes:
    - matchers:
        - severity = "critical"
      receiver: 'default'

receivers:
  - name: 'default'
    # 按需配置通知渠道，例如：
    # webhook_configs:
    #   - url: http://your-webhook-url
    #     send_resolved: true
    # email_configs:
    #   - to: ops@example.com
    #     from: alertmanager@example.com
    #     smarthost: smtp.example.com:587
    #     auth_username: alertmanager@example.com
    #     auth_password: your-password
    #     send_resolved: true

inhibit_rules:
  - source_matchers:
      - severity = "critical"
    target_matchers:
      - severity = "warning"
    equal: ['alertname', 'instance']
EOF
                gen_alertmanager >> "$COMPOSE_FILE"
                add_volume "alertmanager-data"
                add_volume "alertmanager-conf"
                ;;
            grafana)
                gen_grafana >> "$COMPOSE_FILE"
                add_volume "grafana-data"
                ;;
            loki)
                gen_loki >> "$COMPOSE_FILE"
                add_volume "loki-data"
                ;;
            promtail)
                write_default_config "${DATA_DIR}/promtail-conf/config.yml" << 'EOF'
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /promtail/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: docker
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 10s
        filters:
          - name: status
            values: [running]
    relabel_configs:
      - source_labels: ['__meta_docker_container_name']
        regex: '/(.*)'
        target_label: 'container'
      - source_labels: ['__meta_docker_container_log_stream']
        target_label: 'stream'
      - source_labels: ['__meta_docker_container_label_com_docker_compose_service']
        target_label: 'compose_service'
EOF
                gen_promtail >> "$COMPOSE_FILE"
                add_volume "promtail-conf"
                add_volume "promtail-data"
                ;;
            keycloak)
                gen_keycloak >> "$COMPOSE_FILE"
                add_volume "keycloak-data"
                ;;
            keycloak:cluster)
                gen_keycloak_cluster >> "$COMPOSE_FILE"
                add_volume "keycloak-db-data"
                ;;
            xxljob)
                gen_xxljob >> "$COMPOSE_FILE"
                ;;
            powerjob)
                gen_powerjob >> "$COMPOSE_FILE"
                ;;
            sentinel)
                gen_sentinel >> "$COMPOSE_FILE"
                ;;
            rustfs)
                gen_rustfs >> "$COMPOSE_FILE"
                add_volume "rustfs-data"
                add_volume "rustfs-logs"
                ;;
            *)
                warn "Unknown component: $comp, skipping"
                ;;
        esac
    done

    # Dependency hints (these components are useless on their own)
    if [[ " $selected " == *" promtail "* ]] && [[ " $selected " != *" loki "* ]]; then
        warn "promtail selected without loki: logs have nowhere to go (client points to http://loki:3100)"
    fi
    if [[ " $selected " == *" alertmanager "* ]] && [[ " $selected " != *" prometheus "* ]]; then
        warn "alertmanager selected without prometheus: no alerts will be sent to it"
    fi

    # Add network
    echo "" >> "$COMPOSE_FILE"
    echo "networks:" >> "$COMPOSE_FILE"
    echo "  ${NETWORK_NAME}:" >> "$COMPOSE_FILE"
    echo "    driver: bridge" >> "$COMPOSE_FILE"

    # Add volumes
    echo "" >> "$COMPOSE_FILE"
    echo "volumes:" >> "$COMPOSE_FILE"
    IFS=',' read -ra VOLS <<< "$VOLUME_NAMES"
    for vol in "${VOLS[@]}"; do
        echo "  ${vol}:" >> "$COMPOSE_FILE"
        echo "    driver: local" >> "$COMPOSE_FILE"
        echo "    driver_opts:" >> "$COMPOSE_FILE"
        echo "      type: none" >> "$COMPOSE_FILE"
        echo "      o: bind" >> "$COMPOSE_FILE"
        echo "      device: ${DATA_DIR}/${vol}" >> "$COMPOSE_FILE"
        mkdir -p "${DATA_DIR}/${vol}"
    done

    ok "docker-compose.yml generated: $COMPOSE_FILE"
    ok ".env file generated: $ENV_FILE"
}

# ==============================================================================
# Commands
# ==============================================================================

cmd_list() {
    echo ""
    echo "Available Components:"
    echo ""
    printf "%-16s %-20s %-40s\n" "NAME" "CATEGORY" "DESCRIPTION"
    printf "%-16s %-20s %-40s\n" "----" "--------" "-----------"

    # Sort by category then name
    for key in $(echo "${!COMPONENTS[@]}" | tr ' ' '\n' | sort); do
        printf "%-16s %-20s %-40s\n" "$key" "${CATEGORIES[$key]}" "${DESCRIPTIONS[$key]}"
    done

    echo ""
    echo "Cluster/HA modes (use component:mode syntax):"
    echo "  Redis:          standalone (default), sentinel, cluster"
    echo "  MongoDB:        standalone (default), rs (replica set)"
    echo "  MySQL:          standalone (default), master-slave, dual-master"
    echo "  PostgreSQL:     standalone (default), ha (primary-replica)"
    echo "  RabbitMQ:       standalone (default), cluster"
    echo "  Kafka:          standalone (default, needs ZK), cluster (KRaft, no ZK)"
    echo "  RocketMQ:       standalone (default), cluster (2 namesrv + 3 brokers)"
    echo "  ZooKeeper:      standalone (default), cluster (3 nodes)"
    echo "  Elasticsearch:  standalone (default), cluster (3 nodes)"
    echo "  OpenSearch:     standalone (default), cluster (3 nodes)"
    echo "  Nacos:          standalone (default), cluster (3 nodes)"
    echo "  MinIO:          standalone (default), distributed (4 nodes)"
    echo "  Keycloak:       standalone (default), cluster (2 nodes)"
    echo ""
    echo "Use: $0 deploy redis,mysql,postgresql,minio"
    echo "Use: $0 deploy redis:sentinel,mysql:master-slave,mongodb:rs"
    echo "Use: $0 deploy kafka:cluster,nacos:cluster,minio:distributed"
    echo ""
}

cmd_deploy() {
    local components="${1:-}"
    local redis_mode="standalone"

    if [ -z "$components" ]; then
        echo ""
        echo "Select components to deploy:"
        echo "  1. redis           2. mysql          3. postgresql"
        echo "  4. mongodb         5. minio          6. elasticsearch"
        echo "  7. nacos           8. openresty      9. rabbitmq"
        echo " 10. kafka          11. rocketmq      12. zookeeper"
        echo " 13. pulsar         14. kong          15. opensearch"
        echo " 16. skywalking     17. prometheus     18. grafana"
        echo " 19. loki           20. logstash      21. kibana"
        echo " 22. keycloak       23. xxljob        24. powerjob"
        echo " 25. sentinel       26. rustfs        27. pgvector"
        echo " 28. alertmanager   29. promtail"
        echo ""
        echo "Presets:"
        echo "  a. dev-minimal    (redis, mysql, minio)"
        echo "  b. dev-full       (redis, mysql, postgresql, mongodb, minio, nacos, rabbitmq, kafka, zookeeper)"
        echo "  c. monitoring     (prometheus, grafana, loki)"
        echo "  d. elk            (elasticsearch, kibana, logstash)"
        echo "  e. all-databases  (redis, mysql, postgresql, mongodb)"
        echo "  f. all-mq         (rabbitmq, kafka, rocketmq, zookeeper, pulsar)"
        echo "  g. storage        (minio, rustfs)"
        echo "  h. cluster-mq     (kafka:cluster, rabbitmq:cluster, rocketmq:cluster)"
        echo "  i. monitoring-full(prometheus, alertmanager, grafana, loki, promtail)"
        echo ""
        read -p "Enter component names or preset (comma-separated): " components

        case "$components" in
            a) components="redis,mysql,minio" ;;
            b) components="redis,mysql,postgresql,mongodb,minio,nacos,rabbitmq,kafka,zookeeper" ;;
            c) components="prometheus,grafana,loki" ;;
            d) components="elasticsearch,kibana,logstash" ;;
            e) components="redis,mysql,postgresql,mongodb" ;;
            f) components="rabbitmq,kafka,rocketmq,zookeeper,pulsar" ;;
            g) components="minio,rustfs" ;;
            h) components="kafka:cluster,rabbitmq:cluster,rocketmq:cluster" ;;
            i) components="prometheus,alertmanager,grafana,loki,promtail" ;;
        esac
    fi

    # Parse component modes (component:mode syntax)
    local parsed_components=""
    for comp in $(echo "$components" | tr ',' ' '); do
        if [[ "$comp" == *"redis:"* ]]; then
            redis_mode="${comp#redis:}"
            comp="redis"
        elif [[ "$comp" == *"mongodb:"* ]]; then
            local mongo_mode="${comp#mongodb:}"
            if [ "$mongo_mode" = "rs" ]; then
                comp="mongodb-rs"
            else
                comp="mongodb"
            fi
        elif [[ "$comp" == *"mysql:"* ]]; then
            local mysql_mode="${comp#mysql:}"
            comp="mysql:${mysql_mode}"
        elif [[ "$comp" == *"rabbitmq:"* ]]; then
            local rabbit_mode="${comp#rabbitmq:}"
            comp="rabbitmq:${rabbit_mode}"
        elif [[ "$comp" == *"kafka:"* ]]; then
            local kafka_mode="${comp#kafka:}"
            comp="kafka:${kafka_mode}"
        elif [[ "$comp" == *"zookeeper:"* ]]; then
            local zk_mode="${comp#zookeeper:}"
            comp="zookeeper:${zk_mode}"
        elif [[ "$comp" == *"rocketmq:"* ]]; then
            local rmq_mode="${comp#rocketmq:}"
            comp="rocketmq:${rmq_mode}"
        elif [[ "$comp" == *"elasticsearch:"* ]]; then
            local es_mode="${comp#elasticsearch:}"
            comp="elasticsearch:${es_mode}"
        elif [[ "$comp" == *"postgresql:"* ]]; then
            local pg_mode="${comp#postgresql:}"
            comp="postgresql:${pg_mode}"
        elif [[ "$comp" == *"nacos:"* ]]; then
            local nacos_mode="${comp#nacos:}"
            comp="nacos:${nacos_mode}"
        elif [[ "$comp" == *"minio:"* ]]; then
            local minio_mode="${comp#minio:}"
            comp="minio:${minio_mode}"
        elif [[ "$comp" == *"opensearch:"* ]]; then
            local os_mode="${comp#opensearch:}"
            comp="opensearch:${os_mode}"
        elif [[ "$comp" == *"keycloak:"* ]]; then
            local kc_mode="${comp#keycloak:}"
            comp="keycloak:${kc_mode}"
        fi
        parsed_components="$parsed_components $comp"
    done
    components=$(echo "$parsed_components" | xargs)

    info "Selected: $components"
    [ "$redis_mode" != "standalone" ] && info "Redis mode: $redis_mode"

    check_docker
    init_dirs
    generate_compose "$components" "$redis_mode"

    echo ""
    read -p "Start services now? [Y/n] " start_now
    if [[ ! "$start_now" =~ ^[Nn]$ ]]; then
        cmd_up
    fi
}

cmd_up() {
    check_docker
    if [ ! -f "$COMPOSE_FILE" ]; then
        error "docker-compose.yml not found. Run '$0 deploy' first."
        exit 1
    fi
    info "Starting services..."
    cd "$BASE_DIR"
    docker compose --env-file .env up -d
    ok "Services started"
    cmd_status
}

cmd_down() {
    check_docker
    if [ ! -f "$COMPOSE_FILE" ]; then
        error "docker-compose.yml not found."
        exit 1
    fi
    info "Stopping services..."
    cd "$BASE_DIR"
    docker compose --env-file .env down
    ok "Services stopped"
}

cmd_restart() {
    check_docker
    if [ ! -f "$COMPOSE_FILE" ]; then
        error "docker-compose.yml not found."
        exit 1
    fi
    info "Restarting services..."
    cd "$BASE_DIR"
    docker compose --env-file .env restart
    ok "Services restarted"
}

# Map a component name (or exact compose service name) to deployed service names
resolve_services() {
    local name="$1"
    local prefixes="${SERVICE_PREFIXES[$name]:-$name}"
    local matched="" svc p all
    all=$(cd "$BASE_DIR" && docker compose --env-file .env config --services 2>/dev/null) || true
    for svc in $all; do
        for p in $prefixes; do
            if [[ "$svc" == "$p"* ]] && [[ " $matched " != *" $svc "* ]]; then
                matched="$matched $svc"
            fi
        done
    done
    echo "${matched# }"
}

cmd_service() {
    local action="$1"
    local name="$2"
    if [ -z "$name" ]; then
        error "Usage: $0 $action <component|service>  (omit name to affect the whole stack)"
        exit 1
    fi
    check_docker
    if [ ! -f "$COMPOSE_FILE" ]; then
        error "docker-compose.yml not found. Run '$0 deploy' first."
        exit 1
    fi
    local services
    services=$(resolve_services "$name")
    if [ -z "$services" ]; then
        error "No deployed service matched: $name"
        info "Deployed stack services: $(cd "$BASE_DIR" && docker compose --env-file .env config --services | tr '\n' ' ')"
        exit 1
    fi
    info "$action: $services"
    cd "$BASE_DIR"
    case "$action" in
        start)   docker compose --env-file .env up -d $services ;;
        stop)    docker compose --env-file .env stop $services ;;
        restart) docker compose --env-file .env restart $services ;;
        remove)  read -p "Remove containers of [$services]? Data volumes are kept. Continue? [y/N] " confirm
                 if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                     info "Cancelled"
                     exit 0
                 fi
                 docker compose --env-file .env rm -sf $services ;;
    esac
    ok "Done: $action $services"
}

cmd_status() {
    if [ ! -f "$COMPOSE_FILE" ]; then
        error "docker-compose.yml not found."
        exit 1
    fi
    cd "$BASE_DIR"
    docker compose --env-file .env ps
}

cmd_logs() {
    local service="${1:-}"
    if [ ! -f "$COMPOSE_FILE" ]; then
        error "docker-compose.yml not found."
        exit 1
    fi
    cd "$BASE_DIR"
    if [ -n "$service" ]; then
        docker compose --env-file .env logs -f --tail=100 "$service"
    else
        docker compose --env-file .env logs -f --tail=50
    fi
}

cmd_clean() {
    if [ ! -f "$COMPOSE_FILE" ]; then
        error "docker-compose.yml not found."
        exit 1
    fi
    read -p "This will remove ALL containers and data. Continue? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Cancelled"
        exit 0
    fi
    cd "$BASE_DIR"
    docker compose --env-file .env down -v
    ok "All containers and volumes removed"
}

cmd_info() {
    echo ""
    echo "=========================================="
    echo "Docker Stack Information"
    echo "=========================================="
    echo "Base Dir:     $BASE_DIR"
    echo "Data Dir:     $DATA_DIR"
    echo "Config Dir:   $CONFIG_DIR"
    echo "Compose File: $COMPOSE_FILE"
    echo "Env File:     $ENV_FILE"
    echo "Network:      $NETWORK_NAME"
    echo ""

    if [ -f "$COMPOSE_FILE" ]; then
        echo "--- Deployed Services ---"
        cd "$BASE_DIR"
        docker compose --env-file .env ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "No running services"
    else
        echo "No docker-compose.yml found. Run '$0 deploy' first."
    fi
    echo ""
    echo "--- Default Credentials ---"
    echo "Redis:        password=$REDIS_PASS"
    echo "MySQL:        root/$MYSQL_ROOT_PASS"
    echo "PostgreSQL:   postgres/$POSTGRES_PASS"
    echo "pgvector:     postgres/$POSTGRES_PASS (port 5435, run CREATE EXTENSION vector in your DB)"
    echo "MongoDB:      root/$MONGO_ROOT_PASS"
    echo "MinIO:        $MINIO_ROOT_USER/$MINIO_ROOT_PASS"
    echo "Elasticsearch: elastic/$ES_PASS"
    echo "Nacos:        nacos/$NACOS_PASS"
    echo "RabbitMQ:     $RABBIT_USER/$RABBIT_PASS"
    echo "Keycloak:     $KEYCLOAK_ADMIN/$KEYCLOAK_PASS"
    echo "Grafana:      admin/admin"
    echo "RustFS:       $RUSTFS_ACCESS_KEY/$RUSTFS_SECRET_KEY"
    echo "=========================================="
}

cmd_help() {
    cat << HELP
Docker Compose Infrastructure Deployer v$VERSION

Usage: $0 <command> [arguments]

Commands:
  list              List all available components
  deploy [comps]    Deploy selected components (interactive if not specified)
  up [component]    Start all services, or one component (e.g. up redis)
  stop [component]  Stop all services, or one component (e.g. stop kafka)
  restart [component] Restart all services, or one component (e.g. restart mysql)
  remove <component>  Remove one component's containers (volumes kept, e.g. remove nacos)
  status            Show service status
  logs [service]    View logs (follow mode)
  info              Show deployment info and credentials
  clean             Remove all containers and data volumes
  help              Show this help

Per-service operations accept a component name (redis, kafka, xxljob, ...) and
automatically cover all its nodes in cluster/HA modes (e.g. kafka -> kafka1 kafka2 kafka3).
An exact compose service name (e.g. es-node2) also works.
Note: starting a component may also start its depends_on services.

Component format:
  redis              Redis standalone (default)
  redis:sentinel     Redis sentinel mode (1 master + 2 slaves + 1 sentinel)
  redis:cluster      Redis cluster mode (6 nodes)
  mongodb            MongoDB standalone (default)
  mongodb:rs         MongoDB replica set (1 primary + 2 secondary)
  mysql              MySQL standalone (default)
  mysql:master-slave MySQL master-slave replication (GTID-based)
  mysql:dual-master  MySQL dual-master replication (GTID-based)
  rabbitmq           RabbitMQ standalone (default)
  rabbitmq:cluster   RabbitMQ cluster (3 nodes, shared erlang cookie)
  kafka              Kafka standalone (default, requires zookeeper)
  kafka:cluster      Kafka KRaft cluster (3 brokers, no ZooKeeper required)
  zookeeper          ZooKeeper standalone (default)
  zookeeper:cluster  ZooKeeper ensemble (3 nodes)
  rocketmq           RocketMQ standalone (default)
  rocketmq:cluster   RocketMQ cluster (2 namesrv + 3 brokers)
  elasticsearch      Elasticsearch standalone (default)
  elasticsearch:cluster Elasticsearch cluster (3 nodes)
  postgresql         PostgreSQL standalone (default)
  postgresql:ha      PostgreSQL primary-replica (1 primary + 1 replica, repmgr)
  pgvector           pgvector (PostgreSQL 17 + vector extension, port 5435)
  nacos              Nacos standalone (default)
  nacos:cluster      Nacos cluster (3 nodes, embedded raft)
  minio              MinIO standalone (default)
  minio:distributed  MinIO distributed (4 nodes, erasure coding)
  opensearch         OpenSearch standalone (default)
  opensearch:cluster OpenSearch cluster (3 nodes)
  keycloak           Keycloak standalone (default)
  keycloak:cluster   Keycloak cluster (2 nodes, shared DB)

Presets (use in deploy prompt):
  dev-minimal       redis, mysql, minio
  dev-full          redis, mysql, postgresql, mongodb, minio, nacos, rabbitmq, kafka, zookeeper
  monitoring        prometheus, grafana, loki
  monitoring-full   prometheus, alertmanager, grafana, loki, promtail
  elk               elasticsearch, kibana, logstash
  all-databases     redis, mysql, postgresql, mongodb
  all-mq            rabbitmq, kafka, rocketmq, zookeeper, pulsar
  storage           minio, rustfs
  cluster-mq        kafka:cluster, rabbitmq:cluster, rocketmq:cluster

Examples:
  $0 list
  $0 deploy redis,mysql,postgresql,minio
  $0 deploy redis:sentinel,mysql:master-slave,mongodb:rs
  $0 deploy kafka:cluster                    # KRaft mode, no ZooKeeper needed
  $0 deploy nacos:cluster,minio:distributed
  $0 deploy postgresql:ha,opensearch:cluster,keycloak:cluster
  $0 deploy prometheus,alertmanager,grafana,loki,promtail   # metrics + alerting + logs
  $0 deploy              # Interactive mode
  $0 up
  $0 stop redis                      # stop only redis (all its nodes in cluster mode)
  $0 restart kafka                   # cluster nodes too: kafka1 kafka2 kafka3
  $0 remove nacos                    # remove nacos containers, keep data
  $0 logs redis
  $0 info
  $0 clean

Data volumes are mounted at: $DATA_DIR/
HELP
}

# ==============================================================================
# Main entry point
# ==============================================================================

print_banner

case "${1:-help}" in
    list|ls)       cmd_list ;;
    deploy|create) shift; cmd_deploy "$@" ;;
    up|start)      shift; if [ -n "${1:-}" ]; then cmd_service start "$1"; else cmd_up; fi ;;
    down|stop)     shift; if [ -n "${1:-}" ]; then cmd_service stop "$1"; else cmd_down; fi ;;
    restart)       shift; if [ -n "${1:-}" ]; then cmd_service restart "$1"; else cmd_restart; fi ;;
    remove)        shift; cmd_service remove "${1:-}" ;;
    status|ps)     cmd_status ;;
    logs)          shift; cmd_logs "$@" ;;
    info)          cmd_info ;;
    clean)         cmd_clean ;;
    help|--help|-h) cmd_help ;;
    *)             error "Unknown command: $1"; echo ""; cmd_help; exit 1 ;;
esac