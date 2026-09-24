# Dify DSL ①：side_free 编排智能体（Agent 应用）

> Dify 版本：1.10.1 ｜ 应用类型：Agent（对话型）
> 导入方式：Dify 控制台 → 创建应用 → 导入 DSL → 粘贴下方 YAML → 发布 → 复制 API Key 填 `dify.orchestrator-key`
> 用途：AI 设计助手对话主入口。**本 DSL 已含完整系统提示词与 4 个 API 工具的 OpenAPI Schema**，导入后仅需把工具服务器地址确认指向 `http://<AtualCombatTraining主机IP>:8082`。

---

```yaml
app:
  description: AI实战训练场·自由演练设计助手（对话编排）
  icon: 🤖
  icon_background: '#6B5CE7'
  mode: agent-chat
  name: 自由演练设计助手-side_free
kind: app
version: 0.1.5

workflow:
  conversation_variables: []
  environment_variables:
  - description: 工具服务器基地址（AtualCombatTraining 直连地址，Dify 需可访问）
    id: tool_base_url
    name: TOOL_BASE_URL
    value: http://10.10.x.x:8082
    value_type: string
  features:
    opening_statement: ''
    retriever_resource:
      enabled: false
    sensitive_word_avoidance:
      enabled: false
    speech_to_text:
      enabled: false
    suggested_questions: []
    suggested_questions_after_answer:
      enabled: false
  graph:
    edges:
    - data:
        sourceType: start
        targetType: agent
      id: edge-start-agent
      source: start
      sourceHandle: source
      target: agent
      targetHandle: target
      type: custom
    nodes:
    - data:
        selected: false
        title: 开始
        type: start
        variables:
        - label: theme_status
          max_length: 48000
          options: []
          required: false
          type: text-input
          variable: theme_status
        - label: artifact_summary
          max_length: 48000
          options: []
          required: false
          type: paragraph
          variable: artifact_summary
        - label: material_summary
          max_length: 48000
          options: []
          required: false
          type: paragraph
          variable: material_summary
      id: start
      position: {x: 60, y: 280}
      type: custom
    - data:
        context:
          enabled: true
          variable_selector: []
        desc: 对话编排主节点
        instructions: |
          # 角色
          你是 Nova，杰克「AI实战训练场」的实战演练项目设计助手。你协助企业培训管理者，通过对话完成一套训练主题的设计：从业务背景梳理、场景单元设计、客户画像构建、冰山能力建模到评估标准制定，最终产出一套结构化的、可直接发布的训练项目。

          # 输入变量
          - theme_status：主题当前状态（new=新会话无主题 / draft=草稿 / published=已发布）。它决定你当前是"创建模式"还是"更新模式"。
          - artifact_summary：当前主题产物的结构摘要（若非空，说明主题已有内容：场景名列表、画像类型、维度名与权重、案例情况）。
          - material_summary：用户已上传材料的解析摘要（可能为空）。

          # 阶段流程（状态机，按当前产物状态判断所处阶段）
          1.【背景了解】新会话：开场问候后询问三件事——所属行业与业务模式、主要训练对象、本次培训核心目标。若用户上传了材料，先阅读 material_summary 并主动给出材料摘要（核心目标/关键知识点/建议场景数量 5-7 个），再确认目标。不要一次问超过 3 个问题。
          2.【方向确认→自动建题】当用户给出明确方向（主题方向 + 至少一个训练目标，或材料解析已明确方向）时，**立即调用 create_topic 工具**创建草稿主题（名称要专业凝练，格式如"XX销售话术训练/XX职能实战演练"；描述一句话概括目标与人群），**无需向用户确认**，随后告知"已为你创建草稿主题《XX》"，继续细化目标。
          3.【场景规划】在生成前，先在聊天中给出场景规划方案（markdown 表格：场景名称/核心冲突/业务目标/难度星级）+ 客户画像建议 + 评估维度草案，并询问用户是否调整。**用户明确同意（如"可以/开始生成/没问题"）后才进入生成**。
          4.【生成主题】调用 generate_theme 工具（goal=核心目标一句话、audiences=人群数组、materialSummary=材料要点、keepExisting=更新模式且只需局部调整时为 true）。调用后在聊天中说"正在生成训练主题配置，请稍候…"，工具返回只表示任务已受理，**实际结果会以事件推送到右侧面板**。收到受理确认后告知用户右侧面板将实时更新。
          5.【产品档案询问】生成完成后询问是否需要为特定产品/岗位建立产品档案（说明可让训练更真实，但可跳过）。用户拒绝则直接进入案例环节。（本期产品档案仅询问，不生成。）
          6.【案例生成】建议逐场景或批量生成实战案例。用户同意后调用 generate_cases 工具（scenarioIds 留空=全部场景，difficulty: 0=按场景特点自定/1 简单/2 中等/3 困难）。生成中告知"正在生成实战案例，右侧面板将逐个更新"。
          7.【收尾】全部完成后给出概览表格（场景名/案例名/难度），提示用户"若配置符合预期，可点击右侧面板的「确认」按钮保存，随后在主题详情页发布上线"。更新模式（published）则提示"确认后内容将更新为新版本"。

          # 工具使用规则（严格遵守）
          - create_topic：仅在"当前无主题或用户要求改名/改描述"时调用；同会话不重复建主题。
          - update_artifact：用于小幅结构性修改（如材料可见性变更）。**场景/画像/维度的内容修改一律走 generate_theme（keepExisting=true）**，不要自己编 JSON 补丁去改场景内容。
          - generate_theme / generate_cases：是耗时任务，调用后不要在等待中输出虚假结果；只说明已开始，真实进度由右侧面板呈现。**同一时间只允许一个生成任务在跑**：如果 artifact_summary 显示生成可能仍在进行（用户刚触发过），提醒用户稍候。
          - 工具参数里的文本用中文，简洁准确；audiences、scenarioIds 等数组按 schema 传 JSON 数组。
          - 工具调用失败（返回 error）：向用户如实说明失败原因，并建议重试或调整输入；不要假装成功。

          # 对话风格
          - 专业、干练、温和。多用 markdown 结构化输出（表格/列表/分级标题），关键信息加粗。
          - 每次生成类操作前给一句"> 正在生成…，请稍候"的渐进提示（以引用块格式）。
          - 不确定用户意图时优先澄清而非猜测；用户提出 artifact_summary 之外的历史内容（如"上次那个场景"），以 artifact_summary 为准，没有就说没有。
          - 回复控制在必要长度：规划/概览用表格，过程性回复 3 句以内。
          - 绝不编造右侧面板未出现的内容；产物状态以 artifact_summary 与工具返回为准。
        model:
          config:
            completion_params:
              temperature: 0.3
            mode: chat
            name: Qwen3-30B-A3B-Instruct
            provider: langgenius/vllm/vllm
        plugins: null
        prompt_template:
        - id: system-prompt
          role: system
          text: '{{#sys.prompt#}}'
        selected: true
        title: Nova 编排
        tools:
        - enabled: true
          provider_id: create_topic
          provider_name: create_topic
          provider_type: api
          tool_label: 建草稿主题
          tool_name: create_topic
          tool_parameters:
            traceId:
              type: variable
              value: '{{#sys.trace_id#}}'
        - enabled: true
          provider_id: update_artifact
          provider_name: update_artifact
          provider_type: api
          tool_label: 更新产物
          tool_name: update_artifact
          tool_parameters:
            traceId:
              type: variable
              value: '{{#sys.trace_id#}}'
        - enabled: true
          provider_id: generate_theme
          provider_name: generate_theme
          provider_type: api
          tool_label: 生成主题配置
          tool_name: generate_theme
          tool_parameters:
            traceId:
              type: variable
              value: '{{#sys.trace_id#}}'
        - enabled: true
          provider_id: generate_cases
          provider_name: generate_cases
          provider_type: api
          tool_label: 生成实战案例
          tool_name: generate_cases
          tool_parameters:
            traceId:
              type: variable
              value: '{{#sys.trace_id#}}'
        type: agent
      id: agent
      position: {x: 380, y: 280}
      type: custom
```

---

## 工具 OpenAPI Schema（在 Dify「工具→API→创建」分 4 次导入，服务器填 `TOOL_BASE_URL` 变量）

### 工具 1：create_topic

```yaml
openapi: 3.0.0
info: { title: create_topic, version: '1.0' }
servers:
- url: '{{TOOL_BASE_URL}}/api/act/internal/tools'
paths:
  /create_topic:
    post:
      operationId: create_topic
      summary: 创建或重命名训练主题草稿（方向明确时自动调用，无需用户确认）
      parameters:
      - { name: traceId, in: query, required: true, schema: { type: string } }
      - { name: sessionId, in: query, required: true, schema: { type: string } }
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [topic]
              properties:
                topic: { type: string, description: 主题名称，专业凝练，如"柔性智造销售话术训练" }
                description: { type: string, description: 主题描述一句话（目标+人群） }
      responses:
        '200': { description: OK }
```

### 工具 2：update_artifact

```yaml
openapi: 3.0.0
info: { title: update_artifact, version: '1.0' }
servers:
- url: '{{TOOL_BASE_URL}}/api/act/internal/tools'
paths:
  /update_artifact:
    post:
      operationId: update_artifact
      summary: 以 JSON-Patch 增量更新主题产物（仅用于结构性小改动，如材料列表；场景内容修改请用 generate_theme）
      parameters:
      - { name: traceId, in: query, required: true, schema: { type: string } }
      - { name: sessionId, in: query, required: true, schema: { type: string } }
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [patches]
              properties:
                patches:
                  type: array
                  description: JSON-Patch 数组，op 固定 full_replace
                  items:
                    type: object
                    required: [op, path, value]
                    properties:
                      op: { type: string, enum: [full_replace] }
                      path: { type: string, description: '如 /materials' }
                      value: { description: 替换后的完整值 }
                      reason: { type: string }
      responses:
        '200': { description: OK }
```

### 工具 3：generate_theme

```yaml
openapi: 3.0.0
info: { title: generate_theme, version: '1.0' }
servers:
- url: '{{TOOL_BASE_URL}}/api/act/internal/tools'
paths:
  /generate_theme:
    post:
      operationId: generate_theme
      summary: 生成/重新生成完整训练主题配置（场景单元、客户画像、冰山模型、评估标准）。异步任务，返回仅表示已受理，结果实时推送右侧面板。
      parameters:
      - { name: traceId, in: query, required: true, schema: { type: string } }
      - { name: sessionId, in: query, required: true, schema: { type: string } }
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [goal, audiences]
              properties:
                goal: { type: string, description: 核心训练目标一句话 }
                audiences: { type: array, items: { type: string }, description: 训练人群 }
                materialSummary: { type: string, description: 材料要点摘要，无材料传空串 }
                keepExisting: { type: boolean, description: true=在现有内容基础上调整（更新模式），false=全新生成 }
      responses:
        '200': { description: OK }
```

### 工具 4：generate_cases

```yaml
openapi: 3.0.0
info: { title: generate_cases, version: '1.0' }
servers:
- url: '{{TOOL_BASE_URL}}/api/act/internal/tools'
paths:
  /generate_cases:
    post:
      operationId: generate_cases
      summary: 为场景单元批量生成实战案例（对练剧本）。异步任务，每完成一个场景推送一次，结果实时更新右侧面板。
      parameters:
      - { name: traceId, in: query, required: true, schema: { type: string } }
      - { name: sessionId, in: query, required: true, schema: { type: string } }
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                scenarioIds: { type: array, items: { type: string }, description: 要生成的场景ID列表，留空=全部场景 }
                difficulty: { type: integer, enum: [0, 1, 2, 3], description: '0=按场景特点自定，1简单 2中等 3困难' }
      responses:
        '200': { description: OK }
```

---

## Java 侧对接要点（给后端编码智能体的约束）

1. Dify Agent 的工具调用 URL 实为 `POST {TOOL_BASE_URL}/api/act/internal/tools/{name}?traceId=...&sessionId=...`，sessionId 由 Java 在每次 `POST /v1/chat-messages` 的 inputs 里注入不了 query——**解决办法**：Java 调 Dify 时在 inputs 中传 `trace_id` 与 `session_id` 两个变量，工具 Schema 的 query 参数改为从 Dify 上下文变量取值（在工具参数配置里绑定 `{{#sys.session_id#}}` 不支持时，简化为：工具端点仅靠 traceId 定位会话——Java 维护 traceId→sessionId 映射）。**最终实现以 traceId 定位为准**，DSL 中 sessionId 参数保留但可为空。
2. `POST /v1/chat-messages` 入参：`{inputs:{theme_status, artifact_summary, material_summary}, query:<用户文本>, response_mode:"streaming", conversation_id:<dify_conversation_id>}`；首响 `conversation_id` 回存 act_ai_session。
3. SSE 事件映射：`agent_message`→part-content(text_delta)；`message_end`→session-finish 前置落库；`error`→failed 事件+聊天提示。
4. 模型：vllm 插件 Qwen3-30B（temperature 0.3；生成类在两个工作流里另有配置）。
