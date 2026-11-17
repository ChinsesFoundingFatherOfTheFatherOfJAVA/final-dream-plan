-- 平台预览看板 索引增补
-- 版本：v1.0 ｜ 日期：2026-11-17 ｜ 库：final_dream
-- 依据：02-技术实现方案.md 第 3 节（统计查询走时间区间 + 分桶，现有热表时间列无索引）
-- 执行前请确认各索引在目标库尚不存在（information_schema.statistics 已核对，均为新增名）。

-- 在线课堂：按 start_study_time 分桶，配套 user_id 去重与 study_status 判定
ALTER TABLE kng_study_record ADD INDEX idx_sr_start_user (start_study_time, user_id), ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE kng_study_record ADD INDEX idx_sr_status_start (study_status, start_study_time), ALGORITHM=INPLACE, LOCK=NONE;

-- 话术训练：按 start_time 分桶
ALTER TABLE training_session ADD INDEX idx_ts_start_user (start_time, user_id), ALGORITHM=INPLACE, LOCK=NONE;

-- 实战训练场：按 COALESCE(started_at, created_at) 分桶，双列都建以支持 coalesce 走索引
ALTER TABLE act_practice_attempt ADD INDEX idx_attempt_started_user (started_at, user_id), ALGORITHM=INPLACE, LOCK=NONE;

-- 测练中心：按 COALESCE(submit_at, created_at) 分桶 + status / pass_status 过滤
ALTER TABLE exam_attempt ADD INDEX idx_attempt_submit_status (submit_at, status, pass_status), ALGORITHM=INPLACE, LOCK=NONE;
ALTER TABLE exam_arrange ADD INDEX idx_arrange_created (created_at), ALGORITHM=INPLACE, LOCK=NONE;

-- 说明：
-- 1. kng_course 已有 idx_updated(updated_at)，本期新增使用 created_at，数据量 1 行，暂不建索引；
--    若后续课程量增长到万级，再补 idx_course_created (created_at)。
-- 2. training_project 仅 2 行，exam_arrange_student 已有 idx_student_arrange_status 可覆盖 deleted 过滤，均不新增。
-- 3. 所有语句均使用 ALGORITHM=INPLACE, LOCK=NONE，避免统计期业务写入被阻塞。
