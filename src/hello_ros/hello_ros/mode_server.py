from hello_ros_interfaces.srv import SetMode
import rclpy
from rclpy.node import Node


class ModeServer(Node):

    def __init__(self):
        super().__init__('mode_server')
        self.srv = self.create_service(SetMode, 'set_mode', self.handle_set_mode)
        self.get_logger().info('模式服务已启动')

    def handle_set_mode(self, request, response):
        if request.mode in (0, 1, 2):
            response.success = True
            response.message = f'模式已切换到 {request.mode}'
        else:
            response.success = False
            response.message = '非法模式，只接受 0/1/2'

        return response


def main(args=None):
    rclpy.init(args=args)
    node = ModeServer()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
