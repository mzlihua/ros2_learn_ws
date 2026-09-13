from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    """启动一个 talker 节点."""
    return LaunchDescription([
        # TODO 1：加一个"启动节点"的动作
        #   包名 = hello_ros，可执行名 = talker
        #   —— 提示：跟 `ros2 run hello_ros talker` 是同一对词
        Node(
            package='hello_ros',
            executable='talker',
        ),
    ])
