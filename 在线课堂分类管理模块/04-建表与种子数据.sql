-- ============================================================
-- 在线课堂（管理端）建表与种子数据
-- 模块：分类管理 + 课程设置 ｜ 版本 v1.0 ｜ 2026-09-29
-- 数据库：final_dream（10.100.26.200）
-- 配套：01-需求文档.md、02-技术实现方案.md、03-接口文档.md
-- 说明：全库约定 id 为雪花 ID 字符串（应用生成）；执行前先确认
--       kng_* 表不存在（幂等写法见每段 IF NOT EXISTS）
-- ============================================================

-- 1. 分类表
CREATE TABLE IF NOT EXISTS `kng_catalog` (
  `id`                  VARCHAR(32)  NOT NULL                COMMENT '雪花ID(字符串)',
  `parent_id`           VARCHAR(32)  NULL                    COMMENT '父分类id；NULL=一级分类(挂虚拟根"主课堂")',
  `name`                VARCHAR(50)  NOT NULL                COMMENT '分类名称',
  `level`               INT          NOT NULL                COMMENT '层级，一级=1，最大10',
  `order_index`         INT          NOT NULL DEFAULT 0      COMMENT '同级排序，新增=同级max+1',
  `order_type`          TINYINT      NOT NULL DEFAULT 1      COMMENT '默认课程顺序：1发布时间 2更新时间 3名称 4学习人数',
  `prefix_enabled`      TINYINT      NOT NULL DEFAULT 0      COMMENT '标题自动加前缀开关 0/1',
  `prefix_content`      VARCHAR(50)  NULL                    COMMENT '前缀内容',
  `date_suffix_enabled` TINYINT      NOT NULL DEFAULT 0      COMMENT '标题自动加日期开关 0/1',
  `date_suffix_format`  VARCHAR(20)  NULL                    COMMENT '日期格式：yyyy-MM-dd / yyyy/MM/dd / yyyyMMdd',
  `inherit_parent`      TINYINT      NOT NULL DEFAULT 0      COMMENT '继承父分类权限标志(快照锁定) 0/1',
  `kng_count`           INT          NOT NULL DEFAULT 0      COMMENT '本级课件数(预留恒0，未来课件模块维护)',
  `course_count`        INT          NOT NULL DEFAULT 0      COMMENT '本级课程数(预留恒0，未来课程模块维护)',
  `created_by`          VARCHAR(32)  NULL                    COMMENT '创建人 sys_user.id',
  `created_at`          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_parent` (`parent_id`),
  KEY `idx_level` (`level`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='在线课堂-课程分类(树)';

-- 2. 分类权限表
CREATE TABLE IF NOT EXISTS `kng_catalog_permission` (
  `id`           VARCHAR(32)  NOT NULL                       COMMENT '雪花ID(字符串)',
  `catalog_id`   VARCHAR(32)  NOT NULL                       COMMENT '分类id',
  `subject_type` TINYINT      NOT NULL                       COMMENT '1超管&分类创建者(内置) 2课堂管理员(内置) 3课堂成员(内置) 4部门 5岗位 6角色',
  `subject_id`   VARCHAR(64)  NULL                           COMMENT '内置行NULL；部门=sys_department.id；岗位=岗位名称字符串；角色=sys_role.id',
  `subject_name` VARCHAR(100) NOT NULL                       COMMENT '展示名快照(部门名/岗位名/角色名/内置行名)',
  `permissions`  VARCHAR(32)  NOT NULL                       COMMENT '权限码CSV：1浏览 2允许下载课件 3分发 4维护 5App缓存课件，如"1,2,5"',
  `created_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_catalog` (`catalog_id`),
  KEY `idx_subject` (`subject_type`, `subject_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='在线课堂-分类权限';

-- 3. 课程设置表（单行）
CREATE TABLE IF NOT EXISTS `kng_setting` (
  `id`                    TINYINT      NOT NULL DEFAULT 1    COMMENT '恒为1',
  `credit_mode`           TINYINT      NOT NULL DEFAULT 1     COMMENT '1=学完课程时发放所有课件的学分(预留扩展)',
  `anti_idle_enabled`     TINYINT      NOT NULL DEFAULT 0     COMMENT '防挂机开关 0/1',
  `anti_idle_mode`        TINYINT      NOT NULL DEFAULT 1     COMMENT '1模式一 2模式二',
  `check_interval_minutes` INT         NOT NULL DEFAULT 3     COMMENT '确认在线间隔(分钟) 1~60',
  `confirm_seconds`       INT          NOT NULL DEFAULT 120   COMMENT '模式二确认时限(秒) 30~600',
  `prompt_text`           VARCHAR(250) NOT NULL DEFAULT '已触发防挂机验证，请点击"继续学习"，否则学习将被停止' COMMENT '防挂机提示语',
  `updated_by`            VARCHAR(32)  NULL,
  `updated_at`            DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='在线课堂-课程设置(单行)';

-- 初始化设置行
INSERT INTO `kng_setting` (`id`) SELECT 1 FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM `kng_setting` WHERE `id` = 1);

-- 4. 权限点增量（sys_permission，组织架构模块所有）
--    真实结构为 id BIGINT 自增、parent_id BIGINT、sort，无 created_at。
--    DataInitializer 同步补齐“kng”分组 + 四个子权限；本脚本作为兼容兜底插入四个根节点。
INSERT INTO `sys_permission` (`code`, `name`, `parent_id`, `route_path`, `sort`)
SELECT 'kng:courseware', '课件管理', 0, '/kng/courseware', 41
WHERE NOT EXISTS (SELECT 1 FROM `sys_permission` WHERE `code` = 'kng:courseware');
INSERT INTO `sys_permission` (`code`, `name`, `parent_id`, `route_path`, `sort`)
SELECT 'kng:course', '课程管理', 0, '/kng/course', 42
WHERE NOT EXISTS (SELECT 1 FROM `sys_permission` WHERE `code` = 'kng:course');
INSERT INTO `sys_permission` (`code`, `name`, `parent_id`, `route_path`, `sort`)
SELECT 'kng:catalog', '分类管理', 0, '/kng/catalog', 43
WHERE NOT EXISTS (SELECT 1 FROM `sys_permission` WHERE `code` = 'kng:catalog');
INSERT INTO `sys_permission` (`code`, `name`, `parent_id`, `route_path`, `sort`)
SELECT 'kng:setting', '课程设置', 0, '/kng/setting', 44
WHERE NOT EXISTS (SELECT 1 FROM `sys_permission` WHERE `code` = 'kng:setting');

-- 5. 示例种子分类（可选：用于联调；上线环境可删除本段）
--    结构：营销话术(含2个子分类) + 服务话术(叶子)
-- INSERT INTO kng_catalog (id, parent_id, name, level, order_index, order_type, created_by) VALUES
--   ('9000000000000000001', NULL,               '营销话术',        1, 0, 1, 'admin_user_id'),
--   ('9000000000000000002', NULL,               '服务话术',        1, 1, 1, 'admin_user_id'),
--   ('9000000000000000003', '9000000000000000001', 'LTC流程方法论', 2, 0, 1, 'admin_user_id'),
--   ('9000000000000000004', '9000000000000000001', '营销实战案例',  2, 1, 1, 'admin_user_id');

-- 6. 内置权限默认模板说明（应用层实现，无需 SQL）：
--    新建分类时固定插入三行 kng_catalog_permission：
--      (subject_type=1, subject_id=NULL, subject_name='超级管理员&分类创建者', permissions='1,2,3,4,5')
--      (subject_type=2, subject_id=NULL, subject_name='课堂管理员',            permissions='1,2,3,4,5')
--      (subject_type=3, subject_id=NULL, subject_name='课堂成员',              permissions='1,2,5')

-- ============================================================
-- 验证脚本（执行后核对）
-- SELECT COUNT(*) FROM kng_catalog;                 -- 预期 0（或种子数）
-- SELECT COUNT(*) FROM kng_catalog_permission;      -- 预期 0
-- SELECT * FROM kng_setting;                        -- 预期 1 行默认值
-- SELECT code, name, route_path FROM sys_permission WHERE code LIKE 'kng:%';  -- 预期 4 行
-- ============================================================
