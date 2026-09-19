# C++ 支线 · 02 · 订阅者：从 `listener.cpp` 到多字段消息

> 前置：[cpp-01-getting-started.md](cpp-01-getting-started.md)（C++ 五个符号、`talker.cpp`）、[lesson-01-topic.md](lesson-01-topic.md)（Python 版发布/订阅）、[lesson-05-action.md](lesson-05-action.md)（盒子/内容）、[lesson-06-custom-message.md](lesson-06-custom-message.md)（自定义消息）

---

## 目录

- [1. 本步目标](#1-本步目标)
- [2. 核心概念](#2-核心概念)
- [3. 完整代码](#3-完整代码)
- [4. API 速查表](#4-api-速查表)
- [5. 命令行工具速查](#5-命令行工具速查)
- [6. 构建与运行流程](#6-构建与运行流程)
- [7. 实测现象与结论 ⭐](#7-实测现象与结论-)
- [8. 踩坑记录](#8-踩坑记录)
- [9. 自测题](#9-自测题)
- [10. 附：跨关待办](#10-附跨关待办)
- [附：命令速记卡](#附命令速记卡)

---

## 1. 本步目标

把 Python 版的订阅者**逐行对着**翻译成 C++。两步，形状完全一样，只有消息类型不同：

| | 源文件 | 对照的 Python | 话题 | 消息 |
|---|---|---|---|---|
| 第 1 步 | `src/listener.cpp` | `src/hello_ros/hello_ros/listener.py` | `chatter` | `std_msgs/msg/String`（1 个字段） |
| 第 2 步 | `src/status_listener.cpp` | `src/hello_ros/hello_ros/status_listener.py` | `robot_status` | `hello_ros_interfaces/msg/RobotStatus`（4 个字段 + 1 个嵌套） |

**不在本步范围内的**：第 2 步的发布者没写 C++ 版 —— 直接用现成的 Python `status_talker` 发，C++ 收。**这本身就是一次验证**（见 §7.1）。

---

## 2. 核心概念

### 2.1 订阅者的完整形状

Python 一行搞定：

```python
self.sub = self.create_subscription(RobotStatus, 'robot_status', self.callback, 10)
```

C++ 要三个参数，**顺序和 Python 一样**，但每一块的写法都变了：

```cpp
sub_ = this->create_subscription<hello_ros_interfaces::msg::RobotStatus>(   // ① 消息类型
    "robot_status",                                                          // ② 话题名
    10,                                                                      // ③ 队列长度
    [this](const hello_ros_interfaces::msg::RobotStatus::SharedPtr msg)      // ④ 回调
        { callback(msg); });
```

| | Python | C++ |
|---|---|---|
| 消息类型 | 第 1 个参数，位置 | 写进 `<>`，**不在参数列表里** |
| 话题名 | `'robot_status'` | `"robot_status"`（引号不能混） |
| 队列长度 | `10` | `10`（一样） |
| 回调 | `self.callback` 直接给 | **要用 lambda 包一层** |

**顺序一模一样，只是消息类型从"第 1 个参数"挪到了"尖括号里"** —— 所以参数整体前进了一位。这是最容易数错的地方。

### 2.2 ⭐ lambda 是个"适配器"

`talker.cpp` 里你已经写过一次 lambda 了：

```cpp
timer_ = this->create_wall_timer(1s, [this]() { tick(); });
//                                    ↑     ↑
//                                  捕获    参数列表是【空的】
```

订阅者的 lambda **形状一样，但参数列表里有东西**：

```cpp
[this](const std_msgs::msg::String::SharedPtr msg) { callback(msg); }
//                                ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
//                                这里多出来一个"收到的消息"
```

**为什么不一样？** 因为 `create_wall_timer` 和 `create_subscription` 要求的回调**签名不同**：

| 谁要回调 | 回调得长什么样 | 为什么 |
|---|---|---|
| `create_wall_timer` | `()` —— 不收参数 | 定时器到点了，**没有"什么东西"要交给你** |
| `create_subscription` | `(const T::SharedPtr msg)` | 消息到了，**得把消息交给你** |

> 💡 **lambda 是一层"翻译"**：把「你类里那个 `callback` 成员函数」翻译成「rclcpp 想要的那个函数形状」。
> 定时器要空参数的 → 翻译成 `[this]() { tick(); }`
> 订阅者要收消息的 → 翻译成 `[this](msg) { callback(msg); }`

**`[this]` 是什么？** 因为 `tick()` / `callback(msg)` 是**成员函数**，得知道"调哪个对象上的"。`[this]` 就是把"当前这个节点对象"带进去。少了它，编译器会说：

```
error: 'this' was not captured for this lambda function
error: cannot call member function 'void Listener::callback(...)' without object
```

**为什么不能直接传 `callback`？** 试过就是这样：

```cpp
sub_ = this->create_subscription<...>("chatter", 10, callback);   // ❌
```
```
error: invalid use of non-static member function 'void Listener::callback(...)'
```

> Python 里 `self.callback` **自带**"我是绑在哪个对象上的"这个信息（绑定方法）；
> C++ 里光写 `callback` 只是**一个函数地址**，它不知道自己该绑在哪个对象上。
> `[this]` 就是手动把这块补上。

### 2.3 ⭐⭐ 成员变量类型：**4 块结构**

这是本步唯一一个**连栽两次**的地方，值得单独立一块。

```cpp
rclcpp:: Subscription < hello_ros_interfaces::msg::RobotStatus > ::SharedPtr  sub_;
  ①            ②                            ③                        ④        ⑤
```

| | 是什么 | 怎么定 |
|---|---|---|
| ① | 库名 | 永远 `rclcpp::` |
| ② | **角色** | 发东西 → `Publisher`；收东西 → `Subscription` |
| ③ | 尖括号里装**消息类型** | 和 `create_subscription<...>` 尖括号里的**完全一样** |
| ④ | 固定尾巴 | `::SharedPtr` |
| ⑤ | **变量名** + 分号 | `sub_;` |

**关键是②④这两块**。写错的人（包括你，两次）都是**只写了 ③**：

```cpp
hello_ros_interfaces::msg::RobotStatus::SharedPtr sub_;   // ❌ 只有 ③ + ④
std_msgs::msg::String sub_;                               // ❌ 只有 ③（第一次）
```

**原因是脑子里想的是"这是条消息"，但这一格装的不是消息，是"订阅者"。**

> 🔑 **一句话记住**：
> **先问「这一格装的是个什么东西？」**
> 装的是**订阅者** → 外层就是 `Subscription`，消息类型塞进尖括号里。
> 装的是**发布者** → 外层就是 `Publisher`。
> 装在尖括号里的那个，才是消息。

**别背，照抄 `talker.cpp`。** 三个角色其实是同一个模板：

```cpp
rclcpp::Publisher   <std_msgs::msg::String>                     ::SharedPtr pub_;
rclcpp::Subscription<std_msgs::msg::String>                     ::SharedPtr sub_;
rclcpp::Subscription<hello_ros_interfaces::msg::RobotStatus>    ::SharedPtr sub_;
```

**只有②和③在变，①和④永远不动。** 这就是为什么 `pub_` 那一行要背下来 —— 它是模板。

### 2.4 `.` 和 `->`：第 5 关的盒子/内容，C++ 逼你说出来

这条在 [cpp-01 §2.2](cpp-01-getting-started.md) 讲过，这一步第一次遇到**两个混着用**：

```cpp
msg->position.x
   ^^        ^
   箭头       点
```

| 为什么 | |
|---|---|
| `msg` 是 `const RobotStatus::SharedPtr` | **是个盒子**（智能指针）→ 用 `->` |
| `msg->position` 是 `geometry_msgs::msg::Point` | **是个值**（不是指针）→ 用 `.` |

**规律：遇到盒子用箭头，遇到内容用点。** 一个个往下剥。

> 对比 Python：`msg.position.x` —— 全是点。因为 Python **不区分**盒子和内容，`. ` 通吃。
> 这就是 [lesson-05](lesson-05-action.md) 说的"C++ 逼你把第 5 关那个区分写出来"。

### 2.5 格式符：**按位置对**，C 不拦你

```cpp
RCLCPP_INFO(this->get_logger(), "收到: %s 电量=%.1f mode=%d x=%.1f",
            msg->robot_name.c_str(), msg->battery, msg->mode, msg->position.x);
//          ↑ 1            ↑ 2         ↑ 3        ↑ 4
//          %s             %.1f        %d         %.1f
```

**四个格式符和四个参数，按位置一一对应。**

| 字段类型 | 格式符 | 注意 |
|---|---|---|
| `std::string` | `%s` | ⚠️ **必须接 `.c_str()`**，C 只吃 C 风格字符串 |
| `float` / `double` | `%f` | ⚠️ **默认打 6 位小数**；想留 1 位要写 `%.1f` |
| `int` | `%d` | |
| `bool` | —— | ⚠️ **没有能直接用的**（`%d` 能给 0/1，但不标准） |

**🔴 最危险的一条**：位置错了 C **不拦你**。

你把 `mode` 漏掉、让 `position.x` 往前滑了一格，编译器只给**两条 warning**：

```
warning: format '%d' expects argument of type 'int', but argument 7 has type '..._x_type' {aka 'double'}
warning: format '%f' expects a matching 'double' argument
```

**`warning` 不是 `error` —— build 照样全绿，程序照样能跑，然后打印出垃圾。**
`printf` 家族是"照着你的话去内存里乱读"，读到什么全凭运气（实测见 §7.3）。

> ⚠️ `argument 7` 从 5 开始数，是因为 `RCLCPP_INFO` 是个宏，在背后又塞了文件/行号之类的参数进去。**别管编号，看后半句。**

### 2.6 CMake 是"点名制" —— 但这次要点 **4 个**名

[cpp-01 §6.2](cpp-01-getting-started.md) 讲过 CMake 不扫描目录。**新增一个 `.cpp`，要在这 4 个地方点它的名：**

| # | 位置 | 写什么 |
|---|---|---|
| ① | `find_package(...)` | **消息类型所在的包**（不是消息名！） |
| ② | `add_executable(<名字> src/<文件>.cpp)` | 新可执行文件的名字 + 源文件 |
| ③ | `target_link_libraries(<名字> rclcpp::rclcpp ${<包名>_TARGETS})` | 链接 |
| ④ | `install(TARGETS ...)` | **漏了这个 → build 绿灯，`ros2 run` 报 `No executable found`**（坑 8） |

**②和③ 是成对的**：`add_executable` 给名字，`target_link_libraries` 用**同一个名字**。名字写岔了就报：

```
Cannot find target "status_listener"
```

**① 的关键**：`find_package` 要的是**功能包名**，不是消息名。写成消息名会报：

```
CMake Error at CMakeLists.txt:12 (find_package):
  Could not find a package configuration file provided by "RobotStatus" with
  any of the following names:
    RobotStatusConfig.cmake
    robotstatus-config.cmake
```

> 💡 **这条报错自己是证据**：CMake 找的文件叫 **`<包名>Config.cmake`**。
> 只有**功能包**才有这种配置文件，**消息没有**。
> 第 6 关建的包叫 `hello_ros_interfaces`，`RobotStatus` 只是它里面的一个 `.msg`。

---

## 3. 完整代码

### `src/listener.cpp` —— 第 1 步（订阅 `/chatter`）

```cpp
#include "rclcpp/rclcpp.hpp"
#include "std_msgs/msg/string.hpp"

class Listener : public rclcpp::Node
{
public:
    Listener() : Node("listener_cpp")
    {
        sub_ = this->create_subscription<std_msgs::msg::String>(
            "chatter", 10, [this](const std_msgs::msg::String::SharedPtr msg) { callback(msg); });
    }

private:
    void callback(const std_msgs::msg::String::SharedPtr msg)
    {
        RCLCPP_INFO(this->get_logger(), "收到: %s", msg->data.c_str());
    }

    rclcpp::Subscription<std_msgs::msg::String>::SharedPtr sub_;
};


int main(int argc, char ** argv)
{
    rclcpp::init(argc, argv);
    rclcpp::spin(std::make_shared<Listener>());
    rclcpp::shutdown();
    return 0;
}
```

### `src/status_listener.cpp` —— 第 2 步（订阅 `/robot_status`）

和上面**逐行同构**，只有三处不同（已标注）：

```cpp
#include "rclcpp/rclcpp.hpp"
#include "hello_ros_interfaces/msg/robot_status.hpp"     // ← 变①：包名 + 蛇形文件名

class StatusListener : public rclcpp::Node
{
public:
    StatusListener() : Node("status_listener")
    {
        sub_ = this->create_subscription<hello_ros_interfaces::msg::RobotStatus>(   // ← 变②
            "robot_status", 10,
            [this](hello_ros_interfaces::msg::RobotStatus::SharedPtr msg) { callback(msg); });
    }

private:
    void callback(const hello_ros_interfaces::msg::RobotStatus::SharedPtr msg)
    {
        // ← 变③：1 个字段 → 4 个字段，其中 position.x 是嵌套的
        RCLCPP_INFO(this->get_logger(), "收到: %s 电量=%.1f mode=%d x=%.1f",
                    msg->robot_name.c_str(), msg->battery, msg->mode, msg->position.x);
    }

    rclcpp::Subscription<hello_ros_interfaces::msg::RobotStatus>::SharedPtr sub_;
};


int main(int argc, char ** argv)
{
    rclcpp::init(argc, argv);
    rclcpp::spin(std::make_shared<StatusListener>());
    rclcpp::shutdown();
    return 0;
}
```

> 📌 **头文件是蛇形的**：`RobotStatus` → `robot_status.hpp`。
> 路径规律：`<包名>/msg/<消息名的蛇形>.hpp`。
> 查法：`ls install/hello_ros_interfaces/include/hello_ros_interfaces/hello_ros_interfaces/msg/`

### `CMakeLists.txt` 的 4 处

```cmake
# ① 消息所在的【功能包】—— 注意不是 "RobotStatus"
find_package(hello_ros_interfaces REQUIRED)

# ② ③ 成对出现，名字要一致
add_executable(status_listener src/status_listener.cpp)
target_link_libraries(status_listener rclcpp::rclcpp ${hello_ros_interfaces_TARGETS})

# ④ 漏了这处 → build 绿灯，ros2 run 报 No executable found
install(TARGETS hello_cpp talker listener status_listener
  DESTINATION lib/${PROJECT_NAME})
```

⚠️ `${..._TARGETS}` 里的包名**跟着 ① 一起换**。原来 listener 用的是 `${std_msgs_TARGETS}`，这次换成 `${hello_ros_interfaces_TARGETS}`。

### `package.xml` —— **实测：不用改**

第 2 步之前留了个问题：`RobotStatus` 里嵌套了 `geometry_msgs/Point`，`package.xml` 要不要补 `<depend>geometry_msgs</depend>`？

**实测结论：不用补。** 见 §7.5。

---

## 4. API 速查表

### 订阅者（构造函数里调用）

```cpp
// 完整形状
sub_ = this->create_subscription<消息类型>(
    "话题名", 队列长度,
    [this](const 消息类型::SharedPtr msg) { callback(msg); });
```

| 参数 | 说明 |
|---|---|
| `<消息类型>` | 和 Python 版 `create_subscription` 的第 1 个参数**相同**，只是挪进尖括号 |
| `"话题名"` | 双引号，不带 `/` 前缀（`"robot_status"` 而不是 `"/robot_status"`） |
| 队列长度 | 和 Python 版一样，一般 `10` |
| lambda | `[this](const T::SharedPtr msg) { callback(msg); }` |

### 成员变量（照抄）

```cpp
rclcpp::Publisher   <std_msgs::msg::String>                  ::SharedPtr pub_;
rclcpp::Subscription<std_msgs::msg::String>                  ::SharedPtr sub_;
rclcpp::Subscription<hello_ros_interfaces::msg::RobotStatus> ::SharedPtr sub_;
```

**一个变量声明要有三样东西**：

```cpp
rclcpp::Subscription<...>::SharedPtr   sub_   ;
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^   ^^^^   ^
              类型                      名字   分号
```

### 打印（`RCLCPP_INFO`）

```cpp
RCLCPP_INFO(this->get_logger(), "格式串", 参数1, 参数2, ...);
```

**格式串里有多少个 `%`，后面就得有多少个参数，按位置的顺序一一对应。**

| 字段类型 | 格式符 | 例 |
|---|---|---|
| `std::string` | `%s`（接 `.c_str()`） | `msg->robot_name.c_str()` |
| `float` / `double` | `%f` / `%.1f` | `msg->battery`（float32） |
| `int` / `int32` | `%d` | `msg->mode` |
| `bool` | ⚠️ 无直接格式符 | 别打印，或用三元表达式 |

### `.` vs `->`

| 遇到 | 用 | 因为 |
|---|---|---|
| 智能指针（`SharedPtr`） | `->` | 是**盒子** |
| 普通成员（值） | `.` | 是**内容** |

```cpp
msg->position.x
// 盒子 → 箭头    内容 → 点
```

---

## 5. 命令行工具速查

```bash
# ---------- 验收：先确认可执行文件登记了（不依赖任何节点）----------
ros2 pkg executables hello_ros_cpp
#    期望：出现 listener 和 status_listener

# ---------- 看谁在发 ----------
ros2 topic info /robot_status -v

# ---------- 话题名到底带不带斜杠 ----------
ros2 topic list

# ---------- 看函数返回什么类型（成员变量该写什么）----------
# 不用敲长命令：VSCode 里在函数名上按 F12 / Ctrl+点击，直接跳定义

# ---------- 查头文件目录（报错里的名字拿去 ls）----------
ls install/hello_ros_interfaces/include/hello_ros_interfaces/hello_ros_interfaces/msg/
```

---

## 6. 构建与运行流程

### 构建

```bash
cd ~/ros2_learn_ws
colcon build --packages-select hello_ros_cpp
#    期望：Finished <<< hello_ros_cpp [  x.xxs ]
#    如有 error / warning，逐个看完再动手（见 §8 的顺序原则）
```

### 验收清单

```bash
# ① 登记成功了吗
ros2 pkg executables hello_ros_cpp
#    期望：hello_cpp  talker  listener  status_listener

# ② 第 1 步：C++ 收 C++（C++ talker 是 hello_ros_cpp 的 talker）
#    终端 A
ros2 run hello_ros_cpp talker
#    终端 B
ros2 run hello_ros_cpp listener
#    期望：B 每秒一行「收到: ...」，和 A 的内容对得上

# ③ 第 2 步：Python 发，C++ 收 【跨语言】
#    终端 A
ros2 run hello_ros status_talker
#    终端 B
ros2 run hello_ros_cpp status_listener
#    期望：两边逐字段一致 ——
#      A: 发布: r2d2 电量=65.0 mode=1 x=7.0
#      B: 收到: r2d2 电量=65.0 mode=1 x=7.0

# ④ 收工
#    每个终端 Ctrl+C，然后确认没留残留
ros2 topic info /robot_status
```

---

## 7. 实测现象与结论 ⭐

### 7.1 ⭐⭐ C++ 和 Python 的节点能直接通信（跨语言，无需任何转换）

第 2 步是 **Python 发布 / C++ 订阅**，不是同语言。

```
终端 A（Python）  发布: r2d2 电量=65.0 mode=1 x=7.0
终端 B（C++）     收到: r2d2 电量=65.0 mode=1 x=7.0
```

**逐字段一致，包括嵌套的 `x`。**

> 这是 ROS 2 的核心卖点之一：**话题上的数据格式由 `.msg` 定义，和实现语言无关。**
> `RobotStatus.msg` 是一份"合同"，Python 和 C++ 各自生成自己的代码去遵守它。
> 所以 [cpp-01 §6.1](cpp-01-getting-started.md) 那条结论在这里再验一次。

### 7.2 ⭐ 两版 `status_listener` 的输出对比

| | Python 版 | C++ 版 | |
|---|---|---|---|
| 前缀 | `收到: ` | `收到: ` | ✅ |
| robot_name | `r2d2` | `r2d2` | ✅ |
| 电量 | `65.0` | `65.0` | ✅（`%.1f`） |
| mode | `1` | `1` | ✅ |
| x（嵌套） | `7.0` | `7.0` | ✅ |

**唯一要动脑的是格式符**，其余全是"照抄 Python 的字段名"。

### 7.3 ⭐⭐ 格式符错位：build 全绿，输出是垃圾

故意漏掉 `mode` 一个参数（4 个格式符、3 个参数）之后：

```
warning: format '%d' expects argument of type 'int', but argument 7 has type 'double'
warning: format '%f' expects a matching 'double' argument
```

**是 `warning` 不是 `error`** —— build **通过了**。

> **这就是 `printf` 家族最危险的地方**：它不检查数量，只按你说的格式去**内存里乱读**。
> 少一个参数 = 读到栈上的垃圾数据。类型不对 = 把 float 的二进制当 int 解释。
> **同类实测**（cpp-01 做的探针）：`%d` 配 `float 85.5` 打出 **311323144**。
> 更狠的：`%s` 配一个 `int` → **段错误，直接崩**。

**教训：`RCLCPP_INFO` 那行必须自己数。** 数格式符、数参数、一个一个对。

### 7.4 ⭐ `%f` 默认打 6 位小数

同一个 `float32` 字段：

| 写法 | 输出 |
|---|---|
| Python `f'{msg.battery}'` | `65.0` |
| C++ `%f` | `65.000000` |
| C++ `%.1f` | `65.0` |

> **两种语言的性格差别**：
> **Python 帮你美化**（float 的 repr 自动去掉多余的零）；
> **C 不猜你的心思** —— 你说 `%f` 它就老老实实给你 6 位，想要 1 位就写 `%.1f`。

### 7.5 ⭐ 嵌套消息的依赖：**不需要显式 `find_package(geometry_msgs)`**

`RobotStatus.msg` 里有 `geometry_msgs/Point position`，于是有个合理猜想：是不是得补

```cmake
find_package(geometry_msgs REQUIRED)     # ← 实测：不需要
```
和
```xml
<depend>geometry_msgs</depend>           <!-- ← 实测：不需要 -->
```

**结论：都不用。** 不改这两处，`colcon build` 绿灯 + `ros2 run` 正常运行。

**为什么？** 因为**我们的代码里从来没有一行直接碰 `geometry_msgs`**：

- 唯一的 `#include` 是 `hello_ros_interfaces/msg/robot_status.hpp`
- 那个头文件内部会 `#include` 它需要的 `point__struct.hpp`（第 6 关看过）
- 而 `hello_ros_interfaces` 的 ament 导出（`ament_cmake_export_dependencies-extras.cmake`）会**传递性地**把 `geometry_msgs` 一起 find 进来

> **判据**：**你的代码直接 `#include` 了谁，才需要声明谁。**
> 我们只是"用了 `RobotStatus` 的一个字段"，没有"直接用 `Point`" —— 所以依赖是 `hello_ros_interfaces` 的，不是我们的。

### 7.6 ⭐⭐ 编译器把答案印在报错里（本步第 N 次验证）

本步的多数错误，**报错原文里就含着答案或解法**：

| 你看到的 | 编译器已经告诉你了 |
|---|---|
| `has no member named 'c_ctr'; did you mean 'c_str'?` | **直接给了正确拼写** |
| `Could not find ... provided by "RobotStatus"` + `RobotStatusConfig.cmake` | 命名规律暴露了"它要的是**包名**" |
| `operand types are A and B` | **B 就是正确答案**（类型写错时） |
| `expected ';' at end of member declaration` | 缺什么字符，它说得很清楚 |
| `'chat' was not declared in this scope; did you mean 'char'?` | 这个名字**根本不存在** |
| `'msg' was not declared in this scope` + `'this' was not captured` | 捕获列表该写 `this` |
| `argument 7 has type 'double'` | 格式符配对错了 |

> 🔑 **读 C++ 报错的顺序**：**从上往下，读第一条 error，修它，重编，再看下一条。**
> 后面的错常常是第一条的连锁反应（本步实测：修好第 34 行之后，第 51 行的错才浮出来）。

---

## 8. 踩坑记录

### ❌ 坑 1：`create_subscription` 漏了第 3 个参数

```cpp
sub_ = this->create_subscription<std_msgs::msg::String>("chatter", 10);   // ❌
```
```
error: no matching function for call to
  'create_subscription<std_msgs::msg::String>(const char [8], int)'
note: candidate expects 3 arguments, 2 provided
```

**`note:` 那行直接告诉你"要 3 个，你给了 2 个"。**

**根因**：把 Python 的参数顺序（类型, 话题, 回调, 队列）和 C++ 的（话题, 队列, 回调）混了。
**记忆**：C++ 的**消息类型在 `<>` 里**，所以参数列表从"话题名"开始，一共 3 个。

### ❌ 坑 2：把裸成员函数当回调传

```cpp
sub_ = this->create_subscription<std_msgs::msg::String>("chatter", 10, callback);   // ❌
```
```
error: invalid use of non-static member function 'void Listener::callback(...)'
```

**根因**：Python 的 `self.callback` 是**绑定方法**（自带"绑在哪个对象上"）；C++ 的 `callback` 只是**一个函数地址**，不知道自己属于哪个对象。
**解法**：用 lambda 包一层 —— `[this](...) { callback(...); }`，`[this]` 就是手动把这个信息补上。

### ❌ 坑 3：**「菜单当订单」** —— 把 `timer` 的形状抄给了订阅者

写成了：

```cpp
sub_ = this->create_subscription<...>("chatter", 10, (1s, [this]() { callback(); }));   // ❌
```
```
error: unable to find numeric literal operator 'operator""s'
error: no matching function for call to 'Listener::callback()'
```

**两个错，两个根因**：

| 症状 | 根因 |
|---|---|
| `operator""s` 找不到 | 抄了 `1s`（定时器的周期），订阅者**没有周期参数**。而且 `1s` 这个字面量需要 `using namespace std::chrono_literals;`，这个文件里没有 |
| `callback()` 匹配不上 | lambda 参数列表是**空的**，但 `callback` 要收一个 `msg` |

> ⚠️ **这是"菜单当订单"的第 4 次**（见 [lesson-08 §10③](lesson-08-qos.md)）。
> **`talker.cpp` 里的 `[this]() { tick(); }` 是"定时器"那道菜的配方，不是"订阅者"的。**
> 抄之前先问：**我要的这道菜，回调收几个参数？**

### ❌ 坑 4：函数名靠猜 —— `chat(...)` / `c_ctr()`

```cpp
RCLCPP_INFO(..., "收到: %s", msg->data.c_str());   // ✅ 正确
RCLCPP_INFO(..., "收到: %s", chat(msg->data));     // ❌ 'chat' was not declared in this scope; did you mean 'char'?
RCLCPP_INFO(..., "收到: %s", msg->robot_name.c_ctr());   // ❌ did you mean 'c_str'?
```

**根因**：知道"要做个转换"，但**没记住转换叫什么**，于是自己造了个名字。

**🔴 `c_str()` 是 `std::string` 的成员方法，不是自由函数** —— 要写 `msg->data.c_str()`（点出来），不能写 `c_str(msg->data)`。

> 💡 **遇到"名字记不清"这类问题，不要去"想"，要去"查"**：
> 编译器自己会说 `did you mean 'c_str'?`。
> **可枚举的东西（名字、字段、拼写）永远优先"看一眼"，不要靠回忆。**

### ❌ 坑 5：成员变量写成了**消息类型** —— 载了**两次**

```cpp
std_msgs::msg::String sub_;                                  // ❌ 第一次（listener.cpp）
hello_ros_interfaces::msg::RobotStatus::SharedPtr sub_;      // ❌ 第二次（status_listener.cpp）
```
```
error: no match for 'operator=' (operand types are
  'hello_ros_interfaces::msg::RobotStatus_<...>::SharedPtr'
  and
  'std::shared_ptr<rclcpp::Subscription<hello_ros_interfaces::msg::RobotStatus_<...>, ...>>')
```

**两次都是同一个原因：只写了"消息"，没写"订阅者"。**

**正确** = `rclcpp::Subscription<消息类型>::SharedPtr`（见 §2.3）。

> 💡 **报错里那句 `and` 后面的类型，就是标准答案。** 这次连一个字的推理都不需要 ——
> 编译器把 `Subscription<...>` 原样印出来了。**下次类型写错，先去找 `operand types are` 那行。**

### ❌ 坑 6：**一个声明要三样：类型 / 名字 / 分号**（分号漏了 **3 次**）

```cpp
rclcpp::Subscription<...>::SharedPtr                        // ❌ 缺名字、缺分号
rclcpp::Subscription<...>::SharedPtr sub_                   // ❌ 缺分号
rclcpp::Subscription<...>::SharedPtr sub_                   // ❌ 还是缺分号
rclcpp::Subscription<...>::SharedPtr sub_;                  // ✅
```

三次报错分别是：

```
error: expected unqualified-id before '}' token          ← 它在等一个【名字】
error: 'sub_' was not declared in this scope             ← 后果：构造函数里用不到
error: expected ';' at end of member declaration         ← 它在等一个【分号】
```

> 🔑 **C++ 里每个分号都是"这句话说完了"的句号。** 少一个，整个文件崩。
> **检查口诀**：**类型 → 名字 → 分号**，三样齐了才算一行。
> 报错说 "expected X" 的时候，X **就是它当前缺的那个东西** —— 直接补上。

### ❌ 坑 7：CMake 把**消息名**当成了**包名**

```cmake
find_package(RobotStatus REQUIRED)              # ❌
find_package(hello_ros_interfaces REQUIRED)     # ✅
```
```
Could not find a package configuration file provided by "RobotStatus"
```

**根因**和坑 5 是同一个形状：**把"消息"当成了"更大的那个东西"**。

| 层次 | 名字 |
|---|---|
| 功能包（package） | `hello_ros_interfaces` |
| 消息（message） | `RobotStatus` ← 只是包里的一个 `.msg` 文件 |

**自证的证据**：报错里 CMake 找的文件叫 `RobotStatusConfig.cmake` —— 命名规律 `<包名>Config.cmake`。**消息没有这种配置文件。**

### ❌ 坑 8：`CMakeLists.txt` 里的注释少了 `#`

```
CMake Error at CMakeLists.txt:52:
  Parse error.  Expected a command name, got unquoted argument with text "来。一共".
```

一行中文注释的**开头漏了 `#`**，CMake 就把那行中文**当成一条命令名**去执行了。

> CMake 的注释符和 Python 一样是 `#`。
> **报错里带引号的那段文字，就是它读到的"命令名"** —— 拿它回文件里搜，一搜就找到。

### ❌ 坑 9：一行里有 4 个相似位置时，**逐个改必错**

`"收到: %s 电量=%.1f mode=%d x=%.1f"` 这一行：

- 改 `收到=` 时，只改了第一个，**漏了后面三个**
- 被指出后又**全改了**（连本来正确的 `电量=` `mode=` `x=` 也改成了冒号）
- 而且混用了**全角 `：`** 和**半角 `:`**（代码里一律用半角）

**根因**：把"改这一行"理解成了"改某个字符"。

> 🔑 **正确做法：盯住"目标长什么样"，整行替换。**
> 你要改的**从来不是"哪个字符"**，而是**"这行最后该是什么样"**。
> 一行里有多个长得像的地方时 —— **先数一数有几个**，再写完整的目标行，**复制粘贴替换整行**。

### 🔑 本步坑的公共形状

| 坑 | 形状 |
|---|---|
| 1, 2, 3 | **API 形状记混** —— 把"别的函数/别的语言"的形状套了过来 |
| 4 | **名字靠猜** —— 知道要做什么，但没去查它叫什么 |
| 5, 7 | ⭐ **层次混淆** —— 把"消息"当成"订阅者"/"包"（同一个根因，载了 3 次） |
| 6 | **语法细节漏项** —— 类型/名字/分号三样没齐 |
| 8, 9 | **改动的精度** —— 少了一个 `#`；多了/少了不该动的字符 |

---

## 9. 自测题

### 9.1 课堂已覆盖（附答案，先自己答一遍再点开）

**题 1**：`create_subscription` 一共几个参数？分别是什么？为什么消息类型不在里面？

<details><summary><b>答案</b></summary>

**3 个**：话题名、队列长度、回调。

消息类型不在参数列表里，是因为它写在**尖括号 `<>`** 里了（`create_subscription<消息类型>(...)`）。
所以 C++ 的参数列表从"话题名"开始 —— 比 Python 版**少了一个**（Python 是 `(类型, 话题, 回调, 队列)`）。

</details>

**题 2**：为什么不能直接写 `create_subscription<...>("chatter", 10, callback)`？

<details><summary><b>答案</b></summary>

因为 `callback` 是**非静态成员函数**，光写名字只是一个**函数地址**，它不知道自己属于哪个对象。

Python 的 `self.callback` 是**绑定方法**（自带对象信息），C++ 没有这个默认行为。
所以要用 lambda `[this](msg) { callback(msg); }` 手动把 `this` 带进去。

报错原文：`error: invalid use of non-static member function`

</details>

**题 3**：`sub_` 该声明成什么类型？为什么不是 `std_msgs::msg::String`？

<details><summary><b>答案</b></summary>

```cpp
rclcpp::Subscription<std_msgs::msg::String>::SharedPtr sub_;
```

因为 **`sub_` 这一格装的是"订阅者"，不是"消息"**。
消息类型要**塞进尖括号里**，作为订阅者的一个参数。

对照模板：`rclcpp::<角色><消息类型>::SharedPtr`
- 发东西 → `Publisher`
- 收东西 → `Subscription`

</details>

**题 4**：`msg->position.x` 里，为什么是"先箭头、再点"？

<details><summary><b>答案</b></summary>

- `msg` 的类型是 `const RobotStatus::SharedPtr` —— **是个盒子**（智能指针）→ 用 `->`
- `msg->position` 的类型是 `geometry_msgs::msg::Point` —— **是个值**，不是指针 → 用 `.`

**规律：遇到盒子用箭头，遇到内容用点。**

Python 里是 `msg.position.x`（全是点），因为 Python 不区分盒子和内容。

</details>

**题 5**：`RCLCPP_INFO` 里格式符写错位了（比如把 `%d` 配给了 float），会发生什么？

<details><summary><b>答案</b></summary>

**编译只给 warning，不给 error —— build 绿灯通过，但输出是垃圾。**

实测（cpp-01 的探针）：`%d` 配 `float 85.5` → 打印 **311323144**。
更危险的：`%s` 配一个 `int` → **段错误直接崩**。

原因：`printf` 家族**不检查参数数量**，只按你说的格式去内存里乱读。

**所以那行必须自己一个一个数。**

</details>

**题 6**：`CMakeLists.txt` 里新增一个可执行文件，一共要改几个地方？

<details><summary><b>答案</b></summary>

**4 个**：

1. `find_package(<消息所在的包> REQUIRED)`
2. `add_executable(<名字> src/<文件>.cpp)`
3. `target_link_libraries(<名字> rclcpp::rclcpp ${<包名>_TARGETS})`
4. `install(TARGETS ...)` ← **漏了这处 → build 绿灯，`ros2 run` 报 `No executable found`**

②③ 的名字必须**一致**。

</details>

**题 7**：`RobotStatus` 里有 `geometry_msgs/Point position`，那 `find_package(geometry_msgs)` 和 `package.xml` 里的 `<depend>geometry_msgs</depend>` 要不要加？

<details><summary><b>答案</b></summary>

**都不用加。**（实测：不加，build 绿灯 + 正常运行时收数据）

判据：**你的代码直接 `#include` 了谁，才需要声明谁。**

我们的代码里只有 `#include "hello_ros_interfaces/msg/robot_status.hpp"`，从没直接碰 `geometry_msgs`。
那个头文件内部会 include 它要的东西，而 `hello_ros_interfaces` 的 ament 导出会**传递性地**把 `geometry_msgs` 带进来。

</details>

### 9.2 留给下次的思考题（无答案）

**①** `talker.cpp` 用的是 `create_wall_timer(1s, [this]() { tick(); })`。

- 为什么定时器的 lambda 参数列表是空的，而订阅者的要收一个 `msg`？
- **猜**：`create_publisher` 需要回调吗？为什么？

**②** 本步的 C++ 订阅者能同时订阅两个话题吗？如果能，是不是要写两个 `sub_`？变量名怎么办？

**③** 如果 `RCLCPP_INFO` 的格式串是 `"收到: %s"`，但你传的却是 `msg->battery`（一个 float），**build 会报错吗？跑起来会怎样？**

- 先写下预测，再写个最小例子验证（`/tmp` 里，不要污染仓库）

**④** `msg->position.x` 用的是 `->` 和 `.`。那如果我要**修改** `position.x`（比如在发布者里赋值），写法一样吗？

> 提示：去看 `status_talker.py` 第 23 行 `msg.position.x = float(self.count)` —— 在 Python 里，**读和写是同一个写法**。C++ 里呢？

---

## 10. 附：跨关待办

### ① 「菜单当订单」—— 第 4 次

把 `talker.cpp` 里**定时器**的 lambda 形状（`[this]() { tick(); }`）抄给了**订阅者**，连 `1s` 都抄进去了。

**形状**：手边有一个"看起来很像"的示例 → 直接照抄 → 但那是**另一道菜**。

**防法**：抄之前先问 —— **「我要的这道菜，回调收几个参数？」**
这个问题能挡住全部 4 次。

### ② ⭐ 层次混淆 —— 本步最顽固的一条，**载了 3 次**

| # | 写成了 | 应该是 | 层次 |
|---|---|---|---|
| 1 | `std_msgs::msg::String sub_;` | `rclcpp::Subscription<...>::SharedPtr` | 消息 → 订阅者 |
| 2 | `RobotStatus::SharedPtr sub_;` | 同上 | 消息 → 订阅者 |
| 3 | `find_package(RobotStatus)` | `find_package(hello_ros_interfaces)` | 消息 → 包 |

**三次都是同一个动作：把"小的那个"当成了"大的那个"。**

**唯一有效的解法是那句话**：
> **「这一格装的是个什么东西？」**
> 装的是**订阅者** → 外层 `Subscription`，消息塞进 `<>`。
> 装的是**包** → `find_package` 要包名，消息名是**包里面**的东西。

### ③ 「可枚举的东西直接去查」—— 继续全胜

本步凡是**照着查**的都一次过：

- `robot_status.hpp` 的蛇形名字 → `ls` 一眼，一次写对
- `create_subscription` 的形状 → 照 `talker.cpp`，一次对
- `%d` / `%.1f` 的选择 → 照速查表，一次对

凡是**靠猜**的都翻车：`chat(...)`、`c_ctr()`、`RobotStatus` 当包名。

**结论**：**名字、字段、拼写这类可枚举的东西 —— 永远"看一眼"，不要"想一想"。**

### ④ 分号 —— 漏了 **3 次**

在"同一个位缺同一个字符"上反复。**建议**：以后写完一行声明，**默念一遍「类型 → 名字 → 分号」**。

### ⑤ 「整行替换」vs「逐字符修改」

见坑 9。这是本步**新出现**的一类问题，和前面几条都不同 ——
不是"不会写"，是**"改动的方式"**选错了。**一行里有多个相似位置时，整行替换。**

### ⑥ 待补

- `docs/cpp-03-*.md`：C++ 发布者（用 C++ 写 `status_talker`，把 `.` 和 `->` 的**写**也走一遍 —— 见 §9.2 题 ④）
- `docs/cpp-04-*.md`：C++ service / parameter（如果继续走 C++ 线）

---

## 附：本步命令速记卡

```bash
# ---------- 构建 ----------
cd ~/ros2_learn_ws
colcon build --packages-select hello_ros_cpp

# ---------- 只想知道错在哪（输出太长时）----------
colcon build --packages-select hello_ros_cpp 2>&1 | grep -E "error:|warning:"

# ---------- ⭐ 先验可执行文件（不依赖任何节点）----------
ros2 pkg executables hello_ros_cpp

# ---------- 运行 ----------
ros2 run hello_ros_cpp listener          # C++ 收 /chatter
ros2 run hello_ros_cpp status_listener   # C++ 收 /robot_status
ros2 run hello_ros talker                # 第 1 关的 Python 发布者
ros2 run hello_ros status_talker         # 第 6 关的 Python 发布者

# ---------- 排查 ----------
ros2 topic list
ros2 topic info /robot_status -v

# ---------- 查东西（配合 cd 用短命令，别敲长路径）----------
cd /opt/ros/lyrical/include/rclcpp/rclcpp
cd ~/ros2_learn_ws/install/hello_ros_interfaces/include/hello_ros_interfaces/hello_ros_interfaces/msg
ls
# 更好：VSCode 里函数名上按 F12 / Ctrl+点击，直接跳定义，零打字
```

---

## 相关笔记

- [cpp-01-getting-started.md](cpp-01-getting-started.md) —— C++ 五个符号、`talker.cpp`、CMake 点名制、坑 1~9
- [lesson-01-topic.md](lesson-01-topic.md) —— Python 版发布/订阅（本步的对照对象）
- [lesson-05-action.md](lesson-05-action.md) —— 盒子/内容（`->` vs `.` 的源头）
- [lesson-06-custom-message.md](lesson-06-custom-message.md) —— 自定义消息、`DEPENDENCIES` 的两处
- [lesson-08-qos.md](lesson-08-qos.md) —— 「菜单当订单」的前 3 次
