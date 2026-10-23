# P2/P3 Native Workflow 实施计划

> 日期：2026-10-22
> 前序：`04-P1-native-runtime实施计划.md`、`05-P1实施偏差与决策记录.md`
> DSL 权威源：`D:\JACK\plan\final_dream_difys\`
> 目标：先完成 P2 主题/案例生成，再完成 P3 的五个文本 workflow；文生图保留 Dify fallback，
> 直到确认可用的图片生成 API 契约。

> **实施进度（2026-10-23）**：P2 与 P3 六个 workflow 已完成；真实主题/案例/
> 场景/大纲/话术/评分/文生图 smoke 通过。Dify 仅保留 fallback。

## 1. 范围与边界

### P2

1. AIGentService 新增通用 workflow 任务接口：
   - `POST /internal/agent/task/{name}`（阻塞）
   - `POST /internal/agent/task/theme-gen/stream`（SSE 节点事件）
2. 迁移：
   - `主题生成-theme-gen.yml`：3 个结构化 LLM 节点 + 3 个 code 节点；
   - `案例生成-case-gen.yml`：1 个结构化 LLM 节点 + 1 个 code 节点。
3. AtualCombatTraining：
   - `NativeWorkflowClient`；
   - `agent.theme-gen.provider=dify|native`；
   - `agent.case-gen.provider=dify|native`；
   - 原重试、schema 校验、渐进事件、消息落库全部不动。

### P3

4. 迁移以下五个文本 workflow：
   - `AI话术-场景生成.yml`
   - `AI话术-大纲生成.yml`
   - `AI话术-话术生成.yml`
   - `话术评分器.yml`
   - `话术训练报告评分智能体.yml`
5. SpeechTraining 的 `DifyWorkflowSupport` 增加 provider 分流，逐 agent 配置：
   - `agent.gen-scene.provider`
   - `agent.gen-outline.provider`
   - `agent.gen-script.provider`
   - `agent.speech-score.provider`
   - `agent.report-score.provider`
6. `avatar-gen` 暂不接 native：DSL 依赖 Dify 插件
   `wwwzhouhui/qwen_text2image/modelscope` / `Qwen/Qwen-Image`，当前环境没有该插件的
   独立可调用契约；继续由 Dify fallback 承接，待图片 API 参数与凭据确认后再迁。

## 2. AIGentService 设计

### 2.1 LLM 结构化输出

- `LlmRequest` 增加可选 `responseSchema`。
- `QwenClient` 在 schema 存在时发送：
  `response_format={type:"json_schema", json_schema:{name, strict:true, schema}}`。
- 已验证 `qwen3.8-flash` 接受该参数。
- 模型返回内容必须是 JSON；解析失败归类为 workflow 业务错误，不做静默空输出。

### 2.2 WorkflowEngine

- `WorkflowEngine`：按任务名查找 `WorkflowTask`。
- `WorkflowTask.execute(inputs, progressListener)`：
  - 每个节点把结果写入 `WorkflowContext`；
  - prompt 中 `{{#node.var#}}` 原样保留，由 renderer 在运行时替换；
  - 任务返回与 Dify end 节点一致的 `outputs`。
- `WorkflowContext`：
  - `inputs`：DSL start 变量；
  - `nodeOutputs`：节点 id → outputs；
  - 解析对象/数组时传 JSON 字符串，保证与 Dify变量语义一致。
- `PromptProvider` 扩展为按 classpath 资源加载并缓存。

### 2.3 资源生成

从权威 DSL 自动提取，不手工改写提示词：

- `resources/prompts/workflows/theme-gen/*.md`
- `resources/prompts/workflows/case-gen/*.md`
- `resources/prompts/workflows/gen-scene/*.md`
- `resources/prompts/workflows/gen-outline/*.md`
- `resources/prompts/workflows/gen-script/*.md`
- `resources/prompts/workflows/speech-score/*.md`
- `resources/prompts/workflows/report-score/*.md`
- 对应 `*.schema.json`（DSL 有 structured output 的节点）

### 2.4 任务实现

- `ThemeGenTask`：
  - LLM 场景 → `code_scenes`
  - LLM 画像/冰山 → `code_profiles`
  - LLM 评估维度 → `code_merge`
  - 流式进度事件：
    - `node_finished(code_scenes)`
    - `node_finished(code_profiles)`
    - `node_finished(code_merge)`
  - 最终 `artifact_json`。
- `CaseGenTask`：
  - LLM 案例 → Java 版 `code_case` 校验；
  - 输出 `case_json`。
- `GenSceneTask` / `GenOutlineTask` / `GenScriptTask`：
  - 单结构化 LLM → DSL end outputs。
- `SpeechScoreTask`：
  - 结构化 LLM → Java 版 `parse_score`。
- `ReportScoreTask`：
  - 文本 LLM → Java 版 `parse_report`；解析失败返回 DSL 同构的失败 outputs。

## 3. 消费端设计

### 3.1 AtualCombatTraining

- `NativeWorkflowClient`：
  - blocking：解析 `{code,message,data.outputs}`；
  - theme streaming：解析 `node_finished`、`message_end`、`error`；
  - 复用 `act_ai_call_log` 记录 native workflow 调用。
- `WorkflowRuntimeRouter`：
  - 根据 `agent.theme-gen.provider` / `agent.case-gen.provider` 选择 Dify 或 native；
  - 同一轮不自动 fallback，避免重复生成与重复事件。
- `ThemeGenerationServiceImpl` / `CaseGenerationServiceImpl`：
  - 只替换 workflow 调用入口；
  - 校验、重试、事件、持久化代码不变。

### 3.2 SpeechTraining

- `NativeWorkflowClient` 调 AIGentService blocking task。
- `DifyWorkflowSupportImpl` 改为 provider-aware：
  - `dify` 保持原逻辑；
  - `native` 使用 agentType → taskName 映射；
  - 未配置或 native 失败时按现网错误口径抛 `BizException`，不静默。
- 配置：

```properties
aigent.base-url=${AIGENT_BASE_URL:http://localhost:8086}
agent.gen-scene.provider=${AGENT_GEN_SCENE_PROVIDER:dify}
agent.gen-outline.provider=${AGENT_GEN_OUTLINE_PROVIDER:dify}
agent.gen-script.provider=${AGENT_GEN_SCRIPT_PROVIDER:dify}
agent.speech-score.provider=${AGENT_SPEECH_SCORE_PROVIDER:dify}
agent.report-score.provider=${AGENT_REPORT_SCORE_PROVIDER:dify}
agent.avatar-gen.provider=${AGENT_AVATAR_GEN_PROVIDER:dify}
```

## 4. TDD 任务

### Task 1：结构化 LLM 契约

- `QwenClientTest`：
  - schema 请求体；
  - JSON content；
  - schema 缺失时不发 `response_format`。

### Task 2：WorkflowEngine / prompt renderer

- `WorkflowContextTest`：
  - inputs / node outputs 替换；
  - object/array → JSON 字符串；
  - 缺失变量明确失败。

### Task 3：ThemeGenTask

- 3 次 LLM 调用顺序与变量引用；
- 三个 node_finished；
- `artifact_json` 可被 `ArtifactSchemaValidator` 接受（消费端测试）。

### Task 4：CaseGenTask

- 字段校验、difficulty 归一化、`case_json` 输出；
- scriptOpening 长度边界。

### Task 5：P3 单步任务

- 三组话术输出字段与 DSL end 一致；
- speech-score parse；
- report-score parse 与失败兜底。

### Task 6：AtualCombatTraining consumer

- native theme streaming 解析；
- native case blocking 解析；
- provider 路由测试；
- Dify fallback 不变。

### Task 7：SpeechTraining consumer

- agentType → taskName 映射；
- native/dify provider 选择；
- 现有 `DifyWorkflowSupportTest` 保持通过。

### Task 8：真实 smoke

- theme-gen 真实千问调用，至少验证 3 个节点事件；
- case-gen 真实调用并通过消费端 `validateCase`；
- gen-scene / gen-outline / gen-script 链路串联；
- speech-score / report-score 输出可解析；
- 所有结果与 DSL end 字段名一致。

## 5. 验收

- AIGentService、AtualCombatTraining、SpeechTraining 全量测试通过；
- theme-gen 流式节点事件顺序与 Dify 当前消费逻辑一致；
- case-gen / 三组话术 / 两个评分任务 outputs 字段名不变；
- provider 默认 dify，现有线上行为不改变；
- native 失败可读且不自动重试 Dify；
- `avatar-gen` 明确记录为 Dify fallback。
