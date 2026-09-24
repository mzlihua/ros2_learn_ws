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
find_package(rclcpp_components REQUIRED)
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

# ---- 第 11 关：把 Talker 做成"组件"（能被容器装载的东西）--------------------
# ① 是 add_library 不是 add_executable —— 组件是一份【库】，不是一个【程序】。
#    程序有 main，自己跑；库没有 main，等着被别人 dlopen 装载。
# ② 源文件是 talker_component.cpp（新造的那份），不是原件 talker.cpp。
# ③ rclcpp_components::component 只有组件才链，普通可执行文件不需要。
# ④ register_nodes 是"登记表"那一处：漏了它，build 全绿，
#    但 `ros2 component types` 里永远找不到 Talker。
add_library(talker_component SHARED src/talker_component.cpp)
target_link_libraries(talker_component
  rclcpp::rclcpp
  rclcpp_components::component
  ${std_msgs_TARGETS})
rclcpp_components_register_nodes(talker_component "Talker")

# ---- 第 1 步：C++ 版订阅者（订阅 /chatter，和 talker.cpp 同一个消息类型）----
# 这三行我替你写好了。等第 2 步换成 RobotStatus 时，轮到你照它们改。
add_executable(listener src/listener.cpp)
target_link_libraries(listener rclcpp::rclcpp ${std_msgs_TARGETS})

add_executable(status_listener src/status_listener.cpp)
target_link_libraries(status_listener rclcpp::rclcpp ${hello_ros_interfaces_TARGETS})
# ---- status_listener（cpp-02）：4 处接线的落点，供以后照抄 ----
#   ① find_package(hello_ros_interfaces)  ② add_executable + target_link_libraries
#   ③ install(TARGETS ...) 里列名字  ④ package.xml —— **不用补**：
#      嵌套的 geometry_msgs/Point 由接口包自己传递，实测不补也不报错
#      （与第 6 关「嵌套消息的两处 DEPENDENCIES」是同一件事，那次是 Python 包）。

install(TARGETS hello_cpp talker listener status_listener
  DESTINATION lib/${PROJECT_NAME})

# ---- 第 11 关：组件的 .so 装到 lib/，【不是】lib/${PROJECT_NAME}/ ----
# 上面那 4 个是"程序"，装在包专属的 lib/hello_ros_cpp/ 下，只有这个包自己用。
# 组件是"库"，容器要拿着 ament 索引里记的路径 "lib/libtalker_component.so"
# 去 dlopen —— 装错层级 = 索引挂号了、东西却不在那儿 = load 时找不到库。
install(TARGETS talker_component
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)

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
