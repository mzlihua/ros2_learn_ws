# C++ 支线 · 01 · 用 rclcpp 写第一个节点

> ROS 2 核心基础 · C++ 支线笔记
> 学习日期：2026-09-13
> 环境：ROS 2 Lyrical / g++ 15.2 / CMake 4.2.3 / C++20

---

## 目录

1. [为什么单独开一个包](#1-为什么单独开一个包)
2. [核心概念：Python ↔ C++ 对照](#2-核心概念python--c-对照)
3. [完整代码](#3-完整代码)
4. [API 速查表](#4-api-速查表)
5. [构建与运行流程](#5-构建与运行流程)
6. [实测现象与结论 ⭐](#6-实测现象与结论-)
7. [踩坑记录](#7-踩坑记录)
8. [自测题](#8-自测题)

---

## 1. 为什么单独开一个包

### 1.1 一个包只能有一种构建类型

| 构建类型 | 用在哪 | 标志文件 |
|---|---|---|
| `ament_python` | 纯 Python 包 | `setup.py` |
| `ament_cmake` | 纯 C++ 包 | `CMakeLists.txt` |

`hello_ros` 是 `ament_python`，它的 `package.xml` 里写死了：

```xml
<export>
  <build_type>ament_python</build_type>
</export>
```

**一个包只能选一边。** 所以 C++ 代码要新开一个包：

```bash
cd ~/ros2_learn_ws/src
ros2 pkg create --build-type ament_cmake --node-name hello_cpp hello_ros_cpp
```

这条命令生成的东西（**不用手敲**）：

```
hello_ros_cpp/
├── CMakeLists.txt
├── package.xml
├── include/hello_ros_cpp/
└── src/
    └── hello_cpp.cpp        ← 骨架文件，已经能编过
```

### 1.2 两个包的分工

| 包 | 构建类型 | 干什么 |
|---|---|---|
| `hello_ros` | `ament_python` | 主课程：话题 / 服务 / 参数 / launch |
| `hello_ros_cpp` | `ament_cmake` | C++ 支线：把 `hello_ros` 的示例**用 rclcpp 重写** |

---

## 2. 核心概念：Python ↔ C++ 对照

### 2.1 最短的对照表

**同一个 hello 节点，两种语言并排看**：

| | Python | C++ |
|---|---|---|
| 引入 | `import rclpy` | `#include "rclcpp/rclcpp.hpp"` |
| 继承 | `class HelloNode(Node):` | `class HelloNode : public rclcpp::Node` |
| 构造函数 | `def __init__(self): super().__init__('x')` | `HelloNode() : Node("x")` |
| 初始化 | `rclpy.init()` | `rclcpp::init(argc, argv)` |
| 打印 | `self.get_logger().info("hi")` | `RCLCPP_INFO(this->get_logger(), "hi")` |
| 定时器 | `self.create_timer(1.0, self.tick)` | `this->create_wall_timer(1s, [this](){ tick(); })` |
| 自旋 | `rclpy.spin(node)` | `rclcpp::spin(std::make_shared<HelloNode>())` |
| 关闭 | `rclpy.shutdown()` | `rclcpp::shutdown()` |

### 2.2 ⭐ 三个必须理解的差异

#### 差异 1：C++ 有"类型"，而且写在 `<>` 里

Python 里创建发布者：

```python
self.pub = self.create_publisher(String, 'chatter', 10)
#                              ^^^^^^ 类型当一个【参数】传进去
```

C++ 里：

```cpp
pub_ = this->create_publisher<std_msgs::msg::String>("chatter", 10);
//                           ^^^^^^^^^^^^^^^^^^^^^^^^^ 类型写在【尖括号】里
```

**为什么？** 因为 C++ 是**编译期**语言 —— 编译器在生成代码之前就必须知道 `pub_` 到底发布什么类型的消息。Python 是**运行期**的，传参的那一刻才知道。

这不是语法花样，是两种语言的**根本区别**。

#### 差异 2：成员变量的类型 = 初始化它的那个函数的返回值类型

C++ 里你必须**手写**成员变量的类型。怎么知道写什么？

> **看等号右边那个函数的返回值是什么。**

```cpp
pub_   = this->create_publisher<std_msgs::msg::String>("chatter", 10);
timer_ = this->create_wall_timer(1s, [this]() { tick(); });
```

| 左边变量 | 右边的函数 | 所以类型写 |
|---|---|---|
| `pub_` | `create_publisher<std_msgs::msg::String>` | `rclcpp::Publisher<std_msgs::msg::String>::SharedPtr` |
| `timer_` | `create_wall_timer` | `rclcpp::TimerBase::SharedPtr` |

> 💡 **怎么查？** 打开 `/opt/ros/lyrical/include/rclcpp/rclcpp/node.hpp`，搜 `create_publisher`，看它返回什么。**头文件就是标准答案。**

**`SharedPtr` 是什么？** ≈ Python 的"引用"。C++ 里对象默认是**值**（复制），要用共享的方式持有就得显式包一层 `SharedPtr`。**记住结论就行**：ROS 2 里所有"长期持有的东西"（发布者、订阅者、定时器），成员类型都是 `...::SharedPtr`。

#### 差异 3：`->` 和 `.` 的区别

```cpp
pub_->publish(msg);                          // -> ：左边是一个【指针】
this->get_logger()                           // -> ：this 是指针
msg.data = "...";                            // .  ：左边是一个【对象】
```

> **规则：左边是指针就用 `->`，否则用 `.`。**
> 什么时候知道是不是指针？看类型里有没有 `SharedPtr`（或 `*`）。

### 2.3 回调：`[this]() { tick(); }`

Python 里回调就是一个方法名：

```python
self.create_timer(1.0, self.tick)
```

C++ 里没有"传方法名"这回事，得写一个**匿名函数（lambda）**：

```cpp
this->create_wall_timer(1s, [this]() { tick(); });
//                          ^^^^^^ ^^   ^^^^^^^^
//                          ①     ②      ③
```

| 位置 | 是什么 |
|---|---|
| ① `[this]` | **捕获列表** —— 把 `this`（当前对象）带进这个函数，否则里面调不到 `tick()` |
| ② `()` | 参数列表 —— `create_wall_timer` 的回调不收参数，空的 |
| ③ `{ tick(); }` | 函数体 —— 到点了就干这个 |

**一句话**：`[this]() { tick(); }` ≈ Python 的 `self.tick`。

### 2.4 `RCLCPP_INFO` 是宏，不是函数

```cpp
RCLCPP_INFO(this->get_logger(), "第%d次心跳", count_);
//          ^^^^^^^^^^^^^^^^^^^  ^^^^^^^^^^^^  ^^^^^^
//          日志器               格式串        变量
```

| Python | C++ |
|---|---|
| `self.get_logger().info(f'第 {n} 次心跳')` | `RCLCPP_INFO(this->get_logger(), "第%d次心跳", n)` |
| **f-string 内嵌** | **`printf` 风格占位符 + 后面跟参数** |

常用占位符：

| 占位符 | 类型 | 例 |
|---|---|---|
| `%d` | 整数 | `count_` |
| `%f` | 浮点 | `3.14` |
| `%s` | 字符串 | ⚠️ 必须是 **C 风格字符串** → `.c_str()` |

⚠️ **`%s` 那个坑**：

```cpp
std::string s = "abc";
RCLCPP_INFO(logger, "%s", s);          // ❌ 编译能过，运行乱码
RCLCPP_INFO(logger, "%s", s.c_str());  // ✅
```

`%s` 期待的是一个**指针**（`char*`），而 `std::string` 是个对象。`.c_str()` 就是"给我底层那个指针"。

⚠️ **另一个坑**：`RCLCPP_INFO(...)` **结尾必须有分号**。它展开后是个 `do{...}while(0)`，漏分号会报 `expected ';' before 'do'` —— 看到 `do` 这个莫名其妙的词，就是这个原因。

### 2.5 字符串拼接：C++ 没有 f-string

```python
msg.data = f'第 {self.count} 次心跳'          # Python：自动转换
```

```cpp
msg.data = "第 " + std::to_string(count_) + " 次心跳";   // C++：必须手动转
```

| 想拼什么 | 怎么写 |
|---|---|
| 数字 | `std::to_string(n)` |
| 字符串 | 直接用 |
| 字面量 | `"..."`（双引号；单引号 `'a'` 是**单个字符**，类型不同） |

> 不写 `std::to_string` 直接 `"第 " + count_` → 一长串看不懂的编译错误。**数字要用 `std::to_string` 包一下。**

### 2.6 头文件：`#include` 的路径怎么来的

```cpp
#include "rclcpp/rclcpp.hpp"
#include "std_msgs/msg/string.hpp"
```

规律：**`#include "<包名>/<包里的相对路径>"`**

消息类型的 `.hpp` 都在 `<包名>/msg/` 下：

```bash
ls /opt/ros/lyrical/include/ | grep -i '^std'
# std_msgs
# std_srvs
```

⚠️ **目录是双层嵌套的**：`/opt/ros/lyrical/include/rclcpp/rclcpp/rclcpp.hpp`

第 1 个 `rclcpp/` 是**安装目录**，第 2 个 `rclcpp/` 才是 **include 路径的起点**。所以写 `#include "rclcpp/rclcpp.hpp"`，**不是** `#include "rclcpp.hpp"`。

---

## 3. 完整代码

### `include/` —— 本次没用到

生成的 `include/hello_ros_cpp/` 目录空着没动。单文件的小节点**不需要头文件** —— 类直接在 `.cpp` 里定义。

（真要做成库给别人 `#include` 时才需要。暂时不用管。）

### `src/hello_cpp.cpp` —— 第一个节点

```cpp
#include <chrono>
#include <memory>

#include "rclcpp/rclcpp.hpp"

using namespace std::chrono_literals;


class HelloNode : public rclcpp::Node
{
public:
    HelloNode() : Node("hello_cpp")        // ≈ super().__init__('hello_cpp')
    {
        count_ = 0;

        timer_ = this->create_wall_timer(1s, [this]() { tick(); });
        RCLCPP_INFO(this->get_logger(), "hello_cpp起来了");
    }

private:
    void tick()
    {
        count_ += 1;
        RCLCPP_INFO(this->get_logger(), "第%d次心跳", count_);
    }

    rclcpp::TimerBase::SharedPtr timer_;       // create_wall_timer 的返回值类型
    int count_;
};


int main(int argc, char ** argv)
{
    rclcpp::init(argc, argv);                       // ≈ rclpy.init()
    rclcpp::spin(std::make_shared<HelloNode>());    // ≈ rclpy.spin(node)
    rclcpp::shutdown();                             // ≈ rclpy.shutdown()
    return 0;
}
```

**逐块对照 Python 版**：

| C++ | Python |
|---|---|
| `class HelloNode : public rclcpp::Node` | `class HelloNode(Node):` |
| `HelloNode() : Node("hello_cpp")` | `super().__init__('hello_cpp')` |
| `public:` / `private:` | `self.` 前面的下划线约定（Python 靠约定，C++ 靠编译器**强制**） |
| `int count_;` 尾下划线 | `self.count_` 也是这个命名习惯 |
| `main()` + `rclcpp::init/spin/shutdown` | `def main()` + `rclpy.init/spin/shutdown` |

> **为什么 C++ 需要 `main()` 而 Python 不需要？**
> Python 脚本是**从头到尾执行**的，`if __name__ == '__main__': main()` 只是个入口约定。
> C++ 编译产物是**可执行文件**，操作系统规定必须有 `main()` 作为起点。**它是强制的，不是可选风格。**

> **`std::make_shared<HelloNode>()` 是什么？**
> ≈ Python 的 `HelloNode()`。区别是它在**堆上**创建对象，并返回一个 `SharedPtr`（共享指针）。`rclcpp::spin` 需要一个共享指针，所以不能直接写 `rclcpp::spin(HelloNode())`。

### `src/talker.cpp` —— 第一个发布者

```cpp
#include <chrono>
#include <memory>
#include <string>

#include "rclcpp/rclcpp.hpp"
#include "std_msgs/msg/string.hpp"

using namespace std::chrono_literals;


class Talker : public rclcpp::Node
{
public:
    Talker() : Node("talker_cpp")        // ≈ super().__init__('talker_cpp')
    {
        count_ = 0;

        // 类型写在 <> 里 —— C++ 编译期就得知道发布的是什么消息
        pub_ = this->create_publisher<std_msgs::msg::String>("chatter", 10);
        timer_ = this->create_wall_timer(1s, [this]() { tick(); });
    }

private:
    void tick()
    {
        count_ += 1;

        auto msg = std_msgs::msg::String();
        msg.data = "第 " + std::to_string(count_) + " 次心跳";
        pub_->publish(msg);

        RCLCPP_INFO(this->get_logger(), "发布: %s", msg.data.c_str());
    }

    // 成员变量的类型 = 初始化它的那个函数的返回值类型
    rclcpp::Publisher<std_msgs::msg::String>::SharedPtr pub_;
    rclcpp::TimerBase::SharedPtr timer_;
    int count_;
};


int main(int argc, char ** argv)
{
    rclcpp::init(argc, argv);                       // ≈ rclpy.init()
    rclcpp::spin(std::make_shared<Talker>());       // ≈ rclpy.spin(node)
    rclcpp::shutdown();                             // ≈ rclpy.shutdown()
    return 0;
}
```

**对照 Python 的 `talker.py`**：

| Python | C++ |
|---|---|
| `self.pub = self.create_publisher(String, 'chatter', 10)` | `pub_ = this->create_publisher<std_msgs::msg::String>("chatter", 10);` |
| `msg = String()` | `auto msg = std_msgs::msg::String();` |
| `msg.data = f'第 {self.count} 次心跳'` | `msg.data = "第 " + std::to_string(count_) + " 次心跳";` |
| `self.pub.publish(msg)` | `pub_->publish(msg);` |
| `self.get_logger().info(f'发布: {msg.data}')` | `RCLCPP_INFO(this->get_logger(), "发布: %s", msg.data.c_str());` |

> 💡 **`auto` 是什么？** "让编译器自己推类型"。`auto msg = std_msgs::msg::String();` 等价于 `std_msgs::msg::String msg;`。
> **但成员变量不能用 `auto`** —— 成员类型是类的接口的一部分，必须写清楚。这就是为什么上面 `pub_` / `timer_` 的类型得手写。

### `CMakeLists.txt` 的改动

`ros2 pkg create` 生成的骨架只带 `hello_cpp`。加了 `talker.cpp` 之后要补三处：

```cmake
find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(std_msgs REQUIRED)          # ① 用到 std_msgs 就得找它

add_executable(hello_cpp src/hello_cpp.cpp)
target_include_directories(hello_cpp PUBLIC
  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
  $<INSTALL_INTERFACE:include/${PROJECT_NAME}>)
target_compile_features(hello_cpp PUBLIC c_std_17 cxx_std_20)
target_link_libraries(hello_cpp rclcpp::rclcpp)

add_executable(talker src/talker.cpp)                                     # ② 新增
target_link_libraries(talker rclcpp::rclcpp ${std_msgs_TARGETS})          # ③ 新增

install(TARGETS hello_cpp talker          # ← 别忘了把新目标加进 install
  DESTINATION lib/${PROJECT_NAME})
```

**四处改动，一个都不能少**：

| 改动 | 少了会怎样 |
|---|---|
| `find_package(std_msgs REQUIRED)` | `${std_msgs_TARGETS}` 是空的 → 链接失败 |
| `add_executable(talker ...)` | **build 绿灯，但 `talker` 根本不存在** ← 见 §6.3 |
| `target_link_libraries(...)` | 找不到 `rclcpp` / `std_msgs` 里的符号 |
| `install(TARGETS ... talker)` | 编译出来了，但**没装进 `lib/`** → `ros2 run` 找不到 |

> 💡 **CMake 的思维方式**：它**不扫描** `src/` 目录。你**点名**哪个文件，它才编哪个。
> 加一个新的 `.cpp`，**必须**对应加一组 `add_executable` + `target_link_libraries` + `install`。

### `package.xml` 的改动

```xml
<buildtool_depend>ament_cmake</buildtool_depend>

<depend>rclcpp</depend>
<depend>std_msgs</depend>
```

`CMakeLists.txt` 的 `find_package` 和 `package.xml` 的 `<depend>` **要配对**：

| 文件 | 这个声明给谁看 |
|---|---|
| `CMakeLists.txt` 的 `find_package` | **本次构建**：去哪儿找 |
| `package.xml` 的 `<depend>` | **别人**：装我这个包要先装什么 |

`package.xml` 里 `<export>` 是"给别的包看的信息"，`<depend>` 必须是 `<package>` 的**直接子元素**，不能塞进 `<export>` 里。

---

## 4. API 速查表

### 程序骨架

```cpp
#include "rclcpp/rclcpp.hpp"
using namespace std::chrono_literals;          // 才能写 1s / 500ms

class MyNode : public rclcpp::Node
{
public:
    MyNode() : Node("节点名")                   // ≈ super().__init__('节点名')
    {
        // 建发布者 / 订阅者 / 定时器
    }

private:
    // 回调
    // 成员变量
};

int main(int argc, char ** argv)
{
    rclcpp::init(argc, argv);
    rclcpp::spin(std::make_shared<MyNode>());
    rclcpp::shutdown();
    return 0;
}
```

### 常用成员函数（在构造函数里调用，全部用 `this->`）

```cpp
// 定时器：每隔 1 秒跑一次 tick()
timer_ = this->create_wall_timer(1s, [this]() { tick(); });

// 发布者
pub_ = this->create_publisher<std_msgs::msg::String>("话题名", 10);
pub_->publish(msg);

// 订阅者
sub_ = this->create_subscription<std_msgs::msg::String>(
    "话题名", 10, [this](const std_msgs::msg::String::SharedPtr msg) {
        RCLCPP_INFO(this->get_logger(), "收到: %s", msg->data.c_str());
    });

// 日志
RCLCPP_INFO(this->get_logger(), "格式串 %d", 整数);
RCLCPP_WARN(this->get_logger(), "...");
RCLCPP_ERROR(this->get_logger(), "...");
```

### 成员变量的类型（照抄）

```cpp
rclcpp::TimerBase::SharedPtr timer_;
rclcpp::Publisher<std_msgs::msg::String>::SharedPtr pub_;
rclcpp::Subscription<std_msgs::msg::String>::SharedPtr sub_;
int count_;
std::string name_;
```

**规律**：`rclcpp::<东西><消息类型>::SharedPtr`。
不确定就去 `/opt/ros/lyrical/include/rclcpp/rclcpp/node.hpp` 搜对应的 `create_*` 函数，看返回类型。

### 消息字段

```cpp
auto msg = std_msgs::msg::String();
msg.data = "内容";                 // .data 字段，类型 std::string
```

**怎么知道有哪些字段？** 命令行一条：

```bash
ros2 interface show std_msgs/msg/String
```

---

## 5. 构建与运行流程

### ⭐ 工作区有 Python 包也有 C++ 包，构建命令要分别写

```bash
cd ~/ros2_learn_ws

# Python 包
colcon build --packages-select hello_ros --symlink-install

# C++ 包
colcon build --packages-select hello_ros_cpp

# 一起
colcon build --packages-select hello_ros hello_ros_cpp --symlink-install

source install/setup.bash
```

> **为什么 `--symlink-install` 对 C++ 意义不大？**
> C++ 的产物是**编译出来的二进制**，`.cpp` 改了**必须重编**，软链解决不了。这个 flag 只对 Python / launch 这类"原样拷贝的文本文件"有用。
> 混着 build 时统一加上没坏处（`--symlink-install` 是**逐包**生效的）。

### ⚠️ CMake 包什么时候必须重新 build

| 改了什么 | 要 rebuild 吗 |
|---|---|
| `.cpp` 的文件内容 | ✅ **必须**（要重新编译） |
| **新增**一个 `.cpp` | ✅ **必须**（还要改 `CMakeLists.txt`） |
| **新增**一个 `add_executable` | ✅ **必须** |
| `CMakeLists.txt` | ✅ **必须** |
| `package.xml` | ✅ **必须** |

**C++ 包没有"不用 rebuild"的选项。** 每次改完 `.cpp` 都要重新跑一遍 `colcon build`。

### 运行

```bash
ros2 run hello_ros_cpp hello_cpp
ros2 run hello_ros_cpp talker
```

### 验收清单

```bash
# ① 先确认可执行文件真的生成了（别跳过）
ls install/hello_ros_cpp/lib/hello_ros_cpp/
#    必须看到 hello_cpp 和 talker

# ② 再跑
ros2 run hello_ros_cpp hello_cpp
```

---

## 6. 实测现象与结论 ⭐

### 6.1 ⭐⭐ C++ 和 Python 的节点能直接通信

**实测**：跑 C++ 的 `talker`（话题 `/chatter`），再跑 Python 的 `listener`：

```bash
$ ros2 run hello_ros_cpp talker        # 终端 A（C++）
[talker_cpp] [INFO] [...] [talker_cpp]: ...1
$ ros2 run hello_ros listener          # 终端 B（Python）
[listener] [INFO] [...] [listener]: 接收: ...1
```

（`...1` 里的 `...` 就是 `talker.cpp` 里还没填的那两个占位符，见文末「待办」。
重点是：**Python 的 listener 收到了 C++ 发的东西。**）

**结论**：

> ### 📌 话题是一份"语言无关的契约"。
>
> `rclpy` 和 `rclcpp` 只是盖在同一个 DDS 通信层上的**两套语言外壳**。
> 谁发的、谁收的，跟语言**无关** —— 只跟**话题名**和**消息类型**有关。

这解释了为什么 `ros2 topic echo` / `ros2 node list` 这些命令**对两种语言一视同仁**：它们看的是底层，不是语言。

**反过来说**：话题名或消息类型对不上，**任何**语言组合都通不了。

### 6.2 ⭐ CMake 是"点名制"，不是"扫描制"

加了 `talker.cpp` 但 `CMakeLists.txt` 里没有 `add_executable(talker ...)`：

```bash
$ colcon build --packages-select hello_ros_cpp
Finished <<< hello_ros_cpp              # ← 绿灯

$ ls install/hello_ros_cpp/lib/hello_ros_cpp/
hello_cpp                               # ← talker 不存在

$ ros2 run hello_ros_cpp talker
No executable found                     # ← 到这儿才发现
```

**跟第 4 关的 `glob` bug 形状完全一样**：

| | `glob`（第 4 关） | CMake（本关） |
|---|---|---|
| 实际给的清单 | 空列表 `[]` | 没有 `add_executable` |
| `colcon build` | 绿灯 | 绿灯 |
| 结果 | 目录空 | 没有可执行文件 |

> ### 📌 绿灯只证明"没出错"，不证明"做了你想做的事"。
> 每次 build 完，`ls` 一下 `install/<包名>/lib/<包名>/`。

### 6.3 ⭐ C++ 报错的信息量，比 Python 大得多

**同一个错误**，两边的表现：

| 场景 | Python | C++ |
|---|---|---|
| 把 `SharedPtr` 拼成 `SharePtr` | 运行时 `AttributeError`（如果碰巧跑到） | 编译期直接报错，**还附赠** `did you mean 'SharedPtr'?` |
| 变量类型写错 | 可能静静地出问题 | 编译不过 |
| 少个分号 | 没问题 | `error: expected ';'` |

**结论**：

> **Python 的错经常在运行期才出现，甚至不出现（静默 bug）。C++ 的错几乎都在编译期被拦下来。**

这是 C++ 用起来"麻烦"的地方，**也是它最大的好处** —— 编译器在替你检查。第 4 关 §7.2 那种"绿灯了但结果是错的"，在 C++ 里发生的概率低得多。

### 6.4 ⭐ 修 C++ 编译错误的顺序：从上往下，修一条，重编一次

**实例**：把 `pub_` 的类型写成 `std_msgs::msg::String pub_;`（应该是 `rclcpp::Publisher<std_msgs::msg::String>::SharedPtr`），编译器报：

```
error: no match for 'operator=' ...                        (第 25 行，赋值处)
error: base operand of '->' has non-pointer type ...       (第 45 行，调用处)
```

**两个错误，一个根因。**

如果从下往上修（去改第 45 行的 `pub_->`），会越修越乱。正确做法：

1. **看第一条**（第 25 行）
2. 它说"没有匹配的 `operator=`" → 意思是"右边的类型赋不进去" → **类型写错了**
3. 改类型
4. **立刻重编** —— 后面那条错很可能一起消失

> ### 📌 编译器只报它能看见的第一个问题。**第一条错常常是真凶，后面的是余波。**
> **一行一行来**，不要一次改一堆。

### 6.5 ⭐ VSCode 的红线不是判决书

**现象**：`#include "rclcpp/rclcpp.hpp"` 下面一条红波浪线写着"找不到路径"，但 `colcon build` **完全正常**。

**原因**：**VSCode 的 IntelliSense 和编译器是两套独立的东西。**

| | 谁在管 | 看哪份配置 |
|---|---|---|
| VSCode 红线 | IntelliSense | `.vscode/c_cpp_properties.json` |
| 编译能否通过 | `g++` | `CMakeLists.txt` 的 `find_package` / `target_link_libraries` |

默认生成的 `c_cpp_properties.json` 里 `includePath` 只有 `${workspaceFolder}/**`，**不包含 ROS 的头文件目录**，所以 IntelliSense 找不到。

**修法**（加一行）：

```json
{
    "configurations": [
        {
            "name": "Linux",
            "includePath": [
                "${workspaceFolder}/**",
                "/opt/ros/lyrical/include/**"
            ],
            "defines": [],
            "compilerPath": "/usr/bin/g++",
            "cStandard": "gnu23",
            "cppStandard": "gnu++20",
            "intelliSenseMode": "linux-gcc-x64"
        }
    ],
    "version": 4
}
```

**结论**：

> ### 📌 编辑器红线是提示，不是判决。`colcon build` 才是判决。
> 红线可以看（它常能提前发现真错误），但**别为了消红线去改代码** —— 先跑一次 `colcon build` 确认是不是真错。

> ⚠️ `.vscode/` 在 `.gitignore` 里，这个改动只在本机生效，不进版本库。

---

## 7. 踩坑记录

### ❌ 坑 1：在 C++ 里想着 Python 的写法

| 想写 | 写成了 | 应该 |
|---|---|---|
| 类型当参数传 | `create_publisher(String, ...)` | `create_publisher<std_msgs::msg::String>(...)` |
| 拼字符串 | `"第 " + count_` | `"第 " + std::to_string(count_)` |
| 传字符串给 `%s` | `RCLCPP_INFO(..., "%s", msg.data)` | `msg.data.c_str()` |

**根因**：把 Python 的习惯直接搬过来。C++ 的**类型系统是编译期强制的**，每个地方都得说清楚。

### ❌ 坑 2：`RCLCPP_INFO` 漏分号

```cpp
RCLCPP_INFO(this->get_logger(), "第%d次心跳", count_)     // ❌ 没分号
```

```
error: expected ';' before 'do'
```

**为什么会出现 `do`？** 因为 `RCLCPP_INFO` 是个**宏**，展开后是 `do { ... } while (0)` 的形式。"`do`" 这个词是从宏里出来的。

> **看到 `do` / `while` 出现在不该出现的地方 → 检查上一行的宏有没有漏分号。**

### ❌ 坑 3：`SharePtr` 少了个 `d`，还少了前缀

```cpp
SharePtr timer_;                       // ❌ 拼写 + 缺 rclcpp::TimerBase::
```

编译器自己给出了提示：

```
error: 'SharePtr' was not declared in this scope; did you mean 'SharedPtr'?
```

**正确**：

```cpp
rclcpp::TimerBase::SharedPtr timer_;
```

**这只是 C++ 比 Python 友好的一个例子** —— Python 里 `SharePtr` 可能要到运行时才炸。

### ❌ 坑 4：`std_msg` 少了个 `s`

三个文件**同时**写错（`CMakeLists.txt`、`package.xml`、`talker.cpp`）：

```
std_msg      ❌
std_msgs     ✅
```

CMake 的报错里把 `std_msg` 重复了 4 遍：

```
Could not find a package configuration file provided by "std_msg" ...
```

**⭐ 三步定位法**：

| 步 | 做什么 |
|---|---|
| ① | 读**整条**第一条错误（别只看一行就跳走） |
| ② | 找出里面**被重复提到的那个名字** —— 那就是它不认识的东西 |
| ③ | **把那个名字拿去 `ls`** |

```bash
ls /opt/ros/lyrical/include/ | grep -i '^std'
# std_msgs
# std_srvs
```

一目了然。

> ⚠️ **千万别用全局替换！**
> 文件里已经有正确的 `std_msgs::msg::String`，一把替换会变成 `std_msgss::msg::String`，**修一个坏一个**。
> 一个一个改。

### ❌ 坑 5：`find_package(rclcpp REQUIRED)` 塞进了 `if(BUILD_TESTING)` 里

```cmake
if(BUILD_TESTING)
  find_package(rclcpp REQUIRED)      # ❌ 位置不对
  find_package(ament_lint_auto REQUIRED)
  ...
endif()
```

**为什么"居然能用"是错觉**：`BUILD_TESTING` **默认是 ON**，所以那些行确实被执行了；而且 CMake 是在**读完整份文件之后**才检查链接目标是否有效，所以 `add_executable` 里引用 `rclcpp::rclcpp` 也不会当场报错。

**正确位置**：跟其他 `find_package` 放在一起，在文件上半部分：

```cmake
find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)         # ✅
find_package(std_msgs REQUIRED)
```

> **"能跑"不等于"写对了"。** 这里的报应会出现在：某天有人用 `colcon build --cmake-args -DBUILD_TESTING=OFF` 的时候。

### ❌ 坑 6：`private:` 后面跟了中文

```cpp
private:不去
```

**根因**：写完 `private:` 忘了切输入法，多打了两个中文字。

**改法**：写代码时**保持英文输入法**。中文注释写在注释里没问题，代码部分别留中文。

### ❌ 坑 7：成员变量类型写成了消息类型

```cpp
std_msgs::msg::String pub_;    // ❌ pub_ 是【发布者】，不是【消息】
```

**对照**：

| 变量 | 它是什么 | 类型 |
|---|---|---|
| `pub_` | 用来到处发消息的**工具** | `rclcpp::Publisher<std_msgs::msg::String>::SharedPtr` |
| `msg` | 一条具体的**消息** | `std_msgs::msg::String` |

**记法**：`create_publisher` 的返回值类型，就是 `pub_` 的类型。**返回值长什么样，成员就写什么样。**

### ❌ 坑 8：`No executable found`（build 是绿的）

见 §6.2。**根因**：`CMakeLists.txt` 里没有 `add_executable(talker ...)`。

**定位方法**：

```bash
ls install/hello_ros_cpp/lib/hello_ros_cpp/
```

**没看到你想要的文件 → 回头查 `CMakeLists.txt`。**

### ❌ 坑 9：以为 VSCode 红线说明代码错了

见 §6.5。**先 `colcon build`，再决定要不要理红线。**

---

## 8. 自测题

> 答案默认折叠，**先自己回答一遍再展开**。

<details>
<summary><b>题 1：为什么 C++ 代码要新开一个包，不能放在 <code>hello_ros</code> 里？</b></summary>

因为**一个包只能有一种构建类型**。`hello_ros` 是 `ament_python`（靠 `setup.py` 构建），C++ 代码需要 `ament_cmake`（靠 `CMakeLists.txt` 构建）。两者不能共存于一个包。

</details>

<details>
<summary><b>题 2：<code>create_publisher&lt;std_msgs::msg::String&gt;("chatter", 10)</code> 里，类型为什么写在 <code>&lt;&gt;</code> 里而不是当参数传？</b></summary>

因为 C++ 是**编译期**语言 —— 编译器在生成代码之前就必须知道 `pub_` 发布的是什么类型的消息。Python 是运行期的，传参那一刻才知道，所以能当参数传。

</details>

<details>
<summary><b>题 3：<code>pub_</code> 的类型怎么确定？去哪儿查？</b></summary>

**成员变量的类型 = 初始化它的那个函数的返回值类型。**

`pub_` 由 `create_publisher<std_msgs::msg::String>` 初始化，所以类型是：

```cpp
rclcpp::Publisher<std_msgs::msg::String>::SharedPtr
```

去 `/opt/ros/lyrical/include/rclcpp/rclcpp/node.hpp` 搜 `create_publisher`，看它返回什么。

</details>

<details>
<summary><b>题 4：<code>pub_->publish(msg)</code> 用 <code>-></code>，<code>msg.data</code> 用 <code>.</code>，区别是什么？</b></summary>

**左边是指针就用 `->`，否则用 `.`。**

- `pub_` 的类型是 `...::SharedPtr`（共享指针）→ 用 `->`
- `msg` 的类型是 `std_msgs::msg::String`（对象）→ 用 `.`

</details>

<details>
<summary><b>题 5：<code>[this]() { tick(); }</code> 里 <code>[this]</code> 是干什么的？不写会怎样？</summary>

**捕获列表** —— 把当前对象的指针带进这个匿名函数。等价于 Python 里的 `self`。

不写 `[this]`，函数体里就**调不到 `tick()`**（因为 `tick` 是成员函数，需要 `this` 才能调用），编译报错。

</details>

<details>
<summary><b>题 6：为什么 <code>RCLCPP_INFO</code> 漏分号会报 <code>expected ';' before 'do'</code>？</b></summary>

因为 `RCLCPP_INFO` 是个**宏**，展开成 `do { ... } while (0)` 的形式。漏了分号，`do` 就跟上一行粘在了一起，编译器看不懂。

**看到莫名其妙的 `do`，就去检查上一行的宏有没有漏分号。**

</details>

<details>
<summary><b>题 7：<code>msg.data = "第 " + count_</code> 为什么编不过？</b></summary>

C++ 的 `+` 不会自动把数字转成字符串（没有 Python 的 f-string）。

要用：

```cpp
msg.data = "第 " + std::to_string(count_) + " 次心跳";
```

</details>

<details>
<summary><b>题 8：<code>%s</code> 为什么必须配 <code>.c_str()</code>？</b></summary>

`%s` 期待的是一个 **C 风格字符串指针**（`char*`），而 `std::string` 是一个**对象**。`.c_str()` 返回底层那个指针。

不写 `.c_str()` 编译能过，但运行时会打印乱码。

</details>

<details>
<summary><b>题 9：加了一个新的 <code>.cpp</code> 文件，<code>CMakeLists.txt</code> 要改哪几处？</b></summary>

**四处**：

```cmake
find_package(依赖 REQUIRED)                                      # ① 用到新依赖时
add_executable(名字 src/新文件.cpp)                              # ② 点名
target_link_libraries(名字 rclcpp::rclcpp ${std_msgs_TARGETS})   # ③ 链接
install(TARGETS ... 名字 DESTINATION lib/${PROJECT_NAME})        # ④ 安装
```

**只写 ②③ 忘了 ④** → 能编译但 `ros2 run` 找不到。

</details>

<details>
<summary><b>题 10：为什么 C++ 包改了 <code>.cpp</code> 必须重新 build，而 Python 包加了 <code>--symlink-install</code> 就不用？</b></summary>

Python 是**解释执行**的：`--symlink-install` 让 `install/` 里的软链接直通 `src/` 里的 `.py` 源文件，源码一改，下次运行就是新的。

C++ 是**编译**的：产物是**二进制可执行文件**，`src/talker.cpp` 的内容不会进入运行时 —— 它已经被"翻译"成机器码了。**改了源文件就必须重新翻译一遍**，软链解决不了。

</details>

<details>
<summary><b>题 11：VSCode 里 <code>#include "rclcpp/rclcpp.hpp"</code> 报"找不到路径"，但 <code>colcon build</code> 通过。哪个是对的？怎么修？</b></summary>

**`colcon build` 是对的。**

VSCode 的红线来自 IntelliSense，它读 `.vscode/c_cpp_properties.json` 的 `includePath`；编译器读 `CMakeLists.txt`。两套独立的配置。

修法：在 `includePath` 里加 `"/opt/ros/lyrical/include/**"`。

**结论：编辑器红线是提示，不是判决。**

</details>

<details>
<summary><b>题 12：C++ 写的 <code>talker</code> 发的消息，Python 写的 <code>listener</code> 能收到吗？为什么？</b></summary>

**能。**

话题是一份**语言无关的契约**。`rclpy` 和 `rclcpp` 只是同一个 DDS 通信层上的两套语言外壳。能不能通，只取决于**话题名**和**消息类型**是否一致，跟用什么语言写无关。

</details>

<details>
<summary><b>题 13：<code>main()</code> 里三行 <code>rclcpp::init</code> / <code>spin</code> / <code>shutdown</code>，分别对应 Python 的什么？为什么 C++ 必须有 <code>main()</code>？</b></summary>

| C++ | Python |
|---|---|
| `rclcpp::init(argc, argv)` | `rclpy.init()` |
| `rclcpp::spin(...)` | `rclpy.spin(node)` |
| `rclcpp::shutdown()` | `rclpy.shutdown()` |

C++ 必须有 `main()`，因为编译产物是**可执行文件**，操作系统规定程序入口必须是 `main()`。Python 脚本是**从头到尾执行**的，`if __name__ == '__main__':` 只是约定，不是强制。

</details>

---

## 附：待办

- [ ] `src/talker.cpp` 里两处 `"..."` 占位符还没换成真正的内容（第 29 行、第 32 行）。
      预期改成：
      ```cpp
      msg.data = "第 " + std::to_string(count_) + " 次心跳";
      RCLCPP_INFO(this->get_logger(), "发布: %s", msg.data.c_str());
      ```
      改完记得 `colcon build --packages-select hello_ros_cpp` 再验证。

---

## 附：命令速记卡

```bash
# ---------- 新建 C++ 包 ----------
cd ~/ros2_learn_ws/src
ros2 pkg create --build-type ament_cmake --node-name 节点名 包名

# ---------- 构建 ----------
cd ~/ros2_learn_ws
colcon build --packages-select hello_ros_cpp
source install/setup.bash

# ---------- ⭐ 先验可执行文件 ----------
ls install/hello_ros_cpp/lib/hello_ros_cpp/

# ---------- 运行 ----------
ros2 run hello_ros_cpp hello_cpp
ros2 run hello_ros_cpp talker

# ---------- 观察 ----------
ros2 node list
ros2 topic echo /chatter
ros2 interface show std_msgs/msg/String

# ---------- 查函数返回类型（成员变量该写什么） ----------
grep -A3 "create_publisher" /opt/ros/lyrical/include/rclcpp/rclcpp/node.hpp

# ---------- 查头文件目录（报错名字拿去 ls） ----------
ls /opt/ros/lyrical/include/ | grep -i '前缀'
```
