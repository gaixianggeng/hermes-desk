## ADDED Requirements

### Requirement: Hermes Desk behaves as a run-only task client in phase 1
Hermes Desk SHALL support its default workflow using only the Hermes public run APIs for the first milestone.

#### Scenario: Start a task with only run APIs available
- **WHEN** Hermes Desk is connected to a Hermes backend that exposes run start, run action, and run SSE endpoints
- **THEN** the user can still create and operate a task through the existing workspace UI
- **AND** Desk SHALL NOT require transcript or session query APIs to render the current turn

### Requirement: Current-turn assistant output is display-first
Hermes Desk SHALL surface the current turn's assistant reply directly from run transport data before any later transcript reconciliation work.

#### Scenario: Run completes before any transcript hydration exists
- **WHEN** Desk receives `run.completed` with a non-empty final output
- **THEN** the workspace SHALL show that assistant reply as the visible answer for the task
- **AND** placeholders such as "working" or "syncing" SHALL NOT replace or hide that answer

### Requirement: Task continuation reuses stable session identifiers
Hermes Desk SHALL continue an existing task by reusing the stored backend `session_id` through the public run API when that identifier is available.

#### Scenario: Send a follow-up prompt on an existing task
- **WHEN** a user sends another prompt inside an existing Desk task
- **THEN** Hermes Desk starts the new run against that task's stored `session_id`
- **AND** it SHALL NOT require backend session-binding lookups in phase 1

### Requirement: Phase 1 avoids direct local Hermes storage reads
Hermes Desk SHALL NOT depend on `state.db` or other direct local Hermes storage reads for its default first-phase workflow.

#### Scenario: Operate the workspace during an active task
- **WHEN** Desk renders task progress and the current turn's visible answer
- **THEN** it uses client-owned task state plus live run events
- **AND** it SHALL NOT reach into Hermes-owned local transcript/session storage as part of the default path
