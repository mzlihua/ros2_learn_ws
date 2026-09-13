# 第 4 关 · launch 文件

> ROS 2 核心基础 · 课程笔记
> 学习日期：2026-09-13
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

---

## 1. 本关目标

**把"要敲好几遍的启动命令"，变成一个文件。**

前三关你每次测试都要开好几个终端，挨个敲：

```bash
ros2 run hello_ros param_talker --ros-args -p message:=你好 -p period:=0.5
ros2 run hello_ros listener
```

launch 文件就是把这些**记下来**，以后一条命令起一整套。

产出一个 launch 文件和它的"升级版"：

| 文件 | 作用 |
|---|---|
| `launch/talker.launch.py` | 最小 launch 文件：只起一个 `talker` 节点 |
| `launch/demo.launch.py` | 起两个节点（`param_talker` + `listener`），且 `param_talker` 的参数**从命令行传** |

外加 `setup.py` 的一处改动：让 launch 文件被安装进 `share/hello_ros/launch/`。

---

## 2. 核心概念

### 2.1 ⭐ 一句话：launch 文件就是**一个 Python 脚本**

这是最大的认知转弯。它**不是** `.yaml`、**不是** `.xml`、**不是**"配置文件"。

`ros2 launch` 做的事是：**把你的 `.py` 当普通 Python 执行**。唯一的硬性要求是 —— 跑完之后，必须有一个叫 `generate_launch_description()` 的函数。

```python
def generate_launch_description():     # 函数名是死的，写错就报错
    return LaunchDescription([ ... ])  # 返回一张"任务清单"
```

> ⚠️ **launch 文件不是节点。**
> 它不需要 `import rclpy`，不需要 `class`，不需要 `main()`，不需要 `rclpy.init` / `spin` / `shutdown`。
> 只要交出 `generate_launch_description()`，就够了。
>
> 这一点极其容易搞混，因为 **`Node` 这个词在这里有两个完全不同的含义**：

| | `rclpy.node.Node` | `launch_ros.actions.Node` |
|---|---|---|
| 是什么 | 节点**基类**，你继承它 | 一条**启动指令** |
| 怎么用 | `class Talker(Node):` | `Node(package=..., executable=...)` |
| 在哪用 | `.py` 节点文件里 | `.launch.py` 文件里 |

**同名，不同物。**

### 2.2 `LaunchDescription` 里装的是"动作"

"动作"= 一件要发生的事。本关只用了两种：

```python
Node(package='hello_ros', executable='talker')      # 动作①：启动一个节点
DeclareLaunchArgument('period', default_value='1.0')  # 动作②：声明一个 launch 参数
```

`Node` 的两个参数都是**字符串**，读作：

> **去 `hello_ros` 包里，把叫 `talker` 的可执行文件启动起来。**

对照你在终端敲的那半句：

```
ros2 run hello_ros talker
             ^^^^^^^^ ^^^^^^
```

**一模一样。** launch 文件就是把你本来要敲好几遍的命令，用 Python 记下来。

> 💡 但 `Node` 能给的**远不止** `ros2 run` 能给的：改名（`name=`）、喂 ROS 参数（`parameters=`）、话题重映射（`remappings=`）、命名空间（`namespace=`）。

### 2.3 它装到哪：`share/<包名>/launch/`

`ros2 launch hello_ros xxx.launch.py` 里的 `hello_ros` 是**包名** —— 说明 launch 文件是从**安装目录**里找的，不是从 `src/` 找。

所以必须在 `setup.py` 的 `data_files` 里登记：

```python
import os
from glob import glob

setup(
    ...
    data_files=[
        ('share/ament_index/resource_index/packages',
            ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
        (os.path.join('share', package_name, 'launch'), glob('launch/*.launch.py')),
    ],
    ...
)
```

`data_files` 里每一项是 **`(装到哪, [装什么])`** 的二元组：

| 位置 | 是什么 | 类型 |
|---|---|---|
| 第 1 项 | 安装目录（相对 `install/` 的路径） | **一个字符串** |
| 第 2 项 | 源文件 | **一个列表** |

**`glob('launch/*.launch.py')` 里的相对路径，是相对 `src/hello_ros/` 的** —— 因为 `setup.py` 运行时的工作目录就是包根。

> 怎么推出来的？看上面那行已经跑通的 `'resource/' + package_name` —— 它能找到 `src/hello_ros/resource/hello_ros`，说明当前目录就是 `src/hello_ros/`。

### 2.4 launch 参数：`DeclareLaunchArgument` + `LaunchConfiguration`

一对搭档，分两步：

```python
DeclareLaunchArgument('period', default_value='1.0')   # ① 声明：有这么个参数
LaunchConfiguration('period')                          # ② 占位符：运行时换成实际值
```

然后命令行传：

```bash
ros2 launch hello_ros demo.launch.py period:=0.5
                                     ^^^^^^^^ ↔ 声明里的名字，必须一字不差
```

⚠️ **两个必踩的坑**：

| 坑 | 说明 |
|---|---|
| `default_value` **必须是字符串** | 写 `'1.0'`，不是 `1.0`。因为参数从命令行来，命令行里一切都是字符串 |
| 两处的名字必须**一字不差** | `LaunchConfiguration('period')` 找不到 `DeclareLaunchArgument('period_x')` 会报 `launch configuration 'period' does not exist` |

`DeclareLaunchArgument` 本身也是个**动作**，要放进 `LaunchDescription([...])` 里才生效。

### 2.5 `parameters=[{...}]`：从 launch 给节点喂 ROS 参数

这跟**第 3 关直接接上了**。`param_talker` 的 `message` / `period`，以前只能 `ros2 param set` 改，现在可以在 launch 文件里直接写：

```python
Node(
    package='hello_ros',
    executable='param_talker',
    parameters=[{
        'message': LaunchConfiguration('message'),
        'period': LaunchConfiguration('period'),
    }],
)
```

左边是**节点的参数名**，右边是**launch 参数**。两者的名字**不必相同**（本例相同只是巧合）。

于是同一个参数有三种改法：

| 什么时候改 | 怎么改 |
|---|---|
| 启动时 | `ros2 run ... --ros-args -p period:=0.5` |
| **用 launch 启动时** | `ros2 launch ... period:=0.5` ← 本关新增 |
| 运行中 | `ros2 param set /param_talker period 0.5` |

---

## 3. 完整代码

### `launch/talker.launch.py`

```python
from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    """启动一个 talker 节点."""
    return LaunchDescription([
        Node(
            package='hello_ros',
            executable='talker',
        ),
    ])
```

**12 行。** 这就是 launch 文件该有的样子。

### `launch/demo.launch.py`

```python
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    """一次启动 param_talker 和 listener."""
    msg_arg = DeclareLaunchArgument(
        'message',
        default_value='hello',
        description='发布的内容',
    )
    period_arg = DeclareLaunchArgument(
        'period',
        default_value='1.0',
        description='每隔几秒发一次',
    )

    return LaunchDescription([
        msg_arg,
        period_arg,

        Node(
            package='hello_ros',
            executable='param_talker',
            parameters=[{
                'message': LaunchConfiguration('message'),
                'period': LaunchConfiguration('period'),
            }],
        ),

        Node(
            package='hello_ros',
            executable='listener',
        ),
    ])
```

### `setup.py` 的改动

```python
from glob import glob
import os

from setuptools import find_packages, setup

package_name = 'hello_ros'

setup(
    ...
    data_files=[
        ('share/ament_index/resource_index/packages',
            ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
        (os.path.join('share', package_name, 'launch'), glob('launch/*.launch.py')),
    ],
    ...
)
```

> ⚠️ **`glob` 的参数是 `'launch/*.launch.py'`，不是 `'*.launch.py'`。**
> 前者是"`launch/` 目录下所有 `*.launch.py`"，后者是"**当前目录**下所有 `*.launch.py`" —— 而后者的结果是**空列表**。见 §7.2。

---

## 4. API 速查表

```python
# ---------- launch 文件必备 ----------
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    """函数名固定，返回一个 LaunchDescription."""
    return LaunchDescription([...])


# ---------- 动作①：启动节点 ----------
Node(
    package='包名',            # 字符串，跟 ros2 run 的第一段一样
    executable='可执行名',     # 字符串，跟 ros2 run 的第二段一样
    name='改个名',             # 可选：给节点改名（ros2 node list 里显示这个）
    parameters=[{...}],        # 可选：喂 ROS 参数
    remappings=[('/old', '/new')],   # 可选：话题重映射
    namespace='ns',            # 可选：命名空间
)

# ---------- 动作②：声明 launch 参数 ----------
DeclareLaunchArgument(
    '参数名',
    default_value='默认值',    # ⚠️ 必须是【字符串】
    description='说明文字',    # 可选，ros2 launch -s 会显示
)

# ---------- 取值：占位符 ----------
LaunchConfiguration('参数名')  # 运行时替换成"命令行的值，或默认值"
```

**launch 文件里的东西，一律是字符串。** 别写 `default_value=1.0`。

---

## 5. 命令行工具速查

```bash
# ---------- 运行 ----------
ros2 launch hello_ros talker.launch.py
ros2 launch hello_ros demo.launch.py period:=0.5 message:=你好
#                                     ^^ 是冒号等号，不是 =

# ---------- 看这个 launch 文件有哪些参数 ----------
ros2 launch hello_ros demo.launch.py -s            # -s = show arguments

# ---------- 调试 ----------
ros2 launch hello_ros demo.launch.py -d            # -d = debug，打印内部动作
ros2 launch hello_ros demo.launch.py -p            # -p = print description

# ---------- 观察（跟以前一样） ----------
ros2 node list
ros2 topic echo /chatter
ros2 param get /param_talker period

# ---------- 找 launch 文件装到哪了 ----------
ls install/hello_ros/share/hello_ros/launch/
```

---

## 6. 构建与运行流程

### 改完代码的固定动作

```bash
cd ~/ros2_learn_ws
colcon build --packages-select hello_ros --symlink-install
source install/setup.bash
```

### ⚠️ 什么时候**必须**重新 build

| 你改了什么 | 要 rebuild 吗 |
|---|---|
| 节点 `.py` 的内容 | ❌ 不用（加了 `--symlink-install` 的话） |
| **launch 文件的内容** | ❌ 不用（同上） |
| **新增**一个 launch 文件 | ✅ **必须** |
| `setup.py` / `package.xml` | ✅ **必须** |

原因见 §7.1 和 §7.3。

### 验收清单

```bash
# ① 先确认文件真的装进去了（别跳过这步）
ls install/hello_ros/share/hello_ros/launch/
#    必须看到 talker.launch.py 和 demo.launch.py

# ② 看 launch 参数声明对没对
ros2 launch hello_ros demo.launch.py -s

# ③ 跑
ros2 launch hello_ros demo.launch.py period:=0.5 message:=你好
```

---

## 7. 实测现象与结论 ⭐

### 7.1 ⭐ `--symlink-install` 到底免掉了什么

**实测对比**（同一个包，分别用两种方式 build）：

| build 命令 | `install/.../launch/talker.launch.py` 是什么 |
|---|---|
| `colcon build --packages-select hello_ros` | **普通文件**（拷贝了一份） |
| `colcon build --packages-select hello_ros --symlink-install` | **软链接** |

加了 flag 之后，是一个**两层软链**：

```
install/hello_ros/share/hello_ros/launch/talker.launch.py
   └─→ build/hello_ros/launch/talker.launch.py
          └─→ src/hello_ros/launch/talker.launch.py
```

**结论**：

- 加了 `--symlink-install` → 改**已有文件的内容**，不用 rebuild
- **忘了加** → `install/` 里是拷贝，改内容**也要 rebuild**
- ⚠️ **一次不加 flag 的 build，会把之前的软链"降级"成拷贝。** 所以这个 flag 要么每次加，要么别加。

Python 模块同理，加 flag 时是通过 `hello-ros.egg-link` 指回 `src/`。

### 7.2 ⭐⭐ `glob` 返回空列表 = 一次静默失败

**现象**：`glob` 的参数写成 `'*.launch.py'` 时：

```bash
$ python3 -c "from glob import glob; print(glob('*.launch.py'))"
[]
```

`colcon build` 依然**绿灯**，但：

```bash
$ ls -la install/hello_ros/share/hello_ros/launch/
total 8
drwxrwxr-x 2 l l 4096 .
drwxrwxr-x 4 l l 4096 ..        ← 空目录！
```

**为什么目录在、文件不在？**

因为 `data_files` 那一项 `(目标目录, [源文件])` 的两部分分工不同：

| 第几项 | setuptools 拿它干什么 |
|---|---|
| 第 1 项 | **创建这个目录** |
| 第 2 项 | 把列表里的文件**复制进去** |

`glob` 返回 `[]` → 目录被建出来了，文件一个没放。

直到 `ros2 launch` 才报错：

```
file 'talker.launch.py' was not found in the share directory of package 'hello_ros'
```

> 📌 **`glob` 静悄悄地返回空，是这一类 bug 的入口。**
> 以后凡是 `glob` / `find` / 列表推导，**先 `print` 出来看一眼**再往下走。

**怎么一次做对？** 用 `ls` 借力 —— **`glob('X')` 里的 `X`，就是你 `ls` 后面跟的那一串**：

```bash
cd ~/ros2_learn_ws/src/hello_ros
ls talker.launch.py            # ❌ No such file or directory
ls launch/talker.launch.py     # ✅ 成功
```

`ls` 找不到的，`glob` 也找不到。

### 7.3 ⭐ 新增 launch 文件，无论如何都要 rebuild

**实测**：加了 `--symlink-install` 的前提下，往 `launch/` 里丢一个新文件、**不 rebuild**：

```bash
$ ls install/hello_ros/share/hello_ros/launch/
talker.launch.py          # 新文件没出现
```

**原因**：`glob('launch/*.launch.py')` 是**在 build 那一刻**执行的。它当时只"看得见" `talker.launch.py`，所以 `data_files` 的清单里就没有新文件。

**结论**：

> **`--symlink-install` 免的是"改已有文件的内容"，不免"加新文件"。**

### 7.4 launch 参数确实传进了节点

```bash
$ ros2 launch hello_ros demo.launch.py period:=0.5 message:=你好
[INFO] [param_talker-1]: process started with pid [......]
[INFO] [listener-2]: process started with pid [......]
[param_talker-1] [INFO] [...] [param_talker]: param_talker 起来了
[listener-2] [INFO] [...] [listener]: 接收: 你好
[listener-2] [INFO] [...] [listener]: 接收: 你好

$ ros2 param get /param_talker period
Double value is: 0.5          # ← 命令行的值，不是默认的 1.0
$ ros2 param get /param_talker message
String value is: 你好
```

**两点值得注意**：

1. `default_value='1.0'` 是**字符串**，但 `period` 是 **double** 参数 —— launch 会自动转换类型，不用你操心
2. `listener` 立刻就开始收 —— 说明两个节点是**同时**起来的，**launch 会替你处理启动顺序**

### 7.5 `[talker-1]` 这个前缀是 launch 的第一大好处

```
[INFO] [launch]: All log files can be found below /home/l/.ros/log/2026-09-13-...
[INFO] [launch]: Default logging verbosity is set to INFO
[INFO] [talker-1]: process started with pid [260284]
[talker-1] [INFO] [1789269868.737] [talker]: 发布: 第 1 次心跳
[listener-2] [INFO] [1789269868.771] [listener]: 接收: 你好
^^^^^^^^^^^^
```

`[节点名-编号]` 这截前缀，让 `ros2 launch` 把**多个进程的输出混在一个终端里还能分清谁是谁**。`ros2 run` 做不到。

### 7.6 `ros2 launch -s` 显示声明的参数

```bash
$ ros2 launch hello_ros demo.launch.py -s
Arguments (pass arguments as '<name>:=<value>'):

    'message':
        发布的内容
        (default: 'hello')

    'period':
        每隔几秒发一次
        (default: '1.0')
```

`-s` = show arguments。**改完 launch 文件先跑这个**，确认参数声明进去了。

### 7.7 ⭐ 同一件事的第二次静默失败：CMake 的 `add_executable`

（本关做 C++ 支线时撞上的，形状跟 §7.2 **完全一样**）

`CMakeLists.txt` 里没写 `add_executable(talker src/talker.cpp)` 时：

```bash
$ colcon build --packages-select hello_ros_cpp
Finished <<< hello_ros_cpp          # ← 绿灯

$ ls install/hello_ros_cpp/lib/hello_ros_cpp/
hello_cpp                           # ← 没有 talker

$ ros2 run hello_ros_cpp talker
No executable found                 # ← 到这儿才发现
```

**原因**：CMake 的世界里，**"文件存在" ≠ "会被构建"**。你得**点名**（`add_executable`）。

### 7.8 ⭐⭐ 本关最重要的一条结论

把 §7.2 和 §7.7 放在一起看：

| | 第一次（`glob`） | 第二次（`CMakeLists`） |
|---|---|---|
| 我让工具干什么 | 把 `launch/*.launch.py` 装进去 | 把 `talker.cpp` 编译出来 |
| 实际给的清单 | 空列表 `[]` | 没有这一项 |
| `colcon build` | **绿灯** | **绿灯** |
| 结果 | 目录是空的 | 没有 `talker` |
| 谁先发现 | `ros2 launch` | `ros2 run` |

> ### 📌 绿灯只证明"没出错"，不证明"做了你想做的事"。
>
> 所以每次命令成功之后，都该多问一句：
> **"我期望的东西，真的出现了吗？"** —— 然后 **`ls` 一下**去看。

---

## 8. 踩坑记录

### ❌ 坑 1：在 launch 文件里写 `import rclpy` + `class` + `main()` + `spin`

```python
import rclpy                            # ← 错
from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    """启动一个 talker 节点."""
    return LaunchDescription([
        Node(package='hello_ros', executable='talker'),
    ])

def main(args=None):                    # ← 错：整块都是多余的
    rclpy.init(args=args)
    node = Talker()                     # ← 错：NameError，根本没定义过 Talker
    try:
        rclpy.spin(node)
    except LaunchDescription:           # ← 错得最离谱的一行
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()
```

**根因**：`rclpy.node.Node` 和 `launch_ros.actions.Node` **同名不同物**，脑子里"launch 也是 Python 脚本 → 那也该有 `import rclpy` → 也该有 `class` → 也该有 `main()`"这条链条**从第一步就歪了**。

**改法**：**launch 文件不是节点。** `import rclpy` 和整个 `main()` 删掉，文件只剩 12 行。

> 那行 `except LaunchDescription:` 很说明问题 —— 把"异常类型"的位置填成了一个不相干的类，等于在说"我不能删，因为我不确定它是不是必须的"。
> **答案：不必须。**

### ❌ 坑 2：`glob` 的参数漏了目录（连续写错三版）

| 写的 | 含义 | 结果 |
|---|---|---|
| `glob('*.launch.py')` | 当前目录下所有 `*.launch.py` | `[]` |
| `glob('.launch.py')` | 当前目录下**恰好叫 `.launch.py`** 的文件（`*` 没了） | `[]` |
| `glob('talker.launch.py')` | 当前目录下的 `talker.launch.py` | `[]` |
| `glob('launch/*.launch.py')` | **`launch/` 目录下**所有 `*.launch.py` | ✅ |

**三版都在改右边，唯独没动左边缺的那截 `launch/`。**

**教训**：卡住时如果连续几次都在改同一个方向，**换个方向看看**。用 `ls` 借力是最快的。

### ❌ 坑 3：以为 build 过了就等于装上了

见 §7.2。**新增/修改 `setup.py` 之后，先 `ls` 安装目录，再 `ros2 launch`。**

### ⚠️ 坑 4：`ros2 launch` 报错，但其实是上一次的报错

改了 `setup.py` 但**没重新 build** 就去 `ros2 launch` —— 看到的还是上一轮的报错，容易误以为"改了没用"。

**顺序永远是**：改文件 → `colcon build` → `source install/setup.bash` → `ls` 验证 → 再运行。

---

## 9. 自测题

> §9.1 的答案默认折叠，**先自己回答一遍再展开**。
> §9.2 是留给下次课的，**没有答案**。

### 9.1 课堂已覆盖（附答案）

<details>
<summary><b>题 1：launch 文件是什么？它为什么不是一个"配置文件"？</b></summary>

它是一个**普通的 Python 脚本**，被 `ros2 launch` 当 Python 执行。唯一的要求是导出一个 `generate_launch_description()` 函数，返回一张"动作清单"（`LaunchDescription`）。

说它不是配置文件，是因为它**可执行** —— 你可以写 `if`、循环、读环境变量、算路径。`.yaml` 做不到这些。

</details>

<details>
<summary><b>题 2：<code>rclpy.node.Node</code> 和 <code>launch_ros.actions.Node</code> 有什么区别？</b></summary>

| | `rclpy.node.Node` | `launch_ros.actions.Node` |
|---|---|---|
| 是什么 | 节点**基类**，你继承它 | 一条**启动指令** |
| 怎么用 | `class Talker(Node):` | `Node(package=..., executable=...)` |
| 在哪用 | `.py` 节点文件 | `.launch.py` 文件 |

同名不同物。把两者的用法混在一起，就会在 launch 文件里写出 `class` 和 `main()`。

</details>

<details>
<summary><b>题 3：为什么 <code>default_value</code> 必须写成字符串 <code>'1.0'</code>？</b></summary>

因为 launch 参数是从**命令行**来的，而命令行里一切都是字符串。

参数值在传给节点时会由 launch 根据**节点自己声明的参数类型**自动转换 —— 所以 `period`（double）照样能拿到 `0.5` 这个浮点数。

</details>

<details>
<summary><b>题 4：加了 <code>--symlink-install</code>，改 launch 文件还要不要 rebuild？新增 launch 文件呢？</b></summary>

| 情况 | 要 rebuild 吗 |
|---|---|
| 改**已有** launch 文件的**内容** | ❌ 不用（软链直通 `src/`） |
| **新增**一个 launch 文件 | ✅ **必须** |

新增必须 rebuild，因为 `glob('launch/*.launch.py')` 是在 **build 那一刻**执行的，当时的文件清单里没有新文件。

</details>

<details>
<summary><b>题 5：<code>glob('*.launch.py')</code> 和 <code>glob('launch/*.launch.py')</code> 有什么区别？</b></summary>

前者在**当前目录**找，后者在 **`launch/` 子目录**里找。

`setup.py` 运行时的当前目录是**包根**（`src/hello_ros/`），launch 文件在 `launch/` 里，所以必须用后者。

判断方法：**`glob('X')` 里的 `X`，就是你 `ls` 后面跟的那一串。**

</details>

<details>
<summary><b>题 6：<code>colcon build</code> 显示 <code>Finished</code>，为什么 <code>ros2 launch</code> 还是找不到文件？</b></summary>

因为 build 成功只说明"**它被告知要装的东西，都装好了**"。

如果 `glob` 返回空列表，`data_files` 的清单就是空的 —— setuptools 照样创建目录、照样报告成功，只是**一个文件都没放进去**。

**绿灯只证明"没出错"，不证明"做了你想做的事"。**

</details>

<details>
<summary><b>题 7：一次 launch 起了两个节点，怎么从终端输出里分辨哪行是谁打的？</b></summary>

看前缀 `[节点名-编号]`：

```
[param_talker-1] [INFO] [...] [param_talker]: param_talker 起来了
[listener-2]     [INFO] [...] [listener]:     接收: 你好
```

`ros2 run` 一次只能起一个节点，所以没有这个需求；`ros2 launch` 把多个进程的输出混在一起，靠这个前缀区分。

</details>

<details>
<summary><b>题 8：同一个参数，现在有几种改法？分别在什么时候用？</b></summary>

| 什么时候改 | 怎么改 |
|---|---|
| 启动前（写死在代码里） | `declare_parameter('period', 1.0)` |
| 启动时（临时覆盖） | `ros2 run ... --ros-args -p period:=0.5` |
| **启动时（用 launch）** | `ros2 launch ... period:=0.5` |
| 运行中 | `ros2 param set /param_talker period 0.5` |

launch 的好处是：**一次配好、可复用、还能连节点一起起**。

</details>

### 9.2 留给下次课的思考题（无答案）

> ⚠️ 这几题**不要现在查**，下次课上口头答。

**题 9**：`Node(...)` 里有个 `name=` 参数，可以给节点**改名**。

```python
Node(package='hello_ros', executable='param_talker', name='talker_a')
```

那么：`ros2 param get` 的时候该用哪个名字？`ros2 node list` 里显示哪个？

**题 10**：如果一个 launch 文件里**两次** `Node(...)` 起同一个 `param_talker`，而且**都不写 `name=`**，会发生什么？（提示：第 1 关你见过一条 WARNING）

**题 11**：`ros2 launch` 之后按 `Ctrl+C`，两个节点会怎样？如果只想重启其中一个怎么办？

**题 12**：`LaunchConfiguration` 是个"占位符"。那它能不能用在 `Node` 的**别的**参数上，比如 `executable=`？（提示：想想它是什么时候被替换成实际值的）

---

## 附：本关命令速记卡

```bash
# ---------- 构建 ----------
cd ~/ros2_learn_ws
colcon build --packages-select hello_ros --symlink-install
source install/setup.bash

# ---------- ⭐ 先验安装目录 ----------
ls install/hello_ros/share/hello_ros/launch/

# ---------- 看 launch 参数 ----------
ros2 launch hello_ros demo.launch.py -s

# ---------- 运行 ----------
ros2 launch hello_ros talker.launch.py
ros2 launch hello_ros demo.launch.py period:=0.5 message:=你好

# ---------- 观察 ----------
ros2 node list
ros2 topic echo /chatter
ros2 param get /param_talker period

# ---------- 自查 glob 参数（改 setup.py 之前跑） ----------
cd ~/ros2_learn_ws/src/hello_ros
python3 -c "from glob import glob; print(glob('launch/*.launch.py'))"
#    必须打印非空列表，再往下走
```
