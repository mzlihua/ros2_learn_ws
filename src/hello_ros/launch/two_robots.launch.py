from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    return LaunchDescription([
        Node(
            package='hello_ros',
            executable='param_talker',
            namespace='robot1',
            parameters=[{'message': '一号机'}]
        ),
        Node(
            package='hello_ros',
            executable='param_talker',
            namespace='robot2',
            parameters=[{'message': '二号机'}]
        ),
        Node(
            package='hello_ros',
            executable='listener',
            namespace='robot1',
        ),
        Node(
            package='hello_ros',
            executable='listener',
            namespace='robot2',
        ),
    ])
