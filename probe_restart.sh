#!/usr/bin/env bash
# ================================================================
#  第 16 关 · 实验 B 探针
#
#  作用：把容器【重启】 N 次，每次只报一件事 —— 第 1 拍谁先上。
#
#  用法：  bash probe_restart.sh          # 默认 10 轮
#          bash probe_restart.sh 1        # 先跑 1 轮，验尺子
#
#  ⚠️ 为什么直接跑 component_container 的二进制，而不是 ros2 run？
#     `ros2 run` 是个 Python 外壳，`$!` 拿到的是【外壳】的 PID，
#     kill 它杀不到里面的容器 —— 容器会变孤儿（工作区老坑，
#     而且孤儿还会伪造实验数据）。
#
#  ⚠️ 2026-11-22 换机适配（原机 Lyrical/x86 → 本机 Jazzy/ARM）：
#     本关要的是【多线程】容器。原机用 `component_container --executor-type multi-threaded`；
#     Jazzy 的 `component_container` **不认识** `--executor-type`（会静默忽略 →
#     容器变成单线程 → 数据全废）。Jazzy 用单独的二进制 `component_container_mt`。
#
#  ⚠️ 每轮之间必须【重启进程】—— 这是本实验的全部意义。
#     如果只是 load 一个新组件，地址是同一个进程里的，不算数。
# ================================================================

set -u

N="${1:-10}"
OUTDIR="$(mktemp -d /tmp/lesson16-XXXXXX)"

# ---- ROS 2 发行版 / 工作区自适应：不再写死 lyrical 和 /home/xxx ----
DISTRO="${ROS_DISTRO:-jazzy}"
ROS_SETUP="/opt/ros/${DISTRO}/setup.bash"
WS_SETUP="${WS_SETUP:-$HOME/ros2_learn_ws/install/setup.bash}"
[ -f "$ROS_SETUP" ] || { echo "!! 找不到 $ROS_SETUP（ROS 装在哪？）" >&2; exit 1; }
[ -f "$WS_SETUP" ] || { echo "!! 找不到 $WS_SETUP（先 colcon build）" >&2; exit 1; }

# shellcheck disable=SC1090
set +u
source "$ROS_SETUP"
source "$WS_SETUP"
set -u

BIN="$(ros2 pkg prefix rclcpp_components)/lib/rclcpp_components/component_container_mt"

echo "容器：$BIN"
echo "日志目录：$OUTDIR"
echo
printf '%-4s  %-6s  %s\n' "轮次" "先上" "第 1 对「读到」（谁在上面就是谁）"
printf '%-4s  %-6s  %s\n' "----" "----" "--------------------------------"

b_count=0
a_count=0
for i in $(seq 1 "$N"); do
    log="$OUTDIR/run_$(printf '%02d' "$i").log"

    "$BIN" >"$log" 2>&1 &
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
