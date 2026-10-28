# 15 语气维度 Phase 2 任务书（tone 指标入链路，交 code agent）

> 依据：PoC 终判 GO（2026-09-24，三指标全过，数据见 `学员端话术训练模块/14-语气PoC执行包.md` 执行记录节与 poc/summary_final.txt）。
> 范围：08 §2.3 设计的落地实施——`tone` 指标入 metric 白名单 + `ToneScoringService`（调百炼 qwen3.8-omni-flash）+ 管理端配置 UI + 单测。
> **配套阅读**：10-工程实施提示词 §0（工程铁律与验证闸口，不重复）；03-接口文档 §5.4b（metricKey/metricAspect 契约已写）。
> 工作量预估：约 2 人天。

---

## 0. PoC 已定死的设计参数（照抄，勿改）

| 参数 | 值 | 来源 |
|------|-----|------|
| 模型 | `qwen3.8-omni-flash`（百炼 OpenAI 兼容接口） | PoC 四模型探针：跨模型分差大（25/35/25/65），固定单一模型 |
| 端点 | `https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions` | PoC 实测 |
| temperature | 0.1 | PoC 同款 |
| 评次数 | **每条录音评 3 次取中位数**（奇数取中） | PoC：单次差 12.4，取中漂移 4.8 |
| 提示词 | **v2 版全文见 §3**（可数判据锚点 + 庄重不扣分纪律 + evidence 输出） | PoC v2，一字不改的原则：改动需走提示词变更流程并复测 |
| 失败纪律 | 任何失败 → 该维度不参与评分（score=null + 原因文案），**绝不编造分数** | 09 #11 纪律延续 |

## 1. 后端

### 1.1 DimensionMetricConfig 扩展
- 常量 `METRIC_TONE = "tone"`；`SUPPORTED_METRICS` 加入。
- `params` 白名单扩 `aspect`（**注意：aspect 是 String，现有 params 是 `Map<String, Integer>`——在 `DimensionMetricConfig` 内为 tone 单独处理 aspect 参数**：`toJson(String metricKey, Map<String,Integer> params, String aspect)` 重载或等价方案，落库形态 `{"metric":"tone","params":{"aspect":"热情"}}`；`parse` 侧返回 tone 的 aspect，缺省"热情"）。
- `ProjectSaveReq.ScoringDimensionReq` 增 `metricAspect`（String，2~6 字校验，仅 tone 有效其余忽略）——03 §5.4b 已按此写，照做。
- **XML/JSON 列纪律**：`metric_config` 仍是 VARCHAR(500)，注意 aspect 中文按 UTF-8 入 JSON。

### 1.2 新增 service/ToneScoringService
```java
/**
 * 语气维度评分（FP-30 Phase 2，PoC 已验证）。
 * 对进入评分的语音轮（通过且未撤回，与 roundSpeeds 同口径）逐条调
 * 百炼 qwen3.8-omni-flash，按 params.aspect 单角度评分，评 3 次取中位数，
 * 再按各轮识别字数加权平均得维度分。
 * 任何一轮调用失败/超时 → 整维度返回 null（不参与评分），绝不编造。
 */
public MetricOutcome measureTone(DimensionMetricConfig metric, List<ToneRoundInput> rounds)
```
- `ToneRoundInput`：{ audioFile(Path，/audio/asr/{messageId}.wav), text(转写文本), charCount(去标点，复用 SpeechSpeedCalculator#countChars) }。
- **音频输入**：`input_audio` data URI，MIME 按文件（训练页录音恒为 wav）；文件不存在（被清理）→ 该轮跳过并 WARN，全部缺失 → null。
- **HTTP**：新增专用 RestTemplate bean（**不要复用共享 120s 那个**）：connect 5s / read **60s**（单次 omni 调用 PoC 实测 <30s，60s 富余）；3 次调用串行（同录音 3 次），单轮预算 ~3 分钟内。
- **并发**：多轮之间用 `speech.tone.concurrency`（默认 3）限流的线程池并发；报告生成本身异步，预算内完成。
- **中位数**：3 次 score 排序取中；3 次中任何一次解析失败 → 用剩余的取中（≥2 次有效即可），仅 1 次有效 → 用该次并 WARN，0 次 → 该维度 null。
- **加权**：维度分 = Σ(各轮中位分 × 该轮字数) / Σ字数，四舍五入整数。

### 1.3 接线（ReportGenerationService）
- `measure()` switch 加 `case METRIC_TONE -> toneScoringService.measureTone(metric, toneRounds)`。
- `toneRounds` 在 `planDimensions` 前组装：口径与 `roundSpeeds` 完全一致（通过且未撤回的 input_mode=2 轮），字段带上 messageId→audioFile 映射（查 `training_session_message.audio_url` 转 Path，注意 FileStorage 的本地目录前缀配置）。
- **evidence_type=2 + tone**：无语音轮时照既有 `NO_ACOUSTIC_REASON` 口径不参与（零新逻辑）。
- **rule 标注**：tone 走既有"后端已判定"管道（`toDimensionsJson` 追加 + measured 覆盖，机制零改动）；评语文案走后端模板（同违禁词模式），建议模板：「本轮从{aspect}角度的语音表现评分为 N 分，主要依据：{首轮evidence摘要}」。

### 1.4 配置（application.properties，纯 ASCII）
```properties
# Tone scoring via Bailian qwen3.8-omni-flash (PoC validated 2026-09-24)
speech.tone.enabled=true
speech.tone.base-url=https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions
speech.tone.model=qwen3.8-omni-flash
speech.tone.api-key=${dashscope.api-key}
speech.tone.read-timeout-ms=60000
speech.tone.concurrency=3
```
- `speech.tone.enabled=false` 时 tone 维度按"未参与评分"处理（与降级同路径）。

## 2. 前端（EditProject.vue 评分维度区块）

1. "定分方式"下拉新增 **「音频模型评语气」**（value 对应 metricKey=tone）。
2. 选中时旁侧显示 **「评什么角度」输入框**（v-model metricAspect，placeholder "热情"，maxlength 6，2 字起校验）。评分依据不提供下拉，切到语气时直接显示并提交「看语音」。
3. 提交：`metricKey:"tone", metricAspect:"热情"`；回显：从 `metric_config.params.aspect` 反解进输入框。
4. 12 号文档的 params 输入框互斥逻辑扩展：tone 时显示 aspect 输入框而非 bestMin/bestMax。

## 3. v2 提示词全文（ToneScoringService 内嵌常量，PoC 定稿）

```
你是话术训练的语音表现评审。听这段学员录音（ASR 转写文本：{text}），
只从"{aspect}"这一个角度给 0-100 整数分。
评分锚点（按可听特征计分，逐条对照）：
- 80-100：{aspect}特征密集出现——3 处及以上明确的语调上扬/重音强调/能量抬升段落，且贯穿全程，听感有感染力
- 60-79：{aspect}特征存在但稀疏——1~2 处明确特征，其余段落平稳，整体合格不突出
- 40-59：{aspect}特征基本缺失——全程单一节奏/单一音量，仅个别词有轻微变化，但表达仍完整清晰
- 0-39：与{aspect}相悖——特征完全不存在且呈现相反气质（如冷漠、迟疑、破碎）
判定纪律：
1. 只统计听到的声学证据（语调起伏、重音、音量变化、语速变化、停顿控制），逐条对照上面锚点后给分；
2. 庄重、沉稳、从容的风格不等于差——若其停顿控制有力、吐字笃定，按其与"{aspect}"的契合度计分，不因风格严肃而扣分；
3. 转写文本仅作内容参考，不作为评分依据；录音中的掌声、噪声等非人声忽略；
4. 打分克制：没有充分证据不要给两端极值。
只输出 JSON：{"score": N, "evidence": "列出你统计到的特征条数与位置（如：第2句重音、结尾上扬共2处），一句话"}
```

## 4. 单测（新增）

| 测试 | 断言 |
|------|------|
| ToneScoringService 三次取中 | mock 3 次返回 30/50/70 → 中位 50 |
| 次数容错 | 3 次中 1 次失败 → 取剩余中位；仅 1 次成功 → 用该次+WARN；0 次 → null |
| 字数加权 | 轮1（10字,60分）+轮2（30字,80分）→ 75 分 |
| 文件缺失轮跳过 | audio 文件不存在的轮 WARN 跳过，其余照算 |
| 失败降级 | base-url 不可达 → 维度 null，报告仍生成（既有降级路径回归） |
| metric_config 编解码 | tone+aspect 往返（toJson→parse）；坏 JSON 回落 AI 评分 |
| enabled=false | tone 维度不参与，日志可见 |

## 5. 验收标准

1. Given 管理员建维度"语气热情"（定分=音频模型评语气，角度=热情，依据=看语音，权重 10）When 语音项目报告生成 Then 该维度有后端定分（rule 带已判定标注）、评语为模板文案、总分计入；
2. Given 同项目学员全程文字作答 When 报告生成 Then 语气维度 score=null + 未参与原因，且该维度不进入总分分子和分母（E-06 口径）；
3. Given 百炼不可达 When 报告生成 Then 报告正常、语气维度 null + 原因（**不许出现编造分数**）；
4. Given 管理端编辑回显 When 重开编辑页 Then 角度输入框回显正确；
5. 回归闸口：后端 `mvn -o test` 全绿（62 基线+新增）；前端 `npx vue-tsc --noEmit`/`npm test`/`npx vite build` 三绿。

## 6. 明确不做

- 不做多角度合并评分（一个维度一个 aspect，要多角度建多个维度——语义更清晰）；
- 不做语气分数的历史重算/批量回填；
- 不改 04 Dify 智能体（tone 走"后端已判定"标注，提示词零改动——这正是当初"认标注不认名"设计的红利）；
- 不做评语里的逐轮 evidence 全量展示（只取首轮摘要进模板文案）。
