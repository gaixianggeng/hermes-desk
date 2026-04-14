## Why

Hermes Desk already uses a task-first shell, but the main workspace still behaved like a bilateral chat transcript. That made task state, live progress, and future `thinking` or `task list` affordances feel bolted onto a chat UI instead of belonging to a task workspace.

We also need to capture what Hermes can actually provide today. `thinking` data is already available through reasoning signals, while structured task-list data is not. Recording that distinction in OpenSpec keeps the next implementation steps grounded in the real Hermes contract.

## What Changes

- Replace the middle workspace transcript bubble layout with a flat, task-first canvas and semantic content blocks.
- Promote task brief, live status cards, and task-scoped composer framing into the main workspace.
- Document the current Hermes signal contract for `thinking`: live `reasoning.available` events and durable transcript `reasoning`.
- Document the current Hermes gap for `task list`: no structured checklist payload is available yet, so follow-up work must either add a fallback extraction layer or extend Hermes.
- Track already completed workspace redesign work together with the remaining `thinking` and `task list` follow-up tasks.

## Capabilities

### New Capabilities
- `task-workspace`: Present Hermes Desk tasks in a flat workspace with semantic blocks for request, response, progress, status, and results.
- `process-signals`: Define how Hermes Desk consumes and presents Hermes reasoning/progress signals, including explicit handling when structured task-list data is unavailable.

### Modified Capabilities
- None.

## Impact

- Affects [`apps/mac/HermesDeskApp/Features/Dashboard/DashboardView.swift`](/Users/gxg/Code/hermes-desk/apps/mac/HermesDeskApp/Features/Dashboard/DashboardView.swift)
- Relies on existing Hermes run-event models in [`Packages/HermesKit/Sources/HermesKit/HermesAPIModels.swift`](/Users/gxg/Code/hermes-desk/Packages/HermesKit/Sources/HermesKit/HermesAPIModels.swift)
- Relies on existing task-state mapping in [`Packages/AppCore/Sources/AppCore/HermesTaskReducer.swift`](/Users/gxg/Code/hermes-desk/Packages/AppCore/Sources/AppCore/HermesTaskReducer.swift)
- Relies on durable transcript reasoning stored through [`Packages/HermesKit/Sources/HermesKit/HermesLocalTranscriptStore.swift`](/Users/gxg/Code/hermes-desk/Packages/HermesKit/Sources/HermesKit/HermesLocalTranscriptStore.swift)
- Adds OpenSpec change artifacts to track completed work and remaining follow-up items
