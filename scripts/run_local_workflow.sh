#!/usr/bin/env bash
# 一键跑通 local-test-workflow：起 mlx server → 启 Mastra dev → 触发 workflow。
#
# 用法：
#   ./scripts/run_local_workflow.sh                  # 跑全部 12 条 case
#   ./scripts/run_local_workflow.sh product          # 只跑 product 类
#   PORT=8081 ./scripts/run_local_workflow.sh        # 自定义 mlx 端口
#
# 进程管理：trap 保证 Ctrl-C 时一并关掉 mlx server 与 mastra dev，不留孤儿。

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MASTRA_DIR="$PROJECT_ROOT/llm-mastra"
PORT="${PORT:-8080}"

# ---------- 参数解析 ----------
CATEGORY="${1:-}"
read -r -d '' INPUT_JSON <<JSON || true
{"input":{"category":"$CATEGORY"}}
JSON
# 空 category 时传 {}
if [[ -z "$CATEGORY" ]]; then
    INPUT_JSON='{"input":{}}'
fi

# ---------- 激活 venv ----------
if [[ ! -f "$PROJECT_ROOT/.venv/bin/activate" ]]; then
    echo "❌ 未找到 .venv，先 python3 -m venv .venv && source .venv/bin/activate && pip install 'mlx-lm[train]' --upgrade" >&2
    exit 1
fi
source "$PROJECT_ROOT/.venv/bin/activate"

# ---------- 选择模型源（融合产物 > base 4bit）----------
if [[ -f "$PROJECT_ROOT/llm_high/config.json" ]]; then
    MODEL_PATH="$PROJECT_ROOT/llm_high"
    echo "🔧 使用融合模型: $MODEL_PATH"
else
    MODEL_PATH="mlx-community/Qwen2.5-7B-Instruct-4bit"
    echo "🔧 使用基础 4bit 模型: $MODEL_PATH"
fi

# ---------- 启动 mlx server ----------
echo "🚀 启动 mlx_lm.server (port $PORT)…"
mlx_lm.server --model "$MODEL_PATH" --port "$PORT" >/tmp/mlx_server.log 2>&1 &
MLX_PID=$!
trap 'echo "🛑 关闭 mlx server (pid $MLX_PID)…"; kill $MLX_PID 2>/dev/null || true; wait $MLX_PID 2>/dev/null || true' EXIT

# 等 server 就绪
for i in {1..30}; do
    if curl -sf "http://127.0.0.1:$PORT/v1/models" >/dev/null 2>&1; then
        echo "✅ mlx server 已就绪"
        break
    fi
    sleep 1
    if (( i == 30 )); then
        echo "❌ mlx server 30s 内未就绪，日志：" >&2
        tail -20 /tmp/mlx_server.log >&2
        exit 1
    fi
done

# ---------- 启动 Mastra dev ----------
echo "🚀 启动 Mastra dev (port 4111)…"
cd "$MASTRA_DIR"
export LOCAL_LLM_BASE_URL="http://127.0.0.1:$PORT/v1"
pnpm run dev >/tmp/mastra_dev.log 2>&1 &
MASTRA_PID=$!
trap 'echo "🛑 关闭 mastra dev (pid $MASTRA_PID)…"; kill $MASTRA_PID 2>/dev/null || true; wait $MASTRA_PID 2>/dev/null || true; echo "🛑 关闭 mlx server (pid $MLX_PID)…"; kill $MLX_PID 2>/dev/null || true; wait $MLX_PID 2>/dev/null || true' EXIT

# 等 Mastra 就绪
for i in {1..60}; do
    if curl -sf "http://127.0.0.1:4111/api/workflows" >/dev/null 2>&1; then
        echo "✅ Mastra 已就绪"
        break
    fi
    sleep 1
    if (( i == 60 )); then
        echo "❌ Mastra 60s 内未就绪，日志：" >&2
        tail -30 /tmp/mastra_dev.log >&2
        exit 1
    fi
done

# ---------- 触发 workflow ----------
echo "🎯 触发 localTestWorkflow (input=$INPUT_JSON)…"
RESP=$(curl -sf -X POST "http://127.0.0.1:4111/api/workflows/localTestWorkflow/start" \
    -H 'Content-Type: application/json' \
    -d "$INPUT_JSON")

# 取出 runId 并轮询结果
RUN_ID=$(echo "$RESP" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("runId",""))')
if [[ -z "$RUN_ID" ]]; then
    echo "❌ 启动 workflow 失败，原始响应：" >&2
    echo "$RESP" >&2
    exit 1
fi
echo "📋 runId=$RUN_ID，等待结果…"

for i in {1..300}; do
    STATUS_RESP=$(curl -sf "http://127.0.0.1:4111/api/workflows/localTestWorkflow/runs/$RUN_ID" || true)
    STATUS=$(echo "$STATUS_RESP" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' 2>/dev/null || echo "")
    if [[ "$STATUS" == "success" || "$STATUS" == "failed" || "$STATUS" == "error" ]]; then
        echo "$STATUS_RESP" | python3 -m json.tool
        [[ "$STATUS" == "success" ]] && exit 0 || exit 1
    fi
    sleep 2
done
echo "❌ workflow 600s 内未结束" >&2
exit 1