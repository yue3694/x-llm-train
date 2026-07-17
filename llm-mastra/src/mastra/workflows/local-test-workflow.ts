import { createStep, createWorkflow } from '@mastra/core/workflows';
import { z } from 'zod';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { localAgent } from '../agents/local-agent';

/**
 * 本地模型回归测试工作流。
 *
 * 数据源：tests/test_cases.jsonl，每行一个 case，含 id / category / prompt / checks。
 * 评估方式：纯文本启发式（不调用 LLM 做判官），快且确定：
 *   - starts_with       : 输出开头必须以指定字符串开头
 *   - contains_any      : 输出必须包含任一关键词（数组 OR 语义）
 *   - forbidden         : 输出不得包含任一禁用字符串
 *   - has_question      : 输出必须含中文/英文问号
 *   - max_length        : 输出长度上限（防止无限输出）
 *
 * 前置：本地 mlx_lm.server 必须在 127.0.0.1:8080 跑着；否则 agent.generate 会失败。
 */

const checksSchema = z.object({
  starts_with: z.string().optional(),
  contains_any: z.array(z.string()).optional(),
  forbidden: z.array(z.string()).optional(),
  has_question: z.boolean().optional(),
  max_length: z.number().optional(),
}).optional();

const testCaseSchema = z.object({
  id: z.string(),
  category: z.string(),
  prompt: z.string(),
  description: z.string().optional(),
  checks: checksSchema,
});

const caseResultSchema = z.object({
  id: z.string(),
  category: z.string(),
  prompt: z.string(),
  output: z.string(),
  passed: z.boolean(),
  failed_checks: z.array(z.string()),
  duration_ms: z.number(),
});

const workflowOutputSchema = z.object({
  total: z.number(),
  passed: z.number(),
  failed: z.number(),
  pass_rate: z.number(),
  results: z.array(caseResultSchema),
});

const loadCases = createStep({
  id: 'load-cases',
  description: '读取 tests/test_cases.jsonl，可按 category 过滤',
  inputSchema: z.object({
    category: z.string().optional().describe('可选：按 category 过滤'),
  }),
  outputSchema: z.object({
    cases: z.array(testCaseSchema),
  }),
  execute: async ({ inputData }) => {
    const casesPath = resolve(process.cwd(), 'tests/test_cases.jsonl');
    const raw = readFileSync(casesPath, 'utf8');
    const all = raw
      .split('\n')
      .map(line => line.trim())
      .filter(Boolean)
      .map((line, idx) => {
        try {
          return testCaseSchema.parse(JSON.parse(line));
        } catch (e) {
          throw new Error(`test_cases.jsonl 第 ${idx + 1} 行解析失败: ${(e as Error).message}`);
        }
      });

    const filtered = inputData?.category
      ? all.filter(c => c.category === inputData.category)
      : all;

    return { cases: filtered };
  },
});

const runCases = createStep({
  id: 'run-cases',
  description: '串行调用 localAgent，逐条应用启发式检查',
  inputSchema: z.object({
    cases: z.array(testCaseSchema),
  }),
  outputSchema: workflowOutputSchema,
  execute: async ({ inputData, mastra }) => {
    const agent = mastra?.getAgent('localAgent');
    if (!agent) throw new Error('localAgent 未注册到 mastra 实例');

    const results: z.infer<typeof caseResultSchema>[] = [];

    for (const c of inputData.cases) {
      const t0 = Date.now();
      let output = '';
      let failed_checks: string[] = [];
      let passed = false;

      try {
        const response = await agent.generate([{ role: 'user', content: c.prompt }]);
        output = response.text ?? '';
      } catch (e) {
        failed_checks.push(`agent_error: ${(e as Error).message}`);
        results.push({
          id: c.id, category: c.category, prompt: c.prompt,
          output, passed: false, failed_checks,
          duration_ms: Date.now() - t0,
        });
        continue;
      }

      const checks = c.checks ?? {};
      if (checks.starts_with && !output.startsWith(checks.starts_with)) {
        failed_checks.push(`starts_with 失败：期望 "${checks.starts_with}"，实际 "${output.slice(0, 10)}…"`);
      }
      if (checks.contains_any && !checks.contains_any.some(kw => output.includes(kw))) {
        failed_checks.push(`contains_any 失败：未命中 ${JSON.stringify(checks.contains_any)}`);
      }
      if (checks.forbidden) {
        const hit = checks.forbidden.find(kw => output.includes(kw));
        if (hit) failed_checks.push(`forbidden 失败：包含 "${hit}"`);
      }
      if (checks.has_question && !/[？?]/.test(output)) {
        failed_checks.push('has_question 失败：未包含问号');
      }
      if (checks.max_length && output.length > checks.max_length) {
        failed_checks.push(`max_length 失败：${output.length} > ${checks.max_length}`);
      }

      passed = failed_checks.length === 0;
      results.push({
        id: c.id, category: c.category, prompt: c.prompt,
        output, passed, failed_checks,
        duration_ms: Date.now() - t0,
      });
    }

    const total = results.length;
    const passedCount = results.filter(r => r.passed).length;
    return {
      total,
      passed: passedCount,
      failed: total - passedCount,
      pass_rate: total === 0 ? 0 : passedCount / total,
      results,
    };
  },
});

export const localTestWorkflow = createWorkflow({
  id: 'local-test-workflow',
  inputSchema: z.object({
    category: z.string().optional().describe('可选：按 category 过滤'),
  }),
  outputSchema: workflowOutputSchema,
})
  .then(loadCases)
  .then(runCases);

localTestWorkflow.commit();