#!/usr/bin/env bash
# ================================================================
#  第 17 关 · 探针：数手（第 12 关那把尺子）—— 2×2 四格
#
#  用法：  bash probe_threads.sh <执行器类型> [容器额外参数...]
#     bash probe_threads.sh single-threaded
#     bash probe_threads.sh multi-threaded
#     bash probe_threads.sh single-threaded --isolated
#     bash probe_threads.sh multi-threaded --isolated
#     bash probe_threads.sh events-cbg            # 本机 Jazzy 不支持（会明确拒绝）
#
#  每一格数【三次】线程数：
#     起容器后（组件还没装）→ 装 1 个 Sleeper → 装 2 个
#
#  ⭐ 只有第三个数看得出「每个组件到底有没有【自己】的执行器」：
#     --isolated = 每个组件配一个自己的执行器 ⇒ 第二个组件应该带【一整套】新手来。
#
#  尺子：ls /proc/<PID>/task | wc -l   （第 12 关原话）
#
#  ⚠️ 2026-11-22 换机适配（原机 Lyrical/x86 → 本机 Jazzy/ARM）：
#     · Jazzy 的容器没有 `--executor-type`；执行器改由【二进制】选：
#           single-threaded → component_container
#           multi-threaded  → component_container_mt
#           --isolated      → component_container_isolated
#                              （multi-threaded 时再加 --use_multi_threaded_executor）
#       `events-cbg` 在本机跑不了（容器没暴露入口），脚本直接拒绝。
#     · ⭐ 尺子要修：本机的 DDS（Fast DDS）一开容器就带十几个线程。
#       绝对线程数里混着 DDS 的 noise，不能直接当「执行器的手数」。
#       所以下面同时报【空容器绝对值】和【装组件后相对空容器的增量 Δ】。
#       看“执行器多了几只手”要看 Δ，不是绝对值。
# ================================================================

set -u

EXEC="${1:-multi-threaded}"
shift $(( $# < 1 ? $# : 1 ))
RAW_EXTRA=("$@")

# ---- ROS 2 发行版 / 工作区自适应 ----
DISTRO="${ROS_DISTRO:-jazzy}"
ROS_SETUP="/opt/ros/${DISTRO}/setup.bash"
WS_SETUP="${WS_SETUP:-$HOME/ros2_learn_ws/install/setup.bash}"
[ -f "$ROS_SETUP" ] || { echo "!! 找不到 $ROS_SETUP（ROS 装在哪？）" >&2; exit 1; }
[ -f "$WS_SETUP" ] || { echo "!! 找不到 $WS_SETUP（先 colcon build）" >&2; exit 1; }

set +u
# shellcheck disable=SC1090
source "$ROS_SETUP"
source "$WS_SETUP"
set -u

PREFIX="$(ros2 pkg prefix rclcpp_components)"
BIN_ST="$PREFIX/lib/rclcpp_components/component_container"
BIN_MT="$PREFIX/lib/rclcpp_components/component_container_mt"
BIN_ISO="$PREFIX/lib/rclcpp_components/component_container_isolated"

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
        echo "❌ 本机是 ROS 2 ${DISTRO}：component_container 不支持 --executor-type events-cbg。" >&2
        echo "   EventsCBGExecutor 只在 rclcpp 头文件里，容器没暴露入口；本脚本不拿别的执行器冒充。" >&2
        exit 2
        ;;
    *)
        echo "❌ 未知执行器类型：$EXEC（可用：single-threaded / multi-threaded）" >&2
        exit 2
        ;;
esac

OUTDIR="$(mktemp -d /tmp/lesson17t-XXXXXX)"

count_threads() { ls /proc/"$1"/task 2>/dev/null | wc -l; }

echo "执行器：$EXEC ${EXTRA[*]:-}   →  $BIN"
"$BIN" ${EXTRA[@]+"${EXTRA[@]}"} >"$OUTDIR/container.log" 2>&1 &
pid=$!
sleep 3

t0=$(count_threads "$pid")
ros2 component load /ComponentManager hello_ros_cpp Sleeper >/dev/null 2>&1
sleep 2
t1=$(count_threads "$pid")
ros2 component load /ComponentManager hello_ros_cpp Sleeper >/dev/null 2>&1
sleep 2
t2=$(count_threads "$pid")

kill -TERM "$pid" 2>/dev/null
wait "$pid" 2>/dev/null

printf '%-34s  空容器 %-4s  装1个 %-4s  装2个 %-4s\n' \
  "$EXEC ${EXTRA[*]:-}" "$t0" "$t1" "$t2"
printf '%-34s  %-18s  Δ1=%-4s  Δ2=%-4s\n' \
  "（相对空容器的增量）" "" "$((t1 - t0))" "$((t2 - t0))"
echo "   ⚠️ 绝对值里有 DDS 自带线程；看执行器的手数请用 Δ。"
echo "   （日志：$OUTDIR/container.log）"
echo "   残留容器进程：$(pgrep -c compo || true)   ← 必须是 0"
