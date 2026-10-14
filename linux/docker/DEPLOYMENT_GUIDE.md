# Docker 基础设施部署操作手册

> 本手册详细介绍如何从零开始在 CentOS/Ubuntu 上安装 Docker，并使用 docker_compose_deploy.sh 一键部署 28+ 基础设施组件。

---

## 目录

1. [环境要求](#1-环境要求)
2. [第一步：安装 Docker](#2-第一步安装-docker)
3. [第二步：部署基础设施组件](#3-第二步部署基础设施组件)
4. [第三步：组件使用指南](#4-第三步组件使用指南)
5. [第四步：日常运维操作](#5-第四步日常运维操作)
6. [第五步：高级配置](#6-第五步高级配置)
7. [附录：故障排查](#7-附录故障排查)

---

## 1. 环境要求

### 硬件要求

| 配置级别 | CPU | 内存 | 磁盘 | 适用场景 |
|---------|-----|------|------|---------|
| 最低配置 | 2核 | 4GB | 20GB | 单组件测试 |
| 推荐配置 | 4核 | 8GB | 50GB | dev-minimal/dev-full |
| 生产配置 | 8核+ | 16GB+ | 100GB+ | 全量部署 |

### 操作系统支持

| 系统 | 版本 | 状态 |
|------|------|------|
| CentOS | 7 / Stream 8 / Stream 9 | 支持 |
| Ubuntu | 20.04 / 22.04 / 24.04 | 支持 |
| Debian | 11 / 12 | 支持 |
| Rocky Linux | 8 / 9 | 支持 |
| AlmaLinux | 8 / 9 | 支持 |

### 网络要求

- 需要外网访问（拉取 Docker 镜像）
- 国内服务器建议使用 `--mirror china` 参数
- 开放相应端口（见组件端口表）

---

## 2. 第一步：安装 Docker

### 2.1 下载脚本

```bash
# 克隆仓库
git clone https://github.com/smart-open/scripts.git
cd scripts/linux/docker

# 赋予执行权限
chmod +x *.sh
```

### 2.2 执行安装

**方式一：快速安装（推荐）**

```bash
# 使用官方源（海外服务器）
sudo ./docker_install.sh -y

# 使用阿里云镜像源（国内服务器，推荐）
sudo ./docker_install.sh -y --mirror china
```

**方式二：交互式安装**

```bash
sudo ./docker_install.sh
```

脚本会自动：
1. 检测操作系统类型（CentOS/Ubuntu）
2. 查询 GitHub API 获取最新 Docker 版本
3. 移除旧版本 Docker
4. 添加 Docker 官方/阿里云仓库
5. 安装 Docker Engine + Compose 插件
6. 配置 daemon.json（日志轮转、overlay2 存储）
7. 启动 Docker 服务并设置开机自启
8. 添加当前用户到 docker 组
9. 运行 hello-world 验证

### 2.3 验证安装

```bash
# 查看版本
docker --version
# 预期输出: Docker version 29.x.x

docker compose version
# 预期输出: Docker Compose version v5.x.x

# 运行测试容器
docker run --rm hello-world
# 预期输出: Hello from Docker!

# 查看服务状态
systemctl status docker
# 预期: active (running)
```

### 2.4 重新登录（使 docker 组生效）

```bash
# 如果用 sudo 安装，需重新登录使 docker 组生效
exit
# 重新 SSH 登录后验证
docker ps
# 不需要 sudo 即可执行
```

### 2.5 配置镜像加速（可选）

如果安装时未使用 `--mirror china`，可手动配置：

```bash
sudo tee /etc/docker/daemon.json << 'EOF'
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

sudo systemctl daemon-reload
sudo systemctl restart docker
```

---

## 3. 第二步：部署基础设施组件

### 3.1 查看可用组件

```bash
cd scripts/linux/docker
./docker_compose_deploy.sh list
```

输出示例：
```
NAME             CATEGORY            DESCRIPTION
redis            Cache/MQ            Redis 8.0 - In-memory cache/message broker
mysql            Database            MySQL 8.4 LTS - Relational database
postgresql       Database            PostgreSQL 17 - Advanced relational database
...
rustfs           Storage             RustFS - High-performance distributed object storage
```

### 3.2 选择部署方式

**方式一：使用预设方案（推荐新手）**

```bash
./docker_compose_deploy.sh deploy
```

交互式菜单中选择预设方案：

| 输入 | 方案名 | 包含组件 | 适用场景 |
|------|--------|---------|---------|
| a | dev-minimal | redis, mysql, minio | 最小开发环境 |
| b | dev-full | redis, mysql, postgresql, mongodb, minio, nacos, rabbitmq, kafka, zookeeper | 完整微服务开发 |
| c | monitoring | prometheus, grafana, loki | 监控栈 |
| d | elk | elasticsearch, kibana, logstash | 日志分析栈 |
| e | all-databases | redis, mysql, postgresql, mongodb | 全部数据库 |
| f | all-mq | rabbitmq, kafka, rocketmq, zookeeper, pulsar | 全部消息队列 |
| g | storage | minio, rustfs | 对象存储 |
| h | cluster-mq | kafka:cluster, rabbitmq:cluster, rocketmq:cluster | 消息队列集群 |
| i | monitoring-full | prometheus, alertmanager, grafana, loki, promtail | 监控+告警+日志全栈 |

**方式二：指定组件部署**

```bash
# 部署指定组件
./docker_compose_deploy.sh deploy redis,mysql,postgresql,minio,rustfs

# Redis 哨兵模式
./docker_compose_deploy.sh deploy redis:sentinel,mysql

# Redis 集群模式（6节点）
./docker_compose_deploy.sh deploy redis:cluster,mysql

# MongoDB 副本集
./docker_compose_deploy.sh deploy mongodb:rs,mysql

# Kafka KRaft 集群（无需 ZooKeeper）
./docker_compose_deploy.sh deploy kafka:cluster

# MySQL 主从 + PostgreSQL 主从
./docker_compose_deploy.sh deploy mysql:master-slave,postgresql:ha

# Nacos 集群 + MinIO 分布式
./docker_compose_deploy.sh deploy nacos:cluster,minio:distributed

# OpenSearch 集群 + Keycloak 集群
./docker_compose_deploy.sh deploy opensearch:cluster,keycloak:cluster

# 组合使用
./docker_compose_deploy.sh deploy redis:sentinel,mysql,mongodb:rs,nacos:cluster,rabbitmq:cluster
```

### 3.3 部署流程说明

执行 `deploy` 命令后，脚本会自动：

1. **检查 Docker 环境** - 确认 Docker 和 Compose 已安装
2. **创建目录结构** - 在 `~/docker-stack/` 下创建 data、config 目录
3. **生成 .env 文件** - 包含所有组件的默认密码和配置
4. **生成 docker-compose.yml** - 根据选择的组件生成编排文件
5. **创建数据卷目录** - 为每个组件创建独立的数据挂载目录
6. **提示启动** - 询问是否立即启动服务

### 3.4 目录结构

部署完成后，目录结构如下：

```
~/docker-stack/
├── docker-compose.yml    # Docker Compose 编排文件
├── .env                  # 环境变量（密码等）
├── data/                 # 数据卷挂载目录
│   ├── redis-data/
│   ├── mysql-data/
│   ├── postgresql-data/
│   ├── minio-data/
│   ├── rustfs-data/
│   └── ...
└── config/               # 配置文件目录
```

### 3.5 启动/停止服务

```bash
# 启动所有服务
./docker_compose_deploy.sh up

# 停止所有服务
./docker_compose_deploy.sh down

# 重启所有服务
./docker_compose_deploy.sh restart

# 查看服务状态
./docker_compose_deploy.sh status

# 查看日志（所有服务）
./docker_compose_deploy.sh logs

# 查看指定服务日志
./docker_compose_deploy.sh logs redis
./docker_compose_deploy.sh logs mysql
```

---

## 4. 第三步：组件使用指南

### 4.1 组件端口与凭据速查表

| 组件 | 端口 | 访问地址 | 默认账号 | 默认密码 |
|------|------|---------|---------|---------|
| Redis | 6379 | - | - | Redis123! |
| MySQL | 3306 | - | root | Root123! |
| PostgreSQL | 5432 | - | postgres | Postgres123! |
| MongoDB | 27017 | - | root | Mongo123! |
| MinIO | 9000/9001 | http://IP:9001 | admin | Minio123! |
| RustFS | 9002/9003 | http://IP:9003 | rustfs | Rustfs123! |
| Elasticsearch | 9200/9300 | http://IP:9200 | elastic | Elastic123! |
| Kibana | 5601 | http://IP:5601 | elastic | Elastic123! |
| Nacos | 8848/9848 | http://IP:8848/nacos | nacos | Nacos123! |
| RabbitMQ | 5672/15672 | http://IP:15672 | admin | Rabbit123! |
| Kafka | 9092 | - | - | - |
| RocketMQ | 8080/9876/10911 | http://IP:8080 | - | - |
| ZooKeeper | 2181 | - | - | - |
| Pulsar | 6650/8080 | http://IP:8080 | - | - |
| Kong | 8000/8443/8001/8444 | http://IP:8001 | - | - |
| OpenSearch | 9201/9600 | http://IP:9201 | admin | admin |
| SkyWalking | 11800/12800 | http://IP:12800 | - | - |
| Prometheus | 9090 | http://IP:9090 | - | - |
| Alertmanager | 9093 | http://IP:9093 | - | - |
| Grafana | 3000 | http://IP:3000 | admin | admin |
| Loki | 3100 | - | - | - |
| Promtail | 9080 | - | - | - |
| Logstash | 5044/9600 | - | - | - |
| Keycloak | 8080 | http://IP:8080 | admin | Keycloak123! |
| XXL-Job | 8089 | http://IP:8089/xxl-job-admin | admin | 123456 |
| PowerJob | 7700/10086 | http://IP:7700 | - | - |
| Sentinel | 8858 | http://IP:8858 | sentinel | sentinel |
| OpenResty | 80/443 | http://IP | - | - |

> 使用 `./docker_compose_deploy.sh info` 可随时查看凭据信息

### 4.2 Redis 使用

**单机模式：**
```bash
# 连接 Redis
docker exec -it redis redis-cli -a Redis123!

# 基本操作
127.0.0.1:6379> SET hello world
127.0.0.1:6379> GET hello
```

**哨兵模式（1主2从1哨兵）：**
```bash
# 连接哨兵查看状态
docker exec -it redis-sentinel1 redis-cli -p 26379 sentinel masters

# 连接从节点
docker exec -it redis-slave1 redis-cli -a Redis123!
```

**集群模式（6节点，3主3从）：**
```bash
# 初始化集群（首次启动后执行）
docker exec -it redis-node1 redis-cli --cluster create \
  redis-node1:6379 redis-node2:6379 redis-node3:6379 \
  redis-node4:6379 redis-node5:6379 redis-node6:6379 \
  --cluster-replicas 1 -a Redis123!

# 查看集群状态
docker exec -it redis-node1 redis-cli -c -a Redis123! cluster info
docker exec -it redis-node1 redis-cli -c -a Redis123! cluster nodes
```

### 4.3 MySQL 使用

```bash
# 连接 MySQL
docker exec -it mysql mysql -uroot -pRoot123!

# 创建数据库
mysql> CREATE DATABASE myapp CHARACTER SET utf8mb4;
mysql> CREATE USER 'myapp'@'%' IDENTIFIED BY 'MyApp123!';
mysql> GRANT ALL ON myapp.* TO 'myapp'@'%';
mysql> FLUSH PRIVILEGES;
```

### 4.4 MinIO / RustFS 使用

**MinIO：**
- 控制台: http://IP:9001 (admin/Minio123!)
- API: http://IP:9000

**RustFS：**
- 控制台: http://IP:9003 (rustfs/Rustfs123!)
- API: http://IP:9002

```bash
# 使用 mc 客户端连接 MinIO
docker run --rm -it minio/mc alias set local http://localhost:9000 admin Minio123!
docker run --rm -it minio/mc ls local/

# 使用 aws cli 连接 RustFS
aws --endpoint-url http://localhost:9002 s3 ls \
  --no-sign-request
```

### 4.5 Nacos 使用

- 控制台: http://IP:8848/nacos (nacos/Nacos123!)

```bash
# 注册服务示例
curl -X POST "http://localhost:8848/nacos/v1/ns/instance?serviceName=myapp&ip=127.0.0.1&port=8080"

# 查询服务
curl "http://localhost:8848/nacos/v1/ns/instance/list?serviceName=myapp"
```

### 4.6 RabbitMQ 使用

- 管理界面: http://IP:15672 (admin/Rabbit123!)

```bash
# 命令行管理
docker exec -it rabbitmq rabbitmqctl status
docker exec -it rabbitmq rabbitmqctl list_queues
```

### 4.7 ELK (Elasticsearch + Kibana + Logstash)

```bash
# 验证 Elasticsearch
curl -u elastic:Elastic123! http://localhost:9200

# 查看索引
curl -u elastic:Elastic123! http://localhost:9200/_cat/indices?v

# Kibana 控制台
# 访问 http://IP:5601
```

### 4.8 监控栈 (Prometheus + Alertmanager + Grafana + Loki + Promtail)

```bash
# Prometheus
# 访问 http://IP:9090
# 默认配置已写入 ~/docker-stack/data/prometheus-conf/prometheus.yml
# 其中 alerting 已指向 alertmanager:9093

# Alertmanager
# 访问 http://IP:9093
# 通知渠道配置: ~/docker-stack/data/alertmanager-conf/alertmanager.yml
# 改完后热加载: curl -X POST http://localhost:9093/-/reload

# Promtail
# 自动采集本机所有运行中容器的日志并推送到 Loki
# 采集配置: ~/docker-stack/data/promtail-conf/config.yml (clients -> http://loki:3100)
# 改完后重启: ./docker_compose_deploy.sh restart promtail

# Grafana
# 访问 http://IP:3000 (admin/admin)
# 添加数据源: Prometheus (http://prometheus:9090)
# 添加数据源: Loki (http://loki:3100)
# 查看日志: Explore -> Loki -> {container="xxx"} 或 {compose_service="redis"}
```

---

## 5. 第四步：日常运维操作

### 5.1 查看服务状态

```bash
# 查看所有服务状态
./docker_compose_deploy.sh status

# 或使用 docker 命令
cd ~/docker-stack
docker compose ps
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
```

### 5.2 查看日志

```bash
# 查看所有服务日志（实时跟踪）
./docker_compose_deploy.sh logs

# 查看指定服务日志
./docker_compose_deploy.sh logs redis
./docker_compose_deploy.sh logs mysql

# 使用 docker 命令
docker compose -f ~/docker-stack/docker-compose.yml logs -f redis
```

### 5.3 重启服务

```bash
# 重启所有服务
./docker_compose_deploy.sh restart

# 重启单个服务
cd ~/docker-stack
docker compose restart redis
docker compose restart mysql
```

### 5.4 更新镜像

```bash
cd ~/docker-stack

# 拉取最新镜像
docker compose pull

# 重新创建容器
docker compose up -d

# 清理旧镜像
docker image prune -f
```

### 5.5 清理环境

```bash
# 停止并删除所有容器和数据（谨慎操作！）
./docker_compose_deploy.sh clean

# 或使用 docker_cleaner
./docker_cleaner.sh -a
```

### 5.6 备份数据

```bash
# 备份 MySQL
docker exec mysql mysqldump -uroot -pRoot123! --all-databases > backup.sql

# 备份 Redis
docker exec redis redis-cli -a Redis123! SAVE
cp ~/docker-stack/data/redis-data/dump.rdb ./redis-backup-$(date +%Y%m%d).rdb

# 备份所有数据目录
tar -czf docker-stack-backup-$(date +%Y%m%d).tar.gz ~/docker-stack/data/
```

---

## 6. 第五步：高级配置

### 6.1 自定义密码

编辑 `~/docker-stack/.env` 文件：

```bash
vim ~/docker-stack/.env
```

修改密码后重启：
```bash
cd ~/docker-stack
docker compose down
docker compose up -d
```

### 6.2 添加自定义组件

在 `docker-compose.yml` 中手动添加服务：

```yaml
  custom-app:
    image: my-app:latest
    container_name: custom-app
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      - DB_HOST=mysql
      - REDIS_HOST=redis
    depends_on:
      - mysql
      - redis
    networks:
      - docker-stack-net
```

### 6.3 配置 Prometheus 监控目标

编辑 Prometheus 配置文件：

```bash
vim ~/docker-stack/data/prometheus-conf/prometheus.yml
```

添加监控目标：
```yaml
scrape_configs:
  - job_name: 'myapp'
    static_configs:
      - targets: ['myapp:8080']
```

重载配置：
```bash
curl -X POST http://localhost:9090/-/reload
```

### 6.4 配置 Grafana 仪表盘

1. 访问 http://IP:3000 (admin/admin)
2. 添加数据源 → Prometheus → URL: http://prometheus:9090
3. 导入仪表盘 → 输入 ID (如: 893 for Node Exporter)

### 6.5 配置 Nginx/OpenResty 反向代理

```bash
# 编辑 OpenResty 配置
vim ~/docker-stack/data/openresty-conf/nginx.conf
```

添加反向代理：
```nginx
server {
    listen 80;
    server_name api.example.com;

    location / {
        proxy_pass http://myapp:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

重载配置：
```bash
docker exec openresty nginx -s reload
```

---

## 7. 附录：故障排查

### 7.1 Docker 安装失败

```bash
# 检查 Docker 服务状态
systemctl status docker
journalctl -u docker --no-pager | tail -50

# 重新安装
sudo ./docker_install.sh -y --mirror china
```

### 7.2 镜像拉取失败（国内网络）

```bash
# 配置镜像加速
sudo tee /etc/docker/daemon.json << 'EOF'
{
    "registry-mirrors": [
        "https://docker.1ms.run",
        "https://docker.xuanyuan.me"
    ]
}
EOF
sudo systemctl restart docker

# 手动拉取测试
docker pull redis:8.0-alpine
```

### 7.3 端口冲突

```bash
# 查看端口占用
ss -tlnp | grep 3306

# 修改 docker-compose.yml 中的端口映射
vim ~/docker-stack/docker-compose.yml
# 将 "3306:3306" 改为 "3307:3306"

# 重启服务
cd ~/docker-stack
docker compose up -d
```

### 7.4 容器无法启动

```bash
# 查看容器日志
docker logs redis
docker logs mysql

# 检查容器状态
docker ps -a

# 检查资源使用
docker stats
```

### 7.5 数据丢失

```bash
# 检查数据卷
docker volume ls
docker volume inspect docker-stack_redis-data

# 检查数据目录
ls -la ~/docker-stack/data/

# 如果数据目录为空，可能是权限问题
sudo chown -R 1000:1000 ~/docker-stack/data/
```

### 7.6 内存不足

```bash
# 查看内存使用
free -h

# 查看各容器内存使用
docker stats --no-stream

# 添加 swap（如果内存不足）
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### 7.7 磁盘空间不足

```bash
# 查看 Docker 磁盘使用
docker system df

# 清理无用资源
./docker_cleaner.sh -a

# 查看数据目录大小
du -sh ~/docker-stack/data/*
```

---

## 常用命令速查

```bash
# === Docker 基础 ===
docker ps                          # 查看运行中的容器
docker ps -a                       # 查看所有容器
docker images                      # 查看镜像列表
docker stats                       # 实时资源监控
docker system df                   # 磁盘使用情况

# === Docker Compose ===
docker compose ps                  # 查看服务状态
docker compose up -d               # 后台启动
docker compose down                # 停止并删除
docker compose logs -f             # 查看日志
docker compose restart             # 重启服务
docker compose pull                # 拉取最新镜像

# === 部署脚本 ===
./docker_compose_deploy.sh list    # 列出组件
./docker_compose_deploy.sh deploy  # 部署组件
./docker_compose_deploy.sh up      # 启动服务
./docker_compose_deploy.sh down    # 停止服务
./docker_compose_deploy.sh status  # 查看状态
./docker_compose_deploy.sh logs    # 查看日志
./docker_compose_deploy.sh info    # 查看凭据
./docker_compose_deploy.sh clean   # 清理环境
```

---

## 版本信息

- 文档版本: 2.0
- 更新日期: 2026-08-06
- 组件版本: 2026年8月最新稳定版
- 适用系统: CentOS 7+ / Ubuntu 20.04+