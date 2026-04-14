# Hermes Desk Context Compression & Next Steps

> 当前长上下文压缩版，供后续连续开发直接复用。

## 一句话产品结论
Hermes Desk 不是纯聊天壳，也不是纯任务监控软件；它应是 **task-first 的 Hermes Mac 工作台**：
- 左栏：Task Navigator（agent strip + 进行中/归档 + task list）
- 中栏：Task Workspace（chat / 主要结果 / composer）
- 右栏：Execution Inspector（状态 / 步骤 / 日志 / approval / recovery）

## 已确定的信息架构
### 顶层对象
- **Task**：用户看到的稳定工作对象 / workspace
- **Session / Message**：Hermes 已有的真实对话层
- **Run / Event**：Hermes 已有的执行过程层

### 正确关系
- `Task > Session > Message`
- `Task > Run > Event`

## 已确认的技术结论
### 1. 不要另起一套 Mac 专用聊天结构
应该直接复用 Hermes 已有：
- `SessionDB.sessions`
- `SessionDB.messages`
- `session_id`
- `parent_session_id`
- `tool_calls / reasoning`

### 2. `/v1/runs/events` 只能做执行态直播
它适合：
- tool started/completed
- approval requested/resolved
- run completed/failed
- live delta

不适合：
- 作为 durable chat transcript 主真相源

### 3. SessionStore 不是 Mac 顶层模型
`gateway/session.py` 更适合复用在：
- 来源解析
- session_key 归并
- gateway-linked task 的当前 session 映射

而不适合直接充当 Mac 的 Task 模型。

## 当前代码状态
### 已完成
- 三栏 Workspace UI 骨架已落地
- 左栏 task 过滤 / 中栏 workspace / 右栏 inspector 已重构
- Hermes `/v1/runs` + `/events` + `/actions` 已接通
- 当前任务模型里已保留 `requestText`
- 本地版已通过 `HermesLocalTranscriptStore` 直接读取 `~/.hermes/state.db/messages`
- 中栏已优先展示 Hermes 真实 transcript message timeline
- 同一 task 下的 follow-up 已复用同一 session 发起新 run
- `Task` 已增加 `rootSessionID / currentSessionID / effectiveSessionID / sessionLineage`
- App 启动 / 选中 task / run 结束后，会做本地 session binding reconcile
- 中栏 transcript 已能按 `sessionLineage` 聚合多段 session 消息，而不只读当前 leaf session
- 中栏已新增 `Task brief`，并把 tool transcript 聚合成 `Tool activity`，避免滑向纯聊天壳或纯日志墙

### 当前缺口
- Task 还没有更正式的 lineage 可视化与 branch / continuation 历史投影
- 中栏 transcript 还需要继续细化 user / assistant / tool / clarify / result 的分层呈现
- 目前本地版仍是直读 `state.db`，尚未切到正式 Session Query API

## 三方最终技术方案
### 方案核心
1. **Task-first UI 不变**
2. 中栏对话直接接入 Hermes `session/message`
3. 右栏继续使用 `run/event`
4. Mac 侧增加 `task -> current_session_id` 绑定
5. 后续补 Session Query API；在本地版本里可先直接读 `~/.hermes/state.db`

## 当前实施顺序
### Slice 1（现在继续做）
- 在 `HermesKit` 增加本地 transcript 读取能力（直接读 `state.db`）
- 在 `AgentBackend` 暴露 `fetchSessionMessages(sessionID:)`
- `AppStateStore` 缓存并刷新 session transcript
- `DashboardView` 中栏优先展示 transcript message timeline
- follow-up 尽量复用同一 task / 同一 session

### Slice 2
- Task 增加 `root_session_id / current_session_id / lineage` 抽象
- 中栏明确区分 user / assistant / tool / clarify / result
- 右栏继续收敛为 execution inspector

### Slice 3
- 在 Hermes API Server 补正式 Session Query API
- 替换本地直读 `state.db` 的桥接方式
- 支持 gateway-linked task 打开已有飞书/TG session

## 这轮开发的验收标准
- 同一 task 下发送 follow-up 后，中栏能看到连续 user / assistant 消息
- 中栏 message timeline 主要来自 transcript，而不是 task summary 硬凑
- 右栏仍保留 approval / failure / reconnect / steps
- 测试通过，Xcode build 通过
