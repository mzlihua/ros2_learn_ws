#!/usr/bin/env bash
# ================================================================
#  第 17 关 · 探针：换【执行器实现】，量「先上比例」
#
#  用法：  bash probe_executor.sh <轮数> [执行器类型] [容器额外参数...]
#
#     bash probe_executor.sh 10 multi-threaded          # 对照组（第 16 关那份）
#     bash probe_executor.sh 10 events-cbg              # 实验 A ⭐（本机 Jazzy 不支持，见下）
#     bash probe_executor.sh 10 multi-threaded --isolated
#     bash probe_executor.sh 10 single-threaded --isolated
#
#  和第 16 关那份 probe_restart.sh 只差一处：执行器类型从【写死】改成【参数】。
#  量具、判据、抓法一个字都没动 —— 这样两关的读数才可比。
#
#  ⚠️ 2026-11-22 换机适配（原机 Lyrical/x86 → 本机 Jazzy/ARM）：
#     · Jazzy 的容器【没有】 `--executor-type` 参数。写了会被当成普通非 ROS 参数
#       **静默忽略**，容器照旧跑单线程 —— 读数会全错，而且不报错。
#     · Jazzy 用不同二进制来选执行器：
#           single-threaded            → component_container
#           multi-threaded             → component_container_mt
#           single-threaded --isolated → component_container_isolated
#           multi-threaded  --isolated → component_container_isolated + --use_multi_threaded_executor
#     · `events-cbg` 在本机**跑不了**：EventsCBGExecutor 只在 rclcpp 头文件里，
#       Jazzy 的 component_container 没有“选执行器”的入口。要跑得自己写一个容器
#       （挂账，见 SKILL「Jazzy 容器差异」）。本脚本会直接拒绝，不会拿别的执行器冒充。
#
#  ⚠️ 为什么直接跑容器二进制，而不是 ros2 run？
#     `ros2 run` 是个 Python 外壳，`$!` 拿到的是【外壳】的 PID，
#     kill 它杀不到里面的容器 —— 容器会变孤儿（工作区老坑，
#     而且孤儿还会伪造实验数据）。
#
#  ⚠️ 每轮之间都【重开进程】（沿用第 16 关的纪律）：
#     本关不靠它，但同一把尺子要连着用，别中途换规矩。
# ================================================================

set -u

N="${1:-10}"
EXEC="${2:-multi-threaded}"
shift $(( $# < 2 ? $# : 2 ))
RAW_EXTRA=("$@")

# ---- ROS 2 发行版 / 工作区自适应 ----
DISTRO="${ROS_DISTRO:-jazzy}"
ROS_SETUP="/opt/ros/${DISTRO}/setup.bash"
WS_SETUP="${WS_SETUP:-$HOME/ros2_learn_ws/install/setup.bash}"
[ -f "$ROS_SETUP" ] || { echo "!! 找不到 $ROS_SETUP（ROS 装在哪？）" >&2; exit 1; }
[ -f "$WS_SETUP" ] || { echo "!! 找不到 $WS_SETUP（先 colcon build）" >&2; exit 1; }

# ⚠️ 不开 set -u 就 source：setup.bash 里有【未绑定】的变量，
#    在 set -u 之后 source 会当场报 `AMENT_TRACE_SETUP_FILES: 未绑定的变量`。
set +u
# shellcheck disable=SC1090
source "$ROS_SETUP"
source "$WS_SETUP"
set -u

PREFIX="$(ros2 pkg prefix rclcpp_components)"
BIN_ST="$PREFIX/lib/rclcpp_components/component_container"
BIN_MT="$PREFIX/lib/rclcpp_components/component_container_mt"
BIN_ISO="$PREFIX/lib/rclcpp_components/component_container_isolated"

# ---- 把旧的 --executor-type 写法翻译成 Jazzy 的“选二进制” ----
ISOLATED=0
EXTRA=()
for a in "${RAW_EXTRA[@]}"; do
    if [ "$a" = "--isolated" ]; then
        ISOLATED=1
    else
        EXTRA+=("$a")
    fi
done

case "$EXEC" in
    single-threaded)
        if [ "$ISOLATED" -eq 1 ]; then BIN="$BIN_ISO"; else BIN="$BIN_ST"; fi
        ;;
    multi-threaded)
        if [ "$ISOLATED" -eq 1 ]; then
            BIN="$BIN_ISO"
            EXTRA+=(--use_multi_threaded_executor)
        else
            BIN="$BIN_MT"
        fi
        ;;
    events-cbg)
        echo "❌ 本机是 ROS 2 ${DISTRO}：component_container 不支持 --executor-type events-cbg。"
        echo "   EventsCBGExecutor 只在 rclcpp 头文件里，容器没暴露入口；"
        echo "   要跑这一格得自己写容器（见 SKILL「Jazzy 容器差异」）。"
        echo "   本脚本拒绝用别的执行器冒充 —— 那会伪造第 17 关的读数。"
        exit 2
        ;;
    *)
        echo "❌ 未知执行器类型：$EXEC（可用：single-threaded / multi-threaded）" >&2
        exit 2
        ;;
esac

OUTDIR="$(mktemp -d /tmp/lesson17-XXXXXX)"

echo "执行器：$EXEC ${EXTRA[*]:-}   →  $BIN"
echo "日志目录：$OUTDIR"
echo
printf '%-4s  %-6s  %s\n' "轮次" "先上" "第 1 对「读到」（谁在上面就是谁）"
printf '%-4s  %-6s  %s\n' "----" "----" "--------------------------------"

b_count=0
a_count=0
for i in $(seq 1 "$N"); do
    log="$OUTDIR/run_$(printf '%02d' "$i").log"

    "$BIN" ${EXTRA[@]+"${EXTRA[@]}"} >"$log" 2>&1 &
    pid=$!

    sleep 3                                     # 等容器起来
    ros2 component load /ComponentManager hello_ros_cpp Sleeper >/dev/null 2>&1
    sleep 4                                     # 攒几拍（只要第 1 拍，给足余量）

    kill -TERM "$pid" 2>/dev/null               # SIGTERM：脚本里用 SIGINT 容易卡住
    wait "$pid" 2>/dev/null

    pair=$(grep -m1 -A1 '第1拍 读到' "$log" \
           | sed -n 's/.*\[\([AB]\)\] 第1拍 读到.*/\1/p' \
           | paste -sd' ' -)
    first="${pair%% *}"

    case "$first" in
        A) a_count=$((a_count + 1)) ;;
        B) b_count=$((b_count + 1)) ;;
    esac

    printf '%-4s  %-6s  %s\n' "$i" "${first:-?}" "${pair:-（没抓到！去看 $log）}"
done

echo
echo "======== 合计（$N 轮）========"
echo "   B 先上：$b_count"
echo "   A 先上：$a_count"

echo
echo "======== 收工自查（必须是 0）========"
leftovers=$(pgrep -c compo || true)
echo "   残留容器进程：${leftovers:-0}"
echo "   （不是 0 的话：pkill -f /rclcpp_components/component_container）"
echo
echo "日志在：$OUTDIR"
