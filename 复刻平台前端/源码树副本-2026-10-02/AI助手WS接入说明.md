# AI 设计助手 · WS 接入说明（给前端同学）

> 版本：v1.0 ｜ 日期：2026-09-18 ｜ 相关：03-接口文档.md §2/§3、07-实现说明与偏差记录.md D2/D17
> 结论：**前端需要改的只有「接口基地址」与「开发/生产代理配置」两处，WS 相关代码逻辑不用动。**

---

## 1. 前因：为什么 WS 不能像 HTTP 那样直连网关

现在前端是这么连后端的（`src/api/request.ts`）：

```ts
export const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || 'http://localhost:8080/api'
```

`useAssistantWs.ts` 又由它推导 WS 地址：

```ts
/** 由 API 基地址推导 WS 地址：http(s)://host/api → ws(s)://host/api/act/ws/chat */
const base = API_BASE_URL.replace(/^http/i, 'ws').replace(/\/$/, '')
return `${base}/act/ws/chat?sessionId=${encodeURIComponent(sessionId)}`
```

于是浏览器会去连 `ws://localhost:8080/api/act/ws/chat`——也就是**网关**。问题是：

**网关（Spring Cloud Gateway Server WebMVC，servlet 版）不支持 WebSocket upgrade。** 依据是实证的，不是猜的：

- 它的 jar（`spring-cloud-gateway-server-webmvc:5.0.3`）里**没有任何 websocket / upgrade 相关类**；
- 它内置的 `RemoveHopByHopRequestHeadersFilter` 会把 `Connection`、`Upgrade` 这类**逐跳头剥掉**，握手请求到不了后端。

所以 WS 握手穿不过 8080。后端把 WS 端点实现在 `8082`（`/api/act/ws/chat`），已验证可用。**网关和后端都不改**（已由用户确认），走「前端同源代理」。

## 2. 怎么做：同源代理（开发期 Vite + 生产 Nginx）

思路：让浏览器只访问**前端自己的源**，由前端自己的开发服务器 / Nginx 把请求转发到后端。
好处是不动共享网关、浏览器侧只有一个源（无跨域）、以后上 HTTPS 也不会出现「https 页面连 ws://」的混合内容阻断，也不用把 8082 暴露给浏览器。

### 2.1 开发期：Vite 代理

`vite.config.ts` 加 `server.proxy`（贴到现有 `server` 配置里即可）：

```ts
server: {
  port: 3000,
  strictPort: false,
  proxy: {
    // WS 必须放在前面：同一前缀下先匹配更具体的规则
    '/api/act/ws': {
      target: 'ws://localhost:8082',
      ws: true,          // 关键：开启 WebSocket upgrade 转发，必须显式打开
      changeOrigin: true,
    },
    // 其余 HTTP 仍走网关
    '/api': {
      target: 'http://localhost:8080',
      changeOrigin: true,
    },
  },
},
```

> 注意 `ws: true`：Vite 用的 http-proxy 只有在显式开启后才会转发 `Upgrade` 握手，否则请求会被当普通 HTTP 处理并失败。

### 2.2 开发期：把接口基地址改成相对路径（**这一步不能省**）

```ts
// src/api/request.ts
export const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || '/api'
```

**为什么必须改**：`API_BASE_URL` 是绝对地址（`http://localhost:8080/api`）时，浏览器会**直连网关，完全绕过 Vite 代理**，代理配了也没用。改成相对 `/api` 之后：

- HTTP → `http://localhost:3000/api/...` → Vite 代理 → 网关 8080；
- WS → 由 `API_BASE_URL` 推导成 `ws://localhost:3000/api/act/ws/chat?...` → Vite 代理（`ws:true`）→ 后端 8082。

也就是说 **`useAssistantWs.ts` 现有的推导逻辑不用改**，改了基地址它就自然指向同源了。

> 如果不想动 `request.ts` 的默认值，等价做法是在 `.env.development` 里设 `VITE_API_BASE_URL=/api`。但**不要**为了 WS 单独硬编码 `ws://localhost:8082`——那样开发期能通、生产上 HTTPS 会被浏览器拦。

### 2.3 生产期：Nginx 转发（HTTP 走网关，WS 直连后端）

```nginx
server {
    listen 80;
    server_name your-host;

    location / {
        root /usr/share/nginx/html;   # 前端 dist
        try_files $uri $uri/ /index.html;
    }

    # WS：透传 upgrade 到后端 8082（网关不支持 WS，故不经网关）
    location /api/act/ws/ {
        proxy_pass http://<后端主机>:8082;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 3600s;      # 长连接：别让 Nginx 60s 默认超时把对话掐断
        proxy_send_timeout 3600s;
    }

    # 其余 HTTP：走网关 8080
    location /api/ {
        proxy_pass http://<网关主机>:8080;
        proxy_set_header Host $host;
    }
}
```

## 3. 验收自测（两分钟）

1. 改完配置重启 `npm run dev`；
2. 打开对话页 → 浏览器 DevTools → Network → 选 `WS` 过滤 → 应看到一条到
   `ws://localhost:3000/api/act/ws/chat?sessionId=...` 的连接，状态 **101 Switching Protocols**；
3. 点该连接看 Messages：
   - 发出：连接后自动发的 `common-session-start`（`type:"chat"`，`actionName:"common-session-start"`）；
   - 收到：`session-start → message-extra-info → message-start → part-start/part-content… → session-finish`，
     其中 `messageId` 形如 `xxxx_0`，`data.seq` 从 1 递增；
   - 约 20s 收到 `{"type":"ping","ts":...}`，前端回 `{"type":"pong"}`（这条 REST 服务端 80s 收不到 pong 会断开，靠现在的退避重连即可恢复）；
4. 也可直接用后端仓库里的脚本交叉验证（不依赖前端）：
   `node scripts/assistant-ws-smoke.mjs`（默认直连 8082；也可 `BASE=http://localhost:8080` 验证经网关的 HTTP 侧字段）。

## 4. 顺带要同步的两处协议细节

这两条是本轮后端新增/补充的，前端联调时会用到：

**(a) 材料上传要带 `sessionId`，否则不会触发解析**（03 §2.3 已更新）

```ts
// 原来的 POST /api/act/assistant/files（multipart 字段 file）
// 现在加一个查询参数：sessionId
POST /api/act/assistant/files?sessionId=<当前会话ID>
```

带上之后，后端会异步解析材料并推 `biz-common-parse-file` 两态事件（`files[].status` 0 解析中 → 1 完成），
材料也会自动进入 `artifact.materials`（右面板「培训材料」Tab 直接出现卡片）。
不带 `sessionId` 则只落盘返回 `fileId`（旧行为，兼容）。

**两态事件要用「同一个 context_id」原地更新卡片**，不要新增一条消息：

```json
{ "bizType":"biz-common-parse-file",
  "params": { "context_id":"c1...", "call_id":"k1...", "content":"正在解析材料《X》……",
              "files":[{"id":"<fileId>","name":"X.pptx","status":0}], "summary":"…(仅完成态)" } }
```

**(b)「学员可见」开关的写入 action**（03 §3.2 已定义，就是你们之前问的那个）

```json
{ "type":"chat", "payload": { "message": { "id":"<uuid>", "role":"user", "content": [
  { "type":"data", "data": { "type":"action",
    "actionName":"biz-side-manage-update-material",
    "params": { "id":"<artifactId>", "version":<versionNo>, "materialId":"<fileId>", "visibility":0 } } } ] } },
  "traceId":"<uuid>" }
```

- `visibility`：1 学员可见 / 0 内部可见（布尔 `true`/`false` 也接受）；
- 后端回推 `biz-side-manage-artifact-updated`，`params.content` 为
  `[{op:"full_replace", path:"/materials", value:[...完整 materials 数组]}]`，**以前端该事件回写为准**；
- `params.id`/`version` 是前端上下文，后端只用于日志提示，不作为定位依据（以服务端工作区为准）。

## 5. 常见坑

| 现象 | 原因 |
|------|------|
| WS 连不上，且地址是 `ws://localhost:8080/...` | `API_BASE_URL` 还是绝对地址 → 绕过代理直连网关（见 §2.2） |
| WS 连上后立刻断开 / 400 | 代理没开 `ws: true`（Upgrade 没转发） |
| 对话页无开场白 | 连接后没有发 `common-session-start` action（后端靠它触发编排智能体首答） |
| 生产上 HTTPS 下 WS 被拦（Mixed Content） | WS 地址被硬编码成 `ws://`；同源推导会自动变 `wss://`，别硬编码 |
| 长时间无响应后连接断开 | Nginx `proxy_read_timeout` 默认 60s；WS location 里调到 3600s（见 §2.3） |
| 上传 2.6MB 的 pptx 报错 | 后端已修（multipart 上限 50MB）；若仍报错说明后端版本不是最新 |