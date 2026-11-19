#!/usr/bin/env bash
# =============================================================================
# monitor_dog.sh · v1.0
#   终端围栏小狗：NORMAL 时在围栏内来回嗅探巡逻；CPU/内存/磁盘/Swap/Load
#   任一指标越阈值时站定并持续「汪汪」，同时播报指标名与数值；全部恢复后
#   播报一次「警报解除」，随后继续嗅探巡逻。
#   依赖：bash >= 3.2、coreutils、awk、df。不写系统目录、不需要 root。
#   用法：bash monitor_dog.sh --help
# =============================================================================

VERSION="1.0"

# ---------------------------------------------------------------- 默认参数 ---
INTERVAL=2
THRESHOLD=80
LOAD_THRESHOLD=""
BARK_INTERVAL=2
FRAME_DELAY=0.2
SIM_SNAPSHOT=""
SIM_FILE=""
STOP_AFTER=0
NO_CLEAR=0
NO_SOUND=0
NO_COLOR=0
LOG_REQUEST=0
LOG_FILE=""
LOG_ON=0
LOG_FORCED_OFF=0

# ------------------------------------------------------------ 场景几何常量 ---
FENCE_W=80                              # 围栏内部列数（不含左右竖线）
FENCE_H=16                              # 围栏内部行数（启动时按终端高度自适应）
DOG_W=20                                # 狗造型单元格宽度
DOG_H=6                                 # 狗造型单元格高度（行数）
X_MIN=1                                 # 狗左边界（留 1 空格内边距）
X_MAX=$(( FENCE_W - DOG_W ))            # 60，狗右边界
Y_MIN=0                                 # 狗顶边（最上一行内部行）
Y_MAX=10                                # 狗底边（FENCE_H - DOG_H，启动时重算）
STEP=3                                  # 每帧水平步长
STEPY=2                                 # 每帧垂直步长

# ------------------------------------------------------------ 环境特效常量 ---
# 仅在 NORMAL（无告警）时偶发触发的趣味动作；ALERT 一律打断并清除。
# 阈值均可用同名环境变量覆盖，便于测试与个性化。
FX_REST_AFTER=${MONITOR_DOG_FX_REST_AFTER:-120}       # 连续无告警帧数达到此值且低负载 → 打盹休息
FX_REST_COOLDOWN=${MONITOR_DOG_FX_REST_COOLDOWN:-80}  # 打盹结束后再次打盹的冷却帧数
FX_IDLE_PCT=${MONITOR_DOG_FX_IDLE_PCT:-25}            # CPU 与内存都 ≤ 此值才算“资源利用率很低”
FX_IDLE_LOAD=${MONITOR_DOG_FX_IDLE_LOAD:-2.0}         # Load ≤ 此值才算空闲
FX_PLAY_EVERY=${MONITOR_DOG_FX_PLAY_EVERY:-55}        # 每隔多少无告警帧轮到一个搞怪动作
# 特效持续时长：默认每次在 [FX_DUR_MIN_SEC, FX_DUR_MAX_SEC] 秒内随机，按有效帧间隔换算成帧。
# 设 MONITOR_DOG_FX_SLEEP_FRAMES / MONITOR_DOG_FX_PLAY_FRAMES 可直接用帧数覆盖（供测试确定性）。
FX_DUR_MIN_SEC=${MONITOR_DOG_FX_DUR_MIN_SEC:-3}       # 特效最短持续秒数
FX_DUR_MAX_SEC=${MONITOR_DOG_FX_DUR_MAX_SEC:-5}       # 特效最长持续秒数
FX_SLEEP_FRAMES="${MONITOR_DOG_FX_SLEEP_FRAMES:-}"    # 空=按秒随机；非空=固定帧数
FX_PLAY_FRAMES="${MONITOR_DOG_FX_PLAY_FRAMES:-}"      # 空=按秒随机；非空=固定帧数

# ------------------------------------------------------------ 运行期状态量 ---
frame=0
STATE="NORMAL"
X=4
Y=0
DIR=1
DRAW_X=4
DRAW_Y=0
# 方形区域内的巡游航点（x,y）：启动时按围栏实际边界动态生成，覆盖四角与底边，
# 小狗在各航点间自由走动并在到点时嗅探。
WP=()
WP_N=0
WP_I=0
# 搞怪动作轮转序列（不含 SLEEP；SLEEP 由“久无告警+低负载”单独触发）
PLAY_SEQ=("ZOOM" "CATCH" "WATCH" "YAWN")
PLAY_N=4
TX=58
TY=0
POSE="RUN_R"
TURN=0
# 环境特效运行期状态
CALM_FRAMES=0            # 连续无告警帧数（进入 ALERT 归零）
REST_COOLDOWN=0          # 距下次可打盹的冷却帧数
NEXT_PLAY_AT=0           # CALM_FRAMES 达到此值时轮到一个搞怪动作
FX_ACTIVE=""             # 当前特效名：SLEEP/YAWN/ZOOM/CATCH/WATCH，空=无
FX_FRAMES_LEFT=0         # 当前特效剩余帧数
FX_PLAY_IDX=0            # 搞怪动作轮转下标（对应 PLAY_SEQ）
BARK_COUNT=0
BARK_EVERY=1
BARK_NOW=0
BROADCAST=0
LINE_ALERT=""
LINE_CAST=""
RECOVER_LINE=""
RECOVER_FRAME=0
CUR_VIOL=""
CUR_KEYS=""
LAST_VIOL=""
VIOL=""
SPOKEN=""
SIM_LAST=""
SIM_EOF=0
SIM_WARNED=0
SIM_EMPTY_WARNED=0
CPU_PREV_TOTAL=""
CPU_PREV_IDLE=""
CPU_BASELINE_HINT=0
CPU_HINT_SHOWN=0
ALERT_KEYS=""
HOLD_ACTIVE=0
UNKNOWN_COUNT=0
SWAP_DISABLED=0

M_CPU="N/A"
M_MEM="N/A"
M_DISK="N/A"
M_SWAP="N/A"
M_LOAD="N/A"
M_LOAD_DISP="N/A"

AR1=""
AR2=""
AR3=""
AR4=""
AR5=""
AR6=""

SOUND_ON=1
CLEAR_ON=1
COLOR_ON=1
TTS_BIN=""
TTS_DISABLED=0
TTS_FROM_ENV=0
TTS_PID=""
TTS_ARGS=()

# ------------------------------------------------------------------ 小工具 ---
say() {   # $1=颜色前缀（可为空） $2=文本
    if [ -n "$1" ]; then
        printf '%s%s%s%s\n' "$1" "$2" "$NC" "$EL"
    else
        printf '%s%s\n' "$2" "$EL"
    fi
}

warn() {
    printf '[警告] %s\n' "$*" >&2
}

int_ok() {   # 纯整数
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
    esac
    return 0
}

num_ok() {   # 整数或带小数的浮点
    case "$1" in
        ''|.|*[!0-9.]*|*.*.*) return 1 ;;
    esac
    return 0
}

pct_ok() {   # 百分比指标：纯整数且 0..100；先限位数，避免超过 Bash 整数范围
    int_ok "$1" || return 1
    _p=$1
    while [ "${#_p}" -gt 1 ] && [ "${_p#0}" != "$_p" ]; do
        _p=${_p#0}
    done
    [ "${#_p}" -le 3 ] && [ "$_p" -le 100 ]
}

pct_of() {   # 整数 → "NN%"，不可用 → "N/A"
    case "$1" in
        ''|*[!0-9]*) printf 'N/A' ;;
        *) printf '%s%%' "$1" ;;
    esac
}

log_line() {
    [ "$LOG_ON" -eq 1 ] || return 0
    if ! { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"; } 2>/dev/null; then
        LOG_ON=0
        warn "日志写入失败，已关闭日志"
    fi
}

usage() {
    cat <<'USAGE'
用法: monitor_dog.sh [选项]

  -i, --interval SEC      采样周期（秒），默认 2
  -a, --threshold PCT     CPU/内存/磁盘/Swap 阈值百分比，默认 80
      --load-threshold N  Load 阈值，默认 CPU 核数×2
      --bark-interval S   ALERT 期间重复播报间隔（秒），默认 2；0=每帧
      --frame-delay SEC   动画帧间隔（秒），默认 0.2；0=不等待
      --simulate "K=V.."  固定模拟快照，如 'cpu=95 mem=20 disk=30 swap=0 load=1.0'
      --simulate-file P   每帧从文件消费一行 K=V 快照
      --frames N          输出 N 帧后退出（0=无限）
      --no-clear          不清屏，逐帧追加（含 trace 行）
      --no-sound          关闭语音与响铃
      --no-color          关闭 ANSI 颜色
      --log [FILE]        写日志，缺省 ./monitor_dog.log
      --no-log            强制关闭日志
  -h, --help              显示本帮助
环境变量: MONITOR_DOG_TTS（语音命令，none 关闭）、MONITOR_DOG_LOG（日志路径）
环境特效（仅正常无告警时偶发）: 久无告警+低负载→打盹Zzz；周期轮转→搞怪腾跃/追球叼球/盯蝴蝶/打哈欠；告警立即打断
特效持续时长: 默认每次随机 3~5 秒（按帧间隔换算）；设 MONITOR_DOG_FX_SLEEP_FRAMES / FX_PLAY_FRAMES 可覆盖为固定帧数
特效可调阈值: MONITOR_DOG_FX_REST_AFTER(120) FX_REST_COOLDOWN(80)
              MONITOR_DOG_FX_IDLE_PCT(25) FX_IDLE_LOAD(2.0) FX_PLAY_EVERY(55)
              MONITOR_DOG_FX_DUR_MIN_SEC(3) FX_DUR_MAX_SEC(5)
终端建议: 宽度不少于 82 列；更窄时围栏会折行（启动时会提示）
USAGE
}

# -------------------------------------------------------------- 参数解析 ---
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--interval)
                [ $# -ge 2 ] || { warn "$1 需要一个参数"; usage >&2; exit 2; }
                INTERVAL="$2"; shift 2 ;;
            -a|--threshold)
                [ $# -ge 2 ] || { warn "$1 需要一个参数"; usage >&2; exit 2; }
                THRESHOLD="$2"; shift 2 ;;
            --load-threshold)
                [ $# -ge 2 ] || { warn "$1 需要一个参数"; usage >&2; exit 2; }
                LOAD_THRESHOLD="$2"; shift 2 ;;
            --bark-interval)
                [ $# -ge 2 ] || { warn "$1 需要一个参数"; usage >&2; exit 2; }
                BARK_INTERVAL="$2"; shift 2 ;;
            --frame-delay)
                [ $# -ge 2 ] || { warn "$1 需要一个参数"; usage >&2; exit 2; }
                FRAME_DELAY="$2"; shift 2 ;;
            --simulate)
                [ $# -ge 2 ] || { warn "$1 需要一个参数"; usage >&2; exit 2; }
                SIM_SNAPSHOT="$2"; shift 2 ;;
            --simulate-file)
                [ $# -ge 2 ] || { warn "$1 需要一个参数"; usage >&2; exit 2; }
                SIM_FILE="$2"; shift 2 ;;
            --frames)
                [ $# -ge 2 ] || { warn "$1 需要一个参数"; usage >&2; exit 2; }
                STOP_AFTER="$2"; shift 2 ;;
            --no-clear)   NO_CLEAR=1; shift ;;
            --no-sound)   NO_SOUND=1; shift ;;
            --no-color)   NO_COLOR=1; shift ;;
            --no-log)     LOG_REQUEST=0; LOG_FILE=""; LOG_FORCED_OFF=1; shift ;;
            --log)
                LOG_REQUEST=1
                LOG_FORCED_OFF=0
                if [ $# -ge 2 ]; then
                    case "$2" in
                        -*) ;;
                        *) LOG_FILE="$2"; shift ;;
                    esac
                fi
                shift ;;
            -h|--help)    usage; exit 0 ;;
            *)
                warn "未知参数: $1"
                printf '用法: monitor_dog.sh [选项]，详见 --help\n' >&2
                exit 2 ;;
        esac
    done

    # --simulate 与 --simulate-file 同给时以文件为准
    if [ -n "$SIM_FILE" ] && [ -n "$SIM_SNAPSHOT" ]; then
        warn "--simulate 与 --simulate-file 同时指定，以 --simulate-file 为准"
        SIM_SNAPSHOT=""
    fi

    # 采样周期
    if ! num_ok "$INTERVAL" || ! awk -v v="$INTERVAL" 'BEGIN{exit !(v+0 > 0)}'; then
        warn "非法采样周期 '$INTERVAL'，回退 2 秒"
        INTERVAL=2
    fi

    # 百分比阈值
    if ! int_ok "$THRESHOLD" || [ "$THRESHOLD" -lt 1 ] || [ "$THRESHOLD" -gt 100 ]; then
        warn "非法阈值 '$THRESHOLD'，回退 80"
        THRESHOLD=80
    fi

    # 播报间隔
    if ! num_ok "$BARK_INTERVAL" || ! awk -v v="$BARK_INTERVAL" 'BEGIN{exit !(v+0 >= 0)}'; then
        warn "非法播报间隔 '$BARK_INTERVAL'，回退 2 秒"
        BARK_INTERVAL=2
    fi

    # 帧间隔
    if ! num_ok "$FRAME_DELAY" || ! awk -v v="$FRAME_DELAY" 'BEGIN{exit !(v+0 >= 0)}'; then
        warn "非法帧间隔 '$FRAME_DELAY'，回退 0.2 秒"
        FRAME_DELAY=0.2
    fi

    # 帧数上限
    if ! int_ok "$STOP_AFTER"; then
        warn "非法帧数 '$STOP_AFTER'（需为非负整数）"
        exit 2
    fi

    # Load 阈值
    if [ -n "$LOAD_THRESHOLD" ]; then
        if ! num_ok "$LOAD_THRESHOLD" || ! awk -v v="$LOAD_THRESHOLD" 'BEGIN{exit !(v+0 > 0)}'; then
            warn "非法 Load 阈值 '$LOAD_THRESHOLD'，按核数重算"
            LOAD_THRESHOLD=""
        fi
    fi

    # 模拟文件可读性
    if [ -n "$SIM_FILE" ] && [ ! -r "$SIM_FILE" ]; then
        warn "模拟文件不可读: $SIM_FILE"
        exit 2
    fi
}

# ------------------------------------------------------------ 核数与阈值 ---
resolve_cores() {
    _n=""
    if command -v nproc >/dev/null 2>&1; then
        _n=$(nproc 2>/dev/null)
    fi
    if [ -z "$_n" ] && [ -r /proc/cpuinfo ]; then
        _n=$(awk '/^processor[ \t]*:/{c++} END{printf "%d", c+0}' /proc/cpuinfo 2>/dev/null)
    fi
    if [ -z "$_n" ] && command -v getconf >/dev/null 2>&1; then
        _n=$(getconf _NPROCESSORS_ONLN 2>/dev/null)
    fi
    case "$_n" in
        ''|*[!0-9]*) _n=1 ;;
    esac
    [ "$_n" -lt 1 ] && _n=1
    printf '%s' "$_n"
}

init_thresholds() {
    CORES=$(resolve_cores)
    if [ -z "$LOAD_THRESHOLD" ]; then
        LOAD_THRESHOLD=$(awk -v c="$CORES" 'BEGIN{printf "%.1f", c*2}')
    fi
    LOAD_THRESHOLD_DISP=$(awk -v v="$LOAD_THRESHOLD" 'BEGIN{printf "%.1f", v+0}')
}

# ---------------------------------------------------------------- 终端能力 ---
init_terminal() {
    # 无闪烁重绘：每帧仅把光标归位后原地覆盖，画完再擦除底部残留，
    # 不再用 \033[2J 整屏清空（清屏到画完之间会闪黑）。
    CLR=$'\033[H'
    ERASE=$'\033[J'
    EL=$'\033[K'
    NC=$'\033[0m'
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    CYAN=$'\033[0;36m'
    MAGENTA=$'\033[0;35m'
    DIM=$'\033[2m'
    CUR_OFF=$'\033[?25l'
    CUR_ON=$'\033[?25h'

    # 非 TTY 或 --no-clear：不移动/擦除光标，也不输出光标控制序列
    if [ ! -t 1 ] || [ "$NO_CLEAR" -eq 1 ]; then
        CLEAR_ON=0
    fi

    if [ ! -t 1 ] || [ "$NO_COLOR" -eq 1 ]; then
        COLOR_ON=0
    fi

    if [ "$COLOR_ON" -eq 0 ]; then
        RED=""; GREEN=""; YELLOW=""; CYAN=""; MAGENTA=""; DIM=""; NC=""
    fi
    if [ "$CLEAR_ON" -eq 0 ]; then
        CUR_OFF=""; CUR_ON=""
        CLR=""; ERASE=""; EL=""
    fi

    if [ "$NO_SOUND" -eq 1 ]; then
        SOUND_ON=0
    fi

    if [ -t 1 ]; then
        _cols=${COLUMNS:-}
        if [ -z "$_cols" ] && command -v tput >/dev/null 2>&1; then
            _cols=$(tput cols 2>/dev/null)
        fi
        case "$_cols" in
            ''|*[!0-9]*) ;;
            *) [ "$_cols" -lt $(( FENCE_W + 2 )) ] && warn "终端仅 ${_cols} 列，小于 $(( FENCE_W + 2 )) 列，动画可能折行" ;;
        esac

        # 方形围栏高度：按终端可用行数自适应。最高一帧为 FENCE_H+8 行
        # （标题/状态/上下边框/内部/指标/首帧提示/告警/播报），需 ≤ rows-1 才不会
        # 触发滚动——一旦滚动，基于光标归位的无闪烁重绘就会错位。故预留 9 行。
        _rows=${LINES:-}
        if [ -z "$_rows" ] && command -v tput >/dev/null 2>&1; then
            _rows=$(tput lines 2>/dev/null)
        fi
        case "$_rows" in
            ''|*[!0-9]*) ;;
            *)
                _fh=$(( _rows - 9 ))
                [ "$_fh" -lt $(( DOG_H + 2 )) ] && _fh=$(( DOG_H + 2 ))
                [ "$_fh" -gt 24 ] && _fh=24
                FENCE_H=$_fh
                ;;
        esac
    fi

    # 依据最终高度重算纵向边界，保证狗完整落在围栏内
    Y_MAX=$(( FENCE_H - DOG_H ))
    [ "$Y_MAX" -lt 0 ] && Y_MAX=0
    [ "$Y" -gt "$Y_MAX" ] && Y=$Y_MAX
}

# -------------------------------------------------------------------- 语音 ---
detect_tts() {
    TTS_BIN=""
    TTS_DISABLED=0
    TTS_FROM_ENV=0
    TTS_ARGS=()

    if [ -n "${MONITOR_DOG_TTS+x}" ]; then
        case "$MONITOR_DOG_TTS" in
            ""|none|off|0) TTS_DISABLED=1 ;;
            *" "*) warn "MONITOR_DOG_TTS 含空格，已忽略并回退探测" ;;
            *)
                if command -v "$MONITOR_DOG_TTS" >/dev/null 2>&1; then
                    TTS_BIN=$(command -v "$MONITOR_DOG_TTS")
                    TTS_FROM_ENV=1
                else
                    warn "MONITOR_DOG_TTS 指定的命令不可用: $MONITOR_DOG_TTS"
                fi
                ;;
        esac
    fi

    if [ -z "$TTS_BIN" ] && [ "$TTS_DISABLED" -eq 0 ]; then
        for _c in espeak-ng espeak spd-say; do
            if command -v "$_c" >/dev/null 2>&1; then
                TTS_BIN=$(command -v "$_c")
                break
            fi
        done
    fi

    if [ -n "$TTS_BIN" ]; then
        case "$(basename "$TTS_BIN")" in
            espeak-ng) TTS_ARGS=(-v cmn -s 165) ;;
            espeak)    TTS_ARGS=(-v zh -s 165) ;;
            spd-say)   TTS_ARGS=(-l zh -r -10) ;;
            *)         TTS_ARGS=() ;;
        esac
    fi

    # 自动探测到 espeak/espeak-ng 时，确认中文语音包是否存在；显式指定的命令不探测，
    # 避免包装脚本被额外的 --voices 调用干扰。
    if [ -n "$TTS_BIN" ] && [ "$TTS_FROM_ENV" -eq 0 ]; then
        case "$(basename "$TTS_BIN")" in
            espeak-ng|espeak)
                _voices=$("$TTS_BIN" --voices 2>/dev/null)
                if [ -n "$_voices" ]; then
                    _voice=""
                    printf '%s\n' "$_voices" | awk '$2=="cmn"{found=1} END{exit !found}' && _voice=cmn
                    if [ -z "$_voice" ]; then
                        printf '%s\n' "$_voices" | awk '$2=="zh"{found=1} END{exit !found}' && _voice=zh
                    fi
                    if [ -n "$_voice" ]; then
                        TTS_ARGS=(-v "$_voice" -s 165)
                    else
                        TTS_ARGS=()
                        warn "TTS 缺少中文语音包，改用默认语音（可安装 cmn/zh 语音包）"
                    fi
                fi
                ;;
        esac
    fi

    if [ "$SOUND_ON" -eq 1 ] && [ -z "$TTS_BIN" ] && [ "$TTS_DISABLED" -eq 0 ]; then
        # 全链缺失：只降级为文本 + 响铃，不退出
        say "$YELLOW" "[语音不可用]"
    fi
}

speak() {   # $1 = 要朗读的文本；整体作为单个参数传递，不做任何字符串拼接
    [ "$SOUND_ON" -eq 1 ] || return 0
    if [ -z "$TTS_BIN" ]; then
        # 非 TTY 时不把 BEL 写进管道/日志，避免污染下游输出
        if [ -t 1 ]; then printf '\a'; fi
        return 0
    fi
    # 单飞：上一个语音仍在运行时不叠加新进程，防止挂起的 TTS 无限堆积
    if [ -n "$TTS_PID" ]; then
        if kill -0 "$TTS_PID" 2>/dev/null; then
            return 0
        fi
        wait "$TTS_PID" 2>/dev/null
        TTS_PID=""
    fi
    "$TTS_BIN" "${TTS_ARGS[@]}" "$1" >/dev/null 2>&1 &
    TTS_PID=$!
}

# -------------------------------------------------------------------- 日志 ---
init_log() {
    LOG_ON=0
    [ "$LOG_FORCED_OFF" -eq 1 ] && return 0
    if [ -z "$LOG_FILE" ] && [ "$LOG_REQUEST" -eq 1 ]; then
        LOG_FILE="./monitor_dog.log"
    fi
    if [ -z "$LOG_FILE" ] && [ -n "${MONITOR_DOG_LOG:-}" ]; then
        LOG_FILE="$MONITOR_DOG_LOG"
    fi
    if [ "$LOG_REQUEST" -eq 0 ] && [ -z "$LOG_FILE" ]; then
        return 0
    fi
    _d=$(dirname "$LOG_FILE" 2>/dev/null)
    if [ -n "$_d" ] && [ ! -d "$_d" ]; then
        mkdir -p "$_d" 2>/dev/null
    fi
    if { printf '' >> "$LOG_FILE"; } 2>/dev/null; then
        LOG_ON=1
        LOG_FILE=$(printf '%s' "$LOG_FILE")
    else
        LOG_ON=0
        warn "无法写入日志 $LOG_FILE，已关闭日志"
    fi
}

# ------------------------------------------------------------------ 采样器 ---
parse_snapshot() {   # $1 = "cpu=.. mem=.. disk=.. swap=.. load=.."
    # 缺省为 N/A（未知），而不是 0（正常）：缺字段不能被当成“健康”
    M_CPU="N/A"; M_MEM="N/A"; M_DISK="N/A"; M_SWAP="N/A"; M_LOAD="N/A"
    SWAP_DISABLED=0
    _unknown=""
    set -f
    for _kv in $1; do
        case "$_kv" in
            *=*) ;;
            *) continue ;;
        esac
        _k=${_kv%%=*}
        _v=${_kv#*=}
        case "$_k" in
            cpu)  if pct_ok "$_v"; then M_CPU="$_v"; else M_CPU="N/A"; fi ;;
            mem)  if pct_ok "$_v"; then M_MEM="$_v"; else M_MEM="N/A"; fi ;;
            disk) if pct_ok "$_v"; then M_DISK="$_v"; else M_DISK="N/A"; fi ;;
            swap) if pct_ok "$_v"; then M_SWAP="$_v"; else M_SWAP="N/A"; fi ;;
            load) if num_ok "$_v"; then M_LOAD="$_v"; else M_LOAD="N/A"; fi ;;
            *)    _unknown="$_k" ;;
        esac
    done
    set +f
    if [ -n "$_unknown" ] && [ "$SIM_WARNED" -eq 0 ]; then
        SIM_WARNED=1
        warn "忽略未知模拟键: $_unknown"
    fi
    refresh_displays
}

refresh_displays() {
    if num_ok "$M_LOAD"; then
        M_LOAD_DISP=$(awk -v v="$M_LOAD" 'BEGIN{printf "%.2f", v+0}')
    else
        M_LOAD_DISP="N/A"
    fi

    UNKNOWN_COUNT=0
    pct_ok "$M_CPU"  || UNKNOWN_COUNT=$(( UNKNOWN_COUNT + 1 ))
    pct_ok "$M_MEM"  || UNKNOWN_COUNT=$(( UNKNOWN_COUNT + 1 ))
    pct_ok "$M_DISK" || UNKNOWN_COUNT=$(( UNKNOWN_COUNT + 1 ))
    pct_ok "$M_SWAP" || UNKNOWN_COUNT=$(( UNKNOWN_COUNT + 1 ))
    num_ok "$M_LOAD" || UNKNOWN_COUNT=$(( UNKNOWN_COUNT + 1 ))
}

sample_metrics() {
    if [ -n "$SIM_FILE" ]; then
        _t=""
        while IFS= read -r _t <&3; do
            # 兼容 Windows 换行与 UTF-8 BOM
            _t=${_t%$'\r'}
            _t=${_t#$'\xEF\xBB\xBF'}
            case "$_t" in
                ''|'#'*) continue ;;
            esac
            break
        done
        if [ -n "$_t" ]; then
            SIM_LAST="$_t"
            SIM_EOF=0
        else
            _t="$SIM_LAST"
            if [ -z "$SIM_LAST" ]; then
                SIM_EOF=2
                if [ "$SIM_EMPTY_WARNED" -eq 0 ]; then
                    SIM_EMPTY_WARNED=1
                    warn "模拟文件为空或没有有效快照: $SIM_FILE"
                fi
            else
                SIM_EOF=1
            fi
        fi
        parse_snapshot "$_t"
    elif [ -n "$SIM_SNAPSHOT" ]; then
        parse_snapshot "$SIM_SNAPSHOT"
    else
        sample_real
    fi
}

sample_real() {
    # ---- CPU：两次采样求差，首个周期只建基线（N/A，不告警）
    _stat=$(awk '/^cpu /{printf "%d %d", $2+$3+$4+$5+$6+$7+$8, $5+$6}' /proc/stat 2>/dev/null)
    _cpu="N/A"
    if [ -n "$_stat" ]; then
        _tot=${_stat%% *}
        _idle=${_stat##* }
        if [ -n "$CPU_PREV_TOTAL" ]; then
            _cpu=$(awk -v t="$_tot" -v i="$_idle" -v pt="$CPU_PREV_TOTAL" -v pi="$CPU_PREV_IDLE" \
                'BEGIN{d=t-pt; di=i-pi; if(d<=0){printf "%d", 0} else {v=(d-di)*100/d; if(v<0)v=0; if(v>100)v=100; printf "%d", v+0.5}}')
        else
            CPU_BASELINE_HINT=1
        fi
        CPU_PREV_TOTAL=$_tot
        CPU_PREV_IDLE=$_idle
    fi
    if pct_ok "$_cpu"; then M_CPU="$_cpu"; else M_CPU="N/A"; fi

    # ---- 内存：MemAvailable 优先，缺失时退化为 MemFree+Buffers+Cached
    _mem=$(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2; has=1} /^MemFree:/{f=$2} /^Buffers:/{b=$2} /^Cached:/{c=$2}
        END{ if (t+0 <= 0) { print ""; exit }
             if (has) { printf "%d", (t-a)*100/t }
             else { u=t-f-b-c; if (u<0) u=0; printf "%d", u*100/t } }' /proc/meminfo 2>/dev/null)
    if pct_ok "$_mem"; then M_MEM="$_mem"; else M_MEM="N/A"; fi

    # ---- 磁盘：df -P / 的容量百分比列（标准 GNU df 中即第 5 列；这里按 “NN%” 形态定位，
    #      防止设备名含空格时列位漂移；取不到百分比才回落 $5）
    _disk=$(df -P / 2>/dev/null | awk 'NR==2{
        for (i=1; i<=NF; i++) if ($i ~ /^[0-9]+%$/) { v=$i; gsub(/%/,"",v); print v; exit }
        v=$5; gsub(/%/,"",v); print v }')
    if pct_ok "$_disk"; then M_DISK="$_disk"; else M_DISK="N/A"; fi

    # ---- Swap：字段缺失 → N/A；SwapTotal 为 0（未启用）→ 0%，不做除法
    _swap=$(awk '/^SwapTotal:/{t=$2; ht=1} /^SwapFree:/{f=$2; hf=1}
        END{ if (!ht || !hf) { print ""; exit }
             if (t+0 <= 0) { print "disabled"; exit }
             printf "%d", (t-f)*100/t }' /proc/meminfo 2>/dev/null)
    SWAP_DISABLED=0
    if [ "$_swap" = "disabled" ]; then
        M_SWAP="0"
        SWAP_DISABLED=1
    elif pct_ok "$_swap"; then
        M_SWAP="$_swap"
    else
        M_SWAP="N/A"
    fi

    # ---- Load：/proc/loadavg 第 1 列
    _load=$(awk 'NR==1{print $1}' /proc/loadavg 2>/dev/null)
    if num_ok "$_load"; then M_LOAD="$_load"; else M_LOAD="N/A"; fi

    refresh_displays
}

# -------------------------------------------------------------- 阈值判定 ---
add_viol() {
    if [ -n "$VIOL" ]; then
        VIOL="$VIOL，$1"
    else
        VIOL="$1"
    fi
}

judge_alerts() {
    VIOL=""
    if pct_ok "$M_CPU" && [ "$M_CPU" -ge "$THRESHOLD" ]; then
        add_viol "CPU ${M_CPU}%↑(阈值 ${THRESHOLD}%)"
    fi
    if pct_ok "$M_MEM" && [ "$M_MEM" -ge "$THRESHOLD" ]; then
        add_viol "内存 ${M_MEM}%↑(阈值 ${THRESHOLD}%)"
    fi
    if pct_ok "$M_DISK" && [ "$M_DISK" -ge "$THRESHOLD" ]; then
        add_viol "磁盘 ${M_DISK}%↑(阈值 ${THRESHOLD}%)"
    fi
    if pct_ok "$M_SWAP" && [ "$M_SWAP" -ge "$THRESHOLD" ]; then
        add_viol "Swap ${M_SWAP}%↑(阈值 ${THRESHOLD}%)"
    fi
    if num_ok "$M_LOAD" && awk -v l="$M_LOAD" -v t="$LOAD_THRESHOLD" 'BEGIN{exit !(l+0 >= t+0)}'; then
        add_viol "Load ${M_LOAD_DISP}↑(阈值 ${LOAD_THRESHOLD_DISP})"
    fi
}

# ---------------------------------------------------------------- 状态机 ---
current_metric_text() {   # $1 = 指标名 → 当前值文本
    case "$1" in
        CPU)  printf 'CPU %s' "$(pct_of "$M_CPU")" ;;
        内存) printf '内存 %s' "$(pct_of "$M_MEM")" ;;
        磁盘) printf '磁盘 %s' "$(pct_of "$M_DISK")" ;;
        Swap) printf 'Swap %s' "$(pct_of "$M_SWAP")" ;;
        Load) printf 'Load %s' "$M_LOAD_DISP" ;;
        *)    printf '指标' ;;
    esac
}

keys_of_viol() {   # "$VIOL" → "CPU 内存 Load" 这样的指标名列表
    _ks=""
    for _k in CPU 内存 磁盘 Swap Load; do
        case "$1" in
            *"$_k"*) _ks="${_ks}${_ks:+ }$_k" ;;
        esac
    done
    printf '%s' "$_ks"
}

metric_val_ok() {   # 当前指标是否是可判定的有效数值
    case "$1" in
        CPU)  pct_ok "$M_CPU" ;;
        内存) pct_ok "$M_MEM" ;;
        磁盘) pct_ok "$M_DISK" ;;
        Swap) pct_ok "$M_SWAP" ;;
        Load) num_ok "$M_LOAD" ;;
        *)    return 1 ;;
    esac
}

transition_state() {
    if [ -n "$VIOL" ]; then
        CUR_VIOL="$VIOL"
        # 告警优先：打断任何环境特效并清零“无告警计时”
        CALM_FRAMES=0
        FX_ACTIVE=""
        FX_FRAMES_LEFT=0
        if [ "$STATE" != "ALERT" ]; then
            STATE="ALERT"
            BARK_COUNT=0
            ALERT_KEYS=""
            HOLD_ACTIVE=0
            log_line "ALERT frame=$frame $VIOL"
        fi
        for _k in $(keys_of_viol "$VIOL"); do
            case " $ALERT_KEYS " in
                *" $_k "*) ;;
                *) ALERT_KEYS="${ALERT_KEYS}${ALERT_KEYS:+ }$_k" ;;
            esac
        done
        HOLD_ACTIVE=0
        return 0
    fi

    if [ "$STATE" = "ALERT" ]; then
        # 先检查此前越界的指标：未知（N/A）不是“已回落”，必须保持警报。
        _hold=""
        for _k in $ALERT_KEYS; do
            if ! metric_val_ok "$_k"; then
                _hold="${_hold}${_hold:+、}$_k"
            fi
        done
        if [ -n "$_hold" ]; then
            CUR_VIOL="采样失败：${_hold} 为 N/A，保持警报"
            if [ "$HOLD_ACTIVE" -eq 0 ]; then
                HOLD_ACTIVE=1
                log_line "HOLD frame=$frame unknown=$_hold"
            fi
            return 0
        fi

        STATE="RECOVERED"
        RECOVER_FRAME=$frame
        HOLD_ACTIVE=0
        _rec=""
        for _k in $ALERT_KEYS; do
            _rec="${_rec}${_rec:+，}$(current_metric_text "$_k")"
        done
        [ -z "$_rec" ] && _rec="全部指标"
        RECOVER_LINE="[已恢复] 警报解除：${_rec} 已回落"
        SPOKEN="警报解除，${_rec} 已回落"
        log_line "RECOVERED frame=$frame"
        speak "$SPOKEN"
        ALERT_KEYS=""
        CUR_VIOL=""
    elif [ "$STATE" = "RECOVERED" ]; then
        STATE="NORMAL"
    fi
}

frame_bark() {   # 每帧调用：ALERT 每帧都有视觉吠叫行，语音/播报行按节流
    BARK_NOW=0
    BROADCAST=0
    LINE_ALERT=""
    LINE_CAST=""
    [ "$STATE" = "ALERT" ] || return 0

    BARK_COUNT=$(( BARK_COUNT + 1 ))
    BARK_NOW=1
    LINE_ALERT="[异常] 汪汪汪！${CUR_VIOL}"

    if [ "$BARK_COUNT" -eq 1 ] || [ "$BARK_EVERY" -le 1 ] || [ $(( BARK_COUNT % BARK_EVERY )) -eq 0 ]; then
        BROADCAST=1
        LINE_CAST="[播报] 异常: ${CUR_VIOL}，已持续 ${BARK_COUNT} 帧"
        SPOKEN="异常: ${CUR_VIOL}，已持续 ${BARK_COUNT} 帧"
        speak "$SPOKEN"
    fi
    return 0
}

# ---------------------------------------------------------------- 动画姿态 ---
# 侧视四足小狗，画布 20 列 × 6 行；头在右为正向，RUN_L 为整体水平镜像。
set_art() {
    case "$1" in
        RUN_R)
            AR1='              __    '
            AR2='   /\        /  \   '
            AR3='  /  \______/ o  \  '
            AR4=' /        \_____/   '
            AR5='  |  |      |  |    '
            AR6=' _|  |_    _|  |_   '
            ;;
        RUN_L)
            AR1='    __              '
            AR2='   /  \        /\   '
            AR3='  /  o \______/  \  '
            AR4='   \_____/        \ '
            AR5='    |  |      |  |  '
            AR6='   _|  |_    _|  |_ '
            ;;
        SNIFF)
            AR1='              __    '
            AR2='   /\        /  \   '
            AR3='  /  \______/ o  \  '
            AR4=' /        \____/    '
            AR5='  |  |      |  |    '
            AR6=' _|  |_    _|  |_   '
            ;;
        BARK_R)
            AR1='              __  !!'
            AR2='   /\        /  \ ! '
            AR3='  /  \______/ o  \  '
            AR4=' /        \_____/   '
            AR5='  |  |      |  |    '
            AR6=' _|  |_    _|  |_   '
            ;;
        HAPPY_R)
            AR1='    o           __  '
            AR2='   / \        /  \  '
            AR3='  /   \______/ o  \ '
            AR4=' /         \_____/  '
            AR5='  |  |      |  |    '
            AR6=' _|  |_    _|  |_   '
            ;;
        SLEEP)
            AR1='              Zzz   '
            AR2='   /\        /  \   '
            AR3='  /  \______/ -  \  '
            AR4=' /        \_____/   '
            AR5='  |  |      |  |    '
            AR6=' _|  |_    _|  |_   '
            ;;
        YAWN)
            AR1='              __    '
            AR2='   /\        /  \   '
            AR3='  /  \______/ o  \  '
            AR4=' /        \__O__/   '
            AR5='  |  |      |  |    '
            AR6=' _|  |_    _|  |_   '
            ;;
        ZOOM)
            AR1='         *  __      '
            AR2='   /\     */  \   * '
            AR3='  /  \_____/ o  \   '
            AR4=' /        \_____/   '
            AR5='  \  |      |  /    '
            AR6='   \_|      |_/     '
            ;;
        CATCH)
            AR1='              __    '
            AR2='   /\        /  \   '
            AR3='  /  \______/ o \(o)'
            AR4=' /        \_____/   '
            AR5='  |  |      |  |    '
            AR6=' _|  |_    _|  |_   '
            ;;
        WATCH)
            AR1='              __  * '
            AR2='   /\        /  \ /*'
            AR3='  /  \______/ o  \  '
            AR4=' /        \_____/   '
            AR5='  |  |      |  |    '
            AR6=' _|  |_    _|  |_   '
            ;;
        *)
            AR1=''
            AR2=''
            AR3=''
            AR4=''
            AR5=''
            AR6=''
            ;;
    esac
}

set_target() {   # $1="x,y" → 钳制到围栏内并写入 TX/TY
    _xy=$1
    TX=${_xy%%,*}
    TY=${_xy##*,}
    [ "$TX" -lt "$X_MIN" ] && TX=$X_MIN
    [ "$TX" -gt "$X_MAX" ] && TX=$X_MAX
    [ "$TY" -lt "$Y_MIN" ] && TY=$Y_MIN
    [ "$TY" -gt "$Y_MAX" ] && TY=$Y_MAX
}

build_waypoints() {   # 按围栏实际边界（X_MAX/Y_MAX）生成航点，确保覆盖真正的底边
    _xm=$X_MAX; _ym=$Y_MAX; _x0=$X_MIN; _y0=$Y_MIN
    _xc=$(( ( _x0 + _xm ) / 2 ))
    _yc=$(( ( _y0 + _ym ) / 2 ))
    WP=()
    # 右上 → 右下 → 底中 → 左下 → 左上 → 中心；右下/底中/左下都落在真正的底边 _ym
    WP+=("$_xm,$_y0")
    WP+=("$_xm,$_ym")
    WP+=("$_xc,$_ym")
    WP+=("$_x0,$_ym")
    WP+=("$_x0,$_y0")
    WP+=("$_xc,$_yc")
    WP_N=${#WP[@]}
    if [ "$WP_N" -lt 2 ]; then
        WP=("$_xm,$_y0" "$_x0,$_y0")
        WP_N=2
    fi
    WP_I=0
}

is_idle() {   # CPU 与内存都 ≤ FX_IDLE_PCT 且 Load ≤ FX_IDLE_LOAD 才算“资源利用率很低”
    pct_ok "$M_CPU"  || return 1
    pct_ok "$M_MEM"  || return 1
    num_ok "$M_LOAD" || return 1
    [ "$M_CPU" -le "$FX_IDLE_PCT" ] || return 1
    [ "$M_MEM" -le "$FX_IDLE_PCT" ] || return 1
    awk -v l="$M_LOAD" -v t="$FX_IDLE_LOAD" 'BEGIN{exit !(l+0 <= t+0)}' || return 1
    return 0
}

fx_start() {   # $1=特效名 $2=持续帧数 → 冻结小狗于该动作
    FX_ACTIVE="$1"
    FX_FRAMES_LEFT="$2"
}

fx_dur_frames() {   # $1=固定帧数覆盖(可空) → 本次特效持续帧数；无覆盖则在 [min,max] 秒内随机换算
    if [ -n "$1" ]; then printf '%s' "$1"; return 0; fi
    _lo=$FX_DUR_MIN_SEC; _hi=$FX_DUR_MAX_SEC
    [ "$_hi" -lt "$_lo" ] && _hi=$_lo
    _span=$(( _hi - _lo + 1 ))
    _sec=$(( _lo + (RANDOM % _span) ))
    # 秒 → 帧：sec*1000/TICK_MS（TICK_MS 已在主流程按有效帧间隔算好），至少 1 帧
    awk -v s="$_sec" -v t="$TICK_MS" 'BEGIN{ if(t<1)t=1; f=int(s*1000/t+0.5); if(f<1)f=1; printf "%d", f }'
}

# 每帧（NORMAL）推进环境特效计时与触发；返回 0=进入/保持特效（应冻结），1=正常走动
fx_tick() {
    CALM_FRAMES=$(( CALM_FRAMES + 1 ))
    [ "$REST_COOLDOWN" -gt 0 ] && REST_COOLDOWN=$(( REST_COOLDOWN - 1 ))

    # 特效进行中：倒计时，结束则收尾
    if [ -n "$FX_ACTIVE" ]; then
        FX_FRAMES_LEFT=$(( FX_FRAMES_LEFT - 1 ))
        if [ "$FX_FRAMES_LEFT" -le 0 ]; then
            [ "$FX_ACTIVE" = "SLEEP" ] && REST_COOLDOWN=$FX_REST_COOLDOWN
            FX_ACTIVE=""
            return 1
        fi
        return 0
    fi

    # 打盹休息：久无告警 + 冷却结束 + 资源利用率很低
    if [ "$CALM_FRAMES" -ge "$FX_REST_AFTER" ] && [ "$REST_COOLDOWN" -eq 0 ] && is_idle; then
        fx_start "SLEEP" "$(fx_dur_frames "$FX_SLEEP_FRAMES")"
        return 0
    fi

    # 搞怪动作：按无告警帧数周期轮转（ZOOM→CATCH→WATCH→YAWN）
    [ "$NEXT_PLAY_AT" -eq 0 ] && NEXT_PLAY_AT=$FX_PLAY_EVERY
    if [ "$CALM_FRAMES" -ge "$NEXT_PLAY_AT" ]; then
        fx_start "${PLAY_SEQ[$FX_PLAY_IDX]}" "$(fx_dur_frames "$FX_PLAY_FRAMES")"
        FX_PLAY_IDX=$(( (FX_PLAY_IDX + 1) % PLAY_N ))
        NEXT_PLAY_AT=$(( CALM_FRAMES + FX_PLAY_EVERY ))
        return 0
    fi
    return 1
}

update_anim() {
    DRAW_X=$X
    DRAW_Y=$Y
    if [ "$STATE" = "ALERT" ]; then
        POSE="BARK_R"
        TURN=0
        return 0
    fi
    if [ "$STATE" = "RECOVERED" ]; then
        POSE="HAPPY_R"
        TURN=0
        CALM_FRAMES=0
        NEXT_PLAY_AT=0
        FX_ACTIVE=""
        FX_FRAMES_LEFT=0
        return 0
    fi
    # NORMAL：先推进环境特效；若处于特效中则冻结于该动作，否则正常 2D 巡游
    if fx_tick; then
        POSE="$FX_ACTIVE"
        TURN=0
        return 0
    fi
    # 抵达当前航点后原地嗅探一帧，然后换下一个航点
    if [ "$X" -eq "$TX" ] && [ "$Y" -eq "$TY" ]; then
        POSE="SNIFF"
        TURN=1
        WP_I=$(( (WP_I + 1) % WP_N ))
        set_target "${WP[$WP_I]}"
        return 0
    fi
    TURN=0
    # 朝向取水平分量：向右走 RUN_R，向左走 RUN_L；纯垂直移动保持上一次朝向
    if [ "$X" -lt "$TX" ]; then
        DIR=1
    elif [ "$X" -gt "$TX" ]; then
        DIR=-1
    fi
    if [ "$DIR" -gt 0 ]; then
        POSE="RUN_R"
    else
        POSE="RUN_L"
    fi
    return 0
}

advance_pos() {
    [ "$STATE" = "ALERT" ] && return 0
    [ "$STATE" = "RECOVERED" ] && return 0
    # 特效进行中：原地定格，不位移
    [ -n "$FX_ACTIVE" ] && return 0
    # 嗅探帧原地不动
    [ "$TURN" -eq 1 ] && return 0

    # 水平朝 TX 逼近，步长 STEP，绝不越过目标
    if [ "$X" -lt "$TX" ]; then
        X=$(( X + STEP ))
        [ "$X" -gt "$TX" ] && X=$TX
    elif [ "$X" -gt "$TX" ]; then
        X=$(( X - STEP ))
        [ "$X" -lt "$TX" ] && X=$TX
    fi

    # 垂直朝 TY 逼近，步长 STEPY，绝不越过目标
    if [ "$Y" -lt "$TY" ]; then
        Y=$(( Y + STEPY ))
        [ "$Y" -gt "$TY" ] && Y=$TY
    elif [ "$Y" -gt "$TY" ]; then
        Y=$(( Y - STEPY ))
        [ "$Y" -lt "$TY" ] && Y=$TY
    fi

    # 兜底钳制：任何情况下都不越出围栏
    [ "$X" -lt "$X_MIN" ] && X=$X_MIN
    [ "$X" -gt "$X_MAX" ] && X=$X_MAX
    [ "$Y" -lt "$Y_MIN" ] && Y=$Y_MIN
    [ "$Y" -gt "$Y_MAX" ] && Y=$Y_MAX
    return 0
}

# ------------------------------------------------------------------ 渲染 ---
state_label() {
    case "$STATE" in
        ALERT)     printf '嗅探巡逻中(暂停)' ;;
        RECOVERED) printf '嗅探巡逻中(已恢复)' ;;
        *)         printf '嗅探巡逻中' ;;
    esac
}

pose_label() {
    case "$POSE" in
        RUN_R)   printf '奔跑(右)' ;;
        RUN_L)   printf '奔跑(左)' ;;
        SNIFF)   printf '嗅探' ;;
        BARK_R)  printf '吠叫' ;;
        HAPPY_R) printf '摇尾' ;;
        SLEEP)   printf '打盹休息' ;;
        YAWN)    printf '打哈欠' ;;
        ZOOM)    printf '搞怪腾跃' ;;
        CATCH)   printf '追球叼球' ;;
        WATCH)   printf '盯蝴蝶' ;;
        *)       printf '待命' ;;
    esac
}

fx_caption() {   # 特效说明行（含剩余帧，便于观察）
    case "$FX_ACTIVE" in
        SLEEP) printf '风平浪静、资源清闲，趴下打个盹… Zzz (%d 帧后醒)' "$FX_FRAMES_LEFT" ;;
        YAWN)  printf '伸个懒腰，打个哈欠～' ;;
        ZOOM)  printf '突然撒欢，原地腾跃！' ;;
        CATCH) printf '发现小球，扑过去叼住！' ;;
        WATCH) printf '盯上一只蝴蝶，目不转睛' ;;
        *)     printf '趣味动作' ;;
    esac
}

draw_frame() {
    if [ "$CLEAR_ON" -eq 1 ]; then
        printf '%s' "$CLR"
    fi

    _load_disp="$LOAD_THRESHOLD_DISP"
    say "$DIM" "Monitor Dog v${VERSION} · 采样 ${INTERVAL}s · 阈值 ${THRESHOLD}% · Load 阈值 ${_load_disp} · 帧 ${frame}"
    _st="$(state_label)"
    case "$SIM_EOF" in
        1) _st="$_st · 模拟序列结束(沿用末行)" ;;
        2) _st="$_st · 模拟文件为空(无可用快照)" ;;
    esac
    say "$CYAN" "状态: ${_st} · 姿态: $(pose_label) · $(date '+%H:%M:%S')"

    printf '+%s+\n' "$DASHES"
    _padl=$DRAW_X
    _padr=$(( FENCE_W - DRAW_X - DOG_W ))
    [ "$_padl" -lt 0 ] && _padl=0
    [ "$_padr" -lt 0 ] && _padr=0
    _r=0
    while [ "$_r" -lt "$FENCE_H" ]; do
        if [ "$_r" -ge "$DRAW_Y" ] && [ "$_r" -lt $(( DRAW_Y + DOG_H )) ]; then
            _ai=$(( _r - DRAW_Y + 1 ))
            _aname="AR$_ai"
            printf '|%*s%-*s%*s|\n' "$_padl" '' "$DOG_W" "${!_aname}" "$_padr" ''
        elif [ "$POSE" = "SNIFF" ] && [ "$_r" -eq $(( DRAW_Y + DOG_H )) ]; then
            # 嗅点落在狗正下方一行（若底部无空间则省略），随帧左右轻抖
            _c=$(( DRAW_X + 16 + (frame % 2) ))
            [ "$_c" -lt 1 ] && _c=1
            [ "$_c" -gt $(( FENCE_W - 3 )) ] && _c=$(( FENCE_W - 3 ))
            _line="$BLANKS"
            _line="${_line:0:$_c}. .${_line:$(( _c + 3 ))}"
            printf '|%s|\n' "$_line"
        else
            printf '|%s|\n' "$BLANKS"
        fi
        _r=$(( _r + 1 ))
    done
    printf '+%s+\n' "$DASHES"

    _swap_disp=$(pct_of "$M_SWAP")
    [ "$SWAP_DISABLED" -eq 1 ] && _swap_disp="--(未启用)"
    say "" "指标: CPU $(pct_of "$M_CPU")  内存 $(pct_of "$M_MEM")  磁盘 $(pct_of "$M_DISK")  Swap ${_swap_disp}  Load ${M_LOAD_DISP}/${_load_disp}"

    if [ -n "$FX_ACTIVE" ]; then
        say "$MAGENTA" "[特效] $(fx_caption)"
    fi

    if [ "$CPU_BASELINE_HINT" -eq 1 ] && [ "$CPU_HINT_SHOWN" -eq 0 ]; then
        say "$CYAN" "[提示] 首次采样，CPU 基线建立中"
        CPU_HINT_SHOWN=1
    fi

    _dir_txt="right"
    [ "$DIR" -lt 0 ] && _dir_txt="left"

    if [ -n "$RECOVER_LINE" ] && [ "$STATE" = "RECOVERED" ]; then
        say "$GREEN" "$RECOVER_LINE"
    elif [ "$STATE" = "ALERT" ]; then
        say "$RED" "$LINE_ALERT"
        if [ -n "$LINE_CAST" ]; then
            say "$YELLOW" "$LINE_CAST"
        fi
    elif [ "$UNKNOWN_COUNT" -ge 5 ]; then
        say "$YELLOW" "[状态] 采样不可用（全部指标 N/A）"
    elif [ "$UNKNOWN_COUNT" -gt 0 ]; then
        say "$YELLOW" "[状态] 采样不完整（${UNKNOWN_COUNT} 项 N/A）"
    else
        say "$GREEN" "[状态] 一切正常"
    fi

    if [ "$CLEAR_ON" -eq 0 ]; then
        printf '[frame %d] state=%s dir=%s x=%d y=%d pose=%s turn=%d bark=%d\n' \
            "$frame" "$STATE" "$_dir_txt" "$DRAW_X" "$DRAW_Y" "$POSE" "$TURN" "$BARK_NOW"
    else
        # 擦除上一帧更高时残留的底部行，避免整屏清空造成闪烁
        printf '%s' "$ERASE"
    fi
    return 0
}

# -------------------------------------------------------------------- 退出 ---
cleanup() {
    trap - EXIT INT TERM HUP
    if [ -n "$TTS_PID" ]; then
        kill "$TTS_PID" 2>/dev/null
        wait "$TTS_PID" 2>/dev/null
    fi
    printf '%s%s' "$CUR_ON" "$NC"
    if [ "$CLEAR_ON" -eq 1 ]; then
        printf '\n'
    fi
    if [ "$LOG_ON" -eq 1 ]; then
        log_line "EXIT frame=$frame state=$STATE"
    fi
    exit "${1:-0}"
}

# -------------------------------------------------------------------- 主流程 ---
parse_args "$@"
init_terminal
init_thresholds
detect_tts
init_log

# 定时换算：帧间隔为 0 时节流按名义 200ms 计算，避免除零
TICK_MS=$(awk -v v="$FRAME_DELAY" 'BEGIN{ if (v+0 <= 0) v=0.2; printf "%d", v*1000 }')
# 亚毫秒间隔会被整数换算成 0，导致后续除法崩溃；统一提升到 1ms。
if [ "$TICK_MS" -lt 1 ]; then
    TICK_MS=1
    [ "$FRAME_DELAY" != "0" ] && FRAME_DELAY=0.001
fi
BARK_MS=$(awk -v v="$BARK_INTERVAL" 'BEGIN{ printf "%d", v*1000 }')
if [ "$BARK_MS" -le 0 ]; then
    BARK_EVERY=1
else
    BARK_EVERY=$(( (BARK_MS + TICK_MS - 1) / TICK_MS ))
    [ "$BARK_EVERY" -lt 1 ] && BARK_EVERY=1
fi

if [ -n "$SIM_FILE" ] || [ -n "$SIM_SNAPSHOT" ]; then
    SAMPLE_EVERY=1
else
    INTERVAL_MS=$(awk -v v="$INTERVAL" 'BEGIN{ printf "%d", v*1000 }')
    SAMPLE_EVERY=$(( (INTERVAL_MS + TICK_MS - 1) / TICK_MS ))
    [ "$SAMPLE_EVERY" -lt 1 ] && SAMPLE_EVERY=1
fi

printf -v _spaces '%*s' "$FENCE_W" ''
DASHES=${_spaces// /-}
BLANKS="$_spaces"

# 航点按围栏实际边界生成后，把首个目标钳制到范围内
build_waypoints
set_target "${WP[$WP_I]}"

if [ -n "$SIM_FILE" ]; then
    exec 3< "$SIM_FILE" || exit 2
fi

trap 'cleanup 130' INT
trap 'cleanup 143' TERM
trap 'cleanup 129' HUP
trap 'cleanup $?' EXIT

if [ "$CLEAR_ON" -eq 1 ]; then
    printf '\033[2J%s' "$CUR_OFF"
fi

log_line "START interval=$INTERVAL threshold=$THRESHOLD load=$LOAD_THRESHOLD_DISP cores=$CORES tts=${TTS_BIN:-none}"

while :; do
    frame=$(( frame + 1 ))

    # RECOVERED 只停留 1 帧，随后回到 NORMAL
    if [ "$STATE" = "RECOVERED" ] && [ "$RECOVER_FRAME" -lt "$frame" ]; then
        STATE="NORMAL"
        RECOVER_LINE=""
    fi

    if [ "$frame" -eq 1 ] || [ "$SAMPLE_EVERY" -eq 1 ] || [ $(( frame % SAMPLE_EVERY )) -eq 0 ]; then
        sample_metrics
        judge_alerts
        transition_state
    fi

    frame_bark
    update_anim
    set_art "$POSE"
    draw_frame
    advance_pos

    if [ "$STOP_AFTER" -gt 0 ] && [ "$frame" -ge "$STOP_AFTER" ]; then
        cleanup 0
    fi

    if [ "$TICK_MS" -gt 0 ]; then
        sleep "$FRAME_DELAY"
    fi
done
