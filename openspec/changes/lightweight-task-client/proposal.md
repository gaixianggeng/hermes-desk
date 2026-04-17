## Why

Hermes Desk's first milestone is narrower than a full remote workspace. The
immediate product goal is to make the app behave like a task-scoped run client:

- each workspace task maps to a Hermes run/session
- visible assistant output is driven directly from run transport
- the client behaves like Telegram/Lark/Slack/Discord from the perspective of
  current-turn delivery

The current Desk implementation still leaks assumptions from a heavier history
browser model. That creates sync-only placeholders and makes the visible answer
depend on transcript rehydration. For the first phase, that is unnecessary
complexity. The visible task experience should be driven only by the public run
APIs, just like Hermes messaging clients.

## What Changes

- Keep Hermes Desk task-first and make the first phase explicitly run-only.
- Align Desk's current-turn delivery model with Telegram/Lark-style clients.
- Make the current turn's final assistant reply visible from run transport data
  instead of waiting for transcript re-sync.
- Treat Hermes public run APIs as the only required backend contract for this
  first phase.
- Explicitly defer transcript/session reconciliation APIs to a later phase.

## Capabilities

### New Capabilities
- `display-first-task-client`: Hermes Desk can surface the assistant's final
  reply directly from run transport data, even when no transcript refresh has
  happened yet.
- `run-only-task-workspace`: Hermes Desk can present a task-scoped workspace
  using only run start, run action, and SSE event APIs.

### Modified Capabilities
- `remote-task-runs`: Hermes Desk continues to start, continue, and observe task
  runs over HTTP/SSE, but now also materializes final answers directly from the
  run channel.
- `client-owned-task-cache`: Hermes Desk may retain lightweight client-owned
  task state for relaunch convenience, but transcript/session reconciliation is
  not part of the first-phase contract.

## Impact

- Affects [Packages/HermesKit/Sources/HermesKit/AgentBackend.swift](/Users/gaixiaotongxue/code/agent-hub/Packages/HermesKit/Sources/HermesKit/AgentBackend.swift) and [Packages/HermesKit/Sources/HermesKit/HermesLocalAdapter.swift](/Users/gaixiaotongxue/code/agent-hub/Packages/HermesKit/Sources/HermesKit/HermesLocalAdapter.swift) because the run-only Desk contract must stay narrow and centered on run APIs.
- Affects [apps/mac/HermesDeskApp/AppShell/AppStateStore.swift](/Users/gaixiaotongxue/code/agent-hub/apps/mac/HermesDeskApp/AppShell/AppStateStore.swift) because final-answer materialization must move to a display-first model driven by run events.
- Affects [apps/mac/HermesDeskApp/Features/Dashboard/DashboardView.swift](/Users/gaixiaotongxue/code/agent-hub/apps/mac/HermesDeskApp/Features/Dashboard/DashboardView.swift) because working/sync placeholders must never hide or replace the current turn's answer.
- Explicitly defers session/transcript query surfaces and any direct local-storage helpers from the first-phase critical path.
