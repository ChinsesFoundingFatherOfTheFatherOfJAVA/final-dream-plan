# 测练中心·试卷管理 — Phase 1 勘察记录（实操 + 抓包）

> 勘察时间：2026-10-13 ｜ 方式：浏览器自动化实操（用户授权操作 test-随机出卷/test-固定出卷，含发布）
> 平台：train.chinajack.com/ote（API 域 api-phx-ali.yunxuetang.cn，鉴权 token+source 同题库模块）

## 0. Phase 3 第一批决策（2026-10-13 用户确认）

- 策略存储：整条策略 JSON 存 setting_count 列，单元格失焦 PUT 单元格数据后端合并写整条
- 大题分组：后端只存 section_index=题型值，中文编号前端按大题出现顺序动态渲染
- FP-01 数据模型/FP-02 同源写入/FP-03 共享（已发布才可共享）方案照提议执行

## 1. 已实证接口

### 1.1 列表与分类
- **POST `/ote/exam/list?limit=10&orderby=updateTime&direction=desc`**（筛选 body）
  - 实体：`id/name/catalogName/buildType(0固定1随机)/status(0已保存4已发布)/disabled/totalScore/secrecy/usedQty(引用次数)/createUserId/createFullname/createUserName/updateTime/shared/examType/hasSeniorQues` ——**试卷状态简化两态实证合理**（原平台还有 1/2/3 审核中间态，均已走 needCheck=false 旁路）
- **GET `/ote/exam/catalog/list`**：试卷分类树（结构与题库 catalog 完全同构，根=默认试卷分类）
- **GET `/ote/udp/user/operate/permission?operateType=1`**（试卷操作权限；题库是 operateType=0）

### 1.2 详情与试题
- **GET `/ote/exam/{id}`** 与 **GET `/ote/exam/{id}/shared`**（详情变体，同构）：含 `buildType/quesMode/status/totalScore/totalQuesQty/secrecy/usedQty`
- **POST `/ote/exam/{id}/quesList`**（管理页试题列表）：query 全参数（examId/summary/type/levelType/status/currentpage/limit），body 空
  - 响应项含 libId/libName/pointId/pointName/type/levelType/score/content/summary/quesItemList
- **GET `/ote/exam/{id}/edit`**（固定卷题目结构）：`[{quesList:[...题目实体]}]` 按大题分组数组

### 1.3 随机出卷策略（examAutoQuestionSetting）
- **GET `/ote/exam/strategy/{examId}`**：策略数组，每库一条：
  ```
  { examId, libId, libName, selectedSourceType(0按题库), selectedPointIds("1"=全部考核点),
    settingCount: [ // 每难度 levelType 0/1/2 一条
      { levelType, singleQty, multiQty, judgeQty, fillQty, qaQty, needQty(数量模式),
        singleMaxQty, multiMaxQty, judgeMaxQty, fillMaxQty, qaMaxQty, maxQty,  // 库存上限
        singleScore, multiScore, multiMissScore, multiMissScoreType, judgeScore, fillScore, qaScore } ],
    catalogName, quesQty }
  ```
- **GET `/ote/exam/strategy/{examId}/source`**：已选抽题来源
- **POST `/ote/exam/strategy/{examId}/setexamlibpoint`**：`{questionLibs:[{libId,libName,parentId,parentName,nodeData:{完整树节点}}], selectedSourceType}`（按题库/按考核点共用，多选）
- **PUT `/ote/exam/strategy/{examId}/updatecount/{libId}`**：`{levelType, qty, type, indicatorId}` —— 题数单元格级更新（题型+难度模式 type=0写singleQty；数量模式写 needQty）
- **PUT `/ote/exam/strategy/{examId}/updatescore`**：`{levelType, score, missScore, missScoreType, type}` —— 分值单元格级更新
- **PUT `/ote/exam/{examId}/changeQuesMode?quesMode=N`**：0=题型+难度 1=题型 2=难度 3=数量（radio 顺序）
- **辅助**：`GET /ote/lib/lib/point/tree`（抽屉题库-考核点树：label/totalQuesQty/children=考核点）、`GET /ote/lib/catalog/list/select`（选择用分类树）、`GET /ote/lib/default_lib`、`GET /ote/config/examscore`（默认分值矩阵）

### 1.4 固定出卷（quickmt）
- **POST `/ote/ques/add`**（题目保存，body 含 examId/isEdit + 完整题目实体：content/summary/type/levelType/score/questionItems[{itemContent,answer,orderIndex,itemPlay}]）
  - **重要架构语义：响应 libId=默认题库——固定卷题目保存时直接写入所属题库**（试卷题目与题库试题同源；题库选择在卡片"题目设置"区，默认=默认题库）
- 修改复用同接口（isEdit=true + id）
- 题目编辑卡片含**题目设置区**：此题分值（满分N分）/题库/难度级别/考核点 + 确定取消 —— 比题库快速建题卡片多分值与题库归属设置

### 1.5 发布
- **POST `/ote/exam/{id}/publish`**（无 body，确认弹窗"您确认发布该试卷吗？"）
  - 校验链错误码实证：`2151045 请先设置策略或添加试题` → `2151048 请先设置分值`
  - 成功后页面重载进只读态

## 2. 关键行为实证（实操验证）

| # | 行为 | 实证结论 |
|---|------|----------|
| 1 | 抽题方式切换 | radio 切换即调 changeQuesMode 持久化；矩阵维度随之变化（题型×难度 / 题型列 / 难度列 / 单数量列） |
| 2 | 抽题来源多选 | 选全部题库实证；"按自选试题"入口在已选题库/考核点存在时禁用（用户口述一致） |
| 3 | 策略单元格保存 | 题数/分值输入即触发 updatecount/updatescore（失焦即存，自动保存） |
| 4 | 大题自动编号 | 点单选题→"一、单选题（本题共0小题，共0分）"；点多选题→"二、多选题"；再点单选题→编辑卡片进入已有"一、单选题"组末尾（不新建组）——用户描述完全正确 |
| 5 | 卡片校验链 | 确定按钮内联校验：至少设置一个正确选项 → 分数必须大于0（逐项递进显示） |
| 6 | 发布后随机卷 | 顶部仅"预览/导出"（无发布）；101 个输入框 96 个 disabled；radio 保留展示；策略数据完整可见 |
| 7 | 发布后固定卷 | 顶部变"**同步试卷至考试**/预览/导出"（新发现：同步按钮）；**左栏选择题型面板整体隐藏**；题目卡片可点击展开，题干/选项/答案/解析+媒体三模式可编辑，"题目设置"区不再出现（分值/题库/难度/考核点不可改）；修改自动保存生效（实证改题干成功） |
| 8 | 试卷状态 | status 0=已保存 4=已发布（简化两态合理；原平台 1/2/3 为审核中间态，本租户 needCheck=false 不出现） |

## 3. 写接口（未触发，按 RESTful 对称推断，文档标注"推断"）

- 试卷 CRUD：POST/PUT/DELETE `/ote/exam...`（创建/编辑基本信息/删除/转移/修改分类/启停/批量）
- 引用次数抽屉：GET 试卷被考试引用列表（截图24：名称/类型=考试/创建人/创建时间/来源[课程安排|单独安排]/状态[进行中]）
- 快速出卷导入：multipart（模板=归档的试卷导入模板.xlsx，结构见 00 口述）
- 导出：GET 文件流（Excel/Word）
- 同步试卷至考试：POST（发布后固定卷新按钮，二期考试模块联动）

## 4. 与题库管理模块的复用/差异清单

**直接复用**：分类树组件（数据源换试卷分类）、启停列、更多菜单的删除/转移/修改分类抽屉、选人抽屉、确认弹窗、快速建题卡片表单（六题型）、媒体三模式。

**差异点（新开发）**：
1. 出卷方式双形态编辑页（随机=策略矩阵 / 固定=大题分组画布）——全新页面
2. 抽题策略引擎（矩阵渲染 + 单元格保存 + 上限约束计算）
3. 大题分组画布（自动编号/分组追加/拖拽排序大题与小题/右侧概览联动滚动）
4. 快速设置全部分数/设置策略/快速抽题抽屉
5. 发布流（校验链 + 双形态发布后只读规则）
6. 管理页跨模块链接（试题名→题库详情带quesId；所属题库→题库管理页）
7. 引用次数抽屉（考试数据回填——考试模块未建，同正确率策略：轻量表+种子）
