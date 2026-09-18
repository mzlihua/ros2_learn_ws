# 第 8 关 · QoS 策略

> 这一关结的是**第 1 关**欠下的账 —— 那句"后启动的订阅者收不到历史消息"，
> 真正的原因就在这里。
>
> 一句话：**QoS 是发布者和订阅者各自声明的一套质量要求，DDS 在中间配对。**
> **配不上，就一条消息都不过 —— 而 `ros2 topic info` 照样显示 `1 / 1`。**

---

## 目录

- [1. 本关目标](#1-本关目标)
- [2. 核心概念](#2-核心概念)
- [3. 完整代码](#3-完整代码)
- [4. API 速查表](#4-api-速查表)
- [5. 命令行工具速查](#5-命令行工具速查)
- [6. 构建与运行流程](#6-构建与运行流程)
- [7. 实测现象与结论 ⭐](#7-实测现象与结论-)
- [8. 踩坑记录](#8-踩坑记录)
- [9. 自测题](#9-自测题)
- [10. 附：跨关待办](#10-附跨关待办)
- [附：本关命令速记卡](#附本关命令速记卡)

---

## 1. 本关目标

前七关你写过的每一个 `create_publisher` / `create_subscription`，第三个参数都长得像这样：

```python
self.pub = self.create_publisher(String, 'chatter', 10)     # 这个 10 是什么？
```

这个 `10` 就是 **QoS（Quality of Service，服务质量）** 的一个参数。
你一直在用它，只是没问过它是什么。

本关要拿到四样东西：

| # | 目标 | 对应实验 |
|:-:|---|---|
| 1 | 说清 QoS 的**配对规则**，并能**预测**任意两个端点的连接结果 | 题 8-1 四格矩阵 |
| 2 | 认出不兼容时的**症状**，知道去哪儿看病因 | 题 8-1（WARN + `topic info -v`）|
| 3 | 解释**"历史消息"到底是什么、住在哪** | 题 8-2 / 8-3 / 8-4 |
| 4 | 知道三个常用旋钮的**默认值** | §2.6 |

---

## 2. 核心概念

### 2.1 QoS 是"两边各说各的"，然后配对

话题名和消息类型，两边**必须写成一样**，写错就连不上，而且报错很明确。

**QoS 不一样，两边可以不一样 —— 但必须"配得上"。**

打个比方：

- 话题名 = **电话号码**（必须拨对）
- 消息类型 = **语言**（必须说同一种）
- QoS = **通话质量要求**（"我必须听得清清楚楚" vs "能听见个大概就行"）

两边各自报出自己那一侧的要求，DDS 在中间**配对**。配得上才建连接。

> **这是 ROS 2 换 DDS 换来的新东西。** ROS 1 没有 QoS —— 一律走 TCP、一律可靠。
> 好处是简单，代价是相机那种每秒几百兆的数据也得走重传，扛不住。

### 2.2 三个旋钮

本关只碰这三个（`QoSProfile` 还有 lifespan / deadline / liveliness，先不管）：

| 策略 | 取值 | 含义 |
|---|---|---|
| **Reliability** 可靠性 | `RELIABLE` | 保证送达，丢了会重传 |
| | `BEST_EFFORT` | 尽力而为，丢了就丢 |
| **Durability** 持久性 | `VOLATILE` | 只发"我连上之后"产生的消息 |
| | `TRANSIENT_LOCAL` | 还留着最近 N 条，晚来的订阅者**补发** |
| **History / Depth** 历史深度 | `KEEP_LAST(n)` | 只留最近 n 条 |
| | `KEEP_ALL` | 全留 |

直觉对照：

- `BEST_EFFORT` 是给**高频传感器**用的 —— 相机第 100 帧丢了无所谓，第 101 帧马上就到，重传反而是负担。
- `TRANSIENT_LOCAL` 是给**低频状态**用的 —— 比如"地图"、"机器人当前模式"，发一次就不动了，新来的订阅者得能拿到。

### 2.3 ⭐ 唯一的兼容规则

> **发布者能"提供"的 ≥ 订阅者"要求"的。**

**是 ≥，不是 =。** 所以两边写不一样，照样能通。

- `RELIABLE` 发布者 + `BEST_EFFORT` 订阅者 → ✅ 提供得多，要求得少，**配得上**
- `BEST_EFFORT` 发布者 + `RELIABLE` 订阅者 → ❌ 提供得少，要求得多，**配不上**

耐久性同理：`VOLATILE` 发布者 + `TRANSIENT_LOCAL` 订阅者 → ❌ 也连不上（实测见 §7.2）。

**一句话记法：订阅者不能"要求"得比发布者能"给"的更多。**

### 2.4 ⭐ 不兼容长什么样

这是本关最容易骗人的地方，因为它**同时有三副面孔**：

| 你会看到 | 真相 |
|---|---|
| ❌ **一条消息都不来** | 真的没连上 |
| ⚠️ **两边各打一条 WARN** | 症状有提示，但只在发现的那一刻打**一次** |
| 📊 **`ros2 topic info` 显示 `1 / 1`** | ⚠️ **这是假象** —— 它数的是"**发现到**了"，不是"**配得上**" |

WARN 的原文（两边说的是同一件事，主语和方向相反）：

```text
# 订阅者那一侧看到的
[WARN] [xxx] [qos_sub]: New publisher discovered on topic '/l8_qos', offering
incompatible QoS. No messages will be received from it. Last incompatible policy: RELIABILITY

# 发布者那一侧看到的
[WARN] [xxx] [_ros2cli_xxx]: New subscription discovered on topic '/l8_qos', requesting
incompatible QoS. No messages will be sent to it. Last incompatible policy: RELIABILITY
```

**⭐ 最后半句直接点名了是哪个策略不兼容 —— 不用猜。**

> 💡 `offering`（发布者"提供"）对 `requesting`（订阅者"要求"）——
> 这两个词就是 §2.3 那条规则的原文。报错里已经写着规则了。

**诊断动作**：`ros2 topic info -v <话题>`，把两边的 QoS 摊开对照。

### 2.5 ⭐ "历史"是个抽屉，抽屉在**发布者**那边

`TRANSIENT_LOCAL` 的全部机制可以归结成一句话：

> **发布者在自己进程的内存里开了一个抽屉，把最近 `depth` 条消息留着。
> 晚来的订阅者一连上，发布者就把抽屉里的东西补发给他。**

三条例必须记死：

1. **抽屉在发布者手里**，不在订阅者手里。（§7.4 那个判据实验证明的）
2. **抽屉的容量由发布者的 `depth` 决定**，不是订阅者的。
3. **抽屉是内存，不是磁盘。发布者进程一死，抽屉跟着没。**

订阅者的 `--qos-depth` / `depth` 管的是**另一件事**：它自己**接收队列**能接住几条。
两个数字都会限制实际到手的条数，**取小的那个** —— 但**来源**只有发布者一个。

### 2.6 默认值表（本关必须记住的几个）

| 场景 | Reliability | Durability | History |
|---|---|---|---|
| `create_publisher(类型, '话题', 10)` | **`RELIABLE`** | `VOLATILE` | `KEEP_LAST(10)` |
| `QoSProfile(depth=10)` | **`RELIABLE`** | `VOLATILE` | `KEEP_LAST(10)` |
| `ros2 topic echo`（CLI，默认 `sensor_data`） | **`BEST_EFFORT`** | `VOLATILE` | `KEEP_LAST(5)` |

> ⚠️ **第二行和第三行不一样** —— 这是本关最容易踩的坑之一。
> `ros2 topic echo` 默认是 `BEST_EFFORT`，**它连不上 `RELIABLE` 发布者吗？连得上**（提供 ≥ 要求），
> 但它**拿不到 `TRANSIENT_LOCAL` 的历史**（见 §7.3）。

**默认值的现实含义**：

- 你写的所有节点都是 `RELIABLE` + `VOLATILE` + `KEEP_LAST(10)`
- **没有抽屉** → 后启动的订阅者听不到任何历史 → **这就是第 1 关那条旧账**

---

## 3. 完整代码

### `src/hello_ros/setup.py` 的改动

```python
        'console_scripts': [
            # ...
            'group_demo = hello_ros.group_demo:main',

            'qos_talker = hello_ros.qos_talker:main',
        ],
```

### `src/hello_ros/hello_ros/qos_talker.py`

```python
import rclpy
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy
from std_msgs.msg import String


class QosTalker(Node):
    """发 5 条就闭嘴但节点不退：让晚来的订阅者有机会看见"历史"."""

    def __init__(self):
        super().__init__('qos_talker')

        self.declare_parameter('depth', 3)
        depth = self.get_parameter('depth').value

        qos = QoSProfile(
            history=HistoryPolicy.KEEP_LAST,
            depth=depth,
            reliability=ReliabilityPolicy.RELIABLE,
            durability=DurabilityPolicy.TRANSIENT_LOCAL,
        )

        self.count = 0
        self.pub = self.create_publisher(String, 'qos_hist', qos)
        self.timer = self.create_timer(0.5, self.tick)

    def tick(self):
        """发一条；发满 5 条就收手."""
        if self.count == 5:
            return
        self.count += 1
        msg = String()
        msg.data = f'第{self.count}条'
        self.pub.publish(msg)
        self.get_logger().info(f'发了 {msg.data}')


def main(args=None):
    rclpy.init(args=args)
    node = QosTalker()
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

### 三个设计点

**① 为什么"发满 5 条不退出"，而不是直接 `timer.cancel()` 再 `return`？**

退出了抽屉就没了（§2.5 第 3 条）。**"停发"和"退出"必须分开**，否则实验做不成。

**② 为什么 `depth` 做成参数？**

同一份代码，只要换一个数字，就能演示"抽屉容量"的边界（§7.3）。
**一个变量一个行为的对照**，比读十遍文字管用。

**③ 为什么 QoS 显式写在代码里，而不是用默认值？**

`create_publisher(String, 'qos_hist', 10)` 也能跑 —— 但那是 `VOLATILE`，**没有抽屉**，
这个实验就什么也演示不了。**QoS 是这个实验的主体，不是背景。**

---

## 4. API 速查表

```python
# ---------- 构造一个 QoSProfile ----------
from rclpy.qos import QoSProfile, HistoryPolicy, ReliabilityPolicy, DurabilityPolicy

qos = QoSProfile(
    history=HistoryPolicy.KEEP_LAST,          # KEEP_LAST / KEEP_ALL
    depth=10,                                  # KEEP_LAST 时必须给
    reliability=ReliabilityPolicy.RELIABLE,    # RELIABLE / BEST_EFFORT
    durability=DurabilityPolicy.TRANSIENT_LOCAL,   # TRANSIENT_LOCAL / VOLATILE
)

# ---------- 用它 ----------
self.create_publisher(String, 'topic', qos)       # 第三个参数收 QoSProfile 对象
self.create_subscription(String, 'topic', cb, qos)

# ---------- 预设档（懒得手写时）----------
from rclpy.qos import (
    qos_profile_sensor_data,          # BEST_EFFORT + KEEP_LAST(5) + VOLATILE  ← 相机/雷达
    qos_profile_services_default,     # RELIABLE  + KEEP_LAST(10) + VOLATILE
    qos_profile_system_default,       # 全 SYSTEM_DEFAULT，交给 RMW 决定
)
```

> ⚠️ **枚举必须从 `rclpy.qos` import 进来**。
> 它们**不是**节点的属性 —— `self.HistoryPolicy` 会 `AttributeError`（见 §8 坑 2）。

---

## 5. 命令行工具速查

```bash
# ---------- 看一个话题的 QoS ----------
ros2 topic info -v /qos_hist
#   ★ 这是本关的主力诊断命令。不带 -v 只看得到个数，看不到 QoS。

# ---------- 发 / 收 时指定 QoS ----------
ros2 topic pub  --qos-reliability best_effort -r 1 /t std_msgs/msg/String "{data: hi}"
ros2 topic echo --qos-reliability reliable --qos-durability transient_local /t std_msgs/msg/String

# 可选项：--qos-profile / --qos-reliability / --qos-durability / --qos-depth / --qos-history

# ---------- 一个能自动收场的发布者（-t = 发几次就退）----------
ros2 topic pub --qos-reliability best_effort -t 6 -r 1 -w 0 /t std_msgs/msg/String "{data: hi}"
#                                                    ↑     ↑
#                                      发 6 次就退出   不等订阅者（默认会自动等 1 个）
```

### 🔴 `ros2 topic echo` 的默认档是 `sensor_data`

```text
--qos-profile {..., sensor_data, ...}   Quality of service preset profile to subscribe with
                                        (default: sensor_data)
```

翻译过来就是：**`BEST_EFFORT` + `KEEP_LAST(5)` + `VOLATILE`**。

**踩法**：想收 `TRANSIENT_LOCAL` 的历史，只加 `--qos-durability transient_local` ——
**收不到**。因为你还带着 `BEST_EFFORT`，而历史补发要靠可靠传输（§7.3）。

**正确写法**：两个都显式给。

```bash
ros2 topic echo --qos-reliability reliable --qos-durability transient_local /qos_hist std_msgs/msg/String
```

---

## 6. 构建与运行流程

### 构建

```bash
cd ~/ros2_learn_ws
colcon build --packages-select hello_ros --symlink-install
source install/setup.bash
```

> ⚠️ **这次的 `.py` 是新文件，还改了 `setup.py`** —— 两件事都要 build。
> 改的是"**装什么**"的登记表，`--symlink-install` 免不掉（第 6 关三张表，README 边界 1）。

### 验收清单

```bash
# ① 登记成功了吗（不依赖任何节点）
ros2 pkg executables hello_ros
#    期望：14 个名字里出现 qos_talker

# ② 抽屉容量 = 2（终端 A）
ros2 run hello_ros qos_talker --ros-args -p depth:=2
#    期望：发了 第1条 …… 发了 第5条，然后停住（节点不退）

# ③ 晚来的订阅者能拿到什么（终端 B，发布者还活着）
ros2 topic echo --qos-reliability reliable --qos-durability transient_local --qos-depth 5 \
  /qos_hist std_msgs/msg/String
#    期望：只有 2 条 —— 第4条、第5条

# ④ 收工：终端 A Ctrl+C，然后确认干净
ros2 topic info /qos_hist
#    期望：Unknown topic '/qos_hist'    （注意不是 "Publisher count: 0"）
```

> ⚠️ **验收前必须先确认 `Unknown topic`** ——
> 有残留发布者时，你测的根本不是你以为的那个东西（§8 坑 3）。

---

## 7. 实测现象与结论 ⭐

### 7.1 ⭐⭐ 兼容性矩阵：四格只有一格不通

发布者一个、订阅者一个，只改 `reliability`，其余全默认。

| # | 发布者 | 订阅者 | 结果 | 订阅者退出码 | WARN |
|:-:|---|---|:-:|:-:|---|
| ① | `reliable` | `reliable` | ✅ 通 | `0` | 无 |
| ② | `best_effort` | `reliable` | ❌ **不通** | `124` | **两边各 1 条** |
| ③ | `best_effort` | `best_effort` | ✅ 通 | `0` | 无 |
| ④ | `reliable` | `best_effort` | ✅ 通 | `0` | 无 |

**只有 ② 不通，而 ② 正是唯一"订阅者要求 > 发布者提供"的一格。**

④ 是最反直觉的一格：**发布者可靠、订阅者尽力，反而通。** 因为订阅者"不要求保证"，
发布者给得起 —— **提供 ≥ 要求**。

> 退出码也是个可编程的信号：`0` = 收到了，`124` = 超时（`timeout` 命令给的，代表没收到）。

### 7.2 耐久性也是同一个方向

| 发布者 `durability` | 订阅者 `durability` | 结果 |
|---|---|:-:|
| `volatile` | `transient_local` | ❌ 不通 |

订阅者要"历史"，发布者**根本没存**（`VOLATILE` = 没有抽屉）—— 提供不了，配不上。
**实测：发布者每秒发一条，订阅者 4 秒内一条都没过**（不是"没有历史"，是**整个连接都没建起来**）。

### 7.3 ⭐⭐ 抽屉容量表：`depth` 到底管什么

发布者用 `TRANSIENT_LOCAL` 发满 **5 条**（第1～第5）后停发、**但进程活着**，
然后起一个**晚来**的订阅者，只改订阅者的 `depth`：

| 发布者 `depth` | 订阅者 `depth` | 实际收到 | 是哪几条 |
|:-:|:-:|:-:|---|
| 5 | 10 | **5** | 第1、2、3、4、5 |
| 5 | 5 | **5** | 第1、2、3、4、5 |
| 5 | 2 | **2** | 第4、第5 |
| 5 | 1 | **1** | **第5条** |
| **2** | 10 | **2** | 第4、第5 |
| **2** | 5 | **2** | 第4、第5 |

三条结论：

1. **到手 = 两个数字里小的那个。**
2. **挤掉的是最老的。** 订阅者只要 1 条时，拿到的是**最新的第5条**，不是第1条。
3. ⭐ **抽屉在发布者那儿。** 看最后两行 —— 订阅者张着手要 5 条、要 10 条，
   **只拿到 2 条**。那 3 条不是它"不想要"，是**发布者手上根本没有**。

> ⚠️ **别用"两边取小的那个"来解释抽屉的位置** —— 那句话结论对，但**说反了原因**。
> 到手少，是因为**来源少**，不是"订阅者只要了这么多"。

### 7.4 ⭐⭐ 判据实验：怎么才知道抽屉在谁那儿

**同一个观察，两个说法都能解释 —— 那这个观察就什么都没证明。**

`§7.5` 那个"发布者一死 → 收到 0 条"的实验就是这种：

| 说法 | 解释 |
|---|---|
| A：抽屉在**发布者** | 发布者一死，抽屉跟着死 → 0 条 ✅ |
| B：抽屉在**订阅者** | 那个订阅者刚出生，一条都没收到过，抽屉必然是空的 → 0 条 ✅ |

**两版答案一样 = 废题。**

要分开它们，得挑一个**两版答案不同**的输入：**让发布者的 `depth` 比订阅者小**。

```bash
# 终端 A：发布者 depth=2（抽屉只有 2 格）
ros2 run hello_ros qos_talker --ros-args -p depth:=2

# 终端 B：订阅者要 5 条（不要 --once，要数条数）
ros2 topic echo --qos-reliability reliable --qos-durability transient_local --qos-depth 5 \
  /qos_hist std_msgs/msg/String
```

| 说法 | 预测 |
|---|---|
| A（抽屉在发布者，容量 2） | **2 条** |
| B（抽屉在订阅者，容量 5） | **5 条** |

**实测：2 条（第4条、第5条）→ 说法 A 成立，抽屉在发布者。**

> 这就是第 6 关学过的：**好测试 = 新旧答案不一样的那个输入。**

### 7.5 ⭐ `TRANSIENT_LOCAL` 不是持久化

| 操作 | 结果 |
|---|---|
| 发布者发完 5 条，**活着**，晚来的订阅者 | ✅ 收到 5 条 |
| 发布者发完 5 条，**Ctrl+C 杀掉**，晚来的订阅者 | ❌ 收到 **0** 条 |

**"发完 5 条"这个动作一模一样，唯一的差别是进程还活着没有。**

`TRANSIENT_LOCAL` 里那个 **transient** 就是提示 —— **"短暂的、临时的"**。
历史存在**发布者的进程内存**里，不是磁盘。**发布者一死，全没。**

> **现实含义**：想让"新来的订阅者一定拿得到最后状态"，
> 就得让**发布者常驻**。要真正跨进程重启的持久化，得另找机制。

### 7.6 ⭐ 和第 1 关那条旧账对上

第 1 关的答案是"后启动的订阅者收不到启动前的消息，因为默认 QoS 是 volatile"。
现在能说完整了：

```text
默认 QoSProfile    →  durability = VOLATILE
VOLATILE 的含义    →  只发"我连上之后"产生的消息
VOLATILE 没有抽屉  →  发布者根本没留历史
结果              →  晚来的订阅者听到的永远是"从现在开始"
```

**"必须先启动 talker"不是一条规定，是默认 QoS 的必然结果。**
把发布者改成 `TRANSIENT_LOCAL`，顺序就反过来了 —— 先起订阅者、后起发布者，照样能拿到。

---

## 8. 踩坑记录

### ❌ 坑 1：把「API 速查表」当成了「填空答案」

骨架里的 TODO 1 是：

```python
depth = ???          # TODO 1
```

填成了：

```python
depth = self.create_publisher(String, 'depth_hist', qos)
```

**那一行确实是速查表里有的** —— 但速查表是**菜单，不是订单**。

> 菜单上列了所有能点的菜，不等于**每道菜都是你这桌的**。
> 速查表列的是"这个函数**长什么样**"，不是"**你这一格该填哪个**"。

而且它必然报错：`qos` 要到第 16 行才定义，第 14 行就用它 →

```text
UnboundLocalError: cannot access local variable 'qos' where it is not associated with a value
```

**这一格要的是"一个数字"**，而速查表里**只有一行是以 `.value` 结尾的**：

```python
depth = self.get_parameter('depth').value
```

> 📌 **这是"提示文字当代码抄"的第三次**（第 5 关把 `???` 旁的提示当字面量、
> 第 6 关把 `...` 和 `--- TODO 1` 抄进代码）。
> **前两次抄的是中文**，第 6 关的规矩"只有代码块里的英文能抄"**在这里不够用** ——
> 这次抄的**确实是英文**，只不过抄的是**菜单**。

### ❌ 坑 2：`self.HistoryPolicy` —— 名字挂错了人

```python
qos = QoSProfile(
    history=self.HistoryPolicy.KEEP_LAST,          # ❌
    reliability=self.ReliabilityPolicy.RELIABLE,   # ❌
    durability=self.DurabilityPolicy.TRANSIENT_LOCAL,   # ❌
)
```

```text
AttributeError: 'QosTalker' object has no attribute 'HistoryPolicy'
```

**报错在替你问一个问题：`HistoryPolicy` 是"节点身上的东西"吗？**

不是。它是 **`rclpy.qos` 这个模块里的名字**，要 import 进来用：

```python
from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy
```

节点的属性（`self.xxx`）只有 `create_publisher` / `get_parameter` / `get_logger` 这类
**挂在这个对象上的东西**。`HistoryPolicy` 是个**枚举类型**，跟节点没有从属关系。

> 判断方法：**`dir()` 一下，别猜。** 这跟第 5 关那四次
> （`goal_handle.cancel_call`、`feedback()` 串门……）是同一个毛病。

### ❌ 坑 3：残留进程污染实验（本关栽了 **3 次**）

**症状**：`-p depth:=2` 明明只留 2 条，晚来的订阅者却收到了 **`第1条`**。

**⭐ 但那句 `第1条` 本身就是铁证** —— `depth:=2` 的历史里**只可能是第4条、第5条**，
**它根本没有第1条**。能收到 `第1条`，说明对面那个发布者的 `KEEP_LAST` 至少是 5。

**真凶**：`-p depth:=5` 的进程还活着，一直没关。

```text
$ ps -eo pid,etimes,args | grep qos_talker
  681569      46  ... qos_talker --ros-args -p depth:=5     ← 活了 46 秒
```

**这是第三次栽在同一个坑上**（第 3 关 `pkill` 留 `/dev/shm` 垃圾、
专项 01 造题时残留污染"正常基准"、第 7 关收尾那三个跑了 12 分钟的进程）。

**诊断动作 —— 做实验之前先敲**：

```bash
ros2 topic info /qos_hist
```

| 看到 | 含义 |
|---|---|
| `Unknown topic '/qos_hist'` | ✅ 干净，可以开始 |
| `Publisher count: 1` | ⚠️ **有鬼** —— 你要测的这一刻，这里应该是 0 个 |

> ⚠️ **注意判据**：没有发布者时它说的是 **`Unknown topic '/xxx'`**，
> **不是** `Publisher count: 0`。这两个不一样。

**收工动作**：跑完实验**一定**回终端按 Ctrl+C，再确认一次 `Unknown topic`。

### ❌ 坑 4：我自己犯的 —— "不兼容是静默的"

造题之前我以为 QoS 不兼容**没有任何提示**，
因为我早期验证时写的命令是：

```bash
ros2 topic pub ... > /dev/null 2>&1      # ← 就是这里
```

**把输出扔了，然后得出"它不说话"的结论。**

实际它**说了** —— 两边各一条 WARN，而且**直接点名是哪个策略**。

> **扔掉输出 = 自己给自己制造一个静默 bug。**
> 这条和"贴半截输出"是同一个家族：**信息的缺失，多半是自己造成的。**

### 🔑 本关四条坑的公共形状

| 坑 | 真实原因 |
|---|---|
| 1 | 把**参考**当**答案** |
| 2 | 名字的**归属**靠猜，不去 `dir()` |
| 3 | 实验**环境**没清，结论就不可信 |
| 4 | 自己把**证据**丢了，然后说没有证据 |

四条的共同点：**都不是"不会写代码"，是"没去确认"。**

---

## 9. 自测题

### 9.1 课堂已覆盖（附答案，先自己答一遍再点开）

<details>
<summary><b>题 1：发布者用 <code>BEST_EFFORT</code>、订阅者用 <code>RELIABLE</code>，能连上吗？反过来呢？</b></summary>

**前者不能，后者能。**

规则是「**发布者提供 ≥ 订阅者要求**」。

- `BEST_EFFORT`（提供少） + `RELIABLE`（要求多） → ❌ 配不上
- `RELIABLE`（提供多） + `BEST_EFFORT`（要求少） → ✅ 配得上

**它是 ≥ 不是 =** —— 两边写不一样，照样能通。实测见 §7.1。

</details>

<details>
<summary><b>题 2：QoS 不兼容时，<code>ros2 topic info</code> 显示什么？这说明什么？</b></summary>

显示 `Publisher count: 1` / `Subscription count: 1` —— **看起来一切正常。**

因为 `ros2 topic info`（不带 `-v`）数的是"**发现到**了几个端点"，
**不是"有几对配得上"**。发现和匹配是两回事。

**要看 QoS 得加 `-v`**：

```bash
ros2 topic info -v /qos_hist
```

</details>

<details>
<summary><b>题 3：晚上 10 点，一个 <code>TRANSIENT_LOCAL</code> 的发布者 shutdown 了。11 点我起一个 <code>TRANSIENT_LOCAL</code> 的订阅者，能收到它 10 点发的最后一条吗？</b></summary>

**不能，一条都收不到。**

`TRANSIENT_LOCAL` 的"历史"存在**发布者的进程内存**里，**不是磁盘**。
进程没了，抽屉跟着没。

**transient = 短暂的** —— 名字就是提示。实测见 §7.5。

**想让新订阅者一定拿得到状态**：让发布者**常驻**（比如 launch 里一直开着）。

</details>

<details>
<summary><b>题 4：发布者 <code>depth=2</code>、订阅者 <code>--qos-depth 10</code>，晚来的订阅者收到几条？为什么？</b></summary>

**2 条**（第4条、第5条）。

订阅者张着手要 10 条，但**发布者的抽屉里只有 2 格** ——
那 8 条不是它不想要，是**来源就没有**。

> ⚠️ 别答"两边取小的那个" —— 那句话**结论对、原因说反了**。
> 到手少是因为**来源少**，不是"订阅者只要了这么多"。§7.4 有判据实验。

</details>

<details>
<summary><b>题 5：<code>ros2 topic echo --qos-durability transient_local /话题</code> 为什么收不到历史？</b></summary>

因为它**还带着默认的 `BEST_EFFORT`**。

`ros2 topic echo` 的默认档是 **`sensor_data`** = `BEST_EFFORT` + `KEEP_LAST(5)` + `VOLATILE`。
你只覆盖了 `durability` 那一项，`reliability` 还是 `BEST_EFFORT`。

而**历史补发要靠可靠传输** —— `BEST_EFFORT` 不重传已经过去的东西。

**正确写法**（两个都给）：

```bash
ros2 topic echo --qos-reliability reliable --qos-durability transient_local /qos_hist std_msgs/msg/String
```

**教训：QoS 是一组，改一项不等于只改了一项。**

</details>

<details>
<summary><b>题 6：做实验之前，为什么要先跑 <code>ros2 topic info /话题</code>？期望看到什么？</b></summary>

防**残留进程**污染 —— 本关栽了 3 次。

有旧发布者活着时，你测的**不是你以为的那个东西**，日志会变成两个进程交错的垃圾，
而且**完全不报错**，看着就像代码坏了。

**期望看到 `Unknown topic '/话题'`**（⚠️ 不是 `Publisher count: 0`）。
看到 `Publisher count: 1` 就说明还有鬼。

</details>

### 9.2 留给下次的思考题（无答案）

1. `KEEP_ALL` 和 `KEEP_LAST(n)` 除了"留几条"之外，还有个更根本的区别 ——
   一个**会阻塞发布者**，一个不会。想想为什么？什么场景下非用 `KEEP_ALL` 不可？

2. `qos_profile_sensor_data` 为什么把 `durability` 定成 `VOLATILE` 而不是 `TRANSIENT_LOCAL`？
   相机数据"留最近 5 帧"听起来也有用啊。

3. 把发布者改成 `BEST_EFFORT`，然后用你第 7 关写的 `group_demo.py` 那种"睡 2 秒的慢订阅者"接 ——
   **在单线程执行器下**，慢回调睡着的那 2 秒里发布者发的消息会怎样？
   （提示：`depth` + 接收队列 + 第 7 关的"定时器不排队"）

4. `ros2 topic hz /话题` 在 QoS 不兼容的时候会输出什么？先预测再跑。

5. 第 7 关那个 `group_demo.py` 用的是默认 QoS。
   如果把那个慢订阅者改成 `BEST_EFFORT`，而发布者保持 `RELIABLE`，
   **回调组那套结论还成立吗？**（先想清楚"连不上"和"抢锁"哪个先发生）

---

## 10. 附：跨关待办

### ① 「先预测再运行」这个动作，本关**做了一半**

- 题 8-1 四格：**4/4 全对**（这是七关以来第一次预测满分）
- 题 8-3 三格：**3/3 全对**
- 但**两次都是先看到实测、再给的"预测"**（题 8-1 的 `第1条`、题 8-4 的 `0 条`）

**差别在哪**：预测的目的是**制造"预期"**，好让"预期 − 实际"这个差能把异常顶出来。
先跑再看，这个差就永远是 0 —— **撞对了也不知道自己对在哪。**

> 这条和第 5 关那句"我学了这些感觉都没底"是同一件事：
> **"底"来自"我自己算过一遍"，不来自"答案看起来对"。**

### ② 残留进程 —— **本关最顽固的一条，栽了 3 次**

`depth:=5` 活了 46 秒、45 秒，还有一个 `depth:=2` 活了 **232 秒**。
前两次甚至直接导致**实验结论无效**（`第1条` 那件事）。

**已经固化成动作**：做实验前 `ros2 topic info /话题` → 必须是 `Unknown topic`。

### ③ 「菜单当订单」—— 提示文字被当代码抄的**第三次**

前两次抄中文，这次抄英文。**规矩要升级**：

> 聊天里的东西分三种：
> **① 要你抄的**（代码块里、标了 TODO 的那一行）
> **② 给你查的**（API 速查表 / CLI 速查 —— 是**菜单**，列的是"长什么样"）
> **③ 给你看的**（`???` 和 `# TODO` 周围的中文）
>
> **②和③长得都像代码，但都不是答案。**

### ④ 好测试 = 新旧答案不同的那个输入（本关**真正学会**了）

题 8-4 那次：他的假设"抽屉在订阅者"和正确答案"抽屉在发布者"，
**对同一个观察给出同一个结果** —— 那个实验分不出胜负。

他随后自己指出需要"发布者 depth 比订阅者小"的输入来分开两版，
**这是第 6 关那条方法论第一次被主动用出来。**

### ⑤ `dir()` / 报错原文 —— 继续全胜

坑 2 那个 `AttributeError: 'QosTalker' object has no attribute 'HistoryPolicy'`
**已经把答案写在里面了**（"QosTalker 身上没有 HistoryPolicy" → 那就不是它的属性）。

---

## 附：本关命令速记卡

```bash
# ---------- 看 QoS（本关主力）----------
ros2 topic info -v /qos_hist          # 摊开两边端点的 QoS
ros2 topic info /qos_hist             # 没发布者时 = Unknown topic '/qos_hist'

# ---------- 发 / 收 时指定 QoS ----------
ros2 topic pub  --qos-reliability best_effort -t 6 -r 1 -w 0 /t std_msgs/msg/String "{data: hi}"
ros2 topic echo --qos-reliability reliable --qos-durability transient_local --qos-depth 2 \
  /qos_hist std_msgs/msg/String
#                ↑ 两个都要给 —— 只给 durability 是收不到历史的（默认 BEST_EFFORT）

# ---------- 本关实验 ----------
ros2 run hello_ros qos_talker --ros-args -p depth:=2
#    期望：发了 第1条 → 第5条，然后停住不下线

# ---------- 排查（做实验之前必敲）----------
ros2 topic info /qos_hist             # 必须是 Unknown topic
ros2 pkg executables hello_ros        # "No executable found" 的第一反应
ps -eo pid,etimes,args | grep qos_talker     # etimes = 活了多少秒，几百秒的必是残留

# ---------- 清残留 ----------
#   ⚠️ pkill -f 匹配的是【命令行文本】，不是节点名；一行式命令里还会自匹配
P="qos""_talker"; ps -eo pid,args | grep -F "$P" | grep -v grep | awk '{print $1}' | xargs -r kill

# ---------- 测试 ----------
colcon test --packages-select hello_ros
colcon test-result --verbose
```

---

## 相关笔记

- [第 1 关 · 话题](lesson-01-topic.md) —— 本关结的就是它的旧账
- [第 6 关 · 自定义消息](lesson-06-custom-message.md) —— "好测试 = 新旧答案不同的输入"
- [第 7 关 · 执行器与回调组](lesson-07-executor.md) —— 另一个"不写就有一堆默认行为"的旋钮
- [专项 01 · 怎么看日志](skill-01-log-reading.md) —— WARN 也是日志，本关靠它定位
