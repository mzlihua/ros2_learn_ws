from example_interfaces.srv import AddTwoInts
import rclpy
from rclpy.node import Node


def main(args=None):
    rclpy.init(args=args)
    node = Node('add_client')          # 这次不用写类，直接拿 Node 用

    client = node.create_client(AddTwoInts, 'add_two_ints')

    if not client.wait_for_service(timeout_sec=1.0):
        node.get_logger().error('没找到 add_two_ints 服务，服务端开了吗？')
        node.destroy_node()
        rclpy.shutdown()
        return

    request = AddTwoInts.Request()
    request.a = 3
    request.b = 4

    future = client.call_async(request)

    rclpy.spin_until_future_complete(node, future)

    response = future.result()
    node.get_logger().info(f'{request.a} + {request.b} = {response.sum}')

    node.destroy_node()
    rclpy.shutdown()


if __name__ == '__main__':
    main()
