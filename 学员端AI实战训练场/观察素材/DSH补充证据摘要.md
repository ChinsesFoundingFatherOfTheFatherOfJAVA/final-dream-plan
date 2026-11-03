# DSH 两路勘探补充证据摘要

> 恢复日期：2026-10-30
> 来源：deja 索引中的 DSH 原始执行记录
> 目的：补回已删除 DSH 临时目录中对施工和审计有价值的内容，不复制失效接口和敏感凭证。
> 约束：本文件是证据摘要，不是新的前后端契约；业务规则仍以 `00`～`05` 文档为准。

## 1. 两路 DSH 会话

| 标记 | DSH 会话 | 时间 | 覆盖内容 |
|---|---|---|---|
| DSH-A | `f04e0ff3-d8a5-4549-b256-83ca90107285` | 2026-10-29，最终更新 2026-10-30 | 首页最近练习、练习历程、随机练习、正式训练、报告、三种记录状态、计时与 TTS |
| DSH-B | `784112e4-b0c6-4c00-a266-9bbe4ca6ab54` | 2026-10-29 11:04–11:33 | 实战案例开始训练、`session-v2`、准备 WS、教练点评、训练页 |

两路不是重复勘探：

- DSH-A 更偏“练习入口、记录、随机链路和完整跑局”。
- DSH-B 更偏“实战案例准备链路、WebSocket 帧和训练运行页”。

正式契约必须同时吸收这两条线的结论。

## 2. 两路共同确认的完整链路

```text
主题详情
  -> 场景准备弹窗
  -> 实战案例 / 随机练习 / 自定义练习
  -> 训练或考核确认
  -> 创建 attempt/session
  -> 四阶段准备
  -> 练习准备页
  -> 限时确认
  -> 正式对练
  -> 结束
  -> 报告
  -> 练习历程 / 再练一次
```

本系统统一为一个 attempt/runtime；原平台在随机和案例入口上的准备实现不同，不要求复刻其接口差异。

## 3. 随机练习证据（DSH-A）

### 3.1 入口弹窗

- 场景准备弹窗约 800x627，底部为取消、随机练习、自定义练习。
- 随机练习弹窗约 800x624，纯前端打开时不发业务请求。
- 难度三档：
  - 简单：适合新手、角色配合度高、通过 +30 荣誉分。
  - 中等：有一定挑战、需要策略、通过 +50 荣誉分。
  - 困难：角色抵触强硬、通过 +80 荣誉分。
- 默认选中中等，抓包中的 `difficulty=2`。
- 难度只影响 AI 角色抵触强度，不改变场景范围。
- “开始随机练习”后还有 480x436 的开始训练确认弹窗。

### 3.2 原平台准备链路

随机练习抓到了：

```text
GET  /sparring/freeprac/members/{projectId}/{activityId}/randomScript?difficulty=2
POST /sparring/freeprac/members/{projectId}/{activityId}/randomScript
```

原记录推测为 POST 受理、GET 获取结果，但不能据此断定新系统要使用同样的轮询实现。

进入准备后，原平台 URL 依次为：

```text
/drillmate/drill?ex_id={projectId}
/drillmate/drill/{conversationId}?ex_id={projectId}
```

四阶段准备约 20 秒内完成，页面观测到 0% -> 40% -> 完成。

### 3.3 随机化结果

随机练习生成的客户与原案例不同：

- 原案例：王总。
- 随机结果：金鹏，连云港花果山制衣厂生产总监，40–45 岁。

证明随机练习确实重新生成具体客户、工厂、年龄和背景，不能只替换场景标题。

## 4. 实战案例准备证据（DSH-B）

### 4.1 HTTP 顺序

点击“开始训练”后的主要业务请求：

1. `GET .../{activityId}/drill-count-check?studyMode=1`
2. `POST .../members/join/project/{projectId}`
3. 进入 `/drillmate/drill?ex_id=...` 过渡页
4. `POST /xuiappserver/api/session-v2`
5. `GET /xuiappserver/api/agent-v2/code/side_free_user`
6. `POST /sparring/freeprac/members/attend/{projectId}`
7. `GET /xuiappserver/api/message/session/{conversationId}?limit=1000`

案例链路没有出现 `randomScript`。原平台案例和随机练习可能使用不同准备机制；本系统统一由 AIGentService 生成/组装 attempt 脚本。

### 4.2 WebSocket 准备事件

原平台使用：

```text
wss://.../xuiappserver/ws/chat?sessionId={conversationId}
```

客户端关键动作：

- `common-session-start`：进入准备。
- `biz-common-gonext`：准备页确认后推进到正式对练。

关键 `data_delta`：

| identifier / type | 含义 |
|---|---|
| `biz-common-sco-lifecycle` | 导学、剧本生成、对练演绎生命周期 |
| `biz-common-side-roleplaying/script-loading` | 四阶段准备进度 |
| `.../narration` | 场景旁白 |
| `.../progress` | 轮次、时长、剩余时间、目标进度 |
| `tool/coach_guidance` | 教练点评 |
| `text_delta` | AI 角色台词流 |

准备阶段没有 REST 轮询，进度来自 WS。

### 4.3 教练点评样例

实测首轮教练点评大意：

> 开场略急；应准确称呼客户，先回应客户此前项目失败的顾虑，而不是直接堆产品名词。

这与契约中的 `coachReviewEnabled` 对应。考核模式没有该卡片。

## 5. 正式训练与计时（DSH-A）

### 5.1 计时器取证

原平台使用：

```text
GET/POST /xuiappserver/api/user-storage/drill_timer_{conversationId}
```

值大致为：

```json
{
  "duration": 0,
  "savedAt": 1793244443737,
  "isVisible": true
}
```

运行期间约每 5 秒更新一次 `duration`，用于刷新/断线恢复。

本系统不复制 user-storage 临时存储，改为服务端 `started_at/deadline_at/paused_duration_ms`，原因：

- 结束时必须由服务端裁决。
- attempt 需要事务、幂等和审计。
- 浏览器刷新或断网不能影响最终结算。

### 5.2 对话与进度

原平台对话走独立 WS，不通过 REST。

一轮之后的进度事件包含：

- `dialogRound`
- `maxDialogRound`
- `maxDuration`
- `spentDuration`
- `remainDuration`
- `progress`
- `turnLimitReached`

本系统的 WS 事件名不同，但语义需保留这些字段。

### 5.3 TTS

原平台观察到：

```text
wss://openspeech.bytedance.com/api/v3/tts/bidirection
api_resource_id=seed-icl-2.0
```

还观察到角色音色和语音参数。

不在本文件中记录 `api_key`。本系统首期复用 SpeechTraining 现有 TTS，供应商通过适配器替换，前端只消费后端返回的音频 URL。

### 5.4 业务术语热词

原平台进入训练时请求：

```text
POST /utility/pro/words/pageList?offset=0&limit=500
```

用途是把企业专有词送入 ASR，例如产品缩写、部门术语和型号。

本系统把它列为语音质量优化项：

- 不阻塞文字训练。
- 语音训练首期可先使用通用 ASR。
- 后续增加“主题/企业术语表”输入，提升专有词识别。

## 6. 88.7 分通过报告

DSH-A 完成 6 轮、15 分钟训练后拿到 88.7 分报告。

| 维度 | 得分 | 权重 |
|---|---:|---:|
| 需求挖掘与倾听 | 92 | 40% |
| 价值主张传递 | 85 | 30% |
| 信任建立与亲和力 | 88 | 30% |
| 综合 | 88.7 | 通过线 70 |

总体评价：

> 展现了优秀的倾听能力和痛点挖掘技巧，但在应对客户新增需求时略显急躁，需加强闭环确认能力。

六轮目标进度：

| 轮次 | 关键行为 | 目标进度 |
|---|---|---:|
| 1 | 引出小单快反 | 10% |
| 2 | 追问换款停机时间 | 25% |
| 3 | 量化停机损失、追问参数来源 | 40% |
| 4 | 回应数据不准、提出免费体检 | 60% |
| 5 | 提出上门验证、询问时间 | 75% |
| 6 | 回答裁片管理问题 | 85% |

结论：

- 目标进度与沟通指南关键行为相关，不是按轮次线性增长。
- 到时、目标达成、最终通过必须拆成不同字段。
- 最终报告可在到时后仍因综合分达到通过线而通过。

## 7. 练习历程三种状态

DSH-A 实际得到三种状态：

| 状态 | 得分 | 用时 | 操作 |
|---|---:|---:|---|
| 已通过 | 88.7 | 15 分钟 | 查看报告 |
| 进行中 | 无 | 无 | 继续练习 |
| 未通过 | 0 | 1 分钟 | 查看报告 |

正式契约已使用显式状态和 attempt 状态表达，不依赖原平台含混的 `passed/studyStatus` 组合。

## 8. 原平台判定矛盾

当时超时弹窗显示“时间超限、未达成目标”，但最终报告显示：

- 已通过。
- 已达成。
- 88.7 分。

这说明原平台结束提示和最终报告之间存在时序/口径差异。

正式契约已经纠正：

- `timed_out`：是否到时。
- `target_reached`：AI 是否判定目标完成，并保存原因。
- `passed`：综合分是否达到通过线且满足通过规则。
- 主动退出和防作弊违规强制 `passed=false`。

## 9. 勘探踩坑

DSH 第一次尝试训练时给 `window.WebSocket` 打了构造器级 hook，导致页面收不到业务帧：

- AI 回复一直等待。
- 计时继续。
- 只能等 15 分钟超时。
- 同主题再次开始会被“有一场进行中的练习”拦截。

后续正确做法：

- 使用浏览器 CDP/Network 域抓 WS。
- 不替换页面 WebSocket 构造函数。
- 不通过注入层改变业务通道。

影响范围：仅后续勘探和浏览器自动化；对产品代码无要求。

## 10. 与正式契约的取舍

| DSH 证据 | 正式契约处理 |
|---|---|
| `randomScript` POST/GET | 不照抄；统一 attempt 准备和 AIGentService |
| `session-v2` 复用 conversationId | 不照抄；每次正式练习创建新 attempt |
| `drill_timer` 每 5 秒存储 | 不照抄；服务端 deadline 和暂停累计 |
| 火山 TTS 双 WS | 不照抄；复用 SpeechTraining 服务端适配器 |
| ASR 热词表 | 记录为后续语音质量优化项 |
| 教练点评 | 保留为训练模式能力 |
| 到时/目标/通过分开 | 已进入核心契约 |
| WS 注入踩坑 | 记录为勘探纪律 |

## 11. 当前保留的证据

已保留 6 张 DSH 代表截图：

- `原图/60-DSH-练习历程-默认.png`
- `原图/61-DSH-练习历程-三种状态.png`
- `原图/62-DSH-训练报告-通过.png`
- `原图/63-DSH-随机练习弹窗.png`
- `原图/64-DSH-训练运行.png`
- `原图/65-DSH-案例限时确认.png`

未恢复：

- DSH-A 的 4 份观察记录原文和 42 张截图。
- DSH-B 的 30 张截图、README 和 3 份原始抓包 JSON。
- 原平台测试 TTS `api_key`，按安全要求不恢复。

未恢复项不影响施工。本文件已把两路中会改变实现或验收的结论合并保留；原始截图和抓包如需重新用于审计，应从原平台重新采集并清洗，不能从 deja 文本恢复图片二进制。
