# Docker 工具脚本

本目录包含 Docker 相关的安装、部署和管理脚本。

## 脚本列表

| 脚本 | 功能 | 使用场景 |
|------|------|---------|
| **docker_install.sh** | 自动安装最新版 Docker Engine + Compose | 新服务器初始化 |
| **docker_compose_deploy.sh** | 一键部署 28+ 基础设施组件 | 开发/测试环境搭建 |
| **docker_cleaner.sh** | Docker 资源清理工具 | 定期维护 |

## 快速开始

### 1. 安装 Docker

```bash
# 赋予执行权限
chmod +x *.sh

# 快速安装（中国镜像源）
sudo ./docker_install.sh -y --mirror china

# 验证安装
docker --version
docker compose version
```

### 2. 部署基础设施

```bash
# 查看可用组件
./docker_compose_deploy.sh list

# 交互式部署
./docker_compose_deploy.sh deploy

# 指定组件部署
./docker_compose_deploy.sh deploy redis,mysql,postgresql,minio,rustfs

# Redis 哨兵 + MongoDB 副本集
./docker_compose_deploy.sh deploy redis:sentinel,mysql,mongodb:rs

# Kafka KRaft 集群（无需 ZooKeeper）
./docker_compose_deploy.sh deploy kafka:cluster

# Nacos 集群 + MinIO 分布式
./docker_compose_deploy.sh deploy nacos:cluster,minio:distributed

# PostgreSQL 主从 + OpenSearch 集群 + Keycloak 集群
./docker_compose_deploy.sh deploy postgresql:ha,opensearch:cluster,keycloak:cluster

# 监控 + 告警 + 日志全栈
./docker_compose_deploy.sh deploy prometheus,alertmanager,grafana,loki,promtail

# 启动/停止/状态
./docker_compose_deploy.sh up
./docker_compose_deploy.sh down
./docker_compose_deploy.sh status

# 查看凭据信息
./docker_compose_deploy.sh info
```

### 3. 清理 Docker 资源

```bash
# 清理所有无用资源
./docker_cleaner.sh -a

# 查看磁盘使用
./docker_cleaner.sh -s
```

## 支持的组件 (28个)

| 类别 | 组件 | 版本 |
|------|------|------|
| 数据库 | Redis, MySQL, PostgreSQL, MongoDB | 8.0, 8.4 LTS, 17, 8.0 |
| 向量库 | pgvector | 0.8 (PG 17) |
| 搜索 | Elasticsearch, OpenSearch | 8.19, 2.19 |
| 存储 | MinIO, RustFS | RELEASE.2025-10-15, 1.0.0-alpha.69 |
| 消息队列 | RabbitMQ, Kafka, RocketMQ, Pulsar | 4.3, 8.3 (KRaft), 5.5, 4.2 |
| 协调 | ZooKeeper | 3.9 |
| 网关 | OpenResty, Kong | 1.27, 3.9 |
| 监控 | Prometheus, Alertmanager, Grafana, Loki, SkyWalking | 3.13, 0.29, 12.4, 3.7, 10.4 |
| 日志 | Logstash, Kibana, Promtail | 8.19, 3.7 |
| 安全 | Keycloak, Sentinel | 26.6, 1.8 |
| 调度 | XXL-Job, PowerJob | 3.4, 5.1 |
| 注册中心 | Nacos | 3.2 |

## 集群/高可用模式

| 组件 | 模式 | 说明 |
|------|------|------|
| Redis | `redis:sentinel` | 哨兵模式（1主2从1哨兵） |
| Redis | `redis:cluster` | 集群模式（6节点） |
| MySQL | `mysql:master-slave` | 主从复制（GTID） |
| MySQL | `mysql:dual-master` | 双主互备（GTID） |
| PostgreSQL | `postgresql:ha` | 主从复制（流复制，pg_basebackup） |
| MongoDB | `mongodb:rs` | 副本集（1主2从） |
| RabbitMQ | `rabbitmq:cluster` | 集群（3节点，共享 Erlang Cookie） |
| Kafka | `kafka:cluster` | KRaft 集群（3 Broker，无需 ZooKeeper） |
| RocketMQ | `rocketmq:cluster` | 集群（2 NameServer + 3 Broker） |
| ZooKeeper | `zookeeper:cluster` | 集群（3节点） |
| Elasticsearch | `elasticsearch:cluster` | 集群（3节点） |
| OpenSearch | `opensearch:cluster` | 集群（3节点） |
| Nacos | `nacos:cluster` | 集群（3节点，Raft 共识） |
| MinIO | `minio:distributed` | 分布式（4节点，纠删码） |
| Keycloak | `keycloak:cluster` | 集群（2节点，共享 PostgreSQL） |

## 预设方案

| 方案 | 包含组件 |
|------|---------|
| dev-minimal | redis, mysql, minio |
| dev-full | redis, mysql, postgresql, mongodb, minio, nacos, rabbitmq, kafka, zookeeper |
| monitoring | prometheus, grafana, loki |
| elk | elasticsearch, kibana, logstash |
| all-databases | redis, mysql, postgresql, mongodb |
| all-mq | rabbitmq, kafka, rocketmq, zookeeper, pulsar |
| storage | minio, rustfs |
| cluster-mq | kafka:cluster, rabbitmq:cluster, rocketmq:cluster |
| monitoring-full | prometheus, alertmanager, grafana, loki, promtail |

## 数据目录

所有数据卷统一挂载到 `~/docker-stack/data/` 目录下。

需要在宿主机编辑的配置文件（首次部署自动生成默认内容，已存在则不会覆盖）：

| 组件 | 配置文件 |
|------|---------|
| Prometheus | `~/docker-stack/data/prometheus-conf/prometheus.yml` |
| Alertmanager | `~/docker-stack/data/alertmanager-conf/alertmanager.yml` |
| Promtail | `~/docker-stack/data/promtail-conf/config.yml` |

生效方式：
```bash
curl -X POST http://localhost:9090/-/reload   # Prometheus 热加载
curl -X POST http://localhost:9093/-/reload   # Alertmanager 热加载
./docker_compose_deploy.sh restart promtail   # Promtail 需重启
```
