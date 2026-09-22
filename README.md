# ROS 2 学习工作区

> 系统学习 ROS 2 **核心基础**的练习工作区。
> 路线：话题 → 服务 → 参数 → launch → 动作 → 自定义消息 → 执行器与回调组 → QoS 策略 → ros2 bag → 命名空间与重映射，逐关手写代码 + 实测验证。
> 另有 **C++ 支线**（`rclcpp`），2026-09-13 起步，与 Python 主线并行。

---

## 目录

- [环境](#环境)
- [目录结构](#目录结构)
- [快速开始](#快速开始)
- [课程进度](#课程进度)
- [已有节点](#已有节点)
- [学习笔记](#学习笔记)
- [工作约定](#工作约定)

---

## 环境

| 项 | 版本 |
|---|---|
| 操作系统 | Ubuntu 26.04.1 LTS |
| ROS 2 | **Lyrical**（装在 `/opt/ros/lyrical`） |
| Python | 3.14.4 |
| C++ | g++ 15.2（C++20） |
| CMake | 4.2.3 |
| 构建工具 | `colcon` |
| 包 | `hello_ros`（`ament_python`）、`hello_ros_cpp`（`ament_cmake`）、`hello_ros_interfaces`（`ament_cmake`，自定义消息） |

⚠️ **每个新开的终端都要 source**：

```bash
source /opt/ros/lyrical/setup.bash          # ROS 本体
source ~/ros2_learn_ws/install/setup.bash   # 本工作区
```

忘了第二条 → 报 `Package 'hello_ros' not found`。

> 💡 如果真的忘了，不用关终端重开，直接在当前终端补敲一句就行。

---

## 目录结构

```
ros2_learn_ws/
├── README.md                  ← 你在这里
├── docs/                      ← 课程笔记
│   ├── lesson-01-topic.md            第 1 关 · 话题
│   ├── lesson-02-service.md          第 2 关 · 服务
│   ├── lesson-03-parameter.md        第 3 关 · 参数
│   ├── lesson-04-launch.md           第 4 关 · launch 文件
│   ├── lesson-05-action.md           第 5 关 · 动作
│   ├── lesson-06-custom-message.md   第 6 关 · 自定义消息
│   ├── lesson-07-executor.md         第 7 关 · 执行器与回调组
│   ├── lesson-08-qos.md              第 8 关 · QoS 策略
│   ├── lesson-09-bag.md              第 9 关 · ros2 bag 录包与回放
│   ├── lesson-10-namespace.md        第 10 关 · 命名空间与重映射
│   ├── skill-01-log-reading.md       专项 · 怎么看日志
│   ├── cpp-01-getting-started.md     C++ 支线 · 第一个 rclcpp 节点
│   └── cpp-02-subscriber.md          C++ 支线 · 订阅者（含多字段 / 嵌套消息）
└── src/
    ├── hello_ros/             ← Python 包（ament_python）
    │   ├── package.xml           依赖声明
    │   ├── setup.py              可执行文件注册
    │   ├── launch/               launch 文件
    │   │   ├── talker.launch.py      最小 launch 文件
    │   │   ├── demo.launch.py        起两个节点 + 参数从命令行传
    │   │   └── two_robots.launch.py  两台机器人：namespace 隔离，互不串台
    │   └── hello_ros/
    │       ├── hello_node.py     最小节点：定时打印
    │       ├── talker.py         发布者
    │       ├── listener.py       订阅者
    │       ├── add_server.py     服务端
    │       ├── add_client.py     客户端
    │       ├── param_talker.py   参数化的发布者
    │       ├── fib_server.py     动作服务端（边算边播报 + 支持取消）
    │       ├── fib_client.py     动作客户端（收进度 + 主动叫停）
    │       ├── status_talker.py  发布自定义消息 RobotStatus
    │       ├── status_listener.py 订阅自定义消息 RobotStatus
    │       ├── mode_server.py    提供自定义服务 SetMode
    │       ├── mode_client.py    调用自定义服务 SetMode
    │       ├── group_demo.py     执行器与回调组实验（慢订阅者 + 定时器争"锁"）
    │       └── qos_talker.py     QoS 实验：TRANSIENT_LOCAL 发布者（发 5 条后停发但不退出）
    ├── hello_ros_interfaces/  ← 接口包（ament_cmake）· 只定义合同，不含逻辑
    │   ├── package.xml           依赖声明
    │   ├── CMakeLists.txt        rosidl_generate_interfaces 登记表
    │   ├── msg/
    │   │   └── RobotStatus.msg       话题合同：机器人状态
    │   └── srv/
    │       └── SetMode.srv           服务合同：切换模式
    └── hello_ros_cpp/         ← C++ 包（ament_cmake）
        ├── package.xml           依赖声明
        ├── CMakeLists.txt        编译与安装规则
        └── src/
            ├── hello_cpp.cpp     最小节点：定时打印（C++ 版）
            └── talker.cpp        发布者（C++ 版）
```

> 💡 **接口为什么要单独一个包？** 它只定义**合同**，不含逻辑。`hello_ros`（Python）和
> `hello_ros_cpp`（C++）都依赖它 —— **合同不该归属于任何一方**。详见
> [lesson-06 §2.5](docs/lesson-06-custom-message.md)。

构建产物 `build/` `install/` `log/` 已在 `.gitignore` 里，不会进版本库。

---

## 快速开始

### 构建

```bash
cd ~/ros2_learn_ws
colcon build --symlink-install      # 三个包一起
source install/setup.bash

# 只想编一个包
colcon build --packages-select hello_ros_interfaces             # 接口包（自定义消息）
colcon build --packages-select hello_ros --symlink-install      # Python 包
colcon build --packages-select hello_ros_cpp                    # C++ 包
```

> ⚠️ **`hello_ros` 依赖 `hello_ros_interfaces`。** 接口包没 build 过就单独编 `hello_ros`，
> 会在 `import` 时报 `No module named 'hello_ros_interfaces'` —— 而且 **build 本身是绿灯的**
> （"构建成功"和"能用"是两件事）。见 [lesson-06 §8 坑 7](docs/lesson-06-custom-message.md)。

> **`--symlink-install` 是什么？** 让 `install/` 里放软链接指回 `src/`，这样**只改 `.py` / launch 文件的内容时不用重新 build**。
>
> ⚠️ 边界 1：改了 `setup.py` 或 `package.xml`（加可执行文件、加依赖）**还是必须重新 build**——那改的是"装什么"，不是"装的内容"。
>
> ⚠️ 边界 2：**新增**一个 launch 文件也必须重新 build。`glob('launch/*.launch.py')` 是在 build 那一刻执行的，当时的清单里没有新文件。详见 [lesson-04 §7.3](docs/lesson-04-launch.md)。
>
> ⚠️ 边界 3：**C++ 包对 `--symlink-install` 没有依赖** —— 产物是编译出来的二进制，`.cpp` 改了**必须重编**。

### 跑起来看看

```bash
# 终端 A
ros2 run hello_ros hello_node

# 终端 B（观察）
ros2 node list
```

### 清理残留进程

```bash
pkill -f "hello_ros"
```

> ⚠️ **`pkill -f` 匹配的是「命令行文本」，不是「节点名」。**
> 所以在**写成一行**的命令里，它还会匹配到**你自己这条命令**，把自己那个 shell 杀掉
> （症状：终端莫名退出，退出码 144）。
>
> 想避开自匹配，把关键词拆开写：
>
> ```bash
> P="qos""_talker"; ps -eo pid,etimes,args | grep -F "$P" | grep -v grep | awk '{print $1}' | xargs -r kill
> ```
>
> `etimes` 那一列是"这个进程已经活了**多少秒**" —— **几百秒的一眼就是残留**。

**⭐ 做实验之前先确认环境是干净的**：

```bash
ros2 topic info /qos_hist      # 期望：Unknown topic '/qos_hist'
```

看到 `Publisher count: 1` 就说明还有旧进程活着 ——
这时你测的**不是你以为的那个东西**，日志会变成两个进程交错的垃圾，而且**完全不报错**。
详见 [lesson-08 §8 坑 3](docs/lesson-08-qos.md)。

---

## 课程进度

> 完整进度与教学记录见会话记忆；这里只列课程表。

| # | 关卡 | 状态 | 笔记 |
|:-:|---|:-:|---|
| 1 | 话题 Topic | ✅ 已完成 | [lesson-01-topic.md](docs/lesson-01-topic.md) |
| 2 | 服务 Service | ✅ 已完成 | [lesson-02-service.md](docs/lesson-02-service.md) |
| 3 | 参数 Parameter | ✅ 已完成 | [lesson-03-parameter.md](docs/lesson-03-parameter.md) |
| 4 | launch 文件 | ✅ 已完成 | [lesson-04-launch.md](docs/lesson-04-launch.md) |
| 5 | 动作 Action | ✅ 已完成 | [lesson-05-action.md](docs/lesson-05-action.md) |
| 6 | 自定义消息 `.msg` / `.srv` | ✅ 已完成 | [lesson-06-custom-message.md](docs/lesson-06-custom-message.md) |
| 7 | 执行器与回调组 | ✅ 已完成 | [lesson-07-executor.md](docs/lesson-07-executor.md) |
| 8 | QoS 策略 | ✅ 已完成 | [lesson-08-qos.md](docs/lesson-08-qos.md) |
| 9 | ros2 bag 录包与回放 | ✅ 已完成 | [lesson-09-bag.md](docs/lesson-09-bag.md) |
| 10 | 命名空间与重映射 | ✅ 已完成 | [lesson-10-namespace.md](docs/lesson-10-namespace.md) |

**C++ 支线**（2026-09-13 起，与主线并行）

| # | 内容 | 状态 | 笔记 |
|---|---|---|---|
| 1 | 用 rclcpp 写第一个节点 / 发布者 | ✅ 已完成 | [cpp-01-getting-started.md](docs/cpp-01-getting-started.md) |
| 2 | 订阅者：`listener.cpp` + 多字段/嵌套消息的 `status_listener.cpp` | ✅ 已完成 | [cpp-02-subscriber.md](docs/cpp-02-subscriber.md) |

---

## 已有节点

### Python 包 `hello_ros`

全部在 `src/hello_ros/setup.py` 的 `entry_points` 里注册过，可以直接 `ros2 run`。

| 可执行名 | 来源 | 作用 | 验证命令 |
|---|---|---|---|
| `hello_node` | [hello_node.py](src/hello_ros/hello_ros/hello_node.py) | 最小节点，每秒打印一次心跳 | `ros2 run hello_ros hello_node` |
| `talker` | [talker.py](src/hello_ros/hello_ros/talker.py) | 发布者，每秒往 `/chatter` 发一条 | `ros2 topic echo /chatter` |
| `listener` | [listener.py](src/hello_ros/hello_ros/listener.py) | 订阅者，收到 `/chatter` 就打印 | 先跑 `talker` 再跑它 |
| `add_server` | [add_server.py](src/hello_ros/hello_ros/add_server.py) | 服务端，提供 `add_two_ints` 加法服务 | `ros2 service call /add_two_ints example_interfaces/srv/AddTwoInts "{a: 3, b: 4}"` |
| `add_client` | [add_client.py](src/hello_ros/hello_ros/add_client.py) | 客户端，调用加法服务 | 先跑 `add_server` 再跑它 |
| `param_talker` | [param_talker.py](src/hello_ros/hello_ros/param_talker.py) | 参数化发布者，发什么/多快/几条都能改 | `ros2 param set /param_talker message 世界` |
| `fib_server` | [fib_server.py](src/hello_ros/hello_ros/fib_server.py) | 动作服务端，算斐波那契，每秒播报一次进度，可中途取消 | `ros2 action send_goal /fibonacci example_interfaces/action/Fibonacci "{order: 8}" --feedback` |
| `fib_client` | [fib_client.py](src/hello_ros/hello_ros/fib_client.py) | 动作客户端，收进度并在第 3 条时主动叫停 | 先跑 `fib_server` 再跑它 |
| `status_talker` | [status_talker.py](src/hello_ros/hello_ros/status_talker.py) | 发布自定义消息 `RobotStatus` 到 `/robot_status` | `ros2 topic echo /robot_status` |
| `status_listener` | [status_listener.py](src/hello_ros/hello_ros/status_listener.py) | 订阅 `/robot_status` 并打印各字段 | 先跑 `status_talker` 再跑它 |
| `mode_server` | [mode_server.py](src/hello_ros/hello_ros/mode_server.py) | 服务端，提供自定义服务 `set_mode`（只接受 0/1/2） | `ros2 service call /set_mode hello_ros_interfaces/srv/SetMode "{mode: 5}"` |
| `mode_client` | [mode_client.py](src/hello_ros/hello_ros/mode_client.py) | 客户端，调用 `set_mode` 并打印响应两个字段 | 先跑 `mode_server` 再跑它 |
| `group_demo` | [group_demo.py](src/hello_ros/hello_ros/group_demo.py) | **实验节点**：一个睡 2 秒的慢订阅者 + 一个 0.5 秒定时器，用来观察回调组怎么分配"锁" | `ros2 run hello_ros group_demo`（另开终端再跑 `talker` 触发慢回调） |
| `qos_talker` | [qos_talker.py](src/hello_ros/hello_ros/qos_talker.py) | **实验节点**：`TRANSIENT_LOCAL` 发布者，发 5 条后**停发但不退出** —— 让晚来的订阅者能看到"历史" | `ros2 run hello_ros qos_talker --ros-args -p depth:=2`（另开终端再 `ros2 topic echo` 看收到几条） |

### 接口包 `hello_ros_interfaces`

**不是节点，是合同。** 只定义 `.msg` / `.srv`，代码全部由 `rosidl` 生成。

| 接口 | 内容 | 查看命令 |
|---|---|---|
| [RobotStatus.msg](src/hello_ros_interfaces/msg/RobotStatus.msg) | `string robot_name` / `float32 battery` / `int32 mode` / `bool emergency` / `geometry_msgs/Point position`（**嵌套**） | `ros2 interface show hello_ros_interfaces/msg/RobotStatus` |
| [SetMode.srv](src/hello_ros_interfaces/srv/SetMode.srv) | 请求 `int32 mode` ／ 响应 `bool success` + `string message` | `ros2 interface show hello_ros_interfaces/srv/SetMode` |

> 💡 改了 `.msg` / `.srv` **必须重新 build**（`--symlink-install` 免不掉 —— 它要**生成代码**）。
> 这跟 `.py` 相反（`.py` 走软链，改完只要重启节点）。

### launch 文件

不是节点，是"一次起多个节点"的脚本。用 `ros2 launch <包名> <文件名>` 运行。

| launch 文件 | 作用 | 验证命令 |
|---|---|---|
| [talker.launch.py](src/hello_ros/launch/talker.launch.py) | 最小 launch 文件：起一个 `talker` | `ros2 launch hello_ros talker.launch.py` |
| [demo.launch.py](src/hello_ros/launch/demo.launch.py) | 起 `param_talker` + `listener`，参数从命令行传 | `ros2 launch hello_ros demo.launch.py period:=0.5 message:=你好` |
| [two_robots.launch.py](src/hello_ros/launch/two_robots.launch.py) | 起**两台机器人**：同名节点各带 `namespace`，互不串台 | `ros2 launch hello_ros two_robots.launch.py` |

> 💡 `ros2 launch hello_ros demo.launch.py -s` 可以列出这个 launch 文件声明了哪些参数。

### C++ 包 `hello_ros_cpp`

在 `src/hello_ros_cpp/CMakeLists.txt` 里用 `add_executable` + `install` 注册。

| 可执行名 | 来源 | 作用 | 验证命令 |
|---|---|---|---|
| `hello_cpp` | [hello_cpp.cpp](src/hello_ros_cpp/src/hello_cpp.cpp) | 最小节点（C++ 版），每秒打印一次心跳 | `ros2 run hello_ros_cpp hello_cpp` |
| `talker` | [talker.cpp](src/hello_ros_cpp/src/talker.cpp) | 发布者（C++ 版），每秒往 `/chatter` 发一条 | `ros2 topic echo /chatter` |
| `listener` | [listener.cpp](src/hello_ros_cpp/src/listener.cpp) | 订阅者（C++ 版），订阅 `/chatter` | 先跑 `hello_ros_cpp talker` |
| `status_listener` | [status_listener.cpp](src/hello_ros_cpp/src/status_listener.cpp) | 订阅 `/robot_status`，打印 4 个字段（含嵌套的 `position.x`） | 先跑 `hello_ros status_talker` |

> 💡 `hello_ros_cpp talker` 和 `hello_ros talker` 发的是**同一个话题** `/chatter`，
> 所以可以拿 `hello_ros_cpp talker` + `hello_ros listener` 直接验证**跨语言互操作**。

### 典型组合

```bash
# 话题：两个终端
ros2 run hello_ros talker       # 终端 A
ros2 run hello_ros listener     # 终端 B

# 服务：两个终端
ros2 run hello_ros add_server   # 终端 A
ros2 run hello_ros add_client   # 终端 B → 打印 3 + 4 = 7

# 参数：启动时覆盖 + 运行时改
ros2 run hello_ros param_talker --ros-args -p message:=你好 -p period:=0.5   # 终端 A
ros2 param set /param_talker message 世界                                    # 终端 B

# 动作：两个终端（服务端要加 MultiThreadedExecutor，否则取消请求进不来，见笔记 §2.5）
ros2 run hello_ros fib_server   # 终端 A
ros2 run hello_ros fib_client   # 终端 B → 收 3 条进度后主动叫停，状态 5 = CANCELED

# 动作：不用写客户端，直接用 CLI 发目标并看进度
ros2 run hello_ros fib_server   # 终端 A
ros2 action send_goal /fibonacci example_interfaces/action/Fibonacci "{order: 8}" --feedback   # 终端 B（Ctrl-C 可取消）

# launch：一条命令起两个节点
ros2 launch hello_ros demo.launch.py period:=0.5 message:=你好

# 跨语言互操作：C++ 发，Python 收（能通，只跟话题名和消息类型有关）
ros2 run hello_ros_cpp talker   # 终端 A（C++）
ros2 run hello_ros listener     # 终端 B（Python）

# 跨语言互操作：C++ 发，C++ 收（同语言，走同一个话题）
ros2 run hello_ros_cpp talker     # 终端 A
ros2 run hello_ros_cpp listener   # 终端 B → 收到：第1次心跳……

# ⭐ 跨语言互操作：Python 发，C++ 收（多字段 + 嵌套消息）
ros2 run hello_ros status_talker     # 终端 A（Python）
ros2 run hello_ros_cpp status_listener   # 终端 B（C++）→ 收到: r2d2 电量=65.0 mode=1 x=7.0

# 自定义消息：两个终端
ros2 run hello_ros status_talker     # 终端 A
ros2 run hello_ros status_listener   # 终端 B → 收到 r2d2 电量=85.0 mode=0 x=3.0

# 自定义服务：两个终端
ros2 run hello_ros mode_server                                          # 终端 A
ros2 run hello_ros mode_client                                          # 终端 B → mode=2，success=True
ros2 service call /set_mode hello_ros_interfaces/srv/SetMode "{mode: 5}"  # 越界 → success=False

# 执行器与回调组：两个终端（先起 group_demo，再起 talker 触发慢回调）
ros2 run hello_ros group_demo   # 终端 A
ros2 run hello_ros talker       # 终端 B → 慢回调睡 2 秒，看定时器有没有被挡住

# QoS：两个终端（先起发布者，等它发完 5 条，再起订阅者看"历史"）
ros2 run hello_ros qos_talker --ros-args -p depth:=2   # 终端 A → 发完 第1~5 条后停住不退
ros2 topic echo --qos-reliability reliable --qos-durability transient_local --qos-depth 5 \
  /qos_hist std_msgs/msg/String                        # 终端 B → 只有 2 条：第4条、第5条
#   ⚠️ 两个 QoS 参数都要给 —— `ros2 topic echo` 默认是 BEST_EFFORT，只给 durability 收不到历史
#   ⚠️ 实验前先 `ros2 topic info /qos_hist` 确认是 Unknown topic（防残留进程）

# 接口本身（不需要任何节点）
ros2 interface package hello_ros_interfaces
ros2 interface show hello_ros_interfaces/srv/SetMode
```

---

## 学习笔记

**关卡笔记**每关一份，结构固定：**目标 → 核心概念 → 完整代码 → API 速查 → CLI 速查 → 构建运行 → 实测现象 → 踩坑记录 → 自测题**。

**专项笔记**（`skill-NN-*`）是方法课，不占关卡编号：**为什么有这一课 → 核心概念 → 方法 → 实战训练 → 工具速查 → 踩坑 → 自测题**。

| 笔记 | 主要内容 |
|---|---|
| [第 1 关 · 话题](docs/lesson-01-topic.md) | 发布者/订阅者、回调与 executor、话题的多对多、QoS volatile 与历史消息、CLI 工具也是节点 |
| [第 2 关 · 服务](docs/lesson-02-service.md) | 请求/响应、`request`/`response` 的"盒子 vs 字段"、`future`、隐藏节点机制、服务端不可用的两种情况、服务回调串行 |
| [第 3 关 · 参数](docs/lesson-03-parameter.md) | `declare` 注册 vs `get` 读取、参数改了谁自动跟上（现读 vs 焊死）、校验回调的三个必答点、只读参数、节点自带参数、启动 `-p` 绕过回调 |
| [第 4 关 · launch](docs/lesson-04-launch.md) | launch 文件是 Python 脚本不是配置文件、`Node` 同名不同物、`DeclareLaunchArgument`/`LaunchConfiguration`、`data_files` 的二元组、`--symlink-install` 到底免掉什么、**绿灯 ≠ 做了你想做的事** |
| [第 5 关 · 动作](docs/lesson-05-action.md) | 动作 = 3 服务 + 2 话题拼出来的、Goal/Feedback/Result 三段式、**服务端 handle "宣布" vs 客户端 handle "请求"**、执行器那一层决定取消能不能生效、回调式客户端的三个钩子、两处"信封→盒子"、checkpoint 位置决定语义 |
| [第 6 关 · 自定义消息](docs/lesson-06-custom-message.md) | **`.msg` 是合同不是代码**（5 行文本 → Python/C++/IDL/JSON 四种产物）、**三张登记表**（文件在磁盘上 ≠ 被注册了）、`.srv` 的 `---` 必须只有三个减号、嵌套消息的两处 `DEPENDENCIES`、接口为什么单独一个包、**静默 bug #4：`if x == 0 or 1 or 2` 恒真**、改了 `.py` 不重启节点 = 白改 |
| [第 7 关 · 执行器与回调组](docs/lesson-07-executor.md) | **执行器决定"有几只手"，回调组决定"第二只手能不能拿同一把锁"**、默认组 = 全局串行、**⭐ `execute_callback` 是裸任务不挂任何回调组**（源码 `server.py:686`）、**订正第 5 关**的 2×2 矩阵、三路对照表、**可重入组是"允许重叠"不是"允许并行"**、定时器不排队（错过的拍子丢掉）、日志时间戳是 Unix 纪元秒 |
| [第 8 关 · QoS 策略](docs/lesson-08-qos.md) | **QoS 是两边各报要求、DDS 在中间配对**、三条策略（Reliability / Durability / History）、**⭐ 唯一的兼容规则：发布者提供 ≥ 订阅者要求（是 ≥ 不是 =）**、不兼容的三副面孔（**收不到 + 两边各一条 WARN + `topic info` 照样 `1 / 1`**）、**`TRANSIENT_LOCAL` 的"历史"是发布者进程内存里的抽屉**、`transient` 不是持久化、**迟到订阅者要拿到就清 `topic info` 必须是 `Unknown topic`**、⭐ 订正第 1 关"必须先起 talker"的旧账 |
| [第 9 关 · ros2 bag](docs/lesson-09-bag.md) | **`record` 是个订阅者、`play` 是个发布者**（bag 不是新通信机制）、bag 是**目录**不是文件、**⭐ `Duration` 量的是"第一条到最后一条"不是"录了多久"**（N 条 = N−1 个间隔）、**⭐⭐ 判据实验：只改 `--qos-durability` 一个词 → 5 条 vs 0 条**、**历史没有时间戳**（5 条挤在 30 微秒）、2262 年 int64 哨兵值、**空包的三副面孔**、`play -r` 只改播放速度、**未解之谜：回放开头可能漏第一条** |
| [第 10 关 · 命名空间与重映射](docs/lesson-10-namespace.md) | **命名空间是运行时的字符串前缀**（代码一个字不改）、**四种名字**（相对 `chatter` / 绝对 `/chatter` / 私有 `~/x` / 节点名 `__node`）各自加不加前缀、**⭐ 日志名用 `.` 不用 `/`**（`rcutils/logging.h:37`）、**⭐⭐ 重映射左边必须写「展开后的全名」——写错【不报错，只是什么都不做】**、C/D/E/F 四格对照、`-r` 在 `ros2 run` 是 remap 但在 **`ros2 bag play` 是 `--rate`**、bag 存的是**全名**、**⭐⭐ 破第 9 关悬案：`-d` 是 DDS 配对窗口**（基线 2/9 → 加 `-d` 15/15） |
| [专项 01 · 怎么看日志](docs/skill-01-log-reading.md) | **仪式行 vs 业务行**、看日志 = 预期 − 实际、**对表法**、**先描述再解释**、三层防线（行数/内容/数值）、`grep \| cat -n` 挑业务行、`diff` 自动对表、残留进程会让日志变成垃圾 |
| [C++ 支线 01](docs/cpp-01-getting-started.md) | 为什么单开一个包、Python ↔ C++ 对照表、`<>` 里的类型、成员变量类型怎么定、`[this]()` lambda、`RCLCPP_INFO` 占位符、CMake 的点名制、跨语言互操作 |
| [C++ 支线 02](docs/cpp-02-subscriber.md) | 订阅者的完整形状（消息类型从"第 1 个参数"挪进 `<>`）、⭐ lambda 是"适配器"（定时器收空、订阅者收 msg）、**⭐⭐ 成员变量 4 块结构 `rclcpp::<角色><消息类型>::SharedPtr`**、`.` vs `->` 剥盒子、**格式符按位置对（错位只给 warning，build 全绿但打印垃圾）**、`%f` 默认 6 位小数、CMake 新增可执行文件的 **4 处**、**实测：嵌套消息不用显式 find 依赖**、跨语言逐字段一致 |

> 📖 复习建议：每份笔记的 **§7「实测现象与结论」** 和 **§9「自测题」** 是重点。自测题答案默认折叠，**先自己答一遍再点开**。

---

## 工作约定

### 代码风格

- **Python 包**：用 `Pylance` 做类型检查，包内自带 `flake8` / `mypy` / `pep257` 测试
- **C++ 包**：用 4 空格缩进 + 大括号独占一行（Allman 风格），**与 Python 侧保持一致**。
  ROS 官方的 C++ 风格是 2 空格 + 大括号跟行，`ament_lint_auto` 自带的 `uncrustify` 检查的就是这个。
  本包**有意关掉了 `uncrustify`**（见 `CMakeLists.txt` 里的注释）—— 这是个手写练习包，统一风格比贴合 ROS 风格更重要。
  哪天想切换，把那一行注释掉即可。

  ```bash
  colcon test --packages-select hello_ros       # Python 包
  colcon test --packages-select hello_ros_cpp   # C++ 包
  ```

### 编辑器

`.vscode/settings.json` 里**刻意关闭了全部自动补全**（12 项配置），目的是**手写代码练手**。

- 需要补全时按 `Ctrl+Space` 仍可手动唤出
- `editor.hover`（鼠标悬停看文档）**有意保留**
- ⚠️ 这不是配置错误，**不要"修"它**

### 测试

```bash
colcon test --packages-select hello_ros hello_ros_cpp   # ① 执行
colcon test-result --verbose                            # ② 查看（不执行就只会看到旧报告）
```

**Python 包 `hello_ros`**：**5 tests, 0 errors, 0 failures, 1 skipped —— 全绿** ✅
（`test_xmllint` 也会通过，但要等几分钟，原因见下方环境问题）

| 测试 | 查什么 |
|---|---|
| `test_flake8` | 代码风格（`ament_flake8.ini`，行宽 99，import 按 google 风格排序） |
| `test_pep257` | docstring（⚠️ 中文句号 `。` 不算标点，结尾要用半角 `.`） |
| `test_mypy` | 类型标注 |
| `test_xmllint` | `package.xml` 的 XML 是否合法 |
| `test_copyright` | 版权头（**跳过**，本项目没启用） |

**C++ 包 `hello_ros_cpp`**：`cppcheck` / `lint_cmake` 通过；`cpplint`、`copyright`、`uncrustify` **有意关闭**；
`xmllint` **当前失败**（⚠️ 网络环境问题，跟代码无关，见下）

**接口包 `hello_ros_interfaces`**：`lint_cmake` 通过；`xmllint` **当前失败**（⚠️ 同一个网络问题，
它是 `ament_cmake` 包，走 ctest，默认 60 秒超时 —— 和 `hello_ros_cpp` 一模一样）

> ⚠️ **`xmllint` 在这台机器上会因为网络问题失败**，跟代码无关。原因已查明：
>
> 1. `ament_xmllint` 每次运行都要从 `download.ros.org` 下 XSD 校验文件
> 2. 这台机器 **IPv6 是黑洞的**：`getaddrinfo` 先返回 IPv6 地址，连过去**没有报错也不回包**，就那么挂着
> 3. Python 的 `urllib` **没设超时**，所以一直等下去（实测 ~400 秒才轮到 IPv4，然后 0.7 秒就下完了）
> 4. `hello_ros` 的 `test_xmllint` 是 pytest 跑的，没超时限制 → 慢，但**最终通过**
> 5. `hello_ros_cpp` 的 `xmllint` 是 ctest 跑的，**默认 60 秒超时** → 每次都失败
>
> **修法**（一次生效，需要 sudo，改的是系统配置 `/etc/gai.conf`，改完可随时改回来）：
>
> ```bash
> # /etc/gai.conf 第 54 行本来就是给这种情况准备的，取消注释即可
> sudo sed -i 's/^#precedence ::ffff:0:0\/96  100/precedence ::ffff:0:0\/96  100/' /etc/gai.conf
> ```
>
> 改完再跑 `colcon test`，两个包的 `xmllint` 都会秒过。
> 想撤销就把那行前面加回 `#`。
>
> 暂时不想动系统配置的话，可以先跳过这条：
>
> ```bash
> colcon test --packages-select hello_ros_cpp --ctest-args -E xmllint
> ```

### 待办

- [x] ~~`package.xml` 的 `<description>` / `<license>` 占位~~（2026-09-12 已补：Apache-2.0）
- [x] ~~清理源码里练习时的 `# TODO n：...` 注释~~（2026-09-12 已清）
- [x] ~~把 `src/hello_ros_cpp/src/talker.cpp` 里两处 `"..."` 占位符换成真正的内容~~（2026-09-13 已补，跨语言验收通过）
- [x] ~~清理 `fib_server.py` / `fib_client.py` 里练习时的 `# TODO n：...` 注释~~（2026-09-15 已清，`colcon test` 全绿）
- [x] ~~给 `hello_ros_interfaces/package.xml` 补 `<description>`~~（2026-09-16 已补）
- [x] ~~清理第 6 关 4 个节点的 `# TODO n：...` 注释 + 5 处 flake8 风格问题~~（2026-09-16 已清，`flake8` / `pep257` / `mypy` 全过）
- [x] ~~清理 `qos_talker.py` 里练习时的 `# TODO n：...` 注释 + 第 3 行的 flake8 问题~~（2026-09-18 已清，`flake8` 全包干净）
- [x] ~~写 `docs/lesson-08-qos.md`~~（2026-09-18 已写，10 节完整结构 + 6 道自测题）。
      素材来源：兼容性四格矩阵、抽屉容量表、判据实验全部为课堂实测；
      踩坑记录四条为 ① 把 API 速查表当填空答案 ② `self.HistoryPolicy` 名字挂错人 ③ 残留进程污染实验（**栽了 3 次**）④ 我自己把输出重定向到 `/dev/null` 后误判"不兼容是静默的"
- [x] ~~写 `docs/lesson-07-executor.md`~~（2026-09-17 已写，10 节完整结构 + 6 道自测题）。
      素材来源：三路对照表和"两个决定"脱胎于 [group_demo.py](src/hello_ros/hello_ros/group_demo.py) 顶部注释；
      踩坑记录四条为 ① 敲错命令名 `fid_server` ② `cb_slow` 函数体是空的 ③ 没起发布者导致回调从没被触发 ④ 残留进程污染实验
- [x] ~~（可选）**C++ 节点用这个接口**~~（2026-09-19 已完成 → [status_listener.cpp](src/hello_ros_cpp/src/status_listener.cpp)，
      Python `status_talker` 发 / C++ 收，逐字段一致；笔记 [cpp-02-subscriber.md](docs/cpp-02-subscriber.md)）
- [x] ~~写 `docs/lesson-09-bag.md`~~（2026-09-21 已写，10 节完整结构 + 6 道自测题）。
      **本关没有新代码，是九关里唯一一关纯 CLI 的**；
      素材来源：判据实验（TL → 5 条 / volatile → 0 条）、`Duration` 公式、`bag_tl` 的 30 微秒、
      2262 年哨兵值、三次回放 12/12/11 全部为实测；
      踩坑记录六条为 ① 这版 `record` 不接位置参数 ② **我自己造题时栽的 `-w 0`**（`-t` 默认把 `-w` 变成 1，两轮都录到 5 条）③ 非 tty 下只认 SIGTERM ④ 废题的形状（发布者已死 → 0 条证明不了任何事）⑤ **我自己栽的** `ls -l <目录>/` 跟软链进去 ⑥ 不带 `--symlink-install` 的 build 会把 editable 安装降级成拷贝
- [x] ~~写 `docs/lesson-10-namespace.md`~~（2026-09-22 已写，10 节完整结构 + 7 道自测题）。
      **本关只新写了一个 launch 文件**（[two_robots.launch.py](src/hello_ros/launch/two_robots.launch.py)），
      其余全是 CLI；
      素材来源：`__ns` 三处名字（节点 / 话题 / **日志名用点号**）、C/D/E/F 四格重映射对照、
      两台机器人零串台、`remappings` 加错对象导致**全静音**（`Publisher count: 0`）、
      `bag_r1` 空包 / `bag_r2` 14 条、`--remap` 13 条 vs `-r __ns:=/robot1` 14 条，全部为实测；
      踩坑记录五条为 ① **我自己预测错的** `ros2 bag play -r` 其实是 `--rate` ② 重映射加到了两个节点上 ③ 忘了删 remappings 录出空包 ④ 残留 listener 污染四轮数据 ⑤ **我自己栽的** `timeout` 杀父进程留下 947 秒孤儿节点
- [ ] （可选）`docs/cpp-03-*.md`：C++ 版**发布者** —— 用 C++ 写 `status_talker`，
      把 `.` 和 `->` 的**赋值**方向也走一遍（`msg->position.x = ...`），补上 cpp-02 §9.2 题 ④
- [ ] （可选）按上面 `xmllint` 那节修一下 `/etc/gai.conf`

---

**当前进度：第 1～10 关全部完成（核心基础十关走完一轮）＋ C++ 支线 01 / 02 完成 ——
C++ 侧已经能读话题、收自定义多字段消息，并且和 Python 节点双向互通；
第 9 关第一次把数据冻结到磁盘上，也第一次让你亲手用「判据」把一个悬空的结论钉死；
第 10 关让同一份代码起了两遍而互不打架，并且把第 9 关那个悬案从「现象」钉成了「病因」。**

**下一步：①（可选）C++ 版发布者 `status_talker`（补 `.` / `->` 的赋值方向）；②（可选）把 action / service 也接到 C++ 支线；③ 第 7 / 第 8 / 第 10 关 §9.2 的加练题（第 10 关那 6 道里，第 1 题「`__ns` 给两次」和第 6 题「给 recorder 加命名空间」最有挖头）；④ 核心基础十关已走完一轮，下一关可考虑 composition（组件与多节点同进程）或 parameter callback 深挖。**
