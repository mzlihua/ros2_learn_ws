---
name: ros2-learn-ws
description: ROS 2 学习工作区（22 关出题式课程）的换机恢复、继续上课、实验与排障。本机为树莓派 5 / ARMv8 / Ubuntu 24.04 / ROS 2 Jazzy：重建环境、colcon 构建、组件/执行器/原子实验、跑探针脚本、提交推送时使用。
---

# ROS 2 学习工作区

> 这是 **教学** 工作区：Claude 出题、用户做题，**不替用户写代码**。
> 主线 22 关（ROS 2 核心基础）+ C++ 支线 2 篇；每关 `docs/lesson-XX-*.md`，封板后提交推送。
> 完整教学记录见 Claude 记忆；本文件只放「换机 / 接着上手」必需的东西。
>
> 🔁 **2026-11-22 换机**：本机 = **树莓派 5（ARMv8 / Jazzy）**；
> 原机 = **x86-64 / Lyrical**。第 1–21 关的实测数据是原机的**历史记录**，
> 依赖机器的读数（线程数、偏向、ns）**不能跨机照搬**。

## 本机环境（2026-11-22 起）

| 项 | 值 |
|---|---|
| 硬件 | Raspberry Pi 5 Model B Rev 1.0，8 GB，**Cortex-A76 ×4（aarch64）** |
| 系统 | Ubuntu 24.04.5 LTS（noble） |
| ROS 2 | **Jazzy**，装在 `/opt/ros/jazzy`（约 200 个包；`~/.bashrc` 已 source） |
| Python | **3.12.3**（rclpy 在 `/opt/ros/jazzy/lib/python3.12/site-packages`） |
| C++ | **g++ 13.3.0**（C++20 可用；`build-essential`） |
| CMake | 3.28.3 |
| RMW | Fast DDS（`rmw_fastrtps_cpp`），`RMW_IMPLEMENTATION` 未设 |
| 工作区 | `/home/li/ros2_learn_ws` |
| git 代理 | `~/.gitconfig` 里 `http(s).proxy = http://192.168.137.1:7897`（远程代理机，不是本机端口） |

**原机对照（只用于理解历史记录，不要拿它当“本机”）**：Ubuntu 26.04 / ROS 2 Lyrical /
Python 3.14.4 / g++ 15.2 / x86-64 12 代 i5 16 线程。

## 代码在哪

| 位置 | 内容 |
|---|---|
| GitHub `mzlihua/ros2_learn_ws`（`main`） | 唯一持久副本；**换机后 clone 它** |
| `~/ros2_learn_ws` | 工作区根目录 |
| `src/` | 3 个包（见下表） |
| `docs/` | 22 关笔记 + 2 篇专项 + 2 篇 C++ 支线 |
| `probe_*.sh` / `probe_mo_cost.cpp` | 各关实验探针，**在仓库根目录**，随 git 走 |
| `build/ install/ log/ .vscode/` | 本地产物，已被 git 忽略，**不随仓库走** |

**⚠️ 换机必丢的两样（不在 git 里，需手动重建）：**
1. `.vscode/settings.json` —— 刻意关闭 12 项自动补全（练手写）。丢了不影响功能，只是补全回来了；要恢复按 README「工作约定」重建。
2. `install/` —— 新机器要重新 `colcon build`。

## 换机恢复

```bash
# 1) 装 ROS 2 Jazzy（本机在 /opt/ros/jazzy；Ubuntu 24.04 按官方 Jazzy 安装说明）
#    本机环境：Ubuntu 24.04 / Python 3.12.3 / g++ 13.3 (C++20) / CMake 3.28.3 / colcon

# 2) 补本机包 —— 缺了 build 不一定红，但运行/探针会挂
sudo apt update
sudo apt install -y build-essential ros-jazzy-example-interfaces

# 2b) 只有回炉第 11 关（官方组件当“陪练”）才需要这三个
sudo apt install -y ros-jazzy-composition ros-jazzy-demo-nodes-cpp ros-jazzy-demo-nodes-py

# 3) clone（GitHub 代理见下）
git clone https://github.com/mzlihua/ros2_learn_ws.git ~/ros2_learn_ws
cd ~/ros2_learn_ws

# 4) 构建（先接口包，其余一起）
source /opt/ros/jazzy/setup.bash
colcon build --symlink-install
source install/setup.bash

# 5) 冒烟
ros2 pkg list | grep hello_          # 期望看到 hello_ros / hello_ros_cpp / hello_ros_interfaces
ros2 run hello_ros talker            # 另开终端 ros2 topic echo /chatter
```

**每个新终端都要 source 两条**（缺第二条会报 `Package 'hello_ros' not found`）：

```bash
source /opt/ros/jazzy/setup.bash
source ~/ros2_learn_ws/install/setup.bash
```

- `hello_ros` 的 `example_interfaces` **运行时**才用：缺包时 build 绿灯，跑 `add_/fib_` 才 `import` 失败。
- 探针脚本已经自适应：优先用 `$ROS_DISTRO`，没设就默认 `jazzy`；工作区用 `$HOME`，不再写死 `/home/l`。

## 三个包

| 包 | 类型 | 内容 |
|---|---|---|
| `hello_ros` | `ament_python` | 主线 Python 节点：talker/listener、add_/fib_、param_、qos_、status_、group_demo、launch/ |
| `hello_ros_cpp` | `ament_cmake` | C++ 节点 + 3 个组件：talker_component、sleeper_component（第 21/22 关）、listener、status_listener |
| `hello_ros_interfaces` | `ament_cmake` | 自定义 `.msg` / `.srv`；**`hello_ros` 依赖它** |

- `src/` 里还有 `build/ install/ log/` 三个带 `COLCON_IGNORE` 的残留目录（早期误构建），无害，别当成包。
- `hello_ros_interfaces` 没 build 就编 `hello_ros`，build 会绿灯但运行 `import` 失败。

## 当前进度

| 范围 | 状态 |
|---|---|
| 主线 1–21 关 | ✅ 封板并已推送（**数据来自原机 x86/Lyrical**） |
| 第 22 关「顺序（`memory_order` 省的是「钱」还是「保证」？）」 | ⏳ **§0 预习已按本机 ARMv8 重写**（2026-11-22）；正课未开；§7/§8/§9 待填 |
| C++ 支线 01/02 | ✅ 完成（原机实测；本机代码可编译） |
| 专项 skill-01（看日志）/ 02（怎么推测） | ✅ 完成 |

下一关候选见 `docs/lesson-22-memory-order.md` §10.4（ABA / `compare_exchange_weak` / 3 条不明的手 / 死结 / ARM litmus）。
**用户说「第 N 关」就直接接着开；不要主动催硬件项目。**

## 继续上课：教学铁律（22 关蒸馏）

1. **出题式**：Claude 出题，用户答题并自己敲代码；Claude 只给前提、模板、结构分解，**不给答案**。
2. **只收前提，不收答案**：每格先让用户写出「用的是哪几条前提」。只收答案 = 训练猜。
3. **【查】≠【推】**：类型名 / API 名 / 头文件签名是【查】的 —— 让他去查，并**连「怎么查」一起给**；不是考记忆。推理格才是【推】的。
4. **每格先分清**：这一格是查还是推？答案在代码里还是在推理里？
5. **判据会失效**：每关的「尺子」量着量着就可能失效（已 7 次）。**先修尺子，再量东西**；报数必须带标签（不能只给裸数字）。
6. **量纲要对**：数「访问 / 拍子 / 轮数」，不要数「代码行」。
7. **换一个旋钮 = 只动它管的那一格**；改完先 `grep -n` 抓一眼，确认真的改了。
8. **他会拿「上一版前提」答「这一版题」**：听到「还是…」「他就是…」先停，问「这一版里那样东西还在吗」，让他重画「墙在哪、空地在哪」。
9. **别给长命令行**；要让他查，就连命令一起给。
10. **他读不懂英语**：英文注释、头文件、报错原文由 Claude 翻译，别让他「自己去读」。
11. **断更后先量温度**：把最近几关各一句话列表 → 他标 ✅/⚠️/❌ → 只回炉 ⚠️/❌ 那关；复课卷 = 该关 §9，复课不上新关。
12. **预习节先落 §0 再开课**：五块 —— 问题 / 理论背景（厚表格，答题时边答边翻）/ 旋钮+API 形状 / 连哪几关 / 实验预告；**只放前提，结果一个字不写**（判据：「换个旋钮它还成立吗？」成立=理论，只对格成立=结果）。
13. **量具是我写的、判断归他**：教学记录里分开写。

## 关卡文档约定

`docs/lesson-XX-<slug>.md` 固定结构：

```
§0 预习（问题 / 理论背景 / 旋钮+API 形状 / 连哪几关 / 实验预告）
§1 本关目标   §2 核心概念   §3 完整代码   §4 命令速查   §5 工具速查
§6 构建与运行   §7 实测现象与结论 ⭐   §8 踩坑   §9 自测题
§10 附：本关挂的账 / 加练 / 教学记录 / 下一关候选
```

封板后：更新 `README.md` 课程进度表 + 目录树 → `git add` → commit 信息用 `第N关: 标题（题眼）` → push。

## 探针与实验速查

| 脚本 | 关卡 | 用途 | 本机注意 |
|---|---|---|---|
| `probe_restart.sh` | 16 | 把容器重启 N 遍，看每次第 1 拍谁先上 | 用 `component_container_mt` |
| `probe_executor.sh` | 17 | 换执行器，量「先上比例」 | Jazzy **没有** `--executor-type`；脚本按二进制映射。`events-cbg` 直接拒绝 |
| `probe_threads.sh` | 17 | 量手数（`ls /proc/<PID>/task \| wc -l`） | 本机基线含 DDS 线程；看 **Δ**，别只看绝对值 |
| `probe_bias.sh` | 19 | 量偏向（时间戳尺子） | 数字档 = MT + `thread_num:=N`（**不是**原机 events-cbg） |
| `probe_mo_cost.sh` / `.cpp` | 22 | 八格 `memory_order` 的机器码 + 价钱 | ARM 三段：调用点 / libgcc helper / `-mno-outline-atomics` 内联 |
| `probe_run_sleeper.sh` | 22 | 起容器→装 Sleeper→跑 N 秒→SIGTERM→读数 | 直接跑 MT 二进制；`$HOME` 自适应 |

常用手法：

```bash
# 起容器（Jazzy：执行器由【二进制】选，不是 --executor-type）
P="$(ros2 pkg prefix rclcpp_components)/lib/rclcpp_components"
"$P/component_container"        # 单线程
"$P/component_container_mt"     # 多线程（第 16/17/18/19/21/22 关的舞台）
"$P/component_container_isolated"                     # 隔离（单线程）
"$P/component_container_isolated" --use_multi_threaded_executor   # 隔离 + 多线程
ros2 component load /ComponentManager hello_ros_cpp Sleeper
# 数手
ls /proc/<容器PID>/task | wc -l        # ⚠️ 基线含 DDS 线程；看 Δ
```

### ⚠️ Jazzy 容器差异（原机 Lyrical 的写法在这里会**静默**测错）

| 想干的 | 原机（Lyrical） | 本机（Jazzy） |
|---|---|---|
| 多线程容器 | `component_container --executor-type multi-threaded` | **`component_container_mt`** |
| 单线程容器 | `component_container` | `component_container` |
| 隔离容器 | `--isolated` | `component_container_isolated`（多线程加 `--use_multi_threaded_executor`） |
| 换执行器实现 | `--executor-type events-cbg` | ❌ **没有入口**；写 `--executor-type` 会被当成非 ROS 参数**静默忽略**（容器照旧单线程） |
| 池子大小 | `events-cbg + -p thread_num:=N` | MT 容器支持 `--ros-args -p thread_num:=N`（执行器是基类 MT，**不是** EventsCBG） |

- `EventsCBGExecutor` 在 Jazzy **头文件里有**（`rclcpp/executors/events_cbg_executor/...`），但
  `component_container` 没有暴露选择它的入口。要复现第 17–19 关的 events-cbg，得自己写一个容器（挂账）。
- `component_container_mt` 的 `thread_num` 本机实测有效（默认 4 线程；`thread_num:=2` 少 2 条线程）。
- **判断容器到底是几线程**：别信命令行参数，数 `ls /proc/<PID>/task | wc -l` 或看 `--ros-args` 是否被认。

## 环境与命令坑（都会伪造实验数据）

### 本机新增（Jazzy / ARM / Pi）

- **`--executor-type` 静默失效**：Jazzy 的 `component_container` 不认识它，不报错，容器跑单线程。
  第 16–19 关的历史脚本已改成“选二进制”；自己手敲时也一样。
- **ARM 是弱内存模型**：第 22 关 §0 已按 ARMv8 重写；**不能拿 x86 TSO 的前提推本机机器码**。
- **outline atomics**：g++ 默认把 `fetch_add`/CAS 编成 `bl __aarch64_*`，真指令在 libgcc helper 里，
  且按 HWCAP 运行时分派 LSE / LL·SC。看机器码要看到 helper 或加 `-mno-outline-atomics`。
- **DDS 线程基线高**：空容器就有 ~15–18 条线程（Fast DDS）。第 12/17 关“数手”要用 **Δ**，不是绝对值。
- **只有 4 核**：第 19 关的 16 线程曲线、第 16–19 关的偏向数据不可跨机比较；要在本机复现先重跑基线。
- **`ros2 run` 的 `$!` 是外壳 PID**：脚本收工要直接跑二进制；用 `ros2 run ... &` 再 kill `$!` 会留孤儿容器。
- **`ros2 doctor` 在 Pi 上很慢**（本机实测 >20 秒），别把它塞进探针的等待循环。
- **Python 3.12（不是 3.14）**：老笔记里的 `/opt/ros/lyrical/lib/python3.14/...` 在本机对应
  `/opt/ros/jazzy/lib/python3.12/...`。
- **老路径**：文档里还有 `lyrical` / `/home/l` / `g++ 15` 作为历史记录；跑命令时换成
  `jazzy` / `$HOME` / `g++ 13`。探针脚本已自动处理，文档没改历史正文。

### 跨机通用

- **git push 要代理**：本机 `~/.gitconfig` 是 `http(s).proxy = http://192.168.137.1:7897`
  （远程代理机）。端口在监听 ≠ 隧道通；探针要探**真端点**
  `https://github.com/<repo>/info/refs?service=git-upload-pack`，返回 `000` 或
  `GnuTLS handshake failed` = 隧道不通 → 让用户重开代理/换节点，**别改 git 配置**。
- **`pgrep -f` ≠ `pgrep`**：不带 `-f` 匹配进程名（`pgrep -c compo` 是好尺子）；带 `-f` 匹配整条命令行，会捞到 gnome-keyring 的 `--components=pkcs11`。
- **`timeout` 只杀外壳**：`timeout 30 ros2 run …` 后节点会变孤儿并伪造数据。后台起 ROS 进程写进脚本文件，别用 `&` 挂 `&&` 链（`$!` 是子 shell PID）。
- **`.so` 不热重载**：改完 C++ 必须重建；`git checkout` 还原源码 ≠ 还原 `.so`。跑前比 `ls -l --time-style=+%m-%d_%H:%M` 的源码与 `.so` 时间戳，或 `strings build/.../x.so | grep -c "特征串"`。
- **日志行序 ≠ 发生顺序**：多线程写日志会抢；量顺序一律用**时间戳** `grep … | sort`。单线程才信行序。
- **两个终端都要 `source install/setup.bash`**：起容器那个终端漏 source，容器启动**一声不吭**，等 `component load` 才报 `Could not find requested resource in ament index`。自查 `echo $AMENT_PREFIX_PATH`。
- **`--ros-args` 不是 `--ros_args`**：写成下划线参数静默失效，旋钮转三档纹丝不动。
- **`set -u` 之后 source setup.bash** 会报 `AMENT_TRACE_SETUP_FILES: 未绑定的变量` → 用 `set +u … set -u` 夹住。
- **抓容器日志要 `stdbuf -oL -eL`**，否则 stdio 全缓冲，日志是空的。
- **`unload` 一个回调还睡着的组件** = 回执「成功」+ 容器随后 SIGSEGV；先停表再拆东西，回执不能当证据。
- **`ros2 bag record`** 脚本里用 SIGTERM（SIGINT 会卡死）；不接位置参数话题。
- **`colcon test`** 的 pytest cwd 是**源码目录**；要留约 7 分钟（`test_xmllint` 慢）。中途 kill 会伪造 `missing_result`。别手动 cd 进 `build/` 跑。
- **`xmllint` 慢/失败**是 IPv6 黑洞（原机已确诊；本机未复测）：
  `sudo sed -i 's/^#precedence ::ffff:0:0\/96  100/precedence ::ffff:0:0\/96  100/' /etc/gai.conf`；
  或 `--ctest-args -E xmllint` 跳过。
- **本机已装 rclcpp 头文件和 g++**：执行器 `.cpp` 现在读得到；但**读到源码 ≠ 在本机跑过** —— 结论仍要标「读的」还是「量的」。
- `.vscode` 自动补全是**故意关的**，不是配置错误，别「修」。

## 提交

```bash
git add -A
git commit -m "第N关: 标题（题眼）"     # 已有提交都用这个格式
git push                                # 先确认代理隧道通
```

当前未推送过的历史提交：无（`main` 与 `origin/main` 一致）。
第 22 关的预习与探针在 2026-11-20 一并入库；2026-11-22 换机适配（文档 + 探针）随后提交。
