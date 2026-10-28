# 测练中心·题库管理 — Phase 1 勘察记录（逆向 + 抓包）

> 勘察时间：2026-10-12 ｜ 方式：浏览器自动化走查 + XHR 拦截抓包（只读操作，未触发任何写接口）
> 平台：train.chinajack.com（绚星云学习 SaaS 定制版）

## 0. 范围确认决策（2026-10-12 用户已拍板）

| 待定点 | 决策 |
|--------|------|
| QB-18 AI建题 | 2026-10-27 已迁到 AIGentService `exam-gen`；Dify 仅手动回退 |
| QB-26 权限粒度 | **共享范围（部门/人）纳入权限体系**：分类管理员 + 题库删除权限 + 共享范围三层 |
| QB-27 其余菜单 | 交由我定：**置灰展示（tooltip"建设中"）**——与在线课堂模块既往做法一致，避免死链接 |

## 0.1 Phase 2/3 第一批决策（2026-10-12）

| 项 | 决策 |
|----|------|
| 技术栈 | 前端 front-end 增 `views/admin/exam/` + `/exam` 路由段；后端**新建 ExamService 微服务**（用户自建空壳）+ 网关 `/api/exam/**` |
| 开源方案 | **从零自研**（UI 必须照抄原平台，开源前端全作废；核心难点全是空白区）；借鉴 lsgwr POI 导入模式（MIT）+ xzs JSON 存储思想（规避 AGPL） |
| 组合题存储 | **parent_id 自关联**（子题完整 question 行，复用题型组件；删除/换库级联处理） |
| 考核点关系 | **exam_question_point 多对多关联表**（原平台模板实证"最多5个考核点"；列表展示取主考核点） |
| 媒体存储 | **本地存储（服务器磁盘）**，不用 OSS——用户明确：部署到公司服务器时大型文件直接存服务器；本期只存原始文件前端直读，转码等真实需求再挂 |

### 第二批决策（FP-03~05，用户确认）

- 批量分享不做（语义混乱），批量=删除+修改分类+转移（统一转给一人）；单库分享走共享抽屉
- 其余方案照我提议执行（树组件复用/接口路径/权限三层/选人从 StaffManagement Dubbo 取）

## 1. 前端指纹

| 项 | 结论 | 证据 |
|----|------|------|
| 前端框架 | **Vue 2 SPA（hash 路由）** | hash 路由 `#/queslib/mgmt`；`el-popover__reference-wrapper` 类名 |
| UI 组件库 | **云学堂 yxt 自研组件库（Element-UI 兼容体系）** | `yxt-svg-icon`/`yxt-select`/`yxt-tooltip`/`yxt-tree-node`/`yxtbiz-funs-tree__node`/`yxtbiz-nav-top` 类名全站统一；混用 `el-popover` |
| 业务组件命名 | `yxtbiz-` 前缀 = 业务组件（funs-tree 功能树/nav-top 顶部导航） | DOM 结构 |
| 子应用架构 | 微前端：`/ote/` 独立 SPA（otepc bundle），宿主提供导航 | `stc1.yxt.com/fe-dist2/otepc/prod/` chunk |
| 真实 API 域 | `api-phx-ali.yunxuetang.cn`（云学堂 API 网关） | 全部 XHR |
| 鉴权 | Header `token`（JWT）+ `source`（来源标识，localStorage.sourceCode） | 重放请求实证：缺 token 报 `global.token.empty`，缺 source 报 `global.source.empty` |
| 错误结构 | `{code, globalCode, key, message, data, traceId}`，业务 code 7 位（2001002 token空/2002004 source空/2001017 无权限） | 重放实证 |

## 2. 已抓取真实接口契约（GET/POST 全部实证）

### 2.1 分类树
- **GET `/ote/lib/catalog/list`** → 分类树（嵌套 children）
  - 节点字段：`id/name/orgId/parentId/childCatalogQty/libQty/disabled/orderIndex/routingPath/createUserId/createFullname/createTime/updateUserId/updateTime/children/users/inheritParentAuth/childInheritParentId/childInheritCurrentAuth`
  - 根节点 id=`root`，name=默认题库分类；子分类 routingPath=`001`/`002`…（3位一级编码，层级递增推断）
- **GET `/ote/lib/catalog/{catalogId}`** → 分类详情（编辑抽屉用）
  - 含 `users[]` 管理员数组：`id/userName(工号)/fullname/deptId/deptName/positionName`
  - 权限继承三字段：`inheritParentAuth`（继承一级分类权限）/`childInheritParentId`/`childInheritCurrentAuth`（子分类继承当前分类）

### 2.2 题库
- **POST `/ote/lib/list?current=1&limit=10&orderby=updateTime&direction=desc`**（分页参数在 query，筛选在 body）
  - 请求体：`{queryType:1, keyword, keywordType:"0", catalogId:"root", routingPath:"", limit, current, orderby, direction, disabled:"", scope:0, userIds:[]}`
  - 响应 `datas[]`：`id/name/orgId/parentId/catalogId/catalogName/defaultLib/pointQty(考核点数)/totalQuesQty(试题数)/createUserId/createFullname/createUserName(工号)/updateFullname/updateTime/createTime/disabled/secrecy(1=保密)/shared/sharedUserId/sharedFullname/shareSourceType/shareOrgId/shareLibId/orgShareType`
- **GET `/ote/lib/{libId}`** → 题库详情（详情页基本信息区）：同上单对象 + `catDisabled`
- **GET `/ote/lib/{libId}/duplicate/condition`** → 查重条件状态：`{singleStatus,multiStatus,answerStatus,fillStatus,judgeStatus}`（1=该题型已开启查重，页面首次进入时刷新）

### 2.3 考核点
- **GET `/ote/lib/func/point/{libId}`** → 考核点列表（不分页）：`[{name, pointId, libId, defaultPoint}]`（defaultPoint=1 为"默认考点"，每库必有且唯一）

### 2.4 试题
- **POST `/ote/ques/list?limit=10&current=1&orderby=updateTime&direction=DESC`**
  - 请求体：`{libId, libName:"", keyWord, secrecy:"", _disabled:"", _status:"", _type:"", _levelType:"", pointId:"", isDuplicate:0, status:-1, disabled:-1, type:-1, levelType:-1}`（**isDuplicate=查重过滤标志**，印证"查重=列表过滤"）
  - 响应 `datas[]`：`id/summary(纯文本摘要)/quesType/status/type(题型)/levelType(难度)/score/disabled/pointId/pointName/pointNames/duplicate(查重重复标志)/libName/orderIndex/createUserId/createFullname/updateUserId/updateUserName/updateFullname/createTime/updateTime/shared/isMultiMediaType/subQuesSenior(组合题子题标志)/correctRate/sourceType`
- **GET `/ote/ques/{quesId}`** → 试题详情（编辑页/查看抽屉共用）：
  - 题干：`content`（HTML 实体富文本）/`summary`（纯文本）/`fileId`/`playDetails`（媒体播放对象）
  - 题型/难度：`type/quesType/levelType`
  - 选项：`questionItems[]`：`{id, itemContent, answer(0/1), orderIndex, itemPlay(选项媒体)}`
  - 判断题：`judgeAnswer/judgeCorrectOptionContent/judgeWrongOptionContent`
  - 问答/填空：`answerContent/answerPlay`
  - 解析：`explainText/explainPlay`
  - 计数：`totalAnswerQty/correctAnswerQty`
  - 其他：`itemCount/score/missScore/scoreType/status(2=已审核)/duplicate/noOrderMark(填空乱序标志)`

### 2.5 正确率
- **POST `/ote/ques/statistics?limit=10&current=1&orderby=correctRate&direction=DESC`**（按试题统计）
  - 请求体：`{libId, keyWord, _type, _levelType, type:-1, levelType:-1}`
  - 响应 `datas[]`：`{id, summary, type, levelType, quesType, usedQty(引用次数), totalAnswerQty, correctAnswerQty, correctRate(1.0000)}`
- **GET `/ote/lib/{libId}/point/ques/statistics?pointName=&limit=50&current=1&orderby=accuracyRate&direction=DESC`**（按考核点统计）
  - 响应数组：`{pointId, pointName, defaultPoint, quesQty, singleCorrectQty/singleSubmitQty, multiCorrectQty/multiSubmitQty, judge…, fillIn…, answer…, composite…, allCorrectQty/allSubmitQty, accuracyRate}`
- **GET `/ote/ques/{quesId}/statistics/detail?batchId=&arrId=`**（答题详情抽屉）：题干+选项+每选项答题人数/占比+答案/难度/正确率/解析

### 2.6 配置与权限
- **GET `/ote/udp/user/operate/permission?operateType=0`** → 当前用户操作权限
- **GET `/ote/config`** → 测练配置（各题型默认分值矩阵——字段设置模块用，本次只读不改）
- **GET `/core/orgparsetting/code?code=isOpenQuestionDetailExport`** → 导出开关
- **GET `/down/nfs/otepc?fileName=template%5C6.7%5Clevel3%5C导入试题模板.xlsx`** → 模板下载，返回 `{downloadUrl: CDN+auth_key}`（**异步下载模式：先取签名 URL 再下载**，浏览器有独立下载中心 `/down/#/download`）

### 2.7 写接口（未开火，按读接口风格+RESTful 惯例推断，文档中标注"推断，待验证"）
- 分类增删改/移动/禁用：POST/PUT/DELETE `/ote/lib/catalog...`
- 题库新建/编辑/启停/删除/共享/转移/修改分类/批量：POST/PUT/DELETE `/ote/lib...`
- 试题保存（保存/保存并新增）/删除/批量操作/换库/设置考核点：POST/PUT/DELETE `/ote/ques...`
- 考核点增删改：POST/PUT/DELETE `/ote/lib/func/point...`
- 导入上传：multipart POST（推断）

## 3. 枚举值实证

| 枚举 | 取值 | 证据 |
|------|------|------|
| 题型 type | 0=单选、多选/判断/填空/问答/组合 依次（1~5 推断） | 实体 type=0+界面单选；下拉顺序：单选/多选/判断/填空/问答/组合 |
| 难度 levelType | 0=易、1=中（截图数据有中）、2=难（推断） | 实体 levelType=0→界面"易"，levelType=1→"中" |
| 试题状态 status | 下拉：已保存/已提交/已审核/不通过；实体 status=2=已审核 | 前端下拉枚举实证 |
| 启用 disabled | 0=启用 1=禁用 | 启用列绿点+悬浮"禁用"文字 |
| 保密 secrecy | 0=公开 1=保密 | secrecy=1 → 界面橙色"保密"tag |
| 查重 duplicate | 0=正常 1=重复 | ques/list 响应 duplicate 字段 |
| 权限继承 | inheritParentAuth/childInheritCurrentAuth 0=未勾选 | 分类实体 |

## 4. 关键交互行为实证

1. **查重=列表过滤确认**：`/ote/ques/list` 请求体含 `isDuplicate` 标志 + `duplicate` 响应字段 + 详情页 `duplicate/condition` 接口——点击查重下拉题型后，列表以 isDuplicate=1 过滤，重复题标记 duplicate=1（用户口述的"列表过滤"理解正确，且**查重状态按题型记录在 duplicate/condition**）
2. **抽屉全预挂载**：试题查看/请选择题库/设置考核点/导入试题/编辑题库基本信息抽屉在详情页 DOM 预挂载（性能细节，复刻不必照搬）
3. **快速/AI建题同页 tab 切换**：URL 不变（#/queslib/quesmgmt/detail），纯前端 tab；生成试题为前端格式解析+校验，确定录入才调写接口
4. **媒体输入**：题干/选项/解析支持 itemPlay/playDetails/explainPlay 媒体对象；判断题/填空题仅文字（用户口述）
5. **删除权限**：题库列表"删除"对非创建者置灰（前端按 createUserId 比对 + 后端 permission 校验双层）
6. **模板下载走下载中心**：`/down/nfs/otepc?fileName=` 返回带 auth_key 的 CDN URL，浏览器下载中心可见记录

## 5. 导出模板结构（已实证，样例归档于 观察素材/导出样例/）

- Excel：5 Sheet 按题型分（单选/多选/填空/问答/判断），表头=题目/考核点/难度/试题解析/正确答案(或填空顺序/答案：关键词)/答案A~I；考核点最多5个英文`;`分隔；题干选项解析支持嵌图片（文字前图片后，jpg/png≤1M）；填空题 `_(n)_` 标空位
- Word：按题型分节段落式，`序号、题干`→`A、选项`→`【正确答案】`→`【难易度】`→`【考核点】`→`【试题解析】`
- E:\导入试题模板\ 下的官方模板与导出样例同构（导入导出同模板）

## 6. 未走查项（写操作类，不真实触发）

- 分类新建/删除/禁用/移动的确认弹窗与接口
- 题库新建/编辑/启停/共享/转移/修改分类/批量操作写接口
- 试题保存/删除/批量/换库/设置考核点写接口
- 导入上传与校验回显流程
- 快速选人/共享范围人员选择抽屉（公共选人组件，沿用之前模块做法）
