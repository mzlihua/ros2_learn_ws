from example_interfaces.srv import AddTwoInts      # 服务类型
import rclpy
from rclpy.node import Node


class AddServer(Node):

    def __init__(self):
        super().__init__('add_server')             # 节点名
        self.srv = self.create_service(AddTwoInts, 'add_two_ints', self.handle_add)
        self.get_logger().info('加法服务已启动')

    def handle_add(self, request, response):
        response.sum = request.a + request.b
        return response


def main(args=None):
    rclpy.init(args=args)
    node = AddServer()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
