## Why

Hermes Desk showed noticeable CPU spikes when the user switched between agents
or conversations while another agent was still streaming output. The app did not
appear memory-bound; the hot path was repeated UI invalidation and redraw work:

- agent selection changed broad `DashboardView` state
- background streaming tasks kept mutating shared `tasks` state
- the current workspace and inspector were rebuilt more often than necessary
- Markdown-backed workspace content amplified redraw cost, even when parsing was
  cached

The product goal for this work is to keep agent switching responsive while
preserving task correctness and visible results.

## What Changes

- Decouple agent selection from implicit health/reload side effects.
- Reduce transcript/cache churn during streaming, especially for hidden agents.
- Defer hidden-agent streaming materialization until the task becomes visible or
  the run completes.
- Cache the selected task and its workspace feed snapshot inside
  `DashboardView` so the center column and inspector do not rebuild on every
  unrelated store update.
- Add performance-oriented regression coverage and local benchmarks for
  “hidden task streaming while switching agents”.
- Add lightweight performance logging so future regressions can be investigated
  without manual profiling first.

## Capabilities

### New Capabilities

- `agent-switch-performance-debugging`: Hermes Desk can log selection,
  lifecycle, and feed-build behavior to isolate switch-related regressions.
- `hidden-stream-benchmarking`: Hermes Desk has a local benchmark covering
  hidden-task streaming during rapid agent switching.

### Modified Capabilities

- `workspace-transcript-debugging`: streaming updates for hidden agents may be
  materialized lazily instead of eagerly, while still preserving final visible
  task output.
- `remote-task-runs`: live task streaming remains continuous, but hidden-agent
  updates no longer force the same frequency of UI-facing state publication.

## Impact

- Affects [apps/mac/HermesDeskApp/AppShell/AppStateStore.swift](/Users/gaixiaotongxue/code/agent-hub/apps/mac/HermesDeskApp/AppShell/AppStateStore.swift) because selection side effects, streaming buffering, and deferred materialization all live in the central store.
- Affects [apps/mac/HermesDeskApp/Features/Dashboard/DashboardView.swift](/Users/gaixiaotongxue/code/agent-hub/apps/mac/HermesDeskApp/Features/Dashboard/DashboardView.swift) because the selected workspace and inspector now use local snapshots to shrink redraw scope.
- Affects [apps/mac/HermesDeskAppTests/AppStateStoreTests.swift](/Users/gaixiaotongxue/code/agent-hub/apps/mac/HermesDeskAppTests/AppStateStoreTests.swift) because switch-related regressions now need focused coverage and a repeatable benchmark path.
