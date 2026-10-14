# 实用脚本集合

一个跨平台的实用脚本集合，包含 Windows 和 Linux 常用工具，以及 Docker 基础设施一键部署方案。

## 目录结构

```
scripts/
├── README.md                    # 主说明文档
├── .gitignore                   # Git忽略文件
├── LICENSE                      # 开源协议
│
├── windows/                     # Windows 脚本目录
│   ├── Window Beyond Compare重置试用.bat  # BC试用期重置
│   ├── Window微信多开.bat                  # 微信多开工具
│   ├── Windows系统一键优化.bat              # 系统隐私/性能一键优化
│   └── tools/                             # Linux风格命令工具集
│       ├── ls.ps1, du.ps1, df.ps1...     # 55个Linux风格命令
│       ├── install.ps1                    # 安装脚本
│       └── README.md                      # tools详细说明
│
└── linux/                       # Linux 脚本目录
    ├── system_diagnostic.sh               # 系统诊断脚本
    ├── system_monitor.sh                  # 实时系统监控
    ├── process_watchdog.sh                # 进程守护
    ├── io_monitor.sh                      # 磁盘I/O监控
    ├── backup_manager.sh                  # 备份管理器
    ├── db_backup.sh                       # 数据库备份
    ├── security_audit.sh                  # 安全审计
    ├── ssh_key_manage.sh                  # SSH密钥管理
    ├── sudo_audit.sh                      # sudo权限审计
    ├── port_scanner.sh                    # 端口扫描器
    ├── service_deploy.sh                  # 服务部署
    ├── system_tuner.sh                    # 系统调优
    ├── log_analyzer.sh                    # 日志分析
    ├── error_summary.sh                   # 错误汇总告警
    ├── README.md                          # Linux脚本说明
    │
    └── docker/                            # Docker 工具脚本
        ├── docker_install.sh              # Docker自动安装
        ├── docker_compose_deploy.sh       # 基础设施一键部署(28+组件)
        ├── docker_cleaner.sh              # Docker资源清理
        ├── DEPLOYMENT_GUIDE.md            # 详细部署操作手册
        └── README.md                      # Docker脚本说明
```

---

## Windows 脚本

### windows/tools/ - Linux风格命令工具集 (55个命令)

在 Windows PowerShell 中使用 Linux 风格的常用命令。

**安装：**
```powershell
cd windows/tools
.\install.ps1
```

**命令分类：**

| 类别 | 命令 |
|------|------|
| 文件操作 | ls, ll, cat, head, tail, more, less, touch, rm, cp, mv, mkdir, pwd, find, tree, which |
| 文本处理 | grep, awk, sort, uniq, cut, tr, wc, tee, xargs, basename, dirname, realpath |
| 系统信息 | df, du, free, uptime, ps, top, htop, kill, whoami, hostname, date, env, cal |
| 网络工具 | ip, ifconfig, netstat, ss, dig, nc, traceroute |
| 压缩下载 | zip, unzip, wget, curl |
| 其他 | history |

---

### windows/Window Beyond Compare重置试用.bat

重置 Beyond Compare 4.x/5.x 的试用期，右键以管理员身份运行。

### windows/Window微信多开.bat

快速启动多个微信实例，支持运行中直接多开。

### windows/Windows系统一键优化.bat

**版本: v2.0**

Windows系统一键优化脚本，右键以管理员身份运行。支持3级优化等级选择，默认为严重等级。

**使用方法:**
1. 右键以管理员身份运行
2. 选择优化等级（默认回车为严重等级）
3. 等待优化完成，建议重启电脑

**等级说明:**

| 等级 | 说明 | 项目数 |
|------|------|--------|
| 严重 | 严重影响系统性能/安全/隐私，强烈建议优化 | 7项 |
| 一般 | 对系统有一定作用，推荐优化 | 9项 |
| 轻微 | 可优化也可不优化，根据个人喜好选择 | 7项 |

**各等级优化项目:**

**严重等级 (7项):**
- ✅ 关闭Windows自动更新（禁止系统强制更新）
- ✅ 禁用遥测和数据收集服务（保护隐私，减少后台资源）
- ✅ 禁用SMB 1.0协议（老旧协议，安全漏洞重灾区）
- ✅ 禁用远程访问服务（远程桌面、远程注册表、远程协助）
- ✅ 禁用Cortana和Web搜索（减少资源占用和隐私泄露）
- ✅ 禁用SysMain超级预读（减少磁盘IO消耗）
- ✅ 禁用系统休眠（节省C盘几个GB空间）

**一般等级 (9项):**
- ✅ 关闭系统通知和推送（减少干扰和后台活动）
- ✅ 禁用多余自启动项（加快开机速度）
- ✅ 基础隐私设置优化（广告ID、SmartScreen、应用权限）
- ✅ 清除文件浏览记录和运行历史（保护隐私）
- ✅ 关闭活动历史记录和剪贴板同步（保护隐私）
- ✅ 关闭广告ID和位置服务（保护隐私）
- ✅ 禁用动画效果（提升系统响应速度）
- ✅ 禁用应用建议和广告（减少干扰）
- ✅ Microsoft Edge优化（禁用启动加速、后台运行、数据收集）

**轻微等级 (7项):**
- ✅ 资源管理器优化（显示扩展名、默认打开此电脑等）
- ✅ 关闭透明效果（减少GPU消耗）
- ✅ 加快开关机超时设置（自动结束无响应程序）
- ✅ 禁用NetBIOS和LLMNR（安全增强）
- ✅ 释放可保留带宽，禁用WiFi感知
- ✅ 清理不常用服务（传真、蓝牙、错误报告等）
- ✅ 设置高性能电源计划

**其他特性:**
- 自动创建系统还原点，可随时回滚
- 优化完成后自动重启资源管理器
- 清晰的进度显示（当前/总数）

---

## Linux 脚本

### 系统运维脚本 (14个)

| 类别 | 脚本 | 功能 |
|------|------|------|
| 系统监控 | system_monitor.sh, process_watchdog.sh, io_monitor.sh | CPU/内存/磁盘/进程/I/O 实时监控 |
| 备份恢复 | backup_manager.sh, db_backup.sh | 全量/增量备份, MySQL/PostgreSQL备份 |
| 安全审计 | security_audit.sh, ssh_key_manage.sh, sudo_audit.sh | 端口/SUID/权限/SSH/sudo审计 |
| 网络工具 | port_scanner.sh | TCP/UDP端口扫描, Ping Sweep |
| 部署管理 | service_deploy.sh | 服务部署, 版本回滚, 健康检查 |
| 性能调优 | system_tuner.sh | 内核参数调优(网络/内存/文件系统) |
| 日志分析 | log_analyzer.sh, error_summary.sh | 多类型日志分析, 错误汇总告警 |
| 系统诊断 | system_diagnostic.sh | 完整系统诊断报告 |

### Docker 基础设施部署 (linux/docker/)

**一键部署 26+ 开发测试基础设施组件，支持单机和集群模式。**

#### 快速开始

```bash
# 1. 安装 Docker
cd linux/docker
sudo ./docker_install.sh -y --mirror china

# 2. 部署基础设施
./docker_compose_deploy.sh deploy

# 3. 查看状态和凭据
./docker_compose_deploy.sh status
./docker_compose_deploy.sh info
```

#### 支持的组件 (28个，2026年8月最新稳定版)

| 类别 | 组件 | 版本 | 集群模式 |
|------|------|------|---------|
| 数据库 | Redis, MySQL, PostgreSQL, MongoDB | 8.0, 8.4 LTS, 17, 8.0 | Redis: 哨兵/集群, MySQL: 主从/双主, PG: 主从, Mongo: 副本集 |
| 向量库 | pgvector | 0.8 (PG 17) | - |
| 存储 | MinIO, RustFS | RELEASE.2025-10-15, 1.0.0-alpha.69 | MinIO: 分布式(4节点) |
| 搜索 | Elasticsearch, OpenSearch | 8.19, 2.19 | ES: 集群(3节点), OS: 集群(3节点) |
| 消息队列 | RabbitMQ, Kafka, RocketMQ, Pulsar | 4.3, 8.3 (KRaft), 5.5, 4.2 | RabbitMQ: 集群, Kafka: KRaft集群, RocketMQ: 集群(3Broker) |
| 协调 | ZooKeeper | 3.9 | ZooKeeper: 集群(3节点) |
| 网关 | OpenResty, Kong | 1.27, 3.9 | - |
| 监控 | Prometheus, Alertmanager, Grafana, Loki, SkyWalking | 3.13, 0.29, 12.4, 3.7, 10.4 | - |
| 日志 | Logstash, Kibana, Promtail | 8.19, 3.7 | - |
| 安全 | Keycloak, Sentinel | 26.6, 1.8 | Keycloak: 集群(2节点,共享DB) |
| 调度 | XXL-Job, PowerJob | 3.4, 5.1 | - |
| 注册中心 | Nacos | 3.2 | Nacos: 集群(3节点) |

#### 预设方案

| 方案 | 包含组件 |
|------|---------|
| dev-minimal | redis, mysql, minio |
| dev-full | redis, mysql, postgresql, mongodb, minio, nacos, rabbitmq, kafka, zookeeper |
| monitoring | prometheus, grafana, loki |
| monitoring-full | prometheus, alertmanager, grafana, loki, promtail |
| elk | elasticsearch, kibana, logstash |
| all-databases | redis, mysql, postgresql, mongodb |
| all-mq | rabbitmq, kafka, rocketmq, zookeeper, pulsar |
| storage | minio, rustfs |
| cluster-mq | kafka:cluster, rabbitmq:cluster, rocketmq:cluster |

#### 详细文档

完整部署操作手册请参考：[DEPLOYMENT_GUIDE.md](linux/docker/DEPLOYMENT_GUIDE.md)

---

## 快速使用

### Windows

```powershell
# 安装 Linux 风格命令
cd windows/tools
.\install.ps1
# 重启终端后即可使用: ls -la, df -h, grep, find, tree 等
```

### Linux

```bash
# 系统监控
./linux/system_monitor.sh -i 2 -t 80

# 安全审计
sudo ./linux/security_audit.sh

# Docker 安装 + 基础设施部署
sudo ./linux/docker/docker_install.sh -y --mirror china
./linux/docker/docker_compose_deploy.sh deploy redis,mysql,postgresql,minio,rustfs
```

---

## 注意事项

- Windows 脚本需在 PowerShell 5+ 环境运行
- Linux 脚本需在 CentOS 7+ 或 Ubuntu 20.04+ 运行
- 大部分运维脚本需要 root 权限
- Docker 部署脚本需先安装 Docker
- 数据卷统一挂载到 `~/docker-stack/data/` 目录

---

## 开源协议

本仓库脚本仅供学习交流使用。