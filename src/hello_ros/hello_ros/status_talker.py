from hello_ros_interfaces.msg import RobotStatus
import rclpy
from rclpy.node import Node


class StatusTalker(Node):

    def __init__(self):
        super().__init__('status_talker')
        self.count = 0
        self.pub = self.create_publisher(RobotStatus, 'robot_status', 10)
        self.timer = self.create_timer(1.0, self.tick)

    def tick(self):
        self.count += 1

        msg = RobotStatus()
        msg.robot_name = 'r2d2'
        msg.battery = 100.0 - (self.count * 5)
        msg.mode = self.count % 3
        msg.emergency = False

        msg.position.x = float(self.count)

        self.pub.publish(msg)
        self.get_logger().info(
            f'发布: {msg.robot_name} 电量={msg.battery} mode={msg.mode} x={msg.position.x}')


def main(args=None):
    rclpy.init(args=args)
    node = StatusTalker()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
