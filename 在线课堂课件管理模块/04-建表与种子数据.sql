-- ============================================================
-- 在线课堂（管理端）课件管理 建表与种子数据
-- 版本 v1.0 ｜ 2026-09-30 ｜ 数据库：final_dream（10.100.26.200）
-- 配套：01-需求文档、02-技术实现方案、03-接口文档
-- 前置：kng_catalog（分类管理 v1.0）已存在；权限点 kng:courseware 已建
-- ============================================================

-- 1. 课件主表
CREATE TABLE IF NOT EXISTS `kng_courseware` (
  `id`                     VARCHAR(32)  NOT NULL             COMMENT '雪花ID(字符串)',
  `title`                  VARCHAR(200) NOT NULL             COMMENT '名称',
  `type`                   TINYINT      NOT NULL             COMMENT '1文档 2视频 3音频 4压缩 5微课(占位) 6SCORM 7HTML 8外链',
  `catalog_id`             VARCHAR(32)  NOT NULL             COMMENT '所属分类 kng_catalog.id',
  `status`                 TINYINT      NOT NULL DEFAULT 0   COMMENT '0未发布 1发布中 2已发布 3已下架',
  `on_sale`                TINYINT      NOT NULL DEFAULT 1   COMMENT '上架位：1上架 0下架（批量上下架/更多-下架同步维护）',
  `standard_minutes`       INT          NOT NULL DEFAULT 0   COMMENT '标准时长-分',
  `standard_seconds`       INT          NOT NULL DEFAULT 0   COMMENT '标准时长-秒',
  `standard_duration_follow` TINYINT    NOT NULL DEFAULT 0   COMMENT '标准时长 0单独设置 1跟随学分策略(文档/压缩/HTML/外链类；跟随态页数换算待媒体解析)',
  `study_score`            DECIMAL(5,2) NULL                 COMMENT '单独学分；NULL=跟随学分策略(kng_setting.score_conf)',
  `finish_standard_percent` INT         NOT NULL DEFAULT 100 COMMENT '完课标准(10~100)，发布后不可改',
  `description`            TEXT         NULL                 COMMENT '简介(富文本HTML)',
  `cover_url`              VARCHAR(500) NULL                 COMMENT '封面相对路径',
  `code`                   VARCHAR(100) NULL                 COMMENT '编码',
  `version_str`            VARCHAR(100) NULL                 COMMENT '版本(列名避 MySQL version)',
  `platform_no`            VARCHAR(32)  NULL                 COMMENT '平台课程编号 ZXKTyyyyMMddNNNN，发布时生成',
  `view_permission`        TINYINT      NOT NULL DEFAULT 1   COMMENT '1跟随分类浏览权限 2单独设置允许浏览',
  `download_enabled`       TINYINT      NOT NULL DEFAULT 1   COMMENT '允许下载 0/1',
  `download_permission`    TINYINT      NOT NULL DEFAULT 1   COMMENT '1跟随分类「允许下载课件」 2单独设置允许下载',
  `app_save_enabled`       TINYINT      NOT NULL DEFAULT 1   COMMENT '允许App保存 0/1',
  `app_save_permission`    TINYINT      NOT NULL DEFAULT 1   COMMENT '1跟随分类「App保存课件」 2单独设置允许保存',
  `speed_enabled`          TINYINT      NOT NULL DEFAULT 1   COMMENT '倍速播放开关',
  `speed_hours_calc`       TINYINT      NOT NULL DEFAULT 1   COMMENT '学时倍速计算开关',
  `ai_subtitle_enabled`    TINYINT      NOT NULL DEFAULT 0   COMMENT 'AI字幕开关(仅存储，生成待办)',
  `copy_of`                VARCHAR(32)  NULL                 COMMENT '源课件id(复制产生)',
  `contributor_id`         VARCHAR(32)  NULL                 COMMENT '贡献者 sys_user.id(默认创建人)',
  `language`               VARCHAR(20)  NULL                 COMMENT '课件级语种 zh/ha/en/vi',
  `catalog_name`           VARCHAR(50)  NOT NULL DEFAULT ''  COMMENT '分类名冗余(列表三字段模糊搜索避免join)',
  `created_by`             VARCHAR(32)  NULL                 COMMENT '上传者 sys_user.id',
  `created_by_name`        VARCHAR(50)  NULL                 COMMENT '上传者姓名冗余',
  `created_at`             DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '上传日期',
  `updated_at`             DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新日期(列表排序)',
  PRIMARY KEY (`id`),
  KEY `idx_catalog` (`catalog_id`),
  KEY `idx_status` (`status`),
  KEY `idx_updated` (`updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='在线课堂-课件';

-- 2. 课件文件/外链表
CREATE TABLE IF NOT EXISTS `kng_courseware_file` (
  `id`            VARCHAR(32)  NOT NULL               COMMENT '雪花ID',
  `courseware_id` VARCHAR(32)  NOT NULL               COMMENT '课件id',
  `file_name`     VARCHAR(255) NOT NULL               COMMENT '原始文件名',
  `storage_path`  VARCHAR(500) NULL                   COMMENT '磁盘相对路径；外链为NULL',
  `file_size`     BIGINT       NOT NULL DEFAULT 0     COMMENT '字节',
  `language`      VARCHAR(20)  NULL                   COMMENT '语种 zh/ha/en/vi；NULL=未设置',
  `sort_order`    INT          NOT NULL DEFAULT 0     COMMENT '顺序(预留)',
  `created_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_courseware` (`courseware_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='在线课堂-课件文件/外链';

-- 3. 课件附件表
CREATE TABLE IF NOT EXISTS `kng_courseware_attachment` (
  `id`            VARCHAR(32)  NOT NULL,
  `courseware_id` VARCHAR(32)  NOT NULL,
  `file_name`     VARCHAR(255) NOT NULL,
  `storage_path`  VARCHAR(500) NOT NULL,
  `file_size`     BIGINT       NOT NULL DEFAULT 0,
  `created_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_courseware` (`courseware_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='在线课堂-课件附件(上限50应用层校验)';

-- 4. 分片上传暂存表（合并后删除）
CREATE TABLE IF NOT EXISTS `kng_upload_chunk` (
  `upload_id`    VARCHAR(64)  NOT NULL               COMMENT '前端生成uuid',
  `chunk_index`  INT          NOT NULL,
  `total_chunks` INT          NOT NULL,
  `file_name`    VARCHAR(255) NOT NULL,
  `file_size`    BIGINT       NOT NULL,
  `md5`          VARCHAR(64)  NOT NULL               COMMENT '整文件MD5(秒传)',
  `rel_dir`      VARCHAR(200) NOT NULL               COMMENT '暂存目录',
  `created_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`upload_id`, `chunk_index`),
  KEY `idx_md5` (`md5`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='在线课堂-上传分片暂存';

-- 5. 学习记录表（学员端未做，种子空；详情页学习详情/学习数据数据源）
CREATE TABLE IF NOT EXISTS `kng_study_record` (
  `id`                VARCHAR(32) NOT NULL            COMMENT '雪花ID',
  `courseware_id`     VARCHAR(32) NOT NULL            COMMENT '课件id',
  `user_id`           VARCHAR(32) NOT NULL            COMMENT 'sys_user.id',
  `dept_id`           VARCHAR(32) NULL                COMMENT '学习时所属部门',
  `post`              VARCHAR(50) NULL                COMMENT '岗位快照',
  `study_status`      TINYINT     NOT NULL            COMMENT '1已完课 2学习中',
  `start_study_time`  DATETIME    NULL                COMMENT '开始学习时间',
  `end_study_time`    DATETIME    NULL                COMMENT '完成时间',
  `study_len_hours`   DECIMAL(8,2) NOT NULL DEFAULT 0 COMMENT '累计学习时长(h)',
  `finish_cost_days`  INT         NULL                COMMENT '完课用时(天)，未完课NULL',
  `finish_method`     TINYINT     NULL                COMMENT '1培训 2自学',
  `created_at`        DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_courseware` (`courseware_id`),
  KEY `idx_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='在线课堂-课件学习记录(学员端写入)';

-- 6. 引用关系表（预留：未来课程/考试模块插入记录，删除课件时的引用检查数据源）
CREATE TABLE IF NOT EXISTS `kng_ref` (
  `id`            VARCHAR(32) NOT NULL,
  `courseware_id` VARCHAR(32) NOT NULL               COMMENT '被引用课件id',
  `ref_type`      TINYINT     NOT NULL               COMMENT '1课程 2考试(预留枚举)',
  `ref_id`        VARCHAR(32) NOT NULL               COMMENT '引用方id',
  `ref_name`      VARCHAR(200) NOT NULL              COMMENT '引用方名称快照',
  `created_at`    DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_courseware` (`courseware_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='在线课堂-课件引用关系(课程/考试引用)';

-- 7. 示例种子（可选联调用；上线环境可删）
-- 前提：kng_catalog 存在"产品话术"分类（v1.0 分类管理数据）
-- INSERT INTO kng_courseware (id, title, type, catalog_id, status, standard_minutes, standard_seconds,
--   catalog_name, created_by, created_by_name) VALUES
--   ('9000000000000000100', '灯塔工厂方案5', 2, (SELECT id FROM kng_catalog WHERE name='产品话术' LIMIT 1),
--    2, 12, 52, '产品话术', 'admin_uid', '管理员');

-- ============================================================
-- 验证脚本
-- SHOW TABLES LIKE 'kng_%';        -- 预期新增 6 张
-- SELECT COUNT(*) FROM kng_courseware;         -- 0（或种子数）
-- SELECT COUNT(*) FROM kng_upload_chunk;       -- 0（暂存）
-- SELECT COUNT(*) FROM kng_study_record;       -- 0
-- ============================================================
