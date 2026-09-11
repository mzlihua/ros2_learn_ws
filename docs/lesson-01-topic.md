# 第 1 关 · 话题 Topic

> ROS 2 核心基础 · 课程笔记
> 学习日期：2026-09-10 ~ 2026-09-11
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
9. [自测题（附答案）](#9-自测题附答案)

---

## 1. 本关目标

**学会让两个节点互相传数据。**

话题是 ROS 2 里最基础、最常用的通信方式，约 90% 的节点间通信都是话题。这一关搞懂了，后面的服务、动作、参数都只是它的变体。

产出两个可执行节点：

| 文件 | 角色 | 作用 |
|---|---|---|
| `talker.py` | 发布者 Publisher | 每秒往 `/chatter` 发一条消息 |
| `listener.py` | 订阅者 Subscriber | 收到消息就打印出来 |

---

## 2. 核心概念

### 2.1 一句话理解话题

> **ROS 里的节点从不直接调用彼此，而是通过一个叫"话题 (Topic)"的带名字的广播管道传数据。**

```
talker 节点 ──发布──▶ /chatter 话题 ──▶ listener 节点
                                     └──▶ ros2 topic echo（也是订阅者！）
```

### 2.2 三个关键词

| 关键词 | 含义 | 本关取值 |
|---|---|---|
| **话题名** | 管道名字，发布者和订阅者**靠它对暗号** | `chatter`（CLI 里显示为 `/chatter`） |
| **消息类型** | 管道里流的什么格式，**两边必须一致** | `std_msgs/msg/String` |
| **QoS / 队列长度** | 缓冲区大小（第 2 关会细讲） | `10` |

> 💡 话题名写 `chatter`，ROS 会自动补上前导斜杠变成 `/chatter`，这是正常现象。

### 2.3 发布者 vs 订阅者 ⭐ 最重要的一张表

**这是本关最容易搞混的地方。**

|  | **发布者 (Publisher)** | **订阅者 (Subscriber)** |
|---|---|---|
| 创建函数 | `create_publisher` | `create_subscription` |
| 参数个数 | **3 个** | **4 个**（多一个回调函数） |
| 谁主动 | **我主动** `publish()` 往外推 | **我什么都不做**，被动等着 |
| 代码何时执行 | 定时器到点 | 消息到达时，**rclpy 替你调** |
| 需要定时器吗 | ✅ 需要 | ❌ **不需要** |
| 需要造消息吗 | ✅ **造消息是发布者的事** | ❌ 消息是别人喂进来的 |

一句话记忆：

> **发布者 = "我推"**
> **订阅者 = "等着被喂"**

### 2.4 什么是回调 (callback)

**回调 = 你写好一个函数，交给框架，框架在合适的时机替你调用。**

订阅者的回调由 **rclpy 的执行器 (executor)** 在 `rclpy.spin(node)` 循环里调用：

```
rclpy.spin(node) 开始转圈
      ↓
不断问底层：有新消息吗？
      ↓
有 → 取出消息 → 调用你注册的回调，把消息当作参数塞进去
      ↓
没有 → 继续转圈
```

⚠️ **不 spin，回调永远不会被调用。** 这就是 `main()` 里那句 `rclpy.spin(node)` 必须存在的原因。

回调函数**必须接受一个参数**（通常叫 `msg`），这就是 ROS 把消息递给你的方式：

```python
def listener(self, msg):        # ← 这个 msg 由 ROS 填充
    self.get_logger().info(f'接收: {msg.data}')
```

> 对比：定时器回调 `def tick(self)` **没有**参数，因为定时器是"空手"调用的。

---

## 3. 完整代码

### 3.1 `talker.py` —— 发布者

```python
import rclpy
from rclpy.node import Node
from std_msgs.msg import String          # 消息类型：std_msgs 包里的 String


class Talker(Node):

    def __init__(self):
        super().__init__('talker')                    # ① 节点名
        self.count = 0

        # ② 创建发布者：(消息类型, 话题名, 队列长度)
        self.pub = self.create_publisher(String, 'chatter', 10)

        # ③ 定时器：每 1.0 秒调用一次 self.tick
        self.timer = self.create_timer(1.0, self.tick)

    def tick(self):
        self.count += 1

        msg = String()                                 # ④ 造消息
        msg.data = f'第 {self.count} 次心跳'            # ⑤ 填内容
        self.pub.publish(msg)                          # ⑥ 发出去

        self.get_logger().info(f'发布: {msg.data}')


def main(args=None):
    rclpy.init(args=args)          # 启动 rclpy 引擎
    node = Talker()                # 造你的节点
    try:
        rclpy.spin(node)           # 转圈等着，直到 Ctrl+C
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()        # 退出时收拾干净
        rclpy.shutdown()


if __name__ == '__main__':
    main()
```

### 3.2 `listener.py` —— 订阅者

```python
import rclpy
from rclpy.node import Node
from std_msgs.msg import String


class Listener(Node):

    def __init__(self):
        super().__init__('listener')

        # ① 创建订阅者：(消息类型, 话题名, 回调函数, 队列长度)
        #    注意第 3 个参数是回调函数，不是队列长度！
        self.sub = self.create_subscription(String, 'chatter', self.listener, 10)

    # ② 回调：由 ROS 调用，msg 是收到的消息
    def listener(self, msg):
        self.get_logger().info(f'接收: {msg.data}')


def main(args=None):
    rclpy.init(args=args)
    node = Listener()              # ← 唯一和 talker 不同的地方
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
```

**注意 listener 里没有的东西**：没有 `self.timer`、没有 `msg = String()`、没有 `publish()`。
因为**订阅者不主动做任何事**，它只是"注册一个回调然后等着"。

### 3.3 通用模板：每个 ROS 2 Python 节点都长这样 ⭐

```python
# ① 导入
import rclpy
from rclpy.node import Node
from std_msgs.msg import String


# ② 类定义：__init__ 里创建 pub/sub
class MyNode(Node):
    def __init__(self):
        super().__init__('节点名')
        # create_publisher / create_subscription / create_timer ...


# ③ main 模板：一字不改，只换类名
def main(args=None):
    rclpy.init(args=args)
    node = MyNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


# ④ 入口守卫
if __name__ == '__main__':
    main()
```

> 这三块（类 / main / 入口守卫）是**固定套路**，写三个节点之后就成肌肉记忆了。

### 3.4 `setup.py` —— 注册可执行文件

```python
    entry_points={
        'console_scripts': [
            'hello_node = hello_ros.hello_node:main',
            'talker     = hello_ros.talker:main',
            'listener   = hello_ros.listener:main',
            #  ↑终端名        ↑包名.文件名:函数名
        ],
    },
```

⚠️ **写了 `.py` 不等于能用 `ros2 run` 跑** —— 必须在这里"上户口"，否则报 `No executable found`。

---

## 4. API 速查表

```python
# ---------- 创建 ----------
create_publisher(消息类型, '话题名', 队列长度)                    # → 发布者
create_subscription(消息类型, '话题名', 回调函数, 队列长度)        # → 订阅者
create_timer(秒数, 回调函数)                                     # → 定时器

# ---------- 消息 ----------
String()                        # 造一个空的 String 消息
msg.data                        # String 消息里的文本字段

# ---------- 发送 ----------
self.pub.publish(msg)           # 把消息发出去

# ---------- 日志 ----------
self.get_logger().info('文字')   # 打印 INFO 级日志
```

**常用消息类型**（本关用的是第一个）：

| 类型 | 内容 |
|---|---|
| `std_msgs/msg/String` | 一个字符串，字段是 `.data` |
| `std_msgs/msg/Int32` | 一个整数，字段是 `.data` |
| `std_msgs/msg/Bool` | 一个布尔，字段是 `.data` |

查看某个消息类型有哪些字段：

```bash
ros2 interface show std_msgs/msg/String
```

---

## 5. 命令行工具速查

| 命令 | 作用 |
|---|---|
| `ros2 run <包名> <可执行名>` | 运行节点 |
| `ros2 node list` | 列出当前所有节点 |
| `ros2 topic list` | 列出当前所有话题 |
| `ros2 topic echo <话题>` | **打印话题上的消息**（本身是个订阅者） |
| `ros2 topic hz <话题>` | 显示话题的发布频率 |
| `ros2 topic info <话题>` | 显示话题的类型、发布者数、订阅者数 |
| `ros2 interface show <类型>` | 查看消息类型的字段定义 |

---

## 6. 构建与运行流程

### 每次改完代码的固定动作

```bash
cd ~/ros2_learn_ws
colcon build --packages-select hello_ros
source install/setup.bash
```

### 运行（需要多个终端）

```bash
# 终端 A
ros2 run hello_ros talker

# 终端 B
ros2 run hello_ros listener

# 终端 C（观察）
ros2 topic echo /chatter
```

### 环境变量提醒 ⚠️

每个**新开的终端**都需要：

```bash
source /opt/ros/lyrical/setup.bash          # ROS 本体（.bashrc 已自动加载）
source ~/ros2_learn_ws/install/setup.bash   # 你的工作区（需手动 source）
```

忘了第二条 → `Package 'hello_ros' not found`。

---

## 7. 实测现象与结论 ⭐

> 这一节是**复习重点**，都是动手跑出来的结论，不是理论。

### 7.1 话题是多对多的

两个 talker 同时发 `/chatter`，实测：

```
$ ros2 topic info /chatter
Publisher count: 2          ← 两个发布者，ROS 不限制
Subscription count: 0
```

**结论**：话题可以有任意多个发布者、任意多个订阅者，ROS 不做仲裁。

**想分开怎么办？** 用**不同的话题名**（`chatter_a` / `chatter_b`），各写一个 listener 分别订阅。

### 7.2 每个节点是独立进程，内存独立 ⭐

两个 talker 各自维护自己的 `self.count`，**都从 0 开始**，所以日志里编号是重复的：

```
接收: 第 4 次心跳   @ 634.214   ← talker A 的第 4 次
接收: 第 4 次心跳   @ 634.987   ← talker B 的第 4 次（完全不同的另一条消息！）
接收: 第 5 次心跳   @ 635.210
接收: 第 5 次心跳   @ 635.987
```

**关键认知**：

- 两个 talker 是**两个独立的操作系统进程**，各有各的内存空间
- `A.self.count` 和 `B.self.count` 是**两个毫不相干的变量**
- 这是**两条不同的消息**，**不是同一条被收了两次**

时间戳间隔 `0.773s → 0.223s → 0.777s → 0.222s` 交替，两两配对正好约 1 秒 —— 因为实验脚本里两个 talker 启动差了 0.8 秒。

### 7.3 发布/订阅顺序无所谓，但收不到历史消息

**很多人以为必须先启动 talker。错。**

| | |
|---|---|
| **能不能连上** | 顺序**无所谓**，谁先谁后都通（ROS 2 自动发现） |
| **能不能收到某条具体消息** | 后启动的订阅者**收不到启动前的历史消息** |

**实测证据**：talker 先跑了约 3.8 秒才启动 listener，listener 收到的**第一条是"第 4 次心跳"，不是第 1 次** —— 前 3 条因为当时没有订阅者，**丢了**。

> 原因：默认 QoS 是 **volatile**（易失），不缓存历史消息。以后讲 QoS 时会说怎么改成 `transient_local` 来补发历史。

### 7.4 消息路由靠话题名，不靠节点名 ⭐

运行两个同名 talker 后：

```
$ ros2 node list
WARNING: Be aware that there are nodes in the graph that share an exact name,
         which can have unintended side effects.
/talker
/talker
```

**同名节点会有副作用**，因为很多操作靠节点名定位：

- `ros2 param set /talker ...` → 不知道该改哪一个
- `ros2 node info /talker` → 不知道该看哪一个
- 日志筛选、生命周期管理 → 全部含糊

**但是，同名完全不影响话题通信** —— 因为话题靠**话题名**匹配，跟节点叫什么名字毫无关系。

> 📌 **消息路由靠话题名，节点名是另一套独立的东西。**

### 7.5 CLI 工具也是节点

实测 `ros2 topic echo` 对 Subscription count 的影响：

```
① echo 之前      Subscription count: 0
② echo 运行期间  Subscription count: 1    ← 变了！
③ echo 关掉之后  Subscription count: 0    ← 回到 0
```

**结论**：`ros2 topic echo` 本质就是**用命令行临时起了一个订阅者节点**。

**推广**：任何订阅这个话题的进程都算订阅者 —— CLI 工具、rviz、数据录制工具等等。`ros2 topic info` 数的是**所有**订阅者。

### 7.6 话题是匿名的

**订阅者拿不到"这条消息是谁发的"。**

这是设计，不是缺陷：发布者不认识订阅者，订阅者也不知道消息来自哪个发布者。所以 7.2 里两串编号混在一起时，你**无法分辨哪条是哪个 talker 发的**。

---

## 8. 踩坑记录

本关实际踩过的坑，按发生顺序：

| # | 坑 | 报错 / 现象 | 正解 |
|---|---|---|---|
| 1 | 方法名写成 `self.subscription(...)` | `AttributeError: 'Subscription' object has no attribute 'scription'` | 是 **`create_subscription`**，注意 `create_` 前缀 |
| 2 | 忘了写 `main()` 函数 | `AttributeError: module 'hello_ros.listener' has no attribute 'main'` | 每个可执行文件都要有 `main` + 入口守卫 |
| 3 | 把发布者的模型套到订阅者上，想手动调用收消息 | 概念错误 | 订阅是**被动**的，只有回调，没有手动调用 |
| 4 | 类名拼错 `Lisener` | 不影响运行但不规范 | 注意拼写 |
| 5 | 忘了在 `setup.py` 注册 | `No executable found` | `entry_points` 里加一行 |
| 6 | 改了代码没重新 build | 还是旧行为 | 每次改完都要 `colcon build` |
| 7 | 忘了 `source install/setup.bash` | `Package 'hello_ros' not found` | 新终端都要 source |
| 8 | 残留的后台 talker 进程干扰实验 | 日志编号乱跳 | `pkill -f "lib/hello_ros/[t]alker"` |
| 9 | 凭直觉答实验题 | 答错了 | **先跑，再答** ⭐ |

### ⚠️ 关于「错误是会排队的」

**修好一个错，下一个错才会暴露出来。**

比如第 1 条和第 2 条同时存在时，你只会看到第 2 条的报错（`no attribute 'main'`）—— 因为 Python 一上来就找 `main`，找不到就直接死了，`__init__` 里那行 `self.subscription(...)` **根本没机会执行**。

**所以：改完一定要再跑一次**，别以为改了一个就没事了。

---

## 9. 自测题（附答案）

> 复习时**先遮住答案自己答一遍**，答不出来再翻回去对应章节。

### 题 1：话题对发布者数量有限制吗？

<details>
<summary>点开答案</summary>

**没有。** 话题是多对多的，可以有任意多个发布者、任意多个订阅者。实测 `Publisher count: 2` 就是证据。

想分开处理 → 用不同的话题名。

</details>

### 题 2：发布者和订阅者，谁的 `__init__` 里需要 `create_timer`？为什么？

<details>
<summary>点开答案</summary>

**只有发布者需要**（这里是 talker）。

- 发布者是"**我主动推**"—— 靠定时器到点触发 `tick()` 去发消息
- 订阅者是"**等着被喂**"—— 消息一到，ROS 自动调回调，**不需要定时器**

</details>

### 题 3：`create_subscription` 有几个参数？分别是什么？

<details>
<summary>点开答案</summary>

**4 个**：

```python
create_subscription(消息类型, '话题名', 回调函数, 队列长度)
```

最常见的错误是把第 3 个参数（回调函数）漏掉，直接写了队列长度。

</details>

### 题 4：listener 的回调函数是谁调用的？什么时候？

<details>
<summary>点开答案</summary>

**谁**：**rclpy 的执行器 (executor)**，在 `rclpy.spin(node)` 的循环里。

**何时**：有消息到达该话题时。

所以**不 spin，回调永远不会被调用**。

</details>

### 题 5：必须先启动 talker 才能让 listener 收到消息吗？

<details>
<summary>点开答案</summary>

**不需要，顺序无所谓。** ROS 2 会自动发现，谁先谁后都能连上。

**但要拆成两个问题**：

| | |
|---|---|
| 能不能连上 | 顺序无所谓 ✅ |
| 能不能收到某条具体消息 | 后启动的订阅者**收不到启动前的历史消息** ❌ |

原因：默认 QoS 是 volatile，不缓存历史。

</details>

### 题 6：两个 talker 同时发 `/chatter`，listener 会收到几条？会"挑一个"吗？

<details>
<summary>点开答案</summary>

**每秒收到 2 条，不会挑。** 订阅者会收到该话题上**所有**发布者的消息。

而且**无法分辨哪条是谁发的** —— 话题是匿名广播。

</details>

### 题 7：日志里 `第 4 次心跳` 出现了两次，是同一条消息收了两次吗？

<details>
<summary>点开答案</summary>

**不是。** 是两条**不同的**消息。

两个 talker 是**两个独立的操作系统进程**，各有各的内存空间，`self.count` 是**两个毫不相干的变量**，都从 0 开始计数。

所以 A 的第 4 次和 B 的第 4 次，消息内容碰巧一样，但完全是两条独立的消息。

</details>

### 题 8：`ros2 topic echo` 会让 `Subscription count` 变化吗？

<details>
<summary>点开答案</summary>

**会 +1。** `ros2 topic echo` 本身就是一个订阅者节点。

推广：CLI 工具、rviz、录制工具 —— 任何订阅这个话题的进程都算。

</details>

### 题 9：两个节点都叫 `/talker`，会有什么问题？影响话题通信吗？

<details>
<summary>点开答案</summary>

**会有副作用**：`ros2 param set /talker`、`ros2 node info /talker`、日志筛选等操作都会含糊，不知道指向哪一个。ROS 会给出 WARNING。

**但不影响话题通信** —— 话题靠**话题名**匹配，和节点名无关。

> 📌 消息路由靠话题名，节点名是另一套独立的东西。

</details>

### 题 10：写好 `listener.py` 后直接 `ros2 run hello_ros listener` 报 `No executable found`，为什么？

<details>
<summary>点开答案</summary>

因为**没在 `setup.py` 的 `entry_points` 里注册**。

写了 `.py` 不等于能用 `ros2 run` 跑，必须"上户口"：

```python
'listener = hello_ros.listener:main',
```

（另一个可能原因：改了代码没重新 `colcon build`。）

</details>

---

## 附：本关命令速记卡

```bash
# 构建
cd ~/ros2_learn_ws
colcon build --packages-select hello_ros
source install/setup.bash

# 运行
ros2 run hello_ros talker
ros2 run hello_ros listener

# 观察
ros2 node list
ros2 topic list
ros2 topic info /chatter
ros2 topic echo /chatter
ros2 topic hz /chatter

# 清理残留进程
pkill -f "lib/hello_ros/[t]alker"
```

---

**下一关预告 · 服务 Service**

> 话题是**广播**：我喊一嗓子，谁爱听谁听，**我不等回复**。
> 服务是**打电话**：我拨号，对方接，我问一句，他答一句，**我等着**。
>
> 第 1 关踩的"想手动调用订阅者"的坑，在服务里**反而是对的** —— 因为服务就是主动调用别人。
