#!/usr/bin/env bash
# ================================================================
#  第 22 关 · 探针跑一轮：编 → 量价钱 → 把八格的机器码打出来
#
#  用法：
#      bash probe_mo_cost.sh              # 默认 1000 万次，取 3 次最小值
#      bash probe_mo_cost.sh 20000000 5   # 2000 万次，取 5 次最小值
#
#  它做三件事，按顺序：
#      ① 编（-O2，和平时一样）
#      ② 跑价钱表（probe_mo_cost 自己打印）
#      ③ ⭐ 把八格的【热循环那几条指令】打印出来 —— 本关的尺子之一
#
#  ⚠️ 第 ③ 步是本关最容易看花眼的地方：
#     objdump 打出来的行号是**可执行文件里的地址**，不是源码行号。
#     每个 `<函数名(long)>:` 下面十行，就是那一格的循环体。
# ================================================================

set -u

N="${1:-10000000}"
REPS="${2:-3}"
BIN=/tmp/probe_mo_cost
SRC="$(dirname "$0")/probe_mo_cost.cpp"

echo "=== ① 编 ==="
g++ -O2 -std=c++20 -o "$BIN" "$SRC" || exit 1

echo
echo "=== ② 价钱（每格 $N 次，取 $REPS 次最小值）==="
"$BIN" "$N" "$REPS"

echo
echo "=== ③ 八格的机器码（每个函数头下面就是那一格的循环体）==="
objdump -d --demangle --no-show-raw-insn "$BIN" \
    | sed -n '/<store_relaxed(long)>:/,$p' \
    | grep -E '^[0-9a-f]+ <(store|load|add|cas)_(relaxed|seq)\(long\)>:|# 4080 <a>'

echo
echo "⚠️ 读数之前先问自己："
echo "   1) 八格里，哪几格 relaxed 和 seq_cst 是【同一条指令】？"
echo "   2) 找 '\$lock' 之外，别忘了【xchg 带内存操作数时默认就是加锁的】——"
echo "      汇编里不写 lock 三个字，所以数 'lock' 会把它漏掉。"
