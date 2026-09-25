#include <chrono>
#include <memory>

#include "rclcpp/rclcpp.hpp"
#include "rclcpp_components/register_node_macro.hpp"

using namespace std::chrono_literals;


// 第 12/13 关的"测速仪"：一个专门用来占住执行器的手的组件。
// 它不发布任何东西，只在定时器回调里睡一觉 —— 睡觉这段时间它攥着那只手不放。
//
// 第 13 关给它加了【第二个】定时器（tick_b），并且把两个定时器分别挂到
// 【两个独立的互斥回调组】上 —— 定时器两个，锁两把。
class Sleeper : public rclcpp::Node
{
public:
    Sleeper(const rclcpp::NodeOptions & options) : Node("sleeper", options)
    {
        count_a_ = 0;
        count_b_ = 0;
        group_a_ = this->create_callback_group(rclcpp::CallbackGroupType::MutuallyExclusive);
        group_b_ = this->create_callback_group(rclcpp::CallbackGroupType::MutuallyExclusive);
        timer_a_ = this->create_wall_timer(1s, [this]() { tick_a(); }, group_a_);
        timer_b_ = this->create_wall_timer(1s, [this]() { tick_b(); }, group_b_);
    }

private:
    void tick_a()
    {
        count_a_ += 1;
        RCLCPP_INFO(this->get_logger(), "A 第%d拍 开始睡", count_a_);

        // 睡觉这段时间，它攥着执行器的那只手不放 —— 这就是本关的"测速仪"
        rclcpp::sleep_for(500ms);

        RCLCPP_INFO(this->get_logger(), "A 第%d拍 睡醒了", count_a_);
    }

    void tick_b()
    {
        count_b_ += 1;
        RCLCPP_INFO(this->get_logger(), "B 第%d拍 开始睡", count_b_);

        rclcpp::sleep_for(500ms);

        RCLCPP_INFO(this->get_logger(), "B 第%d拍 睡醒了", count_b_);
    }

    rclcpp::TimerBase::SharedPtr timer_a_;
    rclcpp::TimerBase::SharedPtr timer_b_;
    rclcpp::CallbackGroup::SharedPtr group_a_;
    rclcpp::CallbackGroup::SharedPtr group_b_;
    int count_a_;
    int count_b_;
};

RCLCPP_COMPONENTS_REGISTER_NODE(Sleeper)
