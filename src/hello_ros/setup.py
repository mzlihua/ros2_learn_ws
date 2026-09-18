from glob import glob
import os

from setuptools import find_packages, setup

package_name = 'hello_ros'

setup(
    name=package_name,
    version='0.0.0',
    packages=find_packages(exclude=['test']),
    data_files=[
        ('share/ament_index/resource_index/packages',
            ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
        (os.path.join('share', package_name, 'launch'), glob('launch/*.launch.py')),
    ],
    package_data={'': ['py.typed']},
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='mzlihua',
    maintainer_email='3581703344@qq.com',
    description='ROS 2 核心基础练习包：话题、服务、参数、launch、动作、自定义消息的示例节点',
    license='Apache-2.0',
    extras_require={
        'test': [
            'pytest',
        ],
    },
    entry_points={
        'console_scripts': [
            'hello_node = hello_ros.hello_node:main',
            'talker = hello_ros.talker:main',
            'listener = hello_ros.listener:main',
            'add_server = hello_ros.add_server:main',
            'add_client = hello_ros.add_client:main',
            'param_talker = hello_ros.param_talker:main',
            'fib_server = hello_ros.fib_server:main',
            'fib_client = hello_ros.fib_client:main',

            'status_talker = hello_ros.status_talker:main',
            'status_listener = hello_ros.status_listener:main',

            'mode_server = hello_ros.mode_server:main',
            'mode_client = hello_ros.mode_client:main',

            'group_demo = hello_ros.group_demo:main',
            'qos_talker = hello_ros.qos_talker:main',

        ],
    },
)
