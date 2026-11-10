# AI实战训练场学员端与训考闭环建表 SQL

> 版本：v1.1 ｜ 日期：2026-10-30
> 数据库：MySQL 8 / `final_dream`
> 原则：新增表使用 `CREATE TABLE IF NOT EXISTS`；现有表使用迁移器判断列后再 `ALTER`，禁止重复执行失败。

## 1. 迁移顺序

1. 增加主题版本指针。
2. 建 `act_theme_settings`，把每个主题当前版本的设置迁入。
3. 为内容版本补充发布元数据。
4. 建产品档案、材料快照、参与关系、attempt、消息、报告和统计表。
5. 回填 `published_version_no/working_version_no`。
6. 停止旧代码“保存设置升版”和“创建主题即 v1”的写入路径。

## 2. 主题与版本

```sql
-- MySQL 8 不支持 ADD COLUMN IF NOT EXISTS；由 SchemaMigrationRunner 判断。
ALTER TABLE act_theme
  ADD COLUMN working_version_no INT NULL COMMENT '0=hidden working before first publish; >0=current working/published base',
  ADD COLUMN published_version_no INT NULL COMMENT 'published content version; null before first publish',
  ADD COLUMN first_published_at DATETIME NULL,
  ADD COLUMN content_hash VARCHAR(64) NULL COMMENT 'published content hash';

ALTER TABLE act_theme_version
  ADD COLUMN source_type VARCHAR(32) NOT NULL DEFAULT 'initial_publish'
    COMMENT 'legacy_working/legacy_content/initial_publish/ai_confirm/manual_republish',
  ADD COLUMN source_artifact_id VARCHAR(32) NULL,
  ADD COLUMN source_artifact_version INT NULL,
  ADD COLUMN content_hash VARCHAR(64) NULL,
  ADD COLUMN published_at DATETIME NULL,
  ADD COLUMN published_by VARCHAR(64) NULL;

-- 旧字段仍然存在，但新代码不再用它们控制设置或产生版本。
-- theme_name/theme_desc 在版本行仅作历史显示快照。
```

回填：

```sql
UPDATE act_theme t
SET t.working_version_no = COALESCE(
      t.working_version_no,
      CASE WHEN t.status IN (3, 4, 5) THEN t.current_version_no ELSE 0 END
    ),
    t.published_version_no = CASE
      WHEN t.status IN (3, 4, 5)
        THEN COALESCE(t.published_version_no, t.current_version_no)
      ELSE t.published_version_no
    END,
    t.first_published_at = CASE
      WHEN t.status IN (3, 4, 5)
        THEN COALESCE(t.first_published_at, t.updated_at)
      ELSE t.first_published_at
    END
WHERE t.working_version_no IS NULL
   OR (t.status IN (3, 4, 5) AND t.published_version_no IS NULL);
```

从未发布主题应把旧 `current_version_no` 的内容复制为隐藏 `v0`，再把 `working_version_no` 设为 0。迁移器必须同时复制场景和维度，保持 `sort_order` 对应；不得把旧草稿直接当作公开 `v1`。

## 3. 全局设置

```sql
CREATE TABLE IF NOT EXISTS act_theme_settings (
  theme_id                    VARCHAR(32) NOT NULL,
  owner_user_id               VARCHAR(32) NULL,
  plan_start_time             DATETIME NULL,
  plan_end_time               DATETIME NULL,
  total_drill_count           INT NOT NULL DEFAULT 0 COMMENT '0=unlimited',
  per_scene_limit             INT NULL COMMENT 'null/0=unlimited',
  join_mode                   TINYINT NOT NULL DEFAULT 1 COMMENT '1 assigned,2 assigned+public',
  guest_access_enabled        TINYINT NOT NULL DEFAULT 0 COMMENT 'reserved',
  training_mode_enabled       TINYINT NOT NULL DEFAULT 1,
  assessment_mode_enabled     TINYINT NOT NULL DEFAULT 0,
  ai_response_mode            TINYINT NOT NULL DEFAULT 1 COMMENT '1 expert,2 fast',
  coach_review_enabled        TINYINT NOT NULL DEFAULT 1,
  suggestion_enabled          TINYINT NOT NULL DEFAULT 0,
  dialog_modes                VARCHAR(32) NOT NULL DEFAULT 'voice,text' COMMENT 'csv subset of voice,text',
  practice_methods            VARCHAR(64) NOT NULL DEFAULT 'case,custom,random',
  difficulty                  TINYINT NOT NULL DEFAULT 2,
  allow_custom_difficulty     TINYINT NOT NULL DEFAULT 1,
  face_check_before_enabled   TINYINT NOT NULL DEFAULT 0,
  face_check_ongoing_enabled  TINYINT NOT NULL DEFAULT 0,
  face_check_interval_seconds INT NOT NULL DEFAULT 300,
  screen_switch_mode          VARCHAR(16) NOT NULL DEFAULT 'forbid' COMMENT 'forbid/allow',
  screen_switch_limit         INT NOT NULL DEFAULT 0,
  scene_pass_type             TINYINT NOT NULL DEFAULT 1 COMMENT '1 cumulative,2 consecutive',
  scene_pass_count            INT NOT NULL DEFAULT 1,
  min_train_count_to_unlock_exam INT NOT NULL DEFAULT 1,
  max_exam_count              INT NOT NULL DEFAULT 0 COMMENT '0=unlimited',
  created_at                  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (theme_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='theme-level global settings, independent from content versions';
```

从旧版本表回填：

```sql
INSERT INTO act_theme_settings (
  theme_id, owner_user_id, plan_start_time, plan_end_time,
  total_drill_count, per_scene_limit, join_mode, guest_access_enabled,
  training_mode_enabled, assessment_mode_enabled, ai_response_mode,
  coach_review_enabled, suggestion_enabled, dialog_modes, practice_methods, difficulty,
  allow_custom_difficulty, face_check_before_enabled, face_check_ongoing_enabled,
  screen_switch_mode, screen_switch_limit, scene_pass_type, scene_pass_count,
  min_train_count_to_unlock_exam, max_exam_count
)
SELECT
  t.id,
  v.owner_user_id,
  v.plan_start_time,
  v.plan_end_time,
  COALESCE(v.total_drill_count, 0),
  v.per_scene_limit,
  COALESCE(v.join_mode, 1),
  COALESCE(v.guest_access_enabled, 0),
  COALESCE(v.training_mode_enabled, 1),
  COALESCE(v.assessment_mode_enabled, 0),
  COALESCE(v.ai_response_mode, 1),
  COALESCE(v.coach_review_enabled, 1),
  COALESCE(v.suggestion_enabled, 0),
  'voice,text',
  COALESCE(v.practice_methods, 'case,custom,random'),
  COALESCE(v.difficulty, 2),
  COALESCE(v.allow_custom_difficulty, 1),
  COALESCE(v.face_check_enabled, 0),
  COALESCE(v.face_check_enabled, 0),
  COALESCE(v.screen_switch_mode, 'forbid'),
  COALESCE(v.screen_switch_limit, 0),
  COALESCE(v.scene_pass_type, 1),
  COALESCE(v.scene_pass_count, 1),
  1,
  0
FROM act_theme t
JOIN act_theme_version v
  ON v.theme_id = t.id
 AND v.version_no = t.current_version_no
WHERE NOT EXISTS (
  SELECT 1 FROM act_theme_settings s WHERE s.theme_id = t.id
);
```

说明：旧表只有一个 `face_check_stage`，回填时同时置两个开关为其布尔值，部署后需管理员按主题校正。

## 4. 产品档案

```sql
CREATE TABLE IF NOT EXISTS act_product_profile (
  id                    VARCHAR(32) NOT NULL,
  theme_id              VARCHAR(32) NOT NULL,
  content_version_no    INT NOT NULL DEFAULT 0 COMMENT '0=working content, >0 published version',
  profile_key           VARCHAR(64) NOT NULL COMMENT 'stable key inside artifact/version',
  profile_name          VARCHAR(100) NOT NULL,
  category              VARCHAR(200) NULL,
  description           TEXT NULL,
  detail_markdown       MEDIUMTEXT NULL,
  custom_fields         JSON NULL,
  source_artifact_id    VARCHAR(32) NULL,
  source_artifact_version INT NULL,
  sort_order            INT NOT NULL DEFAULT 1,
  created_by            VARCHAR(64) NULL,
  created_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_product_profile_version_key (theme_id, content_version_no, profile_key),
  KEY idx_product_profile_theme (theme_id, content_version_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='product profiles, working or published version snapshot';

CREATE TABLE IF NOT EXISTS act_scenario_product_profile (
  scenario_unit_id      VARCHAR(32) NOT NULL,
  product_profile_id    VARCHAR(32) NOT NULL,
  sort_order            INT NOT NULL DEFAULT 1,
  PRIMARY KEY (scenario_unit_id, product_profile_id),
  KEY idx_spp_profile (product_profile_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='scenario to product profile relation';
```

## 5. 材料快照

```sql
ALTER TABLE act_ai_material
  ADD COLUMN source_type VARCHAR(32) NOT NULL DEFAULT 'act_local'
    COMMENT 'act_local/online_classroom',
  ADD COLUMN source_id VARCHAR(64) NULL COMMENT 'coursewareId for online classroom',
  ADD COLUMN preview_status VARCHAR(24) NOT NULL DEFAULT 'not_needed'
    COMMENT 'not_needed/pending/ready/text_only/failed',
  ADD COLUMN preview_file_id VARCHAR(64) NULL,
  ADD COLUMN preview_error VARCHAR(500) NULL;

UPDATE act_ai_material
SET source_type = CASE WHEN file_id LIKE 'kng\_%' THEN 'online_classroom' ELSE 'act_local' END,
    source_id = CASE WHEN file_id LIKE 'kng\_%' THEN SUBSTRING(file_id, 5) ELSE NULL END
WHERE source_type = 'act_local' AND file_id LIKE 'kng\_%';

CREATE TABLE IF NOT EXISTS act_content_version_material (
  id                    VARCHAR(32) NOT NULL,
  theme_id              VARCHAR(32) NOT NULL,
  content_version_no    INT NOT NULL,
  material_id           VARCHAR(32) NOT NULL,
  name                  VARCHAR(200) NOT NULL,
  file_type             VARCHAR(16) NULL,
  file_size             BIGINT NULL,
  source_type           VARCHAR(32) NOT NULL,
  source_id             VARCHAR(64) NULL,
  preview_file_id       VARCHAR(64) NULL,
  render_mode           VARCHAR(16) NOT NULL DEFAULT 'text' COMMENT 'pdf/text',
  visibility            VARCHAR(16) NOT NULL DEFAULT 'student' COMMENT 'student/internal',
  sort_order            INT NOT NULL DEFAULT 1,
  created_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_content_material (theme_id, content_version_no, material_id),
  KEY idx_content_material_version (theme_id, content_version_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='published learning material snapshot';
```

## 6. 参与关系与学员统计

```sql
CREATE TABLE IF NOT EXISTS act_theme_participant (
  id                    VARCHAR(32) NOT NULL,
  theme_id              VARCHAR(32) NOT NULL,
  user_id               VARCHAR(32) NOT NULL,
  source                VARCHAR(16) NOT NULL COMMENT 'assigned/public',
  status                VARCHAR(16) NOT NULL DEFAULT 'active' COMMENT 'active/removed',
  extra_exam_attempt_count INT NOT NULL DEFAULT 0,
  joined_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  removed_at            DATETIME NULL,
  updated_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_theme_participant (theme_id, user_id),
  KEY idx_participant_user (user_id, status),
  KEY idx_participant_theme (theme_id, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='student participation in a theme';

CREATE TABLE IF NOT EXISTS act_student_scenario_stat (
  id                    VARCHAR(32) NOT NULL,
  user_id               VARCHAR(32) NOT NULL,
  theme_id              VARCHAR(32) NOT NULL,
  scenario_id           VARCHAR(32) NOT NULL,
  study_mode            TINYINT NOT NULL COMMENT '1 training,2 exam',
  formal_count          INT NOT NULL DEFAULT 0,
  completed_count       INT NOT NULL DEFAULT 0,
  passed_count          INT NOT NULL DEFAULT 0,
  consecutive_passed_count INT NOT NULL DEFAULT 0,
  highest_score         DECIMAL(6,2) NULL,
  latest_score          DECIMAL(6,2) NULL,
  last_attempt_at       DATETIME NULL,
  updated_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_student_scenario_mode (user_id, theme_id, scenario_id, study_mode),
  KEY idx_scene_stat_user_theme (user_id, theme_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='student scene counters and scoring summary';

CREATE TABLE IF NOT EXISTS act_exam_quota_adjustment (
  id                    VARCHAR(32) NOT NULL,
  theme_id              VARCHAR(32) NOT NULL,
  user_id               VARCHAR(32) NOT NULL,
  delta                 INT NOT NULL,
  reason                VARCHAR(200) NULL,
  created_by            VARCHAR(64) NULL,
  created_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_exam_quota_user (theme_id, user_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='exam quota adjustments audit';
```

## 7. Attempt

```sql
CREATE TABLE IF NOT EXISTS act_practice_attempt (
  id                    VARCHAR(40) NOT NULL,
  theme_id              VARCHAR(32) NOT NULL,
  scenario_id           VARCHAR(32) NOT NULL,
  user_id               VARCHAR(32) NOT NULL,
  study_mode            TINYINT NOT NULL,
  practice_type         VARCHAR(16) NOT NULL,
  status                VARCHAR(24) NOT NULL,
  active_key            VARCHAR(100) NULL,
  content_version_no    INT NOT NULL,
  settings_snapshot_json JSON NOT NULL,
  scenario_snapshot_json JSON NOT NULL,
  script_snapshot_json  JSON NULL,
  product_profiles_snapshot_json JSON NULL,
  materials_snapshot_json JSON NULL,
  custom_config_json    JSON NULL,
  difficulty            TINYINT NULL,
  agent_session_id      VARCHAR(64) NULL,
  preparation_stage    VARCHAR(32) NULL,
  preparation_percent  INT NOT NULL DEFAULT 0,
  quota_deducted       TINYINT NOT NULL DEFAULT 0,
  current_round         INT NOT NULL DEFAULT 0,
  max_round             INT NOT NULL DEFAULT 50,
  target_progress       INT NOT NULL DEFAULT 0,
  max_duration_seconds  INT NOT NULL,
  paused_duration_ms    BIGINT NOT NULL DEFAULT 0,
  client_writer_id      VARCHAR(64) NULL,
  created_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  prepared_at           DATETIME NULL,
  started_at            DATETIME NULL,
  deadline_at           DATETIME NULL,
  paused_at             DATETIME NULL,
  ended_at              DATETIME NULL,
  end_reason            VARCHAR(32) NULL,
  timed_out             TINYINT NOT NULL DEFAULT 0,
  error_code            VARCHAR(64) NULL,
  error_message         VARCHAR(500) NULL,
  updated_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_attempt_active_key (active_key),
  KEY idx_attempt_user_theme (user_id, theme_id, created_at),
  KEY idx_attempt_status_deadline (status, deadline_at),
  KEY idx_attempt_theme_scene (theme_id, scenario_id, user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='one formal training or exam attempt';

CREATE TABLE IF NOT EXISTS act_attempt_message (
  id                    VARCHAR(48) NOT NULL,
  attempt_id            VARCHAR(40) NOT NULL,
  seq                   BIGINT NOT NULL,
  role                  VARCHAR(16) NOT NULL COMMENT 'user/assistant/coach/system',
  message_type          VARCHAR(24) NOT NULL COMMENT 'text/voice/event',
  client_message_id     VARCHAR(64) NULL,
  text_content          MEDIUMTEXT NULL,
  data_json             JSON NULL,
  tts_json              JSON NULL,
  created_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_attempt_seq (attempt_id, seq),
  UNIQUE KEY uk_attempt_client_message (attempt_id, client_message_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='persisted drill conversation messages';

CREATE TABLE IF NOT EXISTS act_attempt_event (
  id                    BIGINT NOT NULL AUTO_INCREMENT,
  attempt_id            VARCHAR(40) NOT NULL,
  seq                   BIGINT NOT NULL,
  event_type            VARCHAR(48) NOT NULL,
  data_json             JSON NULL,
  created_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_attempt_event_seq (attempt_id, seq),
  KEY idx_attempt_event_type (attempt_id, event_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='server events for reconnect and audit';
```

`active_key` 只在活动状态非空，例如 `themeId:userId`；结束后置 null。

## 8. 报告

```sql
CREATE TABLE IF NOT EXISTS act_practice_report (
  id                    VARCHAR(40) NOT NULL,
  attempt_id            VARCHAR(40) NOT NULL,
  theme_id              VARCHAR(32) NOT NULL,
  scenario_id           VARCHAR(32) NOT NULL,
  user_id               VARCHAR(32) NOT NULL,
  study_mode            TINYINT NOT NULL,
  practice_type         VARCHAR(16) NOT NULL,
  passed                TINYINT NOT NULL DEFAULT 0,
  target_reached        TINYINT NOT NULL DEFAULT 0,
  target_reason         TEXT NULL,
  timed_out             TINYINT NOT NULL DEFAULT 0,
  end_reason            VARCHAR(32) NOT NULL,
  total_score           DECIMAL(6,2) NOT NULL DEFAULT 0,
  pass_score            INT NOT NULL DEFAULT 70,
  duration_seconds      INT NOT NULL DEFAULT 0,
  round_count           INT NOT NULL DEFAULT 0,
  summary               TEXT NULL,
  improvement_json      JSON NULL,
  key_dialogues_json   JSON NULL,
  recommendations_json JSON NULL,
  transcript_json       JSON NULL,
  raw_report_json       JSON NULL,
  generated_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_report_attempt (attempt_id),
  KEY idx_report_user_time (user_id, generated_at),
  KEY idx_report_theme_mode (theme_id, study_mode, generated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='one final report per attempt';

CREATE TABLE IF NOT EXISTS act_report_dimension (
  id                    VARCHAR(40) NOT NULL,
  report_id             VARCHAR(40) NOT NULL,
  dimension_key         VARCHAR(64) NOT NULL,
  dimension_name        VARCHAR(100) NOT NULL,
  score                 DECIMAL(6,2) NOT NULL,
  weight                DECIMAL(5,2) NOT NULL,
  evidence_json         JSON NULL,
  strength              TEXT NULL,
  improvement           TEXT NULL,
  reason                TEXT NULL,
  sort_order            INT NOT NULL DEFAULT 1,
  PRIMARY KEY (id),
  KEY idx_report_dimension (report_id, sort_order)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='dimension score details';
```

## 9. 防作弊

```sql
CREATE TABLE IF NOT EXISTS act_anti_cheat_event (
  id                    VARCHAR(40) NOT NULL,
  attempt_id            VARCHAR(40) NOT NULL,
  event_type            VARCHAR(32) NOT NULL COMMENT 'screen.hidden/face.pass/face.fail/camera.lost',
  client_event_id       VARCHAR(64) NULL,
  occurred_at           DATETIME NOT NULL,
  evidence_id           VARCHAR(40) NULL,
  data_json             JSON NULL,
  created_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_anti_cheat_client (attempt_id, client_event_id),
  KEY idx_anti_cheat_attempt (attempt_id, occurred_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='screen switch and face event audit';

CREATE TABLE IF NOT EXISTS act_face_evidence (
  id                    VARCHAR(40) NOT NULL,
  attempt_id            VARCHAR(40) NOT NULL,
  stage                 VARCHAR(16) NOT NULL COMMENT 'precheck/ongoing',
  storage_path          VARCHAR(500) NOT NULL,
  provider_result_json  JSON NULL,
  passed                TINYINT NOT NULL DEFAULT 0,
  created_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  delete_after          DATETIME NULL,
  PRIMARY KEY (id),
  KEY idx_face_attempt (attempt_id, created_at),
  KEY idx_face_cleanup (delete_after)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='camera capture evidence; restricted access';
```

## 9.1 随机练习脚本分档（2026-11-04 新增）

> 背景：抓包实测（`tmp/investigation-R2R3.md` §4.3）确认原平台**随机脚本在发布阶段预生成**，
> 4 场景 × 3 难度 = 12 份全部在发布窗口 70 秒内生成完毕；`randomScript?difficulty=N` 只是取档、
> 不调模型。本项目此前是「开练现场调 AG-D01 生成」，与实测不符，改为发布预生成 + 取档。
>
> 为什么单独建表而不是给 `act_drill_script` 加列：随机脚本按「场景×难度×候选」分档，
> 与案例「每案例一行、按 case_script_id 对齐」的口径完全不同。合并需要加 3 列并放宽
> `case_script_id` 的 NOT NULL 约束，还要给既有 11 处 `act_drill_script` 查询逐一补
> `kind='case'` 过滤——漏一处就会让案例练习取到随机脚本。单独建表后案例链路零改动。

```sql
CREATE TABLE IF NOT EXISTS act_random_script (
  id                VARCHAR(32)  NOT NULL,
  theme_id          VARCHAR(32)  NOT NULL,
  version_no        INT          NOT NULL,
  scenario_unit_id  VARCHAR(32)  NOT NULL,
  difficulty        TINYINT      NOT NULL COMMENT '1 easy / 2 medium / 3 hard',
  candidate_no      TINYINT      NOT NULL DEFAULT 1 COMMENT 'candidate index within the same bucket, 1-based',
  compiled_payload  JSON         NOT NULL COMMENT 'drill-script-v1 JSON, stored as-is at publish',
  compiled_at       DATETIME              DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_random_script_slot (theme_id, version_no, scenario_unit_id, difficulty, candidate_no),
  KEY idx_random_script_lookup (theme_id, version_no, scenario_unit_id, difficulty)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='random practice scripts pre-generated at publish (per scenario x difficulty x candidate)';
```

- 唯一键 `uk_random_script_slot` 是发布幂等的最终保证：重复发布先删该版本再插，不会堆积。
- 每档候选数由代码常量 `CANDIDATES_PER_BUCKET` 决定（首期定死 2，见 t13 说明），不入库配置——
  该常量一变，同档抽取结果全变，属于行为变更而非数据变更。

## 9.2 案例学员角色（userRole 三列，2026-11-05 新增）

> 背景：案例生成的 prompt/schema 补齐了 `userRoleName` / `userRolePosition` / `userRoleBackground`
> 三个**可选**字段（case-gen v2，DSL 源头见 `plan/final_dream_difys/案例生成-case-gen-v2.yml`）。
> 为什么先测缺失率再决定补填：字段可选，模型给不给要看真实生成情况，不能凭感觉写补填代码。
>
> 三列**全部可空**，且不允许"兜底造值"：取不到写 `NULL`，
> **禁止**用 `script_background`／场景旁白顶替 `user_role_background`（会把场景描述伪装成学员小传）。
> 列名口径：`user_role_position` 在运行时投影里映射到 `AttemptResp.userRoleIdentity`
> （「身份摘要」语义），`user_role_name` → `userRoleName`，`user_role_background` → `userRoleBackground`；
> `userRoleAge` 案例侧没有数据源，保持 `null`，不拿岗位顶替。

```sql
-- MySQL 8 不支持 ADD COLUMN IF NOT EXISTS；由 SchemaMigrationRunner 判断列后再 ALTER。
ALTER TABLE act_case_script
  ADD COLUMN user_role_name       VARCHAR(32) NULL COMMENT '学员角色名 (case-gen v2 userRoleName, optional)',
  ADD COLUMN user_role_position   VARCHAR(64) NULL COMMENT '学员岗位 (userRolePosition); projected as AttemptResp.userRoleIdentity',
  ADD COLUMN user_role_background TEXT        NULL COMMENT '学员人物背景 (userRoleBackground); never fallback to script_background';
```

- 发布快照 `act_drill_script.compiled_payload` 同步带上这三个键（payload 已有则保留、缺失才用列值补），
  否则发布后案例快照会丢失它们。
- 升版复制案例行（`ContentVersionServiceImpl.copyOf`）必须一并复制三列，否则新版本只剩 actor 侧字段。
- 老数据无需回填：这三列本来就没有历史来源，留 `NULL` 正是"该案例没有学员角色"的准确表达。

## 9.3 数字人形象（4 列，2026-11-05 新增）

> 背景：`tmp/r4-avatar-impl.md` §5.1 选定**方案 B「双写」**——形象同时写进发布快照
> `compiled_payload`（学员端实际读这里）与 `act_*.actor_avatar_url` 列（后台可单换图、可统计）。
> 素材是 t1 自建的 60 张 WebP（2 性别 × 5 年龄档 × 6 张），落 `app.upload.avatar-dir`，
> URL 形如 `/avatar/m-A3-04.webp`，浏览器经网关白名单 `/api/avatar/**` 访问。
>
> **属性两列** `actor_gender` / `actor_age_range` 来自 case-gen v3 的**可选**字段
> （DSL 源头 `plan/final_dream_difys/案例生成-case-gen-v3.yml`，v2 未动）。
> 为什么可选：v3 只增不改，required 仍是原 10 项，先测缺失率；取不到留 `NULL`，
> **禁止**按角色名猜性别（设计 §3.4 勘误：模型会自行推断属性，猜比没有更糟）。
> `actor_gender` 允许写「男」「女」或 `male`/`female`，归一化在
> `AvatarMappingService.normalizeGender` 做，**不在库里做格式约束**——避免模型口径差异变成落库脏数据。
>
> **`actor_avatar_url` 的写入来源（优先级从高到低）**：
> 1. 管理端上传覆盖（L0）：列已有值 → 发布时**原样透传**，覆盖任何自动映射；
> 2. 定图服务算出的预置素材图（L1~L4），发布期 `compileOne` / 随机预生成写入；
> 3. 无（返回 `NULL`）：前端「角色名首字圆形」占位（现网已有，零改动）。
>
> **不造假约束**：任何一层取不到就 `NULL`，禁止拿别的图顶替（如用男性图冒充女性）；
> L4 场景默认图是设计里明确的一层，同 `scenario_id` 恒定映射，**不是**顶替。

```sql
-- MySQL 8 不支持 ADD COLUMN IF NOT EXISTS；由 SchemaMigrationRunner 判断列后再 ALTER。
ALTER TABLE act_case_script
  ADD COLUMN actor_gender     CHAR(1)      NULL COMMENT 'AI actor gender (case-gen v3 actorGender); null = not generated',
  ADD COLUMN actor_age_range  VARCHAR(16)  NULL COMMENT 'AI actor age range (case-gen v3 actorAgeRange, e.g. 40-45岁); null = not generated',
  ADD COLUMN actor_avatar_url VARCHAR(512) NULL COMMENT 'L0 admin upload override only (written by case-avatar API); publish never writes it; null = no override';

ALTER TABLE act_drill_script
  ADD COLUMN actor_avatar_url VARCHAR(512) NULL COMMENT 'same value as compiled_payload actor avatar (dual-write)';
```

- 定图时机统一在**发布期**（不运行时算）：案例 `PublishInitServiceImpl.compileOne`，
  随机 `RandomScriptServiceImpl.pregenerate`。运行时 `AttemptResp.actorAvatarUrl`
  只从快照投影（`StudentAttemptController.fillRoleDetails`），零计算零请求。
- **两列的职责必须分清**（2026-11-05 端到端实测后修正，原注释写成"定图结果也写这里"是错的）：
  - `act_drill_script.actor_avatar_url` = **定图结果的双写列**：发布时写，值与
    `compiled_payload` 里的 avatar 键同值（学员端实际读 payload）。
  - `act_case_script.actor_avatar_url` = **仅 L0 人工上传覆盖的输入端**：
    只由管理端「换形象」接口（`CaseAvatarService`）写入；发布**只读不写**它。
    **为什么发布不回写**：若发布把自动定的图写回这一列，`resolveAvatar` 下次就会把
    上一轮的自动结果误判为"人工上传覆盖（L0）"，属性再怎么变都不会换图——
    降级链和 hash 稳定性会一起失效。该列 `NULL` 才是准确的"没人上传过"。
- **`seq = SHA-256(actorName|identity) 前 4 字节 % pool.length`**，算法写死、不用语言内建 hash
  （设计 §7.2 B4：要跨进程稳定，否则「重练沿用同图」不成立）。
- **每组合 N=6 首期定死**（`AvatarMappingServiceImpl.IMAGES_PER_GROUP`，设计 §7.2 B5）：
  池大小一变 `% N` 结果全变 → 所有已分配角色**全量换脸**，属行为变更而非数据变更。
- 升版复制案例行（`ContentVersionServiceImpl.copyOf`）必须复制这 3 列，
  否则新版本丢掉性别/年龄（定图降级到 L3/L4 换脸），上传覆盖（L0）也会失效。
- `act_random_script` **不加列**：随机脚本的形象写在 `compiled_payload.actor.avatarUrl` 里，
  与「图挂档内角色、不另存档位形象」的设计一致（设计 §3.3）。
- `act_practice_attempt` **不加列**：运行时读 `script_snapshot_json` 即可（设计 §5.2 D4）。
- 存量已发布主题不回填：老 payload 无 avatarUrl → `actorAvatarUrl` 为 `null` → 前端首字占位，
  不报错、也不降级成错误图片。

## 10. 索引与运行注意事项

- 所有 JSON 列只在服务端解析，前端 DTO 使用普通对象。
- `active_key` 唯一索引是活动 attempt 唯一的最终保证。
- `act_attempt_message` 的 `client_message_id` 允许 null，但客户端发起的消息必须带值。
- `act_attempt_event` 增长快，按 `created_at` 做归档任务。
- 人脸图片保存到独立目录 `act-drill-evidence/`，禁止位于静态资源目录。
- 发布迁移完成后删除或停止旧的 `current_version_no` 业务写入。
