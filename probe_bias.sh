#!/usr/bin/env bash
# ================================================================
#  第 19 关 · 探针：量「偏」—— N 轮里 B 占几轮
#
#  用法：  bash probe_bias.sh <轮数> <档>
#
#     bash probe_bias.sh 40 2                 # 40 轮，池子 = 2 只手（events-cbg）
#     bash probe_bias.sh 40 16                # 40 轮，池子 = 16 只手
#     bash probe_bias.sh 40 multi-threaded    # 对照组（基类那套）
#     bash probe_bias.sh 20 single-threaded   # 一只手那格（确定，不进曲线）
#
#  `<档>` 是一个数字 → events-cbg + --ros-args -p thread_num:=<数字>
#  `<档>` 是一个词   → 原样当执行器类型（single-threaded / multi-threaded / events-cbg）
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
#  ⚠️ 为什么直接跑 /opt/ros/.../component_container，而不是 ros2 run？
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

if [[ "$DANG" =~ ^[0-9]+$ ]]; then
    EXEC="events-cbg"
    EXTRA=(--ros-args -p "thread_num:=$DANG")
    LABEL="events-cbg + thread_num:=$DANG"
else
    EXEC="$DANG"
    EXTRA=()
    LABEL="$DANG"
fi

BIN=/opt/ros/lyrical/lib/rclcpp_components/component_container
OUTDIR="$(mktemp -d /tmp/lesson19-XXXXXX)"

# ⚠️ 不开 set -u 就 source：/opt/ros/lyrical/setup.bash 里有【未绑定】的变量，
#    在 set -u 之后 source 会当场报 `AMENT_TRACE_SETUP_FILES: 未绑定的变量`。
set +u
# shellcheck disable=SC1091
source /opt/ros/lyrical/setup.bash
# shellcheck disable=SC1091
source "$HOME/ros2_learn_ws/install/setup.bash"
set -u

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

    "$BIN" --executor-type "$EXEC" ${EXTRA[@]+"${EXTRA[@]}"} >"$log" 2>&1 &
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
echo "   （不是 0 的话：pkill -x component_container）"
echo
echo "日志在：$OUTDIR"
