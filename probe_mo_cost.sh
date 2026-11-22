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
#  ⚠️ 2026-11-22 换机适配（原机 x86-64 → 本机 ARMv8 / Cortex-A76）：
#     x86 那套 `lock` / `xchg` / `cmpxchg` 的读法在本机全部作废。ARM 上要看的是：
#         relaxed 写 / 读        →  str / ldr
#         seq_cst 写 / 读        →  stlr / ldar      （l = release, a = acquire）
#         relaxed 加 / CAS       →  ldadd / cas       （LSE 指令）
#         seq_cst 加 / CAS       →  ldaddal / casal   （al = acquire+release）
#     全屏障在 ARM 上是 `dmb ish`，不是 `lock` 前缀。
#
#     ⭐ 还有一层本机特有：GCC 默认用【outline atomics】。
#        读/写是内联的；但 `fetch_add` / CAS 在调用点只看到一条
#        `bl __aarch64_ldadd4_relax` / `bl __aarch64_cas4_acq_rel` ——
#        真正的那条原子指令在 libgcc 的 helper 里，而且 helper 还会按
#        CPU 能力（HWCAP）**运行时二选一**：LSE 指令 or LL/SC 循环。
#        所以本脚本第 ③ 段分三块：
#          (A) 默认编译的调用点
#          (B) helper 里的两条路（LSE / LL-SC）
#          (C) 加 `-march=armv8.2-a+lse -mno-outline-atomics` 重编一份，
#              直接看内联的 ldadd / ldaddal / cas / casal
#
#  ⚠️ 第 ③ 步是本关最容易看花眼的地方：
#     objdump 打出来的行号是**可执行文件里的地址**，不是源码行号。
# ================================================================

set -u

N="${1:-10000000}"
REPS="${2:-3}"
SRC="$(dirname "$0")/probe_mo_cost.cpp"
BIN=/tmp/probe_mo_cost
BIN_LSE=/tmp/probe_mo_cost_lse
ARCH="$(uname -m)"

echo "=== ① 编（默认：GCC outline atomics）==="
g++ -O2 -std=c++20 -o "$BIN" "$SRC" || exit 1

echo
echo "=== ② 价钱（每格 $N 次，取 $REPS 次最小值）==="
"$BIN" "$N" "$REPS"

echo
echo "=== ③ 八格的机器码 ==="

# 只留“会碰内存/原子”的行；去掉函数序言里对栈的存取（[sp] / [x29]）
# ⚠️ 匹配必须锚在【助记符】那一列：`b.le 1188 <cas_relaxed+0x68>` 的
#    跳转目标里也有 "cas"，只按行 grep 会把普通跳转也算进来。
hot_lines() {
    local bin="$1" fn="$2"
    objdump -d --demangle --no-show-raw-insn "$bin" \
        | sed -n "/<$fn(long)>:/,/^\$/p" \
        | grep -E '^[[:space:]]+[0-9a-f]+:[[:space:]]+(stlr|str|ldar|ldr|ldaddal|ldadd|casal|cas|dmb|ldxr|stxr|ldaxr|stlxr|bl)([[:space:]]|$)' \
        | grep -Ev '\[sp|\[x29' || true
}

helper_lines() {
    local bin="$1" h="$2"
    objdump -d --demangle --no-show-raw-insn "$bin" \
        | sed -n "/<$h>:/,/^\$/p" \
        | grep -E '^[[:space:]]+[0-9a-f]+:[[:space:]]+(ldaddal|ldadd|casal|cas|ldxr|stxr|ldaxr|stlxr|dmb|cbz|cbnz|ret)([[:space:]]|$)' \
        || true
}

if [ "$ARCH" = "aarch64" ]; then
    echo
    echo "--- (A) 默认编译：八个函数的调用点 ---"
    echo "    （RMW 那四格看到的是 bl → helper；不是没有指令，是藏在 helper 里）"
    for fn in store_relaxed store_seq load_relaxed load_seq \
              add_relaxed add_seq cas_relaxed cas_seq; do
        echo
        echo "  <$fn>"
        hot_lines "$BIN" "$fn" | sed 's/^/    /'
    done

    echo
    echo "--- (B) libgcc helper 里的两条路（LSE / LL·SC，运行时按 HWCAP 二选一）---"
    echo "    本机 /proc/cpuinfo 有 atomics 标志吗：$(grep -o 'atomics' /proc/cpuinfo | head -1 || echo '没有')"
    for h in __aarch64_ldadd4_relax __aarch64_ldadd4_acq_rel \
             __aarch64_cas4_relax __aarch64_cas4_acq_rel; do
        echo
        echo "  <$h>"
        helper_lines "$BIN" "$h" | sed 's/^/    /'
    done

    echo
    echo "--- (C) 内联版：-march=armv8.2-a+lse -mno-outline-atomics ---"
    if g++ -O2 -std=c++20 -march=armv8.2-a+lse -mno-outline-atomics -o "$BIN_LSE" "$SRC" 2>/dev/null; then
        for fn in store_relaxed store_seq load_relaxed load_seq \
                  add_relaxed add_seq cas_relaxed cas_seq; do
            echo
            echo "  <$fn>"
            hot_lines "$BIN_LSE" "$fn" | sed 's/^/    /'
        done
    else
        echo "  （这个 g++ 不支持 -march=armv8.2-a+lse；看 (A)/(B) 也一样能答题）"
    fi
else
    echo
    echo "⚠️ 本机不是 aarch64（uname -m = $ARCH），上面的 ARM 读法不适用。"
    echo "   这台机器上请用你的 ISA 对应的原子指令读法重新校准。"
    echo
    echo "--- 默认编译：八个函数的调用点 ---"
    for fn in store_relaxed store_seq load_relaxed load_seq \
              add_relaxed add_seq cas_relaxed cas_seq; do
        echo
        echo "  <$fn>"
        hot_lines "$BIN" "$fn" | sed 's/^/    /'
    done
fi

echo
echo "⚠️ 读数之前先问自己："
echo "   1) 八格里，哪几格 relaxed 和 seq_cst 是【同一条指令】？"
echo "   2) 本机默认编译下，RMW 的差别在【调用点】还是在【helper 里面】？"
echo "      —— 只在调用点看，会不会把'调了另一个 helper'误读成'指令没变'？"
echo "   3) 读/写那四格是内联的；它们的变化（str/ldr ↔ stlr/ldar）说明什么？"
