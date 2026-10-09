#!/usr/bin/env bash
# ================================================================
#  第 17 关 · 探针：数手（第 12 关那把尺子）—— 2×2 四格
#
#  用法：  bash probe_threads.sh <执行器类型> [容器额外参数...]
#     bash probe_threads.sh multi-threaded
#     bash probe_threads.sh multi-threaded --isolated
#     bash probe_threads.sh events-cbg
#     bash probe_threads.sh events-cbg --isolated
#
#  每一格数【三次】线程数：
#     起容器后（组件还没装）→ 装 1 个 Sleeper → 装 2 个
#
#  ⭐ 只有第三个数看得出「每个组件到底有没有【自己】的执行器」：
#     --isolated = 每个组件配一个自己的执行器 ⇒ 第二个组件应该带【一整套】新手来。
#
#  尺子：ls /proc/<PID>/task | wc -l   （第 12 关原话）
# ================================================================

set -u

EXEC="${1:-multi-threaded}"
shift $(( $# < 1 ? $# : 1 ))
EXTRA=("$@")

BIN=/opt/ros/lyrical/lib/rclcpp_components/component_container
OUTDIR="$(mktemp -d /tmp/lesson17t-XXXXXX)"

set +u
# shellcheck disable=SC1091
source /opt/ros/lyrical/setup.bash
# shellcheck disable=SC1091
source "$HOME/ros2_learn_ws/install/setup.bash"
set -u

count_threads() { ls /proc/"$1"/task 2>/dev/null | wc -l; }

echo "执行器：--executor-type $EXEC ${EXTRA[*]:-}"
"$BIN" --executor-type "$EXEC" ${EXTRA[@]+"${EXTRA[@]}"} >"$OUTDIR/container.log" 2>&1 &
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

printf '%-28s  空容器 %-4s  装1个 %-4s  装2个 %-4s\n' \
  "--executor-type $EXEC ${EXTRA[*]:-}" "$t0" "$t1" "$t2"
echo "   （日志：$OUTDIR/container.log）"
echo "   残留容器进程：$(pgrep -c compo || true)   ← 必须是 0"
