# Linux 实用脚本集合

本目录包含18个运维实用脚本，涵盖系统监控、备份、安全审计、部署管理、Docker基础设施等多个领域。

---

## 脚本列表

### 📊 系统监控类

| 脚本 | 功能 | 主要特性 |
|------|------|---------|
| **system_monitor.sh** | 实时系统监控 | CPU/内存/磁盘监控、阈值告警、进程排名 |
| **process_watchdog.sh** | 进程守护监控 | 异常自动重启、邮件告警、多进程监控 |
| **io_monitor.sh** | 磁盘I/O监控 | 读写速度统计、Top I/O进程、阈值告警 |
| **monitor_dog.sh** | 终端围栏小狗 | 动画看门狗：指标越阈值站定吠叫播报、恢复播报警报解除、无告警时打盹/搞怪特效 |

### 💾 备份恢复类

| 脚本 | 功能 | 主要特性 |
|------|------|---------|
| **backup_manager.sh** | 文件备份管理器 | 全量/增量备份、自动清理、压缩存储 |
| **db_backup.sh** | 数据库备份 | MySQL/PostgreSQL支持、自动轮换恢复 |

### 🔐 安全审计类

| 脚本 | 功能 | 主要特性 |
|------|------|---------|
| **security_audit.sh** | 系统安全扫描 | 端口检查、SUID扫描、弱权限审计、内核加固 |
| **ssh_key_manage.sh** | SSH密钥管理 | 批量分发、远程部署、连接测试 |
| **sudo_audit.sh** | sudo权限审计 | 密码检查、命令限制、日志审计 |

### 🌐 网络工具类

| 脚本 | 功能 | 主要特性 |
|------|------|---------|
| **port_scanner.sh** | 端口扫描器 | TCP/UDP扫描、服务发现、Ping Sweep |

### 🐳 Docker相关

| 脚本 | 功能 | 主要特性 |
|------|------|---------|
| **docker_cleaner.sh** | Docker清理工具 | 容器/镜像/卷/网络清理、定期执行 |

### 🚀 部署发布类

| 脚本 | 功能 | 主要特性 |
|------|------|---------|
| **service_deploy.sh** | 服务部署工具 | 一键部署、版本回滚、健康检查 |

### ⚡ 性能调优类

| 脚本 | 功能 | 主要特性 |
|------|------|---------|
| **system_tuner.sh** | 系统参数调优 | 网络优化、内存调优、文件系统配置 |

### 📝 日志分析类

| 脚本 | 功能 | 主要特性 |
|------|------|---------|
| **log_analyzer.sh** | 日志分析器 | Auth/Nginx/系统日志分析、HTML报告生成 |
| **error_summary.sh** | 错误汇总告警 | 多日志聚合、统计报表、邮件告警 |

### 🐳 Docker基础设施类 (位于 `docker/` 子目录)

| 脚本 | 功能 | 主要特性 |
|------|------|---------|
| **docker/docker_install.sh** | Docker自动安装 | CentOS/Ubuntu自动检测、最新版安装、中国镜像源支持 |
| **docker/docker_compose_deploy.sh** | 基础设施一键部署 | 29组件模板(含RustFS)、单机/集群模式(15种HA)、9种预设方案、统一数据卷管理 |
| **docker/docker_cleaner.sh** | Docker资源清理 | 容器/镜像/卷/网络清理、磁盘使用统计 |
| **docker/DEPLOYMENT_GUIDE.md** | 详细部署操作手册 | 完整安装/部署/使用/运维/故障排查文档 |

---

## 快速开始

### 通用要求
- 所有脚本需在Linux环境运行
- 部分脚本需要root权限
- 建议使用root或sudo执行

### 设置执行权限
```bash
chmod +x *.sh
```

### 脚本帮助信息
所有脚本均支持 `-h` 参数查看详细帮助：
```bash
./system_monitor.sh -h
./backup_manager.sh -h
./security_audit.sh -h
```

---

## 各脚本使用说明

### system_monitor.sh
系统资源实时监控工具

```bash
# 基本监控（默认5秒间隔）
./system_monitor.sh

# 2秒间隔，告警阈值80%
./system_monitor.sh -i 2 -t 80
```

---

### process_watchdog.sh
关键进程守护，异常自动重启

```bash
# 监控nginx和mysql，30秒检查一次
./process_watchdog.sh -c nginx -c mysql -i 30

# 查看监控状态
./process_watchdog.sh -s
```

---

### monitor_dog.sh
终端围栏小狗：CPU/内存/磁盘/Swap/Load 任一越阈值时站定吠叫并播报指标与数值，全部恢复后播报警报解除。纯 bash + coreutils，不需要 root。

```bash
# 默认：2秒采样，阈值80%
bash monitor_dog.sh

# 自定义阈值与采样周期，并写日志
bash monitor_dog.sh -i 2 -a 85 --log

# 固定模拟快照（无需等待真实负载）
bash monitor_dog.sh --simulate 'cpu=95 mem=20 disk=30 swap=0 load=1.0' --frames 20

# 静音、无色、逐帧追加输出
bash monitor_dog.sh --no-sound --no-color --no-clear
```

主要选项：`-i` 采样周期、`-a` 百分比阈值、`--load-threshold` 负载阈值、`--bark-interval` 告警重复播报间隔、`--simulate` / `--simulate-file` 模拟快照、`--frames` 帧数、`--log` 日志、`--no-sound/--no-color/--no-clear`。终端建议宽度 ≥ 82 列。

---

### backup_manager.sh
灵活的备份管理工具

```bash
# 全量备份
./backup_manager.sh -p /data -d /backup -t full

# 增量备份
./backup_manager.sh -p /data -d /backup -t incr

# 恢复备份
./backup_manager.sh -r /backup/xxx.tar.gz -p /restore
```

---

### db_backup.sh
数据库自动备份

```bash
# MySQL备份
./db_backup.sh -t mysql -u root -p password -d mydb

# PostgreSQL备份
./db_backup.sh -t pgsql -u postgres -d mydb
```

---

### security_audit.sh
全面系统安全审计

```bash
# 完整审计
./security_audit.sh

# 指定输出报告文件
./security_audit.sh -o /var/log/audit_report.log
```

---

### ssh_key_manage.sh
SSH密钥批量管理

```bash
# 生成密钥
./ssh_key_manage.sh -a generate

# 批量添加密钥到主机
./ssh_key_manage.sh -a add -k ~/.ssh/id_rsa.pub -h hosts.txt -u root

# 批量删除密钥
./ssh_key_manage.sh -a remove -h hosts.txt
```

---

### port_scanner.sh
网络端口扫描

```bash
# 扫描常用端口
./port_scanner.sh -t 192.168.1.100

# 指定端口范围
./port_scanner.sh -t 192.168.1.100 -p 1-1000

# 扫描子网
./port_scanner.sh -s 192.168.1.0/24
```

---

### service_deploy.sh
自动化服务部署

```bash
# 部署新版本
./service_deploy.sh -n myapp -v 1.2.0 -a deploy -u http://.../app.tar.gz

# 回滚到上一版本
./service_deploy.sh -n myapp -a rollback
```

---

### docker_cleaner.sh
Docker资源清理

```bash
# 清理所有无用资源
./docker_cleaner.sh -a

# 只清理悬空镜像
./docker_cleaner.sh -i

# 显示磁盘使用情况
./docker_cleaner.sh -s
```

---

### system_tuner.sh
系统性能调优

```bash
# 检查当前配置
./system_tuner.sh -a check

# 应用服务器优化配置
./system_tuner.sh -p server -a apply

# 应用数据库优化配置
./system_tuner.sh -p database -a apply

# 恢复备份
./system_tuner.sh -a restore
```

---

### log_analyzer.sh
多类型日志分析

```bash
# 分析认证日志
./log_analyzer.sh -l auth

# 分析nginx日志
./log_analyzer.sh -l nginx

# 分析所有日志
./log_analyzer.sh -l all -o report.html
```

---

### error_summary.sh
错误汇总告警

```bash
# 过去24小时汇总
./error_summary.sh -t 24h

# 过去1小时汇总，超过10个错误发邮件
./error_summary.sh -t 1h -e admin@example.com -a 10
```

---

### docker/docker_install.sh
自动安装最新版Docker Engine和Docker Compose（支持CentOS/Ubuntu）

```bash
cd docker/

# 快速安装（默认官方源）
sudo ./docker_install.sh -y

# 使用中国镜像源安装
sudo ./docker_install.sh -y --mirror china

# 交互式安装
sudo ./docker_install.sh
```

功能特性：
- 自动检测CentOS/RHEL/Ubuntu/Debian
- 自动查询最新Docker版本
- 支持阿里云中国镜像源
- 自动配置daemon.json（日志轮转、overlay2）
- 自动添加用户到docker组

---

### docker/docker_compose_deploy.sh
通过Docker Compose一键部署29个基础设施组件（含RustFS）

```bash
cd docker/

# 查看所有可用组件
./docker_compose_deploy.sh list

# 交互式部署（显示菜单和预设方案）
./docker_compose_deploy.sh deploy

# 指定组件部署
./docker_compose_deploy.sh deploy redis,mysql,postgresql,minio,rustfs

# Redis哨兵模式 + MongoDB副本集
./docker_compose_deploy.sh deploy redis:sentinel,mysql,mongodb:rs

# Kafka KRaft集群（无需ZooKeeper）
./docker_compose_deploy.sh deploy kafka:cluster

# Nacos集群 + MinIO分布式
./docker_compose_deploy.sh deploy nacos:cluster,minio:distributed

# PostgreSQL主从 + OpenSearch集群 + Keycloak集群
./docker_compose_deploy.sh deploy postgresql:ha,opensearch:cluster,keycloak:cluster

# 启动/停止/查看状态
./docker_compose_deploy.sh up
./docker_compose_deploy.sh down
./docker_compose_deploy.sh status

# 查看日志
./docker_compose_deploy.sh logs redis

# 查看部署信息和凭据
./docker_compose_deploy.sh info

# 清理所有容器和数据
./docker_compose_deploy.sh clean
```

**预设方案（交互模式输入字母即可）：**
- `a. dev-minimal`: redis, mysql, minio
- `b. dev-full`: redis, mysql, postgresql, mongodb, minio, nacos, rabbitmq, kafka, zookeeper
- `c. monitoring`: prometheus, grafana, loki
- `d. elk`: elasticsearch, kibana, logstash
- `e. all-databases`: redis, mysql, postgresql, mongodb
- `f. all-mq`: rabbitmq, kafka, rocketmq, zookeeper, pulsar
- `g. storage`: minio, rustfs
- `h. cluster-mq`: kafka:cluster, rabbitmq:cluster, rocketmq:cluster
- `i. monitoring-full`: prometheus, alertmanager, grafana, loki, promtail

**支持的组件（29个）：**

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

**集群/高可用模式（15种）：**

| 组件 | 模式 | 说明 |
|------|------|------|
| Redis | `redis:sentinel` / `redis:cluster` | 哨兵(1主2从1哨兵) / 集群(6节点) |
| MySQL | `mysql:master-slave` / `mysql:dual-master` | 主从复制(GTID) / 双主互备(GTID) |
| PostgreSQL | `postgresql:ha` | 主从复制(流复制) |
| MongoDB | `mongodb:rs` | 副本集(1主2从) |
| RabbitMQ | `rabbitmq:cluster` | 集群(3节点) |
| Kafka | `kafka:cluster` | KRaft集群(3 Broker，无需ZooKeeper) |
| RocketMQ | `rocketmq:cluster` | 集群(2 NameServer + 3 Broker) |
| ZooKeeper | `zookeeper:cluster` | 集群(3节点) |
| Elasticsearch | `elasticsearch:cluster` | 集群(3节点) |
| OpenSearch | `opensearch:cluster` | 集群(3节点) |
| Nacos | `nacos:cluster` | 集群(3节点) |
| MinIO | `minio:distributed` | 分布式(4节点，纠删码) |
| Keycloak | `keycloak:cluster` | 集群(2节点，共享PostgreSQL) |

**预设方案：**

> 完整部署操作手册请参考: [docker/DEPLOYMENT_GUIDE.md](docker/DEPLOYMENT_GUIDE.md)

---

## 定时任务配置建议

使用crontab定期执行关键脚本：
```bash
# 每日凌晨2点执行完整备份
0 2 * * * /opt/scripts/backup_manager.sh -p /data -d /backup -t full

# 每小时执行错误汇总，超过50个告警
0 * * * * /opt/scripts/error_summary.sh -t 1h -e admin@example.com -a 50

# 每周日执行安全审计
0 3 * * 0 /opt/scripts/security_audit.sh -o /var/log/audit/$(date +\%Y\%m\%d).log

# 每周清理一次Docker
0 4 * * 0 /opt/scripts/docker_cleaner.sh -a
```

---

## 注意事项

1. **权限要求**：大部分脚本需要root权限执行，使用sudo或root用户
2. **依赖工具**：部分脚本依赖如mailx、iostat等系统工具
3. **日志文件**：默认日志输出到 `/var/log/` 目录下
4. **配置备份**：执行系统调优脚本前会自动备份配置
5. **测试环境**：建议在测试环境验证脚本后再在生产环境使用

---

## 版本信息

- Scripts Version: 1.0
- Last Updated: 2026-11
- Author: System Admin Team

---

## 原有的system_diagnostic脚本

### system_diagnostic.sh
系统综合诊断脚本，详见：[system_diagnostic_readme.md](system_diagnostic_readme.md)
```bash
# 执行完整系统诊断
./system_diagnostic.sh
```

| 脚本 | 主要功能 |
|------|---------|
| **system_diagnostic.sh** | 完整系统诊断 |
| | CPU/内存/磁盘/网络/进程/日志等10大类分析 |
| | 彩色输出、HTML报告生成 |
| | 自动健康评分和建议 |