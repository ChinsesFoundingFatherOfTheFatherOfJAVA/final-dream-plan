-- 测练中心·考试管理 建表 SQL（MySQL 8.x，库 final_dream）
-- 版本 v1.0 2026-10-14；配套 01-需求文档 / 02 前端方案 / 03 后端方案 / 04 接口文档
-- 前置：题库管理模块 04-建表SQL、试卷管理模块 08-建表SQL 已执行。
-- 本文件为增量：新增考试管理 15 张表，并对 exam_paper_use 增加考试引用字段。

-- 1. 考试分类树
CREATE TABLE IF NOT EXISTS `exam_arrange_catalog` (
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
  KEY `idx_arrange_catalog_parent` (`parent_id`),
  KEY `idx_arrange_catalog_routing` (`routing_path`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='考试分类树';

-- 2. 考试分类管理员
CREATE TABLE IF NOT EXISTS `exam_arrange_catalog_admin` (
  `id` varchar(32) NOT NULL,
  `catalog_id` varchar(32) NOT NULL,
  `user_id` varchar(32) NOT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_arrange_catalog_user` (`catalog_id`,`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='考试分类管理员';

-- 3. 考试主表
CREATE TABLE IF NOT EXISTS `exam_arrange` (
  `id` varchar(32) NOT NULL,
  `name` varchar(1000) NOT NULL COMMENT '考试名称',
  `catalog_id` varchar(32) NOT NULL DEFAULT 'root',
  `exam_type` tinyint NOT NULL DEFAULT 1 COMMENT '1线上考试',
  `publish_status` tinyint NOT NULL DEFAULT 0 COMMENT '0未发布 1已发布 2已结束',
  `run_status` tinyint NOT NULL DEFAULT 0 COMMENT '0未开始 1进行中 2已结束 3不限',
  `audit_status` tinyint NOT NULL DEFAULT 0 COMMENT '0未发布/未提交 2审核通过',
  `arrange_type` tinyint NOT NULL DEFAULT 0 COMMENT '0单独安排',
  `offline` tinyint NOT NULL DEFAULT 0 COMMENT '0非线下 1线下',
  `step_number` tinyint NOT NULL DEFAULT 1 COMMENT '创建步骤 1创建试卷 2编辑试题 3发布考试',
  `paper_id` varchar(32) NOT NULL COMMENT '试卷 ID',
  `paper_build_type` tinyint NOT NULL DEFAULT 0 COMMENT '0固定出卷 1随机出卷',
  `code` varchar(100) DEFAULT '' COMMENT '考试编号',
  `important` tinyint NOT NULL DEFAULT 0,
  `secrecy` tinyint NOT NULL DEFAULT 0,
  `loop_enabled` tinyint NOT NULL DEFAULT 0,
  `entry_start_at` datetime DEFAULT NULL,
  `entry_end_at` datetime DEFAULT NULL,
  `required_type` tinyint NOT NULL DEFAULT 1 COMMENT '1必修 2选修',
  `pass_score_type` tinyint NOT NULL DEFAULT 1 COMMENT '1固定分 2比例',
  `pass_score` decimal(8,2) NOT NULL DEFAULT 0,
  `pass_ratio` decimal(5,2) DEFAULT NULL,
  `reward_type` tinyint NOT NULL DEFAULT 0 COMMENT '0无 1归档后 2通过后',
  `reward_credit` decimal(8,2) NOT NULL DEFAULT 0,
  `attempt_limit` int NOT NULL DEFAULT 1,
  `late_limit_min` int NOT NULL DEFAULT 0,
  `screen_switch_limit` int NOT NULL DEFAULT 0,
  `notify_settings` mediumtext COMMENT '通知设置 JSON',
  `publish_settings` mediumtext COMMENT '发布设置 JSON',
  `advanced_settings` mediumtext COMMENT '更多设置 JSON',
  `total_score` decimal(8,2) NOT NULL DEFAULT 0,
  `participant_qty` int NOT NULL DEFAULT 0,
  `submitted_qty` int NOT NULL DEFAULT 0,
  `passed_qty` int NOT NULL DEFAULT 0,
  `pass_rate` decimal(7,4) NOT NULL DEFAULT 0,
  `analysis_enabled` tinyint NOT NULL DEFAULT 0,
  `analysis_time` datetime DEFAULT NULL,
  `owner_user_id` varchar(32) DEFAULT '' COMMENT '负责人',
  `owner_name` varchar(128) DEFAULT '',
  `owner_user_ids` varchar(512) DEFAULT '' COMMENT '负责人 IDs，逗号分隔（对齐原站 principalIds）',
  `owner_names` varchar(1000) DEFAULT '' COMMENT '负责人姓名，分号分隔（对齐原站 principalNames）',
  `create_user_id` varchar(32) DEFAULT '',
  `create_fullname` varchar(128) DEFAULT '',
  `create_user_name` varchar(64) DEFAULT '',
  `link_token` varchar(64) DEFAULT '' COMMENT '外部加入链接 token',
  `published_at` datetime DEFAULT NULL,
  `ended_at` datetime DEFAULT NULL,
  `deleted` tinyint NOT NULL DEFAULT 0,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `created_by` varchar(32) DEFAULT '',
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `updated_by` varchar(32) DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `idx_arrange_catalog` (`catalog_id`),
  KEY `idx_arrange_paper` (`paper_id`),
  KEY `idx_arrange_status` (`publish_status`,`run_status`),
  KEY `idx_arrange_owner` (`owner_user_id`),
  KEY `idx_arrange_entry` (`entry_start_at`,`entry_end_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='考试安排';

-- 4. 试卷快照
CREATE TABLE IF NOT EXISTS `exam_paper_snapshot` (
  `id` varchar(32) NOT NULL,
  `arrange_id` varchar(32) NOT NULL,
  `paper_id` varchar(32) NOT NULL,
  `version_no` int NOT NULL DEFAULT 1,
  `snapshot_json` longtext NOT NULL COMMENT '试卷结构、题目、分值、考核点快照 JSON',
  `created_by` varchar(32) DEFAULT '',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_arrange_paper_version` (`arrange_id`,`paper_id`,`version_no`),
  KEY `idx_snapshot_paper` (`paper_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='考试试卷快照';

-- 5. 考试考生安排
CREATE TABLE IF NOT EXISTS `exam_arrange_student` (
  `id` varchar(32) NOT NULL,
  `arrange_id` varchar(32) NOT NULL,
  `user_id` varchar(32) NOT NULL,
  `account` varchar(64) NOT NULL DEFAULT '',
  `fullname` varchar(128) NOT NULL DEFAULT '',
  `account_status` tinyint NOT NULL DEFAULT 1 COMMENT '1已启用 2已禁用 3已删除',
  `dept_id` varchar(32) DEFAULT '',
  `dept_name` varchar(500) DEFAULT '',
  `position_id` varchar(32) DEFAULT '',
  `position_name` varchar(200) DEFAULT '',
  `join_type` tinyint NOT NULL DEFAULT 1 COMMENT '1指派 2链接 3导入',
  `join_method` tinyint NOT NULL DEFAULT 1 COMMENT '原站 joinMethod',
  `user_status` tinyint NOT NULL DEFAULT 1 COMMENT '原站 userStatus',
  `udp_status` tinyint NOT NULL DEFAULT 1,
  `udp_deleted` tinyint NOT NULL DEFAULT 0,
  `exam_status` tinyint NOT NULL DEFAULT 0 COMMENT '0未开始 1考试中 2批阅中 3已完成 4重新考试',
  `user_arr_status` tinyint NOT NULL DEFAULT 0 COMMENT '原站 userArrStatus，与 exam_status 同步',
  `pass_status` tinyint NOT NULL DEFAULT -1 COMMENT '-1未知 0不通过 1通过',
  `first_join_at` datetime DEFAULT NULL,
  `start_at` datetime DEFAULT NULL,
  `submit_at` datetime DEFAULT NULL,
  `ip` varchar(64) DEFAULT '',
  `duration_sec` int NOT NULL DEFAULT 0,
  `ranking` int NOT NULL DEFAULT 0,
  `one_passed` tinyint NOT NULL DEFAULT 0 COMMENT '首次是否通过',
  `existed_resit` tinyint NOT NULL DEFAULT 0 COMMENT '是否已有补考',
  `device_type` tinyint NOT NULL DEFAULT 0,
  `attend_count` int NOT NULL DEFAULT 0,
  `screen_switch_count` int NOT NULL DEFAULT 0,
  `submit_type` tinyint DEFAULT NULL COMMENT '1主动 2自动 3管理员',
  `attempt_qty` int NOT NULL DEFAULT 0,
  `score` decimal(8,2) NOT NULL DEFAULT 0,
  `highest_score` decimal(8,2) NOT NULL DEFAULT 0,
  `highest_attempt_no` int NOT NULL DEFAULT 0,
  `current_attempt_id` varchar(32) DEFAULT NULL,
  `best_ue_id` varchar(32) DEFAULT NULL COMMENT '原站 bestUeId',
  `best_ue_index` int DEFAULT NULL COMMENT '原站 bestUeIndex',
  `resit_score` decimal(8,2) DEFAULT NULL,
  `resit_passed` tinyint DEFAULT NULL,
  `retake_used` tinyint NOT NULL DEFAULT 0,
  `last_retake_at` datetime DEFAULT NULL,
  `analyze_visible` tinyint NOT NULL DEFAULT 0,
  `deleted` tinyint NOT NULL DEFAULT 0,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_arrange_user_deleted` (`arrange_id`,`user_id`,`deleted`),
  KEY `idx_student_arrange_status` (`arrange_id`,`exam_status`,`deleted`),
  KEY `idx_student_user` (`user_id`),
  KEY `idx_student_dept` (`dept_id`),
  KEY `idx_student_position` (`position_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='考试考生安排';

-- 6. 考试尝试记录（id 即前端 ueId）
CREATE TABLE IF NOT EXISTS `exam_attempt` (
  `id` varchar(32) NOT NULL,
  `arrange_id` varchar(32) NOT NULL,
  `student_id` varchar(32) NOT NULL,
  `user_id` varchar(32) NOT NULL,
  `paper_id` varchar(32) NOT NULL,
  `snapshot_id` varchar(32) NOT NULL,
  `attempt_no` int NOT NULL DEFAULT 1,
  `status` tinyint NOT NULL DEFAULT 0 COMMENT '0未开始 1考试中 2批阅中 3已完成 4已作废',
  `score` decimal(8,2) NOT NULL DEFAULT 0,
  `pass_status` tinyint NOT NULL DEFAULT -1,
  `start_at` datetime DEFAULT NULL,
  `submit_at` datetime DEFAULT NULL,
  `submit_type` tinyint DEFAULT NULL,
  `ip` varchar(64) DEFAULT '',
  `duration_sec` int NOT NULL DEFAULT 0,
  `screen_switch_count` int NOT NULL DEFAULT 0,
  `grader_names` varchar(500) DEFAULT '',
  `graded_at` datetime DEFAULT NULL,
  `rank_no` int DEFAULT NULL,
  `analysis_version` int NOT NULL DEFAULT 0,
  `deleted` tinyint NOT NULL DEFAULT 0,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_student_attempt_no` (`arrange_id`,`student_id`,`attempt_no`),
  KEY `idx_attempt_arrange_status` (`arrange_id`,`status`,`deleted`),
  KEY `idx_attempt_student` (`student_id`),
  KEY `idx_attempt_snapshot` (`snapshot_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='考试作答记录';

-- 7. 逐题作答明细
CREATE TABLE IF NOT EXISTS `exam_attempt_answer` (
  `id` varchar(32) NOT NULL,
  `attempt_id` varchar(32) NOT NULL,
  `ques_id` varchar(32) NOT NULL,
  `section_index` tinyint NOT NULL DEFAULT 0,
  `order_index` int NOT NULL DEFAULT 0,
  `answer_json` mediumtext COMMENT '考生答案 JSON',
  `correct_flag` tinyint NOT NULL DEFAULT 0 COMMENT '0错误 1正确 2部分正确 3待批阅',
  `score` decimal(8,2) NOT NULL DEFAULT 0,
  `max_score` decimal(8,2) NOT NULL DEFAULT 0,
  `answer_time` datetime DEFAULT NULL,
  `grade_mode` tinyint NOT NULL DEFAULT 0 COMMENT '0未批阅 1自动 2人工 3AI',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_attempt_ques` (`attempt_id`,`ques_id`),
  KEY `idx_answer_ques` (`ques_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='逐题作答明细';

-- 8. 题目级统计
CREATE TABLE IF NOT EXISTS `exam_question_analysis_stat` (
  `id` varchar(32) NOT NULL,
  `arrange_id` varchar(32) NOT NULL,
  `ques_id` varchar(32) NOT NULL,
  `type` tinyint NOT NULL DEFAULT 0,
  `level_type` tinyint NOT NULL DEFAULT 0,
  `point_id` varchar(32) NOT NULL DEFAULT '',
  `point_name` varchar(200) DEFAULT '',
  `answer_qty` int NOT NULL DEFAULT 0,
  `correct_qty` int NOT NULL DEFAULT 0,
  `correct_rate` decimal(7,4) DEFAULT NULL,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_arrange_ques_point` (`arrange_id`,`ques_id`,`point_id`),
  KEY `idx_question_stat_arrange` (`arrange_id`,`type`,`level_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='考试题目级统计';

-- 9. 考试分值统计
CREATE TABLE IF NOT EXISTS `exam_arrange_score_stat` (
  `arrange_id` varchar(32) NOT NULL,
  `participant_qty` int NOT NULL DEFAULT 0,
  `absent_qty` int NOT NULL DEFAULT 0,
  `participant_times` int NOT NULL DEFAULT 0,
  `pass_qty` int NOT NULL DEFAULT 0,
  `first_pass_qty` int NOT NULL DEFAULT 0,
  `excellent_qty` int NOT NULL DEFAULT 0,
  `highest_score` decimal(8,2) NOT NULL DEFAULT 0,
  `lowest_score` decimal(8,2) NOT NULL DEFAULT 0,
  `average_score` decimal(8,2) NOT NULL DEFAULT 0,
  `average_duration_sec` int NOT NULL DEFAULT 0,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`arrange_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='考试统计聚合';

-- 10. 考前签名记录
CREATE TABLE IF NOT EXISTS `exam_arrange_signature` (
  `id` varchar(32) NOT NULL,
  `arrange_id` varchar(32) NOT NULL,
  `student_id` varchar(32) NOT NULL,
  `user_id` varchar(32) NOT NULL,
  `attempt_id` varchar(32) DEFAULT NULL,
  `signature_url` varchar(500) NOT NULL,
  `signed_at` datetime NOT NULL,
  `source` tinyint NOT NULL DEFAULT 1 COMMENT '1考前签名 2补签',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_signature_arrange_user` (`arrange_id`,`user_id`),
  KEY `idx_signature_attempt` (`attempt_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='考试签名记录';

-- 11. 变更通知
CREATE TABLE IF NOT EXISTS `exam_change_notice` (
  `id` varchar(32) NOT NULL,
  `arrange_id` varchar(32) NOT NULL,
  `title` varchar(200) NOT NULL,
  `content` text NOT NULL,
  `changed_fields` varchar(1000) DEFAULT '' COMMENT '变更字段 JSON',
  `status` tinyint NOT NULL DEFAULT 0 COMMENT '0草稿 1已发送 2发送失败',
  `recipient_qty` int NOT NULL DEFAULT 0,
  `created_by` varchar(32) DEFAULT '',
  `created_by_name` varchar(128) DEFAULT '',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `sent_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_notice_arrange` (`arrange_id`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='考试变更通知';

-- 12. 通用通知事件 Outbox（考试模块只负责可靠投递，不拥有学员已读表）
CREATE TABLE IF NOT EXISTS `exam_notice_outbox` (
  `id` varchar(32) NOT NULL,
  `arrange_id` varchar(32) NOT NULL,
  `notice_id` varchar(32) NOT NULL,
  `event_code` varchar(64) NOT NULL DEFAULT 'ARRANGE_CHANGE',
  `dedup_key` varchar(128) NOT NULL,
  `payload_json` text NOT NULL,
  `status` tinyint NOT NULL DEFAULT 0 COMMENT '0待发送 1成功 2失败',
  `retry_count` int NOT NULL DEFAULT 0,
  `next_retry_at` datetime DEFAULT NULL,
  `published_at` datetime DEFAULT NULL,
  `error_message` varchar(1000) DEFAULT '',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_notice_dedup` (`dedup_key`),
  KEY `idx_outbox_status` (`status`,`next_retry_at`),
  KEY `idx_outbox_arrange` (`arrange_id`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='考试通知事件Outbox';

-- 13. 用户考试偏好设置
CREATE TABLE IF NOT EXISTS `exam_user_setting` (
  `id` varchar(32) NOT NULL,
  `user_id` varchar(32) NOT NULL,
  `biz_type` varchar(64) NOT NULL COMMENT '如 arrange_student_columns',
  `setting_json` mediumtext NOT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_user_biz` (`user_id`,`biz_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='考试用户偏好设置';

-- 14. 操作日志
CREATE TABLE IF NOT EXISTS `exam_arrange_operation_log` (
  `id` varchar(32) NOT NULL,
  `arrange_id` varchar(32) NOT NULL,
  `action` varchar(64) NOT NULL COMMENT 'publish/end/add_student/retake/analyze/export/notice',
  `target_type` varchar(32) DEFAULT '',
  `target_id` varchar(64) DEFAULT '',
  `detail_json` mediumtext,
  `operator_id` varchar(32) DEFAULT '',
  `operator_name` varchar(128) DEFAULT '',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_op_arrange` (`arrange_id`,`created_at`),
  KEY `idx_op_action` (`action`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='考试操作日志';

-- 15. 导出任务
CREATE TABLE IF NOT EXISTS `exam_export_task` (
  `id` varchar(32) NOT NULL,
  `arrange_id` varchar(32) DEFAULT NULL,
  `export_type` varchar(64) NOT NULL COMMENT 'ARRANGE_LIST/STUDENT_HIGHEST/STUDENT_ALL/STUDENT_ANSWER/QUESTION_STAT/SIGNATURE',
  `status` tinyint NOT NULL DEFAULT 0 COMMENT '0处理中 1成功 2失败',
  `file_url` varchar(1000) DEFAULT '',
  `error_message` varchar(1000) DEFAULT '',
  `created_by` varchar(32) DEFAULT '',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `finished_at` datetime DEFAULT NULL,
  `expires_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_export_task_user` (`created_by`,`created_at`),
  KEY `idx_export_task_arrange` (`arrange_id`,`export_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='考试导出任务';

-- ============ 试卷引用表增量 ============
-- 说明：试卷管理 08 已有 exam_paper_use，考试模块上线后补 ref_id/ref_type。
SET @col_ref_id := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'exam_paper_use' AND COLUMN_NAME = 'ref_id'
);
SET @ddl_ref_id := IF(@col_ref_id = 0,
  'ALTER TABLE `exam_paper_use` ADD COLUMN `ref_id` varchar(32) DEFAULT '''' COMMENT ''引用方 ID（考试 ID）'' AFTER `paper_id`',
  'SELECT 1'
);
PREPARE stmt_ref_id FROM @ddl_ref_id;
EXECUTE stmt_ref_id;
DEALLOCATE PREPARE stmt_ref_id;

SET @col_ref_type := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'exam_paper_use' AND COLUMN_NAME = 'ref_type'
);
SET @ddl_ref_type := IF(@col_ref_type = 0,
  'ALTER TABLE `exam_paper_use` ADD COLUMN `ref_type` tinyint NOT NULL DEFAULT 1 COMMENT ''1考试 2课程安排'' AFTER `ref_id`',
  'SELECT 1'
);
PREPARE stmt_ref_type FROM @ddl_ref_type;
EXECUTE stmt_ref_type;
DEALLOCATE PREPARE stmt_ref_type;

SET @idx_ref := (
  SELECT COUNT(*) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'exam_paper_use' AND INDEX_NAME = 'idx_ref'
);
SET @ddl_idx_ref := IF(@idx_ref = 0,
  'ALTER TABLE `exam_paper_use` ADD INDEX `idx_ref` (`ref_type`,`ref_id`)',
  'SELECT 1'
);
PREPARE stmt_idx_ref FROM @ddl_idx_ref;
EXECUTE stmt_idx_ref;
DEALLOCATE PREPARE stmt_idx_ref;

-- ============ 种子数据 ============
INSERT INTO `exam_arrange_catalog` (`id`,`parent_id`,`name`,`order_index`,`routing_path`)
SELECT 'root','root','默认考试分类',0,'' FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM `exam_arrange_catalog` WHERE `id`='root');

-- ============ 对账脚本 ============
-- 1. 考试考生数重算
-- UPDATE exam_arrange a SET participant_qty = (
--   SELECT COUNT(*) FROM exam_arrange_student s WHERE s.arrange_id=a.id AND s.deleted=0
-- );

-- 2. 已交卷/已通过重算
-- UPDATE exam_arrange a SET
--   submitted_qty = (SELECT COUNT(*) FROM exam_arrange_student s WHERE s.arrange_id=a.id AND s.deleted=0 AND s.exam_status=3),
--   passed_qty = (SELECT COUNT(*) FROM exam_arrange_student s WHERE s.arrange_id=a.id AND s.deleted=0 AND s.pass_status=1),
--   pass_rate = CASE WHEN participant_qty=0 THEN 0 ELSE passed_qty / participant_qty END;

-- 3. 试卷引用次数重算
-- UPDATE exam_paper p SET used_qty = (
--   SELECT COUNT(*) FROM exam_paper_use u WHERE u.paper_id=p.id AND u.ref_type=1
-- );


---

## 附录 B2. 契约漏记的表（2026-11-10 核查发现）

> 以下表在**实际数据库中已存在且被代码使用**，但本契约 `07` 正文未收录。
> 属历史遗漏，非本次变更引入；此处补记以免后续按契约建库时缺表。

| 表 | 用途 | 佐证 |
|---|---|---|
| `exam_question_point` | 试题 ↔ 考核点多对多关联；一个题挂多个考核点时按参与统计的考核点分别计入 | `03` §判分维度引用；实际库中存在 |

## 附录 C. 学员端考试与批阅 · 表结构变更（2026-11-10）

> 全部为**增量变更**，不改动既有列语义，可重复执行。
> 变更理由见 `03-技术实现方案-后端.md` §10B 与 `学员端考试-补充待讨论点.md`。

### C1. `exam_attempt` 新增 3 列

| 列 | 类型 | 用途 |
|---|---|---|
| `config_snapshot` | mediumtext | 开考时的配置快照（时长/通过分/作答样式/交卷限制）。<br>**进行中的答卷沿用快照**，避免管理员中途改配置导致「时间突然变短」 |
| `identity_status` | tinyint | 人脸核验结果：0 未核验 / 1 通过 / 2 不通过 / 3 无法核验 |
| `identity_evidence` | varchar(512) | 核验抓拍图 URL，复用 `/exam/files/**` |

### C2. `exam_attempt_answer` 新增 1 列

| 列 | 类型 | 用途 |
|---|---|---|
| `marked` | tinyint | 学员标记（不确定的题），答题卡可快速定位 |

### C3. `exam_attempt_answer` 唯一键

逐题保存需要 upsert，必须保证 `(attempt_id, ques_id)` 唯一：

```sql
ALTER TABLE `exam_attempt_answer`
  ADD UNIQUE KEY `uk_attempt_ques` (`attempt_id`, `ques_id`);
```

> 组合题子题各自一行，`ques_id` 为子题 id，天然不冲突。

### C3b. 人脸核验手段与相似度（2026-11-13 新增，DER-34）

```sql
ALTER TABLE `exam_attempt`
  ADD COLUMN `identity_method` tinyint NULL COMMENT '1仅活体 2活体+基准照比对',
  ADD COLUMN `identity_score` decimal(6,4) NULL COMMENT '比对相似度 0..1，未比对为 NULL';
```

**为什么只加两列而不是新建表**：这两个值是「某一次答卷的核验属性」，与已有的
`identity_status`/`identity_evidence` 同一层级；新建表会让「一次核验」拆到两处，
批阅页取证据时要多一次查询。

**为什么存原始相似度而不是只存「过/不过」**：阈值将来必然要按真实样本重标，
保留原始值才能在不重采样本的前提下重新判定。

**为什么 `identity_method` 可空**：历史数据（本列上线前）本来就是「不知道做了什么核验」，
填 0 或 1 都是编造。查询时按「NULL = 仅活体（旧数据）」理解即可。

### C4. 人脸基准照表（新增；2026-11-12 启用，DER-33）

> 建表语句一直在，但此前从未被使用（表内 0 行）。
> 2026-11-12 起用作学员**自愿录入**的基准照，供后续 1:1 比对。
> **能力边界（DEF-01）**：照片由学员自己拍，首次就可以是别人，
> 只能检测「这次与上次不是同一人」，**不是身份认证**。

```sql
CREATE TABLE IF NOT EXISTS `exam_face_baseline` (
  `id` varchar(32) NOT NULL,
  `user_id` varchar(32) NOT NULL,
  `image_url` varchar(512) NOT NULL COMMENT '基准照 URL（/api/exam/files/**，必须带 /api 前缀）',
  `source` tinyint NOT NULL DEFAULT 1 COMMENT '1学员自建 2管理员预录',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='学员人脸基准照（DEF-01：防不住首次替考）';
```

**为什么 `uk_user` 唯一**：比对时永远只能有唯一基准，不用纠结「该跟哪张比」。
重录直接覆盖（`FaceBaselineServiceImpl.save` 走 updateById）。

### C5. 迁移脚本（可重复执行）

```sql
SET @db := DATABASE();

-- exam_attempt.config_snapshot
SET @sql := (SELECT IF((SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema=@db AND table_name='exam_attempt' AND column_name='config_snapshot')=0,
  'ALTER TABLE `exam_attempt` ADD COLUMN `config_snapshot` mediumtext COMMENT ''开考时配置快照'' AFTER `analysis_version`',
  'SELECT ''exam_attempt.config_snapshot exists'''));
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- exam_attempt.identity_status
SET @sql := (SELECT IF((SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema=@db AND table_name='exam_attempt' AND column_name='identity_status')=0,
  'ALTER TABLE `exam_attempt` ADD COLUMN `identity_status` tinyint NOT NULL DEFAULT 0 COMMENT ''0未核验 1通过 2不通过 3无法核验'' AFTER `config_snapshot`',
  'SELECT ''exam_attempt.identity_status exists'''));
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- exam_attempt.identity_evidence
SET @sql := (SELECT IF((SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema=@db AND table_name='exam_attempt' AND column_name='identity_evidence')=0,
  'ALTER TABLE `exam_attempt` ADD COLUMN `identity_evidence` varchar(512) DEFAULT NULL COMMENT ''核验抓拍图 URL'' AFTER `identity_status`',
  'SELECT ''exam_attempt.identity_evidence exists'''));
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- exam_attempt_answer.marked
SET @sql := (SELECT IF((SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema=@db AND table_name='exam_attempt_answer' AND column_name='marked')=0,
  'ALTER TABLE `exam_attempt_answer` ADD COLUMN `marked` tinyint NOT NULL DEFAULT 0 COMMENT ''学员标记'' AFTER `grade_mode`',
  'SELECT ''exam_attempt_answer.marked exists'''));
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- exam_attempt_answer 唯一键
SET @sql := (SELECT IF((SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema=@db AND table_name='exam_attempt_answer' AND index_name='uk_attempt_ques')=0,
  'ALTER TABLE `exam_attempt_answer` ADD UNIQUE KEY `uk_attempt_ques` (`attempt_id`,`ques_id`)',
  'SELECT ''uk_attempt_ques exists'''));
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;
```

> 执行前先确认 `exam_attempt_answer` 无重复 `(attempt_id, ques_id)`，否则加唯一键会失败：
> ```sql
> SELECT attempt_id, ques_id, COUNT(*) c FROM exam_attempt_answer
> GROUP BY attempt_id, ques_id HAVING c > 1;
> ```

---

## 附录 D. 批阅评语列（v1.6，2026-11-11 新增 / DER-21）

> **必须在部署代码之前执行。** 实体已加 `overallComment` / `gradeComment`，
> MyBatis-Plus 的 `selectById` 会拼出全部列，列缺失会让 `exam_attempt` 与
> `exam_attempt_answer` 的**所有**读写报 `Unknown column`——连学员交卷、结果页一起挂，
> 不只是批阅接口。已在 `sql/README.md` 写明部署顺序。

| 表 | 新增列 | 类型 | 用途 |
|---|---|---|---|
| `exam_attempt` | `overall_comment` | varchar(1000) | 整卷批阅总评 |
| `exam_attempt_answer` | `grade_comment` | varchar(500) | 单题批阅评语 |

```sql
SET @db := DATABASE();

SET @sql := (SELECT IF((SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema=@db AND table_name='exam_attempt' AND column_name='overall_comment')=0,
  'ALTER TABLE `exam_attempt` ADD COLUMN `overall_comment` varchar(1000) DEFAULT NULL COMMENT ''整卷批阅总评'' AFTER `grader_names`',
  'SELECT ''exam_attempt.overall_comment exists'''));
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

SET @sql := (SELECT IF((SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema=@db AND table_name='exam_attempt_answer' AND column_name='grade_comment')=0,
  'ALTER TABLE `exam_attempt_answer` ADD COLUMN `grade_comment` varchar(500) DEFAULT NULL COMMENT ''单题批阅评语'' AFTER `score`',
  'SELECT ''exam_attempt_answer.grade_comment exists'''));
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;
```

**为什么评语要独立列而不是塞进 `exam_arrange_operation_log.detail_json`**：
「重新批阅」要回显上一次的评语，而日志写入路径用 try/catch 吞异常——
落库失败评语会静默消失。批阅评语是学员要看到的业务数据，不能挂在「可以不成功」的链路上。
