#include <chrono>
#include <memory>

#include "rclcpp/rclcpp.hpp"
#include "rclcpp_components/register_node_macro.hpp"

using namespace std::chrono_literals;


// 第 15 关的"记账仪"：在第 12/13/14 关那台"测速仪"上加了一个【两个回调共用的数】。
//
// 变化只有两处：
//   ① 两个定时器现在都碰【同一个】shared_（以前各碰自己那个 count_x_）
//   ② 每拍对 shared_ 做的不是一句 += 1，而是【四步】：
//          读 → 睡 → 加一 → 写回        （"睡"是量具：把原本只有几纳秒的窗口撑到 1.5 秒）
//
// 没变的（这两格是舞台，本关一档都不拧 —— 第 14 关已实测"可重入 + 多线程"会重叠）：
//   组的类型 = Reentrant ／ 容器 = 多线程 ／ 周期 = 1s ／ 觉 = 1500ms
//
// ⚠️ 这是本关的【定稿 / 基准版】：对 shared_ 完全不管。七个实验都是在这份基准上
//    "只动一处"得到的（改动清单见笔记 §3.2）。唯一"对的"那一版在 §3.1：
//    用一对花括号 + std::lock_guard 把【四步】全包起来（只包最后一行 = 等于没锁）。
class Sleeper : public rclcpp::Node
{
public:
    Sleeper(const rclcpp::NodeOptions & options) : Node("sleeper", options)
    {
        count_a_ = 0;
        count_b_ = 0;
        shared_ = 0;            // 两个回调共用的那个数

        group_a_ = this->create_callback_group(rclcpp::CallbackGroupType::Reentrant);
        group_b_ = this->create_callback_group(rclcpp::CallbackGroupType::Reentrant);
        timer_a_ = this->create_wall_timer(1s, [this]() { tick_a(); }, group_a_);
        timer_b_ = this->create_wall_timer(1s, [this]() { tick_b(); }, group_b_);
    }

private:
    void tick_a()
    {
        count_a_ += 1;

        // 第 1 步：读 —— 把共享的那个数抄一份到自己手里
        int local = shared_;

        RCLCPP_INFO(this->get_logger(), "[A] 第%d拍 读到 shared=%d", count_a_, local);

        // 第 2 步：睡 —— 把"读"和"写回"之间的窗口撑开（这是量具，不是 bug）
        rclcpp::sleep_for(1500ms);

        // 第 3 步：加一 —— 改的是自己手里那一份
        local += 1;

        // 第 4 步：写回 —— 把手里的这一份放回去
        shared_ = local;

        RCLCPP_INFO(this->get_logger(), "[A] 第%d拍 写回 shared=%d", count_a_, local);
    }

    void tick_b()
    {
        count_b_ += 1;

        int local = shared_;

        RCLCPP_INFO(this->get_logger(), "[B] 第%d拍 读到 shared=%d", count_b_, local);

        rclcpp::sleep_for(1500ms);

        local += 1;

        shared_ = local;

        RCLCPP_INFO(this->get_logger(), "[B] 第%d拍 写回 shared=%d", count_b_, local);
    }

    rclcpp::TimerBase::SharedPtr timer_a_;
    rclcpp::TimerBase::SharedPtr timer_b_;
    rclcpp::CallbackGroup::SharedPtr group_a_;
    rclcpp::CallbackGroup::SharedPtr group_b_;
    int count_a_;
    int count_b_;
    int shared_;            // 两个回调共用的那个数
};

RCLCPP_COMPONENTS_REGISTER_NODE(Sleeper)
