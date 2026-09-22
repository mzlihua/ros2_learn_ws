# 第 10 关 · 命名空间与重映射

> 前九关里，每个节点都只有**一个**自己 —— 一个 `talker`、一个 `listener`，
> 名字全世界独一份。想开两个，就撞名。
>
> 这一关回答一个问题：**怎么让同一个程序，在地上跑出好几份互不打架的副本？**
>
> 一句话：**命名空间是"在前缀上加一段字符串"，重映射是"把某个名字换成另一个名字"。**
> 两个都是**运行时**的事 —— 代码**一个字都不用改**。
>
> 而本关最大的坑，是一个**看不出错**的坑：
> **重映射的左边，必须写成"展开之后的完整名字"。写错了，它不报错，它只是什么都不做。**

---

## 目录

- [1. 本关目标](#1-本关目标)
- [2. 核心概念](#2-核心概念)
- [3. 完整代码](#3-完整代码)
- [4. 命令速查（CLI + launch）](#4-命令速查cli--launch)
- [5. 命令行工具速查](#5-命令行工具速查)
- [6. 构建与运行流程](#6-构建与运行流程)
- [7. 实测现象与结论 ⭐](#7-实测现象与结论-)
- [8. 踩坑记录](#8-踩坑记录)
- [9. 自测题](#9-自测题)
- [10. 附：跨关待办](#10-附跨关待办)
- [附：本关命令速记卡](#附本关命令速记卡)

---

## 1. 本关目标

- 说清**命名空间**对三类名字（节点名 / 话题名 / 参数名）各做了什么。
- 记住**四种名字写法**，以及它们**谁会被 `__ns` 加前缀、谁不会**。
- 会用 **`-r 左:=右`** 改名，并且知道**左边该写什么**。
- 会在 **launch 文件里**用 `namespace=` / `name=` / `remappings=` 表达同一件事。
- 把第 9 关留下的一个悬案**结掉**。

**这一关的性子**：代码几乎不写（只写了一个新的 launch 文件），
但**名字的密度**是十关里最高的 —— 屏幕上到处都是名字，而且它们**长得像但规则不同**。

> 如果你只从这一关带走一件事，带走这句：
>
> **`--ros-args -r __ns:=/robot1` 不是"起一个叫 robot1 的东西"，
> 它是在说"从今往后，这个节点里所有的相对名字，都给我加一段前缀"。**

---

## 2. 核心概念

### 2.1 命名空间就是一个字符串前缀

节点里写的是什么，和你在终端里看到的**不是一个东西**：

| 代码里写的（第 1 关的 `talker.py`） | 加上 `-r __ns:=/robot1` 之后 |
|---|---|
| `super().__init__('talker')` | 节点名 → `/robot1/talker` |
| `self.create_publisher(String, 'chatter', 10)` | 话题名 → `/robot1/chatter` |

**代码一个字没改，文件一个字没改，连 build 都不用。**
变的只是**启动时传给它的那几个参数**。

> **命名空间是运行时的，不是编译期的。** 这是它最大的价值：
> 同一份二进制，起 10 份，10 个互不干扰的世界。

### 2.2 ⭐ 四种名字写法

这是本关的地基。**四种写法，四条不同的规矩。**

| 写法 | 长什么样 | 在 `__ns:=/robot1` 下展开成 | 会被加前缀吗 |
|---|---|---|---|
| **相对名** | `chatter` | `/robot1/chatter` | ✅ **会** |
| **绝对名** | `/chatter` | `/chatter` | ❌ **不会**（谁都动不了它） |
| **私有名** | `~/x` | `/robot1/<节点名>/x` | ✅ 会，且**还要再插一层节点名** |
| **节点名** | `__node:=talker` 里的 `talker` | `/robot1/talker` | ✅ 会（节点名本身也是相对名） |

**"相对"和"绝对"的区别就一个字符：开头有没有 `/`。**

- 没有 `/` → 相对 → 前面挂上命名空间
- 有 `/` → 绝对 → **命名空间对它完全无效**

实测（都是干净的、清过场的）：

```
-r __ns:=/robot1          话题=/robot1/chatter   节点=/robot1/talker
-r __ns:=/a/b             话题=/a/b/chatter      节点=/a/b/talker      ← 可以嵌套
-r __ns:=/                话题=/chatter          节点=/talker          ← 根命名空间
```

### 2.3 ⭐⭐ logger 名字用 `.`，不用 `/`

同一个节点，屏幕上同时出现两种名字：

```
[INFO] [robot1.talker]: 第 1 次心跳        ← logger 名，点号
$ ros2 node list
/robot1/talker                            ← 节点名，斜杠
```

**这不是笔误，是两套规则。**

- **节点名**：ROS 图里的名字，用 **`/`** 分层。
- **logger 名**：日志系统的名字，默认**从节点名推出来**，但分隔符是 **`.`**。

源码就一行（`rcutils/logging.h:37`）：

```c
#define RCUTILS_LOGGING_SEPARATOR_STRING "."
```

**它长得像节点名，规则却不一样。** 本关题 1 你三处名字全猜错，错的就是这一处。

### 2.4 ⭐⭐ 重映射：`-r 左:=右`，**左边必须写展开之后的名字**

`-r` 是 `--remap` 的简写，形状是 **`-r 旧名:=新名`**。

**规则只有一条，但它是本关的命门：**

> **左边会被当成"完整的、展开之后的图上的名字"来匹配。**

所以在一个 `__ns:=/robot1` 的节点上：

| 你写的 | 它去匹配谁 | 匹配到了吗 | 结果 |
|---|---|---|---|
| `-r chatter:=joint_states` | `/robot1/chatter` | ✅（相对名靠 `__ns` 展开后正好是它） | 改名成功 |
| `-r /chatter:=/foo` | `/chatter` | ❌ **这个图上根本没有 `/chatter`** | **静默失效** |

**注意最后一行：它不报错。** 你敲完，节点照起，话题照发，
**只是那个 `-r` 像没写过一样被丢掉了。**

> **这正是第 9 关那句"跑起来了、有输出、没报错 ≠ 实验做了"的第五个成员。**
> 区别在于：前四个是"你以为你测了"，这个是**"你以为你改了"**。

### 2.5 右边可以是绝对的

左边必须是"展开后的名字"，**右边没这个限制**：

```
-r chatter:=joint_states        → /robot1/joint_states    （右边是相对的，跟着 ns 走）
-r chatter:=/absolute_topic     → /absolute_topic         （右边带 /，就是绝对的）
```

**右边的 `/` 是"我要把它钉死在根"，不是"我写错了"。**

### 2.6 重命名节点：`__node`

`__ns` 改前缀，`__node` 改**节点名本身**：

```
-r __node:=pub_a     → 节点 /robot1/pub_a
```

**它只动节点名。话题名一个都不动。**
（本关题 5 你预测它会把话题也带走 —— 没有。）

### 2.7 launch 文件里的同一件事

CLI 上的三个开关，在 launch 里各有对应：

| CLI | launch 里 |
|---|---|
| `-r __ns:=/robot1` | `Node(namespace='robot1')` |
| `-r __node:=pub_a` | `Node(name='pub_a')` |
| `-r chatter:=joint_states` | `Node(remappings=[('chatter', 'joint_states')])` |

**`remappings` 是一个「二元组的列表」**，不是字典：

```python
remappings=[('chatter', 'joint_states')]              # 一个
remappings=[('chatter', 'joint_states'), ('a', 'b')]  # 两个
```

形状的记忆点：**列表装元组，元组里左边旧、右边新，中间是逗号**（CLI 上是 `:=`）。

---

## 3. 完整代码

### 本关唯一的新文件：`src/hello_ros/launch/two_robots.launch.py`

**一句话起两台机器人，各带一个 talker 一个 listener，互不打架。**

```python
from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    return LaunchDescription([
        Node(
            package='hello_ros',
            executable='param_talker',
            namespace='robot1',
            parameters=[{'message': '一号机'}]
        ),
        Node(
            package='hello_ros',
            executable='param_talker',
            namespace='robot2',
            parameters=[{'message': '二号机'}]
        ),
        Node(
            package='hello_ros',
            executable='listener',
            namespace='robot1',
        ),
        Node(
            package='hello_ros',
            executable='listener',
            namespace='robot2',
        ),
    ])
```

**四行里没有一行是新的** —— `package` / `executable` / `parameters` 都是第 4 关
`demo.launch.py` 里就有的，本关只是多了一个 `namespace=`。

（不用改 `setup.py`：`data_files` 里是 `glob('launch/*.launch.py')`，
**新文件会被自动收进去** —— 但**要重新 build 一次**，见 §6。）

### 用到的现成节点

| 节点 | 来自 | 本关角色 |
|---|---|---|
| `param_talker` | 第 3 关 | 数据源，能靠 `message` 参数区分是哪一台 |
| `listener` | 第 1 关 | 接收端，用来验证"串不串台" |
| `talker` | 第 1 关 | 做 `-r` 对照实验时的一次性探针 |

**为什么用 `param_talker` 而不是 `talker`？** 因为它能靠参数改内容 ——
`一号机` / `二号机` 打在屏幕上，**一眼就能看出哪条消息来自哪台**。
这是第 6 关"好测试 = 新旧答案不同的输入"在这里的应用。

---

## 4. 命令速查（CLI + launch）

### 一次性带命名空间起节点

```bash
ros2 run hello_ros talker --ros-args -r __ns:=/robot1
```

**`--ros-args` 是一个分水岭**：它**后面**的参数归 ROS 管，
**前面**的归节点自己的命令行解析器管。`-r` 必须写在它后面。

### 一次给多个

```bash
ros2 run hello_ros talker --ros-args -r __ns:=/robot1 -r chatter:=joint_states
ros2 run hello_ros talker --ros-args -r __ns:=/robot1 -r __node:=pub_a
```

### `-r` 的完整写法

```bash
-r 旧名:=新名
```

| 左边 | 右边 | 效果 |
|---|---|---|
| `chatter` | `joint_states` | 话题改名（相对 → 相对） |
| `chatter` | `/absolute_topic` | 话题改名并钉到根 |
| `/robot1/chatter` | `/robot2/chatter` | 用**全名**改（相对名在 `__ns` 下匹配不到） |
| `__ns` | `/robot1` | 设命名空间 |
| `__node` | `pub_a` | 改节点名 |

> ⚠️ **`-r` 只在 `ros2 run` / `ros2 launch` 里是"重映射"。**
> 在 `ros2 bag play` 里 `-r` **是 `--rate`（倍速）** —— 见 §8 坑 1。

### launch 里的对应写法

```bash
ros2 launch hello_ros two_robots.launch.py
ros2 launch hello_ros two_robots.launch.py --show-args    # 看它声明了哪些参数
```

---

## 5. 命令行工具速查

### 看名字用这三条

```bash
ros2 node list        # 节点都被展开成了什么名字
ros2 topic list       # 话题都被展开成了什么名字
ros2 topic info /话题  # 这个话题上有几个发布者、几个订阅者
```

### ⭐ 做实验之前必敲的一条

```bash
ros2 node list
```

**必须是空的。**

> 本关最惨的一次数据污染，就是一个**忘了 Ctrl+C 的 listener** 一直挂在图上，
> 让每一轮 `ros2 topic list` 都多出一条 `/robot2/chatter`。
> 我当时已经知道它在那儿，还是把带污染的数据记了下来，差点写进笔记。
>
> **判据同第 9 关：先看有没有人，再动手。**

### 看节点名和 QoS

```bash
ros2 topic info /robot1/chatter --verbose
```

### 看日志名（那个点号）

```bash
ros2 run hello_ros talker --ros-args -r __ns:=/robot1
#   [INFO] [robot1.talker]: ...      ← 点号在这儿
```

### 收工检查

```bash
ps -eo pid,etimes,args | grep ros2 | grep -v grep
#   etimes = 已经活了多少秒，几百秒的必是残留
```

---

## 6. 构建与运行流程

### 构建：本关**必须** build 一次

新加了一个 launch 文件，而 `setup.py` 里是：

```python
data_files=[..., (os.path.join('share', package_name, 'launch'),
                  glob('launch/*.launch.py'))]
```

**`glob` 是在 build 那一刻执行的**，当时的清单里没有 `two_robots.launch.py`。

```bash
colcon build --packages-select hello_ros --symlink-install
```

> ⚠️ **不带 `--symlink-install` 会把 editable 安装降级成拷贝**（第 9 关坑 6）。
> 这条命令**永远带上它**。

### 运行

```bash
ros2 launch hello_ros two_robots.launch.py
```

### 验收清单

```bash
# ① 四个节点，名字都带前缀
ros2 node list
#    期望：/robot1/param_talker  /robot1/listener
#          /robot2/param_talker  /robot2/listener

# ② 两条话题，各挂各的
ros2 topic list
#    期望：/robot1/chatter  /robot2/chatter

# ③ ⭐ 屏幕上交叉出现、且不串台
#    期望：robot1.listener 只打「接收: 一号机」
#          robot2.listener 只打「接收: 二号机」
```

**③ 才是真正的验收。** ①② 只证明"名字起对了"，
③ 证明的是**"它们真的是两个世界"**。

---

## 7. 实测现象与结论 ⭐

### 7.1 ⭐⭐ 判据实验：四格重映射

在 `-r __ns:=/robot1` 之下，只改重映射那一段，看话题和节点分别变成什么。

| | 命令（`__ns:=/robot1` 之后的部分） | 话题 | 节点 |
|---|---|---|---|
| **C** | `-r chatter:=joint_states` | `/robot1/joint_states` | `/robot1/talker` |
| **D** | `-r /chatter:=/foo` | **`/robot1/chatter`（没变！）** | `/robot1/talker` |
| **E** | `-r chatter:=/absolute_topic` | `/absolute_topic` | `/robot1/talker` |
| **F** | `-r __node:=pub_a` | `/robot1/chatter` | `/robot1/pub_a` |

**四格里藏着三条规则：**

1. **C**：相对名靠 `__ns` 展开后**正好匹配上** → 改名成功。
2. **D**：`/chatter` 是个**绝对名**，图上从来没有过 —— **静默失效，什么也没发生**。
3. **E**：**左边相对、右边绝对** —— 两边规则各走各的，互不影响。
4. **F**：`__node` **只动节点名**，话题名一根汗毛都没动。

**C 和 D 是本关最重要的一组对照：**

> 两条命令**看起来都在改 `chatter`**，一条生效、一条失效，
> **失败那条发出的任何信号都不是"错误"** —— 只是没发生。

### 7.2 ⭐ 两台机器人：成功的那一次

`two_robots.launch.py` 跑起来之后：

```
/robot1/param_talker
/robot1/listener
/robot2/param_talker
/robot2/listener
```

```
/robot1/chatter
/robot2/chatter
```

屏幕输出**交叉出现**，但两边各认各的：

```
[robot1.listener]: 接收: 一号机
[robot2.listener]: 接收: 二号机
```

**零串台。** 同一份 `param_talker.py`、同一份 `listener.py`，
**一个字都没改**，就变成了两台机器人。

> 这就是命名空间存在的理由：
> **它让"代码"和"这份代码在这个系统里的身份"彻底分开。**

### 7.3 ⭐⭐ 反过来做一次：串台是怎么造成的

把 `remappings=[('chatter', 'joint_states')]` **加到了两个 talker 上**，
（而不是只加一个）—— 结果**两个 listener 全部静音**。

`ros2 topic list`：

```
/parameter_events
/robot1/chatter          ← 还是在这儿！但……
/robot1/joint_states
/robot2/chatter
/robot2/joint_states
/rosout
```

`ros2 topic info /robot1/chatter`：

```
Type: std_msgs/msg/String
Publisher count: 0
Subscription count: 1
```

**话题还在列表里，但上面没有发布者了。**

> **`ros2 topic list` 里出现一个话题 ≠ 有人在发。**
> 只要**还有订阅者在等**，这个话题就还"存在"。
> （这是第 8 关"discovery ≠ match"的又一次现身。）
>
> **`/robot1/chatter` 上那个 1，是你自己的 listener —— 它在等一个再也不会来的消息。**

这一格比"成功那次"更值钱：**它证明了 `remappings` 是加在"节点"上的，不是加在"话题"上的。**
两个节点各自改各自的，**改的其实是两条不同的路**。

### 7.4 ⭐ 带命名空间的 bag

数据源：`param_talker` 在 `/robot1` 下，`message='一号机'`，1 Hz。

```
$ ros2 bag record --topics /robot1/chatter -o bag_r2
```

`ros2 bag info`：

```
Duration:  13.000110242s
Messages:  14
Topic information:
  Topic: /robot1/chatter | Type: std_msgs/msg/String | Count: 14
```

**包里的 `Topic:` 是 `/robot1/chatter` —— 全名。**

> **bag 存的是"展开之后的名字"，不是代码里写的那个 `chatter`。**
> 因为 recorder 是个订阅者，它**只能看见图上的名字**。

推论（本关题 11 就是这个）：
`ros2 bag play bag_r2 -r __ns:=/robot1` 能把 14 条**原样**交给 `/robot1/listener` ——
**因为 play 出来的名字跟包里存的一模一样，正好对上。**
实测：`接收: 一号机 ×14`。

### 7.5 ⭐⭐ 本关最重的一坑：`ros2 bag play` 的 `-r` 不是重映射

按上一节的思路，很自然会写：

```bash
ros2 bag play bag_r2 -r /robot1/chatter:=/robot2/chatter
```

**这条命令是错的**，而且错的方式很特别：

```
ros2 bag play: error: argument -r/--rate: \
    /robot1/chatter:=/robot2/chatter is not the valid type (float)
```

**`ros2 bag play` 里 `-r` 早就被 `--rate` 占了**（第 9 关 §2.5 讲过，`-r 2.0` 是倍速）。

```
-r, --rate RATE       rate at which to play back messages.
--remap, -m REMAP [REMAP ...]
```

**同一个字母 `-r`，在 `ros2 run` 里是 `remap`，在 `ros2 bag play` 里是 `rate`。**

正确写法：

```bash
ros2 bag play bag_r2 --remap /robot1/chatter:=/robot2/chatter
#   或者简写：-m
```

（**注意左边也必须是全名 `/robot1/chatter`** —— 跟 §7.1 的 D 格同一条规则。
这里左边写对的理由不一样：`bag play` 里没有 `__ns` 帮你展开，包里的名字就是全名。）

### 7.6 ⭐⭐ 第 9 关的悬案，破了

**第 9 关 §7.6 留了个未解之谜**：回放开始的时候，**开头第一条有时会漏掉**。
当时只有假说，没有证据。

这一关把它钉死了。

**假说**：`player` 是"开播那一刻才创建发布者"的，DDS 发现还没配完，
第一条就发出去、也就丢了。

**源码里对应两行**：

```cpp
// rosbag2_transport/player.hpp:94-97
/// Will construct Player class and initialize play_options, storage_options from node
/// parameters. At the end will call Player::play() to automatically start playback in a
/// separate thread.
```

```cpp
// rosbag2_transport/play_options.hpp:103
// Sleep before play. Negative durations invalid. Loops are not affected.
rclcpp::Duration delay = rclcpp::Duration(0, 0);
```

**构造 = 建发布者；`delay`（`-d`）睡在 `play()` 里。**
所以**加了 `-d`，就多出一段"发布者已经在、但还没开口"的时间**，正好够 DDS 配对完成。

**实验（判据：两个假说给出不同预测）**：

- 如果病因是"发布者建得太晚" → **加 `-d` 会好**
- 如果是别的 → `-d` 没用

| 组 | 跑了几次 | 收到完整包 |
|---|---|---|
| 基线（不加 `-d`） | 9 | **2 / 9**（丢了 7 次） |
| `-d 0.5` / `1` / `2` / `5` | 15 | **15 / 15** |

**结论：假说成立。**

> **`-d` 不是"延迟开播"这么简单 —— 它是"DDS 配对的窗口"。**
> 第 9 关把它列在"可用的旋钮，留给下次挖"里，这次挖到了。

**顺带解释了一个老现象**：`--remap` 那次收到 **13** 条，`-r __ns:=/robot1` 那次收到 **14** 条。
包里有 14 条 —— 差的正是那**开头第一条**。
**同一份包、同一个病因、两次不同的运气。**

### 7.7 `__ns` 给两次会怎样

```
-r __ns:=/robot1        → /robot1/chatter    /robot1/talker
-r __ns:=/robot1 再 -r __ns:=/   → /robot1/chatter    /robot1/talker   ← 没回到根
-r __ns:=/                        → /chatter          /talker          ← 单独给才行
```

**后面那个 `__ns` 没有覆盖前面的。**
（本关只测到现象，没测到规则 —— 按第 5 关的规矩，它现在只能算「现象」。）

**实际影响**：想清掉命名空间，就**别在同一个命令行里给两个 `__ns`**。

---

## 8. 踩坑记录

### ❌ 坑 1：`-r` 在两个命令里是两个意思（**我预测错了**）

我让你跑 `ros2 bag play bag_r2 -r /robot1/chatter:=/robot2/chatter`，
并**预测它会成功**。它没有：

```
ros2 bag play: error: argument -r/--rate: ... is not the valid type (float)
```

**我错的正好是本关的题眼** —— 我拿 `ros2 run` 的规则去套 `ros2 bag play`。

> **教训的形状**：**同一个字母在两个命令里可以是两个意思。**
> 靠"上次也是这么写的"推断，就会撞上这种坑。
> **判据是 `--help`，不是记忆。**
>
> （同族：第 4 关的 flake8 配置、第 9 关的 `ls -l <目录>/` ——
> **先确认尺子，再量东西。**）

### ❌ 坑 2：重映射加错了对象，结果**全静音**

只该给**一个** talker 加 `remappings`，我给**两个都**加了。
结果不是"错一半"，是**两边都没了**。

**根因**：`remappings` 是**节点级**的。两个节点各自把自己发的东西挪走了，
两条 `/robot1/chatter` 和 `/robot2/chatter` 上**同时没有发布者**。

**这是好事。** 它把"重映射加在谁身上"这个问题**从脑子里搬到了屏幕上**。

### ❌ 坑 3：录了一个空包（忘了删 remappings）

`bag_r1` 的 `ros2 bag info`：

```
Messages:  0
Start:     Apr 12 2262 ...      ← 哨兵值，第 9 关那副老面孔
```

**因为上一轮的 `remappings` 还在**：`/robot1/chatter` 上压根没有发布者。

**你自己诊断出来了**（"发布到 joint 上了"）—— 这是本关最好的一步。

> 有意思的是：**第 9 关你就见过这副面孔**（volatile 录到 0 条），
> 当时病因是"发布者不留历史"；
> **这次病因完全不同（压根没人发），症状一模一样。**
>
> **症状相同 ≠ 病因相同。** 别凭长相认病。

### ❌ 坑 4：忘了 Ctrl+C 的 listener，污染了四轮数据

一个 `listener --ros-args -r __ns:=/robot2` 一直挂在图上，
活了 **400 秒**。

它的存在让每一轮 `ros2 topic list` 都多一条 `/robot2/chatter`、
`ros2 node list` 都多一条 `/robot2/listener`。

**我自己也栽了一次**：做最后那轮 `__ns` 边界验证时，
屏幕上的 `/robot2/*` 明晃晃地在那儿，我还是把结果抄了下来 ——
**抄完才发现这四行里有两行是别人的。**

**处置**：所有结果作废，`pkill` 清场，重跑一遍干净的。

> **残留进程不只在"污染日志"，它直接伪造数据。**
> 这是本项目的第 5 次了（第 2 / 7 / 9 关都有）。
> **动作已经固化：动手之前先 `ros2 node list`，必须是空的。**

### ❌ 坑 5：`timeout` 杀父进程，留下孤儿节点（**我自己栽的**）

我在脚本里写：

```bash
timeout 25 ros2 run hello_ros listener --ros-args -r __ns:=/robot2
```

`timeout` 到点杀掉的是 **`ros2 run` 这个父进程**，
**它下面真正的节点进程没人管**，继续活着 ——
实测残留了 **947 秒**。

**根因**：`ros2 run` 是个启动器，它**再 fork 一个进程**去跑节点。
杀父不杀子 —— 和第 9 关坑 3「非 tty 下的信号路径不一样」是同一族：
**你以为你在控制那个进程，其实你在控制它的外壳。**

**清法**：

```bash
P="listen""er"
pkill -f "$P --ros-args"
```

（`"listen""er"` 拆开写，是为了**让 `pkill` 自己的命令行文本不匹配到自己** —— 见第 7 关那条老账。）

> **排查形状**：`ps -eo pid,etimes,args | grep ros2`，
> `etimes` 是"活了多久"，**几百秒的一律是残留**。

### 🔑 本关五条坑的公共形状

| 坑 | 一句话 |
|---|---|
| 1 | **同一个符号，换个命令换了意思** —— 尺子得重新核 |
| 2 | 加错了**对象**（节点级的东西加到了两个节点上） |
| 3 | **症状一样，病根不一样** |
| 4 | **残留进程伪造数据** |
| 5 | **杀掉的是外壳，不是本体** |

**坑 1/5 是"你以为你在控制 A，其实在控制 B"；
坑 2 是"你以为你在改名字，其实在改某条路上谁跟谁说话"；
坑 3/4 是"数据不干净，结论就悬空"。**

---

## 9. 自测题

### 9.1 课堂已覆盖（附答案，先自己答一遍再点开）

<details>
<summary><b>题 1：<code>ros2 run hello_ros talker --ros-args -r __ns:=/robot1</code>。写出发送方那三种名字各是什么（节点名 / 话题名 / 日志里那个名字）。</b></summary>

| 名字 | 值 |
|---|---|
| 节点名 | `/robot1/talker` |
| 话题名 | `/robot1/chatter` |
| **日志名** | **`robot1.talker`** ← **用 `.`，不用 `/`** |

**第三处最容易错。** 日志系统的分隔符和 ROS 图的分隔符**是两套规则**，
源码就一行（`rcutils/logging.h:37`）：

```c
#define RCUTILS_LOGGING_SEPARATOR_STRING "."
```

**它长得像节点名，但对不上。**

</details>

<details>
<summary><b>题 2：节点里写 <code>~/status</code>，在 <code>__ns:=/robot1</code> 下展开成什么？</b></summary>

**`/robot1/talker/status`。**

`~` 是**私有名**：它先被换成**节点名**，**然后节点名本身再被命名空间加前缀**。
所以中间**多出来一层节点名**。

```
~/status  →  <ns>/<节点名>/status  →  /robot1/talker/status
```

**记法：`~` = "我自己的"，所以要带上自己的名字。**

</details>

<details>
<summary><b>题 3：在 <code>__ns:=/robot1</code> 之下，<code>-r /chatter:=/foo</code> 会发生什么？</b></summary>

**什么都不发生。话题还是 `/robot1/chatter`。**

**而且不报错。**

左边 `/chatter` 是**绝对名**，它要匹配的是**图上真实存在的名字** ——
而这个节点下面**根本没有 `/chatter` 这个东西**（话题叫 `/robot1/chatter`）。

**它不匹配，就被丢掉，一声不响。**

要改成功，左边得写全名：

```bash
-r /robot1/chatter:=/foo
#   或者写相对名，让 __ns 帮你展开：
-r chatter:=/foo
```

> **这是本关最贵的坑：重映射失败没有报警音。** 详见 §2.4、§7.1 的 D 格。

</details>

<details>
<summary><b>题 4：<code>-r chatter:=joint_states</code> 和 <code>-r chatter:=/absolute_topic</code>，区别在哪？</b></summary>

**区别在右边开头有没有 `/`：**

| 右边 | 展开成 | 原因 |
|---|---|---|
| `joint_states` | `/robot1/joint_states` | 相对名 → **跟着 `__ns` 走** |
| `/absolute_topic` | `/absolute_topic` | 绝对名 → **钉死在根，`__ns` 管不着** |

**左边必须是展开后的全名，右边没这个限制。**
右边那个 `/` 是在说"我要它就在根上"，**不是在写错**。

</details>

<details>
<summary><b>题 5：<code>-r __node:=pub_a</code> 之后，话题名会变成什么？</b></summary>

**不变，还是 `/robot1/chatter`。**

`__node` **只改节点名**，改完是 `/robot1/pub_a`。
**话题名一根汗毛都没动** —— 它俩是两件事。

**容易混的地方**：`__ns` 会**同时**改节点名和话题名（因为两个都是相对名）。
但 `__node` **只管节点名这一个**。

</details>

<details>
<summary><b>题 6：两台机器人不串台，靠的是什么？改代码了吗？</b></summary>

**靠命名空间。代码一个字都没改。**

`two_robots.launch.py` 只是给每个 `Node` 加了一个 `namespace=`：
同一份 `param_talker.py`、同一份 `listener.py`，起了两遍。

- talker 发的是相对名 `chatter` → `/robot1/chatter` 和 `/robot2/chatter`
- listener 收的也是相对名 `chatter` → 各收各的

**因为两边是"相对名 + 不同的前缀"，所以在图上根本就是两条不同的话题。**

> **命名空间让"代码"和"这份代码在这个系统里的身份"彻底分开。**

</details>

<details>
<summary><b>题 7：<code>ros2 bag play bag_r2 -r /robot1/chatter:=/robot2/chatter</code> 能跑吗？</b></summary>

**不能。**

```
ros2 bag play: error: argument -r/--rate: \
    /robot1/chatter:=/robot2/chatter is not the valid type (float)
```

**`ros2 bag play` 里 `-r` 是 `--rate`（倍速），不是重映射。**

正确写法：

```bash
ros2 bag play bag_r2 --remap /robot1/chatter:=/robot2/chatter
#   或 -m
```

> **同一个 `-r`，`ros2 run` 是 remap，`ros2 bag play` 是 rate。**
> **判据是 `--help`，不是记忆。**（第 9 关 §2.5 你已经见过 `-r 2.0` 的用法了。）

</details>

### 9.2 留给下次的思考题（无答案）

1. **`__ns` 给两次会怎样？** §7.7 只测到"后面那个没覆盖前面的"。
   再设计几组（`__ns:=/a` + `__ns:=/b` 反过来给、三个一起给），
   **看是"第一个赢"还是"另有规则"**。先预测再跑。

2. **`-r` 和 `__ns` 给的顺序有关系吗？**
   `-r __ns:=/robot1 -r chatter:=joint_states` 和反过来，
   **结果一样吗？** 想一想为什么。

3. **`remappings` 里写相对名还是全名？**
   `Node(namespace='robot1', remappings=[('chatter', 'joint_states')])`
   和 `remappings=[('/robot1/chatter', '/robot1/joint_states')]`，
   **都能跑吗？** 试一下。（提示：launch 里的重映射和 CLI 上的，
   **是不是在同一个时机生效的？**）

4. **私有名 `~/x` 能不能被重映射？** 左边该写 `~/x`、`/robot1/talker/x`，
   还是别的？先猜，再验证。

5. **两个不同的包里都有个叫 `talker` 的节点** ——
   起在同一台机器上，`ros2 node list` 会显示两个同名节点吗？
   如果会，`ros2 run` 还能正常跑吗？**命名空间能不能救它？**

6. **`ros2 bag record` 的时候加 `-r __ns:=/x` 会怎样？**
   recorder 是个订阅者 —— 给它加命名空间，它订阅的还是 `/robot1/chatter` 吗？
   想想第 9 关那句"`record` 拿不到的东西，一个字也录不下来"。

---

## 10. 附：跨关待办

### ① ✅ 第 9 关的悬案：**结案**

§7.6 那个"回放开头漏第一条"，已经用源码 + 判据实验钉死：
**`player` 构造时建发布者，`-d` 睡在 `play()` 里 → 加 `-d` 就有配对窗口。**

**这是本项目第一次"从悬案到结案"的完整走法**：
留现象 → 提假说 → 找能让两个假说分道扬镳的输入 → 跑 → 钉死。
第 9 关只在文档里写了"病因未知"，这次补上了证据。

### ② ⭐ 本关你真正做到的一件事：**预测错，但预测了**

题 5（`__node`）和题 1（三处名字）你都**写下了预测**才去跑 ——
题 1 你 0/3，题 5 也错了。

**但这两次错的收获，比前面那些"猜对了"的都大**，因为：

> **预测的价值不在"猜对"，在于它制造了「预期」。**
> 只有先有了预期，"预期 − 实际"才能把异常顶出来。
> **题 1 你之所以能立刻记住那个点号，正因为你先写了一个斜杠。**

这是第 7 关以来一直在补的那一课，**本关是第一次真正做到位**。

### ③ ⚠️ 残留进程 —— 第 5 次

这次是**双份**：你的 listener（400 秒）+ 我自己的孤儿（947 秒）。

**两次都是同样的动作缺失**：跑完不收工。

**已固化的动作**：

```bash
ros2 node list                      # 动手之前：必须是空的
ps -eo pid,etimes,args | grep ros2  # 收工之后：几百秒的必是残留
```

**而且这次出了新花样**：残留**不只是污染日志，它直接伪造了数据**
（`/robot2/chatter` 混进了四轮 `ros2 topic list`）。
**症状会变，纪律不能变。**

### ④ ⚠️ 贴输出不分段（第 9 关那条老账，本关**没再犯**）

记一笔好的：本关你贴的日志基本都能看出"这是哪一次运行"。

### ⑤ 本关的环境动作

- 新增 `src/hello_ros/launch/two_robots.launch.py`，**必须重新 build**（§6）。
- 修掉了文件末尾多出来的空行（`W391 blank line at end of file`）——
  `launch/` 下的文件也会被 `test_flake8` 扫到。
  **对拍目标**：`demo.launch.py` 和 `talker.launch.py` 的结尾都是 `])\n`，
  **只有一个换行，没有空行。**

---

## 附：本关命令速记卡

```bash
# ---------- 一次性带命名空间 ----------
ros2 run hello_ros talker --ros-args -r __ns:=/robot1
#                                  ↑ 分水岭：--ros-args 之后的才归 ROS 管

# ---------- 四种名字 ----------
#   chatter     相对名  → /robot1/chatter       （会被加前缀）
#   /chatter    绝对名  → /chatter              （谁都动不了它）
#   ~/x         私有名  → /robot1/talker/x      （多一层节点名）
#   __node      节点名  → /robot1/<新名字>       （它自己也是相对名）
#   ⚠️ 日志名用点号：robot1.talker

# ---------- 重映射 ----------
ros2 run hello_ros talker --ros-args -r chatter:=joint_states
ros2 run hello_ros talker --ros-args -r __ns:=/robot1 -r chatter:=/absolute_topic
#                                     ↑ 左边必须是【展开后的全名】
#                                       在 /robot1 下写 /chatter 会【静默失效】！
#                                       要写 /robot1/chatter 或相对名 chatter

# ---------- 两台机器人（launch）----------
ros2 launch hello_ros two_robots.launch.py
ros2 node list      # /robot1/param_talker /robot1/listener /robot2/...
ros2 topic list     # /robot1/chatter /robot2/chatter

# ---------- ⚠️ bag play 的 -r 不是重映射 ----------
ros2 bag play bag_r2 --remap /robot1/chatter:=/robot2/chatter
#                   ↑ 必须 --remap（或 -m）。-r 是 --rate 倍速！

# ---------- 第 9 关悬案的解药 ----------
ros2 bag play bag_r2 -d 2.0
#                     ↑ 延迟 2 秒开播 = 给 DDS 留配对窗口，
#                       解决"回放开头漏第一条"（§7.6）

# ---------- 排查 ----------
ros2 node list                      # 动手之前：必须是空的
ros2 topic info /话题名              # 0 发布者 + 1 订阅者 = 有人在等一个不会来的消息
ros2 topic info /话题名 --verbose    # 看节点名、看 QoS
ps -eo pid,etimes,args | grep ros2  # 收工之后：etimes 几百秒的必是残留

# ---------- 环境 ----------
colcon build --packages-select hello_ros --symlink-install
#   ⚠️ 新增 launch 文件【必须】重新 build（glob 在 build 那一刻求值）
#   ⚠️ --symlink-install 永远带上（不带会把 editable 降级成拷贝）

# ---------- 测试 ----------
colcon test --packages-select hello_ros
colcon test-result --verbose
```

---

## 相关笔记

- [第 1 关 · 话题](lesson-01-topic.md) —— `talker` / `listener` 就是本关被起了两遍的那两个程序
- [第 3 关 · 参数](lesson-03-parameter.md) —— `param_talker` 的 `message` 参数，本关靠它区分两台机器人
- [第 4 关 · launch](lesson-04-launch.md) —— `Node(...)` 的写法、`glob` 与重新 build 的边界
- [第 8 关 · QoS](lesson-08-qos.md) —— "discovery ≠ match"，本关的 `/robot1/chatter` 上 0 发布者 1 订阅者就是它
- [第 9 关 · ros2 bag](lesson-09-bag.md) —— §7.6 的悬案在本关 §7.6 结案；`-r` 的两种含义也在它那儿
- [专项 01 · 怎么看日志](skill-01-log-reading.md) —— 那个 `robot1.talker` 的点号就出现在日志里
