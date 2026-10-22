-- =====================================================================
-- AI实战训练场 · AI 设计助手模块 建表 SQL
-- 库：final_dream（10.100.26.200:3306）
-- 版本：v1.0  日期：2026-09-17
-- 内容：8 张新表 + 既有 2 表小改（幂等）
-- 执行：本机无 mysql CLI，用 ~/.m2 mysql-connector-j + 临时 Java 类执行（既有方案）
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. AI 会话表 act_ai_session（一个主题一个会话）
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS act_ai_session (
  id                    VARCHAR(40)  NOT NULL COMMENT 'uuid, also WS sessionId',
  theme_id              VARCHAR(32)           DEFAULT NULL COMMENT 'back-filled on topic-changed, null=new topic chat',
  title                 VARCHAR(100)          DEFAULT NULL,
  dify_conversation_id  VARCHAR(64)           DEFAULT NULL COMMENT 'dify orchestrator conversation id for multi-turn',
  creator               VARCHAR(64)           DEFAULT '管理员',
  created_at            DATETIME              DEFAULT NULL,
  updated_at            DATETIME              DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_act_ai_session_theme (theme_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='AI assistant chat session (one per theme)';

-- ---------------------------------------------------------------------
-- 2. AI 消息表 act_ai_message（块数组 JSON，cursor 分页）
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS act_ai_message (
  id           VARCHAR(48)  NOT NULL COMMENT 'client msg uuid or server xxx_0',
  db_id        VARCHAR(40)  NOT NULL COMMENT 'server row uuid (ack returns this)',
  session_id   VARCHAR(40)  NOT NULL,
  role         VARCHAR(16)  NOT NULL COMMENT 'user / assistant',
  content      JSON         NOT NULL COMMENT 'array of part blocks: text/file/data(action)',
  task_id      VARCHAR(64)           DEFAULT NULL,
  context_id   VARCHAR(64)           DEFAULT NULL,
  trace_id     VARCHAR(64)           DEFAULT NULL,
  created_at   DATETIME              DEFAULT NULL,
  PRIMARY KEY (db_id),
  KEY idx_act_ai_msg_session (session_id, created_at, db_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='AI assistant chat messages (block-array json)';

-- ---------------------------------------------------------------------
-- 3. AI 产物表 act_ai_artifact（版本化 JSON 快照；working 行=工作区，confirmed=已确认）
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS act_ai_artifact (
  id            VARCHAR(32)  NOT NULL COMMENT 'artifact snowflake id, stable per theme',
  theme_id      VARCHAR(32)  NOT NULL,
  version_no    INT          NOT NULL COMMENT 'increments per confirm cycle',
  content       JSON         NOT NULL COMMENT 'full artifact json (8 top fields)',
  status        VARCHAR(16)  NOT NULL DEFAULT 'working' COMMENT 'working / confirmed',
  content_hash  VARCHAR(64)           DEFAULT NULL COMMENT 'md5 of content, for confirm idempotent',
  confirmed_at  DATETIME              DEFAULT NULL,
  created_at    DATETIME              DEFAULT NULL,
  updated_at    DATETIME              DEFAULT NULL,
  PRIMARY KEY (id, version_no),
  KEY idx_act_ai_artifact_theme (theme_id, version_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='AI assistant versioned artifact snapshot';

-- ---------------------------------------------------------------------
-- 4. AI 材料表 act_ai_material（上传文件+解析摘要）
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS act_ai_material (
  id            VARCHAR(32)  NOT NULL,
  theme_id      VARCHAR(32)  NOT NULL,
  file_id       VARCHAR(64)  NOT NULL COMMENT 'stored file id under act-files/',
  name          VARCHAR(200) NOT NULL,
  file_type     VARCHAR(16)           DEFAULT NULL,
  file_size     BIGINT                DEFAULT NULL,
  visibility    TINYINT               DEFAULT 1 COMMENT '1 visible to student / 0 internal',
  extract_text  MEDIUMTEXT            COMMENT 'extracted full text (truncated)',
  summary       TEXT                  COMMENT 'llm summary fed to orchestrator',
  created_at    DATETIME              DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_act_ai_material_theme (theme_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='AI assistant uploaded materials';

-- ---------------------------------------------------------------------
-- 5. 客户画像表 act_customer_profile（确认落库产物，随版本）
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS act_customer_profile (
  id                   VARCHAR(32)  NOT NULL,
  theme_id             VARCHAR(32)  NOT NULL,
  version_no           INT          NOT NULL,
  profile_type         VARCHAR(50)  NOT NULL COMMENT 'e.g. price-sensitive purchasing manager',
  description          VARCHAR(500)          DEFAULT NULL,
  personalities        JSON                  DEFAULT NULL,
  decision_factors     JSON                  DEFAULT NULL,
  communication_style  VARCHAR(500)          DEFAULT NULL,
  pain_points          JSON                  DEFAULT NULL,
  sort_order           INT                   DEFAULT 1,
  created_at           DATETIME              DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_act_cp_theme_version (theme_id, version_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='customer profiles (confirmed from artifact)';

-- ---------------------------------------------------------------------
-- 6. 案例剧本表 act_case_script（确认落库产物；编译状态由发布流程更新）
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS act_case_script (
  id                        VARCHAR(32)  NOT NULL,
  theme_id                  VARCHAR(32)  NOT NULL,
  version_no                INT          NOT NULL,
  scenario_unit_id          VARCHAR(32)  NOT NULL,
  script_name               VARCHAR(100) NOT NULL,
  difficulty                TINYINT               DEFAULT 2 COMMENT '1 easy 2 medium 3 hard',
  actor_name                VARCHAR(32)           DEFAULT NULL,
  actor_position            VARCHAR(64)           DEFAULT NULL,
  actor_company             VARCHAR(64)           DEFAULT NULL,
  actor_type                VARCHAR(100)          DEFAULT NULL,
  actor_personality         VARCHAR(300)          DEFAULT NULL,
  actor_communication_style VARCHAR(300)          DEFAULT NULL,
  script_background         TEXT,
  script_opening            TEXT,
  status                    VARCHAR(16)  NOT NULL DEFAULT 'draft' COMMENT 'draft / compiled / failed',
  compile_error             VARCHAR(500)          DEFAULT NULL,
  created_at                DATETIME              DEFAULT NULL,
  updated_at                DATETIME              DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_act_case_theme_version (theme_id, version_no),
  KEY idx_act_case_scenario (scenario_unit_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='roleplay case scripts (confirmed from artifact)';

-- ---------------------------------------------------------------------
-- 7. 编译产物表 act_drill_script（发布初始化产物；学员端二期消费）
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS act_drill_script (
  id                VARCHAR(32)  NOT NULL,
  theme_id          VARCHAR(32)  NOT NULL,
  version_no        INT          NOT NULL,
  case_script_id    VARCHAR(32)  NOT NULL,
  scenario_unit_id  VARCHAR(32)  NOT NULL,
  compiled_payload  JSON         NOT NULL COMMENT 'self-contained drill script: actor setup + opening + scene + dimension refs',
  compiled_at       DATETIME              DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_act_drill_theme_version (theme_id, version_no),
  KEY idx_act_drill_case (case_script_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='compiled drill scripts (publish init product)';

-- ---------------------------------------------------------------------
-- 8. Dify 调用审计表 act_ai_call_log
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS act_ai_call_log (
  id            BIGINT       NOT NULL AUTO_INCREMENT,
  session_id    VARCHAR(40)           DEFAULT NULL,
  app_kind      VARCHAR(16)  NOT NULL COMMENT 'orchestrator / theme_gen / case_gen',
  trace_id      VARCHAR(64)           DEFAULT NULL,
  success       TINYINT               DEFAULT 1,
  error_msg     VARCHAR(500)          DEFAULT NULL,
  duration_ms   INT                   DEFAULT NULL,
  created_at    DATETIME              DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_act_ai_call_log_session (session_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='dify invocation audit log';

-- =====================================================================
-- 既有表小改（幂等：information_schema 判列存在才执行，由执行器保证）
-- =====================================================================
-- act_theme 增加 conversation_id（会话绑定，等同线上 conversationId）
-- ALTER TABLE act_theme ADD COLUMN conversation_id VARCHAR(40) DEFAULT NULL COMMENT 'bound ai session id';
-- （若已存在则跳过）

-- act_scenario_unit 增加 behavior_goals / dimension_weights（artifact 留档字段）
-- ALTER TABLE act_scenario_unit
--   ADD COLUMN behavior_goals JSON DEFAULT NULL COMMENT 'behavior goals from artifact (display in AI panel)',
--   ADD COLUMN dimension_weights JSON DEFAULT NULL COMMENT 'original dimension id+weight refs (archive)';
-- （逐列判断存在才加）

-- ---------------------------------------------------------------------
-- act_ai_material：解析链路改造（2026-09-18 补充执行）
-- 原因：编排智能体第 1 阶段允许"先上传材料再定主题"，此时材料还不能写入不可为空的 theme_id；
--      故材料先挂 session_id，create_topic 建主题后回填 theme_id 并追加进 artifact.materials。
-- ---------------------------------------------------------------------
-- ALTER TABLE act_ai_material ADD COLUMN session_id VARCHAR(40) DEFAULT NULL COMMENT 'bound session before theme exists';
-- ALTER TABLE act_ai_material ADD KEY idx_act_ai_material_session (session_id);
-- ALTER TABLE act_ai_material MODIFY COLUMN theme_id VARCHAR(32) DEFAULT NULL COMMENT 'null until theme created';
-- （逐列/索引判断存在才执行；实际执行语句见 db/06-ai-assistant-schema.sql）

> 说明：以上注释块是历史草案，最终可执行 DDL 已合并到 `AtualCombatTraining/db/06-ai-assistant-schema.sql`，以该文件为准。

-- 说明：act_theme.customer_profile_count 已存在（占位字段），本期改为真实值来源：
--   确认落库后 = act_customer_profile count(theme_id, current_version_no)
