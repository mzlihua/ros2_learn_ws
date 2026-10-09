#!/usr/bin/env bash
# ================================================================
#  第 17 关 · 探针：换【执行器实现】，量「先上比例」
#
#  用法：  bash probe_executor.sh <轮数> [执行器类型] [容器额外参数...]
#
#     bash probe_executor.sh 10 multi-threaded          # 对照组（第 16 关那份）
#     bash probe_executor.sh 10 events-cbg              # 实验 A ⭐
#     bash probe_executor.sh 10 events-cbg --isolated   # 实验 B
#     bash probe_executor.sh 10 multi-threaded --isolated
#
#  和第 16 关那份 probe_restart.sh 只差一处：执行器类型从【写死】改成【参数】。
#  量具、判据、抓法一个字都没动 —— 这样两关的读数才可比。
#
#  ⚠️ 为什么直接跑 /opt/ros/.../component_container，而不是 ros2 run？
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
EXTRA=("$@")

BIN=/opt/ros/lyrical/lib/rclcpp_components/component_container
OUTDIR="$(mktemp -d /tmp/lesson17-XXXXXX)"

# ⚠️ 不开 set -u 就 source：/opt/ros/lyrical/setup.bash 里有【未绑定】的变量，
#    在 set -u 之后 source 会当场报 `AMENT_TRACE_SETUP_FILES: 未绑定的变量`。
set +u
# shellcheck disable=SC1091
source /opt/ros/lyrical/setup.bash
# shellcheck disable=SC1091
source "$HOME/ros2_learn_ws/install/setup.bash"
set -u

echo "执行器：--executor-type $EXEC ${EXTRA[*]:-}"
echo "日志目录：$OUTDIR"
echo
printf '%-4s  %-6s  %s\n' "轮次" "先上" "第 1 对「读到」（谁在上面就是谁）"
printf '%-4s  %-6s  %s\n' "----" "----" "--------------------------------"

b_count=0
a_count=0
for i in $(seq 1 "$N"); do
    log="$OUTDIR/run_$(printf '%02d' "$i").log"

    "$BIN" --executor-type "$EXEC" ${EXTRA[@]+"${EXTRA[@]}"} >"$log" 2>&1 &
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
echo "   （不是 0 的话：pkill -x component_container）"
echo
echo "日志在：$OUTDIR"
