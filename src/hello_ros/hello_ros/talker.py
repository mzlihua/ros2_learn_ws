import rclpy
from rclpy.node import Node
from std_msgs.msg import String          # 消息类型：std_msgs 包里的 String


class Talker(Node):

    def __init__(self):
        super().__init__('talker')
        self.count = 0

        # TODO 1：创建发布者，话题名用 'chatter'，队列长度填 10
        self.pub = self.create_publisher(String, 'chatter', 10)

        self.timer = self.create_timer(1.0, self.tick)

    def tick(self):
        self.count += 1

        # TODO 2：造一个 String 消息对象，赋给 msg
        msg = String()

        # TODO 3：把文本塞进消息的 data 字段
        msg.data = f'第 {self.count} 次心跳'

        # TODO 4：调用发布者，把 msg 发出去
        self.pub.publish(msg)

        self.get_logger().info(f'发布: {msg.data}')


def main(args=None):
    rclpy.init(args=args)
    node = Talker()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
