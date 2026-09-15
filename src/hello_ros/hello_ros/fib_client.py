from example_interfaces.action import Fibonacci

import rclpy
from rclpy.action import ActionClient
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node


class FibClient(Node):
    """斐波那契动作客户端：发目标、收进度、拿结果，数到第 3 条进度就叫停."""

    def __init__(self):
        super().__init__('fib_client')
        self._action_client = ActionClient(self, Fibonacci, 'fibonacci')
        self._goal_handle = None          # 我发出去的那个目标
        self._feedback_count = 0

    def send_goal(self, order):
        """发目标。注意：它发完就返回，不等结果."""
        self.get_logger().info('等待动作服务端...')
        self._action_client.wait_for_server()

        goal_msg = Fibonacci.Goal()
        goal_msg.order = order

        self.get_logger().info(f'发送目标：order={order}')
        self._send_goal_future = self._action_client.send_goal_async(
            goal_msg,
            feedback_callback=self.feedback_callback)
        self._send_goal_future.add_done_callback(self.goal_response_callback)

    def goal_response_callback(self, future):
        """服务端说"我接不接这个活"."""
        goal_handle = future.result()
        if not goal_handle.accepted:
            self.get_logger().info('目标被拒绝')
            return

        self.get_logger().info('目标被接受，开始等结果')
        self._goal_handle = goal_handle
        self._get_result_future = goal_handle.get_result_async()
        self._get_result_future.add_done_callback(self.get_result_callback)

    def feedback_callback(self, feedback):
        """每收到一次进度播报就打印一次，数到第 3 条就取消."""
        self._feedback_count += 1
        self.get_logger().info(
            f'收到进度({self._feedback_count})：{feedback.feedback.sequence}')

        if self._feedback_count == 3:
            self.get_logger().info('>>> 够了，我要叫停')
            self._goal_handle.cancel_goal_async()

    def get_result_callback(self, future):
        """结果到了."""
        self.get_logger().info(f'最终结果：{future.result().result.sequence}')
        self.get_logger().info(f'最终状态：{future.result().status}')
        rclpy.shutdown()


def main(args=None):
    try:
        with rclpy.init(args=args):
            node = FibClient()
            node.send_goal(30)
            rclpy.spin(node)
    except (KeyboardInterrupt, ExternalShutdownException):
        pass


if __name__ == '__main__':
    main()
