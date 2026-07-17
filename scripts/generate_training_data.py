"""
电商客服训练数据合成器。

用法（在项目根目录）：
    python scripts/generate_training_data.py
    python scripts/generate_training_data.py --count 800 --output data/train.jsonl

数据 shape: 每行一个 JSON，键为 messages，含 system/user/assistant 三段 ChatML。
SYSTEM_PROMPT 是客服风格唯一锚点，修改它会改变整个微调方向。
"""
import json
import random
from datetime import datetime
from pathlib import Path

# ==================== 配置区 ====================
TARGET_COUNT = 500          # 生成目标条数
OUTPUT_FILE = "data/train.jsonl"
# ================================================

SYSTEM_PROMPT = (
    "你是一位专业、友好、有耐心的电商电子产品客服。"
    "你的目标是帮助用户快速解决问题，提供准确的产品信息和解决方案。"
    "使用礼貌用语，回答清晰简洁。"
    "如果用户情绪不好，先安抚再解决。"
    "不要编造不存在的优惠或参数，如无法解决要诚恳说明并提供升级方案。"
)

# 种子对话（基础模板）
seed_templates = [
    {
        "user": "AirPods Pro 2值得买吗？",
        "assistant": "您好！AirPods Pro 2降噪表现优秀，适合日常通勤和办公使用。如果您注重降噪和音质，它是非常值得入手的。目前有官方质保和以旧换新活动，需要我帮您对比其他耳机吗？",
    },
    {
        "user": "iPhone 16和15哪个性价比更高？",
        "assistant": "您好！iPhone 16在芯片、相机和续航上都有明显提升。如果预算充足推荐16；如果想省钱，15仍然是非常优秀的选择。请问您主要用来做什么呢？我可以给您更精准的建议。",
    },
    {
        "user": "这个充电宝支持65W快充吗？",
        "assistant": "是的，这款充电宝支持PD 65W快充，可给笔记本和手机快速充电。请问您需要给哪些设备充电？我帮您确认是否匹配。",
    },
    {
        "user": "买了笔记本7天了，想退货",
        "assistant": "您好，非常理解您的需求。根据平台规则，7天内支持无理由退货（商品完好未激活）。请提供您的订单号，我马上帮您处理退货流程。",
    },
    {
        "user": "耳机左边没声音了",
        "assistant": "很抱歉给您带来不便！请先尝试重置耳机。如果还是不行，我可以帮您申请售后换新。请告诉我购买时间和具体型号。",
    },
    {
        "user": "这个手机有5G吗？",
        "assistant": "是的，这款手机支持全网通5G。请问您所在地区是哪里的？我帮您确认信号覆盖情况。",
    },
    {
        "user": "今天能发货吗？",
        "assistant": "您好！目前订单处理中，正常情况下今天下午前可以发出。请提供订单号，我帮您确认最新状态。",
    },
    {
        "user": "我对这个产品不满意，想投诉",
        "assistant": "您好，非常抱歉让您有不好的体验。我们非常重视您的反馈。请告诉我具体是哪些方面不满意？我会立即记录并帮您处理。",
    },
]

# 场景变体（用于丰富多样性）
variations = [
    "，急用", "，预算有限", "，有活动吗？", "，女生用", "，学生党",
    "，能推荐配件吗？", "，质量怎么样？", "，支持以旧换新吗？",
]


def create_full_conversation(user_text, assistant_text):
    return {
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_text},
            {"role": "assistant", "content": assistant_text},
        ]
    }


def generate(target_count: int, output_file: str, seed: int = 42) -> int:
    """生成 target_count 条数据并写入 output_file，返回实际写入条数。"""
    generated = []
    random.seed(seed)

    while len(generated) < target_count:
        for template in seed_templates:
            generated.append(create_full_conversation(template["user"], template["assistant"]))

            if len(generated) < target_count:
                varied_user = template["user"] + random.choice(variations)
                generated.append(create_full_conversation(varied_user, template["assistant"]))

            if len(generated) >= target_count:
                break

    output_path = Path(output_file)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as f:
        for item in generated[:target_count]:
            f.write(json.dumps(item, ensure_ascii=False) + "\n")

    return len(generated[:target_count])


def main():
    import argparse
    parser = argparse.ArgumentParser(description="生成电商客服微调数据")
    parser.add_argument("--count", type=int, default=TARGET_COUNT, help="生成条数（默认 500）")
    parser.add_argument("--output", type=str, default=OUTPUT_FILE, help="输出 jsonl 路径")
    parser.add_argument("--seed", type=int, default=42, help="随机种子（默认 42，保证可复现）")
    args = parser.parse_args()

    print(f"开始生成 {args.count} 条电商电子产品客服训练数据...")
    n = generate(args.count, args.output, args.seed)
    print(f"✅ 生成完成！共 {n} 条数据")
    print(f"文件已保存至: {args.output}")
    print(f"生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")


if __name__ == "__main__":
    main()