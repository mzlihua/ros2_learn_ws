import time

from example_interfaces.action import Fibonacci

import rclpy
from rclpy.action import ActionServer, CancelResponse
from rclpy.executors import MultiThreadedExecutor
from rclpy.node import Node


class FibServer(Node):
    """斐波那契动作服务端：边算边播报进度，支持中途取消."""

    def __init__(self):
        super().__init__('fib_server')
        self._action_server = ActionServer(
            self,
            Fibonacci,
            'fibonacci',
            execute_callback=self.execute_callback,
            cancel_callback=self.cancel_callback)

    def execute_callback(self, goal_handle):
        """算出 order 项斐波那契，每算一项播报一次."""
        self.get_logger().info(f'收到目标：order={goal_handle.request.order}')

        feedback_msg = Fibonacci.Feedback()
        feedback_msg.sequence = [0, 1]

        for i in range(1, goal_handle.request.order):
            if goal_handle.is_cancel_requested:
                self.get_logger().info('目标被取消')
                goal_handle.canceled()
                result = Fibonacci.Result()
                result.sequence = feedback_msg.sequence
                return result

            feedback_msg.sequence.append(
                feedback_msg.sequence[i] + feedback_msg.sequence[i - 1])
            goal_handle.publish_feedback(feedback_msg)
            time.sleep(1)

        goal_handle.succeed()

        result = Fibonacci.Result()
        result.sequence = feedback_msg.sequence

        self.get_logger().info(f'返回结果：{result.sequence}')
        return result

    def cancel_callback(self, goal_handle):
        """服务端说"我让不让你取消"."""
        self.get_logger().info('收到取消请求')
        return CancelResponse.ACCEPT


def main(args=None):
    with rclpy.init(args=args):
        node = FibServer()
        rclpy.spin(node, executor=MultiThreadedExecutor())


if __name__ == '__main__':
    main()
