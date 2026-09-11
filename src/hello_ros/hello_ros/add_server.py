import rclpy
from rclpy.node import Node
from example_interfaces.srv import AddTwoInts      # 服务类型


class AddServer(Node):

    def __init__(self):
        super().__init__('add_server')             # 节点名
        # TODO 1：创建服务。三要素 = 服务类型、服务名、收到请求时的回调函数
        #         服务名就用 'add_two_ints'（和题目 1 的 demo 同名，方便对照）
        self.srv = self.create_service(AddTwoInts, 'add_two_ints', self.handle_add)
        self.get_logger().info('加法服务已启动')

    def handle_add(self, request, response):
        # TODO 2：把 request 里的 a 和 b 相加，结果写进 response.sum
        response.sum = request.a + request.b
        # TODO 3：返回 response
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
