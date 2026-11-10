# 训考运行态接口与 JSON Schema

> 版本：v1.0 ｜ 日期：2026-10-30
> 调用方：`AtualCombatTraining`
> 被调方：`AIGentService`
> 目的：补齐学员训练/考核 runtime 的内部接口、结构化输出、流事件、校验和重试规则。

机器可读文件：

- `schemas/drill-script-v1.schema.json`
- `schemas/drill-report-v1.schema.json`
- `schemas/drill-suggest-v1.schema.json`
- `schemas/drill-chat-event-v1.schema.json`

## 1. 边界

- ACT 负责 attempt、权限、次数、计时、快照、目标状态、最终 `passed` 和持久化。
- AIGentService 负责脚本生成、角色回合生成、训练建议和结构化评分。
- AIGentService 不直接写 ACT 表，不决定最终是否通过。
- 所有输出必须带 `schemaVersion`，ACT 只接受本文定义的版本。

内部接口统一携带：

```http
X-Internal-Token: <AIGENT_INTERNAL_TOKEN>
Content-Type: application/json
```

`sessionId` 使用 attemptId，保证同一 attempt 在 AIGentService 侧的记忆可恢复。

## 2. 接口总表

| 编号 | 方法/路径 | 模式 | 用途 |
|---|---|---|---|
| AG-D01 | `POST /internal/agent/task/drill-script` | 阻塞 JSON | **生成自定义练习脚本**（随机练习已在发布期预生成，不再走本接口） |
| AG-D02 | `POST /internal/agent/drill/chat` | SSE | 生成训练点评、角色回应和目标进度 |
| AG-D03 | `POST /internal/agent/drill/suggest` | 阻塞 JSON | 训练模式建议 |
| AG-D04 | `POST /internal/agent/task/drill-report` | 阻塞 JSON | 生成结构化报告 |

案例练习优先直接使用发布快照，不调用 AG-D01；只有需要补全 AI 演员形象/语音参数时才可调用脚本规范化步骤。

> **2026-11-04 变更（t13）**：AG-D01 的调用时机从「随机/自定义开练时」收窄为「仅自定义开练时」。
> 原因见 §4.0，依据是抓包实测（`tmp/investigation-R2R3.md` §4.3）。
> 影响模块：`AttemptLifecycleServiceImpl`（创建分流）、`RandomScriptServiceImpl`（新增，发布期调用）、
> `PublishInitServiceImpl`（发布收尾触发预生成）。AG-D01 的**请求/响应契约本身未变**。

### 4.0 随机脚本：发布期预生成 + 取档（2026-11-04 新增）

**为什么改**：抓包实测证明原平台的随机脚本**不是开练现场生成的**——

- 4 场景 × 3 难度 = 12 份随机脚本，全部在发布窗口 `2026-11-03T16:27:07~16:28:17`（70 秒）内生成完毕；
- 从**从未练习过**的场景 3/4 直接调 `randomScript`，产物 `create_time` 仍是该发布窗口，且**没有新建**任何产物；
- 即 `randomScript?difficulty=N` 是**取档接口，不调模型**。

**落库形态**：新表 `act_random_script`（`05-建表SQL.md` §9.1），按
`(theme_id, version_no, scenario_unit_id, difficulty, candidate_no)` 分档，
唯一键保证重复发布幂等。

**生成规则**：

1. 发布收尾时（首次发布 v1 / AI 确认升版）为「每个场景 × 每个难度档 1/2/3」生成候选；
2. 每档候选数 `CANDIDATES_PER_BUCKET = 2`（**首期定死，不可运行期配置**）——原平台上限未知，
   只实测到同档在 2 个 targetId 间 7:7 摆动，先按实测下限实现；
3. **命中案例难度档时复用案例正文**：若某难度档 == 该场景案例自带难度，直接落案例脚本正文，不调模型
   （原平台实证：`a2_d2` 与场景 02 案例是同一个 artifact）；
4. 单档生成失败只记日志并跳过，取档时由降级链兜底，不阻断整次发布。

**取档接口**（本项目新增，对齐原平台 `randomScript`）：

- `GET /api/act/student/themes/{themeId}/scenarios/{scenarioId}/random-script?difficulty=N`
- 返回 `{difficulty, requestedDifficulty, degraded, script}`；`degraded=true` 表示发生了降级
  （本档无候选 → 其他档 → 案例正文），前端可据此提示。
- **降级链不静默返回空**：连案例正文都没有时明确报错「该场景尚未生成随机练习脚本，请先在管理端发布」。

**与「再练一次」的关系（用户已拍板）**：

- 再练一次**不走取档**，直接复用上次 attempt 的 `scriptSnapshotJson`（`reuseFromAttemptId` 分支）；
- 理由：原平台同档取档**不可复现**（同一 (场景,难度) 在 2 个 targetId 间 7:7 摆动），
  再练若重取必然换人换脸，与用户实测的「沿用上次」相矛盾。


## 3. 通用请求

现有 `AgentTaskRequest` 的 `inputs` 是 `Map<String,String>`，复杂值统一使用 JSON 字符串：

```json
{
  "sessionId": "attempt-id",
  "traceId": "trace-id",
  "inputs": {
    "attempt_id": "attempt-id",
    "practice_type": "custom",
    "difficulty": "2",
    "scenario_json": "{...}",
    "settings_json": "{...}",
    "custom_config_json": "{...}",
    "product_profiles_json": "[{...}]",
    "materials_summary_text": "..."
  }
}
```

ACT 在调用前校验 JSON 字符串，不允许透传未验证的客户端原文。

## 4. AG-D01：脚本生成

### 4.1 请求

```json
{
  "sessionId": "a1",
  "traceId": "t1",
  "inputs": {
    "attempt_id": "a1",
    "theme_id": "th1",
    "scenario_id": "sc1",
    "practice_type": "random",
    "study_mode": "1",
    "difficulty": "2",
    "ai_response_mode": "1",
    "scenario_json": "{\"id\":\"sc1\",\"name\":\"初次拜访\",\"businessGoal\":\"...\",\"timeLimitMinutes\":15,\"dimensions\":[{\"id\":\"d1\",\"name\":\"需求挖掘\",\"weight\":40}]}",
    "settings_json": "{\"dialogModes\":[\"voice\",\"text\"],\"coachReviewEnabled\":true}",
    "custom_config_json": "{\"sceneBackground\":\"...\",\"actor\":{\"name\":\"王总\",\"identity\":\"客户\",\"personalities\":[\"严谨\"]}}",
    "product_profiles_json": "[{\"profileKey\":\"pp_1\",\"profileName\":\"成套智联2.0\",\"detailMarkdown\":\"...\"}]",
    "materials_summary_text": "场景相关学习材料摘要"
  }
}
```

`practice_type=case` 时可省略 `custom_config_json`。

### 4.2 响应

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "outputs": {
      "script_schema_version": "drill-script-v1",
      "script_json": "{...}",
      "success": "true"
    }
  }
}
```

ACT 必须解析 `script_json` 并按 §5 二次校验。

## 5. DrillScriptV1

```json
{
  "schemaVersion": "drill-script-v1",
  "attemptId": "a1",
  "scenarioId": "sc1",
  "practiceType": "random",
  "studyMode": 1,
  "difficulty": 2,
  "scene": {
    "name": "初次拜访：破冰与价值初探",
    "narration": "周一下午，客户办公室。",
    "background": "客户刚经历一次失败项目。",
    "openingLine": "你好，我只有15分钟。",
    "location": "客户办公室",
    "timeLabel": "周一下午"
  },
  "userRole": {
    "name": "销售顾问",
    "identity": "杰克科技销售顾问",
    "ageRange": "25-35岁",
    "background": "新入职销售",
    "allowedResources": ["产品档案", "案例材料"],
    "forbiddenBehaviors": ["直接报价", "贬低竞品"]
  },
  "actor": {
    "name": "王总",
    "identity": "生产总监",
    "gender": "男",
    "ageRange": "40-45岁",
    "personality": ["务实", "谨慎"],
    "communicationStyle": "语速中等，喜欢反问。",
    "explicitGoals": ["快速判断方案价值"],
    "implicitGoals": ["确认交付风险可控"],
    "hiddenFacts": ["之前项目失败"],
    "behaviorPatterns": ["频繁看表", "用反问施压"],
    "voice": {
      "provider": "server-default",
      "voiceId": "server-default",
      "speed": 1.0
    },
    "avatarPrompt": "middle-aged Chinese manufacturing director"
  },  "goals": {
    "practiceGoal": "建立信任并预约下一次方案演示",
    "behaviorGuidance": [
      "先回应客户旧项目失败的顾虑",
      "用开放式问题挖掘痛点",
      "量化价值",
      "明确推进下一步"
    ],
    "failureSignals": [
      "客户明确表示时间到了",
      "客户连续拒绝回答"
    ]
  },
  "evaluation": {
    "passScore": 70,
    "dimensions": [
      {
        "id": "d1",
        "name": "需求挖掘与倾听",
        "weight": 40,
        "description": "识别客户核心痛点",
        "excellentStandard": "...",
        "goodStandard": "...",
        "improveStandard": "..."
      }
    ]
  },
  "runtime": {
    "maxDurationSeconds": 900,
    "maxRounds": 50,
    "targetProgressMode": "milestones"
  },
  "productProfileKeys": ["pp_1"],
  "generatedAt": "2026-10-30 10:00:00"
}
```

### 5.1 必填与约束

- `scene.name/background/openingLine` 非空。
- `actor.name/identity` 非空。
- `actor.personality` 1~8 项。
- `goals.practiceGoal` 非空，`behaviorGuidance` 2~8 项。
- `evaluation.dimensions` 1~8 项，ID 唯一，权重合计 100（容差 0.01）。
- `runtime.maxDurationSeconds` 60~3600。
- `runtime.maxRounds` 1~100。

> **`actor.avatarPrompt` 已废弃（deprecated，2026-11-04）**。
>
> 保留字段位、**不删除**，但不再作为形象来源。原因：抓包实测（`tmp/r4-avatar-plan.md`）
> 证明原平台的数字人形象来自**预置素材库按角色属性映射**（`actor_config.image_url` 形如
> `av-gen-{m|f}-{年龄档}-{行业码}-{序号}.webp`），不是由提示词现场生图；
> 且全库核查结果为「有字段、无数据、无消费、无存储」——生成提示词从未产出它，Java/Vue/SQL 零消费。
>
> 新的形象口径见 `tmp/r4-avatar-impl.md`：形象挂在**角色定义**上（与难度档解耦），
> 通过 `gender` + `ageRange` 映射预置库。**写入方不得再填 avatarPrompt**；
> 消费方读到该字段应忽略。Schema 中保留 `["string","null"]` 以兼容历史快照。
>
> 2026-11-10：`actor.gender` 正式进入 Schema（`"男"` / `"女"` / null），
> 它同时决定**数字人形象**和**对手 TTS 音色**，两者按同一套「性别 × 年龄段」口径映射：
> 性别归一 male/female，年龄取区间下界落 A1(20-28)/A2(29-36)/A3(37-45)/A4(46-55)/A5(56+)。
> 性别缺失时形象退化到场景默认图、音色回退默认音色，不报错也不猜。
> 案例快照用扁平 `actorGender` / `actorAgeRange`，消费方两种形态都要认。

- `schemaVersion` 必须为 `drill-script-v1`。
- `studyMode` 只能是 1 或 2。
- 考核脚本不得包含教练点评文案。

## 6. AG-D02：角色回合 SSE

### 6.1 请求

```json
{
  "sessionId": "a1",
  "traceId": "turn-trace",
  "query": "王总您好，想先了解目前排产最大的问题。",
  "inputs": {
    "attempt_id": "a1",
    "client_message_id": "msg-uuid",
    "turn_no": "2",
    "study_mode": "1",
    "script_schema_version": "drill-script-v1",
    "script_json": "{...}",
    "settings_json": "{\"coachReviewEnabled\":true,\"suggestionEnabled\":true}",
    "recent_messages_json": "[{\"role\":\"assistant\",\"text\":\"...\"},{\"role\":\"user\",\"text\":\"...\"}]",
    "transcript_summary": "前一轮已建立基本信任。",
    "progress_json": "{\"targetProgress\":25,\"round\":1}"
  }
}
```

### 6.2 SSE 事件

每帧沿用现有内部 SSE 格式：

```text
data: {"event":"...","...":"..."}
```

| event | payload | 说明 |
|---|---|---|
| `turn_start` | `messageId, turnNo` | ACT 可映射为 `turn.started` |
| `coach_start` | `messageId` | 训练模式且有教练点评时 |
| `coach_delta` | `messageId, delta` | 教练点评增量 |
| `coach_end` | `messageId, text` | 教练点评完成 |
| `assistant_start` | `messageId` | 角色台词开始 |
| `assistant_delta` | `messageId, delta` | 角色台词增量 |
| `assistant_end` | `messageId, text, ttsConfig` | 角色台词完成 |
| `progress` | `targetProgress, deltaReason, behaviorHits` | 目标进度更新 |
| `message_end` | `conversation_id, task_id, message_id` | 本轮结束 |
| `error` | `code, message, retryable` | 失败 |

规则：

- `targetProgress` 必须为 0~100，同一 attempt 内不得下降。
- `behaviorHits` 使用脚本中 `behaviorGuidance` 的索引或稳定 key。
- 考核模式禁止输出 `coach_*`。
- 建议未开启时禁止调用 suggestion。
- `messageId` 在完整回合内保持不变。

## 7. AG-D03：训练建议

### 7.1 请求

```json
{
  "sessionId": "a1",
  "traceId": "suggest-trace",
  "inputs": {
    "attempt_id": "a1",
    "turn_no": "3",
    "script_json": "{...}",
    "recent_messages_json": "[...]",
    "progress_json": "{\"targetProgress\":40,\"round\":2}"
  }
}
```

### 7.2 响应

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "outputs": {
      "suggest_schema_version": "drill-suggest-v1",
      "analysis": "客户关注交付风险，应先共情再追问。",
      "sampleReply": "王总，上次项目没落地确实会增加顾虑……",
      "focusHints": ["先回应顾虑", "避免直接推方案"]
    }
  }
}
```

- 只对训练模式开放。
- 建议不写入正式 transcript，作为独立教学辅助记录。

## 8. AG-D04：报告生成

### 8.1 请求

```json
{
  "sessionId": "a1",
  "traceId": "report-trace",
  "inputs": {
    "attempt_id": "a1",
    "study_mode": "1",
    "practice_type": "case",
    "end_reason": "manual_exit",
    "timed_out": "false",
    "duration_seconds": "673",
    "round_count": "6",
    "pass_score": "70",
    "script_json": "{...}",
    "transcript_json": "[{\"role\":\"user\",\"text\":\"...\"}]",
    "settings_snapshot_json": "{...}"
  }
}
```

### 8.2 响应

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "outputs": {
      "report_schema_version": "drill-report-v1",
      "report_json": "{...}",
      "success": "true"
    }
  }
}
```

## 9. DrillReportV1

```json
{
  "schemaVersion": "drill-report-v1",
  "targetReached": true,
  "targetReason": "学员已建立信任、明确痛点并约定下一次演示。",
  "overallComment": "整体表现良好……",
  "dimensions": [
    {
      "id": "d1",
      "name": "需求挖掘与倾听",
      "score": 92,
      "weight": 40,
      "evidence": ["..."],
      "strength": "...",
      "improvement": "...",
      "reason": "..."
    }
  ],
  "improvementSuggestions": [
    {
      "title": "避免过早推进",
      "detail": "...",
      "sampleReply": "..."
    }
  ],
  "keyDialogues": [
    {
      "type": "excellent|attention|rewrite",
      "quote": "...",
      "comment": "..."
    }
  ],
  "recommendations": [
    "复杂异议处理与节奏控制"
  ]
}
```

### 9.1 约束

- `dimensions` 必须与脚本维度一一对应。
- 每个维度 `0 <= score <= 100`，`weight` 与快照一致。
- 权重合计 100。
- `targetReached` 必须带非空 `targetReason`。
- AIGentService 不返回最终 `passed`。
- ACT 计算：

```text
totalScore = round(sum(score * weight / 100), 1)
passed = totalScore >= passScore
         && targetReached
         && endReason != manual_exit
         && endReason != screen_violation
```

## 10. 错误与重试

| code | 场景 | ACT 行为 |
|---|---|---|
| `DRILL_INPUT_INVALID` | 输入 JSON/字段非法 | 不重试，attempt 失败 |
| `DRILL_SCHEMA_INVALID` | 输出 schema 非法 | 带错误信息重试 1 次 |
| `DRILL_TIMEOUT` | 超时 | 脚本可重试；报告保持 generating 并补偿；chat 当前轮失败 |
| `DRILL_LLM_ERROR` | 模型/网络错误 | 可重试 1 次 |
| `DRILL_CANCELLED` | attempt 已取消 | 不重试 |

重试规则：

- 脚本/报告：最多 1 次自动重试，第二次失败标 attempt 错误。
- 角色回合：只重试未产生任何 `assistant_delta` 的失败；已有增量则标记当前轮失败，避免重复台词。
- 所有请求带 `traceId + attemptId + clientMessageId` 做幂等。

## 11. 验收

- 同一输入生成的 `DrillScriptV1` 通过 Java 校验器。
- 考核流中没有 `coach_*`。
- `targetProgress` 单调不降。
- report 的维度 ID/权重与 attempt 快照一致。
- 主动退出和切屏违规由 ACT 强制 `passed=false`。
- 任意失败不会造成重复扣次数或重复报告。
