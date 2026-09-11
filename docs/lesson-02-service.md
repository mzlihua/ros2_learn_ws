# 第 2 关 · 服务 Service

> ROS 2 核心基础 · 课程笔记
> 学习日期：2026-09-11
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
9. [自测题（附答案）](#9-自测题附答案)

---

## 1. 本关目标

**学会让一个节点向另一个节点"提个问题并拿到答案"。**

话题是"广播"，服务是"打电话"。这是 ROS 2 里第二种通信方式，也是理解后面**动作 (Action)** 的基础。

产出两个可执行节点：

| 文件 | 角色 | 作用 |
|---|---|---|
| `add_server.py` | 服务端 Server | 提供 `add_two_ints` 服务，收到两个数就返回它们的和 |
| `add_client.py` | 客户端 Client | 主动调用上面的服务，打印 `3 + 4 = 7` |

服务类型用系统自带的 `example_interfaces/srv/AddTwoInts`（**不用自己定义**，自定义消息是第 6 关的事）。

---

## 2. 核心概念

### 2.1 一句话理解服务

> **客户端主动发一个请求 (Request)，服务端算完之后返回一个响应 (Response)。一来一回。**

```
客户端 ──Request（请求）──▶ 服务端
客户端 ◀──Response（响应）── 服务端
```

### 2.2 话题 vs 服务 ⭐ 最重要的一张表

|  | **话题 Topic** | **服务 Service** |
|---|---|---|
| 数据流 | 单向，一直流 | **一来一回**，问一次答一次 |
| 有没有回执 | ❌ 没有 | ✅ **有**，客户端能拿到结果 |
| 谁主动 | 发布者主动推 | **客户端主动问** |
| 需要等吗 | **谁都不等**，推完就走 | **两边都在等**：服务端等请求，客户端等响应 |
| 对应关系 | 多对多，匿名 | 一对一（一个请求配一个响应） |
| 典型用途 | 传感器数据、状态广播 | 算个数、查状态、让它做件事 |

一句话记忆：

> **话题 = "我喊一嗓子，谁爱听谁听，我不等回复"**
> **服务 = "我拨号，对方接，我问一句他答一句，我等着"**

### 2.3 服务类型（`.srv` 文件）长什么样

```
int64 a          ← 请求 Request
int64 b
---
int64 sum        ← 响应 Response
```

中间那条 `---` 把请求和响应切开。**上面几行属于 Request，下面几行属于 Response。**

查看任意服务类型的定义：

```bash
ros2 interface show example_interfaces/srv/AddTwoInts
```

### 2.4 服务端 vs 客户端 ⭐ 最容易搞混的一张表

|  | **服务端 Server** | **客户端 Client** |
|---|---|---|
| 创建函数 | `create_service` | `create_client` |
| 参数个数 | **3 个**（类型、名字、回调） | **2 个**（类型、名字，**没有回调**） |
| 谁主动 | 被动，**等着被调用** | **主动**发起请求 |
| 代码何时执行 | 请求到达时，**executor 替你调回调** | 你在 `main()` 里自己一行行写 |
| 需要写类吗 | ✅ 习惯上要（要存 service 对象） | ❌ **可以不写**，直接 `Node('名字')` |
| 需要定时器吗 | ❌ 不需要 | ❌ 不需要 |

> 💡 **为什么客户端可以不写类？**
> 因为服务端要长期"挂着"提供服务，得把 `self.srv` 存起来；而客户端做的事在 `main()` 里从头走到尾就结束了，不需要保存状态。
> （第 1 关的发布者/订阅者都活在 `spin` 循环里，所以都要写类。）

### 2.5 `request` 和 `response` 是"盒子"，不是"值" ⭐

这是本关**最容易出错**的概念。

```
response                    ← 整个响应【对象】（一个盒子）
response.sum                ← 盒子里 sum 这个【字段的值】（一个数）
```

打印一个盒子的样子（以有三个字段的 `Point` 为例）：

```python
p = Point(); p.x = 1.0; p.y = 2.0; p.z = 3.0

f'{p}'      →  geometry_msgs.msg.Point(x=1.0, y=2.0, z=3.0)   # 整个盒子
f'{p.x}'    →  1.0                                             # 盒子里的一格
```

**为什么打印盒子会出来那一长串？** Python 打印对象时会去问它"你是什么"，ROS 2 给消息类写的自我介绍是「我是 `<类型名>` 类型的盒子，里面装着：`字段=值, ...`」。

两条铁律：

> **要交给 rclpy 的，永远是整个 `response` 对象。**（服务端 `return response`）
> **要读出来给用户看的，永远是 `response.xxx` 这个字段。**（客户端 `f'{response.sum}'`）

### 2.6 回调依然是 executor 调用的

和第 1 关一模一样：

```
executor 在 rclpy.spin(node) 循环里干等
        ↓ 请求到达（这是一个"事件"）
executor 被唤醒 → 由它调用 handle_add(request, response)
        ↓
拿到你 return 的 response → 打包发回客户端
        ↓
回去继续等下一个事件
```

⚠️ **服务端闲着的时候，`handle_add` 根本没在运行。** 它是个函数，没人调用它就不存在——没有栈帧、没有变量、什么都没发生。真正在跑的是 `rclpy.spin(node)` 里的 **executor**。

---

## 3. 完整代码

### 3.1 `add_server.py` —— 服务端

```python
import rclpy
from rclpy.node import Node
from example_interfaces.srv import AddTwoInts      # 服务类型


class AddServer(Node):

    def __init__(self):
        super().__init__('add_server')             # 节点名
        # 创建服务：(服务类型, 服务名, 收到请求时的回调函数)
        self.srv = self.create_service(AddTwoInts, 'add_two_ints', self.handle_add)
        self.get_logger().info('加法服务已启动')

    def handle_add(self, request, response):
        response.sum = request.a + request.b       # 往盒子里填数
        return response                            # 把整个盒子交回去


def main(args=None):
    rclpy.init(args=args)
    node = AddServer()
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

**回调的契约**：rclpy 递给你一个**空的 response 盒子**，你负责填字段，然后**原样交还**。

⚠️ `return response.sum` 是错的（交了里面的数，没交盒子），会直接抛 `TypeError` 把服务端打崩。

### 3.2 `add_client.py` —— 客户端

```python
import rclpy
from rclpy.node import Node
from example_interfaces.srv import AddTwoInts


def main(args=None):
    rclpy.init(args=args)
    node = Node('add_client')          # 不用写类，直接拿 Node 用

    # ① 创建客户端（类型、服务名）
    client = node.create_client(AddTwoInts, 'add_two_ints')

    # ② 等服务端上线。返回 True/False，不是异常
    if not client.wait_for_service(timeout_sec=1.0):
        node.get_logger().error('没找到 add_two_ints 服务，服务端开了吗？')
        node.destroy_node()
        rclpy.shutdown()
        return

    # ③ 造请求。服务端的盒子是 rclpy 给的，客户端的盒子得自己造
    request = AddTwoInts.Request()
    request.a = 3
    request.b = 4

    # ④ 异步发送，接住 future（一张"凭此条取结果"的凭证）
    future = client.call_async(request)

    # ⑤ spin 这个节点，直到 future 有结果
    rclpy.spin_until_future_complete(node, future)

    # ⑥ 从 future 取出响应，读字段
    response = future.result()
    node.get_logger().info(f'{request.a} + {request.b} = {response.sum}')

    node.destroy_node()
    rclpy.shutdown()


if __name__ == '__main__':
    main()
```

**注意客户端里没有的东西**：没有类、没有 `self`、没有回调、没有定时器。就是一条直线：**建 client → 等 → 造请求 → 发 → 等结果 → 读 → 退出**。

### 3.3 什么是 `future`

`call_async` 是**异步**的：发出去立刻返回，**过一会儿**结果才回来。

`future` 就是那张「凭此条取结果」的凭证：

```python
future = client.call_async(request)          # 立刻返回，此时还没有结果
# ...一段时间过去...
response = future.result()                   # 兑现凭证，拿到 Response
```

`rclpy.spin_until_future_complete(node, future)` 就是"坐在这儿等到凭证兑现为止"——它是 `rclpy.spin` 的**带终止条件版本**。

### 3.4 配置：`setup.py` 与 `package.xml`

```python
# setup.py
    entry_points={
        'console_scripts': [
            'hello_node  = hello_ros.hello_node:main',
            'talker      = hello_ros.talker:main',
            'listener    = hello_ros.listener:main',
            'add_server  = hello_ros.add_server:main',
            'add_client  = hello_ros.add_client:main',
            #  ↑终端名         ↑包名.文件名:函数名
        ],
    },
```

```xml
<!-- package.xml -->
  <depend>rclpy</depend>
  <depend>std_msgs</depend>
  <depend>example_interfaces</depend>
```

**`<depend>` 还是 `<test_depend>`？** 判据只有一个问题：**这个包在哪个阶段被需要？**

| 阶段 | 标签 |
|---|---|
| 构建/编译时需要 | `<build_depend>` |
| **程序跑起来**时需要 | `<exec_depend>` |
| **只有**跑 `colcon test` 时需要 | `<test_depend>` |
| 前两个都要（= 平时就要） | **`<depend>`** |

`add_server.py` 跑起来要 `import AddTwoInts`，所以是运行期依赖 → `<depend>`。

> 📌 **每 `import` 一个新包，加一行 `<depend>`。**
> 短期内不痛（ROS 自带的包不声明也能 import 成功），但三个地方会痛：
> ① `rosdep install` 靠它装依赖；② **colcon 靠它排构建顺序**（第 6 关自己写接口包时，漏了这行会先构建你的包、后构建接口包，直接编不过）；③ 打包发布。

---

## 4. API 速查表

```python
from example_interfaces.srv import AddTwoInts

# ---------- 服务端 ----------
self.create_service(类型, '服务名', 回调函数)

def 回调(self, request, response):
    response.字段 = ...          # 往盒子里填
    return response              # ← 必须交还整个盒子！

# ---------- 客户端 ----------
node.create_client(类型, '服务名')             # → 客户端

client.wait_for_service(timeout_sec=1.0)      # → True / False（服务端在不在）

request = AddTwoInts.Request()                # 自己造盒子
request.a = 3                                 # 自己填字段

future = client.call_async(request)           # 异步发送，→ future 凭证

rclpy.spin_until_future_complete(node, future)                      # 一直等
rclpy.spin_until_future_complete(node, future, timeout_sec=5.0)     # 最多等 5 秒

response = future.result()                    # 兑现凭证 → Response 对象
future.done()                                 # → True/False，凭证兑现了吗

# ---------- 日志 ----------
self.get_logger().info('文字')
self.get_logger().error('文字')
```

---

## 5. 命令行工具速查

| 命令 | 作用 |
|---|---|
| `ros2 service list` | 列出所有服务 |
| `ros2 service list -t` | 列出服务**并显示类型** |
| `ros2 service type <服务名>` | 查某个服务的类型 |
| `ros2 service call <服务名> <类型> "{字段: 值}"` | **以客户端身份调用服务** |
| `ros2 interface show <服务类型>` | 查看 `.srv` 的请求/响应字段 |
| `ros2 node list` | 列出节点（**默认不显示隐藏节点**） |
| `ros2 node list -a` | 列出节点**包括隐藏节点** |
| `ros2 service list --include-hidden-services` | 列出服务包括隐藏服务 |

> ⚠️ **`-a` 是 `ros2 node list` 的开关，`ros2 service list` 没有 `-a`。** 后者对应的叫 `--include-hidden-services`。同一个「隐藏」概念，两个命令的开关名不一样。

`ros2 service call` 例子：

```bash
ros2 service call /add_two_ints example_interfaces/srv/AddTwoInts "{a: 3, b: 4}"
```

⚠️ **类型参数不能省。** 只写 `ros2 service call /add_two_ints` 会报：

```
error: the following arguments are required: service_type
```

因为 CLI 得**亲手拼出一个 `AddTwoInts_Request(a=3, b=4)` 对象**才能发出去。

---

## 6. 构建与运行流程

### 每次改完代码的固定动作

```bash
cd ~/ros2_learn_ws
colcon build --packages-select hello_ros --symlink-install
source install/setup.bash
```

### `--symlink-install` 是什么

让 `install/` 里放**软链接**指回 `src/`，而不是复制品。好处：**只改 `.py` 文件内容时，不用重新 build，直接生效。**

⚠️ **边界**：只有 `.py` **内容**改动才免 build。

| 改了什么 | 要不要重新 build |
|---|---|
| `.py` 里的代码 | ❌ 不用（用了 `--symlink-install`） |
| `setup.py`（加可执行文件） | ✅ **必须** |
| `package.xml`（加依赖） | ✅ **必须** |

因为后两者改的是「**装什么**」，不是「装的内容」。

### 运行（需要两个终端）

```bash
# 终端 A —— 服务端
ros2 run hello_ros add_server

# 终端 B —— 客户端
ros2 run hello_ros add_client
```

### 验收清单

**验收 A（正常路径）**

| 命令 | 期望 |
|---|---|
| 终端 A：`ros2 run hello_ros add_server` | 打印 `加法服务已启动` |
| 终端 B：`ros2 node list` | 出现 `/add_server` |
| 终端 B：`ros2 service list -t \| grep add` | `/add_two_ints [example_interfaces/srv/AddTwoInts]` |
| 终端 B：`ros2 service call /add_two_ints example_interfaces/srv/AddTwoInts "{a: 3, b: 4}"` | `response: example_interfaces.srv.AddTwoInts_Response(sum=7)` |
| 终端 B：`ros2 run hello_ros add_client` | `3 + 4 = 7` |

**验收 B（服务端不在）**

把服务端 `Ctrl+C` 掉，再跑 `add_client`：

```
[ERROR] [1789121168.531328472] [add_client]: 没找到 add_two_ints 服务，服务端开了吗？
```

打出错误 → **干净退出** → 回到提示符。**不是**一堆 traceback，**不是**卡住。

### 环境变量提醒 ⚠️

每个**新开的终端**都需要：

```bash
source /opt/ros/lyrical/setup.bash          # ROS 本体（.bashrc 已自动加载）
source ~/ros2_learn_ws/install/setup.bash   # 你的工作区（需手动 source）
```

忘了第二条 → `Package 'hello_ros' not found`。

---

## 7. 实测现象与结论 ⭐

> 这一节是**复习重点**，都是动手跑出来的结论，不是理论。

### 7.1 CLI 工具也是节点 ✅ 补上第 1 关的旧账

第 1 关遗留了一个问题：**`ros2 topic echo` 算不算节点？**（实测订阅数 +1，说明它算）

那为什么在 `ros2 node list` 里从来没见过它？

**因为它被藏起来了。** 让 `ros2 service call` 卡在 `waiting for service...` 的时候，在另一个终端：

```
$ ros2 node list
（空）

$ ros2 node list -c
0

$ ros2 node list -a
/_ros2cli_daemon_0_1f0c1d52318748e1b537dabbd814dbd8
/_ros2cli_requester_example_interfaces_AddTwoInts

$ ros2 node list -a -c
2
```

**默认 0 个，加 `-a` 是 2 个。它一直都在。**

### 7.2 隐藏节点规则 ⭐

**节点名以 `_` 开头 = 隐藏节点**，`ros2 node list` 默认不列。ROS 2 官方工具的节点全都起这种名字，就是为了不刷屏。

```
_ros2cli_requester_example_interfaces_AddTwoInts
└──┬───┘ └───┬──┘ └──────────┬─────────────┘
隐藏前缀  ros2cli 工具     你是谁、在求什么
```

**结论**：`ros2 service call` 是**客户端节点**，名字里写得很清楚——`requester`（请求方）。

> 📌 同理，`ros2 topic echo` 是个**订阅者节点**，它是 `_ros2cli_...`，只是默认隐藏了。
> 第 1 关"以为 CLI 不是节点"的错，根源就在这里。

### 7.3 每个节点自带一堆参数服务

跑 `ros2 service list -t`，除了自己写的服务，还会多出这些：

```
/add_two_ints                                  [example_interfaces/srv/AddTwoInts]   ← 自己写的
/add_two_ints_server/describe_parameters       [rcl_interfaces/srv/DescribeParameters]
/add_two_ints_server/get_parameter_types       [rcl_interfaces/srv/GetParameterTypes]
/add_two_ints_server/get_parameters            [rcl_interfaces/srv/GetParameters]
/add_two_ints_server/get_type_description      [type_description_interfaces/srv/GetTypeDescription]
/add_two_ints_server/list_parameters           [rcl_interfaces/srv/ListParameters]
/add_two_ints_server/set_parameters            [rcl_interfaces/srv/SetParameters]
/add_two_ints_server/set_parameters_atomically [rcl_interfaces/srv/SetParametersAtomically]
```

**这 7 个不是程序里写的**，是节点一出生就自带的**参数服务**（第 3 关的内容）。

注意命名差别，这是**两种**产生服务的方式：

| 服务名 | 谁起的 |
|---|---|
| `/add_two_ints` | 程序在 `create_service` 里写的，**不带节点名前缀** |
| `/add_two_ints_server/...` | rclpy 自动生成的，**带节点名前缀** |

### 7.4 客户端必须等目标存在

敲下 `ros2 service call` 的瞬间，如果服务端还没被发现，会先看到：

```
waiting for service to become available...
```

**这是服务跟话题的根本分野**——**客户端必须等目标存在**。

| | 目标不在时会怎样 |
|---|---|
| 话题发布者 | **完全不管**，照发不误（没有订阅者也无所谓） |
| 服务客户端 | **停下来等**，等到为止 / 等到超时 |

### 7.5 ⭐「服务端不在」有**两种**，一种能查，一种查不了

**这是本关最值钱的一条结论。**

| 场景 | 检查时机 | 结果 |
|---|---|---|
| 服务端**压根没起**，`wait_for_service` 返回 False | 发请求**之前**检查 | ✅ 能检测，干净报错退出 |
| 服务端**在**，请求送达**之后它才崩** | 请求已在路上 | ❌ **客户端永远等，没有任何提示** |

**实测**（两个独立进程，服务端回调里 `return None`）：

```
服务端：TypeError → 崩掉（一堆 traceback）
客户端：wait_for_service: True
        请求已发出，开始 spin_until_future_complete（无 timeout）...
        （然后，永远的沉默，直到被强杀）
```

**为什么？** DDS 没有「服务端死了」这种通知。客户端只知道"我还在等响应"，它**分不清**这三种情况：

- 服务端正在慢慢算
- 服务端已经崩了
- 服务端从来就没收到我的请求

**这三种在客户端眼里长得一模一样。**

**所以 timeout 不是可有可无的**：

```python
rclpy.spin_until_future_complete(node, future)                    # 天荒地老
rclpy.spin_until_future_complete(node, future, timeout_sec=5.0)   # 最多等 5 秒
```

**生产代码永远要设 timeout。**

对比第 1 关：话题那边发布者死了，订阅者**毫无感觉**（只是不再收到消息，也不报错）。服务这个坑更狠——订阅者至少不会"卡住"，客户端会**死等**。

### 7.6 服务回调是**串行**的 ⭐

**两个客户端同时调用，`handle_add` 会同时跑两遍吗？—— 不会。**

实测：服务端回调里 `sleep(2)`，两个客户端同时发请求：

```
>>> 开始处理 a=1  t=998.939
<<< 处理完毕 a=1  t=1000.945      ← 处理了 2 秒
>>> 开始处理 a=2  t=1000.946      ← 紧接着【才】开始，不是同时
<<< 处理完毕 a=2  t=1002.946
```

a=2 的开始时间 `1000.946` 和 a=1 的结束时间 `1000.945` 只差 **1 毫秒**——a=2 一直在门外站着。

**原因**：`rclpy.spin(node)` 默认用 **SingleThreadedExecutor**（源码 `rclpy/__init__.py`：`__executor = SingleThreadedExecutor()`）。**单线程**，回调**排队一个一个跑**。

想要并发，得换 `MultiThreadedExecutor` + 可重入的 callback group——那是进阶内容。

> ⚠️ 注意区分两件事：**请求数据彼此独立 ≠ 回调并发执行**。调度怎么走由 **executor** 决定，不由数据决定。

### 7.7 同名服务的坑

两个同名服务端同时开着，**请求被谁接走是不确定的**。

而且它还有个更阴险的后果：**它会让你的测试"假成功"**。

真实经历：`setup.py` 里的 `add_server` 根本没写对、代码也没跑起来，但 `ros2 service list` 里就是有 `/add_two_ints`——因为**之前那个 demo 服务端**（`ros2 run demo_nodes_py add_two_ints_server`）一直没关，它用的也是这个名字。CLI 调用返回 `sum=7`，看起来"通了"，其实跟自己写的代码一点关系都没有。

> 📌 **每轮测试前先确认场上干净**：`ros2 service list | grep add` 应该是空的。
> 唯一能区分"是不是我的服务端在跑"的证据是 **`ros2 node list` 里的 `/add_server`**。

### 7.8 进程残留会污染环境

跑久了会在 `/dev/shm` 留下 Fast DDS 的共享内存文件。一个僵尸服务端如果占着 `fastdds_port7000`，之后每个新起的 ROS 进程都会撞一次：

```
[RTPS_TRANSPORT_SHM Error] Failed init_port fastdds_port7000: open_and_lock_file failed
```

**这条报错本身是噪声**（Fast DDS 会退回走网络，通信照常），但它**暴露了"你以为关了、其实没关"**。

查出是谁占着：

```bash
fuser -v /dev/shm/fastdds_port7000_el
```

端口号会随新进程递增（7000 → 7001 → 7002 …），**每次撞一次、换一个**——这就是"报错一直出现"的真相：不是它阴魂不散，是每次都是新的进程在撞同一堵墙。

清理：

```bash
pkill -f "hello_ros add_server"
fuser -v /dev/shm/fastdds_port7000_el      # 确认空了
# 实在清不掉（没有 ROS 进程在跑时）：
ros2 daemon stop
rm -f /dev/shm/fastdds_* /dev/shm/sem.fastdds_*
```

---

## 8. 踩坑记录

本关实际踩过的坑，按发生顺序：

| # | 坑 | 报错 / 现象 | 正解 |
|---|---|---|---|
| 1 | 服务端回调 `return response.sum` | `TypeError`（`rclpy/service.py` 抛出），**服务端整个崩掉** | 要交出**整个盒子**：`return response` |
| 2 | 客户端 `a=3` / `b=4` 没写进 request | **完全不报错**，静默算出 `sum=0` | `request.a = 3` / `request.b = 4` |
| 3 | 客户端 `{response}` 缺 `f` 前缀 | `TypeError: unhashable type` | `f'...'`，ROS 消息对象**不可哈希** |
| 4 | 客户端 `f'{response}'` 打了整个盒子 | 输出 `3 + 4 = AddTwoInts_Response(sum=7)` | 要取**字段**：`f'{response.sum}'` |
| 5 | 客户端 `info(...)` 里的 `...` 没填 | `TypeError: rclpy_logging_rcutils_log(): incompatible function arguments` | `...` 是骨架的**填空位**，不是代码；要填字符串 |
| 6 | 改了 `setup.py` 没重新 build | `ros2 run` 报 `No executable found` | 改 `setup.py` / `package.xml` **必须重新 build** |
| 7 | 改了 `.py` 没重新 build | 行为没变，还报旧的错 | Python 包**也要 build**（或用 `--symlink-install`） |
| 8 | demo 服务端没关就写自己的 | 服务名撞车，测试"假成功" | 测试前 `ros2 service list \| grep add` 确认为空 |
| 9 | 残留的僵尸服务端 | 共享内存端口报错 + 请求被谁接走不确定 | `pkill -f "hello_ros add_server"` |
| 10 | `ros2 service list -a` | `unrecognized arguments: -a` | `-a` 是 `node list` 的；service list 用 `--include-hidden-services` |
| 11 | 把 `ros2 service call` 当成服务端 | 概念错误，猜了三轮 | 它是**客户端**节点，名字里写着 `requester` |
| 12 | `rclpy.spin_until_future_complete` 没设 timeout | 服务端崩了客户端**永远死等** | 加 `timeout_sec=`，配合 `future.done()` |
| 13 | 凭直觉答实验题 | 答错了 | **先跑，再答** ⭐ |

### ⚠️ 三个跨关存在的通用教训

**① 报错要分级**

| 类别 | 处理方式 | 本关例子 |
|---|---|---|
| **影响了结果** | **必须处理** | `No executable found`、`waiting for service...`、`TypeError` |
| **只是吵** | 记下来，可以先不管 | `[RTPS_TRANSPORT_SHM Error]` |

**② 「不报错的 bug」比报错的难抓十倍**

`a=3` / `b=4` 没写进 request —— 语法合法、跑得飞起、就是不报错，答案默默变成 0。

遇到这种坑时别去找报错，要去找**证据**：把中间值打印出来看。

**③ `src/` 和 `install/` 是两份东西**

```
~/ros2_learn_ws/src/...      ← 你写代码的地方
        │  colcon build（复制/软链过去）
        ▼
~/ros2_learn_ws/install/...  ← ros2 run 实际跑的是这里
```

**`ros2 run` 从来不跑你 `src/` 里的代码。**

看 traceback 时，**最上面那一行往往就告诉你在跑哪个文件**：

```
File "/home/l/ros2_learn_ws/install/hello_ros/lib/python3.14/site-packages/hello_ros/add_server.py"
```

**读 traceback 的方法：从下往上。** 最下面一行是错什么，往上几行是错在哪，**最上面一行是"你运行的是哪个文件"**。

---

## 9. 自测题（附答案）

> 复习时**先遮住答案自己答一遍**，答不出来再翻回去对应章节。

### 题 1：服务端回调里 `return response.sum` 会怎样？

<details>
<summary>点开答案</summary>

**服务端整个崩掉**，报 `TypeError`：

```
File "rclpy/service.py", line 80, in _send_response
    raise TypeError()
TypeError
```

**原因**：rclpy 拿你 `return` 的东西去**打包成网络消息**。它要的是 `AddTwoInts_Response` 类型的**盒子**（它得按格式给每个字段编码），你给了个 `int`，它不知道怎么打包。

正解：`return response`。

</details>

### 题 2：为什么服务不能像话题那样"发了就完事"？

<details>
<summary>点开答案</summary>

因为**服务的用途就是"要一个答案"**。

- **话题**：发布者**压根不需要结果**，所以推完就走
- **服务**：客户端要的就是那个响应，**没有响应等于什么都没有**

所以「等」是**双向**的：**服务端等请求，客户端等响应**。

（另外服务有"必须回应"的语义要求：话题丢一条消息没人知道，服务丢了响应客户端会一直等。）

</details>

### 题 3：服务端没被调用的时候，你的 `handle_add` 在干嘛？

<details>
<summary>点开答案</summary>

**它根本没在运行。** 它是个**函数**，没人调用它就不存在——没有栈帧、没有变量、什么都没发生。

真正在跑的是 `rclpy.spin(node)` 里的 **executor**，它在**等事件**。

完整链条：

```
executor 在 spin 循环里干等
        ↓ 请求到达（一个"事件"）
executor 被唤醒 → 由它调用 handle_add(request, response)
        ↓
拿到你 return 的 response → 打包发回客户端
        ↓
回去继续等下一个事件
```

**你从头到尾没有"调用"过 `handle_add`。**（和第 1 关订阅者的回调是同一个机制）

</details>

### 题 4：两个终端同时 `ros2 service call`，`handle_add` 会同时跑两遍吗？

<details>
<summary>点开答案</summary>

**不会，是排队的。**

实测（服务端回调里 sleep 2 秒）：

```
>>> 开始处理 a=1  t=998.939
<<< 处理完毕 a=1  t=1000.945
>>> 开始处理 a=2  t=1000.946      ← 紧接着才开始
<<< 处理完毕 a=2  t=1002.946
```

**原因**：`rclpy.spin(node)` 默认用 **SingleThreadedExecutor**，单线程，回调排队一个一个跑。

想并发：换 `MultiThreadedExecutor` + 可重入 callback group。

⚠️ 「请求相互独立」说的是**数据**，跟**回调能不能同时执行**是两码事——调度由 executor 决定。

</details>

### 题 5：用话题做加法行不行？会多出哪些麻烦？

<details>
<summary>点开答案</summary>

**能做，但等于从头手搓一个服务。** 麻烦一箩筐：

1. **配对问题（最要命）**：两个客户端同时问 `3+4` 和 `5+6`，回来两条 `sum`，**你怎么知道哪条是回答谁的**？→ 只能自己在消息里塞一个 id 字段
2. **会丢消息**：默认 QoS 是 volatile，订阅者晚起、处理慢了就丢 → 客户端永远等不到
3. **没有回执**：不知道服务端收没收到
4. **没有超时语义**：只能自己拿定时器兜底
5. 得开**两个话题**（一个收请求、一个发结果）

**服务类型就是为「一问一答」这个场景造出来的。**

</details>

### 题 6：`ros2 service call` 在 ROS 2 眼里是什么身份？

<details>
<summary>点开答案</summary>

**是个客户端节点。**

证据一：卡在 `waiting for service...` 时，`ros2 node list -a` 会揪出它：

```
/_ros2cli_requester_example_interfaces_AddTwoInts
└──┬───┘ └───┬──┘
隐藏前缀  requester = 请求方
```

证据二：它自己打印 `requester: making request: example_interfaces.srv.AddTwoInts_Request(a=3, b=4)`——它得**亲手造 Request 对象**才能发（这也是为什么类型参数不能省）。

**顺便**：它名字以 `_` 开头，是**隐藏节点**，所以 `ros2 node list` 默认看不到它（要加 `-a`）。第 1 关的 `ros2 topic echo` 同理。

</details>

### 题 7：「服务端不在」有哪两种？客户端分别是什么反应？

<details>
<summary>点开答案</summary>

| 场景 | 检查时机 | 客户端反应 |
|---|---|---|
| 服务端**压根没起** | 发请求**之前**（`wait_for_service`） | ✅ 返回 `False`，能干净报错退出 |
| 服务端**在**，请求送达后才崩 | 请求已在路上 | ❌ **永远等，没有任何提示** |

**为什么第二种检测不了？** DDS 没有「服务端死了」这种通知。客户端分不清：

- 服务端正在慢慢算
- 服务端已经崩了
- 服务端从来就没收到我的请求

**这三种在客户端眼里一模一样。**

**所以 `spin_until_future_complete` 必须设 `timeout_sec`。**

</details>

### 题 8：`response` 和 `response.sum` 有什么区别？

<details>
<summary>点开答案</summary>

- `response` —— 整个**响应对象**（一个盒子），类型是 `AddTwoInts_Response`
- `response.sum` —— 盒子里 `sum` 这个**字段的值**，类型是 `int`

```python
f'{response}'       →  example_interfaces.srv.AddTwoInts_Response(sum=7)   # 盒子
f'{response.sum}'   →  7                                                    # 里面的数
```

**两条铁律**：

- **要交给 rclpy 的，永远是整个 `response` 对象**（服务端 `return response`）
- **要读出来给用户看的，永远是 `response.xxx` 字段**（客户端 `f'{response.sum}'`）

</details>

### 题 9：`ros2 node list` 里为什么看不到 `ros2 topic echo` / `ros2 service call`？

<details>
<summary>点开答案</summary>

**因为它们都是隐藏节点**——节点名以 `_` 开头。

```
/_ros2cli_requester_example_interfaces_AddTwoInts
```

`ros2 node list` **默认不列隐藏节点**，要加 `-a`：

```bash
ros2 node list -a
```

（服务同理：`ros2 service list --include-hidden-services`。注意 `service list` 用的是长开关，没有 `-a`。）

**这解决了第 1 关的一个悬案**：`ros2 topic echo` 实测会让订阅数 +1（说明它是节点），但 `ros2 node list` 里找不到它——因为它藏起来了。

</details>

### 题 10：改了代码但行为没变，先检查什么？

<details>
<summary>点开答案</summary>

**先看 `src/` 和 `install/` 的差距。**

```
src/...      ← 你写代码的地方
install/...  ← ros2 run 实际跑的是这里
```

最快的自查方式：

```bash
# 方法一：看两份文件的时间戳
ls -la src/hello_ros/hello_ros/xxx.py
ls -la install/hello_ros/lib/python3.14/site-packages/hello_ros/xxx.py

# 方法二：看 traceback 最上面一行的路径（它写着实际在跑哪个文件）
```

**改了什么 → 要不要 build**：

| 改了什么 | 要不要 build |
|---|---|
| `.py` 内容 | ❌ 不用（用了 `--symlink-install`） |
| `setup.py` / `package.xml` | ✅ **必须** |

</details>

---

## 附：本关命令速记卡

```bash
# 构建
cd ~/ros2_learn_ws
colcon build --packages-select hello_ros --symlink-install
source install/setup.bash

# 运行
ros2 run hello_ros add_server      # 终端 A
ros2 run hello_ros add_client      # 终端 B

# 观察 / 验收
ros2 node list
ros2 node list -a                                  # 包括隐藏节点
ros2 service list -t
ros2 service list -t | grep add                    # 测试前确认场上干净
ros2 service type /add_two_ints
ros2 interface show example_interfaces/srv/AddTwoInts
ros2 service call /add_two_ints example_interfaces/srv/AddTwoInts "{a: 3, b: 4}"

# 排查残留
fuser -v /dev/shm/fastdds_port7000_el
pkill -f "hello_ros add_server"
```

---

**下一关预告 · 参数 Parameter**

> 第 1 关你写死了队列长度 `10`，第 2 关你写死了服务名 `add_two_ints`。
> 参数就是**运行时才决定**的那些配置——**不改代码、不重新编译，程序跑着就能调**。
>
> 还记得本关 [7.3](#73-每个节点自带一堆参数服务) 里那 7 个 `/add_two_ints_server/*_parameters` 吗？
> 那就是 rclpy 给每个节点白送的参数服务，第 3 关就是它们。
