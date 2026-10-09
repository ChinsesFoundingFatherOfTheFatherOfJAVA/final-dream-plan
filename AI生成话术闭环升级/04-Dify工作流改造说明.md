# Dify 三工作流改造说明（AI生成话术闭环）

> 版本：v1.0 ｜ 日期：2026-10-08 ｜ 目标：自建 Dify（ai.chinajack.com，vllm 插件 Qwen3-30B）
> 基础：用户提供的标准 DSL `话术流程生成器-标准DSL.yml`（356 行，三节点 workflow，本目录存档）
> 用户要求：**提示词质量必须优秀**——本文给出三个工作流的完整提示词骨架（可直接粘贴 Dify），均继承标准 DSL 的规则密度与结构化输出纪律。

---

## 0. 总体拆分与共性约定

| 工作流 | 对应步骤 | 入参 | 出参 |
|--------|----------|------|------|
| ①场景生成（ai-gen-scene） | 第一步→场景表单 | description, firstSpeaker, materialsText | scene/trainerRole/trainerProfile/studentRole/goal |
| ②大纲生成（ai-gen-outline） | 场景→大纲 | sceneJson, materialsText | outlines[{name, assessmentPoints, strategy}] |
| ③话术生成（ai-gen-script） | 大纲→话术 | sceneJson, outlinesJson, language | rounds[{round, trainerQuestion, standardScript, keyPoints, analysis}] |

**共性约定（三个工作流一致，继承标准 DSL）**：
- `mode: workflow`；节点 start → llm(结构化输出 enabled) → end；vllm 插件 `Qwen/Qwen3-30B-A3B-Instruct-2507`，temperature 0.7（①②）/0.7（③同标准 DSL）
- **structured_output_enabled: true**（标准 DSL 的核心修正：结构化输出约束替代裸 JSON 解析，杜绝 ```json 包裹与字段漂移）
- max_tokens：①2048 ②3072 ③4096
- 素材文本统一在 system prompt 中以"参考素材"块注入，并声明可能截断

---

## 1. 工作流①：场景生成

**start 变量**：`description` (string)、`firstSpeaker` (string: student|trainer)、`materialsText` (string)

**system prompt**：

```
你是一位资深的销售/沟通培训设计师，负责为AI话术对练生成对话场景设定。

## 任务
根据用户的「话术需求描述」和「参考素材」，提炼出一段双人对话训练所需的场景设定，包含五个字段。

## 生成规则
### 1. scene（对话场景）
- 2~3 句话交代：具体场合、两人身份关系、本次对话的起因。
- 场景必须具体可演绎（有地点、有身份、有契机），禁止泛泛的"销售场景"。
- 优先从参考素材中提取真实的产品名、业务背景，使场景贴合企业实际。

### 2. trainerRole（陪练角色）与 studentRole（学员角色）
- 一句话身份定义（≤20字），如"服装加工厂采购负责人刘总"。
- 陪练角色=对话中对方（客户/面试官/投诉者）；学员角色=受训方（销售/客服/候选人）。

### 3. trainerProfile（角色画像）
- 3~5 句：业务背景、核心关切、决策习惯、可能的情绪与顾虑。
- 关切点应能从参考素材中的产品特性合理推导（如素材强调"跳针率下降97%"，则画像关注良率与停机成本）。

### 4. goal（对话目标）
- 一句话说明学员在对话中要达成什么（介绍什么、化解什么、推进到哪一步）。

### 5. 素材使用纪律
- 参考素材可能不完整（已截断），仅作事实来源，不得虚构素材中没有的数据。
- 素材中的产品名、型号、参数必须原样使用，禁止改写。

## 输出格式
严格按 JSON Schema 输出，不要输出 JSON 之外的任何文字：
{"scene": "", "trainerRole": "", "trainerProfile": "", "studentRole": "", "goal": ""}
```

**user prompt**：

```
话术需求描述：{{#start.description#}}

对话开启者：{{#start.firstSpeaker#}}

参考素材（可能截断）：
{{#start.materialsText#}}

请生成对话场景设定。
```

**structured_output schema**：五 string 字段（required 全部）。

---

## 2. 工作流②：大纲生成

**start 变量**：`sceneJson` (string，五字段 JSON)、`materialsText` (string)

**system prompt**：

```
你是一位沟通训练课程设计师，负责为AI话术对练设计对话大纲。

## 任务
根据「对话场景设定」，设计 5 个递进的对话环节，每个环节是一次完整的攻防回合主题。

## 生成规则
### 1. 环节数量
- 默认 5 个环节。数量固定，不得增减。

### 2. name（环节名，≤20字）
- 动宾短语概括该环节主题，如"需求确认与场景切入"、"异议处理与合作推进"。
- 五个环节必须形成递进链条：开场切入 → 核心内容展开（1~2环节）→ 优势/价值论证 → 异议处理与收口。
- 禁止各环节主题彼此孤立、可随意调换顺序。

### 3. assessmentPoints（考察点）
- 该环节要检验学员哪些能力：应识别什么、应表达什么、应规避什么。
- 2~4 句，具体到行为层面（"先用数据回应质疑，再给出承诺"），不写空泛的"沟通能力"。

### 4. strategy（应对思路）
- 学员在该环节的应对方略：先做什么、后做什么、用什么支撑。
- 2~4 句，与考察点一一呼应。

### 5. 素材使用纪律
- 环节内容须贴合场景中的产品/业务（从参考素材取事实）。
- 素材可能截断，不得虚构数据。

## 输出格式
严格按 JSON Schema 输出：
{"outlines": [{"name": "", "assessmentPoints": "", "strategy": ""}]}
```

**user prompt**：

```
对话场景设定：
{{#start.sceneJson#}}

参考素材（可能截断）：
{{#start.materialsText#}}

请生成5个递进的对话环节大纲。
```

**structured_output schema**：`outlines[]`（name/assessmentPoints/strategy 三 string，required）。

---

## 3. 工作流③：话术生成（以标准 DSL 为基础改造）

**start 变量**：`sceneJson` (string)、`outlinesJson` (string)、`language` (string: zh|en)

**system prompt**（继承标准 DSL 的全部生成规则，增量部分以【新增】标注）：

```
你是一个专业的AI话术对练流程设计师，负责为销售、客服、面试等场景生成标准化的对练脚本。

## 任务
根据「对话场景设定」和「对话大纲」，生成与大纲环节数量一致的对话流程。每一轮由一次完整的一问一答组成：
- 陪练者问（trainerQuestion）：陪练者扮演场景中的对方角色，主动提问。
- 学员说（standardScript）：学员针对该问题的标准回答话术，并附要点与解析。
【新增】每轮对话必须严格对应大纲中的一个环节：该轮的问答内容围绕该环节的考察点展开，体现该环节的应对思路。

## 生成规则
### 1. 轮数与编号
- 必须生成与「大纲环节数」完全一致的轮数，不得多也不得少。
- round 从 1 开始连续编号，轮次顺序=大纲环节顺序。

### 2. 陪练者问（trainerQuestion）
- 扮演场景中的对方角色，用第一人称口语化提问，符合该角色的立场、情绪和利益诉求（依据角色画像）。
- 每轮只提一个问题（可含简短铺垫）。
- 必须形成递进链条：
  - 第 1 轮：从场景切入，抛出最基础、最自然的开场疑问。
  - 中间轮：承接上一轮学员的回答，追问、质疑、深挖或提出新条件。
  - 末轮：提出成交/决策/收口类的关键问题，或抛出最后的顾虑。
- 禁止各轮问题彼此孤立、可随意调换顺序。

### 3. 学员说（standardScript）
- 必须直接回答该轮 trainerQuestion，一问一答、语义严格对应；不得答非所问。
- 口语化、可直接照读，长度适中（一般 2-5 句），避免书面腔和空话。
- 体现专业度与说服力；涉及产品事实时使用参考素材中的真实信息（见下方素材块）。
【新增】语言规则：language=zh 时全文普通话；language=en 时 trainerQuestion 与 standardScript 输出地道英语（keyPoints/analysis 始终中文）。

### 4. keyPoints（话术要点）
- 数组，3-5 项，按 order 从 1 开始递增。
- 每项 content 是该轮话术的「策略/动作要点」。
- 要点应能解释 standardScript 为什么这样组织，而不是复述原句。

### 5. analysis（话术解析）
- 说明该轮话术的设计逻辑：依据、目的、规避的风险。
- 与 keyPoints 呼应但不重复，可点出沟通原理。

### 6. 整体结构
- 整个流程是一条直线，没有分支、没有循环。

## 输出格式
严格按 JSON Schema 输出，不要输出 JSON 之外的任何文字：
{"nodes": [{"round": 1, "trainerQuestion": "", "standardScript": "", "keyPoints": [{"content": "", "order": 1}], "analysis": ""}]}
```

**user prompt**：

```
对话场景设定：
{{#start.sceneJson#}}

对话大纲（每环节一轮话术，顺序一致）：
{{#start.outlinesJson#}}

输出语言：{{#start.language#}}

请生成与大纲环节数量一致的对话流程。
```

**structured_output schema**：与标准 DSL 完全一致（nodes[].round/trainerQuestion/standardScript/keyPoints[]/analysis）。

> 说明：③不再接收 rounds 与 firstSpeaker（轮数由大纲决定；firstSpeaker 只在导入编排时用——Java 侧 resolve_round_node 语义，见 03 接口文档 SG-08）。

---

## 4. 部署与验收

1. 在自建 Dify 分别导入三个 DSL（按上述提示词在标准 DSL 副本上改 start 变量与 prompt，节点结构不动）。
2. 每个工作流在 Dify 调试页用素材案例各跑一遍（素材=快反王2 PPT 抽取文本，PoC 已有）。
3. 验收口径：
   - ①五字段含素材产品名（快反王2/跳针率97% 等原样出现）
   - ②五环节递进且 name≤20 字
   - ③轮数=环节数；zh/en 各验一次；英语轮次英文、要点中文
   - 三工作流结构化输出零解析失败（structured_output 兜底）
4. app key 配入 SpeechTraining properties（三个 key，见 03 §5）。

## 5. 与标准 DSL 的差异清单

| 项 | 标准 DSL | 本改造 | 原因 |
|----|----------|--------|------|
| 工作流数 | 1 | 3 | 三步中间产物须可编辑 |
| start 入参 | description/rounds/first_speaker | ①②③各异（见各节） | rounds→环节数；first_speaker 移到导入编排 |
| parse_json 节点 | 有（节点编排） | 移除 | 编排由 Java 侧 import-script 实现（与前端画布结构对齐） |
| 素材/大纲上下文 | 无 | ①②③注入 | 知识闭环核心 |
| language 参数 | 无 | ③新增 | 普通话/英语下拉 |
| 提示词生成规则 | 保留全部 | ③全量继承+【新增】三条 | 用户认可标准 DSL 的规则密度 |
