# 第 5 关 · 动作 Action

> ROS 2 核心基础 · 课程笔记
> 学习日期：2026-09-14 ～ 2026-09-15
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

**让一个"要跑一会儿"的任务，能一边跑一边汇报，还能中途叫停。**

前三关的服务是**一问一答**：客户端发请求，然后干等，服务端算完给响应。拿它做长任务有三个洞：

| 洞 | 具体表现 |
|---|---|
| ① 中间没有进度 | 只能干等，不知道它**在算**还是**卡死了** |
| ② 不能取消 | 想停只能 `pkill` 整个节点 |
| ③ 拿不到中间结果 | 只有最后那一个响应，过程全丢 |

动作把这三个洞都补上：**一次 Goal，过程中播报很多次 Feedback，最后给一次 Result，而且可以取消。**

本关产出：

| 文件 | 作用 |
|---|---|
| `hello_ros/fib_server.py` | 动作服务端：收 `order`，边算斐波那契边报进度，支持取消 |
| `hello_ros/fib_client.py` | 动作客户端：发目标、收进度、拿结果，数到第 3 条进度就叫停 |

**没有自定义消息** —— 用现成的 `example_interfaces/action/Fibonacci`（自定义消息是第 6 关）。

```
# Goal       int32 order          要算几项
# Result     int32[] sequence     完整序列
# Feedback   int32[] sequence     当前算到哪了
```

---

## 2. 核心概念

### 2.1 ⭐⭐ 动作不是新的通信机制：它就是"服务 + 话题"拼出来的

这是本关最大的认知点。**你没学任何新的通信方式。**

一个动作在底层是 **3 个服务 + 2 个话题**：

| 动作里的概念 | 底下的东西 | 是什么 |
|---|---|---|
| 发目标 | `<动作名>/_action/send_goal` | **服务** |
| 取消 | `<动作名>/_action/cancel_goal` | **服务** |
| 取结果 | `<动作名>/_action/get_result` | **服务** |
| 播报进度 | `<动作名>/_action/feedback` | **话题** |
| 状态变化 | `<动作名>/_action/status` | **话题**（rclpy 自己发） |

一句话记：

> **3 个服务**管"一问一答的三件事"（发目标 / 取消 / 取结果）
> **2 个话题**管"持续往外播的两件事"（进度 / 状态）

所以你前四关学的结论**全都还成立**——QoS、话题多对多、回调由执行器调用、服务端有权拒绝……一个都没作废。

### 2.2 三段式：Goal → Feedback → Result

```
客户端                                 服务端
  │  Goal（一次，一问一答）──────────────►│
  │◄──────────── Feedback（很多次，话题）│
  │◄──────────── Feedback                │
  │◄──────────── Feedback                │
  │  Result（一次，一问一答）◄────────────│
```

- **Goal** 和 **Result** 走服务 → 客户端能确切知道"活儿收下了没""结果是什么"
- **Feedback** 走话题 → 服务端想播几次播几次，客户端不订阅也照发不误

### 2.3 ⭐⭐ 同一个 `goal_handle`，服务端"宣布"，客户端"请求"

**两边都有一个叫 `goal_handle` 的东西，名字一模一样，能力完全不同。**

实测（`dir()` 对比）：

```
【服务端有、客户端没有】
  abort  canceled  destroy  execute  executing
  is_active  is_cancel_requested  publish_feedback  request  succeed

【客户端有、服务端没有】
  accepted  cancel_goal  cancel_goal_async  get_result  get_result_async  stamp

【两边都有】
  goal_id  status
```

看动词就明白了：

| | 全是些什么动词 |
|---|---|
| **服务端**的 handle | `succeed` / `canceled` / `publish_feedback` / `abort` —— **我宣布** |
| **客户端**的 handle | `cancel_goal_async` / `get_result_async` / `accepted` —— **我请求** |

> **服务端不说"我要取消"**（它只能声明"我被取消了"）；**客户端不说"我成功了"**（它只能问"成了没"）。
> **两边共通的只有 `goal_id` 和 `status` 两个。**

**判断方法**：想不出该用哪个方法时，先问自己"我现在在服务端还是客户端"，然后拿 `dir()` 查，别猜。

```bash
python3 -c "from rclpy.action.server import ServerGoalHandle as S; from rclpy.action.client import ClientGoalHandle as C; f=lambda K: {n for n in dir(K) if not n.startswith('_')}; print('服务端独有:', sorted(f(S)-f(C))); print('客户端独有:', sorted(f(C)-f(S))); print('共有:', sorted(f(S)&f(C)))"
```

> ⚠️ **那个 `f=...` 不能省。** `dir()` 里混着几十个 `__class__` / `__eq__` 这种双下划线方法，
> 不过滤的话输出会被它们淹掉，真正有用的那十几个名字就看不见了。

### 2.4 客户端的形状：**回调式**，不是"一条直线"

对比第 2 关的服务客户端：

```python
# add_client.py —— 一条直线
future = client.call_async(request)
rclpy.spin_until_future_complete(node, future)   # ← 卡在这干等
response = future.result()
```

服务这么写没问题，因为服务就"一问一答"。**但动作的卖点恰恰是"发出去之后不干等"**——写成直线等于把它降级成服务，白白浪费那 2 个话题。

动作客户端是三个回调串起来的：

```python
send_goal()                        # 发出去，立刻返回
  └─ add_done_callback(goal_response_callback)    # ① 它接不接这个活？
         └─ add_done_callback(get_result_callback) # ② 结果到了
feedback_callback                                  # （独立）每次进度到了
```

### 2.5 ⭐⭐ 执行器那一层：为什么"取消"要换 `MultiThreadedExecutor`

**默认的 `rclpy.spin(node)` 是单线程的。** 一个回调在跑，其他回调只能排队。

```python
def execute_callback(self, goal_handle):
    for i in range(...):
        ...
        time.sleep(1)      # ← 这一秒里，整个节点什么都干不了
```

所以**取消请求会卡在门外**：它到了进程里，但执行器正卡在 `time.sleep` 里，腾不出手去处理 `cancel_goal` 这个服务请求。

**修法（两个都要改）：**

| 改动 | 解决什么 |
|---|---|
| `MultiThreadedExecutor` | 给节点**多个线程** → "睡觉的 `execute_callback`" 和"刚到的取消请求"能**同时**跑 |
| `ReentrantCallbackGroup` | 默认的回调组是**互斥**的（同组内一个在跑，别的排队）。光有线程还不够，得**允许它们并发** |

> **关键理解：`time.sleep(1)` 一个字没改。变的是"它堵住了谁"。**
>
> | | `time.sleep(1)` 堵住谁 | 结果 |
> |---|---|---|
> | 单线程 | 堵住**整个节点唯一那个线程** | 节点瘫痪，取消请求进不来 |
> | 多线程 | 只堵住**持有 `execute_callback` 的那一个线程** | 其他线程照样处理取消请求 |
>
> **长任务本来就要花时间——你不能靠"跑快一点"来回避并发问题。**

---

## 3. 完整代码

### `hello_ros/fib_server.py`

```python
import time

from example_interfaces.action import Fibonacci

import rclpy
from rclpy.action import ActionServer, CancelResponse
from rclpy.callback_groups import ReentrantCallbackGroup
from rclpy.executors import MultiThreadedExecutor
from rclpy.node import Node


class FibServer(Node):
    """斐波那契动作服务端：边算边播报进度，支持中途取消."""

    def __init__(self):
        super().__init__('fib_server')
        self._action_server = ActionServer(
            self,
            Fibonacci,
            'fibonacci',
            execute_callback=self.execute_callback,
            cancel_callback=self.cancel_callback,
            callback_group=ReentrantCallbackGroup())

    def execute_callback(self, goal_handle):
        """算出 order 项斐波那契，每算一项播报一次."""
        self.get_logger().info(f'收到目标：order={goal_handle.request.order}')

        feedback_msg = Fibonacci.Feedback()
        feedback_msg.sequence = [0, 1]

        for i in range(1, goal_handle.request.order):
            if goal_handle.is_cancel_requested:
                self.get_logger().info('目标被取消')
                goal_handle.canceled()
                result = Fibonacci.Result()
                result.sequence = feedback_msg.sequence
                return result

            feedback_msg.sequence.append(
                feedback_msg.sequence[i] + feedback_msg.sequence[i - 1])
            goal_handle.publish_feedback(feedback_msg)
            time.sleep(1)

        goal_handle.succeed()

        result = Fibonacci.Result()
        result.sequence = feedback_msg.sequence

        self.get_logger().info(f'返回结果：{result.sequence}')
        return result

    def cancel_callback(self, goal_handle):
        """服务端说"我让不让你取消"."""
        self.get_logger().info('收到取消请求')
        return CancelResponse.ACCEPT


def main(args=None):
    with rclpy.init(args=args):
        node = FibServer()
        rclpy.spin(node, executor=MultiThreadedExecutor())


if __name__ == '__main__':
    main()
```

### `hello_ros/fib_client.py`

```python
from example_interfaces.action import Fibonacci

import rclpy
from rclpy.action import ActionClient
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node


class FibClient(Node):
    """斐波那契动作客户端：发目标、收进度、拿结果，数到第 3 条进度就叫停."""

    def __init__(self):
        super().__init__('fib_client')
        self._action_client = ActionClient(self, Fibonacci, 'fibonacci')
        self._goal_handle = None          # 我发出去的那个目标
        self._feedback_count = 0

    def send_goal(self, order):
        """发目标。注意：它发完就返回，不等结果."""
        self.get_logger().info('等待动作服务端...')
        self._action_client.wait_for_server()

        goal_msg = Fibonacci.Goal()
        goal_msg.order = order

        self.get_logger().info(f'发送目标：order={order}')
        self._send_goal_future = self._action_client.send_goal_async(
            goal_msg,
            feedback_callback=self.feedback_callback)
        self._send_goal_future.add_done_callback(self.goal_response_callback)

    def goal_response_callback(self, future):
        """服务端说"我接不接这个活"."""
        goal_handle = future.result()
        if not goal_handle.accepted:
            self.get_logger().info('目标被拒绝')
            return

        self.get_logger().info('目标被接受，开始等结果')
        self._goal_handle = goal_handle
        self._get_result_future = goal_handle.get_result_async()
        self._get_result_future.add_done_callback(self.get_result_callback)

    def feedback_callback(self, feedback):
        """每收到一次进度播报就打印一次，数到第 3 条就取消."""
        self._feedback_count += 1
        self.get_logger().info(
            f'收到进度({self._feedback_count})：{feedback.feedback.sequence}')

        if self._feedback_count == 3:
            self.get_logger().info('>>> 够了，我要叫停')
            self._goal_handle.cancel_goal_async()

    def get_result_callback(self, future):
        """结果到了."""
        self.get_logger().info(f'最终结果：{future.result().result.sequence}')
        self.get_logger().info(f'最终状态：{future.result().status}')
        rclpy.shutdown()


def main(args=None):
    try:
        with rclpy.init(args=args):
            node = FibClient()
            node.send_goal(30)
            rclpy.spin(node)
    except (KeyboardInterrupt, ExternalShutdownException):
        pass


if __name__ == '__main__':
    main()
```

### `setup.py` 的改动

`entry_points` 里加两行（照 `add_server` 那行的写法）：

```python
'fib_server = hello_ros.fib_server:main',
'fib_client = hello_ros.fib_client:main',
```

> ⚠️ **改了 `setup.py` 必须重新 build**（`--symlink-install` 免不掉这个——它改的是"装什么"，不是"装的内容"）：
> ```bash
> colcon build --packages-select hello_ros --symlink-install
> ```

---

## 4. API 速查表

```python
# ---------- 服务端 ----------
ActionServer(node, action_type, action_name, *,
             execute_callback=..., cancel_callback=..., callback_group=...)
#            ^^^^  ^^^^^^^^^^^  ^^^^^^^^^^^^   三个位置参数，别跟 Goal/Feedback/Result 对号入座！
#            节点自己  动作类型(类，不加括号)  动作名字(字符串)

Fibonacci.Goal() / .Feedback() / .Result()      # 三个"盒子"，字段都是 .order / .sequence

goal_handle.request.order            # 读客户端发来的 order（信封 → 盒子 → 字段）
goal_handle.publish_feedback(盒子)    # 播报一次进度（走 feedback 话题）
goal_handle.succeed()                # 盖章：成功了。不带参数
goal_handle.canceled()               # 盖章：被取消了。不带参数
goal_handle.is_cancel_requested      # bool，客户端有没有要取消
CancelResponse.ACCEPT / .REJECT      # cancel_callback 的返回值

# ---------- 客户端 ----------
ActionClient(node, action_type, action_name, *)     # 前三个参数跟服务端一样

self._action_client.wait_for_server()                # 阻塞等上线【没有超时】
self._action_client.send_goal_async(goal_msg, feedback_callback=回调)
                                                     # → future，结果是 goal_handle
future.add_done_callback(函数)                        # future 的通用方法
goal_handle.accepted                                 # bool
goal_handle.get_result_async()                       # → future，结果是带 .status/.result 的盒子
goal_handle.cancel_goal_async()                      # 请求取消

# ---------- 执行器（取消能不能生效的关键） ----------
ReentrantCallbackGroup()                             # 允许同组回调并发
MultiThreadedExecutor()                              # 多线程执行器
rclpy.spin(node, executor=MultiThreadedExecutor())

# ---------- 状态码 ----------
#   4 = STATUS_SUCCEEDED   5 = STATUS_CANCELED   6 = STATUS_ABORTED
```

### 两处"信封 → 盒子"（本关最容易错的地方）

```
feedback_callback(feedback)                      ← 参数是信封
    feedback.feedback.sequence                   ← 信封 . 盒子 . 字段

get_result_callback(future)
    future.result().result.sequence              ← 信封 . 盒子 . 字段
    future.result().status                       ← 同一个信封里的另一个字段
```

> 这不是新东西——服务端早就是这个形状了：`goal_handle.request.order`。
> **`goal_handle` 是信封，`.request` 才是盒子。**

---

## 5. 命令行工具速查

```bash
# ---------- 看 ----------
ros2 action list                                  # 列出所有动作
ros2 action list -t                               # 带类型
ros2 action info /fibonacci                       # 谁在提供、谁在用
ros2 action info /fibonacci -t                    # 带类型

ros2 interface show example_interfaces/action/Fibonacci   # 看这个动作的 Goal/Result/Feedback 字段

# ---------- 发目标 ----------
ros2 action send_goal /fibonacci example_interfaces/action/Fibonacci "{order: 8}"
ros2 action send_goal /fibonacci example_interfaces/action/Fibonacci "{order: 8}" --feedback
#                                                                                   ^^^^^^^^^^
#                                                                          边跑边打印 Feedback

# ---------- 手动取消 ----------
# send_goal 跑着的时候按 Ctrl-C（--help 原文：
# "Also applies to goal cancellation if interrupted"）
# ⚠️ 会附带打印一行 `Executor is already spinning` —— 这是 CLI 自己的怪癖，跟你的代码无关

# ---------- 看底层零件（默认藏起来，要加 flag） ----------
ros2 service list --include-hidden-services       # → 3 个 _action/* 服务
ros2 topic list --include-hidden-topics           # → 2 个 _action/* 话题
ros2 node info /fib_server                        # 会把 action 单列成 "Action Servers:" 一节

# ---------- 看 goal_handle 到底有什么（别猜名字） ----------
python3 -c "from rclpy.action.server import ServerGoalHandle as S; print([n for n in dir(S) if not n.startswith('_')])"
python3 -c "from rclpy.action.client import ClientGoalHandle as C; print([n for n in dir(C) if not n.startswith('_')])"
```

---

## 6. 构建与运行流程

### 改完代码的固定动作

```bash
cd ~/ros2_learn_ws
colcon build --packages-select hello_ros --symlink-install    # 只有改了 setup.py / package.xml 才必须
source install/setup.bash

# 服务端
ros2 run hello_ros fib_server

# 客户端（另一个终端）
ros2 run hello_ros fib_client
```

> ⚠️ **改了 `.py` 必须重启节点。** `.py` 走软链，不用 `colcon build`——但**正在跑的那个进程**已经把模块加载进内存了，改磁盘上的文件**不会**让它变。**这是两件事。**

### 验收清单

```bash
# ① 动作在不在
ros2 action list
#   必须看到 /fibonacci

# ② 底层零件对不对（5 个）
ros2 service list --include-hidden-services | grep fibonacci
ros2 topic list --include-hidden-topics | grep fibonacci
#   必须看到 3 服务 + 2 话题

# ③ 跑起来
ros2 run hello_ros fib_server        # 终端 A
ros2 run hello_ros fib_client        # 终端 B

# ④ 测试
colcon test --packages-select hello_ros
colcon test-result --verbose
```

---

## 7. 实测现象与结论 ⭐

### 7.1 ⭐⭐ 动作的 5 个零件（实测）

服务端跑起来之后：

**`ros2 node info /fib_server` 看不到零件** —— 它把动作单独归成一节：

```
Action Servers:
    /fibonacci: example_interfaces/action/Fibonacci
```

**零件默认是藏起来的**，要加 flag 才看得见（`_action` 里的 `_` 开头 → 隐藏，跟第 2 关 `_ros2cli_...` 节点是同一条规矩）：

```bash
$ ros2 service list --include-hidden-services
/fibonacci/_action/cancel_goal        ← 服务
/fibonacci/_action/get_result         ← 服务
/fibonacci/_action/send_goal          ← 服务

$ ros2 topic list --include-hidden-topics
/fibonacci/_action/feedback           ← 话题
/fibonacci/_action/status             ← 话题
```

> **结论：3 服务 + 2 话题，正好就是动作的全部身家。** 2.1 那张表不是比喻，是字面事实。

### 7.2 ⭐⭐ 取消：**0 次 vs 1 次** —— 同一份业务代码，只换了执行器

实验：`order=30`（约 30 秒），跑到第 10 秒按 Ctrl-C。

**A. 单线程（`rclpy.spin(node)`）**

```
收到取消请求: 0 次        ← 一次都没有
播报次数:     12 次        ← 一直播到被强行杀掉
```

**取消请求压根没到过服务端。全程没有一行报错。**

**B. 多线程 + ReentrantCallbackGroup**

```
收到取消请求: 1 次
目标已取消:   1 次
播报次数:     10 次        ← 第 10 拍之后停了
```

**业务代码一个字没改**。`execute_callback` 那几行、`time.sleep(1)`、`cancel_callback` 返回 `ACCEPT` 全都一样。**变的只有 4 行配置。**

> **结论：`完成` 和 `完成` 之外的状态（取消、超时）能不能生效，取决于执行器那一层调度。**
> **"代码写得对"和"代码能生效"是两码事。**

### 7.3 ⭐ 取消请求 2 毫秒就到，响应却等了 1 秒

换了多线程之后，客户端主动取消（`order=30`，数到第 3 条进度就叫停）：

```
客户端
196.863   收到进度：[0, 1, 1]
197.863   收到进度：[0, 1, 1, 2]
198.864   收到进度：[0, 1, 1, 2, 3]
198.864   >>> 够了，我要叫停
199.866   最终结果：array('i', [0, 1, 1, 2, 3])
199.866   最终状态：5

服务端
196.862   收到目标：order=30
198.866   收到取消请求       ← 客户端 198.864 发出，2 毫秒就到了
199.864   目标被取消         ← 但整整 1 秒后才响应
```

**为什么慢 1 秒？** 因为 `is_cancel_requested` 放在**循环顶部**，而循环里有一句 `time.sleep(1)`。请求到了，但代码正睡到一半，得等这一拍睡完、绕回循环顶，才轮到你检查。

**这是设计取舍，不是 bug：**

| 检查点位置 | 响应延迟 |
|---|---|
| 循环顶部（当前做法） | 最坏 1 拍 |
| 把 `sleep` 拆成一堆小段，每段检查一次 | 更灵敏，但代码更碎 |

> 📌 **怎么分辨"没进来"和"进来了但没生效"？**
> 在 `cancel_callback` 里打一行日志。**打出来了 = 请求进来了**（问题在循环）；**没打出来 = 请求没到**（问题在执行器）。
>
> **在两三个关键点各放一条日志，就能把故障范围切出来。** 这是"分段定位"。

### 7.4 ⭐ "差一位"：`order=8` 会算出 **9** 个数

```
$ ros2 action send_goal /fibonacci ... "{order: 8}" --feedback

会打印 7 行 Feedback，最后一次的 sequence 有 9 个数：
[0, 1]                                ← 第 1 条
[0, 1, 1]                             ← 第 2 条
...
[0, 1, 1, 2, 3, 5, 8, 13, 21]         ← 第 7 条，也是 Result
```

因为 `sequence` 一开始就是 `[0, 1]` —— **头两项是白送的**，循环 `range(1, 8)` 只跑 7 次、加 7 项。`2 + 7 = 9`。

**边界**：`order=1` 时循环一次都不跑，直接返回 `[0, 1]`。

### 7.5 ⭐ 取消时的 Result：**空数组**，以及怎么改成不空

原版取消分支返回的是**空盒子**：

```python
return Fibonacci.Result()          # → array('i')  空的
```

客户端看到的是 `最终结果：array('i')`。

**这不是 bug，是设计选择：**

| 选择 | 含义 |
|---|---|
| 返回空（ROS 官方例子的做法） | "这个目标没完成，结果不算数" |
| 返回 `feedback_msg.sequence` | "虽然没跑完，但这是我已经算出来的部分" |

**真实场景里（比如导航），第二种往往才是你要的**——取消了也想知道"它走到哪了"。

改成第二种之后：

```
最终结果：array('i', [0, 1, 1, 2, 3])     ← 正好等于最后一条 Feedback
最终状态：5                                ← 还是 CANCELED
```

**为什么正好等于最后一条 Feedback？** 因为检查点在 `append` **之前**：

```
i=1   检查(False) → append → [0,1,1]     → 播报 → 睡
i=2   检查(False) → append → [0,1,1,2]   → 播报 → 睡
i=3   检查(False) → append → [0,1,1,2,3] → 播报 → 睡
i=4   检查(True!)  ← 此刻 feedback_msg.sequence = [0,1,1,2,3]
```

> **检查点挪一行，结果就不一样。** 把 `if` 挪到 `append` 之后，结果会多一项。**位置决定语义。**

### 7.6 ⭐ 服务端/客户端 `goal_handle` 能力对照（`dir()` 实测）

见 2.3。**核心一句话：服务端"宣布"，客户端"请求"。**

### 7.7 ⭐ `ros2 run` 每次都在重新读磁盘

"同一个命令跑第二次就好了"的真相：

```
install/hello_ros/lib/hello_ros/fib_client      ← 生成的启动壳
        ↓ 加载
build/hello_ros/hello_ros/fib_client.py         ← 指向 src/ 的【软链】
        ↓
src/hello_ros/hello_ros/fib_client.py           ← 你改的那个文件
```

**"跑第二次"和"跑第一次"根本不是同一个程序**——中间你把代码改了。**不是"重试"灵了，是你已经改过了。**

（前提：build 时加了 `--symlink-install`。详见第 4 关 §7.1。）

### 7.8 ⭐ `wait_for_server()` **没有超时**

```python
self._action_client.wait_for_server()      # 死等，服务端不在就永远停在这
```

对比第 2 关 `add_client.py` 里用的：

```python
client.wait_for_service(timeout_sec=1.0)   # 带超时，找不到就干净退出
```

> **日志停在 `等待动作服务端...` 不动 = 服务端不在。** 这时候"重试"是解决不了的，得先把服务端起起来。
> 判断方法：另开终端 `ros2 node list`，看有没有 `/fib_server`。

---

## 8. 踩坑记录

### ❌ 坑 1：把 `ActionServer` 的三个位置参数跟 Goal/Feedback/Result 对号入座

```python
ActionServer(
    Fibonacci.Goal(),        # ✗ 我是节点吗？
    Fibonacci.Feedback(),    # ✗
    Fibonacci.Result(),      # ✗
    execute_callback=...)
```

连写三版才改对。**签名的参数名本身就是说明书：**

```python
ActionServer(node, action_type, action_name, *, ...)
#            ^^^^  ^^^^^^^^^^^  ^^^^^^^^^^^^
#            节点自己  动作类型(类，不加括号)  动作名字(字符串)
```

报错其实写得很清楚：

```
File ".../rclpy/action/server.py", line 336, in __init__
    callback_group = node.default_callback_group
AttributeError: type object 'Fibonacci' has no attribute 'default_callback_group'
```

**rclpy 内部把它当 `node` 用了**——报错本身就在告诉你第 1 格该填什么。

### ❌ 坑 2：`.feedback` 串门到 `get_result_callback`

```python
result = future.result().feedback()      # ✗
```

```
AttributeError: 'Fibonacci_GetResult_Response' object has no attribute 'feedback'
```

**报错把信封的真名报出来了。** 拿它去查：

```bash
python3 -c "from example_interfaces.action._fibonacci import Fibonacci_GetResult_Response as R; print([n for n in dir(R) if not n.startswith('_')])"
# → ['SLOT_TYPES', 'get_fields_and_field_types', 'result', 'status']
```

**真正的数据字段就俩：`result` 和 `status`**（`SLOT_TYPES` 和 `get_fields_and_field_types` 是每个 ROS 消息都有的样板）。
**没有 `feedback`。** 正确的是 `future.result().result`。

### ❌ 坑 3：`goal_handle.cancel_call` —— 名字是**猜**的

正确的是 `is_cancel_requested`。**猜错就是一个 `AttributeError`，而查它只要一条 `dir()` 命令。**

### ❌ 坑 4：把提示文字当成代码内容

```python
goal_handle.publish_feedback('我是被取消的')      # ✗
```

两个错叠在一起：

1. **`publish_feedback` 收的是盒子**（`Fibonacci.Feedback()`），不是字符串
2. **"宣告被取消"根本不是"发消息"** —— `goal_handle` 上有两个"盖章"动作，都不带参数：

| | 干什么 | 走哪条通道 |
|---|---|---|
| `publish_feedback(盒子)` | **播报进度**（发数字给客户端看） | `_action/feedback` 话题 |
| `canceled()` | **盖章"我被取消了"** | `_action/status` 话题，rclpy 自己发 |
| `succeed()` | **盖章"我成功了"** | 同上 |

### ❌ 坑 5：`goal_handle.succeed()` / `canceled()` 写在**客户端**

```python
# 5-2 版：在客户端的 feedback_callback 里
if goal_handle.succeed():     # ✗ 客户端没这个方法；而且 succeed() 返回 None
```

犯了**两次**（`succeed()` 一次、`canceled()` 一次）。**同一个 `goal_handle`，服务端"宣布"、客户端"请求"**（见 2.3）。

### ❌ 坑 6：`_feedback_count` 忘了 `+= 1` —— **静默 bug**

```python
self._feedback_count = 0          # __init__ 里
...
if self._feedback_count == 3:     # 但从来没加过 → 永远是 0 → 永远不成立
```

**不报错、循环照跑、取消永远不发生。** 你只会看到"客户端跑完了"，然后以为是自己哪里配错了。

> **静默 bug 唯一的克星：把中间量打出来看。**
> ```python
> self.get_logger().info(f'收到进度({self._feedback_count})：{...}')
> ```
> **把计数打进日志，"它到底加没加"就不用猜了。**

### ❌ 坑 7：把 `time.sleep(1)` 注释掉了

```python
# time.sleep(1)          # ✗
```

`flake8` 立刻抓到：`F401 'time' imported but unused`。

**这次 lint 是真的在帮你**——前面几次它只会报格式，这次它说"`time` 没人用了"，等于在问"你是不是把 sleep 弄没了"。

没有 `sleep`，`order=30` 会在**微秒级**跑完，你根本来不及按 Ctrl-C。

### ⚠️ 坑 8：报错的行里，有的跟你无关

按 Ctrl-C 取消时，`ros2 action send_goal` 会多打一行：

```
Canceling goal...
Executor is already spinning
```

**这是 CLI 自己的怪癖**（rclpy 的一个已知问题），**不影响取消**（实测服务端 2 毫秒就收到了请求）。

> **别看到报错就以为是自己错了。** 第 4 关的"VSCode 假红线"是同一种情况。

### ⚠️ 坑 9：贴半截日志

本关犯了 3 次：

1. 「还是不对」—— **没贴报错**，而答案就在报错里
2. 「为什么重试一次就好了」—— 其实**根本没卡**：`609.203 → 616.460` = **7.257 秒**，正好一次完整运行。只是先贴了第一行
3. 加练那题 —— 只贴了服务端，**最关键的客户端两行没贴**

> **贴日志前先扫两眼：有没有 `Traceback`？有没有走到最后一行？**

---

## 9. 自测题

### 9.1 课堂已覆盖（附答案）

<details>
<summary><b>题 1：动作在底层是什么？数一数有几个服务、几个话题，分别对应动作的哪一步。</b></summary>

**3 个服务 + 2 个话题。**

| 动作里的概念 | 底下的东西 | 是什么 |
|---|---|---|
| 发目标 | `<动作名>/_action/send_goal` | 服务 |
| 取消 | `<动作名>/_action/cancel_goal` | 服务 |
| 取结果 | `<动作名>/_action/get_result` | 服务 |
| 播报进度 | `<动作名>/_action/feedback` | 话题 |
| 状态变化 | `<动作名>/_action/status` | 话题（rclpy 自己发） |

所以**动作不是新的通信机制**，是"服务 + 话题"拼出来的一个包装。这也说明为什么它既有"一问一答"（Goal/Result），又有"持续播报"（Feedback）。

验证命令（默认藏起来，要加 flag）：
```bash
ros2 service list --include-hidden-services
ros2 topic list --include-hidden-topics
```
</details>

<details>
<summary><b>题 2：服务端的 <code>goal_handle</code> 和客户端的 <code>goal_handle</code>，有什么区别？</b></summary>

**名字一样，能力完全不同。**

- **服务端**的 handle 用来**宣布**：`succeed()` / `canceled()` / `publish_feedback()` / `abort()`
- **客户端**的 handle 用来**请求**：`cancel_goal_async()` / `get_result_async()` / `accepted`

**两边共通的只有 `goal_id` 和 `status`。**

所以服务端**不能**说"我要取消"（它只能声明"我被取消了"），客户端**不能**说"我成功了"（它只能问"成了没"）。

记不住就拿 `dir()` 查，别猜。
</details>

<details>
<summary><b>题 3：为什么取消功能"写对了"却不生效？改哪两处？</b></summary>

因为默认的 `rclpy.spin(node)` 是**单线程**执行器。`execute_callback` 里的 `time.sleep(1)` 把唯一那个线程堵死了，**取消请求卡在门外进不来**——`cancel_callback` 根本不会被调用，`is_cancel_requested` 永远是 `False`。全程不报错。

改两处：

```python
callback_group=ReentrantCallbackGroup()              # ① 允许同组回调并发
rclpy.spin(node, executor=MultiThreadedExecutor())   # ② 多线程执行器
```

实测对比：单线程 `收到取消请求` **0 次**；多线程 **1 次，2 毫秒响应**。

**关键：`time.sleep(1)` 一个字没改。变的是"它堵住了谁"。**
</details>

<details>
<summary><b>题 4：取消请求到了服务端之后，为什么还要等 1 秒才生效？</b></summary>

因为 `is_cancel_requested` 放在**循环顶部**，而循环里有一句 `time.sleep(1)`。请求到了，但代码正睡到一半，得等这一拍睡完、绕回循环顶，才轮到检查。

**这是设计取舍，不是 bug。** 想更灵敏就得把 `sleep` 拆成一堆小段，每段检查一次。

**怎么分辨"没进来"和"进来了但没生效"？** 在 `cancel_callback` 里打日志——打出来了是前者，没打出来是后者。
</details>

<details>
<summary><b>题 5：<code>order=8</code> 会打印几行 Feedback？最后一次的 sequence 有几个数？</b></summary>

**7 行 Feedback，最后一次 9 个数。**

因为 `sequence` 一开始就是 `[0, 1]`——**头两项是白送的**，循环 `range(1, 8)` 只跑 7 次、加 7 项。`2 + 7 = 9`。

边界：`order=1` 时循环一次都不跑，直接返回 `[0, 1]`。
</details>

<details>
<summary><b>题 6：为什么服务端和客户端都要写"两层"（<code>.feedback.sequence</code> / <code>.result.sequence</code>）？</b></summary>

因为回调拿到的参数是**信封**，不是数据本身。

```
feedback_callback(feedback)          ← 信封（FeedbackMessage）
    .goal_id                         ← 这是哪个目标的
    .feedback                        ← 真正的 Feedback 盒子
        .sequence                    ← 你要的数

get_result_callback(future)
    future.result()                  ← 信封（GetResult_Response）
        .status                      ← 成功/取消/失败
        .result                      ← 真正的 Result 盒子
            .sequence
```

**这不是动作特有的**——服务端早就是这个形状：`goal_handle.request.order`（`goal_handle` 是信封，`.request` 才是盒子）。
</details>

<details>
<summary><b>题 7：被取消时返回的 Result 里是什么？为什么会这样？</b></summary>

**空数组 `array('i')`**，因为取消分支写的是 `return Fibonacci.Result()`——**造了一个空盒子**，从没往里塞过 `sequence`。

对比成功那条路：
```python
result = Fibonacci.Result()
result.sequence = feedback_msg.sequence      # ← 这里塞了
return result
```

**这不是 bug，是设计选择**：返回空 = "目标没完成，结果不算数"；返回已算出的部分 = "这是我已经算出来的"。

真实场景（比如导航）通常要第二种。改成第二种后实测得到 `array('i', [0, 1, 1, 2, 3])`——**正好等于最后一条 Feedback**，因为检查点在 `append` 之前。
</details>

<details>
<summary><b>题 8：<code>wait_for_server()</code> 和 <code>wait_for_service(timeout_sec=1.0)</code> 有什么区别？</b></summary>

**前者没有超时，后者有。**

```python
self._action_client.wait_for_server()          # 死等，服务端不在就永远停在这
client.wait_for_service(timeout_sec=1.0)       # 1 秒等不到就返回 False，可以干净退出
```

所以**日志停在 `等待动作服务端...` 不动 = 服务端不在**。这时候"重试"解决不了问题。
判断方法：另开终端 `ros2 node list`，看有没有 `/fib_server`。
</details>

### 9.2 留给下次的思考题（无答案）

1. **`cancel_callback` 返回 `CancelResponse.REJECT` 会怎样？** 客户端那边能看出区别吗？写个实验验证一下。
2. **如果两个客户端同时发目标**（`order=10` 和 `order=20`），现在的服务端会怎么表现？**为什么**？（提示：想想 `ReentrantCallbackGroup` 到底允许了什么，以及 `feedback_msg` 是哪个函数里的局部变量。）
3. **`MultiThreadedExecutor` 加了线程，那"共享变量"会不会出问题？** 现在这份代码里，两个目标同时跑会互相踩到谁吗？
4. **`goal_handle.status`（两边都有那个）和 `future.result().status` 是同一个东西吗？** 分别是什么时候的值？
5. **客户端的 `cancel_goal_async()` 返回的是 future**，它的结果里有什么？（`dir()` 一下 `CancelGoalServiceResponse`。）现在代码里没接它，**不接会有什么后果？**

---

## 10. 附：跨关待办

> 这是第 5 关结束时，老师给的**跨关观察**——不是"动作"这一关的问题，是**跟了四关的老毛病**。
> 换一关它们照样在，所以写在这里，第 6 关照这三个盯着。

### ① 贴半截输出 / 不读输出（最顽固）

本关犯了 3 次（见坑 9）。**贴日志前先扫两眼：有没有 `Traceback`？有没有走到最后一行？**

### ② 名字靠猜，不靠查

本关新出现（坑 3）。**代价很明确：猜错就是一个 `AttributeError`，而查它只要一条 `dir()` 命令。**

### ③ 盒子和内容

四关的老账：

| 关卡 | 错误写法 | 正确 |
|---|---|---|
| 第 2 关 | `return response.sum` | `return response` |
| 第 3 关 | `get_parameter('x')`（忘 `.value`） | `get_parameter('x').value` |
| 第 5 关 | `publish_feedback(feedback_msg.sequence)` | `publish_feedback(feedback_msg)` |

**但本关有进步**：`feedback.feedback.sequence` 是自己想出来的。说明"信封里掏盒子"是**会的**，只是偶尔手滑。

> **规则**：每次传参前问一句——**"这个函数要盒子，还是要盒子里的东西？"**

---

## 附：本关命令速记卡

```bash
# ---------- 看 ----------
ros2 action list                                   # 有哪些动作
ros2 action info /fibonacci                        # 谁提供、谁在用
ros2 interface show example_interfaces/action/Fibonacci    # 字段长什么样
ros2 service list --include-hidden-services        # 底层 3 个服务
ros2 topic list --include-hidden-topics            # 底层 2 个话题

# ---------- 发目标 ----------
ros2 action send_goal /fibonacci example_interfaces/action/Fibonacci "{order: 8}" --feedback
#                                                          Ctrl-C = 取消（附带 "Executor is already spinning"，忽略）

# ---------- 跑自己的 ----------
ros2 run hello_ros fib_server      # 终端 A
ros2 run hello_ros fib_client      # 终端 B

# ---------- 排查 ----------
ros2 node list                     # /fib_server 在不在（wait_for_server 卡住时先看这个）
ros2 node info /fib_server         # Action Servers 那一节

# ---------- 别猜名字 ----------
python3 -c "from rclpy.action.server import ServerGoalHandle as S; print([n for n in dir(S) if not n.startswith('_')])"
python3 -c "from rclpy.action.client import ClientGoalHandle as C; print([n for n in dir(C) if not n.startswith('_')])"
```
