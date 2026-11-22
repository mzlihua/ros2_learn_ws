#!/usr/bin/env bash
# ================================================================
#  第 22 关 · 跑一轮 Sleeper：起容器 → 装组件 → 跑 N 秒 → SIGTERM 收工 → 读数
#
#  用法：
#      bash probe_run_sleeper.sh <标签> [秒数]
#        例：bash probe_run_sleeper.sh c1        （默认 10 秒）
#
#  它就是第 21 关那份 /tmp/run21.sh，只是搬进仓库（/tmp 会被清掉），
#  并把日志名改成通用的。量具（几个 grep 计数）一个字没动 —— 两关读数才可比。
#
#  ⚠️ 三条老坑，都在脚本里处理了：
#     · 两个终端都要 source（这里替你把两个都 source 了）
#     · 用 stdbuf，不然容器日志被全缓冲吞掉，日志是空的
#     · 收工用 SIGTERM；别用 timeout / `&` 挂 `&&` 链（只杀外壳，容器变孤儿）
#
#  ⚠️ 2026-11-22 换机适配（原机 Lyrical/x86 → 本机 Jazzy/ARM）：
#     · 原机 `ros2 run ... --executor-type multi-threaded` 在本机不成立：
#       Jazzy 的容器没有 `--executor-type`，写了会被静默忽略 → 单线程容器 → 数据全废。
#       本机直接跑 `component_container_mt`（多线程专用的二进制）。
#     · 原脚本用 `ros2 run` 起容器，`$!` 是 Python 外壳的 PID → kill 它杀不到容器。
#       本机直接跑二进制，`$!` 才是容器本体的 PID。
#     · 原脚本写死 `/home/l/...`；本机是 `$HOME`。
# ================================================================

set -u

LABEL="${1:?用法: probe_run_sleeper.sh <标签> [秒数]}"
SECS="${2:-10}"
LOG="/tmp/log_sleeper_${LABEL}.txt"

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

BIN="$(ros2 pkg prefix rclcpp_components)/lib/rclcpp_components/component_container_mt"

# ---- 清场（残留容器会伪造数据）----
# ⚠️ 进程名 comm 只有 15 个字符（"component_conta"），`pkill -x component_container` 匹配不到；
#    所以按【完整命令行里的二进制路径】匹配（-f），一次清掉 ST/MT/isolated 三种。
pkill -TERM -f '/rclcpp_components/component_container' 2>/dev/null
sleep 1

# ---- 起容器（stdbuf：不然日志被全缓冲吞掉）----
stdbuf -oL -eL "$BIN" > "$LOG" 2>&1 &
CPID=$!

# ---- 等 ComponentManager 出现 ----
for _ in $(seq 1 50); do
    ros2 node list 2>/dev/null | grep -q ComponentManager && break
    sleep 0.2
done
sleep 1

# ---- 装组件 ----
if ! ros2 component load /ComponentManager hello_ros_cpp Sleeper >> "$LOG" 2>&1; then
    echo "!! load 失败 —— 看 $LOG 的最后几行"
    kill -TERM "$CPID" 2>/dev/null
    exit 1
fi

# ---- 跑 ----
sleep "$SECS"

# ---- 收工（SIGTERM）----
kill -TERM "$CPID" 2>/dev/null
wait "$CPID" 2>/dev/null

# ---- 读数 ----
echo "=== $LABEL（${SECS}s）==="
echo "容器: $BIN"
echo "日志: $LOG"
printf '读到: %s\n' "$(grep -c '读到' "$LOG" || true)"
printf '写回: %s\n' "$(grep -c '写回' "$LOG" || true)"
printf '重试: %s\n' "$(grep -c '重试' "$LOG" || true)"
echo "最后一条 写回（按时间戳排序，不是行序）:"
grep '写回' "$LOG" | sort | tail -1
echo "收工自查 pgrep -c compo: $(pgrep -c compo || true)"
