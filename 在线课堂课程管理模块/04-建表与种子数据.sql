-- ============================================================
-- 在线课堂（管理端）课程管理 + 课件管理增补 建表与种子数据
-- 版本 v1.0 ｜ 2026-10-03 ｜ 数据库：final_dream（10.100.26.200）
-- 配套：01-需求文档、02-技术实现方案、03-接口文档、05-课件管理增补
-- 前置：kng_catalog / kng_courseware / kng_ref / kng_study_record（课件管理 v1.0）已存在
-- ============================================================

-- 1. 课程主表
CREATE TABLE IF NOT EXISTS `kng_course` (
  `id`                       VARCHAR(32)  NOT NULL             COMMENT '雪花ID(字符串)',
  `title`                    VARCHAR(200) NOT NULL             COMMENT '名称(创建默认 未命名课程)',
  `catalog_id`               VARCHAR(32)  NOT NULL             COMMENT '所属分类',
  `status`                   TINYINT      NOT NULL DEFAULT 0   COMMENT '0未发布 1发布中 2已发布 3已下架',
  `on_sale`                  TINYINT      NOT NULL DEFAULT 1   COMMENT '上架位',
  `hidden`                   TINYINT      NOT NULL DEFAULT 0   COMMENT '隐藏标记(独立于status,学员不可见)',
  `structure_type`           TINYINT      NOT NULL DEFAULT 0   COMMENT '0无章节 1有章节',
  `unlock_mode`              TINYINT      NOT NULL DEFAULT 1   COMMENT '1自由学习 2按顺序学习',
  `unlock_unit`              TINYINT      NOT NULL DEFAULT 1   COMMENT '1按内容 2按章节(unlock_mode=2时生效)',
  `standard_duration_follow` TINYINT      NOT NULL DEFAULT 0   COMMENT '标准时长 0单独 1跟随学分策略',
  `standard_minutes`         INT          NOT NULL DEFAULT 0   COMMENT '标准时长-分(手填,展示优先任务聚合)',
  `standard_seconds`         INT          NOT NULL DEFAULT 0   COMMENT '标准时长-秒',
  `study_score`              DECIMAL(5,2) NULL                 COMMENT '单独学分;NULL=跟随(展示=任务学分和)',
  `finish_standard_percent`  INT          NOT NULL DEFAULT 100 COMMENT '完课标准10~100',
  `description`              TEXT         NULL                 COMMENT '简介(富文本)',
  `cover_url`                VARCHAR(500) NULL,
  `code`                     VARCHAR(100) NULL,
  `version_str`              VARCHAR(100) NULL,
  `platform_no`              VARCHAR(32)  NULL                 COMMENT 'ZXKTyyyyMMddNNNN',
  `view_permission`          TINYINT      NOT NULL DEFAULT 1   COMMENT '1跟随分类 2单独允许浏览',
  `speed_enabled`            TINYINT      NOT NULL DEFAULT 1   COMMENT '倍速播放(受全局playConf压制)',
  `speed_hours_calc`         TINYINT      NOT NULL DEFAULT 1   COMMENT '学时倍速计算',
  `contributor_id`           VARCHAR(32)  NULL                 COMMENT '贡献者 sys_user.id',
  `catalog_name`             VARCHAR(50)  NOT NULL DEFAULT ''  COMMENT '分类名冗余(搜索)',
  `created_by`               VARCHAR(32)  NULL,
  `created_by_name`          VARCHAR(50)  NULL,
  `created_at`               DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`               DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_catalog` (`catalog_id`),
  KEY `idx_status` (`status`),
  KEY `idx_updated` (`updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='在线课堂-课程';

-- 2. 课程章节表
CREATE TABLE IF NOT EXISTS `kng_course_chapter` (
  `id`          VARCHAR(32)  NOT NULL,
  `course_id`   VARCHAR(32)  NOT NULL,
  `name`        VARCHAR(200) NOT NULL             COMMENT '章节名称',
  `description` VARCHAR(500) NULL                 COMMENT '章节说明(填了则≥5字)',
  `order_index` INT          NOT NULL DEFAULT 0,
  `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_course` (`course_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='在线课堂-课程章节';

-- 3. 课程任务表(=课件引用)
CREATE TABLE IF NOT EXISTS `kng_course_task` (
  `id`            VARCHAR(32)  NOT NULL,
  `course_id`     VARCHAR(32)  NOT NULL,
  `chapter_id`    VARCHAR(32)  NULL               COMMENT 'NULL=无章节课程',
  `courseware_id` VARCHAR(32)  NOT NULL           COMMENT '引用的课件 kng_courseware.id',
  `task_name`     VARCHAR(200) NOT NULL           COMMENT '任务名(默认课件名,可改)',
  `hidden`        TINYINT      NOT NULL DEFAULT 0 COMMENT '隐藏标记(学员不可见,可恢复)',
  `order_index`   INT          NOT NULL DEFAULT 0,
  `created_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_course` (`course_id`),
  KEY `idx_chapter` (`chapter_id`),
  KEY `idx_courseware` (`courseware_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='在线课堂-课程任务(课件引用)';

-- ============================================================
-- 课件管理 v1.0 增补（05 增补文档）：kng_courseware 加 hidden 列；
-- kng_study_record 加 study_schedule 列（课程内课件学习详情页的"学习进度"列）
-- 幂等写法：存在性判断
-- ============================================================
SET @has_hidden := (SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'kng_courseware' AND COLUMN_NAME = 'hidden');
SET @ddl1 := IF(@has_hidden = 0,
  'ALTER TABLE `kng_courseware` ADD COLUMN `hidden` TINYINT NOT NULL DEFAULT 0 COMMENT ''隐藏标记(独立于status,学员不可见,可恢复)'' AFTER `on_sale`',
  'SELECT 1');
PREPARE s1 FROM @ddl1; EXECUTE s1; DEALLOCATE PREPARE s1;

SET @has_sched := (SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'kng_study_record' AND COLUMN_NAME = 'study_schedule');
SET @ddl2 := IF(@has_sched = 0,
  'ALTER TABLE `kng_study_record` ADD COLUMN `study_schedule` DECIMAL(5,2) NULL COMMENT ''学习进度%(课程内学习,学员端写入)'' AFTER `finish_method`',
  'SELECT 1');
PREPARE s2 FROM @ddl2; EXECUTE s2; DEALLOCATE PREPARE s2;

-- ============================================================
-- 验证脚本
-- SHOW TABLES LIKE 'kng_course%';      -- 预期 kng_course / kng_course_chapter / kng_course_task
-- SHOW COLUMNS FROM kng_courseware LIKE 'hidden';       -- 预期 1 行
-- SHOW COLUMNS FROM kng_study_record LIKE 'study_schedule';  -- 预期 1 行
-- ============================================================
