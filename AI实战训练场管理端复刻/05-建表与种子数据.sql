-- =====================================================================
-- AI实战训练场（管理端）建表与种子数据
-- 库：final_dream（10.100.26.200:3306）
-- 版本：v1.0  日期：2026-09-16
-- 说明：4 张表 + 演示主题种子数据（照线上"柔性智造销售话术训练"：
--       5 个场景单元、完整评估标准、v1/v2 两个版本、v2 为当前版本）
-- 执行方式：本机无 mysql CLI，可用 ~/.m2 的 mysql-connector-j jar + 临时
--       Java 类执行（JDBC + 幂等判断），或在 IDE 数据库面板直接执行
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. 主题表 act_theme
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS act_theme (
  id                      VARCHAR(32)  NOT NULL COMMENT 'snowflake id (string)',
  theme_name              VARCHAR(50)  NOT NULL COMMENT 'redundant from current version, for list query',
  theme_desc              VARCHAR(100)          DEFAULT NULL,
  status                  TINYINT      NOT NULL DEFAULT 0 COMMENT '0 draft 1 publishing 2 publish-failed 3 published 4 paused 5 finished',
  theme_mode              TINYINT               DEFAULT 1 COMMENT '1 daily-training 2 pass-assessment 3 both (derived from version drill modes)',
  assign_mode             TINYINT               DEFAULT 1 COMMENT '1 assigned 2 all-students (derived from join mode)',
  difficulty              TINYINT               DEFAULT 2 COMMENT '1 easy 2 normal 3 hard (redundant from current version)',
  jurisdiction_type       TINYINT               DEFAULT NULL COMMENT 'PLACEHOLDER: 1 managed-by-me 2 owned-by-me (frontend not sending yet)',
  source_type             TINYINT               DEFAULT 1 COMMENT 'PLACEHOLDER: 1 standalone 2 project-arranged (frontend not sending yet)',
  current_version_no      INT          NOT NULL DEFAULT 1,
  pass_rate               DECIMAL(5,2)          DEFAULT 0 COMMENT 'PLACEHOLDER stat',
  pass_user_count         INT                   DEFAULT 0 COMMENT 'PLACEHOLDER stat',
  participant_count       INT                   DEFAULT 0 COMMENT 'PLACEHOLDER stat',
  avg_score               DECIMAL(5,2)          DEFAULT 0 COMMENT 'PLACEHOLDER stat',
  total_training_count    INT                   DEFAULT 0 COMMENT 'PLACEHOLDER stat',
  customer_profile_count  INT                   DEFAULT 0 COMMENT 'PLACEHOLDER: customer profile count shown in content overview',
  created_at              DATETIME              DEFAULT NULL,
  updated_at              DATETIME              DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_act_theme_status (status),
  KEY idx_act_theme_mode (theme_mode)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='AI combat training theme';

-- ---------------------------------------------------------------------
-- 2. 主题版本表 act_theme_version（每版本一条记录，五表单全部可编辑字段）
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS act_theme_version (
  id                       VARCHAR(32)  NOT NULL,
  theme_id                 VARCHAR(32)  NOT NULL,
  version_no               INT          NOT NULL,
  -- basic info
  theme_name               VARCHAR(50)  NOT NULL,
  theme_desc               VARCHAR(100)          DEFAULT NULL,
  owner_user_id            VARCHAR(32)           DEFAULT 'admin' COMMENT 'PLACEHOLDER owner, always admin for now',
  plan_start_time          DATETIME              DEFAULT NULL,
  plan_end_time            DATETIME              DEFAULT NULL,
  -- access control
  total_drill_count        INT          NOT NULL DEFAULT 1,
  per_scene_limit          INT                   DEFAULT NULL COMMENT 'NULL = unlimited',
  join_mode                TINYINT      NOT NULL DEFAULT 1 COMMENT '1 assigned-only 2 assigned+public',
  guest_access_enabled     TINYINT               DEFAULT 0 COMMENT 'PLACEHOLDER, display only',
  -- training strategy
  ai_response_mode         TINYINT               DEFAULT 1 COMMENT '1 expert 2 fast',
  training_mode_enabled    TINYINT               DEFAULT 1,
  assessment_mode_enabled  TINYINT               DEFAULT 0,
  coach_review_enabled     TINYINT               DEFAULT 1 COMMENT 'forced 1 when training mode on',
  suggestion_enabled       TINYINT               DEFAULT 0,
  practice_methods         VARCHAR(64)           DEFAULT 'case,custom,random' COMMENT 'csv of case/custom/random',
  difficulty               TINYINT               DEFAULT 2,
  allow_custom_difficulty  TINYINT               DEFAULT 1,
  -- anti-cheat (PLACEHOLDER, display only)
  face_check_enabled       TINYINT               DEFAULT 0,
  face_check_stage         VARCHAR(32)           DEFAULT NULL COMMENT 'before/ongoing',
  screen_switch_mode       VARCHAR(16)           DEFAULT 'forbid' COMMENT 'forbid/allow',
  screen_switch_limit      INT                   DEFAULT 0,
  -- pass standard
  scene_pass_type          TINYINT               DEFAULT 1 COMMENT '1 cumulative 2 consecutive',
  scene_pass_count         INT                   DEFAULT 1,
  -- version meta
  creator                  VARCHAR(64)           DEFAULT '管理员',
  used_user_count          INT                   DEFAULT 0 COMMENT 'PLACEHOLDER stat',
  completed_count          INT                   DEFAULT 0 COMMENT 'PLACEHOLDER stat',
  in_progress_count        INT                   DEFAULT 0 COMMENT 'PLACEHOLDER stat',
  created_at               DATETIME              DEFAULT NULL,
  updated_at               DATETIME              DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_act_theme_version (theme_id, version_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='AI combat training theme version snapshot';

-- ---------------------------------------------------------------------
-- 3. 场景单元表 act_scenario_unit（按 theme_id+version_no 隔离，保存版本时整表复制）
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS act_scenario_unit (
  id                    VARCHAR(32)  NOT NULL,
  theme_id              VARCHAR(32)  NOT NULL,
  version_no            INT          NOT NULL,
  sort_order            INT          NOT NULL DEFAULT 1,
  unit_name             VARCHAR(100) NOT NULL,
  audience              VARCHAR(50)           DEFAULT NULL COMMENT 'target audience tag',
  time_limit_minutes    INT                   DEFAULT NULL,
  business_goal         TEXT,
  iceberg_elements      JSON COMMENT 'string array',
  business_impact       TEXT,
  failure_cost          TEXT,
  core_conflict         TEXT,
  common_failure_modes  JSON COMMENT 'string array',
  difficulties          JSON COMMENT 'string array',
  forbidden_behaviors   JSON COMMENT 'string array',
  pass_score            INT                   DEFAULT 70 COMMENT 'pass score of evaluation standard',
  created_at            DATETIME              DEFAULT NULL,
  updated_at            DATETIME              DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_act_unit_theme_version (theme_id, version_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='AI combat training scenario unit';

-- ---------------------------------------------------------------------
-- 4. 评估维度表 act_evaluation_dimension（挂场景单元，各单元维度可不同）
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS act_evaluation_dimension (
  id                 VARCHAR(32)   NOT NULL,
  scenario_unit_id   VARCHAR(32)   NOT NULL,
  dimension_name     VARCHAR(50)   NOT NULL,
  weight             DECIMAL(5,2)  NOT NULL DEFAULT 0 COMMENT 'weight percent, e.g. 25.00',
  dimension_desc     VARCHAR(500)           DEFAULT NULL,
  excellent_standard VARCHAR(1000)          DEFAULT NULL COMMENT 'excellent 90-100',
  good_standard      VARCHAR(1000)          DEFAULT NULL COMMENT 'good 70-89',
  improve_standard   VARCHAR(1000)          DEFAULT NULL COMMENT 'needs-improvement <70',
  sort_order         INT                   DEFAULT 1,
  PRIMARY KEY (id),
  KEY idx_act_dim_unit (scenario_unit_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='AI combat training evaluation dimension';

-- =====================================================================
-- 种子数据（演示主题：柔性智造销售话术训练，v1/v2 两版本，v2 为当前）
-- 注意：若已存在演示数据则先清理再插入（重复执行安全）
-- =====================================================================

DELETE FROM act_evaluation_dimension WHERE scenario_unit_id LIKE 'seed-unit-%';
DELETE FROM act_scenario_unit        WHERE id LIKE 'seed-unit-%';
DELETE FROM act_theme_version        WHERE id LIKE 'seed-ver-%';
DELETE FROM act_theme                WHERE id LIKE 'seed-theme-%';

-- ---- 主题 ----
INSERT INTO act_theme (id, theme_name, theme_desc, status, theme_mode, assign_mode, difficulty,
  jurisdiction_type, source_type, current_version_no,
  pass_rate, pass_user_count, participant_count, avg_score, total_training_count,
  customer_profile_count, created_at, updated_at)
VALUES ('seed-theme-001', '柔性智造销售话术训练',
  '基于六大场景知识库，训练销售精准讲解方案价值并应对客户质疑',
  3, 1, 1, 2, NULL, 1, 2,
  0, 0, 4, 10, 1,
  4, '2026-05-26 15:32:12', '2026-09-16 10:31:34');

-- ---- 版本 v1（旧版本，2026-05-26 创建） ----
INSERT INTO act_theme_version (id, theme_id, version_no,
  theme_name, theme_desc, owner_user_id, plan_start_time, plan_end_time,
  total_drill_count, per_scene_limit, join_mode, guest_access_enabled,
  ai_response_mode, training_mode_enabled, assessment_mode_enabled, coach_review_enabled, suggestion_enabled,
  practice_methods, difficulty, allow_custom_difficulty,
  face_check_enabled, face_check_stage, screen_switch_mode, screen_switch_limit,
  scene_pass_type, scene_pass_count,
  creator, used_user_count, completed_count, in_progress_count, created_at, updated_at)
VALUES ('seed-ver-001', 'seed-theme-001', 1,
  '柔性智造销售话术训练', '基于六大场景知识库，训练销售精准讲解方案价值并应对客户质疑', 'admin', NULL, NULL,
  3708, NULL, 1, 0,
  1, 1, 0, 1, 0,
  'case,custom,random', 2, 1,
  0, NULL, 'forbid', 0,
  1, 1,
  '管理员', 0, 0, 0, '2026-05-26 15:37:48', '2026-05-26 15:37:48');

-- ---- 版本 v2（当前版本，2026-06-02 创建） ----
INSERT INTO act_theme_version (id, theme_id, version_no,
  theme_name, theme_desc, owner_user_id, plan_start_time, plan_end_time,
  total_drill_count, per_scene_limit, join_mode, guest_access_enabled,
  ai_response_mode, training_mode_enabled, assessment_mode_enabled, coach_review_enabled, suggestion_enabled,
  practice_methods, difficulty, allow_custom_difficulty,
  face_check_enabled, face_check_stage, screen_switch_mode, screen_switch_limit,
  scene_pass_type, scene_pass_count,
  creator, used_user_count, completed_count, in_progress_count, created_at, updated_at)
VALUES ('seed-ver-002', 'seed-theme-001', 2,
  '柔性智造销售话术训练', '基于六大场景知识库，训练销售精准讲解方案价值并应对客户质疑', 'admin', NULL, NULL,
  3708, NULL, 1, 0,
  1, 1, 0, 1, 0,
  'case,custom,random', 2, 1,
  0, NULL, 'forbid', 0,
  1, 1,
  '管理员', 1, 0, 1, '2026-06-02 07:55:17', '2026-06-02 07:55:17');

-- ---- 场景单元（v1 与 v2 内容一致，各 5 个；此处以 v2 为准成对插入） ----
INSERT INTO act_scenario_unit (id, theme_id, version_no, sort_order, unit_name, audience,
  time_limit_minutes, business_goal, iceberg_elements, business_impact, failure_cost,
  core_conflict, common_failure_modes, difficulties, forbidden_behaviors, pass_score, created_at, updated_at)
VALUES
('seed-unit-v2-001', 'seed-theme-001', 2, 1, '初次拜访：系统定位与六大场景全景介绍', '新入职销售',
 15, '在首次客户沟通中清晰传达柔性智造运营管理系统的核心价值与全链路覆盖能力，建立专业可信的第一印象',
 JSON_ARRAY('系统架构认知','场景功能区分','结构化表达','基础话术运用','技术型销售顾问','专业可信','客户导向','耐心细致','积极主动','建立信任','传递价值'),
 '客户对系统形成完整认知，愿意安排技术对接', '客户兴趣流失，后续接触成本大幅上升',
 '客户时间有限，需在短时间内讲清复杂系统的核心价值',
 JSON_ARRAY('遗漏关键场景','表述混乱导致客户理解困难','过度技术化引发客户抵触'),
 JSON_ARRAY('如何简化专业内容以适应非技术背景客户','如何在短时间内突出核心优势'),
 JSON_ARRAY('直接报价','承诺未核实的技术细节'), 70, NOW(), NOW()),
('seed-unit-v2-002', 'seed-theme-001', 2, 2, '客户关注产前效益：物料齐套方案深度解析', '新入职销售',
 12, '针对客户对产前效益的关注，深度解析物料齐套方案的价值与实施路径',
 JSON_ARRAY('物料齐套认知','方案价值表达','数据化论证','需求挖掘','专业可信','客户导向'),
 '客户认可方案价值，进入方案评估阶段', '客户转向竞品对比，错失引导机会',
 '客户已有供应商认知，需重塑价值标准',
 JSON_ARRAY('只谈功能不谈效益','无法回应成本质疑'),
 JSON_ARRAY('如何用 ROI 视角重构对话','如何应对比价压力'),
 JSON_ARRAY('贬低竞品','口头承诺交付期'), 70, NOW(), NOW()),
('seed-unit-v2-003', 'seed-theme-001', 2, 3, '应对技术质疑：智能裁剪与产中齐套对比说明', '新入职销售',
 10, '面对技术型质疑，准确说明智能裁剪与产中齐套的技术差异与优势边界',
 JSON_ARRAY('技术原理认知','对比表达','异议处理','临场应变','专业可信'),
 '技术疑虑消除，客户信任度提升', '被客户技术团队否定，项目停滞',
 '客户技术团队掌握话语权，要求严谨论证',
 JSON_ARRAY('回避技术细节','夸大技术指标'),
 JSON_ARRAY('如何在不确定处诚实表达','如何引导回到价值主线'),
 JSON_ARRAY('编造参数','攻击客户现有系统'), 70, NOW(), NOW()),
('seed-unit-v2-004', 'seed-theme-001', 2, 4, '处理关键异议：分拣准确性与仓储性能验证', '新入职销售',
 13, '针对分拣准确性与仓储性能的关键异议，用验证数据与案例化解顾虑',
 JSON_ARRAY('性能指标认知','证据呈现','异议转化','情绪管理','客户导向','耐心细致'),
 '异议转化为深化沟通的切入点', '异议升级为信任危机',
 '客户要求可验证的数据而现场缺乏完整材料',
 JSON_ARRAY('以偏概全回应异议','情绪化争辩'),
 JSON_ARRAY('如何现场构建可信论证','如何承诺合理的验证路径'),
 JSON_ARRAY('承诺无法兑现的指标','回避验证请求'), 70, NOW(), NOW()),
('seed-unit-v2-005', 'seed-theme-001', 2, 5, '综合考核：小单快反与爆品打造优势整合陈述', '新入职销售',
 15, '整合小单快反与爆品打造的核心优势，完成面向决策层的综合价值陈述',
 JSON_ARRAY('价值整合','结构化表达','场景功能区分','基础话术运用','建立信任','传递价值'),
 '决策层认可整体价值，推动立项', '陈述失焦，项目失去高层支持',
 '决策层时间宝贵且关注点宏观，需高度整合表达',
 JSON_ARRAY('信息堆砌无主线','只讲单点优势'),
 JSON_ARRAY('如何构建决策层视角叙事','如何平衡宏观与细节'),
 JSON_ARRAY('无结论收尾','超时陈述'), 70, NOW(), NOW());

-- v1 场景单元：内容与 v2 一致（版本隔离要求下成对存在）
INSERT INTO act_scenario_unit (id, theme_id, version_no, sort_order, unit_name, audience,
  time_limit_minutes, business_goal, iceberg_elements, business_impact, failure_cost,
  core_conflict, common_failure_modes, difficulties, forbidden_behaviors, pass_score, created_at, updated_at)
VALUES
('seed-unit-v1-001', 'seed-theme-001', 1, 1, '初次拜访：系统定位与六大场景全景介绍', '新入职销售',
 15, '在首次客户沟通中清晰传达柔性智造运营管理系统的核心价值与全链路覆盖能力，建立专业可信的第一印象',
 JSON_ARRAY('系统架构认知','场景功能区分','结构化表达','基础话术运用','技术型销售顾问','专业可信','客户导向','耐心细致','积极主动','建立信任','传递价值'),
 '客户对系统形成完整认知，愿意安排技术对接', '客户兴趣流失，后续接触成本大幅上升',
 '客户时间有限，需在短时间内讲清复杂系统的核心价值',
 JSON_ARRAY('遗漏关键场景','表述混乱导致客户理解困难','过度技术化引发客户抵触'),
 JSON_ARRAY('如何简化专业内容以适应非技术背景客户','如何在短时间内突出核心优势'),
 JSON_ARRAY('直接报价','承诺未核实的技术细节'), 70, NOW(), NOW()),
('seed-unit-v1-002', 'seed-theme-001', 1, 2, '客户关注产前效益：物料齐套方案深度解析', '新入职销售',
 12, '针对客户对产前效益的关注，深度解析物料齐套方案的价值与实施路径',
 JSON_ARRAY('物料齐套认知','方案价值表达','数据化论证','需求挖掘','专业可信','客户导向'),
 '客户认可方案价值，进入方案评估阶段', '客户转向竞品对比，错失引导机会',
 '客户已有供应商认知，需重塑价值标准',
 JSON_ARRAY('只谈功能不谈效益','无法回应成本质疑'),
 JSON_ARRAY('如何用 ROI 视角重构对话','如何应对比价压力'),
 JSON_ARRAY('贬低竞品','口头承诺交付期'), 70, NOW(), NOW()),
('seed-unit-v1-003', 'seed-theme-001', 1, 3, '应对技术质疑：智能裁剪与产中齐套对比说明', '新入职销售',
 10, '面对技术型质疑，准确说明智能裁剪与产中齐套的技术差异与优势边界',
 JSON_ARRAY('技术原理认知','对比表达','异议处理','临场应变','专业可信'),
 '技术疑虑消除，客户信任度提升', '被客户技术团队否定，项目停滞',
 '客户技术团队掌握话语权，要求严谨论证',
 JSON_ARRAY('回避技术细节','夸大技术指标'),
 JSON_ARRAY('如何在不确定处诚实表达','如何引导回到价值主线'),
 JSON_ARRAY('编造参数','攻击客户现有系统'), 70, NOW(), NOW()),
('seed-unit-v1-004', 'seed-theme-001', 1, 4, '处理关键异议：分拣准确性与仓储性能验证', '新入职销售',
 13, '针对分拣准确性与仓储性能的关键异议，用验证数据与案例化解顾虑',
 JSON_ARRAY('性能指标认知','证据呈现','异议转化','情绪管理','客户导向','耐心细致'),
 '异议转化为深化沟通的切入点', '异议升级为信任危机',
 '客户要求可验证的数据而现场缺乏完整材料',
 JSON_ARRAY('以偏概全回应异议','情绪化争辩'),
 JSON_ARRAY('如何现场构建可信论证','如何承诺合理的验证路径'),
 JSON_ARRAY('承诺无法兑现的指标','回避验证请求'), 70, NOW(), NOW()),
('seed-unit-v1-005', 'seed-theme-001', 1, 5, '综合考核：小单快反与爆品打造优势整合陈述', '新入职销售',
 15, '整合小单快反与爆品打造的核心优势，完成面向决策层的综合价值陈述',
 JSON_ARRAY('价值整合','结构化表达','场景功能区分','基础话术运用','建立信任','传递价值'),
 '决策层认可整体价值，推动立项', '陈述失焦，项目失去高层支持',
 '决策层时间宝贵且关注点宏观，需高度整合表达',
 JSON_ARRAY('信息堆砌无主线','只讲单点优势'),
 JSON_ARRAY('如何构建决策层视角叙事','如何平衡宏观与细节'),
 JSON_ARRAY('无结论收尾','超时陈述'), 70, NOW(), NOW());

-- ---- 评估维度（挂 v2 各单元；单元1 五维、单元2~5 各四维，体现"各单元维度可不同"） ----

-- 单元 1（5 维，权重合计 100）
INSERT INTO act_evaluation_dimension (id, scenario_unit_id, dimension_name, weight, dimension_desc, excellent_standard, good_standard, improve_standard, sort_order)
VALUES
('seed-dim-0101', 'seed-unit-v2-001', '系统认知完整性', 25, '评估学员对柔性智造运营管理系统整体架构与核心定位的理解程度',
 '优秀（90-100分）：能准确描述系统为全链路数据驱动、端到端快速反应的六大场景解决方案，并完整列举所有场景名称，逻辑清晰无遗漏',
 '良好（70-89分）：能说出系统核心定位和4-5个场景，表述基本正确但略有卡顿',
 '需改进（<70分）：无法说清系统定位，场景遗漏超过2个或存在明显错误', 1),
('seed-dim-0102', 'seed-unit-v2-001', '量化指标准确运用', 20, '评估学员在陈述中引用关键量化指标的准确性与恰当性',
 '优秀（90-100分）：指标引用准确且贴合客户关注点，能现场推算效益',
 '良好（70-89分）：指标基本准确，个别数据模糊',
 '需改进（<70分）：指标错误或全程无数据支撑', 2),
('seed-dim-0103', 'seed-unit-v2-001', '场景差异辨析能力', 15, '评估学员区分六大场景功能边界与适用条件的能力',
 '优秀（90-100分）：能精准辨析场景差异并举例说明适用场景组合',
 '良好（70-89分）：能区分主要场景，个别混淆',
 '需改进（<70分）：场景概念混用，无法举例', 3),
('seed-dim-0104', 'seed-unit-v2-001', '标准话术规范使用', 25, '评估学员对标准开场与价值话术的掌握与灵活运用',
 '优秀（90-100分）：话术自然流畅，能根据客户反应灵活调整',
 '良好（70-89分）：话术完整但略显背诵感',
 '需改进（<70分）：话术遗漏关键环节或明显生硬', 4),
('seed-dim-0105', 'seed-unit-v2-001', '价值整合与升华', 15, '评估学员将单点价值整合为整体方案的陈述能力',
 '优秀（90-100分）：能自然收束全场信息并升华到战略价值',
 '良好（70-89分）：有总结但整合度一般',
 '需改进（<70分）：陈述散乱，无整合意识', 5);

-- 单元 2（4 维）
INSERT INTO act_evaluation_dimension (id, scenario_unit_id, dimension_name, weight, dimension_desc, excellent_standard, good_standard, improve_standard, sort_order)
VALUES
('seed-dim-0201', 'seed-unit-v2-002', '方案价值表达', 30, '评估学员讲清物料齐套方案价值主线的能力',
 '优秀（90-100分）：价值主线清晰，能分层递进展开', '良好（70-89分）：价值点齐全但层次感不足', '需改进（<70分）：价值表达零散', 1),
('seed-dim-0202', 'seed-unit-v2-002', '数据化论证', 25, '评估学员用数据支撑效益主张的能力',
 '优秀（90-100分）：数据选取精准，论证链完整', '良好（70-89分）：有数据但论证不充分', '需改进（<70分）：缺乏数据支撑', 2),
('seed-dim-0203', 'seed-unit-v2-002', '需求挖掘', 25, '评估学员在解析方案时探询客户真实关注的能力',
 '优秀（90-100分）：能敏锐捕捉信号并追问验证', '良好（70-89分）：有探询但深度不足', '需改进（<70分）：单向输出不探询', 3),
('seed-dim-0204', 'seed-unit-v2-002', '专业可信度', 20, '评估学员整体表达的专业形象与可信度',
 '优秀（90-100分）：术语准确，姿态自信可信', '良好（70-89分）：基本专业，偶有迟疑', '需改进（<70分）：表述不专业', 4);

-- 单元 3（4 维）
INSERT INTO act_evaluation_dimension (id, scenario_unit_id, dimension_name, weight, dimension_desc, excellent_standard, good_standard, improve_standard, sort_order)
VALUES
('seed-dim-0301', 'seed-unit-v2-003', '技术原理认知', 30, '评估学员对智能裁剪与产中齐套技术原理的掌握',
 '优秀（90-100分）：原理阐述准确，边界清晰', '良好（70-89分）：原理基本正确，细节模糊', '需改进（<70分）：原理表述错误', 1),
('seed-dim-0302', 'seed-unit-v2-003', '对比表达', 25, '评估学员进行优势对比时的表达策略',
 '优秀（90-100分）：对比客观有力，突出差异价值', '良好（70-89分）：能对比但重点不突出', '需改进（<70分）：对比混乱或失实', 2),
('seed-dim-0303', 'seed-unit-v2-003', '异议处理', 25, '评估学员应对技术质疑的心态与策略',
 '优秀（90-100分）：沉着应对，层层化解', '良好（70-89分）：能回应但方法单一', '需改进（<70分）：回避或抵触质疑', 3),
('seed-dim-0304', 'seed-unit-v2-003', '临场应变', 20, '评估学员在压力情境下的临场调整能力',
 '优秀（90-100分）：反应迅速，策略灵活', '良好（70-89分）：能调整但速度偏慢', '需改进（<70分）：应变失措', 4);

-- 单元 4（4 维）
INSERT INTO act_evaluation_dimension (id, scenario_unit_id, dimension_name, weight, dimension_desc, excellent_standard, good_standard, improve_standard, sort_order)
VALUES
('seed-dim-0401', 'seed-unit-v2-004', '证据呈现', 30, '评估学员组织验证数据与案例的说服力',
 '优秀（90-100分）：证据链完整，呈现有序有力', '良好（70-89分）：有证据但组织松散', '需改进（<70分）：无有效证据', 1),
('seed-dim-0402', 'seed-unit-v2-004', '异议转化', 25, '评估学员将异议转化为沟通深化的能力',
 '优秀（90-100分）：转化自然，借异议推进关系', '良好（70-89分）：能化解但无转化', '需改进（<70分）：被异议牵制', 2),
('seed-dim-0403', 'seed-unit-v2-004', '情绪管理', 25, '评估学员面对质疑时的情绪稳定性',
 '优秀（90-100分）：全程稳定，压力下依然从容', '良好（70-89分）：基本稳定，偶有波动', '需改进（<70分）：情绪明显失控', 3),
('seed-dim-0404', 'seed-unit-v2-004', '验证承诺', 20, '评估学员给出的验证路径承诺的合理性与可信度',
 '优秀（90-100分）：路径具体可执行，承诺克制', '良好（70-89分）：有承诺但路径模糊', '需改进（<70分）：过度承诺或回避', 4);

-- 单元 5（4 维）
INSERT INTO act_evaluation_dimension (id, scenario_unit_id, dimension_name, weight, dimension_desc, excellent_standard, good_standard, improve_standard, sort_order)
VALUES
('seed-dim-0501', 'seed-unit-v2-005', '价值整合', 30, '评估学员整合多模块优势的整体陈述能力',
 '优秀（90-100分）：整合主线清晰，层次分明', '良好（70-89分）：有整合但主线不突出', '需改进（<70分）：信息堆砌', 1),
('seed-dim-0502', 'seed-unit-v2-005', '结构化表达', 25, '评估学员面向决策层的结构化表达水平',
 '优秀（90-100分）：结构严谨，节奏得当', '良好（70-89分）：结构完整但节奏一般', '需改进（<70分）：表达无结构', 2),
('seed-dim-0503', 'seed-unit-v2-005', '决策层视角', 25, '评估学员站在决策层关注点组织内容的能力',
 '优秀（90-100分）：全程贴合决策视角，直击关切', '良好（70-89分）：偶有视角偏移', '需改进（<70分）：视角错位', 3),
('seed-dim-0504', 'seed-unit-v2-005', '收尾与推进', 20, '评估学员陈述收束与下一步推动的能力',
 '优秀（90-100分）：收尾有力，明确推动动作', '良好（70-89分）：有收尾但推进乏力', '需改进（<70分）：无收尾或无推进', 4);

-- v1 各单元维度：与 v2 相同（复制，保持版本隔离演示一致）
INSERT INTO act_evaluation_dimension (id, scenario_unit_id, dimension_name, weight, dimension_desc, excellent_standard, good_standard, improve_standard, sort_order)
SELECT CONCAT('v1-', id), REPLACE(scenario_unit_id, 'v2', 'v1'),
       dimension_name, weight, dimension_desc, excellent_standard, good_standard, improve_standard, sort_order
FROM act_evaluation_dimension WHERE scenario_unit_id LIKE 'seed-unit-v2-%';
