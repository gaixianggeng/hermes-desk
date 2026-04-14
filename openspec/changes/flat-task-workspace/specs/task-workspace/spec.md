## ADDED Requirements

### Requirement: Workspace uses a flat task-first layout
Hermes Desk SHALL present the selected task in a single-column, task-first workspace canvas instead of a bilateral chat bubble layout.

#### Scenario: Selected task opens in the workspace
- **WHEN** a user selects a task from the navigator
- **THEN** the main pane shows task overview, status context, and a flat content stream aligned to one document column

### Requirement: Workspace content is rendered as semantic blocks
Hermes Desk SHALL render request, response, progress, status, and result content as titled block cards with task-oriented metadata rather than left/right chat bubbles.

#### Scenario: Mixed workspace content is available
- **WHEN** transcript messages, pending outgoing messages, run-state summaries, or artifacts exist for the selected task
- **THEN** the workspace shows each item as a semantic block with styling appropriate to its role in the task flow

### Requirement: Composer is framed as task continuation
Hermes Desk SHALL present the composer as a task workspace input panel rather than a standalone chat input.

#### Scenario: User continues an existing task
- **WHEN** the composer is shown for a selected task
- **THEN** the composer indicates that the user is continuing that task and remains visually integrated with the task workspace canvas
