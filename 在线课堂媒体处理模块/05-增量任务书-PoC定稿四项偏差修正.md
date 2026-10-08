# 在线课堂媒体处理模块 增量任务书 05：PoC 定稿四项偏差修正

> 版本：v1.0 ｜ 日期：2026-10-08 ｜ 性质：后端增量（**前端零改动、接口契约零变化**）
> 基线：已实现代码（提交 2ead6c2，2026-10-04 实施，见 04-实施记录与偏差）。
>
> **取代声明**：本文档取代 02-技术实现方案 §7 风险清单中"热词"条目的 `parameters.context` 机制表述
> （经官方 REST 文档与 SDK 2.20.6 `TranscriptionParam` 核实：录音文件识别 API **无 context 参数**，
> paraformer-v2 热词唯一入口为 `vocabulary_id`，见 FP-05-4）。02 其余条目维持定稿不变，
> 本任务书即"把 10-04 的实现对齐到 10-05/10-08 两轮 PoC 定稿方案"的差距清单。

---

## 0. 背景

实现批次（10-04）早于 PoC-1（10-05，流复制优化）与 PoC-2（10-08，翻译降级/multipart/热词定案）。
经逐文件核对，4 处偏差，其中 FP-05-1 为必现 P0：

| # | 功能点 | 定稿方案 | 实现现状 | 严重度 |
|---|--------|----------|----------|--------|
| FP-05-1 | OSS wav 上传 | multipart 8MB 分块 | `putObject` 单次 PUT | **P0 必现**：≥约10.5分钟视频的 16k wav 超 20MB，单次 PUT 被 10054 掐断，字幕管线必失败（PoC-2 实测 23.6MB 即挂） |
| FP-05-2 | HLS 转码 | 默认 `-c copy` 流复制 + fallback | 固定 `-c:v libx264 -c:a aac` 重编码 | P1：13 分钟视频 295s vs 10.8s，慢 27 倍 |
| FP-05-3 | qwen 翻译 | 25 条/批 + 失败自动降级逐条 | 50 条/批 + 重试 2 次后直接 failed | P1：50 条模型易合并条目；vi 批量 3 连败（PoC-2 实测）→ 整 job 失败 |
| FP-05-4 | ASR 热词 | 启用热词纠"商机→上机" | 未传任何热词参数 | P2：人工抽听确认的错误模式会复现 |

四项相互独立，可任一顺序实施；建议按严重度 FP-05-1 → 2 → 3 → 4。

---

## FP-05-1 OSS multipart 分块上传（P0）

**现状**：`OnlineClassroom/src/main/java/jack/digityhuman/onlineclassroom/service/OssTempService.java`
第 62 行 `client().putObject(bucket, objectKey, wav.toFile())` 单次 PUT。

**改为**：aliyun-sdk-oss 3.17.4（工程已有依赖，**不新增**）的 `UploadFileRequest` 分块上传：

```java
UploadFileRequest request = new UploadFileRequest(bucket, objectKey);
request.setUploadFile(wav.toFile().getAbsolutePath());
request.setPartSize(8 * 1024 * 1024);   // 8MB/块（PoC-2 实测稳定：30.3s 完成 23.6MB）
request.setTaskNum(3);                   // 3 并发分块
request.setEnableCheckpoint(true);       // 断点续传，管线内重试不从头传
client().uploadFile(request);            // 注意：throws Throwable，需捕获收敛为 BizException
```

- 预签名/删除逻辑不变（分块上传完成后对象与普通对象无异）。
- 异常处理：`uploadFile` 的受检异常统一收敛为既有 `BizException("字幕音频上传 OSS 失败，请检查 media.oss 配置")` 口径，保留原因链。

**验收（Given/When/Then）**：
- Given ≥12 分钟视频的 wav（>20MB）When 字幕管线 asr 阶段上传 Then 无 ConnectionReset，预签名 URL 可被百炼读取。
- Given 分块中某块网络抖动 When 上传 Then checkpoint 续传完成（不整轮重来）。

**单测**：mock OSS client，验证调用的是 `uploadFile` 且 `partSize=8MB`、`enableCheckpoint=true`（未再调 `putObject`）。

---

## FP-05-2 HLS 默认流复制 + fallback（P1）

**现状**：`TranscodeTask.java` 第 86-89 行固定 `-c:v libx264 -c:a aac`。

**改为三级策略（用户拍板：预判为主 + 失败兜底）**：

1. **ffprobe 预判**：视频流 codec=h264 且（无音轨 或 音频流 codec=aac）→ 走 `-c copy` 流复制。
2. 预判不通过（HEVC/VP9/非 AAC 音轨等）→ 直接走 libx264+aac 重编码（不试错，避免半途浪费）。
3. **兜底**：`-c copy` 路径 ffmpeg 非零退出（像素格式/profile 等边缘不兼容）→ 自动降级重编码**重跑一次**；重编码再失败才 markFailed。

**实现要点**：
- `MediaProbeService` 需扩展：新增 `probeCodecs(Path absoluteFile)` 方法，返回 `record VideoAudioCodecs(String videoCodec, String audioCodec)`（复用既有 ffprobe ProcessBuilder 执行与 JSON 解析骨架，从 streams 中同时取视频/音频流 codec_name）。**不改动** `MediaMeta` record 与 merge 响应的 mediaMeta 契约。
- `-c copy` 命令行：`-i 源 -c copy -hls_time 10 -hls_playlist_type vod index.m3u8`（hls_time 仅作分片参考，实际按关键帧切，PoC-1 已验证可播可拖）。
- 重编码命令维持现状参数不变（libx264/aac/hls_time 10/vod）。
- `.tmp` 目录原子改名、磁盘余量护栏（源×3）、16k wav 抽取、成功回写 hls_path/status=2/串联字幕 job 全部不变。
- copy 失败降级时 log.warn 记录 copy 的 stderr 尾部，便于后续统计 fallback 占比（PoC-1 决策"fallback 路径占比极低"的运行期验证数据）。

**验收**：
- Given h264+aac 的 mp4（培训视频主流形态）When 发布转码 Then ffmpeg 参数含 `-c copy`，13 分钟视频转码 <60s（PoC-1 实测 10.8s 量级），产物可播可拖。
- Given HEVC 源 When 发布 Then 直接走重编码（不先试 copy）。
- Given copy 启动后非零退出 When 执行 Then 自动重编码重跑一次，成功则 job success（error 不落库）。
- Given 重编码也失败（损坏文件）When 执行 Then failed + stderr 尾部（既有口径）。

**单测**：stub `probeCodecs` 返回值，断言生成的 ffmpeg 参数走对应路径；copy 失败时断言第二次调用为重编码命令。

---

## FP-05-3 qwen 翻译 25 条/批 + 统一降级逐条（P1）

**现状**：
- `SubtitlePipeline.java` 第 36 行 `TRANSLATE_BATCH_SIZE = 50`。
- `QwenTranslateEngine.translateBatch`（第 55-77 行）：条数校验 + 重试 2 次后抛 BizException，整个 translate stage 置 failed。

**改为（用户拍板：统一策略，不做 vi 特判）**：
1. 批大小 50 → **25**（PoC-2 实测 50 条模型易合并条目，25 条稳定）。
2. `translateBatch` 内部重试 2 次仍失败 → **降级逐条翻译**：逐条调用（每条同样剥围栏解析+校验单条），单条失败重试 2 次，仍失败抛 `BizException("qwen 翻译第 N 条失败: ...")`（标注序号，方便人工定位）。不再让整批失败直接终结 stage。
3. 时间戳/序号本地回填逻辑不变（`SubtitlePipeline.translateAll` 现有实现已正确）。
4. 降级发生时 log.warn 记录语言与条数（运行期统计 vi 等语言的实际降级率）。

**验收**：
- Given vi 语言批量 25 条连续 3 次条数不符 When 翻译 Then 自动逐条完成，SRT 条数与 zh 一致。
- Given 某单条 3 次尝试均失败 When 翻译 Then failed 且 error_msg 含"第 N 条"。
- Given zh/ha/en 批量一次成功 When 翻译 Then 不触发逐条（调用次数=批次数）。

**单测**：mock RestTemplate——前 3 次返回错误条数、后续逐条成功 → 断言走逐条路径且结果完整；单条持续失败 → 断言异常消息含序号。

---

## FP-05-4 ASR 热词 vocabulary_id（P2）

**事实修正（本 FP 取代 02 §7 热词条目的 context 表述）**：
经官方 REST 文档与 SDK 2.20.6 `TranscriptionParam` 反编译核实：录音文件识别 API 的 parameters 中
**不存在 `context`**（那是实时识别/SenseVoice 的参数）；paraformer-v2 的热词唯一入口是
`vocabulary_id`——需先在**百炼控制台"定制热词"创建热词表**获得 ID，提交转写时随 parameters 传入。
词表内容（商机、灯塔工厂、杰克缝纫产品词等）由用户在控制台维护，运营改词不改代码。

**实现**：
1. `application.properties` 增：`media.asr.vocabulary-id=${MEDIA_ASR_VOCABULARY_ID:}`
   （留空=不启用，完全不影响现有流程；沿用工程 properties 全 `${ENV_VAR:}` 占位的既有模式）。
2. `BailianAsrEngine`：构造注入该配置；`TranscriptionParam.builder()` 处有值则追加 `.vocabularyId(id)`
   （SDK 字段已核实存在，见 javap：`setVocabularyId(String)`）。未配置不设置，请求体不出现该参数。

> **热词表已创建（2026-10-08，经百炼热词 HTTP API）**：
> `vocabulary_id = vocab-kng-2ca5d66301134ad9b280837fbe5f4b5f`
> target_model=paraformer-v2（必须与识别模型完全一致才生效）、status=OK、初始词表={商机、灯塔工厂、杰克缝纫机}（weight=4）。
> 联调时将此 ID 配入 `MEDIA_ASR_VOCABULARY_ID`。词表增改走 `update_vocabulary`（**全量替换**、两次更新至少间隔 5 分钟），
> 词表上限 500 词、每账号上限 10 张表、**免费**；热词 API 与识别 API 必须同账号（当前项目共用 SpeechTraining
> `dashscope.api-key` 所在百炼账号——PoC-2 实测同账号）。

**验收**：
- Given 已配置 vocabulary-id When 提交转写 Then TranscriptionParam.getVocabularyId() 返回配置值（单测断言）。
- Given 未配置 When 提交转写 Then 不传该参数，行为与现状完全一致。
- 端到端效果验证（含"商机"语音转写不再出"上机"）依赖用户建好热词表，属联调阶段事项，不在本 FP 验收内。

**单测**：BailianAsrEngine 构造参数两分支（配置/未配置）的 param 断言。

---

## 部署联调清单（联调前自查，承接 04 §3 未尽事项）

| # | 事项 | 说明 |
|---|------|------|
| 1 | **执行 DDL** | ✅ **已执行（2026-10-08）**：`kng_media_job` 建表 + `kng_courseware` 五列增补 + `kng_setting.media_conf` + 种子，全部在 MySQL 9.2.0（10.100.26.200/final_dream）落地并验证（information_schema 幂等脚本，重复执行安全） |
| 2 | ffmpeg/ffprobe | 部署机 PATH 可用。GPL 决策已由 PoC-1 快路径缓解：沿用 gyan full 构建（-c copy 不调 x264，fallback 占比极低，内部部署不对外分发）；FP-05-2 落地后运行期日志可统计 fallback 率 |
| 3 | 环境变量 | `DASHSCOPE_API_KEY`、`MEDIA_OSS_ENDPOINT/BUCKET/ACCESS_KEY_ID/ACCESS_KEY_SECRET`（未配则字幕不可用、转码不受影响）；**新增 `MEDIA_ASR_VOCABULARY_ID`**（用户在百炼控制台建好热词表后填入，未填不影响流程） |
| 4 | OSS 桶 | `kng-asr-tmp/` 前缀配 1 天生命周期规则（临时对象双保险之一） |
| 5 | 百炼热词表 | ✅ **已创建（2026-10-08）**：`vocab-kng-2ca5d66301134ad9b280837fbe5f4b5f`（target_model=paraformer-v2，初始词=商机/灯塔工厂/杰克缝纫机，status=OK）。联调时填入 `MEDIA_ASR_VOCABULARY_ID`；词表增改见 FP-05-4 注（update_vocabulary 全量替换、间隔≥5分钟、免费） |

## 端到端联调用例（验收口径）

1. **转码全链路**：上传 13 分钟 h264 mp4 → merge 后发布表单标准时长自动回填（12分52秒）→ 发布 → 转码管理页"转码中"可见 → 秒级完成（流复制）→ 课件变已发布 → `GET .../play` 返回 playUrl，编辑字幕抽屉视频可播可拖。
2. **字幕全链路（P0 修复验证）**：开 AI 字幕 → 字幕管理"识别中"可见 → wav（>20MB）multipart 上传成功 → paraformer 转写 → 四语言 SRT 落盘 → 抽屉四 tab 渲染、行内编辑+保存生效 → 临时对象已删。
3. **失败路径**：上传损坏视频文件 → 转码失败 tab + 失败原因 + 【重试】；字幕翻译某批失败 → 自动降级逐条完成不失败。
4. **热词（可后置）**：填入 vocab ID 后，含"商机"语音转写不再出"上机"。

## 明确不做清单

- 前端零改动（四项均为后端行为修正，03 接口契约无任何变化）
- 不新增任何依赖（multipart 用 aliyun-sdk-oss 自带 UploadFileRequest；热词用 SDK 自带 vocabularyId）
- 不做 vi 语言特判（统一降级策略已覆盖）
- 不做多清晰度、不引入 MQ、不动 MediaWorker/MediaJobService 的投递/幂等/回收逻辑、不动 PublishSimulateJob 退役状态
- 不改 `MediaProbeService.probe` 的 MediaMeta 契约（probeCodecs 为新增方法）
- 不在本轮执行 DDL / 建热词表（部署侧人工事项，见清单）

## 验证要求

`mvnw.cmd test` 全绿：既有 18 项 + 上述四个 FP 各自新增单测；`contextLoads` 因 Nacos/MySQL 不可达的失败属环境问题，报告中注明即可。

---

## 实施记录（2026-10-08，本轮实施完成）

> 实施由需求侧直接完成（用户指令）；四个 FP 全部落地，单测 18 项新增全绿。
> **全量测试 35/36**：唯一失败 `contextLoads` 为 Nacos 配置中心（169.254.180.49:8848）不可达——环境问题，口径同 04 记录。

### 变更清单

| 文件 | 变更 |
|------|------|
| `OssTempService.java` | FP-05-1：putObject → `UploadFileRequest` 分块（8MB/块、3 并发、断点续传）；`uploadFile` 的受检异常收敛为 BizException |
| `MediaProbeService.java` | FP-05-2：新增 `probeCodecs(Path)` + `VideoAudioCodecs` record + `parseCodecs`（不动 `MediaMeta`/`probe` 契约） |
| `TranscodeTask.java` | FP-05-2：注入 MediaProbeService；三级策略（`shouldStreamCopy` 预判 / `hlsCommand` 构造 / copy 失败降级重跑一次） |
| `SubtitlePipeline.java` | FP-05-3：批大小 50→25 |
| `QwenTranslateEngine.java` | FP-05-3：批量重试耗尽 → `translateOneByOne` 逐条兜底（单条再重试 2 次，失败报"第 N 条"） |
| `TranslateEngine.java` | FP-05-3：javadoc 批大小/降级语义同步 |
| `BailianAsrEngine.java` | FP-05-4：注入 `media.asr.vocabulary-id`；参数构造提取为 package-private `buildParam`（有值才 `.vocabularyId()`） |
| `application.properties` | FP-05-4：`media.asr.vocabulary-id=${MEDIA_ASR_VOCABULARY_ID:}`（英文注释，纯 ASCII） |
| 新增测试 4 个类 | `OssTempServiceTest`(4) / `TranscodeTaskTest`(7) / `QwenTranslateEngineTest`(4) / `SubtitlePipelineTest`(1) / `BailianAsrEngineTest`(2)，共 18 项 |

### 实施决策与补充（相对 05 正文的微调，均已落注释）

1. **纯音频文件的流复制判定**（正文只定义了视频流规则，此处补充）：无视频流时 audioCodec=aac 可 copy（aac 直拷进 HLS 稳定），mp3/amr 等保守重编码为 aac。
2. **probeCodecs 探测失败（null）→ 保守走重编码**：不试错 copy。
3. **可测性调整**：`OssTempService` 加 package-private 测试构造器（注入 mock OSS）；`TranscodeTask.execFfmpeg/publishHlsDirectory` 由 private 改 package-private（spy 拦截不真起 ffmpeg 进程）。
4. **probeCodecs 不做扩展名过滤**：与 `probe` 的差异——调用方是转码 worker，文件类型已确定，只查 streams 的视频/音频 codec_name。
5. 降级与流复制失败均 log.warn（保留 stderr 尾部），供运行期统计 vi 降级率与 copy fallback 占比（PoC 决策的验证数据源）。

### 遗留（部署侧，联调前）

DDL 执行、OSS 桶生命周期规则、环境变量（含 `MEDIA_ASR_VOCABULARY_ID=vocab-kng-2ca5d66301134ad9b280837fbe5f4b5f`）——见上文联调清单；端到端联调用例四条待真实环境跑通。
