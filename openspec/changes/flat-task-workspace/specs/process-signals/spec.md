## ADDED Requirements

### Requirement: Workspace can surface Hermes thinking signals
Hermes Desk SHALL be able to consume Hermes reasoning signals from live run events and durable transcript messages when that data is available.

#### Scenario: Live reasoning arrives from Hermes
- **WHEN** Hermes emits a `reasoning.available` event for the current run
- **THEN** Hermes Desk records that reasoning as a process signal that can be presented in workspace or progress-oriented UI

### Requirement: Workspace distinguishes process signals from final answers
Hermes Desk SHALL treat reasoning and execution progress as process signals while keeping final assistant answers separate from those signals.

#### Scenario: Transcript contains assistant reasoning
- **WHEN** a transcript message includes `reasoning` data
- **THEN** Hermes Desk can recover that reasoning for process-signal presentation without automatically treating it as the final assistant answer

### Requirement: Workspace does not invent structured task lists
Hermes Desk SHALL not present a structured task list as authoritative unless Hermes exposes checklist data through a stable contract.

#### Scenario: Hermes provides only free-form progress text
- **WHEN** the workspace receives progress text without a structured checklist schema
- **THEN** Hermes Desk shows progress summaries or research notes and keeps structured task-list support as explicit follow-up work
