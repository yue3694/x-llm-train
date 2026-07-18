import { Agent } from '@mastra/core/agent';
import { Memory } from '@mastra/memory';

/**
 * Local Agent — 直接调用本机 mlx_lm.server 暴露的 OpenAI 兼容端点。
 *
 * 启动本地服务（来自根目录 README.md）：
 *   mlx_lm.server --model mlx-community/Qwen2.5-7B-Instruct-4bit --port 8080
 *
 * 该服务默认在 8080 端口提供 OpenAI 兼容 API：
 *   GET  /v1/models         — 模型列表
 *   POST /v1/chat/completions — 聊天补全
 *
 * 端点 URL 通过环境变量 LOCAL_LLM_BASE_URL 配置，默认 http://127.0.0.1:8080/v1。
 * MLX server 不校验 key，传一个占位符即可（不同部署若启用了鉴权再覆盖）。
 *
 * ⚠️ 关键陷阱：mlx_lm.server 把请求体里的 `model` 字段直接交给 ModelProvider.load()，
 * 任何不匹配 `_model_map["default_model"]` 的名字都会被当成 HuggingFace repo 去下载，
 * 进而抛 404。这里直接把 id 设为 `default_model`，让 server 用 CLI 启动时加载的模型。
 * 参见 server.py:387 — `model_path = self._model_map.get(model_path, model_path)`。
 *
 * 上下文记忆：
 *   1. lastMessages:20 — 每次调用自动注入最近 20 条消息（thread 内短期上下文）
 *   2. workingMemory   — resource 维度长期记忆，跨 thread 保留用户偏好（产品偏好 / 联系方式等）
 *   3. 存储走 index.ts 里 MastraCompositeStore 的 default（LibSQLStore，本地文件）
 *   4. 调用方必须传 threadId + resourceId，否则视为无状态单轮调用
 */
const baseUrl = process.env.LOCAL_LLM_BASE_URL ?? 'http://127.0.0.1:8080/v1';

export const localAgent = new Agent({
  id: 'local-agent',
  name: 'Local MLX Agent',
  instructions: `你是一位专业、友好、有耐心的电商电子产品客服。

你的目标：
- 帮助用户快速解决问题
- 提供准确的产品信息和解决方案
- 使用礼貌用语，回答清晰简洁
- 如果用户情绪不好，先安抚再解决
- 不要编造不存在的优惠或参数
- 如无法解决，诚恳说明并提供升级方案
- 回答前先看 working memory：若用户已有偏好（预算 / 设备 / 联系方式），请据此给出更精准的建议`,
  model: {
    id: 'openai-compatible/default_model',
    url: baseUrl,
    apiKey: process.env.LOCAL_LLM_API_KEY ?? 'no-key-required',
  },
  memory: new Memory({
    options: {
      // thread 内最近消息数（短期上下文）。7B 模型 + max_seq_length=2048 下 20 条约 2~3k tokens。
      lastMessages: 20,
      // resource 级长期记忆（跨 thread）。模板里定义了要追踪的字段，模型按需写入。
      workingMemory: {
        enabled: true,
        scope: 'resource',
        template: `# 用户档案

## 基础信息
- **称呼**：
- **联系方式 / 订单号**：

## 偏好
- **预算区间**：
- **常购品类**：
- **使用场景**：

## 当前进展
- **未解决的工单 / 待跟进事项**：
`,
      },
    },
  }),
});