// ================================================================
//  第 22 关 · 探针：同一个操作，两种 order —— 机器码长什么样、要花多少钱
//
//  用法：
//      g++ -O2 -std=c++20 -o probe_mo_cost probe_mo_cost.cpp
//      ./probe_mo_cost 10000000          # 第三个可选参数 = 每格跑几次，默认 3
//
//  它只做一件事：把「写 / 读 / 加 / 比较交换」四种操作，各自用
//  relaxed 和 seq_cst 写一遍，量 ns/次，并留出干净的符号名，
//  方便你直接反汇编看那一条指令：
//
//      objdump -d --demangle --no-show-raw-insn probe_mo_cost \
//        | grep -A8 'store_relaxed\|store_seq'      # 以此类推
//
//  ⚠️ 这是【量具】，不是实验对象。本关要量的是"同一句代码的两版 order"，
//     所以八格都必须是【同一段循环】，只差那一个 order 参数。
//     想改任何一格，八格都要跟着改 —— 不然比出来的不是 order 的价钱。
// ================================================================

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>

// 对齐到一条缓存行：避免和别的数据挤在同一行（单线程量它不重要，但别让尺子自己抖）
alignas(64) std::atomic<int> a{0};

// 空循环：用来**校准尺子** —— 循环本身（加一、比较、跳转）也要花时间，
// 后面每格减掉它，剩下的才是"那条原子指令"的价钱。
__attribute__((noinline)) void empty_loop(long n)
{
    long s = 0;
    for (long i = 0; i < n; ++i) s += i;   // 和后面几格一样是"加一 + 比较 + 跳转"
    asm volatile("" : : "r"(s));           // 别让编译器把这个循环整个删掉
}

// ---------- ① 写 ----------
__attribute__((noinline)) void store_relaxed(long n)
{
    for (long i = 0; i < n; ++i) a.store(static_cast<int>(i), std::memory_order_relaxed);
}
__attribute__((noinline)) void store_seq(long n)
{
    for (long i = 0; i < n; ++i) a.store(static_cast<int>(i), std::memory_order_seq_cst);
}

// ---------- ② 读 ----------
__attribute__((noinline)) int load_relaxed(long n)
{
    int s = 0;
    for (long i = 0; i < n; ++i) s += a.load(std::memory_order_relaxed);
    return s;
}
__attribute__((noinline)) int load_seq(long n)
{
    int s = 0;
    for (long i = 0; i < n; ++i) s += a.load(std::memory_order_seq_cst);
    return s;
}

// ---------- ③ 加 ----------
__attribute__((noinline)) void add_relaxed(long n)
{
    for (long i = 0; i < n; ++i) a.fetch_add(1, std::memory_order_relaxed);
}
__attribute__((noinline)) void add_seq(long n)
{
    for (long i = 0; i < n; ++i) a.fetch_add(1, std::memory_order_seq_cst);
}

// ---------- ④ 比较交换 ----------
// 每圈都是"一次 CAS"：第一圈成功（0→1），之后一直失败（现在不是 0 了）。
// 失败和成功走的是**同一条指令**（lock cmpxchg），所以价钱一样 —— 这一点本关要验。
__attribute__((noinline)) int cas_relaxed(long n)
{
    int ok = 0;
    for (long i = 0; i < n; ++i) {
        int expected = 0;
        if (a.compare_exchange_strong(expected, 1,
                                      std::memory_order_relaxed, std::memory_order_relaxed)) {
            ++ok;
        }
    }
    return ok;
}
__attribute__((noinline)) int cas_seq(long n)
{
    int ok = 0;
    for (long i = 0; i < n; ++i) {
        int expected = 0;
        if (a.compare_exchange_strong(expected, 1,
                                      std::memory_order_seq_cst, std::memory_order_seq_cst)) {
            ++ok;
        }
    }
    return ok;
}

// ================================================================
//  量具：跑 reps 次，取【最小值】（最小值最接近"没有干扰时"的价钱；
//  平均值会被变频、别的进程、中断拖高 —— 这是本关的尺子纪律之一）
// ================================================================
template <typename F>
double time_it(F f, long n, int reps)
{
    double best = 1e18;
    for (int r = 0; r < reps; ++r) {
        auto t0 = std::chrono::steady_clock::now();
        f();
        auto t1 = std::chrono::steady_clock::now();
        double ns = std::chrono::duration<double, std::nano>(t1 - t0).count() / n;
        if (ns < best) best = ns;
    }
    return best;
}

int main(int argc, char **argv)
{
    long n = argc > 1 ? std::atol(argv[1]) : 10000000;
    int reps = argc > 2 ? std::atoi(argv[2]) : 3;

    // 校准：空循环的价钱（⭐ 只当【参考线】，不做减法 —— 见下面那行警告）
    double base = time_it([&] { empty_loop(n); }, n, reps);

    struct Row { const char *name; double relax; double seq; };
    Row rows[4];

    double r, s;

    a.store(0, std::memory_order_relaxed);
    r = time_it([&] { store_relaxed(n); }, n, reps);
    s = time_it([&] { store_seq(n); }, n, reps);
    rows[0] = {"① 写 store        ", r, s};

    a.store(0, std::memory_order_relaxed);
    r = time_it([&] { (void)load_relaxed(n); }, n, reps);
    s = time_it([&] { (void)load_seq(n); }, n, reps);
    rows[1] = {"② 读 load         ", r, s};

    a.store(0, std::memory_order_relaxed);
    r = time_it([&] { add_relaxed(n); }, n, reps);
    s = time_it([&] { add_seq(n); }, n, reps);
    rows[2] = {"③ 加 fetch_add    ", r, s};

    a.store(0, std::memory_order_relaxed);
    r = time_it([&] { (void)cas_relaxed(n); }, n, reps);
    s = time_it([&] { (void)cas_seq(n); }, n, reps);
    rows[3] = {"④ 比较交换 CAS    ", r, s};

    std::printf("\n每格 = %ld 次循环，取 %d 次里的最小值\n", n, reps);
    std::printf("参考线：空循环 %.3f ns/次（⚠️ 不减掉它 —— 它自己也带依赖，减了会出负数）\n", base);
    std::printf("%s  %12s  %12s  %8s\n", "操作", "relaxed", "seq_cst", "seq/relax");
    std::printf("--------------------------------------------------------------\n");
    for (const auto &row : rows) {
        std::printf("%s  %9.3f ns  %9.3f ns  %7.1fx\n", row.name, row.relax, row.seq,
                    row.seq / row.relax);
    }
    std::printf("\n");
    std::printf("⚠️ 读数之前先问两句：\n");
    std::printf("   1) 反汇编里，那一条指令还在吗？（别把'被优化没了'读成'不要钱'）\n");
    std::printf("   2) 八格里哪几格的 relaxed / seq_cst 是【同一条指令】？\n");
    return 0;
}
