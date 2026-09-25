#include <chrono>
#include <memory>

#include "rclcpp/rclcpp.hpp"
#include "rclcpp_components/register_node_macro.hpp"

using namespace std::chrono_literals;


// 第 12 关的"测速仪"：一个专门用来占住执行器的手的组件。
// 它不发布任何东西，只在定时器回调里睡一觉 —— 睡觉这段时间它攥着那只手不放。
class Sleeper : public rclcpp::Node
{
public:
    Sleeper(const rclcpp::NodeOptions & options) : Node("sleeper", options)
    {
        count_ = 0;
        timer_ = this->create_wall_timer(1s, [this]() { tick(); });
    }

private:
    void tick()
    {
        count_ += 1;
        RCLCPP_INFO(this->get_logger(), "第%d拍 开始睡", count_);

        // 睡觉这段时间，它攥着执行器的那只手不放 —— 这就是本关的"测速仪"
        rclcpp::sleep_for(500ms);

        RCLCPP_INFO(this->get_logger(), "第%d拍 睡醒了", count_);
    }

    rclcpp::TimerBase::SharedPtr timer_;
    int count_;
};

RCLCPP_COMPONENTS_REGISTER_NODE(Sleeper)