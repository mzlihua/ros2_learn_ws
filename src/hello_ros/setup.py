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
    ],
    package_data={'': ['py.typed']},
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='mzlihua',
    maintainer_email='3581703344@qq.com',
    description='TODO: Package description',
    license='TODO: License declaration',
    extras_require={
        'test': [
            'pytest',
        ],
    },
    entry_points={
        'console_scripts': [
            'hello_node = hello_ros.hello_node:main',
            # TODO 5：格式是 '终端里敲的名字 = 包名.文件名:函数名'
            'talker = hello_ros.talker:main',
            
            'listener = hello_ros.listener:main',
            'add_server = hello_ros.add_server:main',
            'add_client = hello_ros.add_client:main',
            #   终端名用 talker，文件就是刚写的 talker.py，函数是 main
        ],
    },

)
