# 第 9 关 · ros2 bag 录包与回放

> 前八关全是**现场直播** —— 节点活着才有数据，节点一死，数据就没了。
> 这一关第一次把一段数据**冻结在磁盘上**，可以反复重放。
>
> 一句话：**`ros2 bag record` 是个订阅者，`ros2 bag play` 是个发布者。**
> bag 不是新的通信机制 —— 它就是你第 1 关写的那个话题，前面挂了一台录音机和一台播放器。
>
> 而"录不录得到"，跟"录"这个动作**没有任何关系** ——
> 只跟发布者**留不留历史**有关。

---

## 目录

- [1. 本关目标](#1-本关目标)
- [2. 核心概念](#2-核心概念)
- [3. 完整代码](#3-完整代码)
- [4. `ros2 bag` 子命令速查](#4-ros2-bag-子命令速查)
- [5. 命令行工具速查](#5-命令行工具速查)
- [6. 构建与运行流程](#6-构建与运行流程)
- [7. 实测现象与结论 ⭐](#7-实测现象与结论-)
- [8. 踩坑记录](#8-踩坑记录)
- [9. 自测题](#9-自测题)
- [10. 附：跨关待办](#10-附跨关待办)
- [附：本关命令速记卡](#附本关命令速记卡)

---

## 1. 本关目标

- 会**录**：知道 `record` 录的是什么、**不录**什么。
- 会**问**：读懂 `ros2 bag info` 的每一个字段。
- 会**放**：知道 `play` 按什么节奏放、哪些旋钮能改。
- 用 bag 做一次**判据实验**，把第 8 关那个"抽屉"钉死。
- 全程**不写代码** —— 用的都是自己在前八关写过的节点。

**这一关的性子跟前八关不一样。** 前八关是"写代码 + 跑起来看看"；
这一关是"**下命令 + 盯数字 + 猜为什么**"。代码一行都不用写，
但**判断密度**是九关里最高的。

> 如果你只从这一关带走一件事，带走这句：
>
> **`ros2 bag record` 只是一个订阅者。它拿不到的东西，它一个字也录不下来。**

---

## 2. 核心概念

### 2.1 bag 不是新东西

| 你敲的 | 它是什么 |
|---|---|
| `ros2 bag record` | 起**一个节点**，是个**订阅者**，收到什么就往磁盘上写什么 |
| `ros2 bag play` | 起**一个节点**，是个**发布者**，把磁盘上的东西按原时间戳重新发出来 |

这和**第 5 关**是同一种"祛魅"：动作（Action）不是新机制，是 3 个服务 + 2 个话题拼的。
bag 也一样 —— 它下面就是**第 1 关的话题**。

实测证据（回放进行中的 `ros2 topic info`）：

```
Publisher count: 1
Node name: rosbag2_player          ← 它就是一个叫这个名字的普通节点
  Reliability: RELIABLE
  History (Depth): KEEP_LAST (10)
  Durability: VOLATILE
```

### 2.2 一个"包"长什么样

`ros2 bag record -o bag1` 造出来的 **`bag1` 是一个目录，不是一个文件**：

```
bag1/
├── 0_bag1_2026_09_21-19_36_37.mcap     ← 数据本体（默认格式是 mcap）
└── metadata.yaml                        ← 索引：谁在哪个文件、什么类型、多少条
```

- `-o` 全称是 `--output`，但它要的是**输出目录**。
- 数据文件名里**自带录制开始的日期-时间**，所以往同一个目录里录两次不会互相覆盖。
- 默认存储格式是 **mcap**（`ros2 bag record --help` 里 `-s, --storage {sqlite3,mcap}`，
  default 是 `mcap`）。录制时会打一句 WARN：

  ```
  [WARN] No input serialization format specified, using default rmw serialization format: 'cdr'.
  ```

  **这不是错误** —— 它在说"消息内容我用 cdr 序列化"（rmw 的默认格式）。

### 2.3 ⭐ `Duration` 量的不是"录了多久"

`ros2 bag info` 里：

```
Duration:  11.000075716s
Start:     Sep 21 2026 19:36:37.579864747
End:       Sep 21 2026 19:36:48.579940463
Messages:  12
```

`Duration = End − Start`。而 `Start` / `End` 是**第一条和最后一条消息的时间戳**，
**不是你按下录制键到按下停止键的那段时间**。

所以：

> **N 条消息只有 N−1 个间隔。**

12 条 → Duration 11.0000 秒。10 条 → Duration 8.9998 秒。**都是 N−1。**

它可以比录制时长**更短**（第一条消息是开始录之后 0.5 秒才来的），
也可以**更长**（你数到 10 才按停止，实际跨了 11 秒）。
**它跟"录了多久"没有固定关系。**

### 2.4 ⭐⭐ 录到多少，取决于发布者留不留历史

这是本关的命门，也是第 8 关的旧账。

**`record` 就是个订阅者，它也有 QoS。** 它能不能拿到"开始录之前就发过的消息"，
取决于发布者那边**有没有留**：

| 发布者 durability | 发布者状态 | 开始录之后录到 |
|---|---|---|
| `TRANSIENT_LOCAL` | 活着 · 已停发 | **5 条**（历史全进来了） |
| `VOLATILE` | 活着 · 已停发 | **0 条** |

**两轮命令只差一个词。** 详见证 §7.1。

> **`ros2 bag record` 拿不到的东西，它一个字也录不下来。**

顺带一个实测细节：`rosbag2_recorder` 的**订阅** durability 两轮里不一样 ——
TL 轮它是 `TRANSIENT_LOCAL`，volatile 轮它是 `VOLATILE`。**它会跟着发布者变**
（否则它根本接不到 TL 的历史）。按什么规则变，本关没测出来。

### 2.5 ⭐ 回放 = 按原时间戳 1:1 重放

`ros2 bag play bag1` 起来的第一行日志是：

```
[INFO] [rosbag2_player]: Set rate to 1
```

**`rate = 1` 就是"按包里存的时间戳 1:1 重放"** —— 原本 1 Hz 的数据，回放还是 1 Hz。

实测（探针打的是"收到时的墙钟时间"）：

```
  4.131  第 7 次心跳
  5.131  第 8 次心跳
  6.131  第 9 次心跳
  7.130  第 10 次心跳
   ...
 14.131  第 17 次心跳        ← 相邻两行精确 1.000 秒
```

想快进/慢放，用 **`-r`**：

```bash
ros2 bag play -r 2.0 bag1     # 2 倍速
ros2 bag play -r 0.5 bag1     # 半速
```

**注意 `-r` 改的是"播放速度"，不是包里的时间戳** —— 包本身一个字节都没变。

放完之后 **`play` 自己退出**，不用你按 Ctrl+C。

### 2.6 空包的三副面孔

`bag_vol2`（0 条）的 `info`：

```
Files:             0_bag_vol2_2026_09_21-20_07_50.mcap
Bag size:          1.9 KiB
Duration:          0.000000000s
Start:             Apr 12 2262 07:47:16.854775807 (9223372036.854775807)
End:               Apr 12 2262 07:47:16.854775807 (9223372036.854775807)
Messages:          0
Topic information:
```

三副面孔：

1. **`Messages: 0`**
2. **`Topic information:` 后面整段空掉** —— 连话题名都没记下来
3. **时间戳是 2262 年** —— `9223372036.854775807` 秒 = `9223372036854775807` 纳秒
   = **int64 的最大值**，是**哨兵值**，意思是"从来没有过"

> 为什么不用 `0`？因为 `0` 会被误读成"1970 年 1 月 1 日"。
> 宁可填一个**一眼就知道不可能**的数。

**还有一点：`Bag size: 1.9 KiB`** —— 空包**也是包**，文件照样建出来了。

> **"有文件"和"有数据"是两件事。**
> 这是第 4 关"绿灯 ≠ 做了你想做的事"、第 6 关"构建成功 ≠ 能用"的同族。

### 2.7 ⭐ 三张脸，一件事

把本关三件事摆一起：

| 现象 | 本质 |
|---|---|
| 开始录**之前**发布者发的，没进包 | VOLATILE 不留历史 |
| 回放**刚开始那一瞬**，晚一步的订阅者，漏了第一条 | 同上 |
| 发布者发完停住了，整个包 **0 条** | 同上 |

**同一句话：**

> **VOLATILE = 没有抽屉。你在场之前发生的事，对你来说不存在。**

这就是第 1 关那句"必须先启动 talker"、第 8 关那句"`TRANSIENT_LOCAL` 不是持久化"的完整版。

---

## 3. 完整代码

### 本关没有新代码

一行都没有。这是九关里唯一一关**纯 CLI** 的。

### 用到的现成节点（都是自己写过的）

| 节点 | 来自 | 用途 |
|---|---|---|
| `talker` | 第 1 关 | 1 Hz 发 `/chatter`，当"活水"数据源 |
| `qos_talker` | 第 8 关 | `TRANSIENT_LOCAL`，发 5 条停发但**不退** |
| `status_talker` | 第 6 关 | 多字段 / 嵌套消息，想录复杂消息时用 |

### 唯一的"新东西"：两条 CLI 临时发布者

本关的判据实验**没有用 `qos_talker`**，而是用 `ros2 topic pub` 现场造了两个发布者。
原因只有一个：**要做到"只改一个词"的干净对照** ——
用它自己写的节点做不到（`qos_talker` 的 durability 是写死在代码里的）。

```bash
# TL 版
ros2 topic pub -r 2 -t 5 -w 0 --keep-alive 60 \
    --qos-durability transient_local \
    /qos_hist std_msgs/msg/String "{data: hi}"

# volatile 版 —— 只改了上面那个词
ros2 topic pub -r 2 -t 5 -w 0 --keep-alive 60 \
    --qos-durability volatile \
    /qos_hist std_msgs/msg/String "{data: hi}"
```

**每个参数都在干活，一个都不能省：**

| 参数 | 作用 | 省了会怎样 |
|---|---|---|
| `-r 2` | 2 Hz | 默认 1 Hz，5 条要 5 秒 |
| `-t 5` | 发 5 条 | 一直发，没有"停发"这个状态 |
| **`-w 0`** | **不等订阅者，立刻开闸** | **它会卡在那儿等订阅者 —— 实验直接作废**（见 §8 坑 2） |
| `--keep-alive 60` | 发完还**活着 60 秒** | 默认只有 0.1 秒，进程一退，"抽屉"跟着没 |
| `--qos-durability` | 本关的自变量 | —— |

---

## 4. `ros2 bag` 子命令速查

### 录

```bash
ros2 bag record --topics /chatter -o bag1          # 录一个话题到 ./bag1/
ros2 bag record --topics /a /b -o bag1             # 录多个
ros2 bag record -a -o bag1                         # 全录（all topics, services, actions）
ros2 bag record --topics /chatter -o bag1 -s sqlite3   # 换存储格式（默认 mcap，推荐不动）
ros2 bag record --topics /chatter -o bag1 --compression-mode file --compression-format zstd
```

> ⚠️ **这版没有"位置参数话题"** —— `ros2 bag record -o bag1 /chatter` 会报
> `ros2: error: unrecognized arguments: /chatter`。**必须写 `--topics`**。见 §8 坑 1。

### 问

```bash
ros2 bag info bag1              # 主力命令
ros2 bag info bag1 --sort count # 按条数排序
```

### 放

```bash
ros2 bag play bag1                      # 1:1 原速
ros2 bag play -r 2.0 bag1               # 2 倍速
ros2 bag play -d 3.0 bag1               # 延迟 3 秒再开播
ros2 bag play --start-paused bag1       # 起来先暂停，按空格开始
ros2 bag play --loop bag1               # 循环
ros2 bag play --topics /chatter bag1    # 只放其中一部分话题
```

**回放中的键盘控制**（终端里）：

| 键 | 作用 |
|---|---|
| `空格` | 暂停 / 继续 |
| `→` | 单步，下一条消息 |
| `↑` / `↓` | 速率 +10% / −10% |

**进度条上的状态位**：`[R]unning` / `[P]aused` / `[B]urst` / `[D]elayed` / `[S]topped`

> ⚠️ 如果不是在真终端里跑（脚本、重定向），会先打一句
> `stdin is not a terminal device. Keyboard handling disabled.` ——
> 键盘控制和 Ctrl+C 都会失效（见 §8 坑 3）。

---

## 5. 命令行工具速查

### 🔴 做实验之前必敲的一条

```bash
ros2 topic info /话题名
```

- 没人在 → **`Unknown topic '/话题名'`**
- 有残留 → `Publisher count: 1` / `Subscription count: 1`

> **判据必须是 `Unknown topic`，不是 `Publisher count: 0`。**
> 这两个不一样：`Publisher count: 0` 可能是"刚还有人，现在没了"。

### 造临时发布者（本关自变量）

```bash
ros2 topic pub -r 2 -t 5 -w 0 --keep-alive 60 \
    --qos-durability transient_local \
    /qos_hist std_msgs/msg/String "{data: hi}"
```

`ros2 topic pub` 常用参数：

| 参数 | 意思 |
|---|---|
| `-r N` | 频率 Hz（默认 1） |
| `-1` / `--once` | 发一条就退 |
| `-t N` / `--times N` | 发 N 条就退 |
| **`-w N`** | **等 N 个订阅者才开闸**（`-1`/`-t` 时**默认是 1**！） |
| `--keep-alive N` | 发完还活着 N 秒（默认 **0.1**） |
| `--qos-durability` | `system_default` / `transient_local` / `volatile` / `best_available` |
| `--qos-reliability` | `system_default` / `reliable` / `best_effort` / `best_available` |
| `--qos-depth N` | 队列深度（默认 10） |

### 看 QoS

```bash
ros2 topic info /话题名 --verbose
```

回放的时候用它，能看到 `rosbag2_player` 那一路的完整 QoS。

### 看回放节奏

```bash
ros2 topic hz /话题名          # 直接报 rate
ros2 topic echo /话题名        # 盯两行之间真实过了多久
```

---

## 6. 构建与运行流程

### 构建

**本关不需要构建。** 没有新代码、没有新消息类型。

唯一和构建有关的一件事是**踩坑 6**：不带 `--symlink-install` 的 build
会把 editable 安装降级成拷贝，之后改 `.py` 就不生效了。要恢复：

```bash
rm -rf build/hello_ros install/hello_ros
colcon build --packages-select hello_ros --symlink-install
```

恢复后正确的形状是**三段软链**：

```
install/hello_ros/lib/python3.14/site-packages/hello-ros.egg-link
        ↓ 内容指向
build/hello_ros
        ↓ 其中的 build/hello_ros/hello_ros 是软链
src/hello_ros/hello_ros/          ← 真身在这儿
```

验证：

```bash
ls -ld build/hello_ros/hello_ros     # 开头是 l 才对
stat -c '%i' src/hello_ros/hello_ros/talker.py build/hello_ros/hello_ros/talker.py
#   两个 inode 号相同 = 同一个文件
```

### 三条标准流程

#### ① 录

```bash
# 终端 A：数据源
ros2 run hello_ros talker

# 终端 B：录 10 秒
cd /tmp
ros2 bag record --topics /chatter -o bag1
#   数到 10，Ctrl+C（终端 B），再回终端 A Ctrl+C

# 验收
ros2 bag info bag1
ls -l bag1
```

#### ② 放

```bash
# 终端 B
cd /tmp
ros2 bag play bag1

# 终端 A
ros2 topic echo /chatter
```

#### ③ 判据实验（本关招牌）

```bash
# 第 0 步（每次都要）：清场
ros2 topic info /qos_hist          # 必须 Unknown topic '/qos_hist'

# 终端 A：起发布者（发 5 条就停，但活着）
ros2 topic pub -r 2 -t 5 -w 0 --keep-alive 60 \
    --qos-durability transient_local \
    /qos_hist std_msgs/msg/String "{data: hi}"
#   看到 publishing #5 之后，再等 5 秒

# 终端 B：⭐ 先验"这题不废"
ros2 topic info /qos_hist          # 必须 Publisher count: 1

# 终端 B：录 5 秒
cd /tmp
ros2 bag record --topics /qos_hist -o bag_tl
#   Ctrl+C

ros2 bag info bag_tl
```

### 验收清单

```bash
# ① 包真的存在且完整
ls -l bag1
#    期望：一个 .mcap + 一个 metadata.yaml

# ② 读得出来
ros2 bag info bag1
#    期望：Messages / Duration / Topic information 都有值

# ③ 回放时话题上有发布者
ros2 topic info /chatter
#    期望：Publisher count: 1（节点叫 rosbag2_player）

# ④ 收工：确认干净
ros2 topic info /qos_hist
#    期望：Unknown topic '/qos_hist'
```

---

## 7. 实测现象与结论 ⭐

### 7.1 ⭐⭐ 判据实验：只改一个词，5 条 vs 0 条

**这是本关的招牌，也是第 8 关"抽屉"的最终判决。**

设置：一个 `ros2 topic pub` 发布者，**2 Hz 发 5 条，发完停发但不退出**。
**等它确实停住之后**，才开始 `record`。两轮只改 `--qos-durability` 一个词。

| 发布者 durability | 发布者状态 | 录到 | `Duration` |
|---|---|---|---|
| `transient_local` | 活着 · 已停发 | **5 条** | **0.000030280s** |
| `volatile` | 活着 · 已停发 | **0 条** | 0.000000000s（时间戳 2262 年） |

**关键的第二步：录之前先验 `Publisher count: 1`。**

没有这一步，这道题**是废的**：

> 发布者**不在了** → 迟到订阅者收 0 条 ——
> **这一条两个模型都预测得出来**（"volatile 不留历史" vs "压根没人在发"），
> 所以它**证明不了任何事**。

**这就叫判据：不是多敲一条命令，是让两种解释分道扬镳。**

> 第一次做的时候漏了这一步，`bag_vol` 的 0 条就是一笔糊涂账 ——
> 那时候发布者已经跑了，0 条完全可能是"没人在发"。**重做（`bag_vol2`）才钉死。**

### 7.2 ⭐⭐ `Duration` 的公式

同一份 `talker`（1 Hz），两次不同的录制：

| 录制 | `Messages` | `Duration` | 关系 |
|---|---|---|---|
| 基线（我跑的） | 10 | 8.999874303s | 10 → 9 个间隔 |
| 课堂（你跑的） | 12 | 11.000075716s | 12 → 11 个间隔 |

**`Duration = (Messages − 1) × 消息间隔`。**

`Duration` 量的是**第一条到第三条消息跨了多远**，不是"你按了多久录制键"。

- 可以**比录制时长短**（第一条是开始录之后 0.5 秒才来的）
- 可以**比录制时长长**（你数到 10 才按停止，实际跨了 11 秒）

**它只跟"包里面的东西"有关，跟你手上的动作无关。**

### 7.3 ⭐⭐ 历史没有时间戳

`bag_tl` 的 `info`：

```
Duration:          0.000030280s
Start:             Sep 21 2026 20:00:55.895395327
End:               Sep 21 2026 20:00:55.895425607
Messages:          5
```

**5 条消息挤在 30 微秒里。**

它们当初是在 2 秒里（2 Hz × 5 条）被发出去的 —— **但那是发布者进程自己的事**。
reccorder 是**后来才加入**的，它**没听见那 5 次发布**，它是**接手了一坨已经存在于
别人内存里的历史**。

于是每条消息头上的时间戳 = **recorder 拿到它的那一刻**。5 条一起拿到
→ 时间戳几乎一模一样 → `Duration ≈ 0`。

> **历史没有时间戳，只有"我拿到你的那一刻"。**

**这一条的直接后果**：拿 `bag_tl` 去回放，那 5 条会**一瞬间全涌出来**，
而不是按原来的 2 Hz 排开。**因为包里存的就是这个。**

（这也解释了 §7.6 那个"漏开头"：对面是 VOLATILE 时，你晚一步就什么都没有。）

### 7.4 ⭐ 三张脸，一件事

见 §2.7。**VOLATILE = 没有抽屉。**

### 7.5 回放 = 一个普通发布者

回放进行中的 `ros2 topic info /chatter`：

```
Type: std_msgs/msg/String
Publisher count: 1
Subscription count: 1
```

`-v` 看节点名：**`rosbag2_player`**。

> **bag 没有任何魔法。回放就是起了个普通发布者，把消息一条条发出去。**
> 它和 `talker` 没有本质区别 —— 唯一的不同是：
> `talker` 的数据来自 `f'第 {count} 次心跳'`，`player` 的数据来自**磁盘**。

那条 `Subscription count: 1` 是谁？是**你自己开的那个 `ros2 topic echo`**。
`ros2 topic echo` **本身也是一个节点、一个订阅者**。
（这是第 1 关"CLI 工具本身就是节点"的又一次现身。）

### 7.6 ⭐ 未解之谜：回放开头可能漏第一条

同一份包、同样两条命令（echo 先起 5 秒，再 play），连跑 3 次：

| 第几次 | 收到 | 起点 |
|---|---|---|
| 1 | 12 条 | 第 6 → 第 17 |
| 2 | 12 条 | 第 6 → 第 17 |
| 3 | **11 条** | **第 7** → 第 17 ← 第 6 条丢了 |

**现象确定：回放开始时，开头几条可能被漏掉。**
（课堂上另一次只收到 8 条，是因为 echo 起得比 play 晚了几秒 ——
前面 4 条在订阅上之前就发过去了，这个**能解释**。）

**病因未知。** 有一个假说：

> `player` 是"开播那一刻才创建发布者"的，DDS 发现还没配完，
> 头一条就发出去、也就丢了 —— 加上 VOLATILE 不留历史，丢了就永远没了。

**但没有证据。** 按第 5 关 L3 那条规矩，它现在只能算「**现象**」，不能算「**病因**」。

**可用的旋钮**（留给下次挖）：`play -d <秒>`（延迟开播）、
`play --start-paused`（起来先暂停）、`-w` 之类。
关键是要设计出让**两个假说给出不同答案**的输入。

> ✅ **已结案** —— [第 10 关 §7.6](lesson-10-namespace.md) 把这个假说钉死了：
> 源码上 `player` **构造时建发布者**（`player.hpp:94-97`），
> 而 `-d` **睡在 `play()` 里**（`play_options.hpp:103`）——
> 所以 `-d` 多出来的那几秒，正是 **DDS 的配对窗口**。
> 判据实验：基线 9 次只收到 2 次完整包，加 `-d`（0.5/1/2/5 秒）后 **15/15 全齐**。
> **旋钮 `-d` 就是那道题的答案。**

### 7.7 那个 `2262 年`

见 §2.6。`9223372036.854775807` = int64 最大值 = 哨兵值 = "从来没有过"。

---

## 8. 踩坑记录

### ❌ 坑 1：`ros2 bag record` 不接位置参数了

**这版是 rosbag2 0.33.3。**

```bash
ros2 bag record -o bag1 /chatter
#   → ros2: error: unrecognized arguments: /chatter
```

看 `--help` 的 usage 行就知道 —— **位置参数在 usage 里根本没有**：

```
usage: ros2 bag record [-h] [-o OUTPUT] [-s {sqlite3,mcap}]
                       [--topics Topic [Topic ...]] ...
```

**正确写法**：`--topics /chatter`（或 `-a` / `--all-topics`）。

> ⚠️ **网上教程几乎全是位置参数写法**，照抄必挂。

### ❌ 坑 2：`ros2 topic pub -t` 会**等订阅者**（我自己造题时栽的）

第一次做判据实验，**两轮都录到 5 条** —— 明明一轮是 volatile，不该有历史。

根因在 `ros2 topic pub --help` 的一行字：

```
-w, --wait-matching-subscriptions WAIT_MATCHING_SUBSCRIPTIONS
    Wait until finding the specified number of matching subscriptions.
    Defaults to 1 when using "-1"/"--once"/"--times", otherwise defaults to 0.
```

**`-t 5` 的时候，`-w` 默认是 1** —— 它在**等订阅者**才肯发。

于是两轮里发布者都**卡在那儿等 recorder**，等 recorder 一订阅，它才现场发 5 条。
**测的根本不是"发完再录"，整道题作废。**

修法：加 **`-w 0`**（不等，立刻开闸）。

> **教训的形状**：**默认值也是逻辑**。`-t` 这个参数看着无害，
> 它背后却悄悄把 `-w` 从 0 改成了 1。
> 跟第 3 关那个"`>=` 悄悄变成 `>`"是同一个家族 —— **不报错，只是行为不是你以为的那样。**

### ❌ 坑 3：非终端环境下 `ros2 bag record` 只认 SIGTERM

在脚本里 `kill -INT`（= 终端里的 Ctrl+C）停录制，**完全无效**：

```
Sl   hrtimer_nanosleep    ros2 bag record --topics /chatter -o /tmp/l9/bag1
```

症状三连：**进程活着**、`.mcap` **0 字节**、**没有 `metadata.yaml`**、
`ros2 bag info` 报 `Could not find metadata in bag directory ...`。

**根因（源码）**：`ros2bag/verb/record.py:513` 只注册了 **SIGTERM**：

```python
signal.signal(signal.SIGTERM, signal_handler)   # 置 termination_requested
...
while not termination_requested.is_set():
    time.sleep(0.1)
...
finally:
    recorder.stop()                             # ← 只有走到这里才落盘
```

而 `rclpy.init()` 默认**接管 SIGINT**（静默关掉通信上下文），
recorder 的循环**不看** `rclpy.ok()`，所以那个 `except KeyboardInterrupt`
永远不会触发 → 卡在 `sleep(0.1)` 里转圈。

**那终端里 Ctrl+C 为什么好用？** 因为 rosbag2 的键盘线程把终端设成了 **raw 模式**，
Ctrl+C **不产生 SIGINT**，而是变成一个 `\x03` 字节被键盘线程读到 → 走另一条停止路径。
非 tty 下它先打 `stdin is not a terminal device. Keyboard handling disabled.`，
那条路径就没了。

> **`kill -TERM`（不是 `-INT`）**，然后留 2~3 秒等这句打出来再读文件：
> `Writing remaining messages from cache to the bag. It may take a while`

### ❌ 坑 4：废题的形状

第一轮做完 volatile，发布者已经被 `--keep-alive` 熬死了。
这时候看到 0 条，**它证明不了任何事**。

**判据的缺失让结论悬空。** 补上 `ros2 topic info` → `Publisher count: 1`，
0 条才变成"发布者还活着且停发了，volatile 就是不给"。

> **"跑了实验、有输出、没报错" ≠ "实验做了"。**
> 这是第 4 关"绿灯 ≠ 做了你想做的事"、第 6 关"构建成功 ≠ 能用"、
> 第 7 关"跑起来有输出 ≠ 实验做了"的**第四个成员**。

### ❌ 坑 5：`ls -l <目录>/` 会跟软链进去（我自己栽的）

查 `build/hello_ros/hello_ros` 是不是软链：

```bash
ls -l build/hello_ros/hello_ros/      # ❌ 末尾的 / 让它跟进了目标目录
#   → 列出一堆 -rw-rw-r-- 的 .py，看着像"拷贝"

ls -ld build/hello_ros/hello_ros      # ✅ 不带 / 、加 -d，才看得到它【本身】
#   → lrwxrwxrwx ... -> /home/l/ros2_learn_ws/src/hello_ros/hello_ros
```

我因此白下了一个"这是拷贝"的结论，还多跑了一次 build。

> **还是那条老规矩：先确认"尺子"量的是不是你要量的东西。**
> （同族：第 3 关的 flake8 配置、第 8 关的 markdownlint MD060、
> `pkill -f` 匹配命令行文本而不是节点名。）

### ❌ 坑 6：不带 `--symlink-install` 的 build 会把 editable 安装降级

`install/hello_ros/lib/python3.14/site-packages/` 处出现了两种形状：

| 形状 | 内容 | 改 `.py` 后 |
|---|---|---|
| **editable（软链）** | 只有一个 `hello-ros.egg-link` | **不用 build，重启节点即可** |
| **拷贝** | 一个真的 `hello_ros/` 目录，里面是 `.py` 的副本 | **必须 `colcon build`** |

**一次不带 `--symlink-install` 的 `colcon build` 就会把它降级成拷贝。**

恢复：

```bash
rm -rf build/hello_ros install/hello_ros
colcon build --packages-select hello_ros --symlink-install
```

验证口诀：**`ls -ld build/<包名>/<包名>` 开头是 `l`**（注意 `-d`，见坑 5）。

### 🔑 本关六条坑的公共形状

| 坑 | 一句话 |
|---|---|
| 1 | 命令的**写法**变了，而教程还是老的 |
| 2 | **默认值**也是逻辑，悄悄改了你以为的东西 |
| 3 | **换了个运行环境**（非 tty），同一套交互就失效了 |
| 4 | **判据缺失** → 结论悬空 |
| 5 | **尺子**量错了对象 |
| 6 | **构建方式**决定"改代码要不要重编" |

**坑 1/2/3 都是"环境变了但你以为没变"，坑 4/5/6 都是"你以为你在量 A，其实在量 B"。**

---

## 9. 自测题

### 9.1 课堂已覆盖（附答案，先自己答一遍再点开）

<details>
<summary><b>题 1：<code>ros2 bag record</code> 造出来的 <code>bag1</code>，是一个文件还是一个目录？里面有什么？</b></summary>

**是一个目录。** 里面两样东西：

```
bag1/
├── 0_bag1_2026_09_21-19_36_37.mcap     ← 数据（默认 mcap 格式）
└── metadata.yaml                        ← 索引
```

- `-o` 是 `--output`，但要的是**输出目录**
- 数据文件名**自带录制开始的日期-时间**，往同一目录录两次不会覆盖

</details>

<details>
<summary><b>题 2：<code>Messages: 12</code>、<code>Duration: 11.000075716s</code>。这两个数为什么差 1？</b></summary>

**因为 N 条消息只有 N−1 个间隔。**

`Duration = End − Start` = **第一条第最后一条的时间跨度**，
**不是"你按了多久录制键"**。

- 可以比录制时长短（第一条是开录之后 0.5 秒才来的）
- 可以比录制时长长（你数到 10 才按停止，实际跨了 11 秒）

**它只跟"包里面的东西"有关。** 详见 §7.2。

</details>

<details>
<summary><b>题 3：发布者 <code>TRANSIENT_LOCAL</code>、发完 5 条就停住不退。我这时候才开始录，能录到几条？<code>VOLATILE</code> 呢？</b></summary>

**TL → 5 条；volatile → 0 条。**

**但光看这个结果是不够的** —— 必须同时确认"录的时候发布者**还活着**"
（`ros2 topic info` 显示 `Publisher count: 1`），否则 0 条完全可能是"没人在发"。

**没有判据，这题就是废题。** 详见 §7.1。

</details>

<details>
<summary><b>题 4：<code>bag_tl</code> 里 5 条消息的 <code>Duration</code> 是本该有的 2 秒吗？</b></summary>

**不是。是 <code>0.000030280</code> 秒。**

因为这 5 条**不是"被发过来"的，是"从抽屉里拿出来"的**。
recorder 没听见当初那 5 次发布，它是**接手了一坨已经存在的历史**，
于是每条的时间戳 = **它拿到的那一刻**，5 条一起拿到 → 几乎同一时刻。

> **历史没有时间戳，只有"我拿到你的那一刻"。**

**后果**：拿这个包回放，5 条会**一瞬间全涌出来**。详见 §7.3。

</details>

<details>
<summary><b>题 5：<code>ros2 bag info</code> 打出一段空包，怎么一眼认出它是空的？</b></summary>

**三副面孔，同时出现：**

1. `Messages: 0`
2. `Topic information:` 后面**整段空掉**（连话题名都没记）
3. 时间戳是 **`Apr 12 2262`** —— `9223372036.854775807` = **int64 最大值** = 哨兵值

**另外**：`Bag size: 1.9 KiB` —— **空包也是包，文件照样建出来**。
**"有文件"和"有数据"是两件事。** 详见 §2.6。

</details>

<details>
<summary><b>题 6：回放的时候 <code>/chatter</code> 上有几个发布者？</b></summary>

**1 个**，节点名叫 **`rosbag2_player`**。

> **bag 没有魔法。回放就是起了个普通发布者，把消息一条条发出去。**

它和 `talker` 的唯一区别是：数据来自**磁盘**而不是 `f'第 {count} 次心跳'`。

（如果同时看到 `Subscription count: 1`，那多半是**你自己开的 `ros2 topic echo`** ——
CLI 工具本身就是节点，第 1 关的老账。）

</details>

### 9.2 留给下次的思考题（无答案）

1. **`-r` 实验**：先预测 —— `ros2 bag play -r 2 bag_tl` 和 `-r 0.1`，
   分别会看到什么？**什么变了，什么没变？**
   （提示：注意 `bag_tl` 的 `Duration` 是 0.000030280 秒 —— 这个包身上有个反转。）

2. **`best_effort` 第三个判据实验**：把 §7.1 那条命令的
   `--qos-reliability` 换成 `best_effort` 再录一轮，`record` 默认能录到吗？
   先预测，再跑。

3. ~~**"漏开头"之谜**（§7.6）~~ ✅ **已在第 10 关结案**，见 [§7.6 那个引用块](lesson-10-namespace.md)。
   答案就是 `play -d`。**但"为什么"值得你自己再推一遍。**

4. **`play` 发布的 QoS 从哪来？** 用 `ros2 topic info /chatter -v` 看
   `rosbag2_player` 的 `Reliability` / `Depth` / `Durability`，
   和当初 `talker` 写的 `create_publisher(String, 'chatter', 10)` 对一对。
   **谁把 QoS 存进包的？** 如果录制时用了 `--qos-profile-overrides-path` 呢？

5. **换个数据源再来一次**：用第 6 关的 `status_talker`（多字段 + 嵌套消息）
   录一段，`ros2 bag info` 的 `Type` 显示什么？回放时 `ros2 topic echo` 打出来的
   结构和你当初 `RobotStatus.msg` 写的一样吗？

---

## 10. 附：跨关待办

### ① ⚠️ 「先预测再运行」—— 本关**又跳过了**（第二次）

题 9-1 你答了 3 个（`文件` / `15` / `不会`），**第 4 个没答**；
题 9-2 答了 3 个（`自己退出` / `第 6～17` / `每秒一次` + `0`）；
**题 9-3 的 3 个预测，一个都没写就开始跑了。**

第 7 关题 7-3 也是这个形状。**这次没翻车，是因为结果本来就明显。**

> **但"看到结果才觉得显然"和"事前推断出来"是两种能力。**
> 预测的价值在于制造「预期」，好让「预期 − 实际」把异常**顶出来**。
> **先跑再看，这个差永远是 0。**

### ② ⚠️ 残留进程 —— 第 4 次

本关的形状变了：不再是"旧的服务端污染日志"，而是
**一次 `ros2 topic echo` 从始至终没 Ctrl+C**，一直挂在那儿当订阅者。

它没直接毁掉结论，但它让"第一次贴的 echo 输出到底属于哪一次回放"
变成一笔糊涂账 —— **你没法追溯屏幕上出现过的东西属于哪次运行**。

**已固化的动作**：做任何实验之前先 `ros2 topic info /话题名`，
判据是 **`Unknown topic`**。

### ③ ⚠️ 「贴输出」—— 这次的新毛病是**不分段**

你贴的 `第 17 次心跳` 那条，是"上一次回放的尾巴 + 这一次的完整 12 条"，
但两段之间没有分界，看上去就像"这一次多了一条"。

**贴之前扫一眼：我贴的是几次运行？要不要标一下？**

（好的一面：本关你**主动**去查了 `ros2 topic info` 并自己读出了
`Publisher count: 1` —— 验证权在你手上的又一次。）

### ④ ⭐ 本关真正做到的一件事：**判据**

题 9-3 那次"先验 `Publisher count: 1` 再录"，是**你自己执行的**。
这一步把"可能废掉的题"变成了"钉死的结论"。

**这是第 6 关"好测试 = 新旧答案不同的输入"、第 8 关"判据实验"的第三次应用，
而且是第一次由你主动完成。** 下一关继续。

### ⑤ 收尾时修的一个环境问题

不带 `--symlink-install` 的 build 把 editable 安装降级成了拷贝，
已经用 `rm -rf build/hello_ros install/hello_ros` +
`colcon build --packages-select hello_ros --symlink-install` 恢复。
**"改 `.py` 不用 build"这个礼物回来了**（验证：`ls -ld build/hello_ros/hello_ros` 是 `l`）。

---

## 附：本关命令速记卡

```bash
# ---------- 录 ----------
ros2 bag record --topics /chatter -o bag1
#   ⚠️ 没有位置参数写法！必须 --topics
#   Ctrl+C 停止（终端里好用；脚本里要 kill -TERM，见坑 3）

# ---------- 问 ----------
ros2 bag info bag1
#   重点看：Messages / Duration / Start / End / Topic information

# ---------- 放 ----------
ros2 bag play bag1                 # 1:1
ros2 bag play -r 2.0 bag1          # 2 倍速
ros2 bag play -d 3.0 bag1          # 延迟 3 秒
ros2 bag play --start-paused bag1  # 起来先暂停
#   空格=暂停  →=单步  ↑↓=调速

# ---------- 判据实验（本关招牌）----------
ros2 topic info /qos_hist          # 第 0 步：必须 Unknown topic '/qos_hist'

ros2 topic pub -r 2 -t 5 -w 0 --keep-alive 60 \
    --qos-durability transient_local \
    /qos_hist std_msgs/msg/String "{data: hi}"
#                ↑            ↑
#           只改这一个词    -w 0 千万别删（删了它会等订阅者，实验作废）
#   换成 volatile 再跑一轮

ros2 topic info /qos_hist          # ⭐ 录之前必须 Publisher count: 1（否则是废题）

ros2 bag record --topics /qos_hist -o bag_tl
ros2 bag info bag_tl

# ---------- 排查 ----------
ros2 topic info /话题名             # 做实验之前必敲
ros2 topic info /话题名 --verbose   # 看 QoS、看节点名
ros2 topic hz /话题名               # 看节奏
ps -eo pid,etimes,args | grep ros2  # etimes = 活了多少秒，几百秒的必是残留

# ---------- 环境：恢复 editable 安装 ----------
rm -rf build/hello_ros install/hello_ros
colcon build --packages-select hello_ros --symlink-install
ls -ld build/hello_ros/hello_ros    # 开头是 l 才对（注意 -d！）

# ---------- 测试 ----------
colcon test --packages-select hello_ros
colcon test-result --verbose
```

---

## 相关笔记

- [第 1 关 · 话题](lesson-01-topic.md) —— "后启动的订阅者收不到历史消息"，本关给出完整答案
- [第 8 关 · QoS 策略](lesson-08-qos.md) —— 本关的判据实验直接吃它的老本（"抽屉"）
- [第 6 关 · 自定义消息](lesson-06-custom-message.md) —— "好测试 = 新旧答案不同的输入"
- [第 7 关 · 执行器与回调组](lesson-07-executor.md) —— 另一个"不写就有一堆默认行为"的旋钮
- [专项 01 · 怎么看日志](skill-01-log-reading.md) —— 本关的 WARN 和进度条都是线索
