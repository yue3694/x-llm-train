# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目性质

本仓库是 **Mac M5 Pro 24GB 本地 LoRA 微调流程的产物**，不是源码工程，而是微调各阶段产物 + 复现脚本的合集。基础模型为 `mlx-community/Qwen2.5-7B-Instruct-4bit`，任务为电商电子产品客服风格定制。详见根目录 `README.md`。

## 目录结构（按微调阶段）

| 路径 | 角色 | 关键内容 |
|------|------|----------|
| `data/` | 训练数据 | `train.jsonl`（500 条 ChatML 三元组 messages） |
| `scripts/` | 操作脚本 | `generate_training_data.py`（合成数据生成器）、`quick_inference.sh`（单条 prompt 推理）、`compare_baseline.sh`（baseline / adapter / 融合 三方对照）、`run_local_workflow.sh`（一键起 mlx server + Mastra dev + 跑测试 workflow） |
| `adapters/` | LoRA 增量权重 | `adapter_config.json`（rank=8、scale=20.0、num_layers=8）+ 每 100 步保存的 `0000N00_adapters.safetensors` + 最终 `adapters.safetensors` |
| `llm/` | 基础 4bit 量化模型 | Qwen2.5-7B-Instruct-4bit（`config.json` 含 `quantization.bits=4`，单文件 `model.safetensors` 约 4.3GB） |
| `llm_high/` | 反量化融合后的全精度模型 | 同架构但去掉 quantization 段，分片 `model-0000N-of-00003.safetensors`，约 15GB |

`llm/` 是训练的起点，`adapters/` 是训练产出，`llm_high/` 是把 adapter 写回 base 模型后的可分发产物（可直接喂 Ollama / LM Studio）。

## 常用命令

> 环境：`python3 -m venv mlx_finetune && source mlx_finetune/bin/activate && pip install "mlx-lm[train]" --upgrade`

```bash
# 1. 重新生成合成训练集（覆盖 data/train.jsonl）
python scripts/generate_training_data.py

# 2. LoRA 微调（24GB 关键参数：batch-size 1、num-layers 8、iters 500）
mlx_lm.lora \
  --model mlx-community/Qwen2.5-7B-Instruct-4bit \
  --train --data data --iters 500 \
  --batch-size 1 --learning-rate 1e-4 \
  --num-layers 8 --max-seq-length 2048 \
  --steps-per-eval 100 --adapter-path adapters

# 3. 抽样验证
mlx_lm.generate \
  --model mlx-community/Qwen2.5-7B-Instruct-4bit \
  --adapter-path adapters \
  --prompt "<user_text>" --max-tokens 512 --temp 0.7

# 4. 本地服务（外部端口 8080，仅推理 base 模型）
mlx_lm.server --model mlx-community/Qwen2.5-7B-Instruct-4bit --port 8080

# 5. 融合 adapter → 全精度模型（输出到 llm_high/）
mlx_lm.fuse \
  --model ~/.cache/huggingface/hub/models--mlx-community--Qwen2.5-7B-Instruct-4bit/snapshots/<snapshot> \
  --adapter-path ./adapters \
  --save-path ./llm_high \
  --dequantize
```

## 数据约定

- `data/train.jsonl` 每行一个 JSON 对象，键为 `messages`，含 `system / user / assistant` 三段。`scripts/generate_training_data.py` 的 `SYSTEM_PROMPT` 是客服风格唯一锚点，修改 system prompt 会改变整个微调方向。
- 训练集 500 条由 8 条种子 ×（基础 + 1 个随机变体后缀）扩出，调整 `TARGET_COUNT` 即可扩缩。

## 训练超参（来自 `adapters/adapter_config.json`）

- LoRA: `rank=8`, `dropout=0.0`, `scale=20.0`, 仅 8 层可训练
- 优化器: `adam`（默认配置），`lr=1e-4`，无 lr schedule
- 序列长度: 2048，`grad_checkpoint=false`，`save_every=100`
- 关键陷阱：`batch-size > 1` 会 OOM（24GB 统一内存）

## OOM / 性能回退路径

按 README 第 7 节：先降 `--iters`，再降 `--num-layers`（如改 4），最后换更小的 base 模型（Qwen2.5-3B / Phi-4）。训练期间关浏览器并监控 Activity Monitor → Memory。

## 模型架构要点（Qwen2.5-7B）

`hidden_size=3584`，`intermediate_size=18944`，`num_hidden_layers=28`，`num_attention_heads=28`，`num_key_value_heads=4`（GQA），`vocab_size=152064`，`max_position_embeddings=32768`，`rope_theta=1e6`，`tie_word_embeddings=false`。`llm_high/` 与 `llm/` 架构完全一致，差异仅在 `quantization` 段是否存在——即是否为 4bit。