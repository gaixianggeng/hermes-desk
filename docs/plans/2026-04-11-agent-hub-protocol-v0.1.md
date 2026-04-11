# Agent Hub 协议与状态机 v0.1

> **目标**：统一 Agent Hub 在 Phase 0 / Phase 1 的对象模型、消息协议、状态机与能力边界  
> **适用范围**：Mac-first、Hermes-only、本机通信优先  
> **原则**：先把 UI/协议内部模型统一，再决定外部远程协议与多端同步

---

## 1. 设计原则

1. **任务是第一实体**，不是会话消息列表
2. **事件驱动 UI**，不是前端自己猜消息语义
3. **动作由能力驱动**，不是所有任务都默认支持同样控制按钮
4. **结果必须结构化沉淀**，不能只有消息尾巴
5. **错误和确认必须显式建模**

---

## 2. 对象模型

## 2.1 Task
表示一个用户发起并由 Hermes 执行的任务。

### 字段
| 字段 | 类型 | 说明 |
|---|---|---|
| `task_id` | string | 全局唯一 ID |
| `title` | string | 用户可读标题 |
| `source` | enum | `manual` / `shortcut` / `scheduled` / `restored` |
| `agent_id` | string | 当前固定为 Hermes |
| `session_id` | string? | Hermes 会话 ID |
| `run_id` | string? | Hermes run ID |
| `created_at` | datetime | 创建时间 |
| `updated_at` | datetime | 最近更新时间 |
| `state` | TaskState | 当前状态 |
| `current_summary` | string | 当前任务一句话摘要 |
| `available_actions` | [TaskAction] | 当前可执行动作 |
| `artifact` | Artifact? | 最终结果物 |

## 2.2 RunState
表示任务运行时的状态信息。

### 字段
| 字段 | 类型 | 说明 |
|---|---|---|
| `state` | TaskState | 当前状态 |
| `phase_label` | string | 如“读取代码”“等待确认”“重试中” |
| `last_event_at` | datetime | 最近事件时间 |
| `progress_hint` | string? | 文本进度提示，不做百分比 |
| `failure_category` | FailureCategory? | 失败分类 |
| `failure_message` | string? | 人话错误摘要 |
| `waiting_reason` | string? | 等待原因 |

## 2.3 ApprovalRequest
表示任务执行过程中需要人工确认的决策点。

### 字段
| 字段 | 类型 | 说明 |
|---|---|---|
| `approval_id` | string | 全局唯一 ID |
| `task_id` | string | 所属任务 |
| `severity` | enum | `normal` / `high` / `critical` |
| `title` | string | 一句人话描述 |
| `reason` | string | 为什么需要确认 |
| `evidence` | [EvidenceItem] | 命令 / patch / path / diff 摘要 |
| `options` | [ApprovalOption] | 可选动作 |
| `timeout_at` | datetime? | 超时时间 |
| `status` | enum | `pending` / `approved` / `rejected` / `expired` |
| `decided_at` | datetime? | 决策时间 |

## 2.4 Artifact
表示任务完成后可回看的结构化产物。

### 字段
| 字段 | 类型 | 说明 |
|---|---|---|
| `summary` | string | 最终摘要 |
| `key_outputs` | [string] | 核心结果条目 |
| `files` | [FileRef] | 相关文件/路径 |
| `diff_summary` | string? | 变更摘要 |
| `next_actions` | [string] | 建议后续动作 |
| `raw_result_ref` | string? | 指向原始结果或日志 |

## 2.5 AgentCapability
表示底层 Agent 当前支持的控制能力。

| 字段 | 类型 | 说明 |
|---|---|---|
| `can_stop` | bool | 是否支持终止 |
| `can_retry` | bool | 是否支持重试 |
| `can_pause` | bool | 是否支持暂停 |
| `can_resume` | bool | 是否支持继续 |
| `can_request_approval` | bool | 是否支持确认流 |
| `can_emit_result` | bool | 是否支持结构化结果 |
| `can_open_workspace` | bool | 是否支持打开本机工作区 |

---

## 3. 枚举定义

## 3.1 TaskState
- `queued`
- `running`
- `waiting_user`
- `paused`
- `failed`
- `succeeded`
- `cancelled`

## 3.2 TaskAction
- `approve_once`
- `approve_for_task`
- `reject`
- `retry`
- `resume`
- `pause`
- `stop`
- `open_terminal`
- `open_workspace`
- `copy_result`

## 3.3 EventType
- `state_change`
- `output`
- `step`
- `confirm`
- `error`
- `result`
- `log`
- `clarify`

## 3.4 FailureCategory
- `connection_error`
- `tool_error`
- `approval_rejected`
- `approval_expired`
- `validation_error`
- `dependency_error`
- `unknown_error`

## 3.5 EvidenceType
- `command`
- `patch`
- `diff_summary`
- `path_list`
- `raw_log_excerpt`

---

## 4. 事件模型

## 4.1 通用事件信封（内部标准）
```json
{
  "version": "0.1",
  "event_id": "evt_xxx",
  "agent_id": "hermes",
  "task_id": "task_xxx",
  "session_id": "sess_xxx",
  "run_id": "run_xxx",
  "type": "state_change",
  "seq": 12,
  "timestamp": "2026-04-11T23:10:00Z",
  "payload": {},
  "capability_snapshot": {
    "can_stop": true,
    "can_retry": true,
    "can_pause": false,
    "can_resume": false,
    "can_request_approval": true,
    "can_emit_result": true,
    "can_open_workspace": true
  }
}
```

### 字段说明
| 字段 | 含义 |
|---|---|
| `version` | 协议版本 |
| `event_id` | 事件唯一 ID |
| `seq` | 同一任务内递增序号，便于去重和排序 |
| `payload` | 事件具体内容 |
| `capability_snapshot` | 当下能力快照，用于 UI 决定按钮显示 |

---

## 5. 事件类型定义

## 5.1 `state_change`
表示任务状态切换。

### payload
```json
{
  "from": "running",
  "to": "waiting_user",
  "phase_label": "等待你确认删除文件",
  "summary": "任务请求执行危险 shell 操作"
}
```

## 5.2 `output`
表示用户默认应该看到的关键输出。

### payload
```json
{
  "text": "已完成代码扫描，发现 3 个问题",
  "importance": "high"
}
```

## 5.3 `step`
表示执行过程中的阶段性步骤，默认折叠展示。

### payload
```json
{
  "label": "正在读取 gateway/platforms/api_server.py",
  "kind": "tool_read",
  "status": "completed"
}
```

## 5.4 `confirm`
表示需要人工确认的动作。

### payload
```json
{
  "approval_id": "apr_123",
  "severity": "high",
  "title": "Agent 想删除 4 个文件并执行 git clean",
  "reason": "该操作不可逆，且会改变当前工作区",
  "evidence": [
    {
      "type": "command",
      "title": "将要执行的命令",
      "content": "git clean -fd"
    }
  ],
  "options": [
    {"action": "approve_once", "label": "允许一次"},
    {"action": "reject", "label": "拒绝"}
  ],
  "timeout_at": "2026-04-11T23:20:00Z"
}
```

## 5.5 `error`
表示错误或失败信息。

### payload
```json
{
  "category": "tool_error",
  "title": "运行 git diff 失败",
  "message": "exit code 128：not a git repository",
  "recoverable": true,
  "suggested_actions": ["retry", "open_terminal"]
}
```

## 5.6 `result`
表示任务完成后的结构化结果。

### payload
```json
{
  "summary": "已完成 Agent Hub PRD 草稿",
  "key_outputs": [
    "输出 PRD v1",
    "统一协议 v0.1",
    "确定 Mac-first 路线"
  ],
  "files": [
    {"path": "docs/plans/2026-04-11-agent-hub-prd-v1-mac-first.md"}
  ],
  "next_actions": [
    "开始搭建 Mac MenuBar 原型",
    "先接 Hermes /health 与 chat/completions"
  ]
}
```

## 5.7 `log`
仅供开发者模式或调试区使用，不进入默认主视图。

## 5.8 `clarify`
表示 Agent 缺少用户输入或需要补充信息。

### payload
```json
{
  "question": "你希望输出文档放到 cache/documents 还是仓库 docs/plans？",
  "suggested_choices": ["仓库 docs/plans", "cache/documents"]
}
```

---

## 6. UI 映射规则

| 事件类型 | MenuBar | Task Detail | 默认策略 |
|---|---|---|---|
| `state_change` | 展示摘要 | 展示 | 高优先级 |
| `output` | 可展示摘要 | 展示 | 默认可见 |
| `step` | 只显示最近 1 条 | 折叠展示 | 默认折叠 |
| `confirm` | 进入 Inbox 顶部 | 强展示 | 强提醒 |
| `error` | 进入 Inbox 顶部 | 展示 | 强提醒 |
| `result` | 进入 Recent | 展示 | 强展示 |
| `log` | 隐藏 | Debug 区可见 | 默认隐藏 |
| `clarify` | 进入 Inbox 顶部 | 展示 | 高优先级 |

---

## 7. 状态机

## 7.1 状态流转
```text
queued -> running
running -> waiting_user
waiting_user -> running
running -> paused
paused -> running
running -> failed
waiting_user -> failed
failed -> running
running -> cancelled
paused -> cancelled
running -> succeeded
```

## 7.2 状态流转表
| 当前状态 | 可迁移到 | 条件 |
|---|---|---|
| `queued` | `running`, `cancelled` | 开始执行 / 用户取消 |
| `running` | `waiting_user`, `paused`, `failed`, `cancelled`, `succeeded` | 取决于事件 |
| `waiting_user` | `running`, `failed`, `cancelled` | 用户批准 / 拒绝或超时 / 用户取消 |
| `paused` | `running`, `cancelled` | 恢复 / 用户取消 |
| `failed` | `running`, `cancelled` | 重试 / 放弃 |
| `succeeded` | - | 终态 |
| `cancelled` | - | 终态 |

## 7.3 状态不变量
1. `waiting_user` 状态下必须存在未决 ApprovalRequest
2. `failed` 状态下必须有 failure category 和 failure message
3. `succeeded` 状态下应尽量生成 Artifact
4. UI 仅渲染 capability 支持的动作按钮

---

## 8. 动作与能力矩阵

| 动作 | 依赖能力 | 适用状态 |
|---|---|---|
| `approve_once` | `can_request_approval` | `waiting_user` |
| `approve_for_task` | `can_request_approval` | `waiting_user` |
| `reject` | `can_request_approval` | `waiting_user` |
| `retry` | `can_retry` | `failed` |
| `pause` | `can_pause` | `running` |
| `resume` | `can_resume` | `paused` |
| `stop` | `can_stop` | `running`, `paused`, `waiting_user` |
| `open_workspace` | `can_open_workspace` | 任意 |
| `copy_result` | `can_emit_result` | `succeeded` |

---

## 9. 失败恢复模型

## 9.1 失败分类与建议动作
| 分类 | 含义 | 默认建议 |
|---|---|---|
| `connection_error` | Hermes 不在线/网络断开 | reconnect, diagnostics |
| `tool_error` | 工具执行失败 | retry, open_terminal |
| `approval_rejected` | 用户明确拒绝 | stop, edit_then_retry |
| `approval_expired` | 确认超时 | retry, reject |
| `validation_error` | 输入不足/参数不全 | clarify |
| `dependency_error` | 外部 API / 凭证 / 权限问题 | open_logs, diagnostics |
| `unknown_error` | 未分类错误 | open_terminal, open_logs |

## 9.2 恢复原则
1. 失败不能只有 toast，必须有明确恢复动作
2. 未确认的危险动作不能自动重放
3. UI 中必须看得出是“整任务重试”还是“从最近失败点恢复”（如果 Hermes 底层未来支持）

---

## 10. Phase 0 / 1 协议落地建议

## 10.1 Phase 0
- 优先接 Hermes：
  - `GET /health`
  - `POST /v1/chat/completions`（stream=true）
  - `X-Hermes-Session-Id`
- 先在客户端内部构造 Task/Event 模型
- 先做最小 confirm / error / result 映射

## 10.2 Phase 1
- 评估接入：
  - `POST /v1/runs`
  - `GET /v1/runs/{run_id}/events`
- 把 Timeline 从“聊天事件”提升为“运行生命周期事件”
- 提升失败恢复与 step 细粒度可视化

---

## 11. 本期不做的协议项
1. 多设备同步协议
2. 端到端移动端签名协议
3. P2P 节点发现
4. 多 Agent 统一外部开放协议

这些都不属于 v0.1 的必要条件。

