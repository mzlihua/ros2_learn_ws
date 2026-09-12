# 第 3 关 · 参数 Parameter

> ROS 2 核心基础 · 课程笔记
> 学习日期：2026-09-12
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

**学会给节点装一组"不改代码、不重新编译，跑着就能调"的配置。**

前两关你把东西**写死**在代码里：第 1 关写死队列长度 `10`，第 2 关写死服务名 `add_two_ints`。参数就是把这些"死"的东西变成"活"的。

产出一个可执行节点：

| 文件 | 作用 |
|---|---|
| `param_talker.py` | 一个"可调"的发布者：发什么、发多快、发几条，全都能从外面改 |

三个参数：

| 参数名 | 类型 | 默认值 | 作用 |
|---|---|---|---|
| `message` | string | `'hello'` | 发布的内容 |
| `period` | double | `1.0` | 每隔几秒发一次 |
| `max_count` | int | `0` | 发满几条就停（`0` = 不限） |

外加一条**校验规则**：`period` 不允许小于 `0.1` 秒。

---

## 2. 核心概念

### 2.1 一句话理解参数

> **参数 = 挂在一个节点身上的 key-value 配置。**

它和话题、服务不是一类东西：

|  | **话题 Topic** | **服务 Service** | **参数 Parameter** |
|---|---|---|---|
| 是什么 | 数据流 | 一次调用 | **节点的配置** |
| 方向 | 广播、单向 | 一问一答 | 外部工具来读 / 来写 |
| 变更频率 | 每毫秒 | 每次调用 | **偶尔改一次** |
| 典型用途 | 传感器数据 | 触发一次计算 | 频率、阈值、名字 |
| 需要校验吗 | 不用 | 不用 | **必须**（配置写错要出事） |

关键差别：**参数存的是"配置"，不是"数据流"**——所以它量小、不频繁、**天生需要校验**。

### 2.2 参数是"每个节点私有"的

一个参数的**全名**长这样：

```
/param_talker.message
└─────┬─────┘ └──┬──┘
   节点名      参数名
```

**A 节点的参数，B 节点看不见。** 两个节点可以各有一个叫 `message` 的参数，互不干扰。

> ⚠️ 所以 `ros2 param set` 必须写**节点名 + 参数名**两段：
> `ros2 param set /param_talker message 世界`

### 2.3 ⭐ `declare` 是"注册"，`get` 是"读取"

**本关第一个大坑，也是最容易反复栽的一个。**

| 函数 | 干的事 | 能调用几次 | 什么时候用 |
|---|---|---|---|
| `declare_parameter(名字, 默认值)` | **注册**：告诉节点"我有这么个参数" | **一辈子一次** | `__init__` 里 |
| `get_parameter(名字).value` | **读取**：把当前的**值**拿出来 | 想读几次读几次 | 任何地方 |

> 口诀：**`__init__` 里签合同，别的地方查余额。**

**反复注册会怎样？** 源码 `rclpy/node.py` 第 506 行：

```python
raise ParameterAlreadyDeclaredException(parameters_already_declared)
```

直接抛异常。

**`get_parameter()` 返回的不是值，是个"盒子"：**

```python
self.get_parameter('message')          →  Parameter 对象（盒子）
self.get_parameter('message').value    →  'hello'      （盒子里的值）← 要这个
```

打印盒子会出来 `<rclpy.parameter.Parameter object at 0x...>`。**少了 `.value` 就是这样。**

### 2.4 三种改参数的方式

| 方式 | 语法 | 生效时机 |
|---|---|---|
| ① 启动时命令行覆盖 | `ros2 run hello_ros param_talker --ros-args -p message:=你好` | 节点启动前 |
| ② 运行时改 | `ros2 param set /param_talker message 世界` | 立刻 |
| ③ 一次改多个 | `ros2 param load /param_talker params.yaml` | 立刻 |

> ⚠️ 参数的赋值符是 **`:=`** 不是 `=`。
> ⚠️ ① **不经过校验回调**（见 [7.3](#73--启动时的--p-覆盖不走校验回调-)）。

### 2.5 ⭐⭐ 参数改了，谁会自动跟上？

**本关的核心问题。** 答案取决于你是"怎么用"这个参数的：

| 写法 | 参数改了会怎样 | 例子 |
|---|---|---|
| **每次用的时候现读** | ✅ **自动生效** | `tick` 里的 `self.get_parameter('message').value` |
| **建的时候读一次，之后一直用那个副本** | ❌ **永远不生效** | `create_timer(周期, ...)` 里的那个周期 |

**为什么定时器不会自动跟上？**

`self.create_timer(1.0, self.tick)` 执行的那一瞬间，周期就被**焊死**在里面了。定时器不是每一拍都去问参数"我现在该多久响一次"——你在创建时就把 `1.0` 这个**数字**交出去了，它跟 `period` 从此**没有联系**。

用一个比喻：

> 你告诉闹钟"每小时响一次"。现在想改成 10 分钟——你没法对着闹钟喊一声"改 10 分钟"。**你得把这个闹钟拆了，换个新的、设成 10 分钟。**

所以：

```python
# 改 period 之后，必须做这两步
self.destroy_timer(self.timer)
self.timer = self.create_timer(新周期, self.tick)
```

**这不是你想复杂了，是机制就是这样**——`message` 和 `period` 两边处理方式不同，是因为它们的"用法"不同。

### 2.6 ⭐ 校验回调：框架在"改之前"问你

给节点注册一个函数，**任何参数要被修改时**，框架都先来问你：

```python
self.add_on_set_parameters_callback(self.on_param_set)
```

⚠️ 传的是**函数对象**（`self.on_param_set`），**不要加括号**。

#### 框架什么时候叫你？——**在参数真正被改掉之前**

源码 `rclpy/node.py` 的顺序：

```
1. 先调用你的回调        ←── 你在这里。此刻参数【还是旧值】
2. 回调返回 successful=True
3. 框架才把新值写进参数里
```

**由此得到两条关键结论：**

| 你想拿 | 从哪拿 |
|---|---|
| **新值**（想改成多少） | 遍历 `params` 里那个 `p.value` |
| **旧值**（现在是多少） | `self.get_parameter('period').value` ← 此刻还没变 |

**不用自己存"旧值"变量**——框架已经替你保管好了，随时能读。

#### 框架"问"的时候，什么都不挑

这几种情况，回调**一律都会被叫**：

| 情况 | 回调被叫吗 |
|---|---|
| 改 `period` | ✅ |
| 改 `period`，但**值没变** | ✅ **照样叫** |
| 改 `message`（跟 `period` 无关） | ✅ **照样叫** |
| `param load` 一次送五个参数 | ✅ 叫**一次**，一次收到五个 |

**框架不会替你判断"这次改动有没有意义"**——它不比较新旧值，也不管你关不关心。这个判断是你自己的活：

```python
for p in params:
    if p.name == 'period':          # ← 过滤"改的不是 period"
        ...
```

#### ⚠️ 每条出口都必须 `return SetParametersResult`

**回调函数每一条可能的路径，都得交出一个 `SetParametersResult`。**

漏了会怎样？函数走到末尾没 `return` → Python 隐式返回 `None` → 框架不认：

```
UserWarning: Callback returned an invalid type, it should return SetParameterResult.
```

然后框架**强行判成失败**（`successful=False`）——**参数改不成**。

**所以结构必须是：**

```python
for p in params:
    ...
    # 拒绝的路径在这里 return（带 reason）
    ...

return SetParametersResult(successful=True)    # ← 循环【外面】，兜底放行
```

> **规则**：`for` 里负责**逐条检查**，循环外负责**统一放行**。
> 检查完**所有**参数，才敢说"都没问题"。

⚠️ 兜底 `return` 写在循环**里面**是错的——一次送多个参数时，第一轮就返回了，**后面的参数一个都不会被检查**。

#### 返回 `reason` 要写人话

```python
SetParametersResult(successful=False, reason='...')                      # ❌
SetParametersResult(successful=False, reason='period 不能小于 0.1 秒')     # ✅
```

**`reason` 是打给使用者看的**，不是给电脑看的。要告诉用户**正确的范围是什么**，不能只说"你错了"。

### 2.7 参数还有别的属性：`read_only`

参数不只有「名字 + 类型 + 值」：

```
一个参数 = 名字 + 类型 + 值 + 描述 + read_only 之类的属性
```

被标成 `read_only` 的参数，`ros2 param set` 会被**框架内部**直接拦下——你的代码里一个字都不用写。

### 2.8 每个节点天生自带两个参数

节点一创建，`BaseNode` 就替你声明好了这两个：

| 参数 | 类型 | 默认 | 干什么 |
|---|---|---|---|
| `use_sim_time` | bool | `False` | `True` 时不用系统墙上时钟，改用 `/clock` 话题上的**仿真时间**（跑 Gazebo、回放 rosbag 时要开） |
| `start_type_description_service` | bool | `True` | 是否启动 `~/get_type_description` 服务（给工具查接口类型用），**`read_only=True`** |

**跟你有没有声明过无关，每个节点都有。**

---

## 3. 完整代码

### `param_talker.py`

```python
from rcl_interfaces.msg import SetParametersResult
import rclpy
from rclpy.node import Node
from std_msgs.msg import String


class ParamTalker(Node):
    """参数发布流程."""

    def __init__(self):
        super().__init__('param_talker')

        # ---------- 声明（注册，一辈子一次） ----------
        self.declare_parameter('message', 'hello')
        self.declare_parameter('period', 1.0)
        self.declare_parameter('max_count', 0)

        self.count = 0
        self.pub = self.create_publisher(String, 'chatter', 10)

        # ---------- 用参数建定时器（此刻把周期焊死进去） ----------
        self.timer = self.create_timer(self.get_parameter('period').value, self.tick)

        # ---------- 注册校验回调 ----------
        self.add_on_set_parameters_callback(self.on_param_set)

        self.get_logger().info('param_talker 起来了')

    def tick(self):
        msg = String()
        msg.data = self.get_parameter('message').value    # ← 每次【现读】，改了立刻生效
        self.pub.publish(msg)

        self.count += 1

        if 0 < self.get_parameter('max_count').value <= self.count:
            self.get_logger().info('停止定时器')
            self.timer.cancel()

    def on_param_set(self, params):
        """外部 ros2 param set 时被调用，返回 SetParametersResult 决定放行还是拒绝."""
        for p in params:
            self.get_logger().info(f'{p.name}')
            if p.name == 'period':
                if p.value < 0.1:
                    return SetParametersResult(
                        successful=False, reason=f'period 不能小于 0.1 秒（你填了 {p.value}）')
                elif p.value != self.get_parameter('period').value:   # ← 此刻参数还是旧值
                    self.destroy_timer(self.timer)                    # ← 拆掉旧闹钟
                    self.timer = self.create_timer(p.value, self.tick)  # ← 换个新的

        return SetParametersResult(successful=True)    # ← 循环外兜底放行


def main(args=None):
    rclpy.init(args=args)
    node = ParamTalker()
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

**三个"关键位"：**

| 行 | 为什么这么写 |
|---|---|
| `msg.data = self.get_parameter('message').value` | **现读** → 运行时改立刻生效 |
| `create_timer(self.get_parameter('period').value, ...)` | **建的时候读一次** → 改了不生效，必须重建 |
| 循环外的 `return SetParametersResult(successful=True)` | **兜底放行** → 漏了就会被框架判失败 |

---

## 4. API 速查表

```python
from rcl_interfaces.msg import SetParametersResult

# ---------- 声明（__init__ 里，一辈子一次） ----------
self.declare_parameter('名字', 默认值)
self.declare_parameter('名字', 默认值, 描述符)      # 进阶：ParameterDescriptor

# ---------- 读取（任何地方，随时） ----------
self.get_parameter('名字')            # → Parameter 对象（盒子）
self.get_parameter('名字').value      # → 真正的值 ← 通常要这个

# ---------- 校验回调 ----------
self.add_on_set_parameters_callback(self.on_param_set)   # 不加括号！

def on_param_set(self, params):       # params 是个【列表】
    for p in params:
        p.name                        # 参数名
        p.value                       # 想改成的新值
    return SetParametersResult(successful=True)
    return SetParametersResult(successful=False, reason='给用户看的人话')

# ---------- 定时器的三种"停"法 ----------
self.timer.cancel()                                   # 停住（还能用 reset() 救回来）
self.timer.reset()                                    # 复活 + 上次调用时间重置为现在
self.destroy_timer(self.timer)                        # 彻底拆掉（救不回来，只能重建）

# ---------- 问状态用 is_ 开头的方法（不改任何东西） ----------
self.timer.is_canceled()                              # → True / False   停了吗？
self.timer.is_ready()                                 # → True / False   该响了吗？

# ---------- 换周期：cancel 救不了，必须重建 ----------
self.destroy_timer(self.timer)
self.timer = self.create_timer(新周期, self.tick)
```

---

## 5. 命令行工具速查

| 命令 | 作用 |
|---|---|
| `ros2 param list` | 列出所有节点及其参数 |
| `ros2 param list /param_talker` | 只看这个节点的 |
| `ros2 param get /param_talker message` | 读一个值 |
| `ros2 param set /param_talker message 世界` | 写一个值 |
| `ros2 param describe /param_talker period` | 看类型、描述、只读与否 |
| `ros2 param dump /param_talker` | 导出成 YAML |
| `ros2 param load /param_talker p.yaml` | 从 YAML **一次载入多个** |
| `ros2 topic hz /chatter` | 量实际发布频率 |
| `ros2 run hello_ros param_talker --ros-args -p message:=hi -p period:=0.5` | 启动时覆盖 |

**频率换算（最容易绕晕的地方）：**

```
频率 hz = 1 ÷ period
period = 0.25 秒  →  4  Hz
period = 1.0  秒  →  1  Hz
period = 0.01 秒  →  100 Hz
```

**`param set` 的类型是 CLI 从字面量猜的**：`3` → int，`0.2` → double，`true` → bool。和声明的类型对不上就报错。

---

## 6. 构建与运行流程

### 每次改完代码的固定动作

```bash
cd ~/ros2_learn_ws
colcon build --packages-select hello_ros --symlink-install
source install/setup.bash
```

⚠️ 本关**新加了可执行文件 `param_talker`**，属于改 `setup.py` —— **必须重新 build**，`--symlink-install` 救不了。

### 验收清单

**验收 A · 读参数**

```bash
ros2 run hello_ros param_talker      # 终端 A
ros2 param list                      # 终端 B
ros2 param get /param_talker message
```

期望：`/param_talker` 下有 `max_count` / `message` / `period` **（外加两个自带的）**，`get` 返回 `String value is: hello`。

**验收 B · 启动时覆盖**

```bash
ros2 run hello_ros param_talker --ros-args -p message:=你好 -p period:=0.25
ros2 topic echo /chatter             # 终端 B
ros2 topic hz /chatter               # 期望 ≈ 4 Hz
```

**验收 C · 运行时改**

```bash
ros2 param set /param_talker message 世界     # → echo 下一拍就变
ros2 param set /param_talker period 0.2       # → hz 变 ≈ 5
```

**验收 D · 拒绝非法值**

```bash
ros2 param set /param_talker period 0.01
ros2 param get /param_talker period           # → 还是旧值
```

**验收 E · 上限**

```bash
ros2 run hello_ros param_talker --ros-args -p max_count:=3
```

期望：**只发 3 条**就打印"停止定时器"，之后不再发。

---

## 7. 实测现象与结论 ⭐

> 这一节是**复习重点**，都是动手跑出来的结论。

### 7.1 每个节点天生自带两个参数 —— 一次对照实验

只声明了 `message` 一个参数，`ros2 param list` 却列出三个：

```
/param_talker:
  message
  start_type_description_service
  use_sim_time
```

**怎么确认这两个不是自己写的？** 做了个对照实验：

1. 把自己声明 `message` 的那行**注释掉** → 两个还在
2. 去看一个**完全无关**的节点 `ros2 param list /listener` → **也在**

```
/listener:
  start_type_description_service
  use_sim_time
```

**结论**：它们是 `BaseNode` 在节点创建时自动声明的，**每个节点都有**，和你写不写没关系。

> 📌 **方法比答案重要**：怀疑"A 导致了 B"时，**把 A 去掉再试一遍**；再换一个样本复现。这叫对照实验。

### 7.2 `read_only` 参数会被框架直接拦下

```bash
$ ros2 param set /param_talker start_type_description_service false
Setting parameter failed: Trying to set a read-only parameter: start_type_description_service.
```

报错说得比什么都清楚。**你的代码里一个字都不用写** —— 这是框架层的拦截。

### 7.3 ⭐ 启动时的 `-p` 覆盖**不走**校验回调

**本关最反直觉的一条，实测结论。**

```bash
$ ros2 run hello_ros param_talker --ros-args -p period:=0.01     # 0.01 远低于下限 0.1
$ ros2 param get /param_talker period
Double value is: 0.01                                            # ← 没被拦下！
```

**为什么？** 因为两种改法发生在**不同时刻**：

| 改法 | 发生的时刻 | 走 `on_param_set` 吗 |
|---|---|---|
| 启动时 `-p` | **`declare_parameter` 那一瞬间**（参数还没"出生"就被定了值） | ❌ **不走** |
| 运行时 `param set` | 节点已经跑起来了 | ✅ 走 |

**实践含义**：

> **校验回调是"运行时守门员"，拦不住启动参数。**
> 启动时给的非法值，你的回调**没有机会**看到它——只能靠它自己去读一遍参数做检查。
> 一句话：**别把安全性全押在校验回调上。**

### 7.4 `set message` 立刻生效，`set period` 不生效

同一个节点，两个参数，两种命运：

```bash
ros2 param set /param_talker message 世界      # → echo 下一行就是「世界」
ros2 param set /param_talker period 0.2        # → param get 显示 0.2，但 hz 还是 1
```

**原因**（本关核心）：

| 参数 | 代码里的用法 | 结果 |
|---|---|---|
| `message` | `tick` 里**每次现读** | ✅ 自动生效 |
| `period` | `create_timer` 时**读一次就焊死** | ❌ 需要 `destroy` + `create` |

**所以 `on_param_set` 里才需要"拆旧建新"那两行。**

### 7.5 回调返回 `None` 的后果

漏写兜底 `return` 时（例如 `set message`，`p.name` 不等于 `period`，循环空转到底）：

```
rclpy/node.py:892: UserWarning: Callback returned an invalid type,
                            it should return SetParameterResult.
```

**注意它是 `UserWarning`，不是 `Error`** —— 但后果更严重：框架把 `None` **强行转成 `successful=False`**，所以：

```
$ ros2 param set /param_talker message 世界
Set parameter failed（或只有一行 warning）
$ ros2 param get /param_talker message
hello                                    # ← 根本没改成功
```

**"光打了一行 warning 就过去了"是最难察觉的一类失败**：参数一声不吭没变，你还以为成功了。

### 7.6 `param load` 是**一次请求送多个**参数

源码 `ros2param/api/__init__.py`：

```python
assert len(response.results) == len(parameters), 'Not all parameters set'
```

**一次调用返回 N 个结果 = 一次请求带了 N 个参数。**

**所以兜底 `return` 必须在循环外面**——写在循环里的话，第一轮就返回了，**后面几个参数完全不会被检查**。

这个坑平时不显形（`ros2 param set` 一次只送一个），只在 `param load` 或程序里 `set_parameters([...])` 时才炸。

### 7.7 `colcon test` 是"执行"，`colcon test-result` 是"查看"

**两个命令，两件事：**

| 命令 | 干什么 |
|---|---|
| `colcon test --packages-select hello_ros` | 把测试**真的跑一遍**（每次都重跑） |
| `colcon test-result --verbose` | **查看**上一次的结果 |

**只敲第二条，看到的永远是旧成绩单。**

`colcon test` 输出里的 `Aborted` 不代表"程序崩了"，只代表"**至少有一个测试没通过**"。它会**故意不告诉你哪里错**——细节要另敲 `test-result`，或者去读：

```
log/latest_test/hello_ros/stdout_stderr.log
```

**出错条数就在失败信息的第一行**，不用自己去数：

```
AssertionError: Found 18 code style errors / warnings:
                    ↑↑ 这个数字就是进度条
```

### 7.8 格式问题交给工具，别靠人眼

本关末尾清 lint 的实战数据：**18 条 → 11 条 → 7 条 → 2 条 → 0 条**。

几条被 ament_flake8 揪出来的：

| 代码 | 人话 |
|---|---|
| `I100` | import 必须按**模块名字母序**（ament 用 `import-order-style = google`） |
| `CNL100` | `class` 后面不能直接跟 `def`，中间要有 **docstring 或空行** |
| `E303` / `E302` | 空行数**多一个少一个都报**（顶层之间 2 行，类里面 1 行） |
| `W291` / `W293` | 行尾、空行里的多余空格 |
| `W391` / `W292` | 文件末尾：**要有换行符，但不要空行** |
| `D400` / `D415` | docstring 第一行必须以 **`.` / `?` / `!`** 结尾——**中文的 `。` 不算！** |

**`D400`/`D415` 那条最坑**：纯粹因为"用中文写注释"才踩到，跟代码逻辑毫无关系。

> 💡 **为什么 `D100`/`D102`（"缺文档字符串"）从来不报？**
> 因为 ament 的默认约定就是**不管它们**。源码 `ament_pep257/main.py` 里的 `_ament_ignore` 列表开头就是：
>
> ```python
> _ament_ignore = ['D100', 'D101', 'D102', 'D103', 'D104', 'D105', 'D106', 'D107', ...]
> ```
>
> 这 8 个全是"必须有 docstring"类的检查。**ROS 2 的约定是：不强制写文档字符串，但你要是写了，就得写对**（所以 `D400`/`D415` 照报）。
>
> 自己用裸 `pydocstyle` 跑会看到几十条 `D100`——**那不是错**，是没套 ament 的约定。

### 7.9 ⭐ 定时器的三种"停"法（补充实验）

`timer.cancel()` 停掉之后还能不能救回来？实测：

```
tick 1 / 2 / 3 / 4          ← 正常跑
=== cancel() ===
is_canceled = True
   (中间 2 秒，一次都没响)     ← 真的停了
=== reset() ===
is_canceled = False
tick 5 / 6 / 7              ← 活过来了 ✅
```

**三个方法，三件事，别混：**

| 方法 | 干什么 | 返回值 | 能救回来吗 |
|---|---|---|---|
| `cancel()` | **停住**（状态变成"已取消"） | `None` | ✅ 能（用 `reset()`） |
| `reset()` | **复活** + 把"上次调用时间"重置为现在 | `None` | — |
| `destroy_timer()` | **拆掉**（对象都没了） | `None` | ❌ 不能，只能 `create_timer` 重建 |

源码依据（`rcl/timer.h`）——`reset()` 的确切语义：

> This function can be called on a timer, canceled or not.
> For all timers it will reset the last call time to now.
> **For canceled timers it will additionally make the timer not canceled.**

**⚠️ 别把"问句"写成"命令"。**

| 名字 | 是什么 | 返回值 |
|---|---|---|
| `cancel()` | **命令**（动词）：把它停掉 | `None` |
| `is_canceled()` | **问句**（`is_` 前缀）：它停了吗？ | `True`/`False` |
| `reset()` | **命令**：复活它 | `None` |
| `is_ready()` | **问句**：该响了吗？ | `True`/`False` |

写错代价很大——`if self.timer.cancel():` 有**两个**后果：

1. `cancel()` 返回 `None` → `if None:` 永远是 `False` → **整块代码不执行**
2. 更阴险：**它真的把定时器停掉了**。你想让定时器活着，代码把它杀了。而且不报错。

> **`is_` 前缀是最强的线索**：看到 `is_` 就知道是问句，不改任何状态。
> 没有 `is_` 默认是命令，会改变状态。这条不只对 rclpy 成立。

### 7.10 ⭐ 改了 `.py` 必须重启节点

一次"代码明明写对了但就是不生效"的排查，真凶在这里：

```
ros2 run hello_ros param_talker     ← 启动时把 .py 读进内存
        ↓
改了 .py 文件
        ↓
跑着的进程【完全不知道】—— 内存里还是旧代码
```

| 你改了 | 要做什么 |
|---|---|
| `.py` 里的代码 | **重启节点**（Ctrl+C 再 `ros2 run`） |
| `setup.py` / `package.xml`（加可执行文件、加依赖） | `colcon build` **+** 重启节点 |
| 只改 `.py` | **不用** `colcon build`（`--symlink-install` 的功劳） |

> ⚠️ **`--symlink-install` 免的是 `colcon build`，免不了重启节点。**
> 这两件事很容易混成一件——"我不用 build 了" ≠ "我不用重启了"。

**排查这类问题最快的动作**：改完代码 → **先 `pkill` / Ctrl+C，再重新起**。跑着的进程永远执行它启动那一刻读到的代码。

### 7.11 复活的完整验收（实测数据）

```bash
ros2 run hello_ros param_talker --ros-args -p max_count:=2 -p period:=1.0
ros2 param set /param_talker max_count 5
```

```
[034.328] 停止定时器        ← 发满 2 条，停了
[039.592] max_count         ← 回调被打到，走进 elif 分支
[042.593] 停止定时器        ← reset() 复活后又发 3 条，第 5 条时停
          └─ 039.592 → 042.593 = 正好 3.0 秒 = 3 拍 ✓
```

**总共 5 条，最后一条是第 5 条。** 每拍 1 秒，3 秒 = 3 条，不多不少。

**注意这里 `ros2 param set` 回的是 `Set parameter successful`。**

> ⚠️ **"回调返回成功" ≠ "你关心的那件事发生了"。**
> 你的 `on_param_set` 对 `max_count` 无脑返回 `successful=True`（它只校验 `period`），所以从系统角度看这次修改**完全合法、完全成功**。
> **唯一没发生的是你以为会发生的那件事**——因为没有任何机制把"`max_count` 变了"和"定时器停了"联系起来。
> **那根线是你自己接的**（`is_canceled()` + `reset()`），接错了它不会报错，只会安静地什么都不做。

---

## 8. 踩坑记录

本关实际踩过的坑，按发生顺序：

| # | 坑 | 报错 / 现象 | 正解 |
|---|---|---|---|
| 1 | `get_parameter()` 当成值用 | 打印出 `<rclpy.parameter.Parameter object at 0x...>` | 加 `.value` |
| 2 | 在校验回调里**重新声明**参数 | `ParameterAlreadyDeclaredException`（只在真的 set 时才炸） | 回调里只读不声明：`__init__` 签合同，别处查余额 |
| 3 | 参数名写成 `'msg.data'` | 整块代码永不执行，静默无效 | 参数名是 `declare` 时写的字符串；`p.name` 打印出来看 |
| 4 | `else` 后面带条件 | `SyntaxError` | Python 里带条件的"否则如果"是 **`elif`** |
| 5 | 用 `&` 当"并且" | `TypeError`（`&` 是**位运算**） | 用 **`and`** |
| 6 | 把上一关的 `msg.data` 拖到参数名上 | 静默不生效 | **长得像 ≠ 是一回事**，先问"这个位置本来该装什么" |
| 7 | 用 `self.pri = declare_parameter(...)` 当"旧值" | 值永远停在初始值 | 回调触发时参数**还是旧值**，直接 `get_parameter` |
| 8 | 校验回调漏写兜底 `return` | `UserWarning: Callback returned an invalid type` + **参数改不成** | 循环**外面**无条件 `return successful=True` |
| 9 | 兜底 `return` 写在**循环里面** | 单参数时正常，`param load` 时后面的参数全跳过 | 循环里逐条检查，循环外统一放行 |
| 10 | **化简时把 `>=` 改成 `>`** ⭐ | **不报错**，`max_count:=3` 变成发 4 条 | 化简前后在心里各念一遍，确认意思**一模一样** |
| 11 | 改 `period` 后定时器频率没变 | `param get` 显示新值，`hz` 还是旧的 | `destroy_timer` + `create_timer` 重建 |
| 12 | 只敲 `colcon test-result` 不敲 `colcon test` | 反复看到同一份旧结果，以为"没改好" | `colcon test` 是**执行**，`test-result` 是**查看** |
| 13 | docstring 用中文句号 `。` 结尾 | `D400` / `D415` | 换成半角的 `.` |
| 14 | 删空行"删过头" | `E303`（3 个）改成 `E302`（1 个） | 空行数是个**精确值**：顶层 2 个，类里 1 个 |
| 15 | 删文件末尾空行时把换行符也删了 | `W391` 变成 `W292` | 结尾要有**一个换行符**，但**不要空行** |
| 16 | 把"问句"写成"命令"：`if self.timer.cancel():` | **不报错**，整块不执行；更糟的是**真把定时器停了** | 问状态用 `is_canceled()`，`is_` 前缀 = 问句（见 [7.9](#79--定时器的三种停法补充实验)） |
| 17 | 改完 `.py` 没重启节点 | 代码明明写对了，行为还是旧的 | 改了代码**必须重启节点**（见 [7.10](#710--改了-py-必须重启节点)） |

### ⚠️ 三条跨关存在的通用教训

**① "不报错的 bug"是最难抓的**

本关出现了三次：

- 参数名写成 `'msg.data'` → 代码永不执行，不报错
- 化简时 `>=` 写成 `>` → 数字只差 1，不报错
- `is_canceled()` 写成 `cancel()` → 整块不执行，**还顺手把定时器杀了**，不报错

第 2 关那次是 `a=3`/`b=4` 没写进 request，静默算出 `sum=0`。

**遇到这种坑别去找报错，要去找证据**：把中间值**打印出来看**。

```python
self.get_logger().info(f'这次要改的参数名是：{p.name}')
```

**不确定就让代码自己说。** 调试完记得删掉。

**② 概念迁移会出错——"长得像"不等于"是一回事"**

| 关卡 | 把什么拖过去了 |
|---|---|
| 第 1 关 | 把"发布者主动推"套到**订阅者**身上 |
| 第 2 关 | 把"服务端推送"套到**服务客户端**身上 |
| 第 3 关 | 把 `msg.data` 套到**参数名**身上 |

**写新代码时先问一句：这个位置本来应该装什么？**——而不是"上次这个位置我填的啥"。

**③ 规则拿不准，别猜——写个最小样例让工具判**

"import 到底怎么排序？" 与其猜，不如：

```bash
python3 -m flake8 --config=/opt/ros/lyrical/lib/python3.14/site-packages/ament_flake8/configuration/ament_flake8.ini 你的文件.py
```

**改一次，跑一次。** 工具说了算。

---

## 9. 自测题（附答案）

> 复习时**先遮住答案自己答一遍**，答不出来再翻回去对应章节。

### 题 1：`declare_parameter` 和 `get_parameter` 有什么区别？

<details>
<summary>点开答案</summary>

|  | `declare_parameter` | `get_parameter` |
|---|---|---|
| 干的事 | **注册**（签合同） | **读取**（查余额） |
| 次数 | **一辈子一次** | 随时，想读几次读几次 |
| 时机 | `__init__` 里 | 任何地方 |

**口诀**：`__init__` 里签合同，别的地方查余额。

搞混的后果：在回调里再 `declare` 一次 → `ParameterAlreadyDeclaredException`（源码 `rclpy/node.py:506`）。

</details>

### 题 2：为什么改了 `message` 立刻生效，改了 `period` 却要重建定时器？

<details>
<summary>点开答案</summary>

因为**用法不同**：

| 参数 | 代码里的写法 | 结果 |
|---|---|---|
| `message` | `tick` 里每次**现读** | 自动生效 ✅ |
| `period` | `create_timer(周期, ...)` 建的时候**读一次就焊死** | 不生效 ❌ |

**定时器不是每拍都去问参数"我该多久响一次"**——创建的那一刻，周期这个**数字**就被交出去了，跟参数从此没有联系。

类比：闹钟设了"每小时响"，想改成 10 分钟，你没法对它喊一声——**得拆了换个新的**。

```python
self.destroy_timer(self.timer)
self.timer = self.create_timer(新周期, self.tick)
```

</details>

### 题 3：`on_param_set` 被调用的时候，`self.get_parameter('period').value` 拿到的是**新值**还是**旧值**？

<details>
<summary>点开答案</summary>

**旧值。**

源码 `rclpy/node.py` 里的顺序是：

```
1. 先调用你的回调        ←── 你在这里，参数【还没被改】
2. 回调返回 successful=True
3. 框架才把新值写进去
```

**所以"旧值"根本不用自己存**：

| 想要 | 从哪拿 |
|---|---|
| 新值 | `params` 里那个 `p.value` |
| 旧值 | `self.get_parameter('period').value` |

⚠️ 反例：`self.pri = declare_parameter('period', 1.0)` 然后拿 `self.pri.value` 当旧值——它是**出生那一刻的快照**，参数再改它也不会变。（源码里 set 参数时会用**新对象替换**字典里的旧对象，你手里那个引用永远指向老的。）

</details>

### 题 4：漏写兜底 `return SetParametersResult(successful=True)` 会怎样？

<details>
<summary>点开答案</summary>

函数某条路径走到末尾 → 隐式返回 `None` → 框架不认：

```
UserWarning: Callback returned an invalid type, it should return SetParameterResult.
```

**然后框架把 `None` 强行转成 `successful=False`** → **参数改不成**。

**两条会掉到函数末尾的路径：**

1. 改的是**别的**参数（`p.name != 'period'`）→ 循环空转到底
2. 改的是 `period`，但**值没变** → `elif` 不成立

**正确结构：**

```python
for p in params:
    ...                            # 逐条检查、该拒绝的在这里 return
return SetParametersResult(successful=True)    # ← 循环【外面】兜底
```

⚠️ 兜底写在**循环里面**是另一个 bug：一次送多个参数时，第一轮就返回，后面的全跳过。

</details>

### 题 5：为什么框架"什么都不挑"，连值没变也要叫你的回调？

<details>
<summary>点开答案</summary>

**因为框架根本不知道你的参数是干嘛的。**

它手里只有一个 `Parameter` 对象——名字 + 值。它不知道 `period` 是"秒"，不知道 `0.1` 是下限，更不知道这个值跟定时器有关系。**这些规矩全在你脑子里，框架里根本不存在。**

所以它唯一的做法就是：**每次有人要改参数，先原封不动地问你一遍，你点头它才改。**

它也不比较新旧值、不管你关不关心——**"这次改动有没有意义"的判断是你自己的活**：

- 改的不是 `period` → 你的 `p.name == 'period'` 挡住了
- 值没变 → 你的 `p.value != self.get_parameter('period')` 挡住了

**这两句"多余"的判断不是多余的**，它们正是把框架"不分青红皂白"的呼叫，过滤成"只在真正需要时才重建定时器"。

> 所以框架"无条件叫"是**好事**：它把"什么算变化"的决定权完全交给你。想重建、想只打印、想干脆拒绝，都由你说了算。框架只负责**在改之前**给你一次说话的机会。

</details>

### 题 6：启动时 `-p period:=0.01`（低于你的下限）会被校验回调拦下吗？

<details>
<summary>点开答案</summary>

**不会。**

实测：

```bash
$ ros2 run hello_ros param_talker --ros-args -p period:=0.01
$ ros2 param get /param_talker period
Double value is: 0.01          # ← 没被拦
```

**原因**：两种改法发生在**不同时刻**：

| 改法 | 时刻 | 走回调吗 |
|---|---|---|
| 启动时 `-p` | `declare_parameter` 那一瞬间 | ❌ |
| 运行时 `param set` | 节点已跑起来 | ✅ |

**实践含义**：**校验回调是"运行时守门员"，拦不住启动参数。** 启动时的非法值你的回调**没机会看到**。

**别把安全性全押在校验回调上。**

</details>

### 题 7：参数为什么不做成话题？

<details>
<summary>点开答案</summary>

能做，但等于**从头手搓一套参数系统**，麻烦一箩筐：

1. **没有"当前值"的概念**：话题是**流**，新订阅者只看到之后的消息。改成"我要读一下现在是多少"，得自己再开一个话题去问——这就是服务了。
2. **没有回执 / 没有拒绝**：`ros2 param set` 返回成功或失败（还能带 `reason`）。用话题广播出去，**谁改了、改没改成功，你根本不知道**——这不只是调试麻烦，配置改没改上是**要出事的**。
3. **没有校验**：参数的核心就是"配置写错要拦住"。话题上没有"改之前先问一句"这个机制。
4. **会丢消息**：默认 QoS 是 volatile，订阅者晚起、处理慢了就丢——配置丢了它自己不知道。
5. **粒度不对**：参数是**每个节点私有**的（`/param_talker.message`），话题是**全局广播**的。

**一句话**：话题是"**喊一嗓子**"，参数是"**改一个开关**"。喊嗓子保证不了"改成功了"，也保证不了"改动被批准"。

</details>

### 题 8：`ros2 param dump` / `ros2 param load` 是干什么的？

<details>
<summary>点开答案</summary>

```bash
ros2 param dump /param_talker > /tmp/p.yaml     # 把当前参数【存进文件】
ros2 param load /param_talker /tmp/p.yaml       # 从文件【一次载入】
```

**`ros2 param set` 改的是内存里的值，不是文件。** 节点一关，改动就没了——下次启动还是 `declare` 的默认值。

**`dump` + `load` 就是"持久化"的手段**：

```bash
ros2 param set /param_talker message 世界    # 改
ros2 param dump /param_talker > my.yaml      # 存盘
# 下次启动
ros2 param load /param_talker my.yaml        # 读回来
```

**下一步（第 4 关 launch 文件）**就是把这套 YAML 固化到启动流程里——**一启动就是你要的配置，不用手敲**。

> ⚠️ `param load` 是**一次请求送多个参数**，所以它会撞上 [题 4](#题-4漏写兜底-return-setparametersresultsuccessfultrue-会怎样) 里那个"兜底 `return` 写在循环里"的 bug。

</details>

### 题 9：参数除了"名字、类型、值"，还有什么？

<details>
<summary>点开答案</summary>

```
一个参数 = 名字 + 类型 + 值 + 描述 + read_only 之类的属性
```

**验证 `read_only` 的方法**：

```bash
$ ros2 param set /param_talker start_type_description_service false
Setting parameter failed: Trying to set a read-only parameter: start_type_description_service.
```

被标成只读的参数，**框架层**直接拦下，你的代码里一个字都不用写。

看一个参数的全部属性：

```bash
ros2 param describe /param_talker period
```

**每个节点天生自带两个参数**：`use_sim_time`（默认 `False`）和 `start_type_description_service`（默认 `True`，只读）。它们是 `BaseNode` 在节点创建时自动声明的，**跟你有没有声明过无关**。

</details>

### 题 10：`ros2 param list` 里有你不认识的参数，怎么办？

<details>
<summary>点开答案</summary>

**先问"是不是节点自带的"，再做对照实验。**

本关的实际做法：

1. 把自己声明它的那行**注释掉** → 还在
2. 去看一个**完全无关**的节点 → **也在**

**结论**：是节点自带的。

> 📌 **方法比答案重要**：怀疑"A 导致了 B"时，**把 A 去掉再试一遍**；再换一个样本复现。这叫对照实验——比问人、比猜都快。

对于不确定的变量/字段，最直接的办法永远是**打印出来看**：

```python
self.get_logger().info(f'{p.name}')
```

</details>

### 题 11：`cancel()` / `reset()` / `destroy_timer()` 有什么区别？

<details>
<summary>点开答案</summary>

| 方法 | 干什么 | 能救回来吗 |
|---|---|---|
| `cancel()` | **停住**（状态变"已取消"） | ✅ 能，用 `reset()` |
| `reset()` | **复活** + 把"上次调用时间"重置为现在 | — |
| `destroy_timer()` | **拆掉**（对象都没了） | ❌ 只能 `create_timer` 重建 |

**怎么问"它停了吗"？**——`is_canceled()`，**不是** `cancel()`。

| 名字 | 词性 | 返回值 |
|---|---|---|
| `cancel()` | 命令（动词） | `None` |
| `is_canceled()` | 问句（`is_` 前缀） | `True` / `False` |
| `reset()` | 命令 | `None` |
| `is_ready()` | 问句 | `True` / `False` |

**写成 `if self.timer.cancel():` 的两个后果**：

1. 返回 `None` → `if None:` 永远 `False` → **整块代码不执行**
2. 更阴险：**它真的把定时器停掉了** —— 你想让它活着，代码把它杀了。**不报错。**

> **规律**：`is_` 开头 = 问句，不改状态；没有 `is_` = 命令，会改状态。不只对 rclpy 成立。

</details>

### 题 12：改完 `.py` 代码没生效，怎么办？

<details>
<summary>点开答案</summary>

**先问自己：节点重启了吗？**

```
ros2 run hello_ros param_talker     ← 启动时把 .py 读进内存
        ↓
改了 .py
        ↓
跑着的进程【完全不知道】
```

**Python 不会盯着文件看。** 跑着的进程永远执行它启动那一刻读到的代码。

| 你改了 | 要做什么 |
|---|---|
| 只改 `.py` | **重启节点**（不用 `colcon build`） |
| `setup.py` / `package.xml` | `colcon build` **+** 重启节点 |

> ⚠️ **`--symlink-install` 免的是 `colcon build`，免不了重启节点。**
> "我不用 build 了" ≠ "我不用重启了"。

**最快的排查动作**：改完代码 → 先 `pkill` / Ctrl+C，再重新起。

</details>

---

## 附：本关命令速记卡

```bash
# 构建
cd ~/ros2_learn_ws
colcon build --packages-select hello_ros --symlink-install   # 本关改了 setup.py，必须 build
source install/setup.bash

# 运行
ros2 run hello_ros param_talker
ros2 run hello_ros param_talker --ros-args -p message:=你好 -p period:=0.25 -p max_count:=3

# 观察 / 验收
ros2 param list
ros2 param list /param_talker
ros2 param get /param_talker message
ros2 param set /param_talker period 0.2
ros2 param describe /param_talker period
ros2 param dump /param_talker
ros2 param load /param_talker p.yaml
ros2 topic echo /chatter
ros2 topic hz /chatter

# 代码检查
colcon test --packages-select hello_ros          # ① 执行
colcon test-result --verbose                     # ② 查看
log/latest_test/hello_ros/stdout_stderr.log      # 原始日志（细节在这里）

# 分类清理
pkill -f param_talker
```

---

**下一关预告 · launch 文件**

> 本关你已经能把参数**存进 YAML**、**启动时覆盖**——但这些还是**手工**的：开两个终端、敲一长串 `--ros-args`。
>
> 第 4 关要解决的是：**一条命令，一次启动多个节点，参数全部写好。**
>
> 到那时，你在本关学的 `ros2 param dump` 出来的 YAML，就会变成 launch 文件的一部分。
