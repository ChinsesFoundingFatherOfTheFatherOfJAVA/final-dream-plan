# 主题生成工作流（theme-gen）· 空画像问题诊断与修改建议

> 版本：v1.0 ｜ 日期：2026-09-18
> 对象：`主题生成-theme-gen.yml`（用户提供的最新 DSL：模型 `Qwen/Qwen3-VL-4B-Instruct`、三个 LLM 节点均启用 `structured_output`）
> 结论：**空画像由 DSL 设计导致（不是 Java 管道），且可复现；修复点有 4 处，其中"②段输入源"是根因。**

---

## 1. 现象与复现

打样时产物里 `customerProfiles=[]`、`icebergModel` 六层全空，但①段场景与③段维度都正常。

用 `scripts/dify-workflow-probe.mjs` 直连工作流做了**单变量对照实验**（仅改 `material_summary`，其余输入完全相同）：

| 实验 | 入参 | ①段（场景） | ②段（画像+冰山） | 最终产物 |
|------|------|------------|------------------|----------|
| **A** | 无材料摘要 | text 5051 / SO 3393 | **text 219 / SO 137 → profiles=[] 冰山全空** | 场景 6、画像 **0**、维度 5 |
| **B** | 有材料摘要（136 字） | 正常 | text 2233 / SO 1362 → **profiles=2，冰山 10/10/4/4/4/4** | 场景 6、画像 2、维度 5 |
| **C** | 无材料，但入参带"上次校验失败：画像为空…请修正" | 正常 | text 2461 / SO 1488 → **profiles=3，冰山 6/6/4/4/4/4** | 场景 6、画像 3、维度 5 |

- A 可稳定复现（两次跑都是 219/137，确定性行为，不是偶发抖动）；
- B 说明**只要②段拿得到素材就正常**（你那次成功的 Dify 测试，输出里 `materials[0].summary` 是有内容的，正好落在 B 的情况）；
- C 说明**给一句"要修正"的提示就能救回来**——这决定了 Java 侧校验策略（见 §4）。
- ①③段在 A/B/C 下都正常，**只有②段受影响**。

## 2. 根因：②段是全流程唯一"素材来源单一 + 被授权留空"的节点

三点叠加：

**① 素材来源单一。** ②段的输入只有 `{{#code_scenes.scene_names#}}`（**只有场景名，没有场景字段**）与 `material_summary`。
没有材料时，模型手里只有几个场景名，却要完成"画像必须与场景核心冲突一一呼应"——素材天然不足。
对比：①段有 goal+audiences 打底；③段吃的是完整 `scenes_json`（含 coreConflict/behaviorGoals 等），素材充足。所以只有②段会崩。

**② prompt 明确授权"留空"。** ②段提示词里有两条：
- 任务A 规则3：「若**场景名信息不足**，可基于材料摘要合理推断」——没材料时这条路走不通；
- 任务B 规则3：「若**材料不足以支撑**某条能力，**宁可不写，也不要编造**」——直接授权不写。

小模型（4B）在"素材不足 + 被明确允许不写"的组合下，选择了整体留空。

**③ schema 允许空数组，所以"留空"是完全合法的解。**
②段的结构化输出 schema 里，`profiles`、`iceberg.visible.knowledge/skills`、`iceberg.hidden.*` **全部没有 `minItems`**。
模型输出 `{"profiles": [], "iceberg": {…全空…}}` 既满足 schema（节点 status=succeeded），
也符合提示词（"宁可不写"）——**没有任何机制要求它必须有内容**。

## 3. DSL 侧建议修改（按优先级）

### 3.1 【根因修复】②段的场景输入改用完整场景字段

把 `code_profiles` 之前那个 LLM 节点的输入从"场景名"换成"完整场景 JSON"：

```
- 场景列表：{{#code_scenes.scene_names#}}          # 改前（只有名字）
+ 场景列表（含字段）：{{#code_scenes.scenes_json#}}  # 改后（与③段一致）
```

这样即使完全没有材料，模型也能从每个场景的 `coreConflict` / `behaviorGoals` / `businessImpact` 推导画像与能力，
不再依赖材料摘要这一个来源。**这是最根本的一处修改。**

### 3.2 【把"可以留空"改成"必须产出"】调整 prompt 措辞

把"禁止编造"限定到**具体要素**（数字、公司名、人名），而不是允许整体留空：

```
- 3. 若材料不足以支撑某条能力，宁可不写，也不要编造。          # 改前（授权留空）
+ 3. 画像与冰山各层必须给出内容：素材不足时，从场景的 coreConflict、behaviorGoals 与训练目标
+    合理推断；仅禁止编造具体公司名、人名与金额数字，不允许留空数组。
```

同时把 任务B 各层的条数要求（knowledge/skills 6~10、hidden 四层 4~8）在输出前自检里再强调一遍。

### 3.3 【把口头要求变成硬约束】给 schema 加 `minItems`

在②段的 `structured_output.schema` 里加下限，模型就无法用空数组"交差"：

```json
{
  "profiles": { "type": "array", "minItems": 2, "maxItems": 3, "items": { "...": "..." } },
  "iceberg": {
    "type": "object",
    "properties": {
      "visible": {
        "type": "object",
        "properties": {
          "knowledge": { "type": "array", "minItems": 6, "items": { "type": "string" } },
          "skills":    { "type": "array", "minItems": 6, "items": { "type": "string" } }
        },
        "required": ["knowledge", "skills"]
      },
      "hidden": {
        "type": "object",
        "properties": {
          "roles":         { "type": "array", "minItems": 4, "items": { "type": "string" } },
          "selfConcept":   { "type": "array", "minItems": 4, "items": { "type": "string" } },
          "personalities": { "type": "array", "minItems": 4, "items": { "type": "string" } },
          "motives":       { "type": "array", "minItems": 4, "items": { "type": "string" } }
        },
        "required": ["roles", "selfConcept", "personalities", "motives"]
      }
    },
    "required": ["visible", "hidden"]
  }
}
```

> 注意 `minItems` 会让"真写不出来"的情况变成节点失败（而不是静默空数组），这正是我们要的：宁可失败重试，不要产出空画像。

### 3.4 【消除 prompt 与 schema 的矛盾】`additionalProperties: false` 会静默丢字段

当前 prompt 要求、但 schema 里**没有**这些属性，而 schema 又设了 `additionalProperties: false`，
所以这些字段即使模型写了也会被约束掉（**静默丢弃**）：

| 节点 | prompt 要求输出 | schema 是否有 | 后果 |
|------|----------------|---------------|------|
| ①段场景 | `dimensionIds: []` | 无 | 被丢（`code_merge` 不读它，无实际影响） |
| ②段画像 | `relatedSceneIds` | 无 | 被丢（画像与场景的关联信息丢失） |
| ③段维度 | `relatedSceneIds`、`alignedForbidBehaviors` | 无 | 被丢 |

另外你那次成功的输出里，画像的 `relatedSceneIds` 和维度的 `alignedForbidBehaviors` **是存在的**——
说明那一次的 schema 与当前文件里的不一致（或 provider 未严格执行 `additionalProperties`）。
**建议：prompt 与 schema 统一**——要么把这些字段补进 schema（如果要用），要么从 prompt 删掉（如果不用）。
两者矛盾时，小模型更容易退化成"少写为妙"。

> 对 Java 与前端无影响的字段（`03-接口文档.md §3.5` 的 artifact schema 里没有 `relatedSceneIds`/`alignedForbidBehaviors`），
> 若要保留，建议由 Java 侧在合并时忽略即可（当前实现就是按 8 个顶级字段白名单取值，多余字段自然不进 artifact）。

### 3.5 其他两处小问题

1. **`start` 节点有 YAML 损伤**（你发的文件第 168–173 行）：

   ```yaml
   - label: 现有场景名列表(JSON数组
     max_length: 3000
     required: false
     type: paragraph
     variable: existing_scenes
     更新模式): null            # ← 这一行是手工改坏后残留的
   ```

   label 被截断、并多出一个 `更新模式): null` 杂键。只影响界面显示名，不影响运行，但建议清掉。

2. **模型选型**：`Qwen/Qwen3-VL-4B-Instruct` 是 4B 的**视觉语言**模型，用于纯文本结构化生成时指令遵循偏弱
   （②段在素材不足时选择整体留空，而不是尽力推断）。可考虑换更大的纯文本模型；
   或把②段拆成"画像 / 冰山"两个 LLM 节点（单次输出负担减半，稳定性更好）。

## 4. Java 侧：已开启"画像与冰山非空"校验（2026-09-18 落地）

**已实现**（`ArtifactSchemaValidator`，规则已同步进 03 §3.5）：`customerProfiles` 2~4 个且必填字段非空；
`icebergModel` 六层非空（visible.knowledge/skills ≥6、hidden 四层 ≥4，与 DSL prompt 条数对齐）。
效果：**空画像不再被静默放行**——会被判失败、推 `failed` 事件，并顺带获得一次带错误提示的重试机会。

> ⚠️ **更正**：本文档初版写"重试通常即可修复"，**该结论不成立**。
> 用与失败重试**完全相同的入参**复跑探针，②段依旧返回空画像（219 字符 / profiles=[]）。
> 即：重试只是"多给一次机会"，**根治必须做 §3.1–§3.3 的 DSL 修改**（②段改吃完整场景 JSON、
> prompt 不再允许留空、schema 加 minItems）。Java 校验负责"显式失败"，不负责"修好质量"。

## 5. 与 Java 实现的兼容性确认

你这份新 DSL 与 Java 侧**完全兼容**，无需改代码：

- Java 只依赖**代码节点**的输出变量名：`scenes_json` / `scene_names` / `profiles_json` / `iceberg_json` / `artifact_json`
  ——新 DSL 里这些名字都没变；
- 三个 LLM 节点改用 `structured_output` 作为代码节点输入，对 Java 不可见，不影响；
- 渐次出现（`in_progress` 按段落推送）依赖代码节点的 `scenes_json` / `profiles_json`，
  实验 A/B/C 中这些节点都正常触发 → 渐进推送仍然有效（新 DSL 下实测 in_progress 3 段 + completed 1 段）；
- `artifact_json` 的 8 个顶级字段与 §3.5 一致（实验里 `scenarios/customerProfiles/evaluationCriteria/icebergModel/…` 齐全）。