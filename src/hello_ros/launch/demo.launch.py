from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    """一次启动 param_talker 和 listener."""
    # TODO 1：声明两个 launch 参数
    #   message 默认 'hello'，period 默认 '1.0'
    #   ⚠️ default_value 一律写【字符串】
    msg_arg = DeclareLaunchArgument(
        'message',
        default_value='hello',
        description='发布的内容',
    )
    period_arg = DeclareLaunchArgument(
        'period',
        default_value='1.0',
        description='每隔几秒发一次',
    )

    return LaunchDescription([
        msg_arg,
        period_arg,

        # TODO 2：启动 param_talker，把两个 launch 参数喂给它
        Node(
            package='hello_ros',
            executable='param_talker',
            parameters=[{
                'message': LaunchConfiguration('message'),
                'period': LaunchConfiguration('period'),
            }],
        ),

        # TODO 3：再起一个 listener（它不吃参数，照题 4-1 的写法）
        Node(
            package='hello_ros',
            executable='listener',
        ),
    ])
