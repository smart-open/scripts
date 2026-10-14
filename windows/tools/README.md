# Windows Linux 风格命令工具集

在 Windows PowerShell 中使用 Linux 风格的常用命令。

## 安装

1. 以管理员身份打开 PowerShell
2. 进入 tools 目录
3. 运行安装脚本：

```powershell
.\install.ps1
```

4. 重启终端使 PATH 生效

## 可用命令列表

### 文件和目录操作

| 命令 | 功能说明 | 用法示例 |
|------|---------|---------|
| ls | 列出目录内容 | `ls`, `ls -la`, `ls -h` |
| pwd | 显示当前路径 | `pwd` |
| cd | 切换目录 | `cd C:\Users` (PowerShell自带) |
| cp | 复制文件 | `cp source.txt dest.txt`, `cp -r dir1 dir2` |
| mv | 移动文件 | `mv old.txt new.txt` |
| rm | 删除文件 | `rm file.txt`, `rm -rf dir` |
| mkdir | 创建目录 | `mkdir newdir`, `mkdir -p a/b/c` |
| touch | 创建空文件 | `touch newfile.txt` |
| open | 打开资源管理器 | `open` (当前目录), `open C:\Users` (指定目录) |

### 文件查看和搜索

| 命令 | 功能说明 | 用法示例 |
|------|---------|---------|
| cat | 查看文件内容 | `cat file.txt`, `cat -n file.txt` (带行号) |
| head | 查看文件开头 | `head file.txt`, `head -n 20 file.txt` |
| tail | 查看文件结尾 | `tail file.txt`, `tail -f log.txt` (实时跟踪) |
| more | 分页查看文件 | `more file.txt` |
| less | 分页查看文件 | `less file.txt` (同more) |
| grep | 搜索文本 | `grep "err" a.log`, `grep -i -n "err" *.log`, `grep -r -n "TODO" .`, `cat a.log \| grep -v DEBUG`, `ps \| grep chrome` |
| wc | 统计字数 | `wc file.txt`, `wc -l file.txt` (行数) |
| awk | 文本处理(简化) | `awk '{print $1}' file.txt`, `cat file.txt | awk '{print $1}'` |

### 系统信息

| 命令 | 功能说明 | 用法示例 |
|------|---------|---------|
| df | 磁盘使用情况 | `df`, `df -h` (人类可读) |
| du | 目录大小 | `du`, `du -sh`, `du -d 1` |
| free | 内存使用 | `free`, `free -h` |
| uptime | 系统运行时间 | `uptime` |

### 进程管理

| 命令 | 功能说明 | 用法示例 |
|------|---------|---------|
| ps | 列出进程 | `ps`, `ps -a`, `ps -n 10` |
| top | 进程资源排行 | `top`, `top -n 15` |
| htop | 交互式进程查看 | `htop`, `htop -Delay 1` |
| kill | 终止进程 | `kill 1234`, `kill -9 1234` (强制) |

### 网络工具

| 命令 | 功能说明 | 用法示例 |
|------|---------|---------|
| ifconfig | 网络接口信息(Linux风格) | `ifconfig`, `ifconfig -a`(含未连接), `ifconfig -s`(流量统计), `ifconfig WLAN` |
| ip | 网络接口信息 | `ip`, `ip a` |
| netstat | 网络连接 | `netstat`, `netstat -tlnp` |
| ss | 套接字统计 | `ss`, `ss -t` (TCP) |
| dig | DNS查询(简化) | `dig google.com`, `dig google.com MX`, `dig google.com NS` |

### 压缩和下载

| 命令 | 功能说明 | 用法示例 |
|------|---------|---------|
| zip | 创建压缩包 | `zip archive.zip file.txt` |
| unzip | 解压文件 | `unzip archive.zip`, `unzip archive.zip -d dest` |
| wget | 下载文件 | `wget https://example.com/file.txt` |
| curl | HTTP请求 | `curl https://example.com` |

### 其他

| 命令 | 功能说明 | 用法示例 |
|------|---------|---------|
| ll | 详细列表(等同ls -l) | `ll` |
| find | 查找文件 | `find . -Name *.ps1` |
| tree | 目录树 | `tree`, `tree -Level 2` |
| diff | 文件对比 | `diff a.txt b.txt` |
| sort | 排序 | `sort file.txt`, `sort -r -n file.txt` |
| uniq | 去重 | `uniq file.txt` |
| cut | 按列切分 | `cut -d , -f 1 file.txt` |
| tr | 字符替换 | `tr a-z A-Z < file.txt` |
| tee | 分流输出 | `cat a.txt \| tee out.txt` |
| xargs | 参数传递 | `... \| xargs rm` |
| basename | 取文件名 | `basename C:\tmp\a.txt` |
| dirname | 取目录名 | `dirname C:\tmp\a.txt` |
| realpath | 取绝对路径 | `realpath a.txt` |
| which | 查找命令位置 | `which grep` |
| hostname | 主机名 | `hostname` |
| whoami | 当前用户 | `whoami` |
| date | 日期时间 | `date` |
| env | 环境变量 | `env` |
| cal | 日历 | `cal` |
| nc | 端口连通性测试 | `nc localhost 8080` |
| traceroute | 路由跟踪 | `traceroute google.com` |
| history | 命令历史 | `history`, `history 10` |

---

## 新命令详细说明

### 🔍 dig - DNS查询工具

**功能：** 查询DNS记录（支持IPv6）

**支持的查询类型：**
- A - IPv4地址记录
- **AAAA - IPv6地址记录**
- MX - 邮件交换记录
- NS - 域名服务器记录
- TXT - 文本记录
- CNAME - 别名记录

**用法示例：**
```powershell
dig google.com              # 查询IPv4地址
dig google.com AAAA         # 查询IPv6地址
dig google.com MX           # 查询邮件服务器
dig google.com NS           # 查询域名服务器
```

---

### 📝 awk - 文本处理工具

**功能：** 简单的awk风格文本处理

**支持的变量：**
- `$0` - 整行内容
- `$1, $2, $3...` - 第N个字段
- `NF` - 字段数量
- `NR` - 当前行号

**用法示例：**
```powershell
# 打印第一列
awk '{print $1}' file.txt

# 打印行号和整行
awk '{print NR ": " $0}' file.txt

# 管道输入
cat file.txt | awk '{print $1, $2}'
```

---

### 🖥️ htop - 交互式进程查看器

**功能：** 简化版htop，实时显示系统资源和进程

**特点：**
- CPU和内存使用进度条可视化 (█ ░)
- 按CPU/内存/PID排序（运行时可切换）
- 自动刷新（默认2秒）
- 按Q键退出

**用法示例：**
```powershell
htop                           # 默认按CPU排序启动
htop -SortBy MEM              # 按内存排序启动
htop -Delay 1 -SortBy PID     # 1秒刷新，按PID排序
```

**运行时按键操作：**
- `Q` 键：退出程序
- `C` 键：按CPU使用率排序
- `M` 键：按内存使用率排序
- `P` 键：按PID排序

---

### 🌐 ifconfig - 网络接口信息（Linux 风格）

**功能：** 以 Linux `ifconfig` 的输出格式显示网卡信息

**输出字段：**
- `flags=4163<UP,BROADCAST,RUNNING,MULTICAST>`：按 Linux 位掩码累加（UP=1, BROADCAST=2, LOOPBACK=8, RUNNING=64, MULTICAST=4096）
- `mtu`：取自 `Get-NetIPInterface.NlMtu`
- `inet` / `netmask` / `broadcast`：IPv4 地址，掩码由前缀长度换算，广播地址按位计算
- `inet6` / `prefixlen` / `scopeid`：IPv6 地址（`fe80::` → `0x20<link>`）
- `ether`：MAC 地址（`-` 转 `:`），括号内为介质类型与速率
- `RX/TX packets bytes`：流量统计（部分虚拟网卡无统计则不显示）

**用法示例：**
```powershell
ifconfig                    # 仅显示已连接(Up)的接口
ifconfig -a                 # 显示所有接口（含未连接、蓝牙等）
ifconfig -s                 # 仅显示流量统计表格
ifconfig WLAN               # 只显示指定接口（名称支持模糊匹配）
```

**退出码：** 0 = 找到接口；1 = 指定接口不存在

---

### 🔎 grep - 文本搜索

**功能：** 搜索文件内容或管道输入，语义尽量贴近 Linux grep

**支持的选项：**
- `-i` 忽略大小写（旧版本该参数声明了但未生效，已修复）
- `-r` 目录递归搜索
- `-n` 显示行号
- `-v` 反向匹配
- `-l` 只列出包含匹配的文件名
- `-c` 只输出每个文件的匹配行数
- `-w` 整词匹配
- `-E` 扩展正则（正则默认开启，此参数仅为兼容）

**用法示例：**
```powershell
grep "error" app.log                 # 单文件搜索
grep -i -n "error" *.log             # 通配符 + 忽略大小写 + 行号
grep -r -n "TODO" .                  # 递归搜索当前目录
grep -l -i "panic" *.log             # 只列出命中的文件
cat app.log | grep -v "DEBUG"        # 管道过滤（支持文件与命令输出）
ps | grep chrome                     # 对命令输出（对象）按文本匹配
```

**退出码：** 0 = 有匹配；1 = 无匹配；2 = 用法错误或文件不存在（可用于 `if` 判断）

**说明：** 多个文件/递归时输出前缀 `相对路径:行号:内容`；单文件时与 Linux 一致不加文件名前缀。

---

## 技术说明

- 所有命令均使用 PowerShell 脚本实现，无需安装额外软件
- 支持常见的 Linux 风格参数
- 由于 PowerShell 限制，部分功能与原版 Linux 命令可能略有差异

## 实现状态

✅ 已实现（55个命令）：
- **文件操作**: ls, ll, cat, head, tail, more, less, touch, rm, cp, mv, mkdir, pwd, find, tree, wc, grep, awk, sort, uniq, cut, tr, tee, xargs, basename, dirname, realpath, which, open, diff
- **系统信息**: df, du, free, uptime
- **进程管理**: ps, top, htop, kill
- **网络工具**: ip, **ifconfig**, netstat, ss, dig, nc, traceroute
- **压缩下载**: zip, unzip, wget, curl
- **其他**: history, whoami, hostname, date, env, cal

## 注意事项

- 首次使用需要将 tools 目录添加到系统 PATH
- 重启终端后才能使用新命令
- 某些命令需要管理员权限（如 netstat -b）
- htop 的交互式功能较为简化，仅支持刷新和退出
- awk 仅支持基础的字段打印，不支持复杂模式匹配
- grep 不支持 `-A/-B/-C` 上下文行与 `--color`；Windows PowerShell 5.1 下无 BOM 的 UTF-8 文件按系统 ANSI 代码页读取（PowerShell 7 无此问题）
- ifconfig 不显示网关/DNS（Linux 原版也不显示），接口名使用 Windows 名称（如 `WLAN`、`以太网`）
