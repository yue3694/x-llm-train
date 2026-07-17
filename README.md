**✅ Mac M5 Pro 24GB 本地模型微调训练文档**

### **文档信息**

- **硬件**：MacBook Pro / Mac Mini M5 Pro 24GB 统一内存
- **适用场景**：轻量 LoRA/QLoRA 微调（推荐 7B 模型）
- **框架**：Apple MLX（最适合 Apple Silicon）
- **更新日期**：2026年7月

---

### **1. 环境准备**

```bash
# 1. 安装 Xcode 命令行工具（首次需要）
xcode-select --install

# 2. 创建虚拟环境
python3 -m venv mlx_finetune
source mlx_finetune/bin/activate

# 3. 安装微调工具
pip install "mlx-lm[train]" --upgrade
```

---

### **2. 下载基础模型（推荐 4bit 量化版）**

```bash
# 推荐模型（24GB 最稳）
mlx_lm.convert --hf-path mlx-community/Qwen2.5-7B-Instruct-4bit -q

# 备选模型
# mlx_lm.convert --hf-path mlx-community/Meta-Llama-3.1-8B-Instruct-4bit -q
```

---

### **3. 准备训练数据集**

在当前目录创建文件夹：

```bash
mkdir -p data
```

**data/train.jsonl** 示例（每行一条对话）：

```json
{
  "messages": [
    { "role": "system", "content": "你是一个专业的 AI 助手" },
    { "role": "user", "content": "解释一下 Python 列表推导式" },
    { "role": "assistant", "content": "列表推导式是一种..." }
  ]
}
```

**建议**：

- 数据量：**200~800 条** 高质量数据
- 格式推荐使用 **ChatML** 或 **Alpaca** 风格

---

### **4. 开始微调（24GB 优化命令）**

- 下载已转换好的 MLX 版本（推荐）

```bash
git clone https://huggingface.co/mlx-community/Qwen2.5-7B-Instruct-4bit
```

- 开始微调

```bash
mlx_lm.lora \
  --model mlx-community/Qwen2.5-7B-Instruct-4bit \
  --train \
  --data data \
  --iters 500 \
  --batch-size 1 \
  --learning-rate 1e-4 \
  --num-layers 8 \
  --max-seq-length 2048 \
  --steps-per-eval 100 \
  --adapter-path adapters
```

- 对外验证，开放端口，这个是拿外部模型本地启动服务
```bash
mlx_lm.server --model mlx-community/Qwen2.5-7B-Instruct-4bit --port 8080
```

**参数说明**（24GB 关键设置）：

- `--batch-size 1`：必须使用 1，否则容易内存溢出
- `--num-layers 8`：减少可训练层数，节省内存
- `--iters`：根据数据量调整（400~800 较合适）

---

### **5. 测试微调效果**

- 单次测试

```bash
mlx_lm.generate \
  --model mlx-community/Qwen2.5-7B-Instruct-4bit \
  --adapter-path adapters \
  --prompt "啥时候能到，太慢了吧" \
  --max-tokens 512 \
  --temp 0.7
```

- server 测试
```bash
mlx_lm.server \
  --model ~/.cache/huggingface/hub/models--mlx-community--Qwen2.5-7B-Instruct-4bit/snapshots/c26a38f6a37d0a51b4e9a1eb3026530fa35d9fed \
  --adapter-path ./adapters \
  --port 8080 \
  --temp 0.7 \
  --max-tokens 2048
```

---

### **6. 融合模型（导出完整模型）**

```bash
mlx_lm.fuse \
  --model ~/.cache/huggingface/hub/models--mlx-community--Qwen2.5-7B-Instruct-4bit/snapshots/c26a38f6a37d0a51b4e9a1eb3026530fa35d9fed \
  --adapter-path ./adapters \
  --save-path ./llm_high \
  --dequantize  # 不加也能融，但融出来还是 4bit，精度损失会比 de-quantize 再融再重量化那套大一点
```

融合后的模型可直接用于 **Ollama**、**LM Studio** 或继续推理。

---

### **7. 注意事项与故障排除**

**内存管理**：

- 关闭所有不必要程序（尤其是浏览器）
- 训练时实时监控 **Activity Monitor → Memory**
- 若出现 OOM（内存溢出）：
  - 减少 `--iters`
  - 降低 `--lora-layers` 到 4
  - 换更小的模型（Qwen2.5-3B / Phi-4 等）

**训练速度**：

- 24GB 下 7B 模型训练速度较慢，属于正常现象
- 建议晚上或不使用电脑时进行长时间训练

**后续优化**：

- 想做 DPO / ORPO 等高级微调 → 使用 **mlx-tune** 工具
- 导出 GGUF 格式用于 Ollama：使用 `mlx_lm` 的转换工具

---
