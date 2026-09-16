from hello_ros_interfaces.srv import SetMode
import rclpy
from rclpy.node import Node


def main(args=None):
    rclpy.init(args=args)
    node = Node('mode_client')

    client = node.create_client(SetMode, 'set_mode')

    if not client.wait_for_service(timeout_sec=1.0):
        node.get_logger().error('没找到 set_mode 服务，服务端开了吗？')
        node.destroy_node()
        rclpy.shutdown()
        return

    request = SetMode.Request()
    request.mode = 2

    future = client.call_async(request)
    rclpy.spin_until_future_complete(node, future)

    response = future.result()
    node.get_logger().info(
        f'请求 mode={request.mode} -> success={response.success}, '
        f'message={response.message}')

    node.destroy_node()
    rclpy.shutdown()
