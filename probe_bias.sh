#!/usr/bin/env bash
# ================================================================
#  第 19 关 · 探针：量「偏」—— N 轮里 B 占几轮
#
#  用法：  bash probe_bias.sh <轮数> <档>
#
#     bash probe_bias.sh 40 2                 # 40 轮，池子 = 2 只手（本机是 MT + thread_num）
#     bash probe_bias.sh 40 multi-threaded    # 对照组（基类那套）
#     bash probe_bias.sh 20 single-threaded   # 一只手那格（确定，不进曲线）
#
#  和第 17/18 关那份 probe_executor.sh 差【两处】，都是修尺子：
#     ① 判「谁先上」从【行序】换成【时间戳】。
#        ⭐ 第 17 关立的纪律：抢起来之后行序 ≠ 发生顺序（50 轮里 11 轮打架）。
#           本关量的全是「抢」的格子，所以尺子必须先修 —— 免得量具自己把数据搅了。
#     ② ⚠️ 时间戳有 19 位有效数字（1791601775.895694371），比 awk 的 float（约 16 位）
#        还长 —— 当成小数比，两个差 24 纳秒的数会【判成相等】。
#        所以拆成【整秒】+【9 位小数】两段，各自当整数、拼成等长字符串再比。
#     除这两处外，量具、判据、每轮重开进程的纪律一个字没动（两关的读数才可比）。
#
#  ⚠️ 2026-11-22 换机适配（原机 Lyrical/x86 → 本机 Jazzy/ARM）：
#     · 原机的数字档 = `events-cbg + --ros-args -p thread_num:=N`。
#       本机 Jazzy 的容器**没有** `--executor-type`，也没暴露 EventsCBGExecutor；
#       写的 `--executor-type` 会被静默忽略（容器仍跑单线程）—— 会伪造数据。
#     · 本脚本的替代：数字档 = **multi-threaded + thread_num:=N**（同是“池子大小”这个旋钮，
#       但执行器实现不是 EventsCBG）。⚠️ 它**不是**原机那一格，读数不能和原机曲线比。
#       想跑真正的 events-cbg，得自己写容器（挂账，见 SKILL「Jazzy 容器差异」）。
#     · 明确写 `events-cbg` 的，脚本直接拒绝，不拿别的执行器冒充。
#
#  ⚠️ 为什么直接跑容器二进制，而不是 ros2 run？
#     `ros2 run` 是个 Python 外壳，`$!` 拿到的是【外壳】的 PID，
#     kill 它杀不到里面的容器 —— 容器会变孤儿（工作区老坑，
#     而且孤儿还会伪造实验数据）。
#
#  ⚠️ 每轮之间都【重开进程】—— 第 16 关立的纪律。
#     本关它升级成了尺子的【前提】：二项分布要求「每轮独立」。
# ================================================================

set -u

N="${1:-10}"
DANG="${2:-multi-threaded}"

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

if [[ "$DANG" =~ ^[0-9]+$ ]]; then
    EXEC="multi-threaded"
    BIN="$BIN_MT"
    EXTRA=(--ros-args -p "thread_num:=$DANG")
    LABEL="multi-threaded + thread_num:=$DANG（替代档，不是原机的 events-cbg）"
elif [ "$DANG" = "multi-threaded" ]; then
    EXEC="$DANG"
    BIN="$BIN_MT"
    EXTRA=()
    LABEL="$DANG"
elif [ "$DANG" = "single-threaded" ]; then
    EXEC="$DANG"
    BIN="$BIN_ST"
    EXTRA=()
    LABEL="$DANG"
elif [ "$DANG" = "events-cbg" ]; then
    echo "❌ 本机是 ROS 2 ${DISTRO}：component_container 不支持 events-cbg。" >&2
    echo "   EventsCBGExecutor 只在 rclcpp 头文件里，容器没暴露入口；本脚本不拿别的执行器冒充。" >&2
    exit 2
else
    echo "❌ 未知档：$DANG（数字 / single-threaded / multi-threaded）" >&2
    exit 2
fi

OUTDIR="$(mktemp -d /tmp/lesson19-XXXXXX)"

echo "档：$LABEL"
echo "轮数：$N   （每轮重开进程 ⇒ 轮与轮独立，二项分布才套得上）"
echo "日志目录：$OUTDIR"
echo
printf '%-4s  %-6s  %-6s  %s\n' "轮次" "行序" "时间戳" "两行的时间戳差（ns）"
printf '%-4s  %-6s  %-6s  %s\n' "----" "----" "------" "--------------------------"

b_count=0
a_count=0
disagree=0
for i in $(seq 1 "$N"); do
    log="$OUTDIR/run_$(printf '%02d' "$i").log"

    "$BIN" ${EXTRA[@]+"${EXTRA[@]}"} >"$log" 2>&1 &
    pid=$!

    sleep 3                                     # 等容器起来
    ros2 component load /ComponentManager hello_ros_cpp Sleeper >/dev/null 2>&1
    sleep 4                                     # 攒几拍（只要第 1 拍，给足余量）

    kill -TERM "$pid" 2>/dev/null               # SIGTERM：脚本里用 SIGINT 容易卡住
    wait "$pid" 2>/dev/null

    # 第 1 拍那两行：一行 [A]、一行 [B]，各自带时间戳
    # ⚠️ 时间戳拆成【整秒】+【小数】两段，拼成等长的纯数字键（19 位）再比 —— 见文件头 ②
    keyed=$(grep '第1拍 读到' "$log" \
            | sed -n 's/.*\[\([0-9][0-9]*\)\.\([0-9][0-9]*\)\].*\[\([AB]\)\] 第1拍 读到.*/\1 \2 \3/p' \
            | awk '{ printf "%s%s %s %s %s\n", $1, substr($2 "000000000", 1, 9), $3, $1, substr($2 "000000000", 1, 9) }')

    by_line=$(printf '%s\n' "$keyed" | head -1 | awk '{print $2}')   # 行序：第一个印出来的
    by_time=$(printf '%s\n' "$keyed" | LC_ALL=C sort | head -1 | awk '{print $2}')   # 时间戳：键最小

    gap=$(printf '%s\n' "$keyed" | LC_ALL=C sort \
          | awk 'NR==1{s=$3; f=$4} NR==2{printf "%d", ($3-s)*1e9 + ($4-f)}')

    [ -n "$by_line" ] && [ -n "$by_time" ] && [ "$by_line" != "$by_time" ] && disagree=$((disagree + 1))

    case "$by_time" in
        A) a_count=$((a_count + 1)) ;;
        B) b_count=$((b_count + 1)) ;;
    esac

    printf '%-4s  %-6s  %-6s  %s\n' "$i" "${by_line:-?}" "${by_time:-?}" "${gap:-（没抓到！去看 $log）}"
done

total=$((a_count + b_count))
echo
echo "======== 合计（$N 轮，判据 = 时间戳）========"
echo "   B 先上：$b_count"
echo "   A 先上：$a_count"
if [ "$total" -gt 0 ]; then
    printf '   B 的占比：%.1f%%   （五五开 = 50.0%%）\n' "$(awk -v b="$b_count" -v t="$total" 'BEGIN{print 100*b/t}')"
    printf '   没偏时的 2σ：±%.1f 轮（= ±%.1f%%）\n' \
        "$(awk -v t="$total" 'BEGIN{print 2*0.5*sqrt(t)}')" \
        "$(awk -v t="$total" 'BEGIN{print 100*2*0.5*sqrt(t)/t}')"
fi
echo "   ⚠️ 行序和时间戳打架的轮数：$disagree  ← 不为 0 就说明「行序那把尺子」确实不能用了"

echo
echo "======== 收工自查（必须是 0）========"
leftovers=$(pgrep -c compo || true)
echo "   残留容器进程：${leftovers:-0}"
echo "   （不是 0 的话：pkill -f /rclcpp_components/component_container）"
echo
echo "日志在：$OUTDIR"
