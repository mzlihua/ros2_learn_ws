# ROS 2 学习工作区

> 系统学习 ROS 2 **核心基础**的练习工作区。
> 路线：话题 → 服务 → 参数 → launch → 动作 → 自定义消息，逐关手写代码 + 实测验证。
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
| 包 | `hello_ros`（`ament_python`）、`hello_ros_cpp`（`ament_cmake`） |

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
│   └── cpp-01-getting-started.md     C++ 支线 · 第一个 rclcpp 节点
└── src/
    ├── hello_ros/             ← Python 包（ament_python）
    │   ├── package.xml           依赖声明
    │   ├── setup.py              可执行文件注册
    │   ├── launch/               launch 文件
    │   │   ├── talker.launch.py      最小 launch 文件
    │   │   └── demo.launch.py        起两个节点 + 参数从命令行传
    │   └── hello_ros/
    │       ├── hello_node.py     最小节点：定时打印
    │       ├── talker.py         发布者
    │       ├── listener.py       订阅者
    │       ├── add_server.py     服务端
    │       ├── add_client.py     客户端
    │       └── param_talker.py   参数化的发布者
    └── hello_ros_cpp/         ← C++ 包（ament_cmake）
        ├── package.xml           依赖声明
        ├── CMakeLists.txt        编译与安装规则
        └── src/
            ├── hello_cpp.cpp     最小节点：定时打印（C++ 版）
            └── talker.cpp        发布者（C++ 版）
```

构建产物 `build/` `install/` `log/` 已在 `.gitignore` 里，不会进版本库。

---

## 快速开始

### 构建

```bash
cd ~/ros2_learn_ws
colcon build --symlink-install      # 两个包一起
source install/setup.bash

# 只想编一个包
colcon build --packages-select hello_ros --symlink-install      # Python 包
colcon build --packages-select hello_ros_cpp                    # C++ 包
```

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

---

## 课程进度

> 完整进度与教学记录见会话记忆；这里只列课程表。

| # | 关卡 | 状态 | 笔记 |
|:-:|---|:-:|---|
| 1 | 话题 Topic | ✅ 已完成 | [lesson-01-topic.md](docs/lesson-01-topic.md) |
| 2 | 服务 Service | ✅ 已完成 | [lesson-02-service.md](docs/lesson-02-service.md) |
| 3 | 参数 Parameter | ✅ 已完成 | [lesson-03-parameter.md](docs/lesson-03-parameter.md) |
| 4 | launch 文件 | ✅ 已完成 | [lesson-04-launch.md](docs/lesson-04-launch.md) |
| 5 | 动作 Action | ⬜ 未开始 | — |
| 6 | 自定义消息 `.msg` / `.srv` | ⬜ 未开始 | — |

**C++ 支线**（2026-09-13 起，与主线并行）

| # | 内容 | 状态 | 笔记 |
|:-:|---|:-:|---|
| 1 | 用 rclcpp 写第一个节点 / 发布者 | 🚧 进行中 | [cpp-01-getting-started.md](docs/cpp-01-getting-started.md) |

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

### launch 文件

不是节点，是"一次起多个节点"的脚本。用 `ros2 launch <包名> <文件名>` 运行。

| launch 文件 | 作用 | 验证命令 |
|---|---|---|
| [talker.launch.py](src/hello_ros/launch/talker.launch.py) | 最小 launch 文件：起一个 `talker` | `ros2 launch hello_ros talker.launch.py` |
| [demo.launch.py](src/hello_ros/launch/demo.launch.py) | 起 `param_talker` + `listener`，参数从命令行传 | `ros2 launch hello_ros demo.launch.py period:=0.5 message:=你好` |

> 💡 `ros2 launch hello_ros demo.launch.py -s` 可以列出这个 launch 文件声明了哪些参数。

### C++ 包 `hello_ros_cpp`

在 `src/hello_ros_cpp/CMakeLists.txt` 里用 `add_executable` + `install` 注册。

| 可执行名 | 来源 | 作用 | 验证命令 |
|---|---|---|---|
| `hello_cpp` | [hello_cpp.cpp](src/hello_ros_cpp/src/hello_cpp.cpp) | 最小节点（C++ 版），每秒打印一次心跳 | `ros2 run hello_ros_cpp hello_cpp` |
| `talker` | [talker.cpp](src/hello_ros_cpp/src/talker.cpp) | 发布者（C++ 版），每秒往 `/chatter` 发一条 | `ros2 topic echo /chatter` |

⚠️ `talker.cpp` 里两处占位符 `"..."` 还没填（见 [cpp-01 笔记](docs/cpp-01-getting-started.md) 末尾「待办」）。

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

# launch：一条命令起两个节点
ros2 launch hello_ros demo.launch.py period:=0.5 message:=你好

# 跨语言互操作：C++ 发，Python 收（能通，只跟话题名和消息类型有关）
ros2 run hello_ros_cpp talker   # 终端 A（C++）
ros2 run hello_ros listener     # 终端 B（Python）
```

---

## 学习笔记

每关一份，结构固定：**目标 → 核心概念 → 完整代码 → API 速查 → CLI 速查 → 构建运行 → 实测现象 → 踩坑记录 → 自测题**。

| 笔记 | 主要内容 |
|---|---|
| [第 1 关 · 话题](docs/lesson-01-topic.md) | 发布者/订阅者、回调与 executor、话题的多对多、QoS volatile 与历史消息、CLI 工具也是节点 |
| [第 2 关 · 服务](docs/lesson-02-service.md) | 请求/响应、`request`/`response` 的"盒子 vs 字段"、`future`、隐藏节点机制、服务端不可用的两种情况、服务回调串行 |
| [第 3 关 · 参数](docs/lesson-03-parameter.md) | `declare` 注册 vs `get` 读取、参数改了谁自动跟上（现读 vs 焊死）、校验回调的三个必答点、只读参数、节点自带参数、启动 `-p` 绕过回调 |
| [第 4 关 · launch](docs/lesson-04-launch.md) | launch 文件是 Python 脚本不是配置文件、`Node` 同名不同物、`DeclareLaunchArgument`/`LaunchConfiguration`、`data_files` 的二元组、`--symlink-install` 到底免掉什么、**绿灯 ≠ 做了你想做的事** |
| [C++ 支线 01](docs/cpp-01-getting-started.md) | 为什么单开一个包、Python ↔ C++ 对照表、`<>` 里的类型、成员变量类型怎么定、`[this]()` lambda、`RCLCPP_INFO` 占位符、CMake 的点名制、跨语言互操作 |

> 📖 复习建议：第 7 节「实测现象与结论」和第 9 节「自测题」是重点。自测题答案默认折叠，**先自己答一遍再点开**。

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
- [ ] 把 `src/hello_ros_cpp/src/talker.cpp` 里两处 `"..."` 占位符换成真正的内容（第 29、32 行）
- [ ] （可选）按上面 `xmllint` 那节修一下 `/etc/gai.conf`

---

**当前进度：第 1～4 关已完成，下一关是「动作 Action」。C++ 支线已起步（第 1 关进行中）。**
