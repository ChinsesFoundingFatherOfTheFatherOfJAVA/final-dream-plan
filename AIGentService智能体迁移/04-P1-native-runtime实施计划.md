# P1 Native Runtime 实施计划

> 日期：2026-10-22
> 目标：先打通自由演练助手的最小 native 垂直链路，不同时迁移 P2/P3。
> 模型：`qwen3.8-flash`（千问兼容模式，复用 `SPEECH_DASHSCOPE_API_KEY`）。
> DSL：`D:\JACK\plan\final_dream_difys\自由演练助手.yml` 为唯一权威源。

> **实施进度（2026-10-22）**：Task 1~5 已完成并通过定向/全量测试；真实千问
> 模糊需求 smoke 已通过。最终取舍见 `05-P1实施偏差与决策记录.md`。

## 1. 范围

本阶段实现：

1. AIGentService 的千问兼容客户端；
2. ReAct 工具调用循环；
3. 工具阶段拦截：无主题时只允许 `create_topic`，未明确确认时禁止生成类工具；
4. AIGentService 到 AtualCombatTraining 的 4 个内部工具 HTTP 调用；
5. AtualCombatTraining `NativeAgentClient` 与 `agent.chat.provider=dify|native` 分流；
6. 最小 SSE 事件：`agent_message`、`message_end`、`error`。

本阶段暂不实现：

- Redis L2、DB L3 重建；
- P2/P3 workflow 迁移；
- 多实例共享会话；
- Dify 全量下线。

## 2. 接口

### AIGentService

`POST /internal/agent/chat`

```json
{
  "sessionId": "session-id",
  "traceId": "trace-id",
  "query": "用户输入",
  "inputs": {
    "theme_status": "new|draft|published",
    "artifact_summary": "",
    "material_summary": ""
  }
}
```

响应为 SSE：

- `agent_message`：`answer` 增量文本；
- `message_end`：结束事件；
- `error`：失败事件。

### AtualCombatTraining

配置：

```properties
agent.chat.provider=dify
agent.chat.native.base-url=http://localhost:8086
agent.chat.native.timeout-ms=300000
```

`native` 模式只替换编排调用，不改 WS、消息落库和工具事件链路。

## 3. 文件规划

### AIGentService

- `config/AgentProperties.java`：模型和工具地址配置；
- `llm/LlmClient.java`、`QwenClient.java`：Qwen 兼容调用；
- `llm/LlmMessage.java`、`LlmRequest.java`、`LlmResponse.java`：模型契约；
- `engine/ReActEngine.java`：循环、工具调用、最终文本；
- `engine/ToolStageGuard.java`：工具阶段规则；
- `engine/ToolRegistry.java`：工具执行接口；
- `tools/AssistantHttpToolClient.java`：调用 AtualCombatTraining 内部工具；
- `controller/InternalAgentController.java`：SSE 端点；
- `resources/prompts/free-practice.md`：从权威 DSL 提取的 instruction。

### AtualCombatTraining

- `dify/NativeAgentClient.java`：调用 AIGentService SSE；
- `service/impl/AssistantChatServiceImpl.java`：provider 分流；
- `application.properties`：provider 与 native 地址；
- 测试：native SSE 解析、provider 选择、错误收尾。

## 4. TDD 任务

### Task 1：工具阶段拦截

先写 `ToolStageGuardTest`，覆盖：

- `theme_status=new` 且无明显方向：不调用 `create_topic`；
- 方向明确：允许 `create_topic`；
- 未明确确认：禁止 `generate_theme`/`generate_cases`；
- 明确确认：允许生成类工具；
- 已有主题：禁止重复 `create_topic`。

实现 `ToolStageGuard`，不联网。

验证：`mvnw.cmd -Dtest=ToolStageGuardTest test`

### Task 2：ReAct 循环

先写 `ReActEngineTest`：

- 模型第一次返回 `create_topic` tool call，第二次返回最终文本；
- 验证工具只执行一次、工具结果回填、最终文本返回；
- 工具被拦截时不执行，改为给模型返回明确错误。

实现 `ReActEngine`、`ToolRegistry` 和 `LlmClient` 的最小版本。

验证：`mvnw.cmd -Dtest=ReActEngineTest test`

### Task 3：千问客户端与 SSE

先写 `QwenClientTest` 或在临时 smoke 中验证：

- 请求体模型名、tools、temperature；
- 解析 `tool_calls`、文本、`reasoning_content`；
- 空 `content` 但有 tool call 时不能误判成功文本。

实现 `QwenClient` 和配置。

### Task 4：内部工具执行

先写 `AssistantHttpToolClientTest`：

- `create_topic` 路径和 query 参数正确；
- 工具响应解析为文本 observation；
- 上游非 200/业务 code 非 0 时不静默成功。

实现 `AssistantHttpToolClient`，默认指向 `http://localhost:8082`。

### Task 5：SSE 与 AtualCombatTraining 接入

先写 `NativeAgentClientTest`：

- 解析 `agent_message`、`message_end`、`error`；
- 保持 `AssistantChatServiceImpl` 的落库和 WS 收尾逻辑不变。

实现 `NativeAgentClient`、provider 分流和配置。

验证：

```powershell
cmd /c "mvnw.cmd test"
```

### Task 6：端到端 smoke

用真实 Qwen：

1. 新会话模糊需求：只追问，不调用工具；
2. 明确方向：`create_topic`；
3. 明确确认：`generate_theme`；
4. `generate_cases`；
5. 观察 WS `topic-changed`/`artifact-generated`/`case-generated` 事件。

## 5. 验收

- `qwen3.8-flash` 真实调用成功；
- 工具阶段错误不会写入业务数据；
- provider 切换不重启即可生效；
- native 失败能返回可读错误并切回 dify；
- AtualCombatTraining 现有测试全绿；
- AIGentService 新测试全绿；
- 不修改 `final_dream_difys` 权威 DSL 内容。
