# 07 DDL 变更清单（话术训练业务闭环模块）

> 库：`final_dream` @ `10.100.26.200:3306`（共享开发库）。
> 变更共 2 项：① 新表 `project_student`；② 权限点数据插入（组织架构模块权限表）。
> **无既有表结构变更**（training_project 的 responsible_person 列保留不新写；统计全部实时聚合不落表）。
> 执行纪律沿用：本机无 mysql CLI，用临时 Java JDBC 类执行（幂等：先查 information_schema / 存在性再执行），执行完清理临时目录。

---

## ① 指派关系表 project_student

### 为什么
"项目下发"缺数据载体：学员端列表按指派过滤、邀请/移除学员、概览统计、排名范围全部依赖此表（01 FP-40）。
决策（2026-09-24）：单表 + 硬删——移除学员后历史训练保留（报告直链可查），不做状态位/日志表。

### 变更语句（幂等）

```sql
CREATE TABLE IF NOT EXISTS project_student (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  project_id BIGINT NOT NULL COMMENT '训练项目ID(training_project.id)',
  user_id VARCHAR(64) NOT NULL COMMENT '学员工号(组织架构sys_user.user_id)',
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  created_by VARCHAR(64) COMMENT '添加人(创建者工号)',
  UNIQUE INDEX uk_project_user (project_id, user_id),
  INDEX idx_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='训练项目指派学员(硬删;移除后历史训练保留,统计/排名仅含当前指派)';
```

### 执行前检查
```sql
SELECT COUNT(*) FROM information_schema.TABLES
WHERE TABLE_SCHEMA='final_dream' AND TABLE_NAME='project_student';  -- 1=已存在跳过
```

### 执行后校验
```sql
SHOW CREATE TABLE project_student;  -- 核对两索引
-- 现有项目（id 见 training_project）手工补指派（否则发布项目对学员不可见）：
-- 例：为项目 19 指派测试学员
INSERT IGNORE INTO project_student (project_id, user_id, created_by) VALUES (19, '40022966', 'admin');
```

### 回滚
```sql
DROP TABLE project_student;
```
（回滚即失去指派数据，学员端列表将回退为"全量已发布"或空——取决于代码分支，建议与代码同回退。）

---

## ② 权限点数据（组织架构模块权限表插入）

### 为什么
E1 决策：AI话术训练管理端 = 单权限点 `sparring:manage`，挂进组织架构模块的权限树（菜单级），角色管理勾选即时生效。

### 变更语句（按组织架构模块 07-DDL 的权限表结构执行，表名以其最终实现为准）

```sql
-- ⚠️ 表名/列名以组织架构模块已执行的 DDL 为准，执行前先 SHOW CREATE TABLE 核对
INSERT INTO sys_permission (code, name, parent_code, sort_order, enabled)
SELECT 'sparring:manage', 'AI话术训练管理', 'sparring', 10, 1
FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM sys_permission WHERE code='sparring:manage');
```

- 若组织架构模块尚有"AI对练"父级菜单概念，parent_code 对应调整；执行前与该模块 DDL 清单核对表结构与父节点 code。
- **依赖**：组织架构模块的 sys_* 表先建好。该模块截至 2026-09-24 处于文档交付状态（编码进度待确认）——若未上线，此项**推迟执行**，SpeechTraining 的权限校验在 dev profile 下放行（02 §3.2 mock 回落），不阻塞其余功能。

### 回滚
```sql
DELETE FROM sys_permission WHERE code='sparring:manage';
```

---

## ③ 数据迁移说明（非 DDL，执行时一并处理）

| 项 | 处理 |
|----|------|
| mock_student_001 历史数据 | **不迁移**：该 user_id 的会话/报告保留可查（直链）；无指派行则不出现在任何列表/统计/排名 |
| 现有 2 个项目（5、19） | 发布/测试需要可见时按 ①执行后校验 手工 INSERT 指派行 |
| responsible_person 历史值 | 保留不清洗；展示层一律改读 created_by_name（FP-57） |

## 部署顺序

1. 先执行 ①（project_student）→ 再部署后端（否则学员端列表过滤直接 SQL 报错——表不存在）。
2. ② 依赖组织架构模块，独立时点执行；未执行期间权限校验走 dev 放行。
3. 前端部署无顺序约束（接口 404/401 兜底已有 toast）。
