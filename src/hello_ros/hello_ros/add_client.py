import rclpy
from rclpy.node import Node
from example_interfaces.srv import AddTwoInts


def main(args=None):
    rclpy.init(args=args)
    node = Node('add_client')          # 这次不用写类，直接拿 Node 用

    # TODO 4：创建客户端（类型、服务名）
    client = node.create_client(AddTwoInts, 'add_two_ints')

    # TODO 5：等服务端上线（给 1 秒耐心）。返回 False 就报错、干净退出
    if not client.wait_for_service(timeout_sec=1.0):
        node.get_logger().error('没找到 add_two_ints 服务，服务端开了吗？')
        node.destroy_node()
        rclpy.shutdown()
        return

    # TODO 6：造请求，a 填 3、b 填 4
    request = AddTwoInts.Request()
    request.a = 3
    request.b = 4

    # TODO 7：异步发送，接住 future
    future = client.call_async(request)

    # TODO 8：spin 这个节点，直到 future 有结果
    rclpy.spin_until_future_complete(node, future)

    # TODO 9：从 future 里取出响应，打印 3 + 4 = 7
    response = future.result()
    node.get_logger().info(f'{request.a} + {request.b} = {response.sum}')

    node.destroy_node()
    rclpy.shutdown()


if __name__ == '__main__':
    main()
