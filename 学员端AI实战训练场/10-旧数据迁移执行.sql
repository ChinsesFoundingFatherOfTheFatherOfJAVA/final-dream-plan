-- AI实战训练场：旧主题版本/设置数据迁移
-- MySQL 8
-- 前置：先创建 05-建表SQL.md 中的新表
-- 本脚本幂等，但生产执行前仍必须备份

SET NAMES utf8mb4;

-- =====================================================================
-- 0. 迁移前备份
-- =====================================================================
CREATE TABLE IF NOT EXISTS act_migration_backup_theme_v1
AS SELECT * FROM act_theme;

CREATE TABLE IF NOT EXISTS act_migration_backup_version_v1
AS SELECT * FROM act_theme_version;

CREATE TABLE IF NOT EXISTS act_migration_backup_material_v1
AS SELECT * FROM act_ai_material;

-- =====================================================================
-- 1. 条件增加主题/版本/材料列
-- MySQL 8 没有 ADD COLUMN IF NOT EXISTS，因此用 information_schema 判断。
-- =====================================================================
DROP PROCEDURE IF EXISTS act_migrate_columns_v1;
DELIMITER $$
CREATE PROCEDURE act_migrate_columns_v1()
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'act_theme'
      AND COLUMN_NAME = 'working_version_no'
  ) THEN
    ALTER TABLE act_theme
      ADD COLUMN working_version_no INT NULL COMMENT '0=hidden working before first publish; >0=working/published base';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'act_theme'
      AND COLUMN_NAME = 'published_version_no'
  ) THEN
    ALTER TABLE act_theme
      ADD COLUMN published_version_no INT NULL COMMENT 'published content version; null before first publish';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'act_theme'
      AND COLUMN_NAME = 'first_published_at'
  ) THEN
    ALTER TABLE act_theme ADD COLUMN first_published_at DATETIME NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'act_theme'
      AND COLUMN_NAME = 'content_hash'
  ) THEN
    ALTER TABLE act_theme ADD COLUMN content_hash VARCHAR(64) NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'act_theme_version'
      AND COLUMN_NAME = 'source_type'
  ) THEN
    ALTER TABLE act_theme_version
      ADD COLUMN source_type VARCHAR(32) NOT NULL DEFAULT 'legacy_content'
        COMMENT 'legacy_working/legacy_content/initial_publish/ai_confirm/manual_republish';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'act_theme_version'
      AND COLUMN_NAME = 'source_artifact_id'
  ) THEN
    ALTER TABLE act_theme_version ADD COLUMN source_artifact_id VARCHAR(32) NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'act_theme_version'
      AND COLUMN_NAME = 'source_artifact_version'
  ) THEN
    ALTER TABLE act_theme_version ADD COLUMN source_artifact_version INT NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'act_theme_version'
      AND COLUMN_NAME = 'content_hash'
  ) THEN
    ALTER TABLE act_theme_version ADD COLUMN content_hash VARCHAR(64) NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'act_theme_version'
      AND COLUMN_NAME = 'published_at'
  ) THEN
    ALTER TABLE act_theme_version ADD COLUMN published_at DATETIME NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'act_theme_version'
      AND COLUMN_NAME = 'published_by'
  ) THEN
    ALTER TABLE act_theme_version ADD COLUMN published_by VARCHAR(64) NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'act_ai_material'
      AND COLUMN_NAME = 'source_type'
  ) THEN
    ALTER TABLE act_ai_material
      ADD COLUMN source_type VARCHAR(32) NOT NULL DEFAULT 'act_local'
        COMMENT 'act_local/online_classroom';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'act_ai_material'
      AND COLUMN_NAME = 'source_id'
  ) THEN
    ALTER TABLE act_ai_material ADD COLUMN source_id VARCHAR(64) NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'act_ai_material'
      AND COLUMN_NAME = 'preview_status'
  ) THEN
    ALTER TABLE act_ai_material
      ADD COLUMN preview_status VARCHAR(24) NOT NULL DEFAULT 'not_needed'
        COMMENT 'not_needed/pending/ready/text_only/failed';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'act_ai_material'
      AND COLUMN_NAME = 'preview_file_id'
  ) THEN
    ALTER TABLE act_ai_material ADD COLUMN preview_file_id VARCHAR(64) NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'act_ai_material'
      AND COLUMN_NAME = 'preview_error'
  ) THEN
    ALTER TABLE act_ai_material ADD COLUMN preview_error VARCHAR(500) NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'act_scenario_unit'
      AND COLUMN_NAME = 'behavior_goals'
  ) THEN
    ALTER TABLE act_scenario_unit ADD COLUMN behavior_goals JSON NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'act_scenario_unit'
      AND COLUMN_NAME = 'dimension_weights'
  ) THEN
    ALTER TABLE act_scenario_unit ADD COLUMN dimension_weights JSON NULL;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.TABLES
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'act_content_version_material'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'act_content_version_material'
      AND COLUMN_NAME = 'preview_file_id'
  ) THEN
    ALTER TABLE act_content_version_material ADD COLUMN preview_file_id VARCHAR(64) NULL;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.TABLES
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'act_content_version_material'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'act_content_version_material'
      AND COLUMN_NAME = 'render_mode'
  ) THEN
    ALTER TABLE act_content_version_material
      ADD COLUMN render_mode VARCHAR(16) NOT NULL DEFAULT 'text' COMMENT 'pdf/text';
  END IF;
END$$
DELIMITER ;

CALL act_migrate_columns_v1();
DROP PROCEDURE act_migrate_columns_v1;

-- =====================================================================
-- 2. 全局设置表（与 05-建表SQL.md 相同）
-- =====================================================================
CREATE TABLE IF NOT EXISTS act_theme_settings (
  theme_id                    VARCHAR(32) NOT NULL,
  owner_user_id               VARCHAR(32) NULL,
  plan_start_time             DATETIME NULL,
  plan_end_time               DATETIME NULL,
  total_drill_count           INT NOT NULL DEFAULT 0 COMMENT '0=unlimited',
  per_scene_limit             INT NULL COMMENT 'null/0=unlimited',
  join_mode                   TINYINT NOT NULL DEFAULT 1,
  guest_access_enabled        TINYINT NOT NULL DEFAULT 0,
  training_mode_enabled       TINYINT NOT NULL DEFAULT 1,
  assessment_mode_enabled     TINYINT NOT NULL DEFAULT 0,
  ai_response_mode            TINYINT NOT NULL DEFAULT 1,
  coach_review_enabled        TINYINT NOT NULL DEFAULT 1,
  suggestion_enabled          TINYINT NOT NULL DEFAULT 0,
  dialog_modes                VARCHAR(32) NOT NULL DEFAULT 'voice,text',
  practice_methods            VARCHAR(64) NOT NULL DEFAULT 'case,custom,random',
  difficulty                  TINYINT NOT NULL DEFAULT 2,
  allow_custom_difficulty     TINYINT NOT NULL DEFAULT 1,
  face_check_before_enabled   TINYINT NOT NULL DEFAULT 0,
  face_check_ongoing_enabled  TINYINT NOT NULL DEFAULT 0,
  face_check_interval_seconds INT NOT NULL DEFAULT 300,
  screen_switch_mode          VARCHAR(16) NOT NULL DEFAULT 'forbid',
  screen_switch_limit         INT NOT NULL DEFAULT 0,
  scene_pass_type             TINYINT NOT NULL DEFAULT 1,
  scene_pass_count            INT NOT NULL DEFAULT 1,
  min_train_count_to_unlock_exam INT NOT NULL DEFAULT 1,
  max_exam_count              INT NOT NULL DEFAULT 0,
  created_at                  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (theme_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =====================================================================
-- 3. 素材来源和预览状态回填
-- =====================================================================
UPDATE act_ai_material
SET source_type = CASE
      WHEN file_id LIKE 'kng\_%' THEN 'online_classroom'
      ELSE 'act_local'
    END,
    source_id = CASE
      WHEN file_id LIKE 'kng\_%' THEN SUBSTRING(file_id, 5)
      ELSE NULL
    END
WHERE source_type IS NULL OR source_type = 'act_local';

UPDATE act_ai_material
SET preview_status = CASE
      WHEN LOWER(COALESCE(file_type, '')) IN ('pdf', 'txt', 'md') THEN 'not_needed'
      WHEN LOWER(COALESCE(file_type, '')) IN ('doc', 'docx', 'ppt', 'pptx', 'pps') THEN 'pending'
      ELSE 'text_only'
    END
WHERE preview_status IS NULL OR preview_status = 'not_needed';

-- =====================================================================
-- 4. 为从未发布主题创建隐藏 v0，并复制场景与维度
-- =====================================================================
DROP PROCEDURE IF EXISTS act_migrate_working_v0_v1;
DELIMITER $$
CREATE PROCEDURE act_migrate_working_v0_v1()
BEGIN
  DECLARE done INT DEFAULT 0;
  DECLARE v_theme_id VARCHAR(32);
  DECLARE v_current_version INT;

  DECLARE theme_cursor CURSOR FOR
    SELECT d.theme_id, d.current_version_no
    FROM tmp_act_draft_themes d;

  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

  DROP TEMPORARY TABLE IF EXISTS tmp_act_draft_themes;
  CREATE TEMPORARY TABLE tmp_act_draft_themes AS
  SELECT id AS theme_id, current_version_no
  FROM act_theme
  WHERE status NOT IN (3, 4, 5);

  START TRANSACTION;

  OPEN theme_cursor;
  read_loop: LOOP
    FETCH theme_cursor INTO v_theme_id, v_current_version;
    IF done = 1 THEN
      LEAVE read_loop;
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM act_theme_version
      WHERE theme_id = v_theme_id AND version_no = 0
    ) AND v_current_version IS NOT NULL THEN
      INSERT INTO act_theme_version (
        id, theme_id, version_no,
        theme_name, theme_desc, owner_user_id, plan_start_time, plan_end_time,
        total_drill_count, per_scene_limit, join_mode, guest_access_enabled,
        ai_response_mode, training_mode_enabled, assessment_mode_enabled,
        coach_review_enabled, suggestion_enabled, practice_methods, difficulty,
        allow_custom_difficulty, face_check_enabled, face_check_stage,
        screen_switch_mode, screen_switch_limit, scene_pass_type, scene_pass_count,
        creator, used_user_count, completed_count, in_progress_count,
        created_at, updated_at, source_type
      )
      SELECT
        REPLACE(UUID(), '-', ''), v_theme_id, 0,
        v.theme_name, v.theme_desc, v.owner_user_id, v.plan_start_time, v.plan_end_time,
        v.total_drill_count, v.per_scene_limit, v.join_mode, v.guest_access_enabled,
        v.ai_response_mode, v.training_mode_enabled, v.assessment_mode_enabled,
        v.coach_review_enabled, v.suggestion_enabled, v.practice_methods, v.difficulty,
        v.allow_custom_difficulty, v.face_check_enabled, v.face_check_stage,
        v.screen_switch_mode, v.screen_switch_limit, v.scene_pass_type, v.scene_pass_count,
        COALESCE(v.creator, 'migration'), 0, 0, 0,
        NOW(), NOW(), 'legacy_working'
      FROM act_theme_version v
      WHERE v.theme_id = v_theme_id AND v.version_no = v_current_version
      LIMIT 1;
    END IF;

    INSERT INTO act_scenario_unit (
      id, theme_id, version_no, sort_order, unit_name, audience,
      time_limit_minutes, business_goal, iceberg_elements, business_impact,
      failure_cost, core_conflict, common_failure_modes, difficulties,
      forbidden_behaviors, pass_score, created_at, updated_at,
      behavior_goals, dimension_weights
    )
    SELECT
      REPLACE(UUID(), '-', ''), u.theme_id, 0, u.sort_order, u.unit_name, u.audience,
      u.time_limit_minutes, u.business_goal, u.iceberg_elements, u.business_impact,
      u.failure_cost, u.core_conflict, u.common_failure_modes, u.difficulties,
      u.forbidden_behaviors, u.pass_score, NOW(), NOW(),
      u.behavior_goals, u.dimension_weights
    FROM act_scenario_unit u
    WHERE u.theme_id = v_theme_id
      AND u.version_no = v_current_version
      AND NOT EXISTS (
        SELECT 1 FROM act_scenario_unit existing
        WHERE existing.theme_id = u.theme_id
          AND existing.version_no = 0
          AND existing.sort_order = u.sort_order
      );

    INSERT INTO act_evaluation_dimension (
      id, scenario_unit_id, dimension_name, weight, dimension_desc,
      excellent_standard, good_standard, improve_standard, sort_order
    )
    SELECT
      REPLACE(UUID(), '-', ''), new_unit.id, d.dimension_name, d.weight, d.dimension_desc,
      d.excellent_standard, d.good_standard, d.improve_standard, d.sort_order
    FROM act_scenario_unit old_unit
    JOIN act_evaluation_dimension d ON d.scenario_unit_id = old_unit.id
    JOIN act_scenario_unit new_unit
      ON new_unit.theme_id = old_unit.theme_id
     AND new_unit.version_no = 0
     AND new_unit.sort_order = old_unit.sort_order
    WHERE old_unit.theme_id = v_theme_id
      AND old_unit.version_no = v_current_version
      AND NOT EXISTS (
        SELECT 1 FROM act_evaluation_dimension nd
        WHERE nd.scenario_unit_id = new_unit.id
          AND nd.dimension_name = d.dimension_name
          AND nd.sort_order = d.sort_order
      );

    UPDATE act_theme
    SET working_version_no = 0,
        published_version_no = NULL,
        updated_at = NOW()
    WHERE id = v_theme_id;
  END LOOP;
  CLOSE theme_cursor;

  COMMIT;
  DROP TEMPORARY TABLE IF EXISTS tmp_act_draft_themes;
END$$
DELIMITER ;

CALL act_migrate_working_v0_v1();
DROP PROCEDURE act_migrate_working_v0_v1;

-- =====================================================================
-- 5. 已发布主题指针
-- =====================================================================
UPDATE act_theme
SET working_version_no = COALESCE(working_version_no, current_version_no),
    published_version_no = COALESCE(published_version_no, current_version_no),
    first_published_at = COALESCE(first_published_at, updated_at)
WHERE status IN (3, 4, 5);

-- =====================================================================
-- 6. 全局设置回填
-- =====================================================================
INSERT INTO act_theme_settings (
  theme_id, owner_user_id, plan_start_time, plan_end_time,
  total_drill_count, per_scene_limit, join_mode, guest_access_enabled,
  training_mode_enabled, assessment_mode_enabled, ai_response_mode,
  coach_review_enabled, suggestion_enabled, dialog_modes, practice_methods,
  difficulty, allow_custom_difficulty, face_check_before_enabled,
  face_check_ongoing_enabled, screen_switch_mode, screen_switch_limit,
  scene_pass_type, scene_pass_count, min_train_count_to_unlock_exam, max_exam_count
)
SELECT
  t.id, v.owner_user_id, v.plan_start_time, v.plan_end_time,
  COALESCE(v.total_drill_count, 0), v.per_scene_limit,
  COALESCE(v.join_mode, 1), COALESCE(v.guest_access_enabled, 0),
  COALESCE(v.training_mode_enabled, 1), COALESCE(v.assessment_mode_enabled, 0),
  COALESCE(v.ai_response_mode, 1), COALESCE(v.coach_review_enabled, 1),
  COALESCE(v.suggestion_enabled, 0), 'voice,text',
  COALESCE(v.practice_methods, 'case,custom,random'),
  COALESCE(v.difficulty, 2), COALESCE(v.allow_custom_difficulty, 1),
  COALESCE(v.face_check_enabled, 0), COALESCE(v.face_check_enabled, 0),
  COALESCE(v.screen_switch_mode, 'forbid'), COALESCE(v.screen_switch_limit, 0),
  COALESCE(v.scene_pass_type, 1), COALESCE(v.scene_pass_count, 1), 1, 0
FROM act_theme t
JOIN act_theme_version v
  ON v.theme_id = t.id AND v.version_no = t.current_version_no
WHERE NOT EXISTS (
  SELECT 1 FROM act_theme_settings s WHERE s.theme_id = t.id
);

-- =====================================================================
-- 7. 迁移验证
-- =====================================================================
SELECT 'theme_settings_missing' AS check_name, COUNT(*) AS bad_count
FROM act_theme t
LEFT JOIN act_theme_settings s ON s.theme_id = t.id
WHERE s.theme_id IS NULL;

SELECT 'draft_v0_missing' AS check_name, COUNT(*) AS bad_count
FROM act_theme t
WHERE t.status NOT IN (3, 4, 5)
  AND NOT EXISTS (
    SELECT 1 FROM act_theme_version v
    WHERE v.theme_id = t.id AND v.version_no = 0
  );

SELECT 'published_pointer_invalid' AS check_name, COUNT(*) AS bad_count
FROM act_theme
WHERE status IN (3, 4, 5)
  AND (published_version_no IS NULL OR published_version_no <> current_version_no);

SELECT 'draft_pointer_invalid' AS check_name, COUNT(*) AS bad_count
FROM act_theme
WHERE status NOT IN (3, 4, 5)
  AND (working_version_no <> 0 OR published_version_no IS NOT NULL);

SELECT 'draft_scene_count_mismatch' AS check_name,
       SUM(CASE WHEN source_count <> v0_count OR v0_count IS NULL THEN 1 ELSE 0 END) AS bad_count
FROM (
  SELECT t.id,
         (SELECT COUNT(*) FROM act_scenario_unit u
          WHERE u.theme_id = t.id AND u.version_no = t.current_version_no) AS source_count,
         (SELECT COUNT(*) FROM act_scenario_unit u0
          WHERE u0.theme_id = t.id AND u0.version_no = 0) AS v0_count
  FROM act_theme t
  WHERE t.status NOT IN (3, 4, 5)
) check_counts;

SELECT 'draft_dimension_count_mismatch' AS check_name,
       SUM(CASE WHEN source_count <> v0_count OR v0_count IS NULL THEN 1 ELSE 0 END) AS bad_count
FROM (
  SELECT t.id,
    (
      SELECT COUNT(*)
      FROM act_evaluation_dimension d
      JOIN act_scenario_unit u ON u.id = d.scenario_unit_id
      WHERE u.theme_id = t.id AND u.version_no = t.current_version_no
    ) AS source_count,
    (
      SELECT COUNT(*)
      FROM act_evaluation_dimension d0
      JOIN act_scenario_unit u0 ON u0.id = d0.scenario_unit_id
      WHERE u0.theme_id = t.id AND u0.version_no = 0
    ) AS v0_count
  FROM act_theme t
  WHERE t.status NOT IN (3, 4, 5)
) check_dimensions;

-- =====================================================================
-- 8. 可选回滚（仅业务启用前手工执行）
-- =====================================================================
-- 新版 attempt/report 已产生后禁止执行。
--
-- DELETE d FROM act_evaluation_dimension d
-- JOIN act_scenario_unit u ON u.id = d.scenario_unit_id
-- JOIN act_theme_version v
--   ON v.theme_id = u.theme_id AND v.version_no = 0
-- WHERE v.source_type = 'legacy_working';
--
-- DELETE u FROM act_scenario_unit u
-- JOIN act_theme_version v
--   ON v.theme_id = u.theme_id AND v.version_no = 0
-- WHERE v.source_type = 'legacy_working';
--
-- DELETE FROM act_theme_version WHERE version_no = 0 AND source_type = 'legacy_working';
--
-- UPDATE act_theme
-- SET working_version_no = current_version_no,
--     published_version_no = CASE WHEN status IN (3,4,5) THEN current_version_no ELSE NULL END
-- WHERE id IN (
--   SELECT id FROM act_migration_backup_theme_v1
-- );
