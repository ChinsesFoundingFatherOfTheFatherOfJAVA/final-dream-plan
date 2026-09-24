# 07 DDL 变更清单（①②③ 已于 2026-09-23 执行并校验；⑤ 为 2026-09-24 新增的可重放脚本）

> 库：`final_dream` @ `10.100.26.200:3306`（**共享开发库**）
> 状态：**①②③ 已按顺序执行完毕**，用户批准由智能体代为执行；每步"执行前检查"均已先跑，结果见各节「执行结果」。
> 尚有一条**纯注释**变更（§④）未批，与功能无关，不阻塞任何链路。
> `schema.sql` 已按变更后的目标结构同步；库侧实际结构以 `SHOW CREATE TABLE` 为准（已比对，差异仅 §④ 一条注释）。
> **§⑤（2026-09-24 新增）**：①②③ 的**幂等可重放版**整理为 `sql/v1.2-评分维度与声学特征-表结构扩展.sql` + v1.3 的
> `sql/v1.3-口型驱动-视频资产表.sql`，堵"新环境按 sql/ 目录脚本升级会缺列缺表"的部署隐患（该目录此前停在 v1.1，
> 本轮审计发现并备案于 09 §J）。脚本已按 S0-1 落盘（10-工程实施提示词 §1），并已在开发库连续执行两遍验证幂等；
> 开发库原有结构已包含等效变更，本次验证未改动既有数据，脚本仍供新环境/重建环境使用。

---

## ① 评分维度：证据类型与量化指标（任务 #3）

### 为什么

v1.1 之前"语速适中""违禁词"两个维度的分数靠**维度名硬编码**判断，改名即失效；且"表达流利""态度积极"
等语音维度在纯文字轮次也照评，拿转写文本给"语速"打分，分数没有依据。
现在改为：维度带 `evidence_type`（评分依据：文字/语音/混合）与 `metric_config`（该维度由哪段后端规则定分），
语音依据的维度在本次训练无语音数据时**不参与评分**（权重归一化，报告说明原因）。

### 执行前检查

```sql
-- 1. 两列是否已存在（已存在则跳过对应 ADD COLUMN）
SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_DEFAULT
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = 'final_dream' AND TABLE_NAME = 'scoring_dimension'
  AND COLUMN_NAME IN ('evidence_type', 'metric_config');

-- 2. 将要回填的维度现状（确认 rule_type 5=公式计算=语速、6=扣分制=违禁词 的实际名称）
SELECT project_id, id, dimension_name, rule_type, weight, enabled
FROM scoring_dimension ORDER BY project_id, sort_order;
```

### 变更语句

```sql
ALTER TABLE scoring_dimension
  ADD COLUMN evidence_type TINYINT DEFAULT 1
    COMMENT '评分依据: 1=文字, 2=语音, 3=文字+语音。语音依据维度在本次训练无语音数据时不参与评分'
    AFTER scoring_rule,
  ADD COLUMN metric_config VARCHAR(500)
    COMMENT '量化指标配置(JSON): {"metric":"speech_speed","params":{...}}。空=该维度由AI评分；非空=得分由后端规则计算，AI只写评语'
    AFTER evidence_type;

-- 回填：原有"公式计算(5)"即语速、"扣分制(6)"即违禁词，改为按 metric key 路由，不再看名字
UPDATE scoring_dimension
SET evidence_type = 2, metric_config = '{"metric":"speech_speed"}'
WHERE rule_type = 5;

UPDATE scoring_dimension
SET metric_config = '{"metric":"forbidden_words"}'
WHERE rule_type = 6;
```

- 违禁词维度评的是转写文本，故其 `evidence_type` 保持默认 1（文字），只有语速改成 2（语音）。
- 未匹配到 rule_type 5/6 的项目不受影响，`evidence_type` 取默认 1 = 与改造前行为一致。

### 执行后校验

```sql
SELECT project_id, dimension_name, rule_type, evidence_type, metric_config
FROM scoring_dimension WHERE metric_config IS NOT NULL;
```

管理端任一项目"评分维度"区块应能看到"依据：文字/语音/混合"单选与所选维度回显正确。

### 执行结果（2026-09-23）

- 两列 `ADD COLUMN` 均一次成功（无 SKIP），`SHOW CREATE TABLE scoring_dimension` 已回读，列注释与本文一致。
- 回填命中 **2 个项目 / 4 行**（`scoring_dimension` 全表 14 行、共 2 个项目配了维度）：

  | project_id | 回填结果 |
  |----|----|
  | 5 | `语速适中` → `evidence_type=2` + `{"metric":"speech_speed"}`；`违禁词` → `evidence_type=1`（默认）+ `{"metric":"forbidden_words"}` |
  | 19 | 同上 |

- 其余 10 行维度 `evidence_type` 取默认 `1`、`metric_config` 为 `NULL`，即"AI 评分、凭文字"，与改造前行为一致。
- 管理端 `GET /admin/projects/{id}` 详情接口回读已带 `evidenceType` / `metricKey` / `metricConfig`，编辑页回显正确。
- 报告侧实测（报告 id=5，纯文字轮次）：`语速适中` 出 `score=null` 且明细写明"本次为文字作答，语音类维度不参与评分"，
  总分权重按参与维度归一；`违禁词` 由后端定分并用模板评语。

---

## ② 会话消息：序号唯一约束（任务 #5）

### 为什么

v1.2 把消息序号改为"会话行锁内取 MAX(seq)+1"。要挡住并发下的重复序号，光靠代码不够——
加 `UNIQUE (session_id, seq)` 让数据库成为最后一道闸。

### 执行前检查（**必须先跑，存量数据可能已有重复**）

```sql
-- 有输出 = 存在重复序号，先人工裁决保留哪条（通常是并发写入产生的），否则 ADD UNIQUE INDEX 直接失败
SELECT session_id, seq, COUNT(*) AS c, GROUP_CONCAT(id) AS ids
FROM training_session_message
GROUP BY session_id, seq
HAVING c > 1;
```

若有重复：按 `created_at`、`role` 顺序人工把后写入的那条改成不冲突的 seq（或删除），再执行变更。
**不要为了建索引批量改数据**——序号是会话内的展示顺序，改错会让对话记录错乱。

### 变更语句

```sql
ALTER TABLE training_session_message
  ADD UNIQUE INDEX uk_session_seq (session_id, seq);

-- 同时把列注释对齐（可选，不影响行为）
ALTER TABLE training_session_message
  MODIFY COLUMN seq INT NOT NULL COMMENT '会话内序号(在会话行锁内取 MAX+1,并发下不得重复)';
```

### 回滚

```sql
ALTER TABLE training_session_message DROP INDEX uk_session_seq;
```

回滚后代码仍可运行（锁内取号），只是失去数据库兜底。

### 执行结果（2026-09-23）

- **执行前检查：重复组 0 条**（`GROUP BY session_id, seq HAVING c>1` 无输出），因此未改动任何存量数据即建索引成功。
- `SHOW CREATE TABLE training_session_message` 已回读到 `UNIQUE KEY uk_session_seq (session_id, seq)`；
  `seq` 列注释同步为"在会话行锁内取 MAX+1,并发下不得重复"。
- 冒烟期间新建 5 个会话（12~16）、共写入 47 条消息（id 45~91），未触发约束冲突——说明锁内取号路径正常，
  约束只作为兜底闸；冲突时表现为 `DuplicateKeyException` → 该条消息写入失败回滚，不会产生错序记录。

---

## ③ 每轮语音声学特征表（任务 #6）

### 为什么

"语气/流利度"等语音维度此前无任何客观特征可用：豆包 ASR 的分句与逐字时间戳在解析时直接被丢弃。
本表把这些事实先攒下来（**只留存、不参与评分与流转**），为后续"语音维度到底能不能客观评"提供数据。
详见 02-技术实现方案 §4.5。

### 执行前检查

```sql
SELECT COUNT(*) FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'final_dream' AND TABLE_NAME = 'training_round_acoustic';
-- 返回 1 表示已存在，跳过建表
```

### 变更语句

```sql
CREATE TABLE IF NOT EXISTS training_round_acoustic (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  session_id BIGINT NOT NULL COMMENT '会话ID',
  message_id BIGINT NOT NULL COMMENT '学员语音消息ID(撤回的消息同样留存)',
  round_no INT COMMENT '轮次号(1起)',
  audio_ms INT COMMENT '录音时长(毫秒,本端WAV头,含静音)',
  speech_ms INT COMMENT '净发声时长(毫秒,各分句首尾跨度之和)',
  utterance_count INT COMMENT '分句数',
  pause_count INT COMMENT '停顿次数(相邻分句间隔≥300ms才计)',
  pause_total_ms INT COMMENT '停顿总时长(毫秒,与pause_count同口径)',
  max_pause_ms INT COMMENT '最长一次分句间隔(毫秒,不设阈值)',
  text_length INT COMMENT '识别文本长度(含标点)',
  lid_lang VARCHAR(32) COMMENT '豆包检出语种(粤语=speech_dia_cant,未检出为空)',
  definite TINYINT COMMENT '末分句是否终结结果: 0/1, NULL=无分句',
  words_json JSON COMMENT '豆包逐字时间戳原文(跨分句拼接的JSON数组)',
  server_audio_ms INT COMMENT '豆包回传音频时长(毫秒),与audio_ms不符即WAV封装头有问题',
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  UNIQUE INDEX uk_message (message_id),
  INDEX idx_session_round (session_id, round_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='每轮语音声学特征表(留存,暂不参与评分)';
```

### ⚠️ 部署顺序（必须遵守）

特征行与学员消息在**同一个事务、同一把会话行锁**内写入（保证不出现"有消息没特征"或反之）。
因此：**本表未建好之前，不要部署本轮后端**——否则每条语音消息都会整笔失败回滚，学员端表现为"语音上传失败"。

文字消息、报告、管理端不受本表影响。

> 实际执行顺序遵守了本条：**先建表 → 后重启后端**（2026-09-23）。

### 回滚

```sql
DROP TABLE training_round_acoustic;
```

回滚后需一并回退后端（原因同上）。

### 执行结果（2026-09-23）

- 建表一次成功（表原先不存在）。`SHOW CREATE TABLE training_round_acoustic` 与本文语句逐列一致，
  含 `uk_message (message_id)`、`idx_session_round (session_id, round_no)`、`words_json` 为 JSON 类型。
- 冒烟写入 **11 行**特征，覆盖同期 11 条语音消息；`training_session_message` 中 2026-09-23 之前的 2 条老语音消息
  （id 41、44）无特征行，属预期（当时表未建），未回填。
- 抽样实测（会话 14，撤回的消息同样留存）：

  | message_id | round | audio_ms | server_audio_ms | speech_ms | 分句 | text_length | words_json | lid_lang | definite |
  |----|----|----|----|----|----|----|----|----|----|
  | 86 | 5 | 18688 | 18688 | 7940 | 1 | 33 | 33 token | `speech_mand` | 1 |
  | 87 | 5 | 7288 | 7288 | 7283 | 1 | 36 | 33 token | `speech_mand` | 1 |

  - `audio_ms == server_audio_ms` **全部成立**（11/11）→ 本端 `WavHeader` 采样的头解析正确，豆包回传的音频时长能对上。
  - `speech_ms` 明显小于 `audio_ms`（7940 vs 18688）→ 净发声口径生效，录音里的静音段没被算进发声时长。
  - `pause_count=0` 而 `speech_ms < audio_ms` 不矛盾：样本是**单条整段音频**、ASR 只回一个分句，
    分句内停顿当前口径不测。多分句样本待真实对练数据积累（见 09 §K）。

---

## ④ 待批：`scoring_dimension.rule_type` 列注释（纯注释，不影响行为）

库侧注释仍是改造前的 `'规则类型(话术一致性专用): 1=精准逐字匹配, 2=要点表达, 3=混合模式'`，
而 `schema.sql` 与代码已按 1~6 六种取值使用（5=公式计算、6=扣分制即语速/违禁词的来源，见任务 #7 的兼容映射）。
注释里"话术一致性专用"已是错的信息，会误导下一个改维度的人。

```sql
ALTER TABLE scoring_dimension
  MODIFY COLUMN rule_type TINYINT DEFAULT 1
    COMMENT '规则类型: 1=精准逐字匹配, 2=要点表达, 3=混合模式, 4=分级评分, 5=公式计算, 6=扣分制。5/6 现仅作历史来源标记,定分改由 metric_config 路由';
```

- 只改注释，不改类型、默认值与任何数据；`MODIFY COLUMN` 在 MySQL 8 对同类型同默认值的注释变更走 INSTANT/元数据路径，不重建表。
- **未执行**：与功能无关的一条独立审批项，留给下次业务低峰一并处理。

---

## ⑤ v1.2 幂等增量脚本 + v1.3 视频资产表（2026-09-24 新增，未执行）

### ⑤-1 为什么

2026-09-23 修复轮的 DDL ①②③ 只执行进了开发库并同步了 `schema.sql`，**`sql/` 目录的增量脚本停留在 v1.1**——
新环境按目录脚本逐版升级会在 v1.2 断档：`scoring_dimension` 缺两列（管理端保存维度即报 Unknown column）、
`training_round_acoustic` 缺表（**语音消息整笔回滚**，见 ③ 部署顺序警告）、缺 `uk_session_seq` 兜底闸。
（2026-09-24 审计发现，09 §J 备案。）

### ⑤-2 `sql/v1.2-评分维度与声学特征-表结构扩展.sql`（内容即下文，code agent 按 S0-1 落盘）

> 幂等实现：MySQL 8 的 `ADD COLUMN / ADD INDEX` 不支持 `IF NOT EXISTS`，用临时存储过程 + information_schema
> 守卫；回填 UPDATE 带条件排除已回填行。**执行两遍不报错**。前置假设：库结构 = v1.1
> （已跑 `学员端话术训练-新增表.sql` + `v1.1-语音与形象-表结构扩展.sql`）。

```sql
-- v1.2 评分维度与声学特征（幂等，可重复执行；开发库已于 2026-09-23 直接执行过等效语句，勿重复跑也无妨）
DELIMITER $$

DROP PROCEDURE IF EXISTS p_v12_upgrade$$
CREATE PROCEDURE p_v12_upgrade()
BEGIN
  -- ① scoring_dimension: evidence_type / metric_config
  IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'scoring_dimension' AND COLUMN_NAME = 'evidence_type') THEN
    ALTER TABLE scoring_dimension
      ADD COLUMN evidence_type TINYINT DEFAULT 1
        COMMENT '评分依据: 1=文字, 2=语音, 3=文字+语音。语音依据维度在本次训练无语音数据时不参与评分'
        AFTER scoring_rule;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'scoring_dimension' AND COLUMN_NAME = 'metric_config') THEN
    ALTER TABLE scoring_dimension
      ADD COLUMN metric_config VARCHAR(500)
        COMMENT '量化指标配置(JSON): {"metric":"speech_speed","params":{...}}。空=该维度由AI评分；非空=得分由后端规则计算，AI只写评语'
        AFTER evidence_type;
  END IF;
  -- ① 回填（rule_type 5=公式计算=语速、6=扣分制=违禁词；条件排除已回填行，幂等）
  UPDATE scoring_dimension SET evidence_type = 2, metric_config = '{"metric":"speech_speed"}'
   WHERE rule_type = 5 AND metric_config IS NULL;
  UPDATE scoring_dimension SET metric_config = '{"metric":"forbidden_words"}'
   WHERE rule_type = 6 AND metric_config IS NULL;

  -- ② training_session_message: uk_session_seq（若存量有重复 seq，下面的 ALTER 会报错——
  --    先跑 ② 的执行前检查（09-23 实测开发库重复组为 0），有人工裁决后再重跑本脚本）
  IF NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'training_session_message' AND INDEX_NAME = 'uk_session_seq') THEN
    ALTER TABLE training_session_message
      ADD UNIQUE INDEX uk_session_seq (session_id, seq),
      MODIFY COLUMN seq INT NOT NULL COMMENT '会话内序号(在会话行锁内取 MAX+1,并发下不得重复)';
  END IF;
END$$

CALL p_v12_upgrade()$$

DROP PROCEDURE IF EXISTS p_v12_upgrade$$
DELIMITER ;

-- ③ training_round_acoustic（CREATE IF NOT EXISTS 天然幂等）
CREATE TABLE IF NOT EXISTS training_round_acoustic (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  session_id BIGINT NOT NULL COMMENT '会话ID',
  message_id BIGINT NOT NULL COMMENT '学员语音消息ID(撤回的消息同样留存)',
  round_no INT COMMENT '轮次号(1起)',
  audio_ms INT COMMENT '录音时长(毫秒,本端WAV头,含静音)',
  speech_ms INT COMMENT '净发声时长(毫秒,各分句首尾跨度之和)',
  utterance_count INT COMMENT '分句数',
  pause_count INT COMMENT '停顿次数(相邻分句间隔≥300ms才计)',
  pause_total_ms INT COMMENT '停顿总时长(毫秒,与pause_count同口径)',
  max_pause_ms INT COMMENT '最长一次分句间隔(毫秒,不设阈值)',
  text_length INT COMMENT '识别文本长度(含标点)',
  lid_lang VARCHAR(32) COMMENT '豆包检出语种(粤语=speech_dia_cant,未检出为空)',
  definite TINYINT COMMENT '末分句是否终结结果: 0/1, NULL=无分句',
  words_json JSON COMMENT '豆包逐字时间戳原文(跨分句拼接的JSON数组)',
  server_audio_ms INT COMMENT '豆包回传音频时长(毫秒),与audio_ms不符即WAV封装头有问题',
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  UNIQUE INDEX uk_message (message_id),
  INDEX idx_session_round (session_id, round_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='每轮语音声学特征表(v1.3起语速评分读speech_ms,停顿供混合维度参考)';
```

### ⑤-3 执行前检查（新环境必跑）

```sql
-- ② 的重复序号检查：有输出先人工裁决，否则建唯一索引会失败
SELECT session_id, seq, COUNT(*) AS c, GROUP_CONCAT(id) AS ids
FROM training_session_message GROUP BY session_id, seq HAVING c > 1;
```

### ⑤-4 `sql/v1.3-口型驱动-视频资产表.sql`（FP-29；**S3 才启用，落盘不执行**）

```sql
-- v1.3 口型驱动：陪练者视频资产表（设计见 08 §1.3.2；随 S3 阶段执行）
CREATE TABLE IF NOT EXISTS trainer_video_asset (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  asset_key CHAR(32) NOT NULL COMMENT '缓存键 md5(text|voice_id|speed|avatar_image|model),五要素任一变化即重新生成',
  text TEXT COMMENT '生成用台词原文(排查冗余,不参与逻辑)',
  voice_id VARCHAR(64) COMMENT '生成用音色',
  speed INT COMMENT '生成用语速刻度',
  avatar_image VARCHAR(255) COMMENT '生成用形象图URL',
  model VARCHAR(32) COMMENT '唇形模型(wav2lip/sadtalker)',
  status TINYINT DEFAULT 0 COMMENT '0=待生成 1=生成中 2=成功 3=失败(可重试)',
  file_path VARCHAR(255) COMMENT '成功后=/video/lip/{asset_key}.mp4',
  duration_ms INT COMMENT '视频时长(毫秒,与TTS durationMs同源)',
  error_msg VARCHAR(500) COMMENT '失败原因(如 no_face_detected=形象图不适合驱动)',
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE INDEX uk_asset_key (asset_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='陪练者口型视频资产(发布时预生成,运行时只读)';
```

> 时钟纪律（09 §K45 同款）：`updated_at` 由 DB 写。若后续给本表加"生成中超时回收"扫描，阈值必须用
> `DATE_SUB(CURRENT_TIMESTAMP, …)` 数据库时钟，不得用 JVM 时钟相减。
> 部署顺序：本表建好前不得部署启用了 `speech.lipsync.enabled=true` 的后端（否则查表报错——但降级路径返回
> videoUrl=null 不影响训练，风险远低于 ③ 的"整笔回滚"，仍建议先 DDL 后部署）。

---

## 执行完毕后的动作（①②③ 于 2026-09-23，已逐项完成）

1. ✅ 用 `SHOW CREATE TABLE scoring_dimension / training_session_message / training_round_acoustic` 取回线上真实结构，与
   `after-end/SpeechTraining/src/main/resources/schema.sql` 比对：**唯一差异是 §④ 的 `rule_type` 注释**，其余列、默认值、
   索引、字符集全部一致。schema.sql 无需回写。
2. ✅ 学员端语音链路已跑通（含静音与撤回两种异常态）。撤回消息的特征留存实测见 ③「执行结果」，SQL 口径：
   ```sql
   SELECT m.id, m.withdrawn, a.speech_ms, a.pause_count, a.lid_lang, a.words_json IS NOT NULL AS has_words
   FROM training_session_message m JOIN training_round_acoustic a ON a.message_id = m.id
   ORDER BY m.id DESC LIMIT 5;
   ```
   `pause_count` 在多分句真实样本上的表现**仍待验证**（当前样本恒为 1 个分句）。
3. ✅ 报告页两种口径均已实测：语音项目的语音维度**未出分**（该轮 ASR 未拿到通过答案，见 09 §K 残留说明），
   报告按设计写明"本次为文字作答，语音类维度不参与评分"；纯文字项目的 `违禁词` 由后端定分并配模板评语。
4. ⚠️ **冒烟残留数据留在共享开发库**，未擅自删除，清单见 `09-问题清单.md` §H.3。
