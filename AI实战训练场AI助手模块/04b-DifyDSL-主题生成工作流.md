# Dify DSL ②：主题生成工作流（Workflow 应用）

> Dify 版本：1.10.1 ｜ 应用类型：Workflow
> 导入后发布 → API Key 填 `dify.theme-gen-key`
> 设计要点：**三段式 LLM 串行生成**（场景列表 → 画像+冰山 → 评估维度），每段 <90s 防 300s 超时；Java 侧聚合校验。

---

```yaml
app:
  description: AI实战训练场·训练主题配置生成（场景/画像/冰山/评估标准）
  icon: 🎯
  icon_background: '#6B5CE7'
  mode: workflow
  name: 主题生成-theme-gen
kind: app
version: 0.1.5

workflow:
  environment_variables: []
  features: {}
  graph:
    edges:
    - { id: e1, source: start, sourceHandle: source, target: llm_scenes, targetHandle: target, type: custom }
    - { id: e2, source: llm_scenes, sourceHandle: source, target: code_scenes, targetHandle: target, type: custom }
    - { id: e3, source: code_scenes, sourceHandle: source, target: llm_profiles, targetHandle: target, type: custom }
    - { id: e4, source: llm_profiles, sourceHandle: source, target: code_profiles, targetHandle: target, type: custom }
    - { id: e5, source: code_profiles, sourceHandle: source, target: llm_criteria, targetHandle: target, type: custom }
    - { id: e6, source: llm_criteria, sourceHandle: source, target: code_merge, targetHandle: target, type: custom }
    - { id: e7, source: code_merge, sourceHandle: source, target: end, targetHandle: target, type: custom }
    nodes:
    - data:
        title: 开始
        type: start
        variables:
        - { variable: goal, label: 核心训练目标, type: paragraph, required: true, max_length: 2000 }
        - { variable: audiences, label: 训练人群(JSON数组字符串), type: paragraph, required: true, max_length: 500 }
        - { variable: material_summary, label: 材料摘要, type: paragraph, required: false, max_length: 20000 }
        - { variable: keep_existing, label: 保留现有内容调整, type: text-input, required: false, max_length: 10 }
        - { variable: existing_scenes, label: 现有场景名列表(JSON数组,更新模式), type: paragraph, required: false, max_length: 3000 }
      id: start
      position: {x: 40, y: 300}
      type: custom

    - data:
        title: ①生成场景列表
        type: llm
        model:
          completion_params: { temperature: 0.4 }
          mode: chat
          name: Qwen3-30B-A3B-Instruct
          provider: langgenius/vllm/vllm
        prompt_template:
        - role: system
          text: |
            你是资深企业培训设计师，精通岗位任务拆解与情景模拟设计。基于训练目标、人群与材料，设计一套训练场景单元。

            ## 输入
            核心目标：{{#start.goal#}}
            训练人群：{{#start.audiences#}}
            材料摘要：{{#start.material_summary#}}
            {% if start.keep_existing == 'true' %}
            ## 更新模式
            现有场景：{{#start.existing_scenes#}}
            请保留现有场景的名称与大体结构（除非目标要求增删），只按新目标优化各场景的字段内容。
            {% endif %}

            ## 要求
            1. 设计 4~6 个场景（若材料丰富可 7 个），覆盖业务全流程：从基础规范到高难度冲突递进。
            2. 每个场景字段：
               - name："A：B"格式（业务环节：具体冲突/任务），20字内
               - audiences：适用人群（从训练人群派生）
               - businessGoal：业务目标，一句话，动词开头
               - behaviorGoals：行为目标 3~4 条，可观察可衡量
               - businessImpact / failureCost：业务影响/失败代价，一句话写实
               - coreConflict：核心冲突，"A的诉求 vs B的约束"式张力描述
               - failureReasons：常见失败模式 2~3 条（"×"级具体行为）
               - difficulties：困难挑战 2~3 条
               - forbidBehaviors：禁止行为 2~3 条（"禁止…"开头，合规红线）
               - maxTime：时长 10~30 分钟
            3. 内容必须贴合材料与真实业务语境，禁止空话套话；量化处给量化（金额/时长/层级）。
            4. 为每个场景生成 id：格式 "sc-" + 两位序号（sc-01…）；dimensionIds 留待第三步，此处不填。

            ## 输出（仅输出 JSON，无其他文字）
            {"scenes":[{"id":"sc-01","name":"…","audiences":["…"],"businessGoal":"…","behaviorGoals":["…"],"businessImpact":"…","failureCost":"…","coreConflict":"…","failureReasons":["…"],"difficulties":["…"],"forbidBehaviors":["…"],"maxTime":15}]}
        - role: user
          text: 请生成场景列表。
      id: llm_scenes
      position: {x: 340, y: 300}
      type: custom

    - data:
        title: 解析场景JSON
        type: code
        code_language: python3
        code: |
          import json, re
          def main(arg0: str) -> dict:
              t = arg0.strip()
              m = re.search(r'\{.*\}', t, re.S)
              if m: t = m.group(0)
              scenes = json.loads(t)["scenes"]
              names = [s["name"] for s in scenes]
              return {"scenes_json": json.dumps(scenes, ensure_ascii=False), "scene_names": json.dumps(names, ensure_ascii=False), "scene_count": len(scenes)}
        variables: [{ variable: arg0, value_selector: [llm_scenes, text] }]
        outputs: { scenes_json: {type: string}, scene_names: {type: string}, scene_count: {type: number} }
      id: code_scenes
      position: {x: 640, y: 300}
      type: custom

    - data:
        title: ②生成画像与冰山模型
        type: llm
        model:
          completion_params: { temperature: 0.4 }
          mode: chat
          name: Qwen3-30B-A3B-Instruct
          provider: langgenius/vllm/vllm
        prompt_template:
        - role: system
          text: |
            你是人才测评专家，精通客户画像构建与麦克利兰冰山能力模型。

            ## 输入
            核心目标：{{#start.goal#}}
            训练人群：{{#start.audiences#}}
场景列表（含字段）：{{#code_scenes.scenes_json#}}
            材料摘要：{{#start.material_summary#}}

            ## 任务A：客户画像（2~3 个）
            从场景冲突中提炼典型的对话对象画像（学员在演练中面对的人），每个：
            - id："cp-01"…；type：画像名（如"价格敏感型采购经理"，7字内）
            - description：身份处境一句话
            - personalities：性格标签 3 个；decisionFactors：决策关注点 3 条
            - communicationStyle：沟通风格（语速/表达习惯/施压方式）
            - painPoints：常见痛点 3 条
            画像必须与场景的核心冲突一一呼应（每个高冲突场景至少有一个画像能对上）。

            ## 任务B：冰山模型（主题级，合并所有场景所需能力）
            - visible.knowledge：知识点 6~10 条，格式"名称: 一句话掌握标准"
            - visible.skills：技能 6~10 条，同上格式
            - hidden.roles / selfConcept / personalities / motives：各 4~8 条短语
            内容必须从场景的行为目标与材料知识推导，不得虚构无关能力。

            ## 输出（仅输出 JSON）
            {"profiles":[{"id":"cp-01","type":"…","description":"…","personalities":["…"],"decisionFactors":["…"],"communicationStyle":"…","painPoints":["…"]}],"iceberg":{"visible":{"knowledge":["…"],"skills":["…"]},"hidden":{"roles":["…"],"selfConcept":["…"],"personalities":["…"],"motives":["…"]}}}
        - role: user
          text: 请生成画像与冰山模型。
      id: llm_profiles
      position: {x: 940, y: 300}
      type: custom

    - data:
        title: 解析画像冰山JSON
        type: code
        code_language: python3
        code: |
          import json, re
          def main(arg0: str) -> dict:
              t = arg0.strip()
              m = re.search(r'\{.*\}', t, re.S)
              if m: t = m.group(0)
              j = json.loads(t)
              return {"profiles_json": json.dumps(j["profiles"], ensure_ascii=False), "iceberg_json": json.dumps(j["iceberg"], ensure_ascii=False)}
        variables: [{ variable: arg0, value_selector: [llm_profiles, text] }]
        outputs: { profiles_json: {type: string}, iceberg_json: {type: string} }
      id: code_profiles
      position: {x: 1240, y: 300}
      type: custom

    - data:
        title: ③生成评估维度与权重
        type: llm
        model:
          completion_params: { temperature: 0.3 }
          mode: chat
          name: Qwen3-30B-A3B-Instruct
          provider: langgenius/vllm/vllm
        prompt_template:
        - role: system
          text: |
            你是培训评估体系设计专家。基于场景与画像，设计训练主题的评估标准。

            ## 输入
            核心目标：{{#start.goal#}}
            场景列表（含字段）：{{#code_scenes.scenes_json#}}
            客户画像：{{#code_profiles.profiles_json#}}

            ## 要求
            1. 全局评估维度 3~5 个（跨场景通用能力，如"流程规范与合规性/沟通技巧/情绪控制/问题解决"），每个：
               - id："dim-01"…；name：6字内；description：考察点一句话
               - criteria：三档评分标准，严格格式：
                 "优秀(90-100分)：…；良好(70-89分)：…；需改进(<70分)：…"（各档一句具体行为描述，可判可区分）
            2. defaultDimensionWeights：默认权重组合，合计=100
            3. 每个场景的 dimensionWeights：从全局维度中选 2~4 个最相关的，**每场景权重合计=100**
            4. passScore：通过分数线 70
            5. 维度设计必须能从对话表现判定（不考书面知识），与场景 forbidBehaviors/businessGoal 呼应。

            ## 输出（仅输出 JSON）
            {"passScore":70,"dimensions":[{"id":"dim-01","name":"…","description":"…","criteria":"…"}],"defaultDimensionWeights":[{"dimensionId":"dim-01","weight":30}],"sceneWeights":[{"sceneId":"sc-01","weights":[{"dimensionId":"dim-01","weight":40}]}]}
        - role: user
          text: 请生成评估标准。
      id: llm_criteria
      position: {x: 1540, y: 300}
      type: custom

    - data:
        title: 聚合校验输出
        type: code
        code_language: python3
        code: |
          import json, re
          def main(scenes_s: str, profiles_s: str, iceberg_s: str, criteria_s: str, materials_s: str) -> dict:
              def pick(t):
                  m = re.search(r'\{.*\}', t.strip(), re.S)
                  return json.loads(m.group(0) if m else t)
              scenes = pick(scenes_s); crit = pick(criteria_s)
              profiles = pick(profiles_s); iceberg = pick(iceberg_s)
              # 组装 scenarios
              sw = {x["sceneId"]: x["weights"] for x in crit["sceneWeights"]}
              dim_ids = [d["id"] for d in crit["dimensions"]]
              scenarios = []
              for s in scenes:
                  w = sw.get(s["id"], crit["defaultDimensionWeights"])
                  assert abs(sum(x["weight"] for x in w) - 100) < 0.01, f"scene {s['id']} weights != 100"
                  for x in w: assert x["dimensionId"] in dim_ids, f"bad dim ref {x['dimensionId']}"
                  scenarios.append({
                      "id": s["id"], "name": s["name"], "audiences": s["audiences"],
                      "businessGoal": s["businessGoal"], "behaviorGoals": s["behaviorGoals"],
                      "relatedIcebergElements": {},  # Java 侧从冰山全文匹配回填
                      "businessImpact": s["businessImpact"], "failureCost": s["failureCost"],
                      "coreConflict": s["coreConflict"], "failureReasons": s["failureReasons"],
                      "difficulties": s["difficulties"],
                      "constraints": {"forbidBehaviors": s["forbidBehaviors"], "maxTime": s["maxTime"]},
                      "relatedKnowledgeIds": [], "relatedScriptIds": [], "relatedProductProfileArtifactIds": [],
                      "caseArtifactIds": [], "cases": [],
                      "dimensionWeights": w })
              materials = json.loads(materials_s) if materials_s else []
              artifact = {
                  "materials": materials, "scenarios": scenarios,
                  "customerProfiles": profiles, "icebergModel": iceberg,
                  "evaluationCriteria": {"passScore": crit["passScore"], "dimensions": crit["dimensions"],
                                          "defaultDimensionWeights": crit["defaultDimensionWeights"]},
                  "professionalKnowledge": None, "productProfiles": [], "version": "v1" }
              return {"artifact_json": json.dumps(artifact, ensure_ascii=False)}
        variables:
        - { variable: scenes_s, value_selector: [code_scenes, scenes_json] }
        - { variable: profiles_s, value_selector: [code_profiles, profiles_json] }
        - { variable: iceberg_s, value_selector: [code_profiles, iceberg_json] }
        - { variable: criteria_s, value_selector: [llm_criteria, text] }
        - { variable: materials_s, value_selector: [start, material_summary] }
        outputs: { artifact_json: {type: string} }
      id: code_merge
      position: {x: 1840, y: 300}
      type: custom

    - data:
        title: 结束
        type: end
        outputs:
        - { variable: artifact_json, value_selector: [code_merge, artifact_json] }
      id: end
      position: {x: 2140, y: 300}
      type: custom
```

---

## Java 侧对接要点

1. `POST /v1/workflows/run`：`{inputs:{goal, audiences:"[\"订单运营专员\"]", material_summary, keep_existing:"true|false", existing_scenes:"[\"场景A\",\"场景B\"]"}, response_mode:"blocking"}`；Java 超时设 300s。
2. 响应取 `data.outputs.artifact_json`（字符串再 parse）。
3. **Java 二次校验**（不可省，Dify 内校验可能被绕过）：ArtifactSchemaValidator 按接口文档 §3.5 规则校验；`relatedIcebergElements` 由 Java 回填——用场景 businessGoal/behaviorGoals 与冰山 knowledge/skills 做关键词匹配（简单包含匹配即可，匹配不上的留空数组，不阻塞）。
4. 失败重试：校验失败把错误信息拼进 `material_summary` 尾部（`【上次输出校验失败：{errors}，请修正】`）重跑 1 次。
5. materials 从当前工作区 artifact 原样带入（工作流不管理材料，只透传）。
