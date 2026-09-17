# 第 7 关 · 执行器与回调组

> ROS 2 核心基础 · 课程笔记
> 学习日期：2026-09-17
> 环境：ROS 2 Lyrical / Python 3.14 / 工作区 `~/ros2_learn_ws`

---

## 目录

1. [本关目标](#1-本关目标)
2. [核心概念](#2-核心概念)
3. [完整代码](#3-完整代码)
4. [API 速查表](#4-api-速查表)
5. [命令行工具速查](#5-命令行工具速查)
6. [构建与运行流程](#6-构建与运行流程)
7. [实测现象与结论 ⭐](#7-实测现象与结论-)
8. [踩坑记录](#8-踩坑记录)
9. [自测题](#9-自测题)
10. [附：跨关待办](#10-附跨关待办)

---

## 1. 本关目标

前六关都在**造东西**：话题、服务、参数、launch、动作、自定义消息。每一关都是"写一个能用的节点"。

本关不一样 —— **本关不改任何业务逻辑**。

| | 前六关 | 本关 |
|---|---|---|
| 改什么 | 加功能（新的发布者、新的服务……） | **一行都不改**，只改"谁来调回调" |
| 产出 | 能跑的节点 | **一个能解释"为什么会卡住"的结论** |
| 验收 | 输出对不对 | **预测的日志和实际的日志对不对得上** |

要回答的问题就一句：

> **同一份代码，为什么有时候回调会互相卡住？**

这个问题是**欠账**，从第 1 关欠到第 5 关：

| 关 | 当时的观察 | 当时没讲透的那一层 |
|---|---|---|
| 1 | "回调是收到消息时触发的" | 触发它的到底是谁？ |
| 2 | "两个请求不会同时跑" | 为什么不会？ |
| 5 | "单线程执行器下取消不生效" | 那多线程为什么就生效了？ |

**答案就是本关的两个旋钮。**

本关产出：

| 文件 | 作用 |
|---|---|
| `hello_ros/group_demo.py` | 实验节点：一个慢订阅者 + 一个 0.5 秒定时器 |
| `docs/lesson-05-action.md` 的 **6 处订正** | 第 5 关的结论是错的，本关实测推翻了它 |

---

## 2. 核心概念

### 2.1 两个旋钮：一个管"几只手"，一个管"拿不拿得到锁"

ROS 2 里"回调什么时候跑、能不能同时跑"由**两层**决定，它们是**独立的两个旋钮**：

| 层 | 是什么 | 决定 |
|---|---|---|
| **执行器 Executor** | 谁来调回调 | **有几只手** |
| **回调组 Callback Group** | 回调之间的互斥关系 | **第二只手能不能拿同一把锁** |

```python
# 旋钮 1：执行器 —— 几只手
rclpy.spin(node)                                  # 一只手（SingleThreadedExecutor，默认）
rclpy.spin(node, executor=MultiThreadedExecutor())  # 一池子手

# 旋钮 2：回调组 —— 第二只手能不能拿同一把锁
node.create_subscription(..., callback_group=某个组)
```

**为什么是"锁"？** 因为 `rclpy` 内部给每个回调组配了一把锁：

- **互斥组**（`MutuallyExclusiveCallbackGroup`）：这个组里**同一时刻只允许一个回调在跑**。谁先拿到锁谁先跑，**其他人排队等**。
- **可重入组**（`ReentrantCallbackGroup`）：同一个组的回调**可以同时跑**，**不用等前面的跑完**。

⚠️ 注意：**互斥组挡的是"同一个组里"的回调**。不同组的回调之间**互不影响** —— 这是本关最有用的那一半，见 §7.1。

### 2.2 默认的那一个：什么都不写 = 所有回调挤在一个互斥组里

**不写 `callback_group=` 时，回调会进 `node.default_callback_group`。**

而 `default_callback_group` 是一个**互斥组**。所以：

> **一个节点里，只要你没写 `callback_group=`，那么它的所有回调（订阅、定时器、服务）都在同一个互斥组里 → 全局串行。**

这一句话把前几关的旧账全解释掉了：

- **第 2 关**"两个服务请求不会同时跑" —— 因为两个服务回调在同一个默认互斥组里，第二个必须排队。
- **第 1 关**"回调是 executor 调的" —— executor 拿锁、调回调、放锁，循环往复。

```python
# 这两行其实是同一件事
node.create_timer(0.5, self.tick)
node.create_timer(0.5, self.tick, callback_group=node.default_callback_group)
```

`callback_group=` 可以加在这些东西上：

| 加在哪 | 写法 |
|---|---|
| 订阅 | `node.create_subscription(类型, '话题', 回调, 10, callback_group=组)` |
| 定时器 | `node.create_timer(周期, 回调, callback_group=组)` |
| 服务 | `node.create_service(类型, '服务名', 回调, callback_group=组)` |
| 动作服务端 | `ActionServer(node, 类型, '名字', ..., callback_group=组)` |

### 2.3 ⭐⭐ `execute_callback` 是个特例（本关最值钱的发现）

**在动作服务端上，回调组根本不起作用。**

这不是"效果不明显"，是**它压根没参与**。原因在 `rclpy` 源码里，两行：

```python
# /opt/ros/lyrical/lib/python3.14/site-packages/rclpy/action/server.py

# 第 379 行：把 ActionServer 这个整体挂进回调组
callback_group.add_entity(self)
self._node.add_waitable(self)

# ...

# 第 686 行（上面那行注释是源码自己写的）
# Schedule user callback for execution
if self._node.executor:
    _: Task[None] = self._node.executor.create_task(self._execute_goal, execute_callback,
                                                    goal_handle)
```

拆开看：

| 行 | 干了什么 | 后果 |
|---|---|---|
| `:379` | `callback_group.add_entity(self)` —— 挂进去的是 **`self`（ActionServer 对象）** | 锁保护的是"收目标/收取消请求"这些**框架动作** |
| `:686` | `executor.create_task(...)` —— 你的 `execute_callback` 被当成**一个裸任务**丢进线程池 | **它不挂在任何回调组上** |

所以：

> **不管你把 `execute_callback` 放进互斥组还是可重入组，它都拿不到那把锁 —— 因为它根本没有去拿。**
> 没人争锁，"互斥"和"可重入"当然没有任何区别。

**结论：动作服务端能不能响应取消，只取决于执行器有几个线程，跟回调组无关。**

这就是第 5 关那个错误结论的根因 —— 当时我把执行器和回调组**两处一起改**，看到取消生效，就把功劳平分给了它们。**两处一起改 = 功劳平分，分不清哪个才是必要的。** 一次只改一个变量。

### 2.4 一句话口诀

> **执行器决定"有几只手"，回调组决定"第二只手能不能拿同一把锁"。**
> **手不够（单线程），再宽的回调组也白搭；锁够宽（可重入），手不够照样串行。**

还有一条**反直觉**的，本关实测出来的：

> **可重入组是"允许重叠"，不是"允许并行"。**
> 把它当成"并行开关"打开，会得到一个**副作用** —— 同一个慢回调会**自己叠自己**（见 §7.1 中间那行）。

---

## 3. 完整代码

### `src/hello_ros/setup.py` 的改动

```python
    entry_points={
        'console_scripts': [
            # ...（前 12 个略）
            'group_demo = hello_ros.group_demo:main',
        ],
    },
```

⚠️ **改了 `setup.py` 必须重新 `colcon build`** —— `--symlink-install` 免不掉这一条，因为它改的是"装什么"，不是"装的内容"。改完才能 `ros2 run hello_ros group_demo`。

### `src/hello_ros/hello_ros/group_demo.py`

```python
import time

import rclpy
from rclpy.callback_groups import MutuallyExclusiveCallbackGroup
from rclpy.executors import MultiThreadedExecutor
from rclpy.node import Node
from std_msgs.msg import String          # 消息类型：std_msgs 包里的 String


class GroupDemo(Node):
    """一个慢订阅者 + 一个 0.5 秒定时器：看回调组到底管不管事."""

    def __init__(self):
        super().__init__('group_demo')

        # ⭐ 这个文件要回答一句话：慢回调睡那 2 秒时，定时器还滴不滴答？
        #    答案由两个决定拼出来，下面两行各管一个，必须分开看。
        #
        #    【决定一】慢回调进哪个组 —— 决定"它会不会挡别人 / 会不会叠自己"
        #      MutuallyExclusiveCallbackGroup()  组内一次只跑一个回调，
        #                                        慢回调排自己的队，不占用外人
        #      ReentrantCallbackGroup()          组内可同时跑多个，慢回调会
        #                                        自己叠自己（实测 3 个一起睡）
        #      self.default_callback_group       和定时器挤同一组，定时器只能
        #                                        排队等它睡完（实测 0 次滴答）
        #
        #    【决定二】定时器进哪个组 —— 决定"它会不会被别人挡住"
        #
        #    本文件的答案：慢回调 → 独立互斥组；定时器 → 默认组。
        #    效果：定时器 0.5 秒照常滴答（实测 2 秒睡里滴了 4 次），
        #          慢回调之间仍互斥，不重叠（"开始睡"从没连着出现两次）。
        #
        #    关键：可重入组是"允许重叠"，不是"允许并行"。
        #          想既不挡别人、又不叠自己，只能分成两个互斥组。
        group = MutuallyExclusiveCallbackGroup()

        self.create_subscription(String, 'chatter', self.cb_slow, 10,
                                 callback_group=group)          # 决定一
        self.create_timer(0.5, self.tick,
                          callback_group=self.default_callback_group)  # 决定二

    def cb_slow(self, msg):
        """慢回调：打印 → 睡 2 秒 → 打印."""
        self.get_logger().info('慢回调：开始睡 2 秒')
        time.sleep(2)
        self.get_logger().info('慢回调：睡醒了')

    def tick(self):
        self.get_logger().info('定时器：滴答')


def main(args=None):
    with rclpy.init(args=args):
        node = GroupDemo()
        rclpy.spin(node, executor=MultiThreadedExecutor())


if __name__ == '__main__':
    main()
```

**为什么必须用 `MultiThreadedExecutor`？** 因为本实验要看"定时器会不会被慢回调挡住"——**只有存在第二只手，这个问题才有意义**。单线程下没有任何悬念，一切排队。

### 实验用的另外两种摆法（只在 `/tmp` 跑过，没进仓库）

为了把三路对照表测全，`__init__` 里那两行换一下即可：

```python
# 摆法 A：同一个互斥组（= 什么都不写，默认行为）
group = self.default_callback_group
...
self.create_timer(0.5, self.tick, callback_group=group)

# 摆法 B：同一个可重入组
group = ReentrantCallbackGroup()
...
self.create_timer(0.5, self.tick, callback_group=group)

# 摆法 C：各自一个组（= 本文件的答案）
group = MutuallyExclusiveCallbackGroup()
...
self.create_timer(0.5, self.tick, callback_group=self.default_callback_group)
```

---

## 4. API 速查表

```python
# ---------- 执行器：决定"有几只手" ----------
import rclpy
from rclpy.executors import MultiThreadedExecutor

rclpy.spin(node)                                    # 单线程（默认）—— 一只手
rclpy.spin(node, executor=MultiThreadedExecutor())  # 多线程 —— 一池子手

# 也可以用 with 管生命周期（本项目统一用这种写法）
with rclpy.init(args=args):
    node = MyNode()
    rclpy.spin(node, executor=MultiThreadedExecutor())

# ---------- 回调组：决定"第二只手能不能拿同一把锁" ----------
from rclpy.callback_groups import (
    MutuallyExclusiveCallbackGroup,   # 互斥：组内同时只跑一个 ← 默认就是这个
    ReentrantCallbackGroup,           # 可重入：组内可以同时跑多个
)

grp = MutuallyExclusiveCallbackGroup()
grp = ReentrantCallbackGroup()
grp = node.default_callback_group     # 不写 callback_group= 时用的那个（互斥组）

# ---------- 把回调挂进组 ----------
node.create_subscription(MsgType, 'topic', self.cb, 10, callback_group=grp)
node.create_timer(0.5, self.tick, callback_group=grp)
node.create_service(SrvType, 'service', self.handle, callback_group=grp)
ActionServer(node, ActType, 'action', execute_callback=..., callback_group=grp)
#   ⚠️ 动作服务端上 callback_group 对 execute_callback 无效，见 §2.3
```

**两个组放一起对照：**

| | `MutuallyExclusiveCallbackGroup` | `ReentrantCallbackGroup` |
|---|---|---|
| 组内两个回调能同时跑吗 | ❌ 不能，排队 | ✅ 能 |
| 同一回调会被重入（自己叠自己）吗 | ❌ 不会 | ✅ 会 |
| 谁用 | **默认**，`default_callback_group` | 明确需要并发时 |
| 常见写法 | **给会阻塞的回调单独开一个** | 少用；用错会叠罗汉 |

**跨语言对照**（C++ 支线用得上）：

| Python（`rclpy`） | C++（`rclcpp`） |
|---|---|
| `SingleThreadedExecutor` | `rclcpp::executors::SingleThreadedExecutor` |
| `MultiThreadedExecutor` | `rclcpp::executors::MultiThreadedExecutor` |
| `MutuallyExclusiveCallbackGroup` | `rclcpp::CallbackGroupType::MutuallyExclusive` |
| `ReentrantCallbackGroup` | `rclcpp::CallbackGroupType::Reentrant` |

---

## 5. 命令行工具速查

```bash
# ---------- 跑本关的实验 ----------
ros2 run hello_ros group_demo      # 终端 A：实验节点
ros2 run hello_ros talker          # 终端 B：发布者，触发慢回调

# ---------- 本关用得最多的三个排查命令 ----------

# ① 包里有哪几个可执行文件（"No executable found"的第一反应）
ros2 pkg executables hello_ros

# ② 这个话题上有没有发布者（0 = 没有人发，回调永远不会响）
ros2 topic info /chatter
#    期望看到 Publisher count: 1；是 0 就说明 talker 没起来

# ③ 谁还在跑（"数值莫名其妙"的第一反应）
ps -eo pid,etimes,args | grep -E 'group_demo|talker' | grep -v grep
#    etimes = 活了多久（秒）。几百秒的一定是上次实验没关的残留

# ---------- 日志时间戳是 Unix 纪元秒，可以反解成人类时间 ----------
date -d @1789626155
#    → Thu Sep 17 02:22:35 PM CST 2026

# ---------- 清残留 ----------
pkill -f "hello_ros"
#    ⚠️ pkill -f 匹配的是【命令行文本】，不是节点名。
#       进程命令行是 python3 xxx.py 时，pkill -f 节点名是打不中的
```

### 日志时间戳怎么读

ROS 2 日志形如：

```
[INFO] [1789626155.163821000] [group_demo]: 慢回调：开始睡 2 秒
        ^^^^^^^^^^ ^^^^^^^^^   ^^^^^^^^^^
        秒         纳秒        节点名
```

- 前面那串是 **Unix 纪元秒**（1970-01-01 起算），不是"运行了多久"。
- **判断一份日志是不是新的**：`date -d @1789626155` 解一下，跟当前时间比。
  （本关踩过一次：贴了一份 2 小时 44 分钟前的日志当成新的。）
- **判断两次运行的间隔**：两个时间戳相减，**不用**去数日志行数。

---

## 6. 构建与运行流程

### 构建

```bash
cd ~/ros2_learn_ws
source /opt/ros/lyrical/setup.bash
source install/setup.bash

# group_demo 刚注册进 setup.py，必须 build 一次
colcon build --packages-select hello_ros --symlink-install
source install/setup.bash        # build 完要重新 source，否则看不到新的可执行文件
```

### 验收清单

```bash
# ① 可执行文件注册成功了吗（不依赖任何节点）
ros2 pkg executables hello_ros | grep group_demo
#    期望：hello_ros group_demo

# ② 跑起来看看（终端 A）
ros2 run hello_ros group_demo
#    期望：每 0.5 秒一行「定时器：滴答」，其余什么都没有

# ③ 触发慢回调（终端 B）
ros2 run hello_ros talker
#    终端 A 期望变成：慢回调睡 2 秒，期间滴答 4 次，睡醒后紧接着下一次

# ④ 收尾：两边都 Ctrl+C，然后确认干净
ps -eo pid,etimes,args | grep -E 'group_demo|talker' | grep -v grep
#    期望：输出为空

# ⑤ 测试（本关没改业务代码，但改了 setup.py）
colcon test --packages-select hello_ros
colcon test-result --verbose
#    期望：flake8 / mypy / pep257 全过
```

---

## 7. 实测现象与结论 ⭐

### 7.1 ⭐⭐ 三路对照表：订阅回调 vs 定时器回调抢锁

**实验设置**：`group_demo`，`MultiThreadedExecutor`（手是够的）。
慢回调睡 **2 秒**；定时器 **0.5 秒**一拍，所以不被打断时 2 秒里应该滴 **4 次**。

| 摆法 | 定时器被打断？ | 慢回调会重叠？ |
|---|---|---|
| **A. 同一个互斥组**（= 默认） | ✅ **被打断**（睡 2 秒里滴 **0** 次） | ❌ 不重叠 |
| **B. 同一个可重入组** | ❌ 不停（滴 **4** 次） | ✅ **会重叠**（实测 3 个一起睡） |
| **C. 各自一个组** ← 目标 | ❌ 不停（滴 **4** 次） | ❌ 不重叠 |

**逐行读这张表：**

- **A 行**：慢回调和定时器在**同一个互斥组**里，共用一把锁。慢回调一睡 2 秒，定时器就得排队 2 秒 → **0 次滴答**。这是"什么都没写"的默认行为。
- **B 行**：换成可重入组，锁放开了，定时器 4 次一次不少 —— **但它把慢回调自己也放开了**。同一个组的可重入回调可以重入，于是第 2 秒还没睡完，第 3 个、第 4 个消息又进来了，**3 个慢回调同时睡**。修好了一个问题，引入了另一个。
- **C 行**：慢回调**自己一个互斥组**（组里只有它，锁永远不会被别人抢），定时器**留在默认组**。两个组各有一把锁，互不相干 → 定时器不被打断；而慢回调在自己组里仍然互斥 → **不重叠**。**这才是要的。**

**这就是回调组在生产代码里最常见的用法：**

> **把会阻塞（耗时）的回调单独放进它自己的互斥组，别拖累别人；其余回调留在默认组。**

### 7.2 ⭐⭐ 2×2 矩阵：动作服务端上回调组**完全没参与**（订正第 5 关）

**实验设置**：`fib_server`，`order=30`。客户端在第 3 条反馈时发取消请求。

| 执行器 | 回调组 | 收到取消请求 | 进度条数 | 最终状态 | 耗时 |
|---|---|---|---|---|---|
| 单线程 | 默认 | ❌ | 29 | 4 | 30 秒 |
| 单线程 | `Reentrant` | ❌ | 29 | 4 | 30 秒 |
| 多线程 | 默认 | ✅ | 3 | 5 | 3.3 秒 |
| 多线程 | `Reentrant` | ✅ | 3 | 5 | ~4 秒 |

**怎么读这张表：**

> **上两行一字不差，下两行一字不差。**
> **横向看（换回调组）没有任何变化；纵向看（换执行器）天翻地覆。**

**结论：在动作服务端上，回调组完全没参与。真正的开关只有"线程数"。**

原因见 §2.3：`execute_callback` 是 `executor.create_task(...)` 丢出去的**裸任务**，压根不挂回调组；`callback_group.add_entity(self)` 挂进去的是 ActionServer 那个整体。**没人在争那把锁。**

**这一条推翻了第 5 关的结论。** 第 5 关写的是"取消生效需要 `MultiThreadedExecutor` + `ReentrantCallbackGroup` 两个一起"——那是**我的归因错误**：当时我把两处一起改，看到取消生效，就把功劳平分了。`docs/lesson-05-action.md` 已订正 6 处。

**方法上的教训（比结论本身重要）：**

> **两处一起改 = 功劳平分，分不清哪个才是必要的。一次只改一个变量。**

### 7.3 ⭐ 定时器**不排队**：错过的拍子就丢掉了

摆法 A（同一个互斥组）下，慢回调睡 2 秒，定时器本该滴 4 次。实测：

```
定时器：滴答          ← 慢回调开始睡之前
慢回调：开始睡 2 秒
                      ← 这 2 秒里，0 次滴答
慢回调：睡醒了
定时器：滴答          ← 睡醒后 7 毫秒，补打【一次】
```

**这里有两个容易想错的地方：**

| 想当然 | 实际 |
|---|---|
| "憋了 4 次，睡醒后一起放出来" | ❌ **只补一次** |
| "错过的拍子会排进队列等着" | ❌ **丢掉了，不排队** |

**原因**：`rcl` 的定时器**不会把错过的 tick 攒起来**。醒来后如果有欠账，它**只补一次**（把下一次提前到"立刻"），而不是补满 4 次。

> **一句话：定时器不是"每 0.5 秒一定发生一次"，而是"每 0.5 秒来问我一次，我不在就算了"。**

**这条的实用价值**：看到定时器日志里有大段空白，**别去数"少了几次"，那几次是找不回来的**。要问的是"这段时间里谁按着锁"。

### 7.4 ⭐ 摆法 C 的日志长什么样（"1 毫秒"彩蛋）

这是做完本关之后，`group_demo.py` 在摆法 C 下的真实输出（时间戳只留秒后 3 位）：

```
163.821  慢回调：开始睡 2 秒
163.848  定时器：滴答          ┐
164.347  定时器：滴答          │ 睡觉的 2 秒里
164.847  定时器：滴答          │ 整整 4 次滴答
165.347  定时器：滴答          ┘
165.821  慢回调：睡醒了         ← 正好 2.000 秒
165.822  慢回调：开始睡 2 秒     ← 隔了 1 毫秒
```

**三个可以自己验证的数：**

| 看什么 | 数出来 | 说明 |
|---|---|---|
| 睡觉 2 秒里滴了几次 | **4 次**（`163.848 / 164.347 / 164.847 / 165.347`） | 间隔精确 `0.500` 秒，一次没漏 → 没被挡 |
| `开始睡` 连着出现过两次吗 | **没有**，每次都被一条 `睡醒了` 隔开 | → 没有重叠 |
| `睡醒了` → 下一次 `开始睡` | **1 毫秒** | 第二条消息早就在队列里，锁一松立刻被拿起 |
| 每一轮 `开始睡` → `睡醒了` | 都是 **2.000 秒** | 说明没人在跟它抢锁 |

**最后那个"1 毫秒"值得多看一眼**：它说明**消息在互斥组的队列里排队**，锁一释放就立刻被下一个人拿走。这就是"互斥"在日志里的样子 —— **不是拒绝，是排队**。

---

## 8. 踩坑记录

### ❌ 坑 1：命令名敲错 —— `fid_server`

```
ros2 run hello_ros fid_server
→ No executable found
```

`b` / `d` 是镜像字母，**手打命令名很容易敲错**。

**修法（一条命令）**：

```bash
ros2 pkg executables hello_ros      # 12 个名字一次列全
```

**更重要的是**：终端有 **Tab 补全**，而且实测可用：

```bash
ros2 run hello_ros fib<Tab>         # → fib_client fib_server
```

```bash
complete -p ros2                     # → complete -F _python_argcomplete ros2
```

> **这跟"在编辑器里关掉自动补全"是两件事。**
> 编辑器补全补的是**代码**（关掉有意义，手写练手）；终端补全补的是**命令名**（没有练手价值）。
> **命令可以 Tab 补全，只有代码要手打。**

⚠️ **不要在终端里按 ↑ 翻历史命令** —— 翻出来的是旧命令，改了哪个参数你自己不记得。要查就用 `history 5` 看清楚了再敲。

### ❌ 坑 2：回调体是**空的**

`cb_slow` 只写了 docstring，**函数体一行都没有**：

```python
def cb_slow(self, msg):
    """慢回调：打印 → 睡 2 秒 → 打印."""
    # ← 这里一行都没有
```

症状：**两种摆法跑出来一模一样**，于是得出结论"回调组怎么摆都不管用"。

**这不是回调组的问题，是实验根本没做。** 空函数被调用 1000 次也不会产生任何输出。

### ❌ 坑 3：没起发布者 —— 回调**一次都没被触发**

`/chatter` 上没有任何发布者，`cb_slow` **永远不会响**。

症状同上：**两种摆法跑出来一模一样**（都只有定时器在滴答）。

**判断命令**：

```bash
ros2 topic info /chatter
```

```
Publisher count: 0      ← 0 就是没人发，回调永远不响
Subscription count: 1
```

### ❌ 坑 4：**残留进程**污染实验

本关出现两次：

1. 上一次课留下的 `mode_server` **残留了 41341 秒（11.5 小时）**。
2. 本关做完实验，**三个进程没关**（`group_demo.py` + `ros2 run ... talker` + `talker` 本体），跑了 12 分钟。

**症状**：日志里出现**不属于这次运行**的行；或者数值莫名其妙（两个发布者抢同一个话题，输出交错）。

**每次实验的固定动作**：

```bash
# 实验前
ps -eo pid,etimes,args | grep -E 'group_demo|talker' | grep -v grep

# 实验后
pkill -f "hello_ros"
```

⚠️ **`pkill -f` 匹配的是命令行文本，不是节点名。**
进程命令行是 `python3 src/xxx.py` 时，`pkill -f 节点名` **打不中**。这时要按 PID 杀：

```bash
kill <PID>
```

（也可以用变量拼接绕开"自匹配"：`P="fib""_server"` —— 直接写 `pkill -f fib_server` 时，**这条命令自己的命令行里也含 `fib_server`，会把自己也匹配上**。）

### 三条坑的公共形状

坑 2 和坑 3 的症状**完全相同**（两种摆法跑出来一样），但根因一个是"回调是空的"、一个是"回调没被调用"。**症状相同 ≠ 病因相同。**

而这个"跑起来了、有输出、没报错，但实验根本没做"的形状，**本关是第三次出现**：

| 关 | 形状 |
|---|---|
| 4 | `colcon build` **绿灯**，但 launch 文件没被装进去 |
| 6 | build **成功**，但 `import` 报 `No module named ...` |
| 7 | 节点**跑起来了、有输出、没报错**，但回调是空的 / 没被触发 |

> **「跑起来了、有输出、没报错」≠「实验做了」。**
> **绿灯只证明"没出错"，不证明"做了你想做的事"。**
> **固定动作：跑完先问一句"我期望的那一行，出现了吗？"**

---

## 9. 自测题

### 9.1 课堂已覆盖（附答案）

<details>
<summary><b>题 1：<code>rclpy.spin(node)</code> 和 <code>rclpy.spin(node, executor=MultiThreadedExecutor())</code> 的区别是什么？</b></summary>

默认的 `rclpy.spin(node)` 用的是 **`SingleThreadedExecutor`** —— **一只手**。不管有多少个回调就绪，**同一时刻只能跑一个**，其余排队。

`MultiThreadedExecutor()` 是**一池子手**（线程池），就绪的回调可以**同时跑** —— 但**能不能同时跑，还要看它们是不是在同一个互斥组里**（§2.1）。

两者是**独立的两个旋钮**：执行器管"有几只手"，回调组管"第二只手能不能拿同一把锁"。

</details>

<details>
<summary><b>题 2：不写 <code>callback_group=</code> 时，回调进哪个组？这意味着什么？</b></summary>

进 **`node.default_callback_group`**，而它是个 **`MutuallyExclusiveCallbackGroup`**。

所以：**一个节点里所有没写 `callback_group=` 的回调，都在同一个互斥组里 → 全局串行，谁也跑不过谁。**

这一句解释了第 2 关"两个服务请求不会同时跑"。

</details>

<details>
<summary><b>题 3：在动作服务端上，把 <code>execute_callback</code> 放进 <code>ReentrantCallbackGroup</code> 能让取消生效吗？</b></summary>

**不能。回调组在动作服务端上完全不参与。**

`rclpy/action/server.py:686` 用 `executor.create_task(self._execute_goal, execute_callback, goal_handle)` 把你的回调当成**裸任务**丢出去 —— **它不挂任何回调组**。而 `:379` 的 `callback_group.add_entity(self)` 挂进去的是 **ActionServer 那个整体**。

**没人在争那把锁，互斥和可重入当然没区别。** 能不能响应取消，**只取决于执行器有几个线程**（§7.2 的 2×2 矩阵）。

</details>

<details>
<summary><b>题 4：同一个互斥组里，定时器 0.5 秒一拍、回调睡 2 秒。醒来后定时器补几次？</b></summary>

**只补一次。**

`rcl` 的定时器**不排队** —— 睡着的这 2 秒里错过的 4 拍**直接丢掉了**，醒来后只补打一次（把下一次提前到"立刻"）。

答"补 4 次"是把定时器当成了"攒账"的东西，**它不是**。

</details>

<details>
<summary><b>题 5：怎么让"慢回调不被打断"<i>同时</i>"慢回调之间也不重叠"？</b></summary>

**给慢回调单独开一个互斥组，定时器留在默认组。**

```python
group = MutuallyExclusiveCallbackGroup()          # 慢回调：自己的锁
self.create_subscription(String, 'chatter', self.cb_slow, 10, callback_group=group)
self.create_timer(0.5, self.tick,
                  callback_group=self.default_callback_group)   # 定时器：默认组
```

- **两个组各有一把锁** → 定时器不会被慢回调挡住（4 次滴答）
- **慢回调在自己组里仍然互斥** → 不会自己叠自己（不重叠）

⚠️ **别用可重入组代替** —— 它是"允许重叠"，开了之后慢回调会**自己叠自己**（实测 3 个一起睡）。

**这是回调组在生产代码里最常用的写法：把会阻塞的回调单独隔离出去。**

</details>

<details>
<summary><b>题 6：怎么判断一份 ROS 日志是不是"这次的"？</b></summary>

日志开头那串数字是 **Unix 纪元秒**（不是"运行了多久"）：

```bash
date -d @1789626155        # → Thu Sep 17 02:22:35 PM CST 2026
```

跟当前时间比一下就知道是不是新的。

**本关真踩过一次**：贴了一份时间戳解码为 **11:36:30** 的日志，而当时已经是 **14:20** —— **2 小时 44 分钟前的**。

顺带：判断两次运行的间隔**直接拿两个时间戳相减**，不用去数日志行数。

</details>

### 9.2 留给下次的思考题（无答案）

1. **两个订阅者，各睡 2 秒，都挂在同一个可重入组上。** 此时来 4 条消息，会同时有几个回调在跑？**先预测再跑。**

2. **一个节点里同时有：一个服务回调（睡 3 秒）、一个定时器（0.2 秒）。** 什么都不写（都用默认组）时，定时器会被挡吗？改成"各自一个组"之后呢？**两个预测都写下来再跑。**

3. `MultiThreadedExecutor()` **不给参数**时用几个线程？怎么指定线程数？（提示：去查 `help(MultiThreadedExecutor)`）

4. **可重入组下，慢回调"自己叠自己"有什么实际危害？** 举一个真实场景（提示：想想一个正在写共享变量或者发命令给机器人的回调被重入了会怎样）。

5. `MultiThreadedExecutor` 是"一池子手"，那么**两个不同的互斥组**里的回调，能同时跑吗？（这一题是本关那张三路对照表的直接推论，**不要运行，从概念上推**。）

---

## 10. 附：跨关待办

本关暴露和复发的习惯问题：

### ① 贴半截输出 / 不读输出（本关**复发**）

本关最典型的一次：**贴了一份 2 小时 44 分钟前的日志当成新的**。日志里的时间戳自己就写着答案。

**固定的检查动作**：贴日志前扫两眼 ——

- 有没有 `Traceback`？
- 走到最后一行了吗？
- **时间戳是新的吗**（`date -d @...`）？

### ② 实验没搭起来就下结论（本关**新出现，卡了 3 次**）

`fid_server`（敲错）/ `cb_slow`（函数体空的）/ 没起 `talker`（回调没被触发）—— **代码一次都没写错，全是实验环境的问题。**

**固定的检查动作**：得出"XX 不管用"这个结论之前，先问一句 **"我期望的那一行日志，出现过吗？"**
—— 没出现过，那就是实验没做，不是结论。

### ③ 跳过"先预测"

本关有两次是先跑再看。**"先预测、再运行"不是走流程，它就是在造"预期"那一半。**

看出来问题 = **预期 − 实际**。缺了"预期"，就算实际结果摆在眼前也认不出来 —— 这正是"不会看日志"的真正原因（不是读不懂，是**没有基线**）。

### ④ 可枚举的东西，去查一眼，别猜

本关全胜记录：`ros2 pkg executables` / `ros2 topic info` / `history 5` / `Tab` / `date -d @...` —— **五次都是一发命中，没有一次需要讲道理。**

**对"名字、参数、字段"这类可枚举的问题，永远优先给"去查一眼"的命令；只有"为什么会这样"才需要讲。**

---

## 附：本关命令速记卡

```bash
# ---------- 跑实验 ----------
ros2 run hello_ros group_demo                # 终端 A
ros2 run hello_ros talker                    # 终端 B

# ---------- 排查（本关三个主力）----------
ros2 pkg executables hello_ros               # 有哪些可执行文件
ros2 topic info /chatter                     # Publisher count 是几
ps -eo pid,etimes,args | grep -E 'group_demo|talker' | grep -v grep

# ---------- 日志时间戳反解 ----------
date -d @1789626155

# ---------- 清残留 ----------
pkill -f "hello_ros"
kill <PID>                                   # pkill 打不中时按 PID 杀

# ---------- 测试 ----------
colcon test --packages-select hello_ros
colcon test-result --verbose
```

**本关一句话总结：**

> **执行器决定"有几只手"，回调组决定"第二只手能不能拿同一把锁"。**
> **可重入组是"允许重叠"，不是"允许并行"。**
> **想既不挡别人、又不叠自己 —— 把会阻塞的回调单独放进它自己的互斥组。**
