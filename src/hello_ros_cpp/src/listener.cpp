// ============================================================================
// C++ 支线 02 · 第 1 步：C++ 版订阅者，订阅 /chatter
//
// 对照对象：你第 1 关写的 src/hello_ros/hello_ros/listener.py
// 话题名、消息类型、队列长度 —— 全都和 Python 版一样，只换语言。
//
// 只有 4 个空，每个都是【一行】。别一次填完，填一个保存一次。
// ⚠️ 每一行都能在你自己的笔记里查到答案 —— 去查，别猜：
//      docs/cpp-01-getting-started.md  §2 和 §4
// ============================================================================


// TODO 1：两行 #include
//   · rclcpp 本体        —— 照 talker.cpp 第 5 行
//   · 消息类型           —— talker.cpp 用的是哪个 .hpp？这次是同一个消息类型
#include "rclcpp/rclcpp.hpp"
#include "std_msgs/msg/string.hpp"

class Listener : public rclcpp::Node
{
public:
    Listener() : Node("listener_cpp")
    {
        // TODO 2：建订阅者。就这一行。
        //   话题名 "chatter"，队列 10（和 Python 版一致）
        //   回调：lambda，收一个参数，参数类型是 const std_msgs::msg::String::SharedPtr msg
        //
        //   ⚠️ 这是和 Python 差别最大的一处：
        //        Python: self.create_subscription(String, 'chatter', self.callback, 10)
        //        C++   : 消息类型要写进 <> 里，回调要用 lambda 包一层
        //
        //   ⭐ 笔记 §4「常用成员函数」里【已经有】订阅者的完整写法，
        //      连 lambda 长什么样都写了。你做的事是【照着改】，不是【从零想】。
        sub_ = this->create_subscription<std_msgs::msg::String>(
            "chatter", 10, [this](const std_msgs::msg::String::SharedPtr msg) { callback(msg); });

    }

private:
    void callback(const std_msgs::msg::String::SharedPtr msg)
    {
        RCLCPP_INFO(this->get_logger(), "收到: %s", msg->data.c_str());   // TODO 3
        // ↑ 把 ??? 换成正确写法
        //   Python 是 f'收到: {msg.data}' —— 直接塞进去就行
        //   C++ 的 %s 只吃 C 风格字符串，std::string 得转换一下
    }

    // TODO 4：成员变量声明。就这一行。
    //   规律：rclcpp::<东西><消息类型>::SharedPtr
    //   不确定就去 /opt/ros/lyrical/include/rclcpp/rclcpp/node.hpp
    //   搜 create_subscription，看它返回什么类型
    rclcpp::Subscription<std_msgs::msg::String>::SharedPtr sub_;
};


int main(int argc, char ** argv)
{
    rclcpp::init(argc, argv);
    rclcpp::spin(std::make_shared<Listener>());
    rclcpp::shutdown();
    return 0;
}
