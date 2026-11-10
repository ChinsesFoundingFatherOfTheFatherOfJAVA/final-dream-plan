-- 测练中心·试卷管理 建表 SQL（MySQL 8.x，库 final_dream）
-- 版本 v1.0 2026-10-13；配套 05-需求文档/06-技术方案/07-接口文档
-- 前置：题库管理模块 04-建表SQL.md（exam_question 等九表已建，本文增量 7 张表）

-- 1. 试卷主表
CREATE TABLE IF NOT EXISTS `exam_paper` (
  `id` varchar(32) NOT NULL,
  `name` varchar(200) NOT NULL COMMENT '试卷名称',
  `catalog_id` varchar(32) NOT NULL DEFAULT 'root',
  `build_type` tinyint NOT NULL DEFAULT 0 COMMENT '0固定出卷 1随机出卷',
  `status` tinyint NOT NULL DEFAULT 0 COMMENT '0已保存 4已发布（简化两态）',
  `ques_mode` tinyint NOT NULL DEFAULT 0 COMMENT '抽题方式 0题型+难度 1题型 2难度 3数量',
  `secrecy` tinyint NOT NULL DEFAULT 0 COMMENT '0公开 1保密',
  `disabled` tinyint NOT NULL DEFAULT 0,
  `total_score` decimal(6,2) NOT NULL DEFAULT 0 COMMENT '总分（冗余）',
  `total_ques_qty` int NOT NULL DEFAULT 0 COMMENT '试题数（冗余，父题计数）',
  `used_qty` int NOT NULL DEFAULT 0 COMMENT '引用次数（考试回填）',
  `release_time` datetime DEFAULT NULL COMMENT '发布时间',
  `group_order` varchar(64) DEFAULT NULL COMMENT '大题排序兜底 JSON（如 "[0,1,3]"）',
  `deleted` tinyint NOT NULL DEFAULT 0,
  `created_by` varchar(32) DEFAULT '' COMMENT '创建人（转移时变更）',
  `created_by_name` varchar(64) DEFAULT '',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_by` varchar(32) DEFAULT '',
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_catalog` (`catalog_id`),
  KEY `idx_created_by` (`created_by`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='试卷';

-- 2. 试卷分类树（与题库分类独立两棵树，结构同构）
CREATE TABLE IF NOT EXISTS `exam_paper_catalog` (
  `id` varchar(32) NOT NULL,
  `parent_id` varchar(32) NOT NULL DEFAULT 'root',
  `name` varchar(200) NOT NULL,
  `order_index` int NOT NULL DEFAULT 0,
  `routing_path` varchar(64) NOT NULL DEFAULT '',
  `inherit_parent_auth` tinyint NOT NULL DEFAULT 0,
  `child_inherit_current_auth` tinyint NOT NULL DEFAULT 0,
  `disabled` tinyint NOT NULL DEFAULT 0,
  `deleted` tinyint NOT NULL DEFAULT 0,
  `created_by` varchar(32) DEFAULT '',
  `created_by_name` varchar(64) DEFAULT '',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_by` varchar(32) DEFAULT '',
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_parent` (`parent_id`),
  KEY `idx_routing` (`routing_path`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='试卷分类树';

-- 3. 试卷分类管理员（结构同 exam_catalog_admin）
CREATE TABLE IF NOT EXISTS `exam_paper_catalog_admin` (
  `id` varchar(32) NOT NULL,
  `catalog_id` varchar(32) NOT NULL,
  `user_id` varchar(32) NOT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_catalog_user` (`catalog_id`,`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='试卷分类管理员';

-- 4. 抽题策略（整条 JSON 存 setting_count）
CREATE TABLE IF NOT EXISTS `exam_paper_strategy` (
  `id` varchar(32) NOT NULL,
  `paper_id` varchar(32) NOT NULL,
  `lib_id` varchar(32) NOT NULL COMMENT '来源题库',
  `indicator_id` varchar(32) DEFAULT NULL COMMENT '按考核点来源时的考核点 id（按库来源为空）',
  `selected_source_type` tinyint NOT NULL DEFAULT 0 COMMENT '0按题库 1按考核点 2按自选试题',
  `selected_point_ids` varchar(2048) DEFAULT '1' COMMENT '考核点 id 逗号串（"1"=全部）',
  `setting_count` mediumtext COMMENT '策略 JSON：[{levelType, *Qty, needQty, *MaxQty, maxQty, *Score, multiMissScore, multiMissScoreType}] ×3 难度',
  `catalog_name` varchar(200) DEFAULT '' COMMENT '题库分类名快照',
  `lib_name` varchar(200) DEFAULT '' COMMENT '题库名快照',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_paper` (`paper_id`),
  KEY `idx_lib` (`lib_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='试卷抽题策略';

-- 5. 试卷-题目关联（固定卷大题分组）
CREATE TABLE IF NOT EXISTS `exam_paper_question` (
  `id` varchar(32) NOT NULL,
  `paper_id` varchar(32) NOT NULL,
  `ques_id` varchar(32) NOT NULL COMMENT '关联 exam_question.id（同源，不复制）',
  `score` decimal(5,2) NOT NULL DEFAULT 0 COMMENT '此题分值',
  `sub_scores` mediumtext COMMENT '组合题各小题分值 JSON：[{score,missScore,missScoreType}]（与子题同序；非组合题为空）',
  `miss_score` decimal(5,2) NOT NULL DEFAULT 0 COMMENT '多选漏选得分',
  `miss_score_type` tinyint NOT NULL DEFAULT 0 COMMENT '0不漏选得分 1统一得 2按漏选数量均分',
  `blank_scores` varchar(2048) DEFAULT NULL COMMENT '填空题按空得分 JSON：[{blankIndex,score}]（与答案空同序；未开启按空得分为空）',
  `section_index` tinyint NOT NULL DEFAULT 0 COMMENT '大题=题型值（0单选..5组合），中文编号前端算',
  `order_index` int NOT NULL DEFAULT 0 COMMENT '组内排序',
  `deleted` tinyint NOT NULL DEFAULT 0,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_paper_ques` (`paper_id`,`ques_id`),
  KEY `idx_ques` (`ques_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='试卷题目关联';

-- 6. 试卷共享范围（仅已发布可共享；结构同 exam_lib_share）
CREATE TABLE IF NOT EXISTS `exam_paper_share` (
  `id` varchar(32) NOT NULL,
  `paper_id` varchar(32) NOT NULL,
  `target_type` tinyint NOT NULL COMMENT '1部门 2人',
  `target_id` varchar(32) NOT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_paper_target` (`paper_id`,`target_type`,`target_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='试卷共享范围';

-- 7. 试卷引用轻量表（考试模块上线后回填；演示可插种子）
CREATE TABLE IF NOT EXISTS `exam_paper_use` (
  `id` varchar(32) NOT NULL,
  `paper_id` varchar(32) NOT NULL,
  `ref_name` varchar(200) DEFAULT '' COMMENT '引用方名称（考试名）',
  `source_type` tinyint NOT NULL DEFAULT 1 COMMENT '1课程安排 2单独安排',
  `creator_name` varchar(128) DEFAULT '',
  `status` varchar(32) DEFAULT '进行中' COMMENT '考试状态文本',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_paper` (`paper_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='试卷引用（考试回填）';

-- 8. 全局默认分值配置（设置默认分值抽屉；策略/新题分值默认值）
CREATE TABLE IF NOT EXISTS `exam_score_config` (
  `id` varchar(32) NOT NULL,
  `type` tinyint NOT NULL COMMENT '题型 0单选..4问答（组合无默认分值）',
  `level_type` tinyint NOT NULL DEFAULT 0,
  `score` decimal(5,2) NOT NULL DEFAULT 0,
  `miss_score` decimal(5,2) NOT NULL DEFAULT 0,
  `miss_score_type` tinyint NOT NULL DEFAULT 0,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_type_level` (`type`,`level_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='默认分值配置';

-- ============ 种子数据 ============
-- 试卷分类根节点（对齐原平台"默认试卷分类"）
INSERT INTO `exam_paper_catalog` (`id`,`parent_id`,`name`,`order_index`,`routing_path`)
SELECT 'root','root','默认试卷分类',0,'' FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM `exam_paper_catalog` WHERE `id`='root');

-- 默认分值种子（单选/判断各难度 1 分起步，实施时可按需调整）
INSERT INTO `exam_score_config` (`id`,`type`,`level_type`,`score`)
SELECT 'cfg-0-0',0,0,1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM `exam_score_config` WHERE `type`=0 AND `level_type`=0);

-- ============ 运维脚本 ============
-- 试卷冗余计数全量重算（对账用）：
-- UPDATE exam_paper p SET
--   total_ques_qty = (SELECT COUNT(*) FROM exam_paper_question pq WHERE pq.paper_id=p.id AND pq.deleted=0),
--   total_score = (SELECT COALESCE(SUM(score),0) FROM exam_paper_question pq WHERE pq.paper_id=p.id AND pq.deleted=0);
--
-- 引用次数重算（考试模块上线后）：
-- UPDATE exam_paper p SET used_qty = (SELECT COUNT(*) FROM exam_paper_use u WHERE u.paper_id=p.id);
