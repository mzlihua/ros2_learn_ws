import rclpy
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy
from std_msgs.msg import String


class QosTalker(Node):
    """发 5 条就闭嘴但节点不退：让晚来的订阅者有机会看见"历史"."""

    def __init__(self):
        super().__init__('qos_talker')

        self.declare_parameter('depth', 3)
        depth = self.get_parameter('depth').value

        qos = QoSProfile(
            history=HistoryPolicy.KEEP_LAST,
            depth=depth,
            reliability=ReliabilityPolicy.RELIABLE,
            durability=DurabilityPolicy.TRANSIENT_LOCAL,
        )

        self.count = 0
        self.pub = self.create_publisher(String, 'qos_hist', qos)
        self.timer = self.create_timer(0.5, self.tick)

    def tick(self):
        """发一条；发满 5 条就收手."""
        if self.count == 5:
            return
        self.count += 1
        msg = String()
        msg.data = f'第{self.count}条'
        self.pub.publish(msg)
        self.get_logger().info(f'发了 {msg.data}')


def main(args=None):
    rclpy.init(args=args)
    node = QosTalker()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
