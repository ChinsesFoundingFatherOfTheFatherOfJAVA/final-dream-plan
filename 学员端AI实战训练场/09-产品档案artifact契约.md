# 产品档案 artifact 契约

> 版本：v1.0 ｜ 日期：2026-10-30
> 涉及：AI 设计助手 artifact、`ConfirmServiceImpl`、产品档案 CRUD、场景关联、发布快照、学员端详情。

机器可读文件：`schemas/product-profile-v1.schema.json`

## 1. 稳定标识

产品档案在两个平面出现：

- artifact 平面：使用稳定 `profileKey`。
- 数据库平面：使用内部 `id`，并保存同一 `profile_key`。

规则：

- `profileKey` 在主题生命周期内稳定，不因编辑名称或重新生成而变化。
- 新建时由 ACT 生成：`pp_` + 8~48 位 `[A-Za-z0-9_-]`。
- 场景引用使用 `relatedProductProfileKeys[]`。
- 旧 artifact 的 `relatedProductProfileArtifactIds[]` 仅作为迁移输入，读取时转换为 keys。
- 数据库唯一键：`theme_id + content_version_no + profile_key`。

## 2. Artifact JSON

### 2.1 产品档案

```json
{
  "profileKey": "pp_2FQ7A9K2",
  "profileName": "成套智联2.0智能化平台",
  "category": "服装智能制造软硬件一体化解决方案",
  "description": "杰克科技推出的智能化生产运营平台。",
  "customFields": [
    { "key": "品牌", "value": "杰克科技", "sortOrder": 1 },
    { "key": "产品状态", "value": "成熟商用", "sortOrder": 2 }
  ],
  "detailMarkdown": "## 产品概述\n……",
  "source": {
    "type": "ai_generated",
    "materialIds": ["kng_123"],
    "generatedBy": "product-profile-gen",
    "generatedAt": "2026-10-30 10:00:00"
  }
}
```

字段：

| 字段 | 类型 | 必填 | 限制 |
|---|---|---|---|
| profileKey | string | 是 | 稳定且主题内唯一 |
| profileName | string | 是 | 1~100 字 |
| category | string/null | 否 | 0~200 字 |
| description | string/null | 否 | 0~2000 字 |
| customFields | array | 否 | 最多 30 项 |
| detailMarkdown | string/null | 否 | 最多 50,000 字 |
| source.type | string | 是 | manual/ai_generated/imported |
| source.materialIds | string[] | 否 | 最多 20 个 |

`customFields[]`：

| 字段 | 类型 | 规则 |
|---|---|---|
| key | string | 去空白后 1~30 字，档案内唯一 |
| value | string | 0~1000 字 |
| sortOrder | int | 从 1 递增 |

### 2.2 artifact 顶级字段

```json
{
  "productProfiles": [],
  "scenarios": [
    {
      "id": "sc1",
      "relatedProductProfileKeys": ["pp_2FQ7A9K2"]
    }
  ]
}
```

校验：

- 每个 `profileKey` 不重复。
- 场景引用必须存在于同一 artifact 的 `productProfiles[]`。
- 删除仍被场景引用的档案时，后端拒绝并返回引用场景清单。
- 一个场景可关联 0~N 个档案。

## 3. 数据库映射

`act_product_profile`：

| DB 字段 | artifact 字段 |
|---|---|
| id | ACT 内部生成，不进入 artifact |
| theme_id | 当前主题 |
| content_version_no | 0=工作内容；>0=发布版本 |
| profile_key | profileKey |
| profile_name | profileName |
| category | category |
| description | description |
| detail_markdown | detailMarkdown |
| custom_fields | JSON 数组，保持顺序 |
| source_artifact_id/version | 当前 artifact 来源 |

场景关联写 `act_scenario_product_profile`，发布快照时随场景/内容版本复制。

## 4. 工作区与发布语义

### 4.1 首次发布前

- artifact 编辑和“确认”只更新工作内容。
- 产品档案写入 `content_version_no=0`。
- `published_version_no` 保持 null。
- 用户版本历史不显示 v0。

### 4.2 首次发布

- 校验工作产品档案和场景引用。
- 创建 `v1`。
- 将 `content_version_no=0` 的产品档案复制到 `v1`。
- 复制场景关联。

### 4.3 已发布后的 AI 确认

- 在事务中创建下一内容版本。
- 将工作 artifact 的产品档案固化为该版本行。
- 场景关联同步复制。
- 原子切换 `published_version_no`。

### 4.4 CRUD

- 工作内容编辑写 v0/working artifact。
- 已发布主题的用户编辑也先进入工作内容；只有 AI 主“确认”才发布新版本。
- 不允许直接改写已发布版本的历史行。

## 5. 产品档案生成接口

### 5.1 管理端接口

`POST /api/act/admin/theme/{themeId}/product-profiles/generate`

请求：

```json
{
  "materialIds": ["kng_123", "file_456"],
  "profileNameHint": "成套智联2.0",
  "instructions": "突出软硬件一体化、典型客户和实施边界",
  "customFieldKeys": ["品牌", "产品状态", "核心价值"]
}
```

规则：

- 最多 5 个材料。
- 候选结果只返回，不自动保存。
- 管理员编辑后调用创建/更新接口。
- 生成失败不影响已有产品档案。

响应：

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "candidates": [
      {
        "profileKey": "pp_candidate_123",
        "profileName": "成套智联2.0智能化平台",
        "category": "服装智能制造软硬件一体化解决方案",
        "description": "...",
        "customFields": [],
        "detailMarkdown": "## 产品概述\n...",
        "source": {
          "type": "ai_generated",
          "materialIds": ["kng_123"],
          "generatedBy": "product-profile-gen"
        }
      }
    ],
    "warnings": []
  }
}
```

### 5.2 AIGentService 内部任务

`POST /internal/agent/task/product-profile-gen`

`inputs`：

| key | 值 |
|---|---|
| `theme_id` | 主题 |
| `profile_name_hint` | 名称提示 |
| `instructions` | 用户要求 |
| `custom_field_keys_json` | 自定义字段 key 数组 JSON |
| `materials_json` | 材料名称、摘要、来源 JSON |
| `existing_profiles_json` | 已有档案摘要，供避免重复 |

`outputs`：

```json
{
  "profile_schema_version": "product-profile-v1",
  "profiles_json": "[...]",
  "success": "true"
}
```

生成输出必须符合本文 §2.1 结构。

## 6. 校验器

新增 `ProductProfileSchemaValidator`：

- 必填字段。
- `profileKey` 格式和唯一性。
- 自定义字段 key 唯一。
- Markdown 长度。
- 场景引用完整性。
- 产品档案最多 20 个/主题。
- 单个材料源最多 20 个。

校验失败：

- 手工编辑：返回字段级错误，不写 artifact。
- AI 生成：将错误摘要回传生成任务，重试 1 次。
- 主确认：校验失败阻止确认/发布。

## 7. 学员端

`GET /api/act/student/product-profiles/{profileId}` 只读取当前 published snapshot。

返回：

```json
{
  "id": "db-profile-id",
  "profileKey": "pp_2FQ7A9K2",
  "profileName": "成套智联2.0智能化平台",
  "category": "服装智能制造软硬件一体化解决方案",
  "description": "...",
  "customFields": [
    { "key": "品牌", "value": "杰克科技", "sortOrder": 1 }
  ],
  "detailMarkdown": "## 产品概述..."
}
```

不返回：

- working artifact id。
- 内部数据库版本。
- 来源材料全文。
- 其他主题档案。

## 8. 验收

- 场景只能引用存在的 profileKey。
- 编辑档案名不改变 profileKey，也不打断场景关联。
- 发布后修改工作档案不影响线上学员。
- AI 主确认后新版本立即发布并切换学员可见内容。
- 产品档案删除被引用时阻止。
- 学员跨主题访问档案返回 403。
