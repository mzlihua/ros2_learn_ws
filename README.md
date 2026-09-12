# ROS 2 学习工作区

> 系统学习 ROS 2 **核心基础**的练习工作区。
> 路线：话题 → 服务 → 参数 → launch → 动作 → 自定义消息，逐关手写代码 + 实测验证。

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
| 构建工具 | `colcon` |
| 包名 | `hello_ros`（`ament_python` 类型） |

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
│   ├── lesson-01-topic.md         第 1 关 · 话题
│   ├── lesson-02-service.md       第 2 关 · 服务
│   └── lesson-03-parameter.md     第 3 关 · 参数
└── src/
    └── hello_ros/             ← 唯一的 ROS 2 包
        ├── package.xml           依赖声明
        ├── setup.py              可执行文件注册
        └── hello_ros/
            ├── hello_node.py     最小节点：定时打印
            ├── talker.py         发布者
            ├── listener.py       订阅者
            ├── add_server.py     服务端
            ├── add_client.py     客户端
            └── param_talker.py   参数化的发布者
```

构建产物 `build/` `install/` `log/` 已在 `.gitignore` 里，不会进版本库。

---

## 快速开始

### 构建

```bash
cd ~/ros2_learn_ws
colcon build --packages-select hello_ros --symlink-install
source install/setup.bash
```

> **`--symlink-install` 是什么？** 让 `install/` 里放软链接指回 `src/`，这样**只改 `.py` 里的代码时不用重新 build**。
>
> ⚠️ 边界：改了 `setup.py` 或 `package.xml`（加可执行文件、加依赖）**还是必须重新 build**——那改的是"装什么"，不是"装的内容"。

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
| 4 | launch 文件 | ⬜ 未开始 | — |
| 5 | 动作 Action | ⬜ 未开始 | — |
| 6 | 自定义消息 `.msg` / `.srv` | ⬜ 未开始 | — |

---

## 已有节点

全部在 `src/hello_ros/setup.py` 的 `entry_points` 里注册过，可以直接 `ros2 run`。

| 可执行名 | 来源 | 作用 | 验证命令 |
|---|---|---|---|
| `hello_node` | [hello_node.py](src/hello_ros/hello_ros/hello_node.py) | 最小节点，每秒打印一次心跳 | `ros2 run hello_ros hello_node` |
| `talker` | [talker.py](src/hello_ros/hello_ros/talker.py) | 发布者，每秒往 `/chatter` 发一条 | `ros2 topic echo /chatter` |
| `listener` | [listener.py](src/hello_ros/hello_ros/listener.py) | 订阅者，收到 `/chatter` 就打印 | 先跑 `talker` 再跑它 |
| `add_server` | [add_server.py](src/hello_ros/hello_ros/add_server.py) | 服务端，提供 `add_two_ints` 加法服务 | `ros2 service call /add_two_ints example_interfaces/srv/AddTwoInts "{a: 3, b: 4}"` |
| `add_client` | [add_client.py](src/hello_ros/hello_ros/add_client.py) | 客户端，调用加法服务 | 先跑 `add_server` 再跑它 |
| `param_talker` | [param_talker.py](src/hello_ros/hello_ros/param_talker.py) | 参数化发布者，发什么/多快/几条都能改 | `ros2 param set /param_talker message 世界` |

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
```

---

## 学习笔记

每关一份，结构固定：**目标 → 核心概念 → 完整代码 → API 速查 → CLI 速查 → 构建运行 → 实测现象 → 踩坑记录 → 自测题**。

| 笔记 | 主要内容 |
|---|---|
| [第 1 关 · 话题](docs/lesson-01-topic.md) | 发布者/订阅者、回调与 executor、话题的多对多、QoS volatile 与历史消息、CLI 工具也是节点 |
| [第 2 关 · 服务](docs/lesson-02-service.md) | 请求/响应、`request`/`response` 的"盒子 vs 字段"、`future`、隐藏节点机制、服务端不可用的两种情况、服务回调串行 |
| [第 3 关 · 参数](docs/lesson-03-parameter.md) | `declare` 注册 vs `get` 读取、参数改了谁自动跟上（现读 vs 焊死）、校验回调的三个必答点、只读参数、节点自带参数、启动 `-p` 绕过回调 |

> 📖 复习建议：第 7 节「实测现象与结论」和第 9 节「自测题」是重点。自测题答案默认折叠，**先自己答一遍再点开**。

---

## 工作约定

### 代码风格

- 每个节点用 `Pylance` 做类型检查，包内自带 `flake8` / `mypy` / `pep257` 测试：

  ```bash
  colcon test --packages-select hello_ros
  ```

### 编辑器

`.vscode/settings.json` 里**刻意关闭了全部自动补全**（12 项配置），目的是**手写代码练手**。

- 需要补全时按 `Ctrl+Space` 仍可手动唤出
- `editor.hover`（鼠标悬停看文档）**有意保留**
- ⚠️ 这不是配置错误，**不要"修"它**

### 测试

```bash
colcon test --packages-select hello_ros      # ① 执行
colcon test-result --verbose                 # ② 查看（不执行就只会看到旧报告）
```

包内 5 条检查，当前状态 **5 tests, 0 errors, 0 failures, 1 skipped**：

| 测试 | 查什么 |
|---|---|
| `test_flake8` | 代码风格（`ament_flake8.ini`，行宽 99，import 按 google 风格排序） |
| `test_pep257` | docstring（⚠️ 中文句号 `。` 不算标点，结尾要用半角 `.`） |
| `test_mypy` | 类型标注 |
| `test_xmllint` | `package.xml` 的 XML 是否合法 |
| `test_copyright` | 版权头（**跳过**，本项目没启用） |

> ⚠️ `test_xmllint` 会从 `download.ros.org` 下载 XSD 校验文件，**且没设超时**。没网的环境下这一条会卡几分钟才失败。

### 待办

- [x] ~~`package.xml` 的 `<description>` / `<license>` 占位~~（2026-09-12 已补：Apache-2.0）
- [x] ~~清理源码里练习时的 `# TODO n：...` 注释~~（2026-09-12 已清）

---

**当前进度：第 3 关已完成，下一关是「launch 文件」。**
