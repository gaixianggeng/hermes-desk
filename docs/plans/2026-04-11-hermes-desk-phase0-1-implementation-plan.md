# Hermes Desk Phase 0 / Phase 1 实施计划（Mac 原生 + Hermes Adapter）

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** 以 Mac 原生方式完成 Hermes Desk 的 Phase 0 / Phase 1：先做一个程序员愿意长期使用的 MenuBar 监督控制面，只接 Hermes，一个阶段一个闭环。

**Architecture:** 客户端使用 SwiftUI + MenuBarExtra + 少量 AppKit 桥接；本机通过 Hermes 现有 API Server（127.0.0.1 HTTP + SSE）通信；服务生命周期优先复用 Hermes 现有 launchd 能力，不额外重做守护进程系统。

**Tech Stack:** SwiftUI, Swift Concurrency, URLSession, OSLog, Keychain, Hermes API Server, macOS launchd

---

## 0. 实施前明确决策

### 已知事实
- Hermes 已存在 API server、health endpoint、SSE、runs/events、launchd 管理
- 用户已明确只接 Hermes，只做 Mac 原生，不追求首版视觉 polish
- Phase 0 / 1 以“自己先用得爽”为首要目标

### 实施决策
1. **形态选型**：MenuBarExtra + 独立 utility window
2. **通信选型**：127.0.0.1 HTTP + SSE
3. **工程范围**：Phase 0 做可用闭环；Phase 1 做历史、诊断、增强恢复
4. **架构边界**：产品上只支持 Hermes；代码上保留薄接口，不做大而全多 Adapter 框架

---

## 1. 推荐仓库结构

建议新建独立仓库（便于将来继续做 iPhone 端复用），推荐结构：

```text
hermes-desk/
├── apps/
│   └── mac/HermesDeskApp/
│       ├── HermesDeskApp.swift
│       ├── AppShell/
│       ├── Features/
│       ├── Resources/
│       └── SupportingFiles/
├── Packages/
│   ├── AppCore/
│   │   ├── Sources/AppCore/
│   │   └── Tests/AppCoreTests/
│   └── HermesKit/
│       ├── Sources/HermesKit/
│       └── Tests/HermesKitTests/
├── Docs/
│   └── ADRs/
└── Scripts/
```

### 包职责
| 包 | 职责 |
|---|---|
| `AppCore` | UI 状态、Task 模型、页面级 ViewModel、诊断状态 |
| `HermesKit` | 与 Hermes API Server 的 HTTP/SSE 通信、health、模型转换 |

如果想先极简，也可以先做单 target，但仍建议按目录保持可演化性。

---

## 2. 模块划分

## 2.1 AppShell
**职责**：App 生命周期、MenuBar、窗口管理、Settings 入口

**建议文件**：
- `apps/mac/HermesDeskApp/HermesDeskApp.swift`
- `apps/mac/HermesDeskApp/AppShell/MenuBarScene.swift`
- `apps/mac/HermesDeskApp/AppShell/WindowRouter.swift`
- `apps/mac/HermesDeskApp/AppShell/SettingsScene.swift`

## 2.2 Feature：Inbox / Task Detail / Confirm / Diagnostics
**职责**：核心页面和交互逻辑

**建议文件**：
- `Features/Inbox/InboxView.swift`
- `Features/Inbox/InboxViewModel.swift`
- `Features/TaskDetail/TaskDetailView.swift`
- `Features/TaskDetail/TaskDetailViewModel.swift`
- `Features/Confirm/ConfirmationCardView.swift`
- `Features/Diagnostics/DiagnosticsView.swift`

## 2.3 HermesKit
**职责**：与 Hermes 通信，屏蔽 API 细节

**建议文件**：
- `Packages/HermesKit/Sources/HermesKit/AgentBackend.swift`
- `Packages/HermesKit/Sources/HermesKit/HermesLocalAdapter.swift`
- `Packages/HermesKit/Sources/HermesKit/HermesAPIModels.swift`
- `Packages/HermesKit/Sources/HermesKit/SSEParser.swift`
- `Packages/HermesKit/Sources/HermesKit/HealthClient.swift`

## 2.4 AppCore Models
**职责**：Task/Event/Approval/Artifact 等 UI 共享模型

**建议文件**：
- `Packages/AppCore/Sources/AppCore/Models/Task.swift`
- `Packages/AppCore/Sources/AppCore/Models/TaskEvent.swift`
- `Packages/AppCore/Sources/AppCore/Models/ApprovalRequest.swift`
- `Packages/AppCore/Sources/AppCore/Models/Artifact.swift`
- `Packages/AppCore/Sources/AppCore/Models/Capability.swift`

---

## 3. 阶段目标

## 3.1 Phase 0：可用闭环
### 目标
证明一件事：

> 不盯 Hermes CLI，也能知道任务状态、处理确认、看失败、回看结果。

### 交付物
- MenuBar 入口
- Inbox / Running / Recent 最小列表
- Task Detail Window
- Hermes health 检测
- 基础 chat/completions + SSE 接入
- confirm / error / result 的最小 UI 映射
- Diagnostics 基础页

### 不做
- 多 Agent
- iPhone
- pause/resume 完整控制
- 复杂本地数据库
- 花哨视觉系统

## 3.2 Phase 1：增强可用性
### 目标
把 Phase 0 从“能用”提升到“愿意常驻使用”。

### 交付物
- 最近任务历史
- 重试 / 恢复增强
- 更清晰的 step / timeline
- 更完整的日志 / 诊断 / 打开终端 / 打开工作区
- task-level allow 等更细确认 scope
- 全局快捷键呼出（可选）

---

## 4. 任务拆解

### Task 1：建立产品骨架与工程骨架

**Objective:** 创建 Mac 原生项目骨架、共享包和基础模块命名。

**Files:**
- Create: `apps/mac/HermesDeskApp/HermesDeskApp.swift`
- Create: `apps/mac/HermesDeskApp/AppShell/MenuBarScene.swift`
- Create: `Packages/AppCore/Sources/AppCore/Models/Task.swift`
- Create: `Packages/HermesKit/Sources/HermesKit/AgentBackend.swift`
- Create: `Docs/ADRs/0001-mac-first-hermes-only.md`

**Step 1: 写 ADR，固化核心决策**
- 记录：Mac-first、Hermes-only、MenuBarExtra、HTTP+SSE、Phase 0/1 边界

**Step 2: 搭建最小 App Scene**
- 建立 MenuBarExtra 入口和 Settings Scene

**Step 3: 创建共享模型与空协议**
- 建立 Task / Event / Approval / Capability 基础结构

**Step 4: 验证应用可启动**
Run: Xcode Build / `xcodebuild -scheme HermesDeskApp -destination 'platform=macOS' build`
Expected: 编译通过，MenuBar 图标出现

**Step 5: Commit**
`git commit -m "chore: bootstrap agent hub mac app skeleton"`

---

### Task 2：实现 Hermes 健康检查与连接状态

**Objective:** 让客户端能可靠感知 Hermes 是否在线。

**Files:**
- Create: `Packages/HermesKit/Sources/HermesKit/HealthClient.swift`
- Modify: `Packages/HermesKit/Sources/HermesKit/HermesLocalAdapter.swift`
- Modify: `apps/mac/HermesDeskApp/AppShell/MenuBarScene.swift`
- Test: `Packages/HermesKit/Tests/HermesKitTests/HealthClientTests.swift`

**Step 1: 写失败测试/桩测试**
- 覆盖在线、超时、401、端口未开启等场景

**Step 2: 实现 /health client**
- 使用 URLSession 调用 Hermes `/health`

**Step 3: 暴露连接状态给 UI**
- 在线 / 失联 / 启动中 / 配置错误

**Step 4: 在 MenuBar 顶部渲染状态区**
- 展示 Hermes 状态与错误摘要

**Step 5: 验证**
- Hermes 开启 / 未开启两种状态切换正确

**Step 6: Commit**
`git commit -m "feat: add hermes health monitoring"`

---

### Task 3：实现基础 Task / Event 内部模型

**Objective:** 统一 UI 内部使用的数据结构，避免页面直接吃 Hermes 原始 JSON。

**Files:**
- Modify: `Packages/AppCore/Sources/AppCore/Models/Task.swift`
- Create: `Packages/AppCore/Sources/AppCore/Models/TaskEvent.swift`
- Create: `Packages/AppCore/Sources/AppCore/Models/ApprovalRequest.swift`
- Create: `Packages/AppCore/Sources/AppCore/Models/Artifact.swift`
- Test: `Packages/AppCore/Tests/AppCoreTests/TaskModelTests.swift`

**Step 1: 写模型测试**
- 覆盖状态、排序、available_actions、事件映射

**Step 2: 实现枚举与结构体**
- 使用协议文档 v0.1 中的枚举

**Step 3: 提供最小 mock 数据**
- 用于 SwiftUI 预览和首屏开发

**Step 4: 验证 SwiftUI 预览可工作**

**Step 5: Commit**
`git commit -m "feat: add core task and event models"`

---

### Task 4：打通 Hermes chat/completions + SSE

**Objective:** 通过 Hermes API Server 获取流式结果，建立最小真实任务链路。

**Files:**
- Create: `Packages/HermesKit/Sources/HermesKit/SSEParser.swift`
- Create: `Packages/HermesKit/Sources/HermesKit/HermesChatClient.swift`
- Modify: `Packages/HermesKit/Sources/HermesKit/HermesLocalAdapter.swift`
- Test: `Packages/HermesKit/Tests/HermesKitTests/SSEParserTests.swift`

**Step 1: 写 SSE 解析测试**
- 覆盖分块、断流、data 多段拼接

**Step 2: 封装 chat/completions 请求**
- 支持 `stream=true`
- 支持传递 `X-Hermes-Session-Id`

**Step 3: 把流式输出映射为 TaskEvent**
- 最小支持 `output` / `error` / `state_change`

**Step 4: 本机连真实 Hermes 验证**
- 可发起任务并获得流式输出

**Step 5: Commit**
`git commit -m "feat: connect hermes chat completions with sse"`

---

### Task 5：实现 MenuBar Inbox / Running / Recent 列表

**Objective:** 完成最重要的一屏，让用户一眼看到要处理的事。

**Files:**
- Create: `apps/mac/HermesDeskApp/Features/Inbox/InboxView.swift`
- Create: `apps/mac/HermesDeskApp/Features/Inbox/InboxViewModel.swift`
- Modify: `apps/mac/HermesDeskApp/AppShell/MenuBarScene.swift`
- Test: `Packages/AppCore/Tests/AppCoreTests/InboxSortingTests.swift`

**Step 1: 写排序测试**
- 顺序应为：待确认 > 待恢复 > 运行中 > 最近完成

**Step 2: 渲染顶部状态区**
- Hermes 状态、任务统计、快捷入口

**Step 3: 渲染四个区块**
- Inbox / Running / Recent / Quick Actions

**Step 4: 支持点入任务详情**

**Step 5: 验证**
- 打开后第一屏不是聊天欢迎页，而是任务收件箱

**Step 6: Commit**
`git commit -m "feat: add menubar inbox and task overview"`

---

### Task 6：实现 Task Detail Window

**Objective:** 提供任务级工作界面，承接 timeline、当前阶段、结果卡片与 debug 信息。

**Files:**
- Create: `apps/mac/HermesDeskApp/Features/TaskDetail/TaskDetailView.swift`
- Create: `apps/mac/HermesDeskApp/Features/TaskDetail/TaskDetailViewModel.swift`
- Create: `apps/mac/HermesDeskApp/Features/TaskDetail/TaskTimelineView.swift`
- Create: `apps/mac/HermesDeskApp/Features/TaskDetail/ResultCardView.swift`

**Step 1: 先用 mock 数据做布局**
- 跑通 running / waiting_user / failed / succeeded 四种状态

**Step 2: 接真实 Task 模型**
- 时间线、状态头、动作区

**Step 3: 加 Debug / Artifact 区**
- 命令、路径、结果摘要、可复制 ID

**Step 4: 验证**
- 用户能明确看到“现在卡在哪里”

**Step 5: Commit**
`git commit -m "feat: add task detail window"`

---

### Task 7：实现 Confirmation Card 最小闭环

**Objective:** 把最关键的确认流做成可用组件。

**Files:**
- Create: `apps/mac/HermesDeskApp/Features/Confirm/ConfirmationCardView.swift`
- Create: `apps/mac/HermesDeskApp/Features/Confirm/ConfirmationActionHandler.swift`
- Modify: `Features/TaskDetail/TaskDetailView.swift`
- Test: `Packages/AppCore/Tests/AppCoreTests/ApprovalActionTests.swift`

**Step 1: 先做 mock 审批卡片**
- 标题、风险说明、命令预览、按钮

**Step 2: 实现 allow once / deny**
- 先跑最小动作闭环

**Step 3: 键盘交互**
- Enter / Esc / Tab

**Step 4: 决议状态回写**
- 卡片进入“已决议”状态

**Step 5: 验证**
- 处理确认时不必回 CLI

**Step 6: Commit**
`git commit -m "feat: add confirmation card flow"`

---

### Task 8：实现失败展示与恢复动作

**Objective:** 让失败不只是错误文本，而是一个可恢复工作流。

**Files:**
- Create: `apps/mac/HermesDeskApp/Features/TaskDetail/FailurePanelView.swift`
- Modify: `TaskDetailViewModel.swift`
- Modify: `InboxViewModel.swift`
- Test: `Packages/AppCore/Tests/AppCoreTests/FailureRecoveryTests.swift`

**Step 1: 写失败分类测试**
- connection / tool / approval timeout 等

**Step 2: 渲染失败面板**
- 错误摘要 + 建议动作

**Step 3: 接入 retry / open terminal / diagnostics**
- 先做最小恢复链路

**Step 4: 验证**
- 失败任务进入 Inbox 顶部

**Step 5: Commit**
`git commit -m "feat: add failure recovery flow"`

---

### Task 9：实现 Diagnostics 页

**Objective:** 让连接与环境问题能在 30 秒内定位。

**Files:**
- Create: `apps/mac/HermesDeskApp/Features/Diagnostics/DiagnosticsView.swift`
- Create: `apps/mac/HermesDeskApp/Features/Diagnostics/DiagnosticsViewModel.swift`
- Modify: `AppShell/SettingsScene.swift`

**Step 1: 展示当前 Hermes host/port/profile/health**
**Step 2: 增加一键健康检查**
**Step 3: 增加日志/目录/复制诊断信息**
**Step 4: 验证用户能定位“为什么连不上”**
**Step 5: Commit**
`git commit -m "feat: add diagnostics view"`

---

### Task 10：Phase 1 增强项

**Objective:** 将可用版提升为常驻可用版。

**Files:**
- Modify: `InboxView.swift`
- Modify: `TaskDetailView.swift`
- Modify: `ConfirmationCardView.swift`
- Create: `Features/History/RecentTasksView.swift`
- Create: `Features/AppShortcuts/GlobalShortcutManager.swift`

**增强项内容：**
1. 最近任务历史
2. task-level allow（谨慎）
3. 打开终端 / 打开工作区
4. 更完整 step timeline
5. 可选全局快捷键呼出

**验证标准：**
- 连续 3~7 天自用后，MenuBar 仍愿意常驻

**Commit**
`git commit -m "feat: phase 1 usability enhancements"`

---

## 5. 测试与验证

## 5.1 单元测试重点
- Task / Event / Approval 模型
- SSE parser
- Health 状态机
- Inbox 排序
- 确认动作状态回写
- 失败分类与恢复动作

## 5.2 手工验证重点
1. Hermes 在线 / 离线切换
2. 任务运行中 UI 是否明确
3. 确认卡片是否足够理解风险
4. 失败后能否快速找到下一步
5. 结果卡片是否有价值

## 5.3 Phase 0 完成标准
- 可打开 MenuBar 并看到 Hermes 状态
- 可查看任务收件箱
- 可打开详情页
- 可处理最小确认流
- 可看到失败并重试/打开终端
- 可回看 result card

---

## 6. 风险与取舍

### 风险 1：Hermes 事件粒度不足
**影响：** Timeline 只能基于聊天输出推断  
**缓解：** Phase 0 接 chat/completions；Phase 1 评估 runs/events

### 风险 2：服务生命周期不一致
**影响：** UI 误判 Hermes 在线状态  
**缓解：** 先把 diagnostics 做扎实，health + launchd 状态双重校验

### 风险 3：过早抽象多 Adapter
**影响：** 工程复杂度膨胀  
**缓解：** 产品只支持 Hermes；代码只保留薄接口

### 风险 4：UI 走向聊天化
**影响：** 产品退化成另一个 AI 聊天壳  
**缓解：** 以 Inbox / Task Detail / Confirmation Card 为主结构

---

## 7. 推荐开发顺序（压缩版）
1. 工程骨架
2. Hermes health
3. Task/Event 模型
4. chat/completions + SSE
5. MenuBar 收件箱
6. Task Detail
7. Confirmation Card
8. Failure Recovery
9. Diagnostics
10. Phase 1 增强

