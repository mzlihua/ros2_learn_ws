#include <chrono>
#include <memory>

#include "rclcpp/rclcpp.hpp"

using namespace std::chrono_literals;


class HelloNode : public rclcpp::Node
{
public:
    HelloNode() : Node("hello_cpp")        // ≈ super().__init__('hello_cpp')
    {
        count_ = 0;

        timer_ = this->create_wall_timer(1s, [this]() { tick(); });
        RCLCPP_INFO(this->get_logger(), "hello_cpp起来了");
    }

private:
    void tick()
    {
        count_ += 1;
        RCLCPP_INFO(this->get_logger(), "第%d次心跳", count_);
    }

    rclcpp::TimerBase::SharedPtr timer_;       // create_wall_timer 的返回值类型
    int count_;
};


int main(int argc, char ** argv)
{
    rclcpp::init(argc, argv);                       // ≈ rclpy.init()
    rclcpp::spin(std::make_shared<HelloNode>());    // ≈ rclpy.spin(node)
    rclcpp::shutdown();                             // ≈ rclpy.shutdown()
    return 0;
}
