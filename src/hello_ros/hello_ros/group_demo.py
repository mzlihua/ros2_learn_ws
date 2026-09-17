import time

import rclpy
from rclpy.callback_groups import MutuallyExclusiveCallbackGroup
from rclpy.executors import MultiThreadedExecutor
from rclpy.node import Node
from std_msgs.msg import String          # 消息类型：std_msgs 包里的 String


class GroupDemo(Node):
    """一个慢订阅者 + 一个 0.5 秒定时器：看回调组到底管不管事."""

    def __init__(self):
        super().__init__('group_demo')

        # ⭐ 这个文件要回答一句话：慢回调睡那 2 秒时，定时器还滴不滴答？
        #    答案由两个决定拼出来，下面两行各管一个，必须分开看。
        #
        #    【决定一】慢回调进哪个组 —— 决定"它会不会挡别人 / 会不会叠自己"
        #      MutuallyExclusiveCallbackGroup()  组内一次只跑一个回调，
        #                                        慢回调排自己的队，不占用外人
        #      ReentrantCallbackGroup()          组内可同时跑多个，慢回调会
        #                                        自己叠自己（实测 3 个一起睡）
        #      self.default_callback_group       和定时器挤同一组，定时器只能
        #                                        排队等它睡完（实测 0 次滴答）
        #
        #    【决定二】定时器进哪个组 —— 决定"它会不会被别人挡住"
        #
        #    本文件的答案：慢回调 → 独立互斥组；定时器 → 默认组。
        #    效果：定时器 0.5 秒照常滴答（实测 2 秒睡里滴了 4 次），
        #          慢回调之间仍互斥，不重叠（"开始睡"从没连着出现两次）。
        #
        #    关键：可重入组是"允许重叠"，不是"允许并行"。
        #          想既不挡别人、又不叠自己，只能分成两个互斥组。
        group = MutuallyExclusiveCallbackGroup()

        self.create_subscription(String, 'chatter', self.cb_slow, 10,
                                 callback_group=group)          # 决定一
        self.create_timer(0.5, self.tick,
                          callback_group=self.default_callback_group)  # 决定二

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
