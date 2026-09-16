# 第 6 关 · 自定义消息 `.msg` / `.srv`

> ROS 2 核心基础 · 课程笔记
> 学习日期：2026-09-16
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

**前五关用的消息都是别人定义好的**（`std_msgs`、`example_interfaces`）。本关自己定一份。

| 前五关 | 本关 |
|---|---|
| `std_msgs/msg/String`、`example_interfaces/srv/AddTwoInts` | `hello_ros_interfaces/msg/RobotStatus`、`.../srv/SetMode` |
| 拿来就用 | 自己写、自己生成、自己用 |

本关产出：

| 文件 | 作用 |
|---|---|
| `src/hello_ros_interfaces/msg/RobotStatus.msg` | 一份**话题**合同：机器人状态 |
| `src/hello_ros_interfaces/srv/SetMode.srv` | 一份**服务**合同：切换模式 |
| `hello_ros/status_talker.py` | 发布 `RobotStatus` |
| `hello_ros/status_listener.py` | 订阅 `RobotStatus` |
| `hello_ros/mode_server.py` | 提供 `SetMode` 服务 |
| `hello_ros/mode_client.py` | 调用 `SetMode` 服务 |

外加一个**全新的包** `hello_ros_interfaces`（`ament_cmake` 类型）—— 这是本关唯一一个新包。

---

## 2. 核心概念

### 2.1 ⭐⭐ `.msg` / `.srv` 不是代码，是**合同**

```
        RobotStatus.msg                    ← 你写的，只有 5 行，一门语言都不属于
              │
   ┌──────────┼──────────┬─────────────┐
   ▼          ▼          ▼             ▼
 .py        .hpp        .idl        .json      ← 全是【生成】出来的，你一个字没写
 (Python)    (C++)     (中间产物)   (类型描述)
```

**你写的 5 行文本，被工具翻译成了至少四种语言的代码。**

> **合同一旦签了，两边都得照着它来。**
> Python 发布者填的字段、Python 订阅者读的字段、将来 C++ 节点读的字段 —— **全部**来自这 5 行。

**直接证据**（本关一个字 C++ 都没写）：

```bash
sed -n '45,58p' install/hello_ros_interfaces/include/hello_ros_interfaces/hello_ros_interfaces/msg/detail/robot_status__struct.hpp
```

```cpp
this->robot_name = "";
this->battery = 0.0f;
this->emergency = false;
```

### 2.2 ⭐⭐ 本关的命门：**文件在磁盘上 ≠ 被注册了**

`.msg` 文件写完存盘，**什么都不会发生**。必须有人在**三张表**上点名。

| 表 | 在哪 | 管什么 | 落下的症状 |
|---|---|---|---|
| 生成登记表 | `CMakeLists.txt` 的 `rosidl_generate_interfaces` | 哪些 `.msg` / `.srv` **要生成代码** | 文件明明在，`ros2 interface show` 说找不到 |
| 可执行登记表 | `setup.py` 的 `entry_points` | 哪些 `.py` 能 `ros2 run` | `No executable found` |
| 依赖登记表 | `package.xml` | 这个包**装了什么 / 用了什么** | build 报找不到包，或运行报 `No module named ...` |

**三张表，三个位置，三种症状。** 症状长得完全不一样，但根因是同一个：**你写了东西，但没登记。**

> 这条原则**贯穿全课程**，本关只是它最集中的一次：
> 第 4 关的 `data_files`（launch 文件要登记才装得进去）、第 5 关的 `entry_points`、第 6 关的 `rosidl_generate_interfaces` —— 是同一件事换了个位置。

**查表工具（别猜，去读）**：

```bash
ros2 pkg xml hello_ros_interfaces              # 把 package.xml 原样打出来
ros2 pkg xml example_interfaces                # 跟"标准答案"对表
```

### 2.3 `.srv` 的分隔符：**那一行必须只有三个减号**

一份 `.srv` 文件装**两个**消息：上半是请求，下半是响应。

```
int32 mode          ← 请求（Request）
                       ↑ 中间这一行是分隔符
---
                        ↓
bool success        ← 响应（Response）
string message
```

**规则很死：分隔符那一行，必须恰好是 `---` 三个减号，前后不能有别的东西。**

实测三种写法（见 §7.3）：

| 写的 | 结果 |
|---|---|
| `---` | ✅ |
| `--- # 分隔符` | ❌ `InvalidServiceSpecification: Could not find separator` |
| ` ---`（前面一个空格） | ❌ 同上 |

**为什么记得住？** 因为在 Python 里这两个名字是自动切出来的：

```python
from hello_ros_interfaces.srv import SetMode

SetMode.Request     # ← 上半部分
SetMode.Response    # ← 下半部分
```

一个文件，两个类。**分隔符就是切这一刀的地方。**

### 2.4 嵌套消息：字段本身可以是一个消息

`RobotStatus.msg` 第 5 行：

```
geometry_msgs/Point position
```

`Point` 自己也是个消息（`float64 x / y / z`）。用起来**没有额外语法**：

```python
msg.position.x = 1.0        # 直接点下去
```

**但要在两处额外登记**（又是"登记表"）：

```python
# CMakeLists.txt
rosidl_generate_interfaces(${PROJECT_NAME}
  ...
  DEPENDENCIES geometry_msgs      # ← 生成代码时要能找到 Point 的定义
)
```

```xml
<!-- package.xml -->
<depend>geometry_msgs</depend>     <!-- ← 运行时要能找到 Point 的定义 -->
```

**一个给"生成时"，一个给"运行时"，两个都要。**

### 2.5 为什么接口要单独开一个包？（而不是塞进 `hello_ros`）

| 理由 | 说明 |
|---|---|
| **依赖方向** | 接口包**不依赖**任何业务包；业务包**依赖**接口包。方向单一，不会绕圈 |
| **谁都能用** | Python 包要用、C++ 包要用、将来别的包也要用。**合同不该归属于任何一方** |
| **构建顺序** | colcon 按依赖关系决定谁先 build。接口必须先于用它的包 |

本关的依赖链：

```
hello_ros_interfaces  （只定义合同，不含逻辑）
        ▲
        ├── hello_ros       （Python：用它）
        └── hello_ros_cpp   （C++：将来也能用）
```

> ⚠️ **反过来是错的**：让 `hello_ros_interfaces` 去 `<depend>hello_ros`，
> 等于"合同依赖签合同的人"。实测会直接 build 失败，见 §8 坑 4。

---

## 3. 完整代码

### `src/hello_ros_interfaces/msg/RobotStatus.msg`

```
string robot_name
float32 battery
int32 mode
bool emergency
geometry_msgs/Point position
```

> 语法就一种：`类型 字段名`，一行一个，**没有逗号、没有分号、没有引号**。

### `src/hello_ros_interfaces/srv/SetMode.srv`

```
int32 mode

---

bool success
string message
```

> 空行是无害的（但会被 `ros2 interface show` 原样打印出来，见 §7.2）。

### `src/hello_ros_interfaces/package.xml` 的四处改动

```xml
  <buildtool_depend>ament_cmake</buildtool_depend>
  <buildtool_depend>rosidl_default_generators</buildtool_depend>   <!-- ① 生成器 -->

  <depend>geometry_msgs</depend>                                   <!-- ② 嵌套消息要用 -->

  <exec_depend>rosidl_default_runtime</exec_depend>                <!-- ③ 运行时 -->
  <member_of_group>rosidl_interface_packages</member_of_group>     <!-- ④ 声明"我是接口包" -->
```

**四个元素，缺一个都有后果。** 最陌生的是 ④：

> `rosidl_interface_packages` 是给构建系统看的**分组标签** ——
> "这个包会产出接口代码，请把它排在依赖它的包前面 build"。

**怎么查的？** 不猜，跟标准答案对表：

```bash
ros2 pkg xml example_interfaces | grep -E 'depend|group'
```

### `src/hello_ros_interfaces/CMakeLists.txt` 的改动

```cmake
find_package(ament_cmake REQUIRED)
find_package(geometry_msgs REQUIRED)
find_package(rosidl_default_generators REQUIRED)

rosidl_generate_interfaces(${PROJECT_NAME}
  "msg/RobotStatus.msg"
  "srv/SetMode.srv"
  DEPENDENCIES geometry_msgs
)

ament_export_dependencies(rosidl_default_runtime)
```

> ⚠️ **这几行要放在 `if(BUILD_TESTING)` 之前**，跟 `find_package` 挨着。
> `if(...)` / `endif()` 是**一对括号**，写进去了就等于写进了"另一个格子"。

### `src/hello_ros/package.xml` 的一处改动

```xml
  <depend>hello_ros_interfaces</depend>     <!-- 我用它，所以我依赖它 -->
```

### `src/hello_ros/setup.py` 的改动

```python
'status_talker = hello_ros.status_talker:main',
'status_listener = hello_ros.status_listener:main',
'mode_server = hello_ros.mode_server:main',
'mode_client = hello_ros.mode_client:main',
```

### `hello_ros/status_talker.py`

```python
from hello_ros_interfaces.msg import RobotStatus
import rclpy
from rclpy.node import Node


class StatusTalker(Node):

    def __init__(self):
        super().__init__('status_talker')
        self.count = 0
        self.pub = self.create_publisher(RobotStatus, 'robot_status', 10)
        self.timer = self.create_timer(1.0, self.tick)

    def tick(self):
        self.count += 1

        msg = RobotStatus()
        msg.robot_name = 'r2d2'
        msg.battery = 100.0 - (self.count * 5)
        msg.mode = self.count % 3
        msg.emergency = False

        msg.position.x = float(self.count)

        self.pub.publish(msg)
        self.get_logger().info(
            f'发布: {msg.robot_name} 电量={msg.battery} mode={msg.mode} x={msg.position.x}')


def main(args=None):
    rclpy.init(args=args)
    node = StatusTalker()
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

### `hello_ros/status_listener.py`

```python
from hello_ros_interfaces.msg import RobotStatus
import rclpy
from rclpy.node import Node


class StatusListener(Node):

    def __init__(self):
        super().__init__('status_listener')
        self.sub = self.create_subscription(
            RobotStatus, 'robot_status', self.callback, 10)

    def callback(self, msg):
        self.get_logger().info(
            f'收到: {msg.robot_name} 电量={msg.battery} mode={msg.mode} x={msg.position.x}')


def main(args=None):
    rclpy.init(args=args)
    node = StatusListener()
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

### `hello_ros/mode_server.py`

```python
from hello_ros_interfaces.srv import SetMode
import rclpy
from rclpy.node import Node


class ModeServer(Node):

    def __init__(self):
        super().__init__('mode_server')
        self.srv = self.create_service(SetMode, 'set_mode', self.handle_set_mode)
        self.get_logger().info('模式服务已启动')

    def handle_set_mode(self, request, response):
        if request.mode in (0, 1, 2):
            response.success = True
            response.message = f'模式已切换到 {request.mode}'
        else:
            response.success = False
            response.message = '非法模式，只接受 0/1/2'

        return response


def main(args=None):
    rclpy.init(args=args)
    node = ModeServer()
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

### `hello_ros/mode_client.py`

```python
from hello_ros_interfaces.srv import SetMode
import rclpy
from rclpy.node import Node


def main(args=None):
    rclpy.init(args=args)
    node = Node('mode_client')

    client = node.create_client(SetMode, 'set_mode')

    if not client.wait_for_service(timeout_sec=1.0):
        node.get_logger().error('没找到 set_mode 服务，服务端开了吗？')
        node.destroy_node()
        rclpy.shutdown()
        return

    request = SetMode.Request()
    request.mode = 2

    future = client.call_async(request)
    rclpy.spin_until_future_complete(node, future)

    response = future.result()
    node.get_logger().info(
        f'请求 mode={request.mode} -> success={response.success}, '
        f'message={response.message}')

    node.destroy_node()
    rclpy.shutdown()
```

---

## 4. API 速查表

```python
# ---------- 用自定义消息 ----------
from hello_ros_interfaces.msg import RobotStatus      # 话题类型
from hello_ros_interfaces.srv import SetMode          # 服务类型
#       ^^^^^^^^^^^^^^^^^^^^^  ^^^  ^^^^^^^^^^^
#           包名               类别    名字（首字母大写，跟文件名一致）

msg = RobotStatus()                # 造盒子。不用传参
msg.robot_name = 'r2d2'            # 顶层字段：直接点
msg.position.x = 1.0               # 嵌套字段：一路点下去，没有额外语法

# ---------- 用自定义服务 ----------
request = SetMode.Request()        # 上半部分
response = SetMode.Response()      # 下半部分（服务端由框架给，不用自己造）

# ---------- 注册（这才是本关的重点）----------
# CMakeLists.txt
rosidl_generate_interfaces(${PROJECT_NAME}
  "msg/Xxx.msg"                    # 每个文件都要点名！
  "srv/Yyy.srv"
  DEPENDENCIES 其他消息包            # 只有嵌套了别家的消息才要
)

# package.xml（接口包）
<buildtool_depend>rosidl_default_generators</buildtool_depend>
<exec_depend>rosidl_default_runtime</exec_depend>
<member_of_group>rosidl_interface_packages</member_of_group>
<depend>被嵌套的消息包</depend>
```

### 类型对照：`.msg` 里写什么，Python 里拿到什么

| `.msg` 写法 | Python 里的类型 |
|---|---|
| `string` | `str` |
| `bool` | `bool` |
| `int32` / `int64` | `int` |
| `float32` / `float64` | `float` |
| `float64[3]`（固定长度） | `array('d')` |
| `float64[]`（可变长度） | `array('d')` |
| `geometry_msgs/Point` | `Point` 对象，继续点 `.x` |

> ⚠️ `float32` 和 `float64` 在 Python 里**都是 `float`**，看不出区别。
> 想知道某个字段真正的类型，用 `get_fields_and_field_types()`：
>
> ```bash
> python3 -c "from hello_ros_interfaces.msg import RobotStatus; print(RobotStatus.get_fields_and_field_types())"
> ```

---

## 5. 命令行工具速查

```bash
# ---------- 看接口 ----------
ros2 interface list                          # 系统里所有接口
ros2 interface packages                      # 哪些包提供了接口
ros2 interface package hello_ros_interfaces  # 这个包提供了哪些 ← 先查这个
ros2 interface show hello_ros_interfaces/msg/RobotStatus    # 字段长什么样
ros2 interface show hello_ros_interfaces/srv/SetMode        # 注意打印出的分隔线

# ---------- 用接口 ----------
ros2 topic echo /robot_status                # 看自定义消息的话题
ros2 topic info /robot_status -v             # 带类型
ros2 service call /set_mode hello_ros_interfaces/srv/SetMode "{mode: 5}"

# ---------- 查包（本关最常用的排查工具）----------
ros2 pkg list | grep hello                   # 这个包 build 出来了吗
ros2 pkg xml hello_ros_interfaces            # package.xml 原样打印
ros2 pkg xml example_interfaces              # 跟标准答案对表

# ---------- 看生成物 ----------
ls install/hello_ros_interfaces/include/hello_ros_interfaces/hello_ros_interfaces/msg/
ls install/hello_ros_interfaces/share/hello_ros_interfaces/msg/
```

> 💡 **`ros2 interface show` 看不到你的接口？** 第一件事不是改代码，是问：
> **"我 build 过吗？"** —— 它只看得见 **install 空间**里的东西。
> 验证：`ls install/` 里有没有你的包。

---

## 6. 构建与运行流程

### 构建

```bash
cd ~/ros2_learn_ws
source /opt/ros/lyrical/setup.bash
colcon build --packages-select hello_ros_interfaces hello_ros --symlink-install
source install/setup.bash
```

> ⚠️ **`.msg` / `.srv` 改了必须重新 build**（`--symlink-install` 免不掉）。
> 因为它要**生成代码**，生成是需要跑工具的。
> **这条和第 5 关相反**：`.py` 走软链，改了不用 build；`.msg` 不走软链，改了必须 build。

### 验收清单

```bash
# ① 接口注册成功了吗（不依赖任何节点）
ros2 interface package hello_ros_interfaces
ros2 interface show hello_ros_interfaces/srv/SetMode

# ② 话题那一对
ros2 run hello_ros status_talker        # 终端 A
ros2 run hello_ros status_listener      # 终端 B

# ③ 服务那一对
ros2 run hello_ros mode_server          # 终端 A
ros2 run hello_ros mode_client          # 终端 B
ros2 service call /set_mode hello_ros_interfaces/srv/SetMode "{mode: 5}"   # 应该成功被拒

# ④ 测试
colcon test --packages-select hello_ros
colcon test-result --verbose
```

---

## 7. 实测现象与结论 ⭐

### 7.1 ⭐⭐ 5 行文本 → 四种语言的产物

写完 `RobotStatus.msg`（5 行）并 build 之后，磁盘上凭空多出来的东西：

```
同一份 RobotStatus.msg
        │
        ├── Python：  _robot_status.py                  ← 你 import 的那个
        │             _robot_status_s.c                 ← 底层 C 胶水（你没写，但它在跑）
        │
        ├── C++：     robot_status.hpp / robot_status.h
        │             detail/robot_status__struct.hpp   ← 结构体真身在这里
        │
        ├── IDL：     RobotStatus.idl                   ← 跨语言中间语言
        │
        └── 类型描述： RobotStatus.json
```

**`.idl` 里那行注释，把来源写死了**：

```
// generated from rosidl_adapter/resource/msg.idl.em
// with input from hello_ros_interfaces/msg/RobotStatus.msg
#include "geometry_msgs/msg/Point.idl"
```

> **结论：`.msg` 是源头，其余全是派生物。**
> **改派生物没用 —— 下次 build 会被覆盖。要改就改源头。**

### 7.2 ⭐ `ros2 interface show` 打印的行数 ≠ 文件的行数

| 文件 | 文件里几行 | `show` 打印几行 | 差在哪 |
|---|---|---|---|
| `RobotStatus.msg` | 5 | **8** | 嵌套的 `Point` 被**展开**成 3 行 |
| `SetMode.srv` | 6（含空行） | **6** | 空行被**原样保留** |

实测输出：

```
$ ros2 interface show hello_ros_interfaces/msg/RobotStatus
1  string robot_name
2  float32 battery
3  int32 mode
4  bool emergency
5  geometry_msgs/Point position
6      float64 x          ← 缩进的，是上一条的"内部"
7      float64 y
8      float64 z

$ ros2 interface show hello_ros_interfaces/srv/SetMode
1  int32 mode
2
3  ---
4
5  bool success
6  string message
```

> **预测过 4 行（`int32 mode` + `---` + 2 个响应字段），实际 6 行 —— 多的 2 行是自己写的空行。**
> **它不替你做任何"整理"，你写什么它显示什么。**
>
> 顺带：**缩进 = 层级**。第 6~8 行缩进了，说明它们**属于**第 5 行，不是并列的。

### 7.3 ⭐ `.srv` 分隔符：三种写法的实测结果

| 写法 | 结果 |
|---|---|
| `---` | ✅ 正常 |
| `--- # 分隔符` | ❌ `rosidl_adapter.parser.InvalidServiceSpecification: Could not find separator` |
| ` ---`（前导空格） | ❌ 同上 |

**报错信息本身就写明了原因**：它在找「separator（分隔符）」，没找到。

> ⚠️ **这个坑的根源不是手滑，是"把提示文字当成了代码内容"。**
> 出题时在分隔符那行的注释里写了 `--- TODO 1：...`，被原样抄进了文件。
> **聊天里的 `???` 和 `# TODO`，是给你看的，不是给你抄的。**

### 7.4 ⭐⭐ 静默 bug #4：`if` 写成了**恒真**

```python
if request.mode == 0 or 1 or 2:       # ✗ 永远为真
```

**实测**：

```bash
$ python3 -c "print(5 == 0 or 1 or 2)"
1                                      ← 不是 True/False，是【第一个为真的值】
```

| `request.mode` | 这行算出什么 | 真不真 |
|---|---|---|
| 0 | `True` | 真 ✅ |
| 1 | `1` | 真 ✅ |
| 2 | `1` | 真 ✅ |
| **5** | **`1`** | **真 ✅ ← 越界也放行** |
| **999** | **`1`** | **真 ✅ ← 越界也放行** |

**为什么？** Python 读的是：

```
(request.mode == 0)   or   1   or   2
        ↑                  ↑
     一个比较          字面量 1 —— 恒真
```

第一个比较要是假，就轮到 `1`；`1` 恒真，**表达式到此结束，`2` 根本轮不上**。

> **`or` 返回的不是 `True`/`False`，是「第一个为真的那个值」。**
> **`or` 不连接比较，它连接值。**

**现场证据**（学生自己的测试输出）：

```bash
$ ros2 service call /set_mode hello_ros_interfaces/srv/SetMode "{mode: 5}"
hello_ros_interfaces.srv.SetMode_Response(success=True, message='模式已切换到 ...')
#                                                        ^^^^^^^^^^^^ 越界放行了
```

**后果**：`else` 那一整块（"非法模式，只接受 0/1/2"）是**死代码** —— 写在文件里，永远走不到。

**正确写法**：

```python
if request.mode in (0, 1, 2):          # ✅ "是其中之一"
if 0 <= request.mode <= 2:             # ✅ 也可以（这个链式比较 Python 读得懂）
```

> 📌 **这是「静默 bug」家族的第四个成员**：
>
> | 关 | 错误写法 | 症状 |
> |---|---|---|
> | 3 | `0 < max_count < count`（本想写 `count >= max_count`） | 边界差一 |
> | 5 | `self._feedback_count` 忘了 `+= 1` | 计数永远是 0 |
> | 5 | 把 `time.sleep(1)` 注释掉 | 跑太快，来不及取消 |
> | **6** | **`if x == 0 or 1 or 2:`** | **一边永远走不到** |
>
> **共同点：不报错、能跑完、绿灯。** 唯一的克星是**用边界值去捅它**。

### 7.5 ⭐ 改了 `.py` 不重启节点 = 白改（实测两次）

**第一次（课堂现场）**：

```
22:11:47  改了 src/hello_ros/hello_ros/mode_server.py
22:1x     重新 build
          → 客户端打印：模式已切换到2     ← 新代码生效
22:2x     又改了同一个文件（改字符串里的空格）
          → 客户端打印：模式已切换到2     ← 空格没变！旧代码还在跑
```

**不是改错了，是那个进程已经把旧模块加载进内存了。**

```
磁盘上的 .py    ←── 你改这里
     │
     │  ① 启动时读一次
     ▼
进程内存里的模块  ←── 只认这一份，之后再不看磁盘
```

> **"改了文件"和"改了正在跑的程序"是两件事。**
> **改完 `.py` 的固定动作：改 → `Ctrl+C` → 重跑。**
>
> **怎么判断旧进程还在？** `ps -eo pid,etimes,args | grep <名字>`，
> `etimes` 是"活了多久（秒）"——**几百秒的一定是残留**。

**关于 `--symlink-install`**：本工作区的 Python 包是**可编辑安装**（`install/hello_ros/lib/python3.14/site-packages/hello-ros.egg-link` 指回 `src/`），
所以**改了 `.py` 不用 build**，只要重启节点。**要 build 的只有 `.msg` / `.srv` / `.xml` / `CMakeLists.txt`。**

### 7.6 ⭐ `.msg` 的**顺序**就是内存里的顺序

`.msg` 里字段的排列，决定了生成出来的结构体里成员的排列。
Python 里看不出来（都是属性，点哪个都行），但 C++ 那边 `__struct.hpp` 里的成员是**按顺序**排的。

> 所以**别随便调整 `.msg` 里字段的顺序** —— 它们是合同的一部分，改了顺序等于改合同。
> 追加字段在末尾是安全的；插在中间、删掉、改类型，都是**破坏性变更**。

---

## 8. 踩坑记录

### ❌ 坑 1：名字靠猜（`package.xml` 连错三次）

要给接口包加依赖，凭印象连着写了三个都错的：`rosidl_default_runtime` → `rosidl_interface_packages` → ……

**根因**：把 `CMakeLists.txt` 里的**函数名**（`rosidl_generate_interfaces`）和 `package.xml` 里的**包名**当成了同一袋东西。

> **它们是两袋完全不同的东西：**
> - `package.xml` 里全是 **`<标签>真实存在的包名</标签>`**
> - `CMakeLists.txt` 里是 **`函数名(参数)`**
>
> **`find_package(X)` 里的 X 和 `<depend>X</depend>` 里的 X 才是同一个 X。**

**正确通道 —— 不猜，对表**：

```bash
ros2 pkg xml example_interfaces | grep -E 'depend|group'
```

### ❌ 坑 2：把 TODO 骨架填进了 `if(BUILD_TESTING)` 里面

```cmake
if(BUILD_TESTING)
  find_package(geometry_msgs REQUIRED)          # ✗ 写进"另一个格子"了
  rosidl_generate_interfaces(...)
  ...
endif()
```

`if(...)` / `endif()` 是**一对括号**，框住的是"只在测试时才需要的东西"。
把生成规则写进去，等于"不跑测试就不生成接口"。

**正确位置**：跟 `find_package(ament_cmake REQUIRED)` 挨着，在 `if(BUILD_TESTING)` **之前**。

### ❌ 坑 3：`setup.py` 复制粘贴，把 `status_listener` 写成了 `status_talker`

```python
'status_listener = hello_ros.status_talker:main',     # ✗ 名字对，右边的文件错了
```

**症状极其迷惑**：跑 `ros2 run hello_ros status_listener`，屏幕上是 `[status_talker]: 发布:` ——
**它是个发布者**。于是同一个话题上有**两个发布者**，`ros2 topic echo` 的输出开始交错：

```
r2d2  95 1  1.0
r2d2  95 1  1.0      ← 重复！
r2d2  90 2  2.0
```

**怎么看出来的**：两个进程的启动时间戳差 7 毫秒，数值正好错开 7 拍。

> **"数值莫名其妙"的第一反应，永远是"是不是有第二个进程"。**

```bash
ps -eo pid,etimes,args | grep -E 'hello_ros' | grep -v grep
ros2 topic info /robot_status -v        # 看 Publisher count 是不是 1
```

**这是"串门"的第三次**：右边的东西是对的，只是放错了格子。

### ❌ 坑 4：把自依赖写进了**自己**的 `package.xml`

`<depend>hello_ros_interfaces</depend>` 要加在 **`hello_ros`** 的 `package.xml` 里
（因为是用它的那一方），却加进了 `hello_ros_interfaces` 自己的。

```
The package "hello_ros_interfaces" must not "build_depend" on a package
with the same name as this package
```

**报错把话说得明明白白**：一个包不能依赖它自己。

> **判断口诀：`package.xml` 里该写谁，取决于"这个包**用**了谁"，不是"谁**被**用了"。**

### ❌ 坑 5：`Unknown package 'hello_ros_interfaces'` —— 其实什么都没错

写完文件就想 `ros2 interface show`，报：

```
Unknown package 'hello_ros_interfaces'
```

**原因：还没 build 过。** `ros2 interface show` 只看得见 **install 空间**。

```bash
ls install/          # 有没有 hello_ros_interfaces？
```

**没有 → 去 build。** 不是代码问题。

### ❌ 坑 6：把提示里的省略号抄进了代码

```python
response.message = '模式已切换到 ...'        # ✗ 那个 ... 是我留下的省略号
```

**这是本关第二次犯"把提示当代码"**（第一次是 `--- TODO 1：...`，见 §7.3）。

> **凡是聊天里 `???` 和 `# TODO` 周围的中文，都是给你看的，不是给你抄的。**

### ⚠️ 坑 7：`No module named 'hello_ros_interfaces.srv'` —— build 是**成功**的

学生预测"build 会失败"，实测：**build 全绿（`Finished`），失败的是后面那句 `import`。**

```
[INFO] Finished <<< hello_ros_interfaces [2.01s]
...
ModuleNotFoundError: No module named 'hello_ros_interfaces.srv'
```

**"构建成功"和"能用"是两件事。**

**这条要查哪个登记表？** 三张表逐个对：

| 检查 | 命令 | 这一关的实际情况 |
|---|---|---|
| 生成登记表 | `grep rosidl_generate_interfaces src/hello_ros_interfaces/CMakeLists.txt` | 写了 `SetMode.srv` 吗？ |
| 依赖登记表 | `ros2 pkg xml hello_ros \| grep interfaces` | `<depend>hello_ros_interfaces</depend>` 在吗？ |
| —— | `ros2 interface package hello_ros_interfaces` | 系统认得这个接口吗？ |

### ⚠️ 坑 8：`ros2 service call` 成功 ≠ 业务逻辑对

见 §7.4。`"{mode: 5}"` 返回 `success=True`，**服务调用是成功的，业务判断是错的。**

> **CLI 只告诉你"消息送到了、响应回来了"。它不验你的 `if`。**

---

## 9. 自测题

### 9.1 课堂已覆盖（附答案）

<details>
<summary><b>题 1：你写的 <code>.msg</code> 文件，最后变成了几样东西？分别给谁用？</b></summary>

**四种以上，全部是生成的，你一个字没写。**

| 产物 | 给谁用 |
|---|---|
| `_robot_status.py` | **Python**（你 `import` 的就是它） |
| `robot_status.hpp` / `_struct.hpp` | **C++** |
| `RobotStatus.idl` | 跨语言**中间语言**（rosidl 内部用） |
| `RobotStatus.json` | 类型描述 |
| `_robot_status_s.c` | 底层 C 胶水 |

所以 `.msg` 是**源头**，其余都是派生物。**改派生物没用，下次 build 会被覆盖。**

验证：
```bash
sed -n '1,3p' install/hello_ros_interfaces/share/hello_ros_interfaces/msg/RobotStatus.idl
# 写着 "with input from hello_ros_interfaces/msg/RobotStatus.msg"
```
</details>

<details>
<summary><b>题 2：`.msg` 文件写完存盘了，为什么 <code>ros2 interface show</code> 说找不到？</b></summary>

**因为"文件在磁盘上"和"被登记了"是两回事。**

要有三张表都点头，一个接口才真正存在：

| 表 | 在哪 | 缺了会怎样 |
|---|---|---|
| 生成登记表 | `CMakeLists.txt` 的 `rosidl_generate_interfaces` | 不生成代码 |
| 依赖登记表 | `package.xml` | build 找不到包 |
| 分组标签 | `<member_of_group>rosidl_interface_packages</member_of_group>` | 构建顺序乱 |

而且**必须要 build 过**：`ros2 interface show` 只看得见 **install 空间**里的东西。

```bash
ls install/          # 第一件事：build 过吗？
```
</details>

<details>
<summary><b>题 3：<code>.srv</code> 里分隔请求和响应的是什么？有什么格式要求？</b></summary>

**一行恰好三个减号：`---`。**

| 写法 | 结果 |
|---|---|
| `---` | ✅ |
| `--- # 注释` | ❌ `Could not find separator` |
| ` ---`（前导空格） | ❌ 同上 |

切出来的两个类：
```python
SetMode.Request      # 上半部分
SetMode.Response     # 下半部分
```
</details>

<details>
<summary><b>题 4：<code>RobotStatus</code> 里嵌了一个 <code>geometry_msgs/Point</code>，要多做哪两件事？</b></summary>

**两处登记，一个给"生成时"，一个给"运行时"：**

```cmake
# CMakeLists.txt —— 生成代码时要能找到 Point 的定义
DEPENDENCIES geometry_msgs
```

```xml
<!-- package.xml —— 运行时要能找到 Point 的定义 -->
<depend>geometry_msgs</depend>
```

用起来**没有额外语法**：`msg.position.x = 1.0`，一路点下去就行。
</details>

<details>
<summary><b>题 5：<code>if request.mode == 0 or 1 or 2:</code> 有什么问题？为什么？</b></summary>

**它恒为真，`else` 是死代码。**

`or` 返回的不是 `True`/`False`，**是"第一个为真的那个值"**：

```
(request.mode == 0)   or   1   or   2
        ↑                  ↑
     一个比较          字面量 1 —— 恒真
```

第一个比较要是假，就轮到 `1`；`1` 恒真，表达式到此结束。

实测 `mode=5` 和 `mode=999` 都返回 `success=True`。

正确写法：
```python
if request.mode in (0, 1, 2):
```
</details>

<details>
<summary><b>题 6：改了 <code>.py</code> 和改了 <code>.msg</code>，分别要不要重新 build？</b></summary>

| 改了什么 | 要不要 build | 为什么 |
|---|---|---|
| `.py` | **不用**，但要**重启节点** | 可编辑安装，走软链；但旧进程内存里还是旧模块 |
| `.msg` / `.srv` | **必须 build** | 要**生成代码**，生成要跑工具 |
| `setup.py` / `package.xml` | **必须 build** | 改的是"装什么"，不是"装的内容" |

**最容易忘的是第一行**：改了 `.py` 不重启节点 = 白改。实测见 §7.5。
</details>

<details>
<summary><b>题 7：`ros2 service call` 返回 <code>success=True</code>，能说明业务逻辑对吗？</b></summary>

**不能。**

CLI 只告诉你"**消息送到了、响应回来了**"。它不验你的 `if`。

§7.4 的现场就是：`"{mode: 5}"` 越界，照样返回 `success=True` —— 因为 `if` 恒真。

**服务调用成功 ≠ 业务判断正确。** 这是"绿灯 ≠ 做了你想做的事"的又一个例子。
</details>

<details>
<summary><b>题 8：`ros2 interface show RobotStatus` 打印 5 行还是 8 行？</b></summary>

**8 行。** 文件里是 5 行，但：

- 嵌套的 `Point` 被**展开**成 3 行（缩进显示）
- 空行会被**原样保留**（`SetMode.srv` 的 6 行就是这么来的）

**它不替你做任何"整理"，你写什么它显示什么。**
</details>

### 9.2 留给下次的思考题（无答案）

1. **字段类型改成 `float64` 会怎样？** 现在 `battery` 是 `float32`，`.msg` 里改成 `float64` 再 build —— Python 代码要改吗？C++ 代码要改吗？（提示：想想 §2.1 那张图。）
2. **在 `.msg` 中间插一个字段会怎样？** 把 `mode` 挪到 `robot_name` 前面，重新 build —— 会报错吗？会有别的问题吗？（提示：§7.6。）
3. **一个 `.msg` 能不能用另一个自定义 `.msg`？** 试着让 `RobotStatus` 里嵌一个你自己写的消息类型，`DEPENDENCIES` 该写什么？
4. **`SetMode.srv` 的响应里加一个 `int32 old_mode`**，让服务端把"切换前的模式"返回去。服务端怎么知道切换前是什么？（提示：这和参数、状态有关。）
5. **`.msg` 里的常量怎么写？** 查 `ros2 interface show sensor_msgs/msg/NavSatStatus`，看 `int8 STATUS_NO_FIX = -1` 这种行是什么，怎么在代码里用。
6. **同一份 `.msg`，Python 发的和 C++ 发的能互相收吗？** 这是下一关（C++ 支线）要实测的。

---

## 10. 附：跨关待办

> 这是第 6 关结束时，老师给的**跨关观察**。第 5 关记了三条，看看这一关的表现。

### ① 贴半截输出 / 不读输出

**本关有进步**：`mode: 5` 那次把完整的响应、完整的服务端日志都贴了。

**但要盯的是"读"那一半**：`success=True, message='模式已切换到 ...'` 这行就在屏幕上，
里面**明明白白有两个异常**（越界放行、省略号），当时没读出来。

> **贴出来 ≠ 读过了。** 每次贴之前先扫一遍：**有没有哪个值不对劲？**

### ② 名字靠猜，不靠查

本关犯了 —— `package.xml` 连错三次（坑 1）。

**这次找到了正确的通道**：`ros2 pkg xml <包名>` 对表，比翻文档快。
**代价对比**：猜错三次花了十几分钟；`ros2 pkg xml example_interfaces` 一条命令 2 秒。

> **凡是"应该有个名字/字段/参数"的地方，都是可枚举的 —— 都可以查。**

### ③ 盒子和内容

**本关没犯。** `msg.position.x`、`SetMode.Request()`、`response.success` 全都写对了。

> 五关的老账（`return response.sum`、忘 `.value`、`publish_feedback(序列)`），这一关清了。

### ④ 🆕 把提示文字当代码抄（本关新出现，犯了 **2 次**）

| 地点 | 抄进去的东西 |
|---|---|
| `SetMode.srv` 的分隔符行 | `--- TODO 1：...` |
| `mode_server.py` 第 21 行 | `'模式已切换到 ...'`（把我的省略号原样打进去） |

**第二次更有迷惑性** —— 它不报错，只是日志里多打三个点。

> **规则：聊天里 `???` 和 `# TODO` 周围的**中文**，是给你看的；只有**代码块里的英文/符号**才是给你抄的。**
> **拿不准的时候问一句，比抄错再改快。**
> （第 5 关的 `publish_feedback('我是被取消的')` 是同一个坑的第一次。）

### ⑤ 🆕 "文件在磁盘上 ≠ 被注册了"（本关的核心，也会跟着你走）

| 关 | 位置 | 症状 |
|---|---|---|
| 4 | `setup.py` 的 `data_files` | launch 文件装了但 `ros2 launch` 找不到 |
| 5 | `setup.py` 的 `entry_points` | `No executable found` |
| 6 | `CMakeLists.txt` 的 `rosidl_generate_interfaces` | `Unknown package` / 接口找不到 |

**症状长得完全不一样，根因是同一个。**
**以后遇到"我明明写了啊"，第一反应改成："我登记了吗？"**

---

## 附：本关命令速记卡

```bash
# ---------- 看接口 ----------
ros2 interface package hello_ros_interfaces                 # 这个包提供了哪些接口
ros2 interface show hello_ros_interfaces/msg/RobotStatus    # 字段长什么样
ros2 interface show hello_ros_interfaces/srv/SetMode        # 注意分隔线也会打出来

# ---------- 查包（排查第一步）----------
ls install/                                                 # build 过了吗
ros2 pkg list | grep hello                                  # 系统认得这个包吗
ros2 pkg xml example_interfaces                             # 跟标准答案对表

# ---------- 跑话题那一对 ----------
ros2 run hello_ros status_talker        # 终端 A
ros2 run hello_ros status_listener      # 终端 B
ros2 topic echo /robot_status           # 终端 C

# ---------- 跑服务那一对 ----------
ros2 run hello_ros mode_server          # 终端 A
ros2 run hello_ros mode_client          # 终端 B
ros2 service call /set_mode hello_ros_interfaces/srv/SetMode "{mode: 5}"

# ---------- 看生成物 ----------
ls install/hello_ros_interfaces/include/hello_ros_interfaces/hello_ros_interfaces/msg/
find install/hello_ros_interfaces -name '*.idl'
python3 -c "from hello_ros_interfaces.msg import RobotStatus; print(RobotStatus.get_fields_and_field_types())"

# ---------- 排查残留节点（"数值莫名其妙"的第一反应）----------
ps -eo pid,etimes,args | grep -E 'hello_ros' | grep -v grep
#   etimes = 活了多久（秒），几百秒的一定是残留
ros2 topic info /robot_status -v        # Publisher count 应该是 1

# ---------- lint / 测试 ----------
colcon test --packages-select hello_ros
colcon test-result --verbose
```
