#!/usr/bin/env bash
# 对照测试：同一个 prompt，分别用「带 adapter」「不带 adapter」「融合产物」跑，
# 把 3 个输出写到 tmp/compare_<timestamp>/ 下，肉眼对比风格差异。
#
# 用法：
#   ./scripts/compare_baseline.sh "AirPods Pro 2值得买吗"
#   ./scripts/compare_baseline.sh "今天能发货吗"
#
# 注意：会跑 3 次 mlx_lm.generate，对 24GB 机器约 30~60s。

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

PROMPT="${1:?用法: $0 \"<prompt>\"}"

if [[ -f .venv/bin/activate ]]; then
    source .venv/bin/activate
fi

STAMP=$(date +%Y%m%d_%H%M%S)
OUT_DIR="$PROJECT_ROOT/tmp/compare_$STAMP"
mkdir -p "$OUT_DIR"

echo "📂 输出目录: $OUT_DIR"
echo "🔹 prompt: $PROMPT"
echo

run_one() {
    local label="$1"; shift
    local outfile="$OUT_DIR/$label.txt"
    echo "── $label ──" | tee "$outfile"
    "$@" 2>&1 | tee -a "$outfile"
    echo | tee -a "$outfile"
}

run_one "01_baseline_4bit" \
    mlx_lm.generate \
        --model mlx-community/Qwen2.5-7B-Instruct-4bit \
        --prompt "$PROMPT" \
        --max-tokens 256 --temp 0.7

if [[ -f adapters/adapters.safetensors ]]; then
    run_one "02_lora_adapter" \
        mlx_lm.generate \
            --model mlx-community/Qwen2.5-7B-Instruct-4bit \
            --adapter-path adapters \
            --prompt "$PROMPT" \
            --max-tokens 256 --temp 0.7
fi

if [[ -f llm_high/config.json ]]; then
    run_one "03_fused_full" \
        mlx_lm.generate \
            --model llm_high \
            --prompt "$PROMPT" \
            --max-tokens 256 --temp 0.7
fi

echo "✅ 完成，diff 一下："
echo "   diff $OUT_DIR/01_baseline_4bit.txt $OUT_DIR/02_lora_adapter.txt"