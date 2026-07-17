#!/usr/bin/env bash
# 单条 prompt 的快速推理脚本（带 adapter）。
#
# 用法：
#   ./scripts/quick_inference.sh "AirPods Pro 2值得买吗"
#   ./scripts/quick_inference.sh "订单还没到" --max-tokens 256
#
# 依赖：项目根目录的 .venv 中已安装 mlx-lm；adapters/ 目录里有训练产物。
# 不启 server，直接走 mlx_lm.generate。

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

PROMPT="${1:?用法: $0 \"<prompt>\" [-- extra mlx_lm.generate args]}"
shift || true

# 激活 venv（如果存在）
if [[ -f .venv/bin/activate ]]; then
    source .venv/bin/activate
else
    echo "❌ 未找到 .venv，请先 python3 -m venv .venv && source .venv/bin/activate && pip install 'mlx-lm[train]' --upgrade" >&2
    exit 1
fi

# 校验产物
if [[ ! -f adapters/adapters.safetensors ]]; then
    echo "❌ adapters/adapters.safetensors 不存在，请先跑训练或调整 --adapter-path" >&2
    exit 1
fi

mlx_lm.generate \
    --model mlx-community/Qwen2.5-7B-Instruct-4bit \
    --adapter-path adapters \
    --prompt "$PROMPT" \
    --max-tokens 512 \
    --temp 0.7 \
    "$@"