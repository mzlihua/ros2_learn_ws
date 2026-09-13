#include <chrono>
#include <memory>
#include <string>

#include "rclcpp/rclcpp.hpp"
#include "std_msgs/msg/string.hpp"

using namespace std::chrono_literals;


class Talker : public rclcpp::Node
{
public:
    Talker() : Node("talker_cpp")        // ≈ super().__init__('talker_cpp')
    {
        count_ = 0;

        // 类型写在 <> 里 —— C++ 编译期就得知道发布的是什么消息
        pub_ = this->create_publisher<std_msgs::msg::String>("chatter", 10);
        timer_ = this->create_wall_timer(1s, [this]() { tick(); });
    }

private:
    void tick()
    {
        count_ += 1;

        auto msg = std_msgs::msg::String();
        msg.data = "第" + std::to_string(count_)+"次心跳";              // ⚠️ 待补：换成真正的中文内容
        pub_->publish(msg);

        RCLCPP_INFO(this->get_logger(), "发布：%s", msg.data.c_str());   // ⚠️ 待补：同上
    }

    // 成员变量的类型 = 初始化它的那个函数的返回值类型
    rclcpp::Publisher<std_msgs::msg::String>::SharedPtr pub_;
    rclcpp::TimerBase::SharedPtr timer_;
    int count_;
};


int main(int argc, char ** argv)
{
    rclcpp::init(argc, argv);                       // ≈ rclpy.init()
    rclcpp::spin(std::make_shared<Talker>());       // ≈ rclpy.spin(node)
    rclcpp::shutdown();                             // ≈ rclpy.shutdown()
    return 0;
}
