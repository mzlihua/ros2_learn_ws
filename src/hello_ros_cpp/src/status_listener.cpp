// ============================================================================
// C++ 支线 02 · 第 2 步：RobotStatus 订阅者（多字段 + 嵌套字段）
//
// 对照对象：src/hello_ros/hello_ros/status_listener.py
// 实测两边逐字段一致：
//   发布: r2d2 电量=65.0 mode=1 x=7.0        （Python status_talker）
//   收到: r2d2 电量=65.0 mode=1 x=7.0        （本文件）
//
// 相对 listener.cpp 只有 3 处变：
//   ① 消息类型    String  →  RobotStatus
//   ② include     包名跟着变（且头文件名是【蛇形】）
//   ③ 打印那一行   1 个字段 → 4 个字段，其中 position.x 是【嵌套】的
//
// ⚠️ 接线顺序：先在 CMakeLists.txt 里注册这个可执行文件（4 处），
//    编译器才看得见本文件。漏了那段，build 一百次也不会报这里的错。
// ============================================================================


// 【要点 1】消息头文件的路径规律：<包名>/msg/<消息名的蛇形>.hpp
//   ⚠️ 文件名是【蛇形】的：RobotStatus → robot_status.hpp
//      （第 6 关讲过：C++ 头文件用蛇形，Python 才用驼峰）
//   查法：ls install/hello_ros_interfaces/include/hello_ros_interfaces/hello_ros_interfaces/msg/
#include "rclcpp/rclcpp.hpp"
#include "hello_ros_interfaces/msg/robot_status.hpp"


class StatusListener : public rclcpp::Node
{
public:
    StatusListener() : Node("status_listener")
    {
        // 【要点 2】create_subscription 和 listener.cpp 是【同一个形状】，
        //   只换两样：尖括号里的消息类型、以及话题名字符串。
        //   lambda 的参数类型照抄下面 callback 的签名。
        sub_ = this->create_subscription<hello_ros_interfaces::msg::RobotStatus>(
            "robot_status", 10, [this](hello_ros_interfaces::msg::RobotStatus::SharedPtr msg) { callback(msg); });
    }

private:
    void callback(const hello_ros_interfaces::msg::RobotStatus::SharedPtr msg)
    {
        // 【要点 3】格式符和参数是【按位置一个个对】的 —— 位置错了 C 不拦你，
        //   只给一条 warning，然后照着你的话去内存里乱读。
        //
        //   对照 Python（status_listener.py 第 15 行）：
        //   f'收到: {msg.robot_name} 电量={msg.battery} mode={msg.mode} x={msg.position.x}'
        //         ↑冒号            ↑等号           ↑等号          ↑等号
        //
        //   📋 格式符速查：
        //        std::string     →  %s   但要接 .c_str()
        //        float / double  →  %f   默认打【6 位小数】；想留 1 位写 %.1f
        //        int             →  %d
        //        bool            →  ⚠️ 没有能直接用的（Python 版也没打印 emergency）
        //
        //   嵌套字段：msg->position.x —— 先箭头、再点
        //     msg 是盒子（智能指针）→ 箭头；position 是值（不是盒子）→ 点
        RCLCPP_INFO(this->get_logger(), "收到: %s 电量=%.1f mode=%d x=%.1f", msg->robot_name.c_str(), msg->battery, msg->mode, msg->position.x);
    }

    // 【要点 4】成员变量的类型 = rclcpp::<角色><消息类型>::SharedPtr
    //   先问：「这一格装的是个什么东西？」
    //   装的是【订阅者】→ 所以外层是 Subscription，不是 RobotStatus。
    //   对照 talker.cpp 的 pub_（Publisher）和 listener.cpp 的 sub_（Subscription）。
    //   ⚠️ 别漏末尾的分号 —— 漏了会报 expected ';' at end of member declaration。
    rclcpp::Subscription<hello_ros_interfaces::msg::RobotStatus>::SharedPtr sub_;
};


int main(int argc, char ** argv)
{
    rclcpp::init(argc, argv);
    rclcpp::spin(std::make_shared<StatusListener>());
    rclcpp::shutdown();
    return 0;
}
