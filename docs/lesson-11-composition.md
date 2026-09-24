# 第 11 关 · Composition（组件与容器）

> 前十关，我们一直默默默认了一件事：**一个节点 = 一个进程**。
> `ros2 run` 起一个节点，屏幕上就多一个进程；Ctrl+C 关掉，进程就少一个。
> 十关下来，这条默认从来没被怀疑过。
>
> 这一关把它掀掉：**一个进程里，可以住好几个节点。**
>
> 一句话：**组件（Component）是"一个没有 `main` 的节点类"，容器（Container）是"那个负责把它造出来的进程"。**
>
> 本关最重的一击是一个数字：
> **屏幕上 4 个节点，`pgrep -c compo` 数出来只有 1 个进程。**

---

## 目录

- [1. 本关目标](#1-本关目标)
- [2. 核心概念](#2-核心概念)
- [3. 完整代码](#3-完整代码)
- [4. 命令速查（CLI）](#4-命令速查cli)
- [5. 命令行工具速查](#5-命令行工具速查)
- [6. 构建与运行流程](#6-构建与运行流程)
- [7. 实测现象与结论 ⭐](#7-实测现象与结论-)
- [8. 踩坑记录](#8-踩坑记录)
- [9. 自测题](#9-自测题)
- [10. 附：跨关待办](#10-附跨关待办)
- [附：本关命令速记卡](#附本关命令速记卡)

---

## 1. 本关目标

- 说清**组件**和**普通节点**在代码上差哪两处（构造函数 / `main`）。
- 说清**容器**是什么，以及它和里面装的节点是什么关系。
- **能亲手把"节点数 ≠ 进程数"量出来** —— 本关唯一必须记住的一句话。
- 会用 `ros2 component list / load / unload / types / standalone`。
- 会把一个现成的节点**改造成组件**（改 2 行 + 动 CMake 4 处）。
- 知道组件的 `.so` **必须装到 `lib/`，不是 `lib/${PROJECT_NAME}/`**，以及装错之后是什么症状。

**这一关的性子**：概念只有一层，但**它踩中了你十个关以来所有的老账** ——
类型匹配（第 1 关）、QoS 三件套（第 8 关）、命名空间（第 10 关）、
重映射左边要写全名（第 10 关）、执行器（第 7 关）**一个都没少**。

> 如果你只从这一关带走一件事，带走这句：
>
> **composition 省的是「进程开销」，不改任何通信规则。**
> 装进同一个进程里的两个节点，**照样得靠话题名 + 消息类型 + QoS 三样互相对上**才能说上话。

---

## 2. 核心概念

### 2.1 组件 = 一个没有 `main` 的节点类

`talker.cpp` 和 `talker_component.cpp` 的差别，**只有两处**：

| | `talker.cpp`（普通节点） | `talker_component.cpp`（组件） |
|---|---|---|
| 类名 | 没有类，只有 `main()` 里的函数 | `class Talker : public rclcpp::Node` |
| 构造函数 | —— | `Talker(const rclcpp::NodeOptions & options)` |
| `main()` | **有**（`rclcpp::init` / `spin` / `shutdown`） | **删掉**（一行都不留） |
| 最后一行 | —— | `RCLCPP_COMPONENTS_REGISTER_NODE(Talker)` |
| 编译产物 | **可执行文件**（程序） | **`.so` 动态库**（库） |

**为什么删掉 `main`？**
因为"什么时候开始转"这件事，已经**不归它管了** —— 归容器管。

> **有 `main` 的东西自己会跑；没有 `main` 的东西，得等别人把它造出来。**

这就是组件和普通节点最本质的分工：
**普通节点是"程序"，组件是"零件"。**

### 2.2 容器 = 那个装着零件的进程

```bash
ros2 run rclcpp_components component_container
```

这一条起起来的东西就是容器。它**本身也是一个节点**，节点名固定叫 `/ComponentManager`。

它干的活只有三件：

1. 举着一份**零件清单**（`ros2 component types` 看到的那张表）；
2. 你叫它装哪个，它就**打开对应的 `.so`、造一个对象、把那个对象当成一个节点挂到 ROS 图上**；
3. 你按 Ctrl+C，它就带着身上所有零件一起消失。

**容器自己不会发布任何话题，也不会订阅任何话题** ——
它就是个"托儿所"，安静地待在图上。

### 2.3 ⭐⭐ 节点数 ≠ 进程数

这是本关的地基，也是**唯一需要死记住的一条**。

| 数什么 | 命令 | 结果 |
|---|---|---|
| **节点** | `ros2 node list` | `/ComponentManager`、`/talker_cpp`、`/listener`、`/talker` = **4 个** |
| **组件** | `ros2 component list` | `1 /talker_cpp`、`4 /listener`、`5 /talker` = **3 个** |
| **进程** | `pgrep -c compo` | **1 个** |

**三个数字，一台机器，同时成立。**

为什么容器自己不算"组件"？因为它**不是被装进去的** ——
它是那个**装别人的人**，它自己就是那个进程。

> ⭐ 这一关真正在教的是**"数出来的东西 ≠ 你以为的东西"**：
> `ros2 node list` 数的是**图上的身份**，`pgrep` 数的是**操作系统里的进程**。
> 这两样东西**从来就不是一回事**，只是前面十关里它们恰好一比一，所以你没机会发现。

**前面十关是"碰巧一比一"。**

### 2.4 装载的那一刻，发生了什么

你在终端敲：

```bash
ros2 component load /ComponentManager hello_ros_cpp Talker
```

容器那个终端**会多出三行**：

```
[INFO] [xxx] [component_container]: Load Library: /home/l/ros2_learn_ws/install/hello_ros_cpp/lib/libtalker_component.so
[INFO] [xxx] [component_container]: Found class: rclcpp_components::NodeFactoryTemplate<Talker>
[INFO] [xxx] [component_container]: Instantiate class: rclcpp_components::NodeFactoryTemplate<Talker>
```

三行就是三件事，**一一对应**：

| 日志 | 动作 | 用到的信息 |
|---|---|---|
| `Load Library:` | **打开那个 `.so` 文件** | 插件登记表里记的路径 |
| `Found class:` | **在里面找到 `Talker` 这个类** | `RCLCPP_COMPONENTS_REGISTER_NODE(Talker)` 留下的登记 |
| `Instantiate class:` | **`new` 一个出来，挂到图上** | 构造函数 |

**而你敲命令的那个终端**，收到的是容器回给你的一句回执：

```
Loaded component 1 into '/ComponentManager' container node as '/talker_cpp'
```

一个命令的**两端**：你那边一句"成功了"，容器那边三行"我干了什么"。
**看现象要两边都看** —— 这是第 9 关"判据实验"的同一个习惯。

### 2.5 ⭐ 容器身上那三个隐形服务

前面十关有个动作一直很好用：

```bash
ros2 service list | grep -i 关键词
```

**在容器身上，它返回空。** 但服务明明在。加一个开关就出来了：

```bash
ros2 service list --include-hidden-services
```

那三个服务长这样：

```
/ComponentManager/_container/list_nodes
/ComponentManager/_container/load_node
/ComponentManager/_container/unload_node
```

**为什么藏起来？**
因为**它们不是给你手敲的** —— `ros2 component load` 这条命令，
**底下就是去调 `load_node` 这个服务**。它们是 CLI 的内部接口。

> 这个形状**第 5 关见过一次**：动作（Action）也是拿隐藏的服务和话题拼出来的，
> `ros2 service list` 默认也看不见它们。
> **规律**：ROS 里凡是"给工具自己用、不给人手敲"的接口，**都默认藏在 `--include-hidden-services` 后面。**

⚠️ 顺带记一笔：`ros2 node info /ComponentManager` **看不到**这三个服务。
它只列话题、服务、动作的"公开面"。

### 2.6 ⭐ 组件的构造函数契约（**这里有一句英文，我给你翻好了**）

`RCLCPP_COMPONENTS_REGISTER_NODE` 这个宏对类**有要求**。
要求写在头文件的注释里，原文是：

```cpp
// /opt/ros/lyrical/include/rclcpp_components/rclcpp_components/register_node_macro.hpp
 *  * Have a constructor that takes a single argument that is a `rclcpp::NodeOptions` instance.
```

**中文**：

> **构造函数必须只收一个参数，类型是 `rclcpp::NodeOptions`。**

所以正确的那一行是：

```cpp
Talker(const rclcpp::NodeOptions & options) : Node("talker_cpp", options)
//     ↑ 类型是 rclcpp::NodeOptions（不是 rclcpp_components::NodeOptions！）
//                              ↑ & 是"引用"，收东西不用拷贝
//                                        ↑ options 是【变量名】，你自己起
//                                                 ↑ 转手交给 Node 基类
```

四个位置**各自归谁管**，拆开看：

| 位置 | 写什么 | 归谁姓 |
|---|---|---|
| ① `rclcpp::` | 库名 | **看 `Node` 是哪个库的** → `rclcpp` |
| ② `NodeOptions` | 类型名 | 同上 |
| ③ `const ... &` | 引用，不拷贝 | C++ 语法 |
| ④ `options` | **变量名** | **你起** —— 右边 `Node(...)` 里用的就是它 |

**为什么容器非要传 `NodeOptions` 进来？**
因为**容器是"替你启动"的那个人**。命名空间、参数、重映射这些"启动时才定的东西"，
全都是通过这个 `options` **从外面塞进去的**。

> 第 10 关的 `--ros-args -r __ns:=/robot1` 为什么在组件上也能用？
> 因为它就是塞进了这个 `options`。

### 2.7 CMake 的四处 + 一张登记表

把一个节点变成组件，CMake 要动**四处**：

```cmake
find_package(rclcpp_components REQUIRED)          # ① 找到这个包

add_library(talker_component SHARED src/talker_component.cpp)   # ② 库，不是可执行文件
target_link_libraries(talker_component
  rclcpp::rclcpp
  rclcpp_components::component                    # ③ 链上组件库
  ${std_msgs_TARGETS})
rclcpp_components_register_nodes(talker_component "Talker")     # ④ 登记

install(TARGETS talker_component
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib                         # ⑤ 装到 lib/，不是 lib/${PROJECT_NAME}/
  RUNTIME DESTINATION bin)
```

**第 ④ 处 `register_nodes` 干的事，是往磁盘上写一张表。**

那张表在这个位置：

```bash
install/hello_ros_cpp/share/ament_index/resource_index/rclcpp_components/hello_ros_cpp
```

里面只有一行：

```
Talker;lib/libtalker_component.so
```

**读法**：

```
Talker  ;  lib/libtalker_component.so
  ↑           ↑
类名        这个 .so 的【相对路径】
（全名，     （相对于 install/hello_ros_cpp/）
 不带包名）
```

**两端必须对上**：表上写 `lib/libtalker_component.so`，
东西就**必须真的在** `install/hello_ros_cpp/lib/libtalker_component.so`。

> ⚠️ **装到 `lib/hello_ros_cpp/` 会怎么坏？**
> 表照写、`colcon build` 全绿、`ros2 component types` **照样能列出 `Talker`** ——
> 因为那张表是**在 build 的时候写的**，它不管东西最后落在哪。
> 然后 `ros2 component load` 才炸：**表上挂号了，人却不在那儿。**
>
> **这就是本关最典型的"绿灯 ≠ 生效"，和 cpp-01 坑 8（漏了 `install` → `ros2 run` 说 No executable found）同一个形状。**

### 2.8 ⭐ 类名 ≠ 节点名

这是本关最容易看岔的一处：

| 名字 | 值 | 从哪来 | 用在哪 |
|---|---|---|---|
| **类名** | `Talker` | 登记表 `Talker;lib/...` | `ros2 component types`、`ros2 component load ... hello_ros_cpp Talker` |
| **节点名** | `/talker_cpp` | 构造函数里的 `Node("talker_cpp", options)` | `ros2 node list`、`ros2 component list` |

**一个是"这个零件叫什么型号"，一个是"这一个装上去叫什么名字"。**

所以：

- 同一个类，**可以同时装好几个**，各起各的节点名（重映射 `__node:=` 也行）；
- 类名是**全局**的，不带包名前缀（登记表里写的是 `Talker`，不是 `hello_ros_cpp/Talker`）；
- 但 `load` 的时候**要连包名一起给**：`ros2 component load <容器> <包名> <类名>`。

---

## 3. 完整代码

### 本关唯一的新文件：`src/hello_ros_cpp/src/talker_component.cpp`

它是从 [talker.cpp](../src/hello_ros_cpp/src/talker.cpp) **复制**出来改的。
**只改了 2 处，其余一个字没动**（连 `pub_` / `timer_` / `count_` 都一模一样）。

```cpp
#include <chrono>
#include <memory>
#include <string>

#include "rclcpp/rclcpp.hpp"
#include "std_msgs/msg/string.hpp"
#include "rclcpp_components/register_node_macro.hpp"   // ← 改①：多这一个头（最后那个宏要用）

using namespace std::chrono_literals;


class Talker : public rclcpp::Node                      // ← 改②：从"散装 main"变成"一个类"
{
public:
    Talker(const rclcpp::NodeOptions & options) : Node("talker_cpp", options)
    //  ↑ 收 options，原样转交给 Node 基类 —— 容器就是这么把命名空间/参数塞进来的
    {
        count_ = 0;

        pub_ = this->create_publisher<std_msgs::msg::String>("chatter", 10);
        timer_ = this->create_wall_timer(1s, [this]() { tick(); });
    }

private:
    void tick()
    {
        count_ += 1;

        auto msg = std_msgs::msg::String();
        msg.data = "第" + std::to_string(count_) + "次心跳";
        pub_->publish(msg);

        RCLCPP_INFO(this->get_logger(), "发布：%s", msg.data.c_str());
    }

    rclcpp::Publisher<std_msgs::msg::String>::SharedPtr pub_;
    rclcpp::TimerBase::SharedPtr timer_;
    int count_;
};

RCLCPP_COMPONENTS_REGISTER_NODE(Talker)                 // ← 改③：登记这一行
```

**和 `talker.cpp` 的对照表（整份文件只差这些）**：

| | `talker.cpp` | `talker_component.cpp` |
|---|---|---|
| `#include .../register_node_macro.hpp` | 无 | **有** |
| `class Talker : public rclcpp::Node` | 无 | **有** |
| `Talker(const rclcpp::NodeOptions & options)` | 无 | **有** |
| `TickPublisher`（自己起的类名） | 有 | 无（不需要了） |
| `int main(int argc, char * argv[])` | 有，**20 多行** | **整段删掉** |
| `RCLCPP_COMPONENTS_REGISTER_NODE(Talker)` | 无 | **有** |

> **`main()` 整段删掉**，这是最关键的一刀。
> 删掉之后它就不是"程序"了，是"零件"—— 谁来 `new` 它，谁就是它的 `main`。

### `CMakeLists.txt` 的改动

见 §2.7。要点重复一遍：**`add_library` 不是 `add_executable`；`.so` 装 `lib/` 不是 `lib/${PROJECT_NAME}/`。**

### `package.xml` 的改动

```xml
<depend>rclcpp_components</depend>
```

**一行。** 少这一行，`find_package` 会在别人机器上找不到（本机能过是因为 `/opt/ros` 里有）。

### 用到的现成组件（来自 `demo_nodes_cpp` / `composition`）

本关大量拿官方包当"陪练"：

```bash
ros2 component types        # 会列出 demo_nodes_cpp 和 composition 里的一堆组件
```

| 组件 | 包里 | 节点名 | 干什么 |
|---|---|---|---|
| `composition::Talker` | `composition` | `/talker` | 发 `example_interfaces/String` 到 `chatter` |
| `composition::Listener` | `composition` | `/listener` | 订 `example_interfaces/String` 的 `chatter` |
| `demo_nodes_cpp::Talker` | `demo_nodes_cpp` | `/talker` | 另一份同名同姓的 talker |

⚠️ 注意上面两个 `Talker` **同名叫 `Talker`，但不同包** ——
所以 `load` 时**包名必须给**，不然它不知道你要哪一个。

---

## 4. 命令速查（CLI）

### 起容器

```bash
ros2 run rclcpp_components component_container
```

**就这一条**。起起来之后终端是**安静的**（不打印任何东西），别以为它没起来。

### 看清单 / 看容器里装了什么

```bash
ros2 component types                    # 全机器的组件清单（每种零件）
ros2 component list                     # 每个容器里【已经装上的】（每一件）
```

### 装 / 卸

```bash
ros2 component load /ComponentManager hello_ros_cpp Talker
#                    ↑容器名           ↑包名          ↑类名
ros2 component unload /ComponentManager 1
#                                       ↑ component list 里那个编号
```

### 单独跑一个组件（不装容器）

```bash
ros2 component standalone hello_ros_cpp Talker
```

`standalone` 的意思是"**临时造个容器，只装这一个**" ——
效果上等价于 `ros2 run`，但是**按类名找，不是按可执行文件名找**。

**用途**：组件装载失败时，用它把组件单独拎出来跑，看是组件本身坏了还是容器的问题。

### 装载时顺手改名字 / 换话题

```bash
# 换个节点名
ros2 component load /ComponentManager hello_ros_cpp Talker -n my_talker
# 加命名空间（第 10 关那套，原样适用）
ros2 component load /ComponentManager hello_ros_cpp Talker --node-namespace /robot1
# 重映射（⭐ 左边必须写【展开后的全名】—— 第 10 关最重的那条规则）
ros2 component load /ComponentManager composition composition::Listener -r /chatter:=/demo_chatter
```

> ⚠️ **`-r` 在 `ros2 component load` 里是 `--remap`**（不是 `--rate`）。
> **判据永远是 `--help`，不是记忆。**（第 10 关 §7.5 栽过一次了。）

---

## 5. 命令行工具速查

### 数进程用这条 ⭐

```bash
pgrep -c compo
```

**为什么是 `compo` 不是 `component_container`？**

| 命令 | 结果 |
|---|---|
| `pgrep -c component_container` | **0** + 一句 warning |
| `ps -C component_container` | **空** |
| `pgrep -c compo` | **1** ✅ |

原因：Linux 的 `comm`（进程名）字段**只留 15 个字符**，
`component_container` 被截断成 `component_conta`。
`pgrep` 默认只匹配 `comm`，**给全名反而匹配不上**。

> **这是本关一个很好的"工具本身有坑"的样例**：
> 量错了不是你的错，但**量出来的数不对时，先怀疑尺子**。

### 看节点 / 看话题（老三条）

```bash
ros2 node list
ros2 node info /ComponentManager
ros2 topic info /chatter
```

⚠️ `ros2 node info /ComponentManager` **看不见**那三个 `_container` 服务（§2.5）。

### 看隐藏服务

```bash
ros2 service list --include-hidden-services | grep _container
```

### 看这个包到底装了什么

```bash
ros2 pkg executables hello_ros_cpp
```

⚠️ 这一条只数**可执行文件**。组件**不在里面** ——
组件是 `.so`，不是 executable。组件的清单在 `ros2 component types`。

### 收工检查（第 9 关起的老规矩）

```bash
ros2 node list                      # 动手之前：必须是空的
ps -eo pid,etimes,args | grep ros2  # 收工之后：etimes 几百秒的必是残留
```

⚠️ **容器是"一个进程装一堆节点"，所以它残留的时候，`ros2 node list` 会一次多出好几个** ——
比单个残留节点更显眼，也更容易骗人。

---

## 6. 构建与运行流程

### 构建（本关**必须** build）

```bash
cd /home/l/ros2_learn_ws
colcon build --packages-select hello_ros_cpp --symlink-install
```

⚠️ **改了 CMakeLists 必须重新 build** —— 登记表是在 build 那一刻写出来的。

### 验收：build 完先看两样

```bash
source install/setup.bash

ros2 component types | grep -A2 hello_ros_cpp     # 表上有没有 Talker
ls install/hello_ros_cpp/lib/libtalker_component.so   # 人有没有真的在那儿
```

**这两条是配套的**：第一条查"挂了号没"，第二条查"东西在不在"。
**只查第一条会骗你**（§2.7 那个坑）。

### 一次完整的运行

**终端 A**：

```bash
source /opt/ros/lyrical/setup.bash
source install/setup.bash
ros2 run rclcpp_components component_container
```

**终端 B**：

```bash
source install/setup.bash
ros2 component load /ComponentManager hello_ros_cpp Talker
```

### 验收清单（**自己判，别让我判**）

| 看什么 | 应该是 |
|---|---|
| `ros2 node list` | 2 个：`/ComponentManager` + `/talker_cpp` |
| `ros2 component list` | 1 行：`1 /talker_cpp` |
| `pgrep -c compo` | **1** |
| 终端 A | 多了 **3 行**（Load Library / Found class / Instantiate class） |
| 终端 B | 一句 `Loaded component 1 into '/ComponentManager' container node as '/talker_cpp'` |

**五个都对上，这一关的"地基"就打好了。**

---

## 7. 实测现象与结论 ⭐

### 7.1 容器起来的那一刻：终端是安静的

| 看什么 | 结果 |
|---|---|
| 终端 A 打印 | **什么都不打印** |
| `ros2 node list` | `/ComponentManager` |
| `pgrep -c compo` | 1 |

**结论**："起容器"这个动作，**唯一的证据是节点名 `/ComponentManager` 出现在图上**。
终端安静**不代表没起来** —— 这条和第 4 关那句"绿灯 ≠ 做了你想做的事"是同一族。

⚠️ 本关课堂实测：你在容器还没起来的时候就跑了 `ros2 node list`，
看到的是空 —— 这不是 bug，是**顺序问题**。

### 7.2 装载一个组件：两端各有一句话

**容器那边（终端 A）3 行** / **你这边（终端 B）1 行**，见 §2.4。

**结论**：**"装载"这个动作把两个终端连起来了** ——
你那边是回执，它那边是过程。**以后查这类问题，永远两边都看一眼。**

### 7.3 ⭐⭐ 判据实验：3 个组件 / 4 个节点 / **1 个进程**

这是本关的核心测量。装到 3 个组件时的完整状态：

| 看什么 | 结果 |
|---|---|
| `ros2 component list` | `1 /talker_cpp`、`4 /listener`、`5 /talker` |
| `ros2 node list` | `/ComponentManager`、`/listener`、`/talker`、`/talker_cpp` = **4 个** |
| `pgrep -c compo` | **1** |

**你的预测是 2 个进程（`2 个，一个是容器，一个是 listener`）。实际是 1。**

> **这一格就是整关的教学现场。**
>
> 为什么你会预测 2？因为前十关里"节点"和"进程"**从来没分开过** ——
> 你的脑子里它们是一个东西，所以"多一个节点"自然地等于"多一个进程"。
>
> **而这正是这一关要拆掉的那个默认。**

**三个数字之间的关系**：

```
4 个节点  =  1 个容器节点 + 3 个装进去的组件节点
1 个进程  =  容器本身（它装的那 3 个，住它身体里，不另开进程）
3 个组件  =  4 个节点 − 1 个容器节点
```

⚠️ **"组件"和"节点"的计数口径不一样**：容器**是**节点，但**不是**组件。

### 7.4 卸载：干净的一次 vs 重复的一次

**干净卸载**（终端 B）：

```
Unloaded component 1 from '/ComponentManager' container node
```

**容器那边：一行都不打印。** （装载有 3 行日志，卸载什么都没有。）

**再卸一次同一个编号**：

```
Failed to unload component 1 from '/ComponentManager' container node
  / No node found with unique_id: 1
```

**容器那边：多一行 `[WARN]`。**

**结论**：这两句话**天差地别**，而且**都是"卸载"这个词开头的**。
分不清就会像本关课堂上那样，以为"命令写错了"。

> **判据**：`Unloaded` = 成功；`Failed to unload ... No node found` = **它已经不在了**。
> 不是命令错，是**你在卸一个已经卸掉的东西**。

### 7.5 Ctrl+C 容器 = 全灭

在容器那个终端按 Ctrl+C：

| 看什么 | 结果 |
|---|---|
| `pgrep -c compo` | **0** |
| `ros2 node list` | **空** |
| `ros2 component list` | 空 |

**结论**：**容器死了，身上所有的零件跟着一起死**（它们都在同一个进程里）。

> 这是 composition 的**代价**：省了进程开销，也**绑定了生死**。
> 一个进程崩了，里面所有节点全没。
> （反过来说，分开跑的话，listener 崩了 talker 还在。）

### 7.6 ⭐⭐ 类型冲突：字段一模一样，也配不上

课堂上装载官方 `Listener` 时炸了，报错原文：

```
[ERROR] [...] Component constructor threw an exception:
  could not create subscription: create_subscription() called for existing
  topic name rt/chatter with incompatible type example_interfaces::msg::dds_::String_
```

**翻译**：你这个容器里已经有一个 `/chatter` 了，**类型对不上**，订不了。

对一下两个"String"：

```bash
$ ros2 interface show std_msgs/msg/String
string data                     # 我们的 talker_cpp 发的

$ ros2 interface show example_interfaces/msg/String
string data                     # 官方 Listener 要收的
```

**两行字一模一样 —— 一个字段、一个类型、一个名字。**

但：

```
[ERROR] ... incompatible type example_interfaces::msg::dds_::String_
```

**结论**：

> **⭐ DDS 配话题，比的是「类型名」这三个字，不是「字段长什么样」。**
> `std_msgs/msg/String` 和 `example_interfaces/msg/String` 在 DDS 眼里
> 是**两个完全不同的类型** —— 它俩的 IDL 全名不同
> （`std_msgs::msg::dds_::String_` vs `example_interfaces::msg::dds_::String_`）。

**解药**（两种，效果一样）：

```bash
# ① 让 listener 换一个话题名（推荐，不碰原话题）
ros2 component load /ComponentManager composition composition::Listener -r /chatter:=/demo_chatter

# ② 或者让两边用同一个类型名（要改代码，本关不做）
```

**修好之后的对照表**（⭐ 这张表值得记）：

| 话题 | 类型 | 发布者 | 订阅者 |
|---|---|---|---|
| `/chatter` | `std_msgs/msg/String` | 1 | **0**（自言自语） |
| `/demo_chatter` | `example_interfaces/msg/String` | 1 | 1 |

**`/chatter` 上那个 `Publisher 1 / Subscription 0`，就是 §7.6 那个报错的静态样子。**

> 这一条把**第 1 关和第 8 关的账一起结了**：
> 两个节点要说得上话，要看**三样** ——
> **话题名**（第 1 关）、**消息类型**（本关）、**QoS**（第 8 关）。
> 三样里差一样，症状都是"收不到"。

### 7.7 从零 build，组件照样挂得上号

课堂上有一步是**删掉 `build/` 和 `install/` 重来一遍**：

```bash
rm -rf build/hello_ros_cpp install/hello_ros_cpp
colcon build --packages-select hello_ros_cpp --symlink-install
```

之后 `ros2 component types` 里 **`hello_ros_cpp / Talker` 还在**，`.so` 也还在 `lib/`。

**结论**：CMakeLists 里那四处**是完整的**，之前能跑不是靠残留产物撑着。

> ⭐ **"删干净重来一遍"是个便宜又硬的验收动作。**
> 增量 build 会**藏住"其实少写了一行"** —— 旧的产物还在，你就看不出来。
> （本关正好栽过一次，见 §8 坑 9。）

### 7.8 关掉之后：一切归零

Ctrl+C 容器之后，全部清空（§7.5）。
**下一次实验前先 `ros2 node list` 确认是空的** —— 第 9 关起的老规矩。

---

## 8. 踩坑记录

### ❌ 坑 1：把组件当程序写 —— `add_executable`

**你写的**：

```cmake
add_executable(talker_component src/talker.cpp)
```

**错在哪**：**组件是"库"，不是"程序"。**

| | 程序 | 库 |
|---|---|---|
| CMake 命令 | `add_executable` | `add_library(... SHARED ...)` |
| 有 `main` 吗 | **有** | **没有** |
| 自己会跑吗 | 会 | **不会，等别人装载** |
| 产物 | 可执行文件 | `.so` |
| 谁能用 | 谁都能 `ros2 run` | **只有容器能装** |

**判据（以后照这个想）**：

> **"这个东西自己有一个 `main` 吗？"**
> 有 → `add_executable`；没有 → `add_library`。
>
> **组件没有 `main`（§3 里整段删掉了），所以是库。**

### ❌ 坑 2：改了左边没改右边 —— 源文件名还是 `talker.cpp`

同一行里，你把 **target 名**改成了 `talker_component`，
但**源文件**还写着 `src/talker.cpp`（那个是**没动过的原件**）。

**正确的源文件是 `src/talker_component.cpp`** —— 你新造的那一份。

> ⚠️ **这是第 4 关那个 `glob` 坑的镜像版**：
> 那次你**一直改右边，从来不改左边**；这次反过来。
>
> **规律**：一行里有两三个"长得像名字的东西"时，
> **动手前先数一数这行有几个名字，一个一个点名。**
> （第 4 关那条"整行替换，不是改哪个字符"，就是为这个。）

### ❌ 坑 3：`.so` 装到了 `lib/hello_ros_cpp/`

**你的想法**：把 `talker_component` 加进那一行现成的

```cmake
install(TARGETS hello_cpp talker listener status_listener
  DESTINATION lib/${PROJECT_NAME})
```

**错在哪**：那一行装的是**程序**，装进包专属的 `lib/hello_ros_cpp/`，
只有这个包自己用。**组件不是这样。**

**组件要装到 `lib/` 那一层**，因为登记表上写的就是 `lib/libtalker_component.so`（§2.7）。

**症状**（如果装错层级）：

```
表上有 Talker  ✅  ros2 component types 列得出来
load 的时候炸  ❌  找不到那个 .so
```

> **"绿灯 ≠ 生效"** —— cpp-01 坑 8（漏 `install`）、第 4 关（glob 没求值）之后，**这是第三次**。
> **形状完全一样**：**某一步"记了一笔"成功了，但"那一笔指向的东西"不存在。**

### ❌ 坑 4：构造函数签名错了三处（**而且是我教法的问题**）

**你写的**：

```cpp
Talker(rclcpp_components::NodeOptions) : Node("talker_cpp", rclcpp_components::NodeOptions)
```

三处错：

| 错 | 你写的 | 应该 |
|---|---|---|
| ① 库名 | `rclcpp_components::` | `rclcpp::` |
| ② 少了 `const &` | `NodeOptions` | `const NodeOptions &` |
| ③ 右边用了**类型名** | `rclcpp_components::NodeOptions` | **变量名** `options` |

**①② 的根因是同一个层次混淆**：你**站在哪个文件里**，就顺手拿了哪个名字。
你当时正在看 `#include "rclcpp_components/register_node_macro.hpp"` —— 于是把 `rclcpp_components` 当成了 `NodeOptions` 的姓。

> ⭐ **一条规矩**：**一个名字归谁姓，看它自己的定义，不看你现在站在哪个文件里。**
> `NodeOptions` 定义在 `rclcpp` 里 → 它就姓 `rclcpp`。

**③ 的根因是"类型"和"变量"没分开**（cpp-02 那条老账）。

---

⚠️ **这里必须记一笔我自己的账，因为它比你的错更重要：**

我当时的教法是——**让你 F12 跳进那个头文件，自己读注释找构造函数签名。**

你照做了。但那个注释里**有两个 bullet**，你框了**第二条**
（`get_node_base_interface`，那是另一个要求，跟构造函数无关）。
我第二次指对了方向，你才读出来。

然后你直说了：

> **「我读不懂英语啊」**

**这是我的错，而且错得不轻。** 因为：

> **"去查一眼"这条策略能不能成立，前提是那个"一眼"你看得懂。**
> ROS 的头文件、宏注释、报错原文**全是英文** ——
> 我把关键信息锁在了一个**你打不开的地方**，然后催你自己去开。

所以从本关起，规矩改成：

| 你能做 | 我做 |
|---|---|
| **定位**（F12 / Ctrl+点击 / Ctrl+P）——**零英文门槛** | **解读**（把英文注释翻成中文再给你） |
| 照着中文版对照自己写的 | 报错原文也由我**圈出那半句 + 翻译** |

> **能查的让你查，查到的英文由我翻。**
> （和 cpp-02 那条"能查的让他查，不能查的（结构/层次）给模板"是一对。）

### ❌ 坑 5：改了 CMakeLists 不重新 build

**症状**：CMakeLists 改了，`ros2 component types` 里**没有 `Talker`**。

**原因**：**登记表是在 build 那一刻写出来的**。
不 build，磁盘上那张表根本还没被写。

> **第 4 关那条"新增 launch 文件必须重新 build"的同族**：
> **"我改了源码"和"生效了"之间，永远隔着一个 build。**

### ❌ 坑 6：`source install/setup.bash` 没敲 —— `component types` 静默空

**症状**：`ros2 component types | grep hello_ros_cpp` **返回空**，**一个错都不报**。

**原因**：那个终端**从头到尾没 source 过工作区**。
它敲的 `component_container`、`ros2 component`、`service list` 全是从 `/opt/ros` 来的 ——
**能跑，但眼里没有你的工作区。**

**修法**：

```bash
source install/setup.bash
```

之后 `hello_ros_cpp / Talker` 立刻出现。

> **「没报错 ≠ 没事发生」** ——
> 这和第 4 关的「绿灯 ≠ 做了你想做的事」、第 8 关的「不兼容是静默的」是同一族。
> **空结果和"真的没有"，长得一模一样。**
>
> **纪律**：**每个新终端，source 两句**：
> ```bash
> source /opt/ros/lyrical/setup.bash
> source install/setup.bash
> ```

### ❌ 坑 7：失败的装载也会**吃掉一个编号**

看你的 `ros2 component list`：

```
1 /talker_cpp
4 /listener
5 /talker
```

**2 和 3 呢？**

**它们被"装载失败"的组件吃掉了。**

组件编号是**递增发放**的，**不管这次装载成不成功**：

| 编号 | 发生了什么 |
|---|---|
| 1 | `talker_cpp` 装载**成功** |
| 2 | 装载了别的 → **炸了**（类型冲突，§7.6） |
| 3 | 又装载了一次 → **又炸了** |
| 4 | 修好之后 `Listener` 进来 → 成功 |
| 5 | demo `Talker` 进来 → 成功 |

**结论**：**编号有洞 = 中间有失败**。

> ⭐ **这是一个很好的"法证线索"** ——
> 屏幕上没有 2 和 3，但**它们存在过**。
> 就像第 9 关那个"2262 年"的哨兵值一样：**看不见的东西也在讲故事。**

### ❌ 坑 8：贴的是**片段**（第 9 关那条老账，本关**又犯了**）

你贴给我的那段里：

```
Hello World: 83                      ← 时间戳 1790247775
[WARN] ... No node found with unique_id: 1   ← 时间戳 1790247878
```

**两个时间戳差 103 秒。**

**中间那 ~103 秒的行，全被剪掉了。**

所以我从那段粘贴里**读不出**你跑了几次 —— 而你坚称"我就跑了 1 次"。
后来在干净容器里重做，**第一次卸载就成功了**。

**结论**：

> 你贴的东西**必须能自证"这是哪一次运行"** ——
> 而**自证的工具就是时间戳**。
>
> **剪掉中间 = 把证据剪掉了。**

**做法**：**一次实验的输出，从头到尾整段贴**；中间有别的实验，**中间加一行分隔**。

### ❌ 坑 9：陈旧 build 产物 —— `ros2 pkg executables` 里的幽灵（**收工时发现的**）

收工时把 CMakeLists 整理了一遍，然后 `ros2 pkg executables hello_ros_cpp` 里**还有 `talker_component`**：

```
hello_ros_cpp talker_component      ← 它根本不是可执行文件，是组件！
```

**原因**：CMakeLists 里**曾经**写过 `add_executable(talker_component ...)`（坑 1），
那次 build 在 `build/hello_ros_cpp/` 里**留下了一个可执行文件**。
改成 `add_library` 之后，**CMake 不会去删旧产物** ——
而 `--symlink-install` 的 install 目录**还软链着它**。

于是 `ros2 pkg executables` 里就飘着一个**早就不存在的身份**。

**修法**：**删干净重 build**（§7.7）：

```bash
rm -rf build/hello_ros_cpp install/hello_ros_cpp
colcon build --packages-select hello_ros_cpp --symlink-install
```

修完只剩下 4 个真正的程序。

> ⭐ **教训**：**增量 build 会藏住"其实少写了一行"，也会藏住"其实已经删掉的东西"。**
> **改过 CMake 的目标类型（可执行 ↔ 库）之后，删干净重来一遍。**

### 🔑 本关七条坑的公共形状

**七条里有四条是同一个形状**：

| 坑 | 记了一笔什么 | 那一笔指向的东西 |
|---|---|---|
| 3 `.so` 装错层 | 登记表写了 `lib/libtalker_component.so` | **不在那儿** |
| 5 不重新 build | 你脑子里"我改好了" | **磁盘上没改** |
| 6 没 source | `/opt/ros` 说"我没有这个包" | **你的包在，它看不见** |
| 9 陈旧产物 | `pkg executables` 说"有这个程序" | **那个程序已经不该存在** |

> **「有人替你记了一笔，你却没去核对那一笔指向的东西」** ——
> **这就是本关的公共形状。** 和 cpp-01 坑 8 是同一个祖先。

---

## 9. 自测题

### 9.1 课堂已覆盖（附答案，先自己答一遍再点开）

<details>
<summary><b>题 1：容器起来之后，终端打印什么？<code>ros2 node list</code> 看到什么？</b></summary>

**终端：什么都不打印。** `ros2 node list` → `/ComponentManager`。

**要点**：**起容器唯一的证据是节点名出现在图上，不是终端有话说。**

⚠️ 你在容器**还没起来**的时候跑了 `ros2 node list`，看到的是空 ——
**空结果和"真的没有"长得一样**（§8 坑 6 的同一个形状）。

</details>

<details>
<summary><b>题 2：装了 2 个组件之后，几个节点？几个进程？</b></summary>

**3 个节点，1 个进程。**

- 节点 = `/ComponentManager` + 装进去的那 2 个
- 进程 = **只有容器自己那一个**

**你的预测是 2 个进程，实际是 1。** 这一格就是整关的教学现场：

> 前十关"节点"和"进程"**从来没分开过**，
> 于是你以为"多一个节点 = 多一个进程"。
>
> **这一关拆的就是这个默认。**

</details>

<details>
<summary><b>题 3：<code>ros2 component list</code> 里的编号能重复用吗？</b></summary>

**不能。** 而且：

> **装载失败的组件也会吃掉一个编号。**

所以编号有洞（`1 / 4 / 5`）= 中间有失败过。

**这是法证线索**：屏幕上没有 2 和 3，但**它们存在过**。

</details>

<details>
<summary><b>题 4：为什么 <code>ros2 service list | grep -i container</code> 是空的？</b></summary>

**因为那三个 `_container` 服务是隐藏服务。**

```bash
ros2 service list --include-hidden-services
# /ComponentManager/_container/list_nodes
# /ComponentManager/_container/load_node
# /ComponentManager/_container/unload_node
```

**它们是给 `ros2 component` 这条命令自己用的**，不是给人手敲的。

> **规律**：ROS 里"给工具用、不给人手敲"的接口，**都藏在 `--include-hidden-services` 后面**。
> 第 5 关的动作（Action）也是这个形状。

⚠️ `ros2 node info /ComponentManager` **看不到**这三个。

</details>

<details>
<summary><b>题 5：<code>std_msgs/String</code> 和 <code>example_interfaces/String</code> 字段一模一样，为什么配不上？</b></summary>

**因为 DDS 比的是「类型名」，不是「字段长什么样」。**

```bash
ros2 interface show std_msgs/msg/String           # string data
ros2 interface show example_interfaces/msg/String # string data   ← 一模一样
```

但在 DDS 眼里：

```
std_msgs::msg::dds_::String_          ≠   example_interfaces::msg::dds_::String_
```

**两个完全不同的类型。**

**解药**：`-r /chatter:=/demo_chatter` 让它们用不同的话题名。

> ⭐ 这条把**第 1 关和第 8 关的账一起结了**：
> 两个节点要说得上话，看**三样** —— **话题名 / 消息类型 / QoS**，差一样就"收不到"。

</details>

<details>
<summary><b>题 6：组件的构造函数为什么必须收一个 <code>NodeOptions</code>？</b></summary>

**因为容器是"替你启动"的那个人 —— 启动时才定的东西，得从外面塞进去。**

命名空间、参数、重映射，全是通过这个 `options` 传进来的。

```cpp
Talker(const rclcpp::NodeOptions & options) : Node("talker_cpp", options)
//                                                                    ↑ 原样转交给基类
```

（头文件里的原文要求见 §2.6 —— 那句英文我给你翻好了。）

</details>

<details>
<summary><b>题 7：类名叫 <code>Talker</code>，节点名为什么是 <code>/talker_cpp</code>？</b></summary>

**因为这是两个不同的东西：**

| | 值 | 从哪来 |
|---|---|---|
| **类名** | `Talker` | 登记表 `Talker;lib/libtalker_component.so` |
| **节点名** | `/talker_cpp` | `Node("talker_cpp", options)` |

> **一个是"这个零件叫什么型号"，一个是"这一个装上去叫什么名字"。**

所以同一个类**可以同时装好几个**，各起各的节点名。

⚠️ `load` 时**包名要给**（`hello_ros_cpp Talker`），因为不同包里可能有**同名**的组件
（`composition::Talker` 和 `demo_nodes_cpp::Talker` 就是）。

</details>

### 9.2 留给下次的思考题（无答案）

1. **同一个组件装两次会怎样？**
   `ros2 component load /ComponentManager hello_ros_cpp Talker` 敲两遍 ——
   **能装进去吗？两个节点同名吗？** 先预测再跑。

2. **`ros2 component standalone` 和 `ros2 run` 到底差在哪？**
   一个按**类名**找，一个按**可执行文件名**找。
   **那为什么我们的 `talker_component` 用 `ros2 run` 起不来？**

3. **组件的命名空间从哪进去？**（第 10 关的账）
   ```bash
   ros2 component load /ComponentManager hello_ros_cpp Talker --node-namespace /robot1
   ```
   跑完看 `ros2 node list` 和 `ros2 topic list`，
   **和 `ros2 run ... -r __ns:=/robot1` 的效果一样吗？**

4. **⭐ 把 listener 也做成组件，让它和 talker 住同一个进程 ——**
   然后想：**这个进程里有几个执行器？**（提示：`component_container` 是**单线程**的。
   那第 7 关"执行器有几只手"这件事，在这里是什么？）
   **这是本关和第 7 关的接口。**

5. **`component_container` 和 `component_container_mt` 差在哪？**
   名字里那个 `mt` 是什么的缩写？（提示：回到第 7 关。）
   **同一个容器换成 `_mt`，上面第 4 题的结果会变吗？**

6. **composition 到底省了什么？**
   起 10 个节点，分开跑 vs 装一个容器里 ——
   `pgrep`、内存占用、**启动耗时**各差多少？
   设计一个能**量出来**的实验。（提示：第 9 关那套"判据实验"。）

---

## 10. 附：跨关待办

### ① ⭐ 本关你真正做到的一件事：**"我不知道怎么看"变成了"我数出来了"**

这一关的每一次测量，**都是你敲的**：

| 你敲的 | 你数出来的 |
|---|---|
| `pgrep -c compo` | 1 |
| `ros2 node list` | 4 |
| `ros2 component list` | 3 |
| `ros2 topic info /chatter` | 1 / **0** |

**而"节点数 ≠ 进程数"这个结论，是你自己被那三个数顶出来的** ——
你先预测了 2，数出来 1。

> 这是第 7 关以来一直在补的那一课（**验收权在你自己手里**），
> 本关第一次是**一整关都做到了**。

### ② ⚠️ 残留进程 —— 第 6 次

本关的新花样：**容器是"一个进程装一堆节点"**，
所以它残留的时候，`ros2 node list` 一次多出好几个 —— **比单个残留更显眼，也更容易骗人**。

**已固化的动作**（每关都要重复，因为症状一直在变）：

```bash
ros2 node list                      # 动手之前：必须是空的
pgrep -c compo                      # 容器专杀：应该是 0
ps -eo pid,etimes,args | grep ros2  # 收工之后：几百秒的必是残留
```

### ③ ⚠️ 贴输出分段（第 9 关那条老账，本关**又犯了**）

§8 坑 8：两个时间戳差 103 秒，中间的证据全被剪掉，
导致我从粘贴里读不出你跑了几次 —— **剪掉中间 = 把自证的证据剪掉了**。

**纪律**：**一次实验的输出整段贴；中间有别的实验，加一行分隔。**

### ④ 📌 一条关于"读英文"的教法修订（**我的账**）

§8 坑 4 那段。**你不必自责** —— 你 F12 跳对了文件，注释也真的读了一遍。

**是我把关键信息放在了一个你打不开的地方。**

已改的规矩：**定位你来做（F12 零门槛），解读我来做（英文注释和报错我翻成中文）。**

### ⑤ 本关的环境动作

- **新增** `src/hello_ros_cpp/src/talker_component.cpp`（从 `talker.cpp` 复制后改 3 处）
- **`CMakeLists.txt`**：加 `find_package(rclcpp_components)`、
  `add_library` + `register_nodes` 两段、**单独的 `install(... LIBRARY DESTINATION lib)`**
- **`package.xml`**：加 `<depend>rclcpp_components</depend>`
- **清理了历史遗留**：
  - `CMakeLists.txt` 里那段 cpp-02 的 `TODO 5` 接线说明（已完成）→ 压成 4 行速查
  - `talker.cpp` / `talker_component.cpp` 里两处 `// ⚠️ 待补` 注释（内容是已补好的真内容，注释是 cpp-01 的旧账）
  - `package.xml` 里"先不补看会不会报错"那句 → 换成实测结论（**不用补**）
- ⚠️ **本关必须重新 build**（登记表是 build 那一刻写的）。
  改过目标类型（可执行 ↔ 库）之后，**建议删干净重 build**（§7.7）。

---

## 附：本关命令速记卡

```bash
# ---------- 起容器（终端 A）----------
ros2 run rclcpp_components component_container
#   ⚠️ 终端【什么都不打印】—— 唯一证据是 ros2 node list 里出现 /ComponentManager

# ---------- 看清单（终端 B）----------
ros2 component types                 # 全机器有哪些【种】零件
ros2 component list                  # 每个容器【装上了哪几件】

# ---------- 装 / 卸 ----------
ros2 component load /ComponentManager hello_ros_cpp Talker
#                    ↑容器            ↑包名          ↑类名（不是节点名！）
ros2 component unload /ComponentManager 1
#                                       ↑ component list 里的编号
#   ✅ Unloaded component 1 from '/ComponentManager' container node
#   ❌ Failed to unload ... No node found with unique_id: 1
#        → 它【已经不在了】，不是命令错

# ---------- 单独拎出来跑 ----------
ros2 component standalone hello_ros_cpp Talker   # 临时造个容器只装这一个

# ---------- 装载时改名 / 换话题 ----------
ros2 component load /ComponentManager hello_ros_cpp Talker -n my_talker
ros2 component load /ComponentManager hello_ros_cpp Talker --node-namespace /robot1
ros2 component load /ComponentManager composition composition::Listener -r /chatter:=/demo_chatter
#   ⚠️ 这里 -r 是 --remap；左边必须写【展开后的全名】（第 10 关）

# ---------- 数进程（容器专杀）----------
pgrep -c compo
#   ⚠️ 不是 component_container —— comm 只有 15 字符，被截成 component_conta
#      给全名【匹配不上】，会返回 0 + 一句 warning

# ---------- 看隐藏服务 ----------
ros2 service list --include-hidden-services | grep _container
#   /ComponentManager/_container/{list_nodes,load_node,unload_node}

# ---------- 验收（⭐ 两条配套，缺一条会骗你）----------
ros2 component types | grep -A2 hello_ros_cpp          # 表上挂了号没
ls install/hello_ros_cpp/lib/libtalker_component.so    # 人真的在不在那儿
cat install/hello_ros_cpp/share/ament_index/resource_index/rclcpp_components/hello_ros_cpp
#   → Talker;lib/libtalker_component.so

# ---------- 构建 ----------
source install/setup.bash
colcon build --packages-select hello_ros_cpp --symlink-install
#   ⚠️ 改了 CMakeLists 必须重新 build（登记表是 build 那一刻写的）
#   ⚠️ 改过目标类型（可执行 ↔ 库）→ 删干净重来：
#      rm -rf build/hello_ros_cpp install/hello_ros_cpp

# ---------- 排查 ----------
ros2 node list                                  # 动手前必须是空的
ros2 topic info /chatter                        # 1 发布 0 订阅 = 有人在自言自语
ros2 interface show std_msgs/msg/String         # 类型对不上先对比这个
pgrep -c compo                                  # 收工后应该是 0
ps -eo pid,etimes,args | grep ros2              # 几百秒的必是残留

# ---------- 测试 ----------
colcon test --packages-select hello_ros_cpp
colcon test-result --verbose
```

---

## 相关笔记

- [第 1 关 · 话题](lesson-01-topic.md) —— "靠话题名配对"，本关 §7.6 证明它**只是三条件里的第一条**
- [第 4 关 · launch](lesson-04-launch.md) —— 「绿灯 ≠ 做了你想做的事」，本关坑 3/5/6/9 全是它的后代
- [第 5 关 · 动作](lesson-05-action.md) —— 隐藏服务/话题的形状，和本关那三个 `_container` 服务一模一样
- [第 7 关 · 执行器与回调组](lesson-07-executor.md) —— ⭐ 本关 §9.2 题 4/5 直接接回去：**容器是单线程的，那"几只手"呢？**
- [第 8 关 · QoS](lesson-08-qos.md) —— 三条件里的第三条；"不兼容是静默的"和本关坑 6 同族
- [第 9 关 · ros2 bag](lesson-09-bag.md) —— 判据实验、法证线索（哨兵值 ↔ 编号有洞）、贴输出要自证
- [第 10 关 · 命名空间与重映射](lesson-10-namespace.md) —— `-r 左边必须写全名`、`-r` 在不同命令里含义不同，本关**原样复用**
- [C++ 支线 01](cpp-01-getting-started.md) —— 坑 8（漏 `install` → No executable found）是本关坑 3 的祖先
- [C++ 支线 02](cpp-02-subscriber.md) —— "类型 vs 变量名"的层次混淆，本关坑 4 ③ 又犯了一次
