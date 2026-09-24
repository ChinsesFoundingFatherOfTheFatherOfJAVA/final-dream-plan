# Dify DSL ③：案例生成工作流（Workflow 应用）

> Dify 版本：1.10.1 ｜ 应用类型：Workflow
> 导入后发布 → API Key 填 `dify.case-gen-key`
> 设计要点：**单场景单次调用**（Java 逐场景循环，并发 2）——单次输出 <3KB、耗时 <60s，稳定且单场景失败不拖垮全局；Java 每完成一个场景即推 case-generated 事件（渐进体验同线上）。

---

```yaml
app:
  description: AI实战训练场·实战案例（对练剧本）生成——单场景
  icon: 🎭
  icon_background: '#E8833A'
  mode: workflow
  name: 案例生成-case-gen
kind: app
version: 0.1.5

workflow:
  environment_variables: []
  features: {}
  graph:
    edges:
    - { id: e1, source: start, sourceHandle: source, target: llm_case, targetHandle: target, type: custom }
    - { id: e2, source: llm_case, sourceHandle: source, target: code_case, targetHandle: target, type: custom }
    - { id: e3, source: code_case, sourceHandle: source, target: end, targetHandle: target, type: custom }
    nodes:
    - data:
        title: 开始
        type: start
        variables:
        - { variable: scenario_json, label: 场景定义JSON(含13项字段+维度), type: paragraph, required: true, max_length: 8000 }
        - { variable: customer_profiles, label: 客户画像列表JSON, type: paragraph, required: true, max_length: 6000 }
        - { variable: difficulty, label: 难度(1简单2中等3困难), type: text-input, required: true, max_length: 2 }
        - { variable: goal, label: 主题核心目标, type: paragraph, required: true, max_length: 500 }
      id: start
      position: {x: 40, y: 280}
      type: custom

    - data:
        title: 生成实战案例剧本
        type: llm
        model:
          completion_params: { temperature: 0.6 }
          mode: chat
          name: Qwen3-30B-A3B-Instruct
          provider: langgenius/vllm/vllm
        prompt_template:
        - role: system
          text: |
            你是资深情景剧本编剧，擅长把培训场景改写成有张力的实战对话案例。你要为学员设计一个"AI 陪练角色"，让学员在该角色的对抗/协作中练习目标能力。

            ## 输入
            主题目标：{{#start.goal#}}
            场景定义：{{#start.scenario_json#}}
            可选客户画像（优先从中选角色原型）：{{#start.customer_profiles#}}
            难度：{{#start.difficulty#}}（1简单：单点诉求、态度温和；2中等：两个诉求叠加、有情绪波动；3困难：施压对抗、抛出合规/利益威胁、带隐藏动机）

            ## 生成要求
            1. scriptName："冲突主题：化解方式"格式（如"高压催单下的精准录入：特殊包装与地址核对的生死线"），不超过 25 字。
            2. 角色设定（学员的对话对象）：
               - actorName：常见中文名；actorPosition/actorCompany：贴合业务的职位与公司名（可用"宏达科技"类虚构名）
               - actorType：身份一句话；actorPersonality：3~5 个性格词+一句行为化说明
               - actorCommunicationStyle：沟通风格具体化（语速/口头禅/施压方式）
            3. scriptBackground：300 字内情境铺垫——学员身份、事件起因、角色处境与立场、利益关系（必须呼应场景 coreConflict）。
            4. scriptOpening：角色的开场白，150 字内。**必须包含**：（情绪/动作舞台指示）+ 直接抛出冲突的台词。情绪强度与难度匹配（1 温和提问；2 明显不满；3 拍桌/威胁式开场）。台词要口语化、有业务细节（具体数字/期限/条款），让学员一读就能进入情境。
            5. 角色动机、施压点必须来自场景的 coreConflict/difficulties，禁止与场景无关的冲突。

            ## 输出（仅输出 JSON，无其他文字）
            {"scriptName":"…","difficulty":{{#start.difficulty#}},"actorName":"…","actorPosition":"…","actorCompany":"…","actorType":"…","actorPersonality":"…","actorCommunicationStyle":"…","scriptBackground":"…","scriptOpening":"…"}
        - role: user
          text: 请为该场景生成实战案例。
      id: llm_case
      position: {x: 340, y: 280}
      type: custom

    - data:
        title: 解析与字段校验
        type: code
        code_language: python3
        code: |
          import json, re
          REQ = ["scriptName","actorName","actorType","actorPersonality","scriptBackground","scriptOpening"]
          def main(arg0: str, difficulty: str) -> dict:
              t = arg0.strip()
              m = re.search(r'\{.*\}', t, re.S)
              if not m: raise ValueError("output is not JSON")
              c = json.loads(m.group(0))
              miss = [k for k in REQ if not c.get(k)]
              if miss: raise ValueError("missing fields: " + ",".join(miss))
              if len(c["scriptOpening"]) < 40: raise ValueError("opening too short")
              c["difficulty"] = int(difficulty)
              c.setdefault("actorPosition",""); c.setdefault("actorCompany",""); c.setdefault("actorCommunicationStyle","")
              return {"case_json": json.dumps(c, ensure_ascii=False)}
        variables:
        - { variable: arg0, value_selector: [llm_case, text] }
        - { variable: difficulty, value_selector: [start, difficulty] }
        outputs: { case_json: {type: string} }
      id: code_case
      position: {x: 640, y: 280}
      type: custom

    - data:
        title: 结束
        type: end
        outputs:
        - { variable: case_json, value_selector: [code_case, case_json] }
      id: end
      position: {x: 940, y: 280}
      type: custom
```

---

## Java 侧对接要点

1. 调用：`POST /v1/workflows/run`，`inputs = {scenario_json: <该场景完整JSON含dimensionWeights>, customer_profiles: <画像数组JSON>, difficulty: "1|2|3", goal}`，blocking，超时 120s。
2. **逐场景循环**（generateExecutor 并发 2）：每场景独立调用；单场景失败重试 1 次，仍失败标记该场景 failed 并推 `case-generated {status:"failed"}`（含 error），不影响其他场景。
3. 每场景成功：解析 case_json → 合入工作区 artifact 对应 scenario.cases[] + caseArtifactIds（Java 生成雪花 id）→ 推 `case-generated {status:"completed", scriptName, difficulty, scenarioId, id, jsonArtifactId, subjectId: artifactId}`。
4. difficulty=0（自定）时 Java 按场景在 artifact 中的冲突强度映射：maxTime≥20 或 difficulties≥3 条 → 3；否则含"质疑/施压"关键词 → 2；默认 1。（避免再调一次 LLM。）
5. Java 校验兜底：actorName 非空、scriptOpening ≥40 字（与代码节点一致）；不通过按失败流程处理。
