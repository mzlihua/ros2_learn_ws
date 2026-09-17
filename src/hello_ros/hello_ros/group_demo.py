import time

import rclpy
from rclpy.callback_groups import ReentrantCallbackGroup
from rclpy.executors import MultiThreadedExecutor
from rclpy.node import Node
from std_msgs.msg import String          # 消息类型：std_msgs 包里的 String


class GroupDemo(Node):
    """一个慢订阅者 + 一个 0.5 秒定时器：看回调组到底管不管事."""

    def __init__(self):
        super().__init__('group_demo')

        # ⭐ 本题唯一的变量，换这一行就换一种行为：
        #     ReentrantCallbackGroup()      → 可以并行：慢回调睡觉时定时器照常滴答
        #     self.default_callback_group   → 同组互斥：慢回调睡觉时定时器完全停摆
        group = ReentrantCallbackGroup()

        self.create_subscription(String, 'chatter', self.cb_slow, 10,
                                 callback_group=group)
        self.create_timer(0.5, self.tick, callback_group=group)

    def cb_slow(self, msg):
        """慢回调：打印 → 睡 2 秒 → 打印."""
        self.get_logger().info('慢回调：开始睡 2 秒')
        time.sleep(2)
        self.get_logger().info('慢回调：睡醒了')

    def tick(self):
        self.get_logger().info('定时器：滴答')


def main(args=None):
    with rclpy.init(args=args):
        node = GroupDemo()
        rclpy.spin(node, executor=MultiThreadedExecutor())


if __name__ == '__main__':
    main()
