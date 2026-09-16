from hello_ros_interfaces.msg import RobotStatus
import rclpy
from rclpy.node import Node


class StatusListener(Node):

    def __init__(self):
        super().__init__('status_listener')
        self.sub = self.create_subscription(
            RobotStatus, 'robot_status', self.callback, 10)

    def callback(self, msg):
        self.get_logger().info(
            f'收到: {msg.robot_name} 电量={msg.battery} mode={msg.mode} x={msg.position.x}')


def main(args=None):
    rclpy.init(args=args)
    node = StatusListener()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
