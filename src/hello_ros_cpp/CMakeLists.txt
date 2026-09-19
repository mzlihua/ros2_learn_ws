cmake_minimum_required(VERSION 3.20)
project(hello_ros_cpp)

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

# find dependencies
find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(std_msgs REQUIRED)
find_package(hello_ros_interfaces REQUIRED)
# uncomment the following section in order to fill in
# further dependencies manually.
# find_package(<dependency> REQUIRED)

add_executable(hello_cpp src/hello_cpp.cpp)
target_include_directories(hello_cpp PUBLIC
  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
  $<INSTALL_INTERFACE:include/${PROJECT_NAME}>)
target_compile_features(hello_cpp PUBLIC c_std_17 cxx_std_20)  # Require C17 and C++20
target_link_libraries(hello_cpp rclcpp::rclcpp)

add_executable(talker src/talker.cpp)
target_link_libraries(talker rclcpp::rclcpp ${std_msgs_TARGETS})

# ---- 第 1 步：C++ 版订阅者（订阅 /chatter，和 talker.cpp 同一个消息类型）----
# 这三行我替你写好了。等第 2 步换成 RobotStatus 时，轮到你照它们改。
add_executable(listener src/listener.cpp)
target_link_libraries(listener rclcpp::rclcpp ${std_msgs_TARGETS})

add_executable(status_listener src/status_listener.cpp)
target_link_libraries(status_listener rclcpp::rclcpp ${hello_ros_interfaces_TARGETS})
# ============================================================================
# TODO 5：把 status_listener.cpp 接进来。一共 4 处，都在这个文件里。
#
#   ⚠️ 这 4 处不做完，你 build 多少次都不会看见 status_listener.cpp 的报错 ——
#      编译器压根不知道有这个文件。先做完这里，再去填那个 .cpp。
#
#   ① 上面第 11 行附近：find_package(...)  现在只 find 了 rclcpp / std_msgs
#        → 消息类型换了包，这里得跟着加一行。去文件最上头看现有写法，照着写。
#
#   ② 上面 add_executable / target_link_libraries（就在本段上方两行）
#        → 照 listener 那两行【复制一份改成 status_listener】。
#          源文件是 src/status_listener.cpp。
#
#   ③ 下面 install(TARGETS ...)  → 把 status_listener 加进列表
#        ⚠️ cpp-01 坑 8 就是这个：漏了这处，build 绿灯，
#           `ros2 run` 报 "No executable found"。想体验一次就故意不加。
#
#   ④ package.xml 要不要补依赖 —— 先【不补】，看 build 会不会报错。
#      嵌套消息（RobotStatus 里的 geometry_msgs/Point）这个问题我没验证过，
#      正好拿它做实验：报错了就补，不报错就说明不用补。
# ============================================================================

install(TARGETS hello_cpp talker listener status_listener
  DESTINATION lib/${PROJECT_NAME})

if(BUILD_TESTING)
  find_package(ament_lint_auto REQUIRED)
  # the following line skips the linter which checks for copyrights
  # comment the line when a copyright and license is added to all source files
  set(ament_cmake_copyright_FOUND TRUE)
  # the following line skips cpplint (only works in a git repo)
  # comment the line when this package is in a git repo and when
  # a copyright and license is added to all source files
  set(ament_cmake_cpplint_FOUND TRUE)
  # the following line skips uncrustify (which enforces the ROS C++ style guide:
  # 2-space indent, attached braces). This package is a handwriting exercise and
  # keeps 4-space / Allman style for consistency with the Python side.
  # comment the line to switch to the ROS style guide.
  set(ament_cmake_uncrustify_FOUND TRUE)
  ament_lint_auto_find_test_dependencies()
endif()

ament_package()
