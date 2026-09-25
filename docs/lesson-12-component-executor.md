# 第 12 关 · 组件与执行器（几只手？）

> 第 11 关掀掉了「一个节点 = 一个进程」。掀完之后立刻冒出一个新问题：
>
> **好几个节点住进同一个进程 —— 那它们谁来跑？**
>
> 你在第 7 关学过一句：**执行器决定"有几只手"**。那句话当时是在一个节点、一个进程里说的。
> 现在一个进程里有三个节点，这句话得重新问一遍：
>
> **这一只手（或这一池子手），是节点的，还是进程的？**
>
> 一句话答案：**手是进程的。**
> 所以同一个 `.so`、同一行代码、连 build 都不用重做 —— **只换一个容器，两个组件的命运就完全相反**。

---

## 目录

- [1. 本关目标](#1-本关目标)
- [2. 核心概念](#2-核心概念)
- [3. 完整代码](#3-完整代码)
- [4. 命令速查（CLI）](#4-命令速查cli)
- [5. 命令行工具速查](#5-命令行工具速查)
- [6. 构建与运行流程](#6-构建与运行流程)
- [7. 实测现象与结论 ⭐](#7-实测现象与结论-)
- [8. 踩坑记录](#8-踩坑记录)
- [9. 自测题](#9-自测题)
- [10. 附：跨关待办](#10-附跨关待办)
- [附：本关命令速记卡](#附本关命令速记卡)

---

## 1. 本关目标

走完这一关，你应该能回答四个问题：

1. 一个容器进程里装了三个节点，它们**共用几个执行器**？
2. 你怎么**用眼睛看见**"有几只手"？（不是查文档，是看日志）
3. 手不够的时候，谁会吃亏？（**不是"都慢一点"，是有明确的先后**）
4. 想让它们别互相拖累，**要改哪里**？—— 改组件代码，还是改容器？

### 你需要造的唯一一件东西：测速仪

"执行器有几只手"这件事本身看不见。要看见它，得**占住那只手一段时间**。

所以本关先造一个**不干正事的组件** `Sleeper`：1 秒的定时器，回调里**先打印、再睡 0.5 秒、再打印**。

```
第N拍 开始睡      ← 手被攥住了
   （睡 0.5 秒）
第N拍 睡醒了      ← 手松开了
```

它不发布任何话题、不调任何服务。它唯一的用途就是**把那只手占住 0.5 秒**，
然后我们看**别人在这 0.5 秒里能不能插进来**。

---

## 2. 核心概念

### 2.1 ⭐⭐ 执行器住在**进程**里，不住在**节点**里

第 7 关学到的是：**执行器 = 那几只手，回调是它一只一只抓起来跑的**。
这一关补上后半句：

> **执行器是进程启动时装配进去的，不是节点自带的。**

证据就在你眼前：`Sleeper` 这个类**一个字都没改**，`.so` **一个字节都没变**，
把它装进 `component_container` 和装进 `component_container_mt`，
两个实例之间**是否互相等**这件事，结果完全相反。

改的是**容器**（也就是进程），不是**组件**（也就是节点）。

```
进程（容器）
 ├── 执行器 ← 起进程那一刻装配的，「手」在这一层
 ├── 节点 A（组件）
 ├── 节点 B（组件）
 └── 节点 C（组件）
```

### 2.2 两个容器型号 = 两种执行器

| 容器命令 | 里面装的执行器 | 手 |
|---|---|---|
| `component_container`（默认） | `SingleThreadedExecutor` | **1 只** |
| `component_container_mt` | `MultiThreadedExecutor` | **一池子**（默认 = CPU 核数） |
| `component_container --executor-type multi-threaded` | 同上（**新的写法**） | 同上 |

> 📌 `mt` = **m**ul**t**i-**t**hreaded。这条路现在偏老 ——
> `component_container_mt` 起来时自己会提示"改用 `--executor-type`"。
> 这也是第 11 关 §9.2 题 5 的答案。

### 2.3 ⭐ 「有几只手」数得出来 —— 就是进程的线程数

多线程执行器的"一池子手"不是比喻，**它就是进程里多出来的那些线程**。

这台机器 16 核：

| 容器 | 进程的线程数 |
|---|---|
| `component_container`（单线程） | **18** |
| `--executor-type multi-threaded --ros-args -p thread_num:=1` | **18** |
| `--executor-type multi-threaded --ros-args -p thread_num:=2` | **19** |
| `--executor-type multi-threaded`（默认） | **33** |

> 底下那 17 条是 DDS 一大家子（运输、发现、监听……），**跟你写的东西无关**。
> 多出来的就是手：默认 16 条（= 核数），`thread_num:=1` 时 1 条。

**查法**（`<PID>` 换成容器进程号）：

```bash
ls /proc/<PID>/task | wc -l
```

### 2.4 ⭐ 手数是个**能直接设的参数**：`thread_num`

```bash
ros2 run rclcpp_components component_container \
  --executor-type multi-threaded --ros-args -p thread_num:=1
```

给了 1，就等于**明明是多线程容器，却只发一只手**。
执行器自己也知道这很怪，会打一条 WARN（英文原文 + 中文）：

```
[WARN] [rclcpp]: MultiThreadedExecutor is used with a single thread.
                 Use the SingleThreadedExecutor instead.
```

> 中文：**"多线程执行器只配了一条线程 —— 你应该改用单线程执行器。"**

⚠️ 注意 `--ros-args` 里是**减号**，不是下划线。写成 `--ros_args` 会**静默失效**
（参数根本没传进去，线程数一点没变）—— 详见 §8 坑 2。

### 2.5 ⭐⭐ 怎么"看见"手数？看**插队**

日志里怎么区分"一只手"和"一池子手"？不是看快慢（后面会看到快慢经常一样），
而是看**一个回调睡着的时候，别人的日志能不能插进来**。

**判据（本关唯一要记的一条）：**

> 盯 `sleeper_a` **自己**的「开始睡」和它**自己**的「睡醒了」这一对。
> **中间有没有夹着 `[sleeper_b]` 的行？**

| 结果 | 说明 |
|---|---|
| **夹进来了** | a 睡的时候 b 也在睡 → **不止一只手** |
| **没夹进来** | a 睡的时候 b 只能干等着 → **只有一只手** |

> 💡 这就是第 7 关你练过的那条判据（"`开始睡` 会不会连续出现两次"）**换了个地方再问一遍**。
> 判据没变，问的场景从"一个进程里两个回调"变成了"一个进程里两个节点"。

### 2.6 一只手一秒只能干那么多活

每个 `Sleeper`：1 秒一拍，拍里睡 0.5 秒 → **每秒要占掉 0.5 秒的手**。

| 装几个 | 每秒需要的手 | 一只手一秒只有 | 结果 |
|---|---|---|---|
| 1 个 | 0.5 秒 | 1 秒 | 绰绰有余，一拍整 1.000 秒 |
| 2 个 | 1.0 秒 | 1 秒 | **刚好排满**，两个都保住 1 秒，但**严丝合缝、一毫秒不剩** |
| 3 个 | 1.5 秒 | 1 秒 | **超载 50%** → 干不完 → **有人被拖长** |

**手不够的后果不是"平均都慢一点"，而是有明确的"先来后到"**（§7.6 有判据实验）。

### 2.7 三个数字，三个层面

这是本关和前后两关接起来的地方：

| 数字 | 是什么 | 哪一关 |
|---|---|---|
| **节点数** | 图上有几个节点 | 第 1 关起 |
| **进程数** | `pgrep` 数出来几个 | **第 11 关**（节点数 ≠ 进程数） |
| **线程数** | 进程里给执行器开了几条 | **第 12 关**（手是进程的） |

> 第 12 关这一路，**进程数从头到尾是 1，没有变过**。
> 变的只有线程数。这就是它俩不是一回事的直接证据。

---

## 3. 完整代码

### 本关唯一的新文件：`src/hello_ros_cpp/src/sleeper_component.cpp`

它就是 [`talker_component.cpp`](../src/hello_ros_cpp/src/talker_component.cpp) 改三处的产物：
**不发消息**（删掉 publisher）、**回调里加一觉**、**类名换掉**。

```cpp
#include <chrono>
#include <memory>

#include "rclcpp/rclcpp.hpp"
#include "rclcpp_components/register_node_macro.hpp"

using namespace std::chrono_literals;


// 第 12 关的"测速仪"：一个专门用来占住执行器的手的组件。
// 它不发布任何东西，只在定时器回调里睡一觉 —— 睡觉这段时间它攥着那只手不放。
class Sleeper : public rclcpp::Node
{
public:
    Sleeper(const rclcpp::NodeOptions & options) : Node("sleeper", options)
    {
        count_ = 0;
        timer_ = this->create_wall_timer(1s, [this]() { tick(); });
    }

private:
    void tick()
    {
        count_ += 1;
        RCLCPP_INFO(this->get_logger(), "第%d拍 开始睡", count_);

        // 睡觉这段时间，它攥着执行器的那只手不放 —— 这就是本关的"测速仪"
        rclcpp::sleep_for(500ms);

        RCLCPP_INFO(this->get_logger(), "第%d拍 睡醒了", count_);
    }

    rclcpp::TimerBase::SharedPtr timer_;
    int count_;
};

RCLCPP_COMPONENTS_REGISTER_NODE(Sleeper)
```

**三处和 `talker_component.cpp` 的差别**：

| | `talker_component.cpp` | `sleeper_component.cpp` |
|---|---|---|
| 成员变量 | `pub_` + `timer_` + `count_` | **只有** `timer_` + `count_`（不发消息就没有 publisher） |
| 回调里干什么 | 拼字符串 + `publish` | 打印 + **`rclcpp::sleep_for(500ms)`** + 打印 |
| 最后一行 | `RCLCPP_COMPONENTS_REGISTER_NODE(Talker)` | `..._NODE(Sleeper)` |

> ⚠️ 本关最经典的一个错就出在第 1 行差别上：**顺着"照第 37、38 行抄"抄来了一个 `pub_`**。
> 判别方法只有一个 —— **看这个类的构造函数里到底造了什么**（它造了几样，就只需要几个成员）。

### `CMakeLists.txt` 的改动

和 `talker_component` 那三行**一模一样**，只有两个名字换了，**并且不链 `std_msgs`**（它不发消息）：

```cmake
add_library(sleeper_component SHARED src/sleeper_component.cpp)
target_link_libraries(sleeper_component
  rclcpp::rclcpp
  rclcpp_components::component)
rclcpp_components_register_nodes(sleeper_component "Sleeper")
```

外加 `install(TARGETS ...)` 那块里**把 `sleeper_component` 列进去**：

```cmake
install(TARGETS talker_component sleeper_component
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
```

> ⚠️ 第 11 关坑 3 的老账：组件的 `.so` 装 `lib/`，**不是** `lib/${PROJECT_NAME}/`。

**`package.xml` 不用动**（`rclcpp_components` 第 11 关已经加过了）。

---

## 4. 命令速查（CLI）

### 起容器（三种手数）

```bash
# 一只手（默认）
ros2 run rclcpp_components component_container

# 一池子手（默认 = CPU 核数）
ros2 run rclcpp_components component_container_mt

# 一池子手，但明说几条（这条长，直接粘）
ros2 run rclcpp_components component_container --executor-type multi-threaded --ros-args -p thread_num:=1
```

> `--executor-type` 还可以接 `events-cbg`（配合 `--isolated`），本关没用到。

### 装 / 卸

```bash
ros2 component load /ComponentManager hello_ros_cpp Sleeper             # 装，节点名默认叫 sleeper
ros2 component load /ComponentManager hello_ros_cpp Sleeper -n sleeper_a # 装，顺手改节点名
ros2 component unload /ComponentManager 1                               # 按编号卸
```

> ⭐ **同一个类要装好几份，就必须用 `-n` 分开**，否则日志分不清谁是谁。
> 日志前缀跟着**节点名**走：`[sleeper_a]: 第1拍 开始睡`。

### 看清单

```bash
ros2 component list      # 容器里现在挂着谁、编号几号
ros2 component types     # 全世界有哪些组件型号（含官方包）
```

---

## 5. 命令行工具速查

### ⭐ 查残留容器：`pgrep -c compo`（第 11 关那把）本来就是好尺子

第 11 关用的是 `pgrep -c compo`，本关一开始我以为它坏了 —— **我错了，实测如下**：

| 命令 | 匹配什么 | 有容器 | 杀掉之后 |
|---|---|---|---|
| `pgrep -c compo` | **`comm`**（进程名，截 15 字符） | **1** ✅ | **0** ✅ |
| `pgrep -af compo` | **整条命令行文本**（`-f`） | 1 + **一串无辜的** | 1 + 一串 |

**差的就是那个 `-f`：**

- **不带 `-f`**：只匹配 `comm`。容器的 comm 是 `component_conta`（含 `compo`）；
  而 gnome-keyring 的 comm 是 **`gnome-keyring-d`** —— **不含 `compo`**，捞不到。**所以这把尺子是对的。**
- **带 `-f`**：匹配**整条命令行文本**，于是 `gnome-keyring-daemon --foreground --components=pkcs11`
  里那串 `--components=` 就把 `compo` 撞上了 —— **`-f` 会捞出一堆无关进程。**

> ⭐ **本关这一课的真正教训在这儿**：`pgrep` 的两种模式匹配的是**两个不同的东西**（进程名 vs 整条命令行）。
> **"尺子坏了"和"我把尺子举错了"是两回事** —— 这次是后者（详见 §8 坑 1）。

### 如果要用更精确的那把（推荐，本关后面都用它）

```bash
pgrep -af '[c]omponent_conta'
```

两个细节：

1. **写 `component_conta` 而不是 `component_container`**：Linux 的 `comm` 只留 15 个字符，
   进程名被截断成 `component_conta`（第 11 关坑）。**注意这条只在不带 `-f` 时成立** ——
   带了 `-f` 反而必须写全名 `component_container`（因为整条命令行里是全名）。
2. **`[c]` 那对方括号是防自匹配的正则技巧**：它匹配字母 `c`，
   但你的命令行里写出来的是 `[c]omponent_conta` 这串字面，所以 `pgrep` 捞不到自己的命令行。
   ⚠️ **但这个技巧只防"命令行里出现这个模式本身"** ——
   如果你的脚本里另外出现了完整路径 `/opt/.../component_container`，照样会被 `-f` 捞到（见 §8 坑 1 末尾）。

### 数线程（= 数手）

```bash
ls /proc/<PID>/task | wc -l
```

`<PID>` 怎么拿：`pgrep -c compo`（最简单）或 `pgrep -f component_container`（带 `-f` 时写全名）。

> ⚠️ 如果你是用 `ros2 run ...` 起的容器，`pgrep` 可能先捞到 `ros2 run` 那个**外壳**。
> 外壳的线程数没有意义 —— 第 10 关那个 947 秒孤儿就是这一族的。

### 看节点 / 话题（老三条，本关用来对照）

```bash
ros2 node list
ros2 topic list
ros2 component list
```

### 收工检查（第 9 关起的老规矩）

```bash
pgrep -c compo || echo 干净
```

---

## 6. 构建与运行流程

### 构建（新增了组件库，**必须** build）

```bash
source /opt/ros/lyrical/setup.bash
cd ~/ros2_learn_ws
colcon build --packages-select hello_ros_cpp --symlink-install
```

### 验收 1：`.so` 落在哪

```bash
ls -l install/hello_ros_cpp/lib/*sleeper*
```

要看到 `libsleeper_component.so`，而且它是个**软链**指向 `build/`。

### 验收 2：登记表上有没有它

```bash
source install/setup.bash      # ⚠️ 不 source 会【静默空】，第 11 关坑 6
ros2 component types
```

`hello_ros_cpp` 那一段下面要有：

```
hello_ros_cpp
  Talker
  Sleeper
```

> ⚠️ 你当时贴的是**全量输出**（40 多个包全列出来了）——
> 这比只贴半截强得多，但更好的是**只截你自己那一段**。

### 一次完整的实验（两个终端）

```bash
# 终端 A：起容器
source install/setup.bash
ros2 run rclcpp_components component_container

# 终端 B：装两个（名字必须分开，否则日志分不清）
source install/setup.bash
ros2 component load /ComponentManager hello_ros_cpp Sleeper -n sleeper_a
ros2 component load /ComponentManager hello_ros_cpp Sleeper -n sleeper_b
```

然后**盯终端 A**，只看一件事：`sleeper_a` 的「开始睡」和它自己的「睡醒了」中间，有没有 `[sleeper_b]`。

### 验收清单（**自己判，别让我判**）

- [ ] `ros2 component list` 里有两个编号
- [ ] 两个节点名不一样（`/sleeper_a`、`/sleeper_b`）
- [ ] 日志里**每条都带节点名前缀**，能一眼分清谁是谁
- [ ] 换容器之前，`pgrep -c compo` 是 **0**

---

## 7. 实测现象与结论 ⭐

> 本关所有数字都是实测的（日志带纳秒时间戳，直接对差值）。

### 7.1 基线：单个 `Sleeper` 的节奏

| 时间 | 谁 | 干什么 |
|---|---|---|
| 2855.761 | sleeper_a | 第1拍 开始睡 |
| 2856.262 | sleeper_a | 第1拍 睡醒了（**+0.500**） |
| 2856.761 | sleeper_a | 第2拍 开始睡（**+0.500**） |

**一拍整 1.000 秒**：0.5 睡 + 0.5 等。

> ⭐ **定时器的周期是从上一次"响"的那一刻开始算的，不是从回调跑完算起。**
> 回调吃掉的那 0.5 秒是从这 1 秒里**扣掉**的，不是加在 1 秒外面。
>
> 推论（后面要用）：**如果回调睡得比周期还长，定时器就一点空闲都没有了。**

### 7.2 两个 + 单线程容器：**严格交替**

| 时间 | 谁 | 干什么 |
|---|---|---|
| 2872.363 | sleeper_a | 第3拍 开始睡 |
| 2872.863 | sleeper_a | 第3拍 睡醒了 |
| 2872.863 | sleeper_b | 第2拍 开始睡（**+0.000**） |
| 2873.364 | sleeper_b | 第2拍 睡醒了 |
| 2873.364 | sleeper_a | 第4拍 开始睡（**+0.000**） |

**交错次数 = 0。** 一条线把它钉死了：**a 一醒，b 立刻接上；b 一醒，a 立刻接上，中间只隔 0.000 秒。**
像两条腿走路 —— 从不重叠，也从不空着。

而且两个**都保住了 1.000 秒**（2 × 0.5 = 1.0，正好排满一只手，一毫秒不剩）。

> **结论：节点是两个，手只有一只。**

### 7.3 两个 + 多线程容器：**插队了**

| 时间 | 谁 | 干什么 |
|---|---|---|
| 2888.418 | sleeper_a | 第3拍 开始睡 |
| 2888.456 | **sleeper_b** | 第1拍 睡醒了 ← **夹进来了** |
| 2888.919 | sleeper_a | 第3拍 睡醒了 |

`a` 在 2888.418 开始睡，**b 直到 2888.456 还醒着** —— 两个节点**同时在睡**。

**交错次数 = 18。** 判据翻转。

> ⭐ 这一格的关键是：**`.so` 一个字节没变、代码一行没改、build 都没重做。**
> 换的只是容器。

### 7.4 ⭐⭐ 判据实验：把 16 只手改成 1 只

上一条还"动了两样东西"（容器型号 = 执行器种类 + 手数）。**能不能只动手数？**

```bash
ros2 run rclcpp_components component_container \
  --executor-type multi-threaded --ros-args -p thread_num:=1
```

| 时间 | 谁 | 干什么 |
|---|---|---|
| 607.154 | sleeper_a | 第2拍 睡醒了 |
| 607.157 | sleeper_b | 第1拍 开始睡（+0.003） |
| 607.657 | sleeper_b | 第1拍 睡醒了 |
| 607.658 | sleeper_a | 第3拍 开始睡（+0.001） |
| 608.158 | sleeper_a | 第3拍 睡醒了 |

**交错次数 = 0。** 又回到严格交替。

| 容器配置 | 线程数 | 交错次数 |
|---|---|---|
| `component_container`（单线程） | 18 | **0** |
| `multi-threaded -p thread_num:=1` | 18 | **0** |
| `multi-threaded -p thread_num:=2` | 19 | **18** |
| `multi-threaded`（默认 16） | 33 | **18** |

> ⭐⭐ **手数从 16 改成 1，现象原封不动地消失 —— 病因就是"手数"这个数字本身**，
> 不是"容器型号"这个标签。

### 7.5 三个 + 一只手：产能被卡死

| 组件 | 平均周期 | 拍数（约 14 秒） |
|---|---|---|
| `sleeper_a`（先装） | **1.218 秒** | 15 |
| `sleeper_b` | 1.334 秒 | 13 |
| `sleeper_c`（最后装） | **2.001 秒** | 7 |

三个，每个都要每秒 0.5 秒的手 = **每秒要 1.5 秒**，而一只手只有 1 秒。

**产能是固定的**（一只手每秒只能干两个 0.5 秒的活）：

```
1/1.218 + 1/1.334 + 1/2.001 = 0.821 + 0.750 + 0.500 ≈ 2.07 拍/秒  ≈ 产能上限 2 拍/秒
```

超载的那部分，**一分不多一分不少，全变成"排队等"**。

### 7.6 ⭐ 谁吃亏？——「先来后到」（判据实验）

`sleeper_c` 最惨，是不是因为**名字叫 c**？换一下装载顺序就知道。

| 装载顺序 | 第一个装的 | 中间 | 最后装的 |
|---|---|---|---|
| c → b → a | c **1.218** | b 1.334 | a **2.001** |
| a → b → c | a **1.218** | b 1.334 | c **2.001** |

**数字一模一样，只有名字换了。** 决定快慢的是"**第几个装进来的**"。

> 📌 **这里只给到"现象 + 规则"。**
> 执行器内部为什么这么排（是不是每轮从头扫一遍节点表），这次**没有查**，
> 按第 5 关 L3 那条规矩：**没有证据的部分不算结论，只能算观察。**
>
> （两次独立测量给出 1.20 / 1.35 / 1.90 和 1.22 / 1.33 / 2.00 —— 形状完全一致，
> 最后装的那个稳定落在 1.9~2.0 秒。）

### 7.7 一张总表

| 装几个 | 容器 | 交错 | 各自的周期 |
|---|---|---|---|
| 1 | 单线程 | —（只有一个） | 1.000 |
| 2 | 单线程 | **不交错** | 1.000 / 1.000（刚好排满） |
| 2 | 多线程（16 手） | **交错** | 1.000 / 1.000 |
| 2 | 多线程（1 手） | **不交错** | 1.000 / 1.000 |
| 3 | 单线程 | 不交错 | 1.218 / 1.334 / **2.001** |

> ⭐ **注意"周期"那一列：装 2 个时，单线程和多线程的周期都是 1.000 —— 一模一样。**
> 所以**快慢看不出手数，只有"插队"能。**

---

## 8. 踩坑记录

### ❌ 坑 1：我把尺子举错了，却判成"尺子坏了"（**本关最该记的一条**）

我用 `pgrep -af compo` 清场，屏幕上冒出：

```
4498 /usr/bin/gnome-keyring-daemon --foreground --components=pkcs11,secrets --control-directory=...
```

**我当时的判断**：`compo` 这把尺子是坏的（会匹配到 gnome-keyring），
于是**连带宣告第 11 关一直用的 `pgrep -c compo` 也不可信**，并把这个"结论"当场讲给了他。

**这个判断是错的。实测：**

| 命令 | 有容器 | 杀掉之后 |
|---|---|---|
| `pgrep -c compo`（**不带 `-f`**） | **1** | **0** |
| `pgrep -af compo`（**带 `-f`**） | 1 + 一堆无关的 | 1 + 一堆无关的 |

**根因在 `-f`，不在 `compo`：**

- **不带 `-f`** → `pgrep` 匹配 **`comm`**（进程名）。
  容器是 `component_conta` ✅；gnome-keyring 是 **`gnome-keyring-d`** —— **不含 `compo`** ❌。
  → **第 11 关那把尺子是好的。**
- **带 `-f`** → 匹配**整条命令行文本**。
  `gnome-keyring-daemon --foreground --components=pkcs11` 里那串 `--components=` 正好撞上 `compo`。
  → **是我加的 `-f` 把无关进程捞了进来。**

> ⭐⭐ **两条要分开的结论：**
> ① **`pgrep -c compo` 没错**，他跑出来的 `1` 是真话 —— **当时确实还有一个容器进程活着**
>    （至于为什么和他的预期不符，那个现场已经过去了，还原不了；但那把尺子量对了）。
> ② **"尺子坏了"和"我把尺子举错了"，是两件完全不同的事。** 这次是后者。
>    我犯的错比"探针太短"严重 —— **我把自己的操作失误，说成了工具的缺陷，还让他记了下来。**

**改法（两条都对，看你要什么）：**

```bash
pgrep -c compo                    # 最短，够用（不带 -f，匹配 comm）
pgrep -af '[c]omponent_conta'     # 更明确，还能顺便看到"是哪几个"
```

⚠️ **`[c]` 技巧不是万能的**：它只防"命令行里出现这个模式本身"。
本关我写答案键脚本时踩了第二次 —— 脚本里有 `Q=/opt/ros/.../component_container` 这一行，
于是 `pgrep -af '[c]omponent_conta'` **把这行脚本自己捞了出来**（返回 2 而不是 1）。
**要数得准，就得连自己脚本里的路径一起防。**

### ❌ 坑 2：`--ros_args` 写成下划线 → 参数**静默不生效**（**我自己的**）

我准备答案键时把 `--ros-args` 打成了 `--ros_args`。结果是：

| 我以为在测 | 实际在测 | 线程数 |
|---|---|---|
| `thread_num:=1` | 默认（16 手） | **33**（没变） |
| `thread_num:=2` | 默认（16 手） | **33**（没变） |

**三组跑出来一模一样，我还差点当成"结论"。**
被抓出来是因为**数了一眼线程数** —— 参数生效的话它必须变。

> ⭐ **教训：一个旋钮转了三档、结果纹丝不动时，先怀疑旋钮没接上，别急着写结论。**
> 同族：第 4 关 `glob` 返回 `[]`（改了参数没改对地方）、第 10 关 `-r /chatter:=/foo`（写错左边 = 静默失效）。

### ❌ 坑 3：装了 b，忘了 a —— 组件跟着旧容器一起死了

清场的时候把**跑着 sleeper_a 的那个容器** Ctrl+C 了，然后重新起了一个容器、
只装 `sleeper_b`。现象是"日志里怎么只有 b"。

**当时唯一的法证线索**（在你自己贴的那行里）：

```
Loaded component 1 into '/ComponentManager' container node as '/sleeper_b'
                 ↑ 编号是 1
```

**编号是从 1 开始数的**（第 11 关那条"失败的装载会吃掉编号"就是它）。
b 拿到 1 → 说明它是这个容器里**头一个**装进去的 → **a 不在里面**。

> **动作**：换容器之后老老实实**把两个都重新装一遍**。第 11 关的"同生共死"（Ctrl+C 容器 = 组件全灭）。

### ❌ 坑 4：跳过了"先预测再运行"（**第 3 次了**）

题 12-3 只问了"会 / 不会"，还是没答就去敲命令了。

前两次：第 7 关题 7-3、第 9 关题 9-3。

> 本关**做对的地方**：后面几题都写了预测，而且**错了两次也对了两次** ——
> 错的那两次（"不会"、"只有最后一个"）**收获比猜对的还大**，因为预测制造了「预期」。
> **先说、再跑**，不是流程，是造「预期」的那个动作。

### ❌ 坑 5：贴输出时**没截断**（新毛病，与第 9 关相反）

`ros2 component types` 输出了 40 多个包，全贴上来了。

这比第 9 关的"只贴半截"好得多，但**信息密度太低**。更好的做法：

```bash
ros2 component types | head -5
```

> 第 9 关的老账是"贴半截"（把自证证据剪掉了）；
> 这一关翻到另一面 —— **贴整坨**。两边的目标是一样的：**让读的人一眼看到该看的那几行。**

---

## 9. 自测题

### 9.1 课堂已覆盖（附答案，先自己答一遍再点开）

<details>
<summary><b>题 1：一个容器里装了两个组件，它们共用几个执行器？</b></summary>

**一个。** 执行器是**进程**的，不是节点的。

**证据**：单线程容器里，`sleeper_a` 睡着时 `sleeper_b` 连"开始"都打不出来，
日志严格交替、接棒间隔 **0.000 秒** —— 两个节点在一只手上轮流。

</details>

<details>
<summary><b>题 2：怎么用日志判断"有几只手"？</b></summary>

**看插队**：盯一个节点**自己**的「开始睡」和「睡醒了」，中间有没有夹进别的节点。

- 夹进来了 → 两个回调同时在跑 → **不止一只手**
- 没夹进来 → **一只手**

⚠️ **不要看快慢** —— 装 2 个时，单线程和多线程的周期都是 1.000 秒，**完全一样**。

</details>

<details>
<summary><b>题 3：`component_container_mt` 和 `component_container` 差在哪？</b></summary>

`mt` = **m**ul**t**i-**t**hreaded。它里面装的是 `MultiThreadedExecutor`（一池子手，默认 = CPU 核数），
默认的 `component_container` 装的是 `SingleThreadedExecutor`（1 只）。

**新的写法**是 `component_container --executor-type multi-threaded`；
`component_container_mt` 这条路偏老了（它自己会提示你换）。

</details>

<details>
<summary><b>题 4：手数能不能不换容器就改？</b></summary>

能：

```bash
ros2 run rclcpp_components component_container \
  --executor-type multi-threaded --ros-args -p thread_num:=1
```

`thread_num:=1` 时甚至能"数出来"：线程数从 **33 掉到 18**，
而且执行器自己会打一条 WARN 说"多线程执行器只配了一条线程"。

</details>

<details>
<summary><b>题 5：三个组件塞进单线程容器，谁最慢？为什么？</b></summary>

**最后装进去的那个最慢**（约 2.0 秒一拍，正好慢一倍）；另外两个也被拖长了（1.2 / 1.3）。

**为什么**：每个要每秒 0.5 秒的手，三个一起要 **1.5 秒**，而一只手只有 1 秒 —— **超载 50%**。
总产能被卡死在"每秒 2 拍"，三个组件分这两拍，**先来后到**。

**判据实验**：换装载顺序，1.218 就跟着"第一个装的人"走了 —— 跟名字、跟代码都无关。

</details>

<details>
<summary><b>题 6：为什么说"执行器住在进程里，不住在节点里"？</b></summary>

因为**同一个 `.so`、同一行代码、连 build 都不用重做** ——
只把 `.so` 装进另一个容器（换一个进程），"两个组件会不会互相等"这件事，
结果就完全相反。

组件能带的东西里没有"手"这一项。手是**起进程那一刻**装配进去的。

</details>

### 9.2 留给下次的思考题（无答案）

1. **同一个节点里的两个回调，在多线程容器里会不会并行？**
   （提示：回到第 7 关。现在一个 `Sleeper` 只有一个定时器 ——
   让一个组件挂**两个**定时器，都放**默认回调组**，再看插队。需要改几行组件代码。）

2. **`--executor-type events-cbg` 是什么？** 加上 `--isolated` 又是什么？
   （提示：`component_container --help` 里有这两个词，第 11 关 §9.2 也没答。）

3. **手数设成 2，装 3 个组件会怎样？** 设成 3 呢？
   设计一个能**量出来**的实验，先写预测。

4. **`thread_num` 设成 0 会怎样？设成 1000 呢？**
   （提示：`--help` 里写着"省略它 = 用满系统可用核数"。）

5. **composition 到底省了什么、亏了什么？**
   同一个 `Sleeper`，装 3 份到一个容器 vs 用 `ros2 run` 起 3 个进程，
   量一下：进程数、线程总数、内存、**启动耗时**。

---

## 10. 附：跨关待办

### ① ⭐ 本关你真正做到的：**从"预测"到"判据实验"**

题 12-4 和 12-6 你都先写了预测，而且 12-4 猜错了 —— 这正是预测该有的样子。

差距还在**坑 4**（第 3 次跳过预测）。但趋势是好的：第 7 关 1 次、第 9 关连续跳、
本关只剩第一次跳了。

### ② ⚠️ 残留进程 —— 本关**没有第 6 次**

清场这条做到了。**但这一关真正暴露的不是"没清场"，是我把"尺子举错了"（`-f`）说成了"尺子坏了"，
还顺手否掉了第 11 关那把本来正确的 `pgrep -c compo`** —— 见坑 1，那条比清场本身重要。
**⚠️ 而"我说某条命令不可信"比"没清场"更危险** —— 它会让你**丢掉一件本来正确的工具**。
本关的教训是反过来的：**判一条命令的死刑之前，先把它单独跑一遍**（§5 那两张对照表就是这么来的）。

### ③ ⚠️ 贴输出：从"贴半截"翻到了"贴整坨"

见坑 5。两边都欠一点：**截到只留该看的那几行**。

### ④ 📌 一条固定的前置动作（本关固化）

**换容器/换实验之前，先确认三件事**：

```bash
pgrep -c compo                  # 1. 旧容器清干净了没（0 = 干净）
ros2 component list             # 2. 里面现在挂着谁
ls /proc/$(pgrep -c compo)/task | wc -l   # 3. 新容器起来之后数一遍线程（= 数手）
```

本关的坑 3（装了 b 忘了 a）就是跳过第 2 条的下场。

### ⑤ 本关的环境动作

- 新增 `src/hello_ros_cpp/src/sleeper_component.cpp`（组件，`add_library`）
- `CMakeLists.txt`：`add_library` + `target_link_libraries`（**不链 `std_msgs`**）+ `register_nodes` + `install` 里加名字
- `package.xml`：**不用动**
- 新增 `docs/lesson-12-component-executor.md`（本文件）

---

## 附：本关命令速记卡

```bash
# ── 清场（⭐ 别加 -f：不加只匹配进程名，加了会连整条命令行一起捞）──
pgrep -c compo                    # 最短；有容器=1、没有=0
pgrep -af '[c]omponent_conta'     # 想看"是哪几个"时用这条

# ── 起容器：三种手数 ─────────────────────────────────────────────
ros2 run rclcpp_components component_container                    # 1 只手
ros2 run rclcpp_components component_container_mt                 # 一池子（老写法）
ros2 run rclcpp_components component_container \
  --executor-type multi-threaded --ros-args -p thread_num:=1      # 明说几条（减号！）

# ── 装组件（同名要 -n 分开，否则日志分不清）──────────────────────
ros2 component load /ComponentManager hello_ros_cpp Sleeper -n sleeper_a
ros2 component list

# ── 数手：看容器进程的线程数 ─────────────────────────────────────
ls /proc/$(pgrep -f '[c]omponent_conta')/task | wc -l

# ── 本关唯一的判据 ──────────────────────────────────────────────
#   盯 sleeper_a 自己的「开始睡」和它自己的「睡醒了」，
#   中间有没有夹着 [sleeper_b]？夹了 = 不止一只手。
```

---

## 相关笔记

- [第 7 关 · 执行器与回调组](lesson-07-executor.md) —— **⭐ 本关直接接在它后面**：
  "执行器决定有几只手"这一句，在容器进程里长出了第二层 **"手是进程的"**。
  第 7 关的判据（"`开始睡` 会不会连续出现两次"）在本关**原样复用**。
- [第 11 关 · Composition](lesson-11-composition.md) —— 本关的前半句：
  **节点数 ≠ 进程数**（3 组件 / 4 节点 / 1 进程）。
  本关补上第三个数：**线程数**。§9.2 题 4 / 5 在本关结案。
- [第 5 关 · 动作](lesson-05-action.md) —— **§L3 那条规矩**在本关用到：「现象」和「病因」是两回事，
  没查过的部分只写现象，不写结论（§7.6 的"先来后到"就是这么处理的）。

**跨关串起来的三句话**：

- 第 11 关：**节点数 ≠ 进程数**（3 组件 / 4 节点 / 1 进程）
- 第 12 关：**进程数 ≠ 线程数**（1 进程 / 18 条线程，其中 1 条才是执行器的手）
- 两关合起来：**"一个节点 = 一个进程"和"一个节点 = 一只手"，两条默认都不成立。**
