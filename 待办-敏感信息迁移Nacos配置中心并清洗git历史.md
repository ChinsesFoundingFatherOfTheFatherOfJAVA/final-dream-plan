# 待办：敏感信息迁移 Nacos 远程配置中心（并清洗 git 历史）

> 状态：**待办**（全部工程完成后统一执行，2026-10-02 记录）
> 前置：gateway/各工程已引入 nacos-config 依赖，`import-check.enabled=false`，尚未真正接管配置
> 关联：《后端架构总纲.md》§8 配置与安全规范

## 1. 为什么要做

当前数据库口令、Oracle 口令、JWT secret、Dify/百炼/豆包 API key 全部明文写在各工程
`application.properties` 中并已进入 git 历史。工程完成后需一次性完成：
①密钥外移到 Nacos 配置中心；②历史提交中的敏感信息替换（改密钥 + 历史清洗双管齐下，只删历史不改钥匙等于没改）。

## 2. 敏感信息清单（迁移项）

| 配置项 | 所在工程 | 说明 |
|---|---|---|
| `spring.datasource.password`（root/***REMOVED***） | SpeechTraining / OnlineClassroom / AtualCombatTraining / StaffManagement(sm.mysql.password) | 共享库 final_dream；顺带评估业务库独立账号（总纲 §11.5） |
| `sm.oracle.password`（***REMOVED***） | StaffManagement | Oracle 只读视图 |
| `sm.auth.jwt-secret` / `speech.auth.jwt-secret` / `kng.auth.jwt-secret` / `gateway.auth.jwt-secret` | 四工程 + gateway | 同一把 HS256 密钥；统一用环境变量 `SPEECH_AUTH_JWT_SECRET` 占位已就位 |
| `sm.auth.default-password` / `sm.auth.admin-initial-password` | StaffManagement | 全员默认口令（风险 R-5） |
| `dify.agents.*.api-key`（4 个 app key） | SpeechTraining | Dify 智能体 |
| `dashscope.api-key` / `speech.tone.api-key` | SpeechTraining / AtualCombatTraining | 百炼（同一把 key，两处重复） |
| `media.asr.api-key` / `media.translate.api-key` / `media.oss.access-key-id/-secret` | OnlineClassroom | 百炼 key（与 SpeechTraining 同一把，第三处重复）+ OSS AK/SK（gulimall-fangyuan 桶）；2026-10-08 本地开发期由环境变量占位改为明文（用户拍板），属新增迁移项 |
| `speech.asr.doubao.app-key / access-key` | SpeechTraining | 豆包 SAUC |
| `spring.data.redis`（无密码，仅内网） | StaffManagement | 迁配置中心时一并收口 |

## 3. 执行步骤

1. **Nacos 侧**：建 `after-end-common.yaml`（共享：JWT secret、Dify base-url 等跨工程项）+ 各工程专属
   `{application}.yaml`（数据源、各 API key）；开启 `spring.config.import=nacos:...`，删除各工程的
   `import-check.enabled=false`；本地开发回退用环境变量。
2. **轮换所有密钥**（迁移后旧值全部作废）：MySQL 口令、Oracle 口令、JWT secret（换 secret 会让全站在线登录态失效，选择低峰窗口）、Dify/百炼/豆包 key。
3. **git 历史清洗**（轮换后执行，顺序不能反）：
   - 推荐 `git filter-repo --replace-text`（把各明文密钥串替换为 `***REMOVED***`），对 after-end 与 plan 两个仓库分别执行；
   - 或 BFG Repo-Cleaner；清洗后强制推送并通知所有协作者重新 clone；
   - 注意 plan 仓库同样含密钥（各 02-技术实现方案里贴过配置样例），两个仓库都要清。
4. **验证**：全部应用以"环境变量 + Nacos 配置"冷启动跑通冒烟；`git log -p | grep` 抽查历史中已无密钥原文。

## 4. 验收口径

- 任一工程 `application.properties` 中不再出现口令/key 原文，只有 `${ENV_VAR:}` 占位或 Nacos import；
- 两个 git 仓库全历史检索不到本清单中的任何原文；
- Nacos 配置有命名空间/权限隔离，配置中心访问账号不落库。
