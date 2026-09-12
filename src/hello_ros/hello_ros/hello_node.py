import rclpy
from rclpy.node import Node


class HelloNode(Node):
    """一个最小 ROS 2 节点：每 1 秒打印一次心跳."""

    def __init__(self):
        super().__init__('hello_node')            # 节点名（ros2 node list 里会看到）
        self.count = 0
        # 定时器：每 1.0 秒调用一次 self.tick，代替 while+sleep
        self.timer = self.create_timer(1.0, self.tick)
        self.get_logger().info('hello_node 起来了')

    def tick(self):
        self.count += 1
        self.get_logger().info(f'第 {self.count} 次心跳')


def main(args=None):
    rclpy.init(args=args)        # 1) 初始化 rclpy
    node = HelloNode()           # 2) 创建节点
    try:
        rclpy.spin(node)         # 3) 阻塞循环，直到 Ctrl+C
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()      # 4) 销毁节点
        rclpy.shutdown()         # 5) 关闭 rclpy


if __name__ == '__main__':
    main()
