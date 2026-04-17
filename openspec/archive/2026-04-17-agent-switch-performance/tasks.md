## 1. Selection Side Effects

- [x] 1.1 Stop agent selection from implicitly triggering backend health/reload work
- [x] 1.2 Add regression coverage for cross-agent task selection without backend refresh

## 2. Streaming Churn Reduction

- [x] 2.1 Reduce repeated transcript/cache rebuilds when content has not changed
- [x] 2.2 Slow hidden-agent streaming flush cadence relative to the visible agent
- [x] 2.3 Defer hidden-agent streaming materialization until the task becomes visible or finishes

## 3. Workspace Isolation

- [x] 3.1 Snapshot the selected task inside `DashboardView`
- [x] 3.2 Snapshot the selected task’s feed entries for the center column
- [x] 3.3 Keep the composer and inspector aligned to the selected-task snapshot instead of the entire store

## 4. Verification

- [x] 4.1 Add local benchmark coverage for “hidden task streaming while switching agents”
- [x] 4.2 Verify `HermesDeskApp` still builds after the performance changes
- [x] 4.3 Verify the benchmark still passes after deferred hidden-stream materialization

## 5. Follow-Up

- [ ] 5.1 Split Dashboard into narrower subscription boundaries for navigation, workspace, and inspector
- [ ] 5.2 Evaluate whether `tasks` should move from one broad published array to per-task observable models
- [ ] 5.3 Add rendering-specific instrumentation for Markdown/layout work if switch-time CPU is still noticeable
