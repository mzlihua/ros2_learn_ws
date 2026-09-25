# 第 13 关 · 回调组进容器（谁跟谁共用一把锁？）

> 第 12 关掀掉了「一个节点 = 一只手」，结论是：**执行器住在【进程】里**，
> 它决定"有几只手"。
>
> 掀完这一层，紧接着该问**下一层**：那"回调组"住在哪？
>
> 一句话答案：**回调组住在【节点】里。**
> 更准确地说：`default_callback_group` 是**每个节点各造一份**的。
>
> 于是同一池子手底下冒出一件怪事 ——
> **2 个组件（2 个节点）能互相插队，1 个节点里的 2 个定时器却不能。**
> 本关就是把这件事钉死。

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

### 1.1 要回答的两个问题

1. **同一个节点里的两个回调，能不能同时用两只手？**
2. 第 12 关里"2 个组件能插队"，**凭什么？** —— 它们也都没显式给回调组。

### 1.2 你需要造的：把测速仪改成"一个节点里两个都想睡"

第 12 关那件仪器 [`sleeper_component.cpp`](../src/hello_ros_cpp/src/sleeper_component.cpp)
只有**一个**定时器。本关给它加**第二个**（`tick_b`），两个都睡 500 毫秒：

- 先都不给回调组 → **两个定时器都落在【这一个节点的默认回调组】里**（同一把锁）
- 再各给一个互斥组 → **两把锁**

**不换代码逻辑、不换容器、只换一个参数。**

### 1.3 本关唯一的判据

> 盯 **A 自己**的「开始睡」和它**自己**的「睡醒了」，
> **中间有没有夹着 `B` 的行？**
> 夹了 = 两个回调同时在跑；没夹 = 一个一个来。

⚠️ 这**就是第 12 关那条判据**（当时是"`sleeper_a` 的中间有没有夹着 `[sleeper_b]`"），
**只把参照物从"另一个节点"换成了"同一个节点的另一个定时器"**。

⚠️ **不要看快慢** —— 第 12 关量过：装 2 个时单线程和多线程的周期都是 1.000 秒，
**完全一样**。本关同样如此，见 §7.5。

---

## 2. 核心概念

### 2.1 ⭐⭐ 手是进程给的，锁是节点自己带的

两关并排：

| | 住在哪 | 管什么 | 换它会怎样 |
|---|---|---|---|
| **执行器** | **进程** | 有几只手 | 第 12 关：换容器 → 严格交替 ↔ 互相插队 |
| **回调组** | **节点** | 谁跟谁共用一把锁 | 第 13 关：换组 → 不夹 ↔ 夹 |

**手再多，挂在同一把锁上的两个回调也只能一个一个来。**

线程数是 16 还是 1，对"同一个互斥组里的两个回调"完全没有区别 ——
因为它们 **不是在手这一层排队，是在锁这一层排队**。

### 2.2 ⭐ 默认回调组是"每个节点各一份"

`create_wall_timer(周期, 回调)` 不给第三个参数时，定时器落在**这个节点的**默认回调组里。
"这个节点的"是关键 —— 它**不是全局的、不是进程的**。

**证据在你第 7 关自己写的代码里**（`src/hello_ros/hello_ros/group_demo.py`）：

```python
class GroupDemo(Node):                    # ← 第 7 关那个文件
    def __init__(self):
        ...
        self.create_timer(0.5, self.tick,
                          callback_group=self.default_callback_group)
```

那个 `self` 就是**节点对象自己**（同一个 `self` 在这一小块里还出现在
`self.create_timer(...)` 和 `self.tick` 上 —— 造定时器的显然不是回调组）。

所以：

| 容器里装的东西 | 有几个"自己" | 几把锁 |
|---|---|---|
| 2 个组件 | 2 个节点 | **2 把** |
| 1 个组件（2 个定时器） | 1 个节点 | **1 把** |

**这就是"2 个组件能插队、1 个节点里的 2 个定时器不能"的全部原因。**

### 2.3 ⭐ 换锁 = 换结果（判据实验）

如果"挡住你的是锁"这个模型是对的，那么：

> **只换锁、不换手** —— 容器仍然是多线程，只把两个定时器分到两个组里 ——
> 插队就应该回来。

本关实测：**回来了**（§7.3）。
第 8 关那条"**好测试 = 新旧答案不同的那个输入**"，这里是它的又一次应用。

### 2.4 ⭐⭐ 造出来 ≠ 接住它（本关最值钱的一块）

`create_callback_group(...)` 返回一个 `rclcpp::CallbackGroup::SharedPtr`。
如果你**直接把它写在 `create_wall_timer` 那一行里**：

```cpp
// ⚠️ 反面写法：组是个临时对象，传完就没人持有
timer_a_ = this->create_wall_timer(
    1s, [this]() { tick_a(); },
    this->create_callback_group(rclcpp::CallbackGroupType::MutuallyExclusive));
```

结果**不是报错，也不是退化成默认组** —— 是：

> **一拍都不响，一个字都不报。**（实测见 §7.4）

**为什么？** 源码里那张"我的回调组"名单，存的**不是**拥有所有权的指针：

- `rclcpp/node_interfaces/node_base.hpp:154`
  —— `std::vector<rclcpp::CallbackGroup::WeakPtr> callback_groups_;`
- `rclcpp/executors/executor_entities_collection.hpp:49`
  —— `rclcpp::CallbackGroup::WeakPtr callback_group;`

**弱引用（`WeakPtr`）的意思是：我记着有这个东西，但它死不死我不负责。**
所有权在**创建它的那个人**手上 —— 创建的人一松手（临时对象出了语句就销毁），
组就没了，定时器手里只剩一个空引用，执行器永远看不到它。

**这条不只对回调组成立。** `create_publisher` / `create_subscription` / `create_timer`
造出来的东西全是这个脾气：**你不接住它，它就没了，而且不报错。**
第 11 关你写 `pub_` 和 `timer_` 那两个成员变量，就是在接住它们。

### 2.5 一句话收口

- 第 11 关：**节点数 ≠ 进程数**
- 第 12 关：**进程数 ≠ 线程数**（执行器住在进程里）
- 第 13 关：**线程数 ≠ 能同时跑的回调数**（回调组住在节点里）

---

## 3. 完整代码

### 3.1 `src/hello_ros_cpp/src/sleeper_component.cpp`（本关定稿版）

相比第 12 关，本关**新增/改了 4 行**：两个成员变量 + 构造函数里的两行。

```cpp
#include <chrono>
#include <memory>

#include "rclcpp/rclcpp.hpp"
#include "rclcpp_components/register_node_macro.hpp"

using namespace std::chrono_literals;


// 第 12/13 关的"测速仪"：一个专门用来占住执行器的手的组件。
// 它不发布任何东西，只在定时器回调里睡一觉 —— 睡觉这段时间它攥着那只手不放。
//
// 第 13 关给它加了【第二个】定时器（tick_b），并且把两个定时器分别挂到
// 【两个独立的互斥回调组】上 —— 定时器两个，锁两把。
class Sleeper : public rclcpp::Node
{
public:
    Sleeper(const rclcpp::NodeOptions & options) : Node("sleeper", options)
    {
        count_a_ = 0;
        count_b_ = 0;
        group_a_ = this->create_callback_group(rclcpp::CallbackGroupType::MutuallyExclusive);
        group_b_ = this->create_callback_group(rclcpp::CallbackGroupType::MutuallyExclusive);
        timer_a_ = this->create_wall_timer(1s, [this]() { tick_a(); }, group_a_);
        timer_b_ = this->create_wall_timer(1s, [this]() { tick_b(); }, group_b_);
    }

private:
    void tick_a()
    {
        count_a_ += 1;
        RCLCPP_INFO(this->get_logger(), "A 第%d拍 开始睡", count_a_);

        // 睡觉这段时间，它攥着执行器的那只手不放 —— 这就是本关的"测速仪"
        rclcpp::sleep_for(500ms);

        RCLCPP_INFO(this->get_logger(), "A 第%d拍 睡醒了", count_a_);
    }

    void tick_b()
    {
        count_b_ += 1;
        RCLCPP_INFO(this->get_logger(), "B 第%d拍 开始睡", count_b_);

        rclcpp::sleep_for(500ms);

        RCLCPP_INFO(this->get_logger(), "B 第%d拍 睡醒了", count_b_);
    }

    rclcpp::TimerBase::SharedPtr timer_a_;
    rclcpp::TimerBase::SharedPtr timer_b_;
    rclcpp::CallbackGroup::SharedPtr group_a_;
    rclcpp::CallbackGroup::SharedPtr group_b_;
    int count_a_;
    int count_b_;
};

RCLCPP_COMPONENTS_REGISTER_NODE(Sleeper)
```

⚠️ **`group_a_` / `group_b_` 这两个成员变量不是装饰** —— 见 §2.4 和 §7.4。
少了它们，组件装得上、日志一条不出。

### 3.2 `CMakeLists.txt`（本关**没动**）

组件是库（`add_library` + `rclcpp_components_register_nodes`），第 11 关已经配好。
本关只改同一个 `.cpp`，target 名、源文件名、`.so` 安装路径**全都不用动**。

### 3.3 ⚠️ 加练那版（**只用来做实验，别提交**）

把 §2.4 那个反面写法替换掉 §3.1 的第 22～25 行、并删掉第 52、53 行两个成员变量，
就是"静默炸弹"那版。做完实验记得改回来 —— **仓库里提交的那份是"两把锁"版，它就是准的**，
做完实验 `git checkout -- src/hello_ros_cpp/src/sleeper_component.cpp` 就复原了。

---

## 4. 命令速查（CLI）

```bash
# ── 起容器（本关两个都要用到）────────────────────────────────────
ros2 run rclcpp_components component_container              # 单线程（1 只手）
ros2 run rclcpp_components component_container_mt           # 多线程（一池子手，老写法）

# ── 装组件 ──────────────────────────────────────────────────────
ros2 component load /ComponentManager hello_ros_cpp Sleeper

# ── 看清单 / 卸 ─────────────────────────────────────────────────
ros2 component list
ros2 component unload /ComponentManager 1
```

⚠️ **装之前必须 `source install/setup.bash`** —— 否则 `ros2 component load` 报
`Could not find requested resource in ament index`（这是第 11 关坑 6 的复发，见 §8 坑 7）。

---

## 5. 命令行工具速查

### 查残留容器：`pgrep -c compo`（第 11 关那把，**不加 `-f`**）

```bash
pgrep -c compo                    # 有容器=1，没有=0
pgrep -af '[c]omponent_conta'     # 想看"是哪几个"时用
```

⚠️ **带不带 `-f` 是两个东西**（第 12 关 ⭐⭐）：不带 `-f` 匹配**进程名**，带 `-f` 匹配**整条命令行**
（会把 `gnome-keyring-daemon --components=pkcs11` 一起捞上来）。详见第 12 关 §8 坑 1。

### 看"装成功了没有"：装载回执

| 在哪看 | 打什么 |
|---|---|
| **你这边**（`ros2 component load` 那条终端） | `Loaded component 1 into '/ComponentManager' container node as '/sleeper'` |
| **容器那边**（终端 A） | `Load Library:` / `Found class:` / `Instantiate class:` 三行 |

**本关的"静默炸弹"就是靠"容器那边三行齐全、`[sleeper]` 零行"认出来的。**

### 收工检查（第 9 关起的老规矩）

```bash
pgrep -c compo                                          # 应为 0
ps -eo pid,etimes,args | grep -E "component_conta" | grep -v grep
```

---

## 6. 构建与运行流程

### 构建（改了 `.cpp` **必须** build）

```bash
source /opt/ros/lyrical/setup.bash
colcon build --packages-select hello_ros_cpp --symlink-install
```

### 一次完整的实验（两个终端）

```
终端 A：ros2 run rclcpp_components component_container_mt
终端 B：ros2 component load /ComponentManager hello_ros_cpp Sleeper
```

盯 **10 秒**，然后 Ctrl+C 收掉容器（**别忘了**，见 §8 坑 4）。

### 验收清单（**自己判，别让我判**）

1. `pgrep -c compo` 在实验前是 **0**、收工后也是 **0**
2. 容器那边有 `Load Library` / `Found class` / `Instantiate class` **三行**
3. 你那边有 `Loaded component N ... as '/sleeper'` **一行**
4. 然后才去看 A/B 有没有夹

---

## 7. 实测现象与结论 ⭐

### 7.1 六张牌

| # | 容器里装什么 | 回调组 | 容器 | 夹？ | 谁跑的 |
|---|---|---|---|---|---|
| 1 | 2 个组件（2 节点）| 各自默认 | 单线程 | 不夹（0 次） | 第 12 关 |
| 2 | 2 个组件（2 节点）| 各自默认 | **多线程** | **夹**（18 次） | 第 12 关 |
| 3 | 1 个组件（2 定时器）| **都在默认** | 单线程 | 不夹（0 次，46 行） | 本关 |
| 4 | 1 个组件（2 定时器）| **都在默认** | **多线程** | **不夹（0 次）** ← **题眼** | 本关 |
| 5 | 1 个组件（2 定时器）| **各一个互斥组** | **多线程** | **夹** ← 判据实验 | 本关 |
| 6 | 同上，但**组没人接住** | 各一个组（虚的） | 多线程 | **一拍都不响** | 本关 |

**第 4 行 vs 第 5 行：容器一模一样（多线程），只换了锁。**
**第 4 行 vs 第 1 行：容器一模一样、回调组写法一模一样，只差"装的是 2 个节点还是 1 个节点"。**

### 7.2 第 3 行原始输出（单线程容器 + 都在默认组）

```
[1790334232.639140113] [sleeper]: B 第1拍 开始睡
[1790334233.139621615] [sleeper]: B 第1拍 睡醒了   ← +0.5005 秒
[1790334233.139713192] [sleeper]: A 第1拍 开始睡   ← +0.0001 秒
[1790334233.640043883] [sleeper]: A 第1拍 睡醒了   ← +0.5003 秒
[1790334233.640206642] [sleeper]: B 第2拍 开始睡   ← +0.0002 秒
[1790334234.140544422] [sleeper]: B 第2拍 睡醒了
[1790334234.140629043] [sleeper]: A 第2拍 开始睡
[1790334234.640850369] [sleeper]: A 第2拍 睡醒了
```

**严格交替，0 次交错**（全程 46 行）。

### 7.3 第 4 行原始输出（**多线程容器** + 都在默认组）—— 题眼

```
[1790334184.606391956] [sleeper]: B 第1拍 开始睡
[1790334185.106567605] [sleeper]: B 第1拍 睡醒了   ← +0.5002 秒
[1790334185.106694234] [sleeper]: A 第1拍 开始睡   ← +0.0001 秒
[1790334185.607057269] [sleeper]: A 第1拍 睡醒了   ← +0.5004 秒
[1790334185.607307827] [sleeper]: B 第2拍 开始睡   ← +0.0003 秒
```

**仍然是 0 次交错**，与第 3 行（单线程容器）**看不出任何区别**。

⭐ **16 只手 vs 1 只手，对这两个定时器完全没有区别** —— 因为它们卡的**不是手**。

### 7.4 第 5 行原始输出（多线程容器 + 各一个互斥组）—— 判据实验

```
[1790327652.394677435] [sleeper]: B 第1拍 开始睡
[1790327652.394765316] [sleeper]: A 第1拍 开始睡   ← 差 0.088 毫秒
[1790327652.894943131] [sleeper]: B 第1拍 睡醒了   ← +0.5003 秒
[1790327652.894943139] [sleeper]: A 第1拍 睡醒了   ← 比 B 晚 8 纳秒
[1790327653.394531142] [sleeper]: B 第2拍 开始睡
[1790327653.394621246] [sleeper]: A 第2拍 开始睡
[1790327653.894728792] [sleeper]: B 第2拍 睡醒了
```

**夹了**：`A 开始睡` 和 `B 开始睡` 只差 **0.088 毫秒**，两次"睡醒了"只差 **8 纳秒** ——
它俩是**同时**在睡。

**唯一的改动是"各给一个回调组"**（容器、代码逻辑、睡得时长都没动）。
→ **挡住你的从来不是手，是锁。**

### 7.5 第 6 行原始输出（组没人接住）—— 静默炸弹

```
[INFO] [...265.072838415] [ComponentManager]: Load Library: .../lib/libsleeper_component.so
[INFO] [...265.073505514] [ComponentManager]: Found class: rclcpp_components::NodeFactoryTemplate<Sleeper>
[INFO] [...265.073537538] [ComponentManager]: Instantiate class: rclcpp_components::NodeFactoryTemplate<Sleeper>
```

**装载回执三行齐全，`[sleeper]` 行数 = 0，一个字都没报。**

⚠️ 注意：**"装成功了"和"跑起来了"是两件事** —— 这一行是第 4 关以来
"**绿灯 ≠ 做了你想做的事**"家族的**第六个成员**（前五个见 §10 ④）。

### 7.6 一张总表：看什么能区分，看什么不能

| 你想知道的事 | 看什么 | **不要**看什么 |
|---|---|---|
| 有几只手 | **夹不夹**（第 12 关判据） | 周期快慢（单线程/多线程都是 1.000） |
| 谁跟谁共用一把锁 | **夹不夹**（本关判据，同一把尺子） | 线程数（16 还是 1 都一样） |
| 组件装上了没有 | 装载回执**三行 + 一行** | 上面三行出来了就以为"跑起来了"（第 6 行反例） |

---

## 8. 踩坑记录

### ❌ 坑 1：把"单线程容器"预测成"会夹"

第 3 行（单线程容器 + 都在默认组）课堂上预测的是"**会**"，实测**不夹**。

单线程容器里只有**一只**手，第二个回调**没有任何可能**插进去 ——
"互斥组"和"只有一只手"这两道闸门，**任何一道关着，结果都是不夹**。

> ⚠️ 只记"现象"，不编"病因"：当时没有追问为什么会这么预测（第 5 关 §L3 那条纪律）。

### ❌ 坑 2：把"各给一个组"预测成"不夹"

第 5 行课堂上预测的是"**不夹**"，实测**夹**。

这一处**错得非常有价值** —— 它正是本关的判据实验：
**"换锁就翻盘"这件事，只有真的跑了才知道。** 预测错了，才发现自己心里那个模型不对。

### ❌ 坑 3：贴输出时**恰好剪掉了最关键的那一行**

第 5 行跑完，贴过来的四行是：

```
A 第13拍 开始睡
A 第13拍 睡醒了
B 第13拍 睡醒了
B 第14拍 开始睡
```

**判据本身那一行（`B 第13拍 开始睡`）不在里面** —— 于是从这四行看，"B 是从 A 睡完之后才开始睡的"，
像是**不夹**，正好把结论读反了。

**但时间戳替它作证了**：`B 睡醒了` 是 `664.895131855`，
往前推 0.500 秒 = **`664.395`** —— 那就是 B 开始睡的时刻，而 A 是 `664.394761` 开始睡的。
**两个"睡醒了"只差 7 纳秒。**

⭐ **补上那行之后结论就反过来了。** 这次被问"B 是什么时候开始睡的"之后，
**你自己把前面那一段完整重贴了出来** —— 这是第 9 关"贴半截"、第 12 关"贴整坨"之后，
**第一次把缺的那几行找回来。**

### ❌ 坑 4：残留进程（**第 6 次**）

收尾时那个 `component_container_mt` 还活着 —— **403 秒**（近 7 分钟），
是"静默炸弹"那次实验留下的。

**自第 9 关固化的前置动作仍然有效，且必须两头做**：

```bash
pgrep -c compo        # 实验【前】必须是 0；实验【后】也必须回到 0
```

### ❌ 坑 5：`create_callback_group` 写在定时器那一行里（**本关最值钱的一块**）

见 §2.4 / §7.5。**不报错、不打日志、组件装得上、一条输出都没有。**

### ❌ 坑 6（**我自己的**）：`&` 挂在 `&&` 链上，`$!` 拿到的是外壳

我为了给本关补答案键，写了一条这样的命令：

```bash
source ... && BIN=... && "$BIN" ... > log 2>&1 & CPID=$!
```

**`&` 挂的是整条 `&&` 链**，所以 `$!` 拿到的是那个后台**子 shell** 的 PID，
不是容器的 PID —— `kill $CPID` 杀的是外壳，容器照样活着。

**这正是 [[第 9 关]] / [[第 10 关]] 那条老坑的当场复发**：
**`timeout` 杀的是外壳、`timeout` 包的 `ros2 run` 杀的是外壳，
这次是我自己手动 `&` 出来的外壳。** 改用独立脚本之后一次就对了。

### ❌ 坑 7：`ros2 component load` 前忘了 `source install/setup.bash`

```
[ERROR] [ztest.ComponentManager]: Could not find requested resource in ament index
Failed to load component: Could not find requested resource in ament index
```

**这是第 11 关坑 6 的复发** —— `/opt/ros` 能跑，但 `ament index` 里看不见你的包。
**换个终端就要重 source 一次**（第 11 关那条"静默空"的兄弟：这次是"报错"，比静默空好一点）。

---

## 9. 自测题

### 9.1 课堂已覆盖（附答案，先自己答一遍再点开）

<details>
<summary><b>题 1：一个节点里的两个定时器，装进多线程容器会同时跑吗？</b></summary>

**不会。**

两个定时器都没给回调组 → 都落在**这一个节点的默认回调组**里 → **同一把锁** →
互斥组一次只放一个回调进来。**16 只手也一样。**

**证据**：第 4 行 vs 第 3 行（单线程容器）的输出**看不出区别**，都是 0 次交错。

</details>

<details>
<summary><b>题 2：默认回调组是"每个节点一份"还是"全进程一份"？证据在哪？</b></summary>

**每个节点一份。**

**证据**就在第 7 关你自己写的 `group_demo.py` 里：

```python
self.create_timer(0.5, self.tick,
                  callback_group=self.default_callback_group)
```

`self` 是**节点对象自己**（同一个 `self` 也出现在 `self.create_timer` 和 `self.tick` 上）。
既然它是"**我自己的**默认回调组"，那就是每个节点各造一份。

**推论**：2 个组件 = 2 个节点 = **2 把锁** → 第 2 行能夹；
1 个组件 = 1 个节点 = **1 把锁** → 第 4 行不能夹。

</details>

<details>
<summary><b>题 3：把 <code>create_callback_group(...)</code> 直接写进 <code>create_wall_timer</code> 那一行，会怎样？为什么？</b></summary>

**一拍都不响，而且一个字都不报。**

因为那个组是个**临时对象**，语句一结束就销毁了；而节点记它的方式是**弱引用**：

- `rclcpp/node_interfaces/node_base.hpp:154` —— `std::vector<rclcpp::CallbackGroup::WeakPtr> callback_groups_;`
- `rclcpp/executors/executor_entities_collection.hpp:49` —— `rclcpp::CallbackGroup::WeakPtr callback_group;`

**弱引用 = 我记着有这个东西，但它死不死我不负责。** 所有权在创建者手上。
创建者松手 → 组没了 → 定时器手里剩个空引用 → 执行器永远看不到它。

</details>

<details>
<summary><b>题 4：这条"必须用成员变量接住它"的规矩，还适用哪些东西？</b></summary>

`create_publisher` / `create_subscription` / `create_timer` / `create_service` / `create_client`
—— **凡是 `create_xxx` 返回 `SharedPtr` 的，你不接住它，它就没了，而且不报错。**

第 11 关写 `pub_` / `timer_` 两个成员变量就是在接住它们。
**"没接住"这类 bug 的共同症状是：程序跑得好好的，就是那件事没发生。**

</details>

<details>
<summary><b>题 5：本关的判据是什么？和第 12 关的判据差在哪？</b></summary>

**判据一模一样**：盯一个东西**自己**的「开始睡」和「睡醒了」，中间有没有夹别人的行。

**差的只是参照物**：

- 第 12 关：夹的是**另一个节点**（`[sleeper_b]`）→ 测的是**有几只手**
- 第 13 关：夹的是**同一个节点的另一个定时器**（`B`）→ 测的是**是不是同一把锁**

**同一把尺子，换了个对象量。**

</details>

<details>
<summary><b>题 6：<code>component_container_mt</code> 现在是什么状态？</b></summary>

**已经标记为弃用**，它自己会打：

```
[WARN] [component_container_mt]: This executable is deprecated and will be removed in M-turtle.
Use 'component_container --executor-type multi-threaded' instead.
```

**新写法**：`ros2 run rclcpp_components component_container --executor-type multi-threaded`

⚠️ 这个 `--executor-type` 是**程序自己的参数**，必须写在 `--ros-args` **之前**（第 12 关坑 2）。

</details>

### 9.2 留给下次的思考题（无答案）

1. **`--executor-type events-cbg` 是什么？加上 `--isolated` 又是什么？**
   （第 12 关 §9.2 题 2 留下的，两关都没答。`component_container --help` 里有这两个词。）
2. **把两个互斥组换成【可重入】组（`Reentrant`），会怎样？**
   同一个节点、两个可重入定时器、多线程容器 —— **先写预测**。
   （提示：第 7 关的结论是"可重入组 = 允许重叠，不是允许并行"，本关要验证它在**同一节点的两个定时器**上成不成立。）
3. **一个组件挂 3 个定时器、都在默认组、各睡 0.5 秒**，会怎样？
   一只手一秒只够干两个 0.5 秒的活 —— **这次是谁吃亏？**（第 12 关 §7.6"先来后到"的直接延伸）
4. **手数设成 2，装 3 个组件**会怎样？设成 3 呢？（第 12 关 §9.2 题 3）
5. **composition 到底省了什么、亏了什么？** 同一个 `Sleeper` 装 3 份到一个容器
   vs 用 `ros2 run` 起 3 个进程，量：进程数、线程总数、内存、**启动耗时**。（第 12 关 §9.2 题 5）
6. **把 `create_publisher` 的返回值也丢掉**会怎样？—— 验证 §9.1 题 4 那条推广。
   （预测：`ros2 topic list` 里还会不会有那个话题？）

---

## 10. 附：跨关待办

### ① ✅ 本关你真正做到的：**把缺的那一行找回来了**

坑 3。你贴的输出缺了判据本身那一行，被问"B 是什么时候开始睡的"之后，
**你没有重跑、而是把前面那一段完整重贴了出来** —— 证据一直在你手里。

### ② ⚠️ 预测成绩：4 题 1 对，但两次错的都比对的更有用

| 题 | 你预测 | 实测 | |
|---|---|---|---|
| 第 3 行（单线程 + 同组） | 会 | 不夹 | ❌ |
| 第 4 行（多线程 + 同组） | 不夹 | 不夹 | ✅ |
| 第 5 行（多线程 + 各组） | 不夹 | **夹** | ❌ |
| 加练（组没人接住） | 不夹 | **一拍都不响** | ❌ |

**第 5 行那次错了才是这一关的关键** —— 它逼出了判据实验。
**"先预测再运行"的价值不在猜对，在于造出「预期」**，好让「预期 − 实际」把异常顶出来。

### ③ ⚠️ 残留进程：**第 6 次**

见坑 4。前置动作两头做：实验前 `pgrep -c compo` 必须是 0，收工后也要回到 0。

### ④ 📌 "绿灯 ≠ 做了你想做的事"家族，本关添第六个成员

| 关 | 病症 |
|---|---|
| 第 4 关 | `glob` 返回 `[]` / `CMakeLists` 漏 `add_executable` → build 绿灯，`ros2 run` 才报找不到 |
| 第 6 关 | 文件在磁盘上 ≠ **被注册了**（三张登记表） |
| 第 7 关 | 跑起来了、有输出、没报错 ≠ **实验做了** |
| 第 11 关 | 有人替你记了一笔，你**没去核对**（`ament` 索引 / `.so` 落错目录） |
| 第 12 关 | 参数写错（`--ros_args`）→ **静默不生效**，三档纹丝不动 |
| **第 13 关** | **你造了它，但没人接住** —— 它一声不响地没了 |

### ⑤ 本关的环境动作

- 仪器恢复成"两把锁"那版（教学期间备份在 `/tmp`，现已收入仓库
  —— **仓库里那份才是准的**，`/tmp` 里的临时文件已清理）。
- 教学用的六行答案键全部实测在案（§7），其中第 1、2 行是第 12 关的老数据，
  第 3、4、6 行是我在 `/ztest` 命名空间下补测的，第 5 行是课堂测量。
- `colcon test` 与提交见 README 的进度行。

---

## 附：本关命令速记卡

```bash
# ── 两头都要做的前置动作（残留容器会伪造数据）──────────────────
pgrep -c compo                    # 实验前 / 收工后都必须是 0

# ── 起容器：本关要对比的两个 ────────────────────────────────────
ros2 run rclcpp_components component_container              # 单线程（1 只手）
ros2 run rclcpp_components component_container_mt           # 多线程（一池子手）

# ── 装组件（必须先 source install/setup.bash）──────────────────
source install/setup.bash
ros2 component load /ComponentManager hello_ros_cpp Sleeper

# ── 本关唯一的判据 ──────────────────────────────────────────────
#   盯 A 自己的「开始睡」和它自己的「睡醒了」，
#   中间有没有夹着 B 的行？夹了 = 不是同一把锁。

# ── 源码里那两处"弱引用"（本关最值钱的一条）────────────────────
#   rclcpp/rclcpp/node_interfaces/node_base.hpp:154
#   rclcpp/rclcpp/executors/executor_entities_collection.hpp:49
```

---

## 相关笔记

- [第 7 关 · 执行器与回调组](lesson-07-executor.md) —— **本关的正前方**：
  "回调组只在两个正经回调抢同一把锁时才说话"这句话，本关第一次放进了**组件容器**里。
  第 7 关那条三路对照表（同一个互斥组 / 同一个可重入组 / 各自一个组）在本关**原样复用**，
  参照物从"订阅 + 定时器"换成了"定时器 + 定时器"。
- [第 12 关 · 组件与执行器](lesson-12-component-executor.md) —— **本关的直接上一关**：
  它把执行器放进**进程**，本关把回调组放进**节点**。
  第 12 关的判据（"夹不夹"）在本关**一字不改地复用**。
- [第 11 关 · Composition](lesson-11-composition.md) —— 仪器 `sleeper_component.cpp` 的上游，
  也是"节点 ≠ 进程"那句的出处。

**跨关串起来的三句话**：

- 第 11 关：**节点数 ≠ 进程数**（3 组件 / 4 节点 / 1 进程）
- 第 12 关：**进程数 ≠ 线程数**（执行器住在【进程】里）
- 第 13 关：**线程数 ≠ 能同时跑的回调数**（回调组住在【节点】里）

**两句话的最终形态**：

> **手是进程给的，锁是节点自己带的。**
> 手再多，挂在同一把锁上的两个回调也只能一个一个来。
