from rcl_interfaces.msg import SetParametersResult
import rclpy
from rclpy.node import Node
from std_msgs.msg import String


class ParamTalker(Node):
    """参数化发布者：发什么、发多快、发几条都能在运行时改."""

    def __init__(self):
        super().__init__('param_talker')

        # 声明 = 注册，一辈子一次（见笔记 §2.3）
        self.declare_parameter('message', 'hello')
        self.declare_parameter('period', 1.0)
        self.declare_parameter('max_count', 0)

        self.count = 0
        self.pub = self.create_publisher(String, 'chatter', 10)

        # 周期在创建定时器时就被"焊死"，之后改参数不会自动跟上（见笔记 §2.5）
        self.timer = self.create_timer(self.get_parameter('period').value, self.tick)

        self.add_on_set_parameters_callback(self.on_param_set)

        self.get_logger().info('param_talker 起来了')

    def tick(self):
        # 每次【现读】message，所以运行时改了立刻生效
        msg = String()
        msg.data = self.get_parameter('message').value
        self.pub.publish(msg)

        self.count += 1

        if 0 < self.get_parameter('max_count').value <= self.count:
            self.get_logger().info('停止定时器')
            self.timer.cancel()

    def on_param_set(self, params):
        """外部 ros2 param set 时被调用，返回 SetParametersResult 决定放行还是拒绝."""
        for p in params:
            self.get_logger().info(f'{p.name}')

            if p.name == 'period':
                # 回调触发时参数【还是旧值】，所以这里能拿它跟新值比
                if p.value < 0.1:
                    return SetParametersResult(
                        successful=False,
                        reason=f'period 不能小于 0.1 秒（你填了 {p.value}）',
                    )
                elif p.value != self.get_parameter('period').value:
                    # 周期没法原地改，只能拆掉重建
                    self.destroy_timer(self.timer)
                    self.timer = self.create_timer(p.value, self.tick)

            elif p.name == 'max_count':
                if self.timer.is_canceled():                    # ① 定时器停了没？
                    if p.value == 0 or p.value > self.count:    # ② 新值还有得发吗？
                        self.timer.reset()                      # ③ 复活它

        return SetParametersResult(successful=True)


def main(args=None):
    rclpy.init(args=args)        # 1) 初始化 rclpy
    node = ParamTalker()         # 2) 创建节点
    try:
        rclpy.spin(node)         # 3) 阻塞循环，直到 Ctrl+C
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()      # 4) 销毁节点
        rclpy.shutdown()         # 5) 关闭 rclpy


if __name__ == '__main__':
    main()
