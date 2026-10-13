-- 测练中心·题库管理 建表 SQL（MySQL 8.x，库 final_dream）
-- 版本 v1.0 2026-10-12；配套 01-需求文档/02-技术方案/03-接口文档
-- 表前缀 exam_；id 统一 varchar(32) 雪花；审计字段统一 created_by/created_by_name/created_at/updated_by/updated_at
-- 逻辑删 deleted tinyint 0/1

-- 1. 分类树
CREATE TABLE IF NOT EXISTS `exam_catalog` (
  `id` varchar(32) NOT NULL COMMENT '雪花',
  `parent_id` varchar(32) NOT NULL DEFAULT 'root' COMMENT '父分类(root=根)',
  `name` varchar(200) NOT NULL COMMENT '分类名称',
  `order_index` int NOT NULL DEFAULT 0 COMMENT '同级排序',
  `routing_path` varchar(64) NOT NULL DEFAULT '' COMMENT '层级编码 001.001.002（root 子级为 001）',
  `inherit_parent_auth` tinyint NOT NULL DEFAULT 0 COMMENT '继承一级分类权限',
  `child_inherit_current_auth` tinyint NOT NULL DEFAULT 0 COMMENT '所有子分类继承当前分类权限',
  `disabled` tinyint NOT NULL DEFAULT 0,
  `deleted` tinyint NOT NULL DEFAULT 0,
  `created_by` varchar(32) DEFAULT '' COMMENT '创建人 userId',
  `created_by_name` varchar(64) DEFAULT '',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_by` varchar(32) DEFAULT '',
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_parent` (`parent_id`),
  KEY `idx_routing` (`routing_path`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='题库分类树（10级）';

-- 2. 分类管理员
CREATE TABLE IF NOT EXISTS `exam_catalog_admin` (
  `id` varchar(32) NOT NULL,
  `catalog_id` varchar(32) NOT NULL,
  `user_id` varchar(32) NOT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_catalog_user` (`catalog_id`,`user_id`),
  KEY `idx_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='分类管理员关系';

-- 3. 题库
CREATE TABLE IF NOT EXISTS `exam_lib` (
  `id` varchar(32) NOT NULL,
  `name` varchar(200) NOT NULL COMMENT '题库名称',
  `catalog_id` varchar(32) NOT NULL DEFAULT 'root',
  `secrecy` tinyint NOT NULL DEFAULT 0 COMMENT '0公开 1保密',
  `default_lib` tinyint NOT NULL DEFAULT 0 COMMENT '默认题库标记（每租户一个）',
  `disabled` tinyint NOT NULL DEFAULT 0,
  `duplicate_condition` tinyint NOT NULL DEFAULT 0 COMMENT '查重条件位标记 bit0单选..bit4问答',
  `point_qty` int NOT NULL DEFAULT 0 COMMENT '考核点数（冗余计数）',
  `total_ques_qty` int NOT NULL DEFAULT 0 COMMENT '试题数（冗余计数，父题计数）',
  `deleted` tinyint NOT NULL DEFAULT 0,
  `created_by` varchar(32) DEFAULT '' COMMENT '创建人 userId（转移时变更）',
  `created_by_name` varchar(64) DEFAULT '',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_by` varchar(32) DEFAULT '',
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_catalog` (`catalog_id`),
  KEY `idx_created_by` (`created_by`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='题库';

-- 4. 题库共享范围
CREATE TABLE IF NOT EXISTS `exam_lib_share` (
  `id` varchar(32) NOT NULL,
  `lib_id` varchar(32) NOT NULL,
  `target_type` tinyint NOT NULL COMMENT '1部门 2人',
  `target_id` varchar(32) NOT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_lib_target` (`lib_id`,`target_type`,`target_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='题库共享范围（部门/人）';

-- 5. 考核点
CREATE TABLE IF NOT EXISTS `exam_point` (
  `id` varchar(32) NOT NULL,
  `lib_id` varchar(32) NOT NULL,
  `name` varchar(200) NOT NULL,
  `default_point` tinyint NOT NULL DEFAULT 0 COMMENT '默认考点（每库唯一）',
  `deleted` tinyint NOT NULL DEFAULT 0,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_lib` (`lib_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='考核点';

-- 6. 试题（六题型统一表，组合题 parent_id 自关联）
CREATE TABLE IF NOT EXISTS `exam_question` (
  `id` varchar(32) NOT NULL,
  `lib_id` varchar(32) NOT NULL,
  `parent_id` varchar(32) NOT NULL DEFAULT '' COMMENT '组合题父题 id（子题非空）',
  `order_index` int NOT NULL DEFAULT 0 COMMENT '子题在父题内排序（父题为0）',
  `type` tinyint NOT NULL COMMENT '0单选1多选2判断3填空4问答5组合',
  `level_type` tinyint NOT NULL DEFAULT 0 COMMENT '0易1中2难',
  `status` tinyint NOT NULL DEFAULT 2 COMMENT '0已保存1已提交2已审核3不通过（列表不展示）',
  `content` mediumtext COMMENT '题干HTML（富文本）',
  `summary` varchar(2000) DEFAULT '' COMMENT '题干纯文本（列表/查看）',
  `summary_norm` varchar(2000) DEFAULT '' COMMENT '归一化题干（查重，去空白/HTML）',
  `stem_play` varchar(1024) DEFAULT NULL COMMENT '题干媒体 JSON {fileId,fileUrl,fileType}',
  `explain_text` mediumtext COMMENT '解析HTML',
  `explain_play` varchar(1024) DEFAULT NULL COMMENT '解析媒体 JSON',
  `judge_answer` tinyint NOT NULL DEFAULT 0 COMMENT '判断题答案 0正确 1错误',
  `judge_correct_option_content` varchar(500) DEFAULT '' COMMENT '判断题正确项文案',
  `judge_wrong_option_content` varchar(500) DEFAULT '' COMMENT '判断题错误项文案',
  `answer_content` mediumtext COMMENT '填空(按行)/问答题答案',
  `answer_play` varchar(1024) DEFAULT NULL COMMENT '问答题答案媒体 JSON',
  `answer_keywords` varchar(2048) DEFAULT NULL COMMENT '问答题关键词 JSON [{keyword,scoreRatio}]',
  `no_order_mark` tinyint NOT NULL DEFAULT 0 COMMENT '填空题多空答案不分先后',
  `duplicate` tinyint NOT NULL DEFAULT 0 COMMENT '查重重复标记',
  `sim_hash` bigint DEFAULT NULL COMMENT '查重增强预留（本期不用）',
  `disabled` tinyint NOT NULL DEFAULT 0,
  `deleted` tinyint NOT NULL DEFAULT 0,
  `created_by` varchar(32) DEFAULT '',
  `created_by_name` varchar(64) DEFAULT '',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_by` varchar(32) DEFAULT '',
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_lib` (`lib_id`),
  KEY `idx_parent` (`parent_id`),
  KEY `idx_norm` (`lib_id`,`type`,`summary_norm`(255))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='试题（组合题子题自关联）';

-- 7. 试题选项
CREATE TABLE IF NOT EXISTS `exam_question_item` (
  `id` varchar(32) NOT NULL,
  `ques_id` varchar(32) NOT NULL,
  `item_content` mediumtext COMMENT '选项HTML',
  `item_summary` varchar(1000) DEFAULT '' COMMENT '选项纯文本',
  `item_play` varchar(1024) DEFAULT NULL COMMENT '选项媒体 JSON',
  `answer` tinyint NOT NULL DEFAULT 0 COMMENT '0普通 1正确项',
  `order_index` int NOT NULL DEFAULT 0,
  `deleted` tinyint NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `idx_ques` (`ques_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='试题选项';

-- 8. 试题-考核点多对多
CREATE TABLE IF NOT EXISTS `exam_question_point` (
  `id` varchar(32) NOT NULL,
  `ques_id` varchar(32) NOT NULL,
  `point_id` varchar(32) NOT NULL,
  `order_index` int NOT NULL DEFAULT 0 COMMENT '最小=主考核点',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_ques_point` (`ques_id`,`point_id`),
  KEY `idx_point` (`point_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='试题考核点关联';

-- 9. 答题统计轻量聚合（考试模块上线后回填）
CREATE TABLE IF NOT EXISTS `exam_answer_stat` (
  `id` varchar(32) NOT NULL,
  `ques_id` varchar(32) NOT NULL,
  `point_id` varchar(32) NOT NULL DEFAULT '',
  `used_qty` int NOT NULL DEFAULT 0 COMMENT '引用次数',
  `total_answer_qty` int NOT NULL DEFAULT 0 COMMENT '答题数',
  `correct_answer_qty` int NOT NULL DEFAULT 0 COMMENT '正解数',
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_ques_point` (`ques_id`,`point_id`),
  KEY `idx_ques` (`ques_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='答题统计（回填）';

-- ============ 种子数据 ============
-- 根分类（对齐原平台：唯一根"默认题库分类"）
INSERT INTO `exam_catalog` (`id`,`parent_id`,`name`,`order_index`,`routing_path`)
SELECT 'root','root','默认题库分类',0,'' FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM `exam_catalog` WHERE `id`='root');

-- 默认题库（对齐原平台：每租户一个 default_lib=1 的库）+ 其默认考点
INSERT INTO `exam_lib` (`id`,`name`,`catalog_id`,`default_lib`)
SELECT '1','默认题库','root',1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM `exam_lib` WHERE `id`='1');

INSERT INTO `exam_point` (`id`,`lib_id`,`name`,`default_point`)
SELECT '1','1','默认考点',1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM `exam_point` WHERE `id`='1');

-- ============ 运维脚本：冗余计数全量重算（上线/对账用） ============
-- UPDATE exam_lib l SET
--   total_ques_qty = (SELECT COUNT(*) FROM exam_question q WHERE q.lib_id=l.id AND q.parent_id='' AND q.deleted=0),
--   point_qty = (SELECT COUNT(*) FROM exam_point p WHERE p.lib_id=l.id AND p.deleted=0);
