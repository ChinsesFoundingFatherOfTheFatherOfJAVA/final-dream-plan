-- ============================================================
-- 在线课堂（管理端）课程设置扩展 —— kng_setting 重构脚本
-- 版本 v2.0 ｜ 2026-09-30 ｜ 数据库：final_dream（10.100.26.200）
-- 配套：05-需求文档、06-技术实现方案、07-接口文档
--
-- ⚠️ 本脚本【重建】kng_setting（v1.0 旧列结构作废，改 JSON 列）。
--    表内仅一行默认配置；若线上已保存过设置，先执行文末"留档查询"导出后再执行 DROP。
-- ============================================================

-- 0.（可选）留档查询：执行 DROP 前先导出当前配置
-- SELECT * FROM kng_setting;

-- 1. 重建表（4 个 JSON 列对应 4 个设置区块）
DROP TABLE IF EXISTS `kng_setting`;

CREATE TABLE `kng_setting` (
  `id`          TINYINT      NOT NULL DEFAULT 1     COMMENT '恒为1',
  `score_conf`  JSON         NULL                   COMMENT '学分策略（FP-02b）',
  `cheat_conf`  JSON         NULL                   COMMENT '防挂机+特殊设置（FP-02c/02d）',
  `play_conf`   JSON         NULL                   COMMENT '课程播放（FP-02e）',
  `face_conf`   JSON         NULL                   COMMENT '人脸识别（FP-02f）',
  `updated_by`  VARCHAR(32)  NULL,
  `updated_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='在线课堂-课程设置(单行,JSON配置)';

-- 2. 种子行（默认值 = 原平台抓包当前值；读接口对 NULL 亦有代码级默认兜底，本行保证首屏即有数据）
INSERT INTO `kng_setting` (`id`, `score_conf`, `cheat_conf`, `play_conf`, `face_conf`) VALUES (
  1,
  -- 学分策略：五类规则 + 发放时间（rewardType 0=每学完一个课件任务发放）
  '{"videoAudio":{"standardMinutes":10,"score":1.0,"applyToAll":false},
    "document":{"pagesPerScore":1,"score":0.1,"standardMinutes":1,"maxScore":6.0,"applyToAll":false},
    "microcourse":{"standardMinutes":10,"score":1.0,"maxScore":10.0,"applyToAll":false},
    "scorm":{"standardMinutes":10,"score":1.0,"applyToAll":false},
    "html":{"standardMinutes":10,"score":1.0,"applyToAll":false},
    "rewardType":0}',
  -- 防挂机：开、模式一、3分钟、120秒、防多课程开、禁拖拽开、后台播放关
  '{"antiIdleEnabled":true,"mode":1,"checkMinutes":3,"confirmSeconds":120,
    "promptText":"已触发防挂机验证，请点击\u201c继续学习\u201d，否则学习将被停止",
    "multiCourseEnabled":true,"forbidDragEnabled":true,"audioBackgroundPlay":false}',
  -- 课程播放：倍速开、跟随课件或课程各自的功能设置
  '{"speedEnabled":true,"speedScope":2,"speedHoursCalc":true}',
  -- 人脸识别：关
  '{"enabled":false}'
);

-- ============================================================
-- 验证脚本
-- SELECT JSON_VALID(score_conf), JSON_VALID(cheat_conf), JSON_VALID(play_conf), JSON_VALID(face_conf)
--   FROM kng_setting;                          -- 预期 1,1,1,1
-- SELECT JSON_EXTRACT(cheat_conf, '$.checkMinutes') FROM kng_setting;  -- 预期 3
-- SELECT id FROM kng_setting;                  -- 预期 1 行
-- ============================================================
