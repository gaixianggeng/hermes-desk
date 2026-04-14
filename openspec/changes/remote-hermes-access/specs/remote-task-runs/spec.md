## ADDED Requirements

### Requirement: Hermes Desk can start and continue remote task runs
Hermes Desk SHALL be able to start a new remote run or continue an existing remote task using a stable backend session identifier.

#### Scenario: Continue an existing remote task
- **WHEN** a user sends a follow-up prompt for a task that already has a backend session identifier
- **THEN** Hermes Desk submits the run against that existing backend session instead of creating an unrelated local-only session

### Requirement: Hermes Desk can observe remote run progress over SSE
Hermes Desk SHALL consume remote run events over HTTP/SSE so task progress, approvals, failures, and completions remain visible during remote operation.

#### Scenario: Stream remote run events
- **WHEN** Hermes Desk starts a remote run
- **THEN** it subscribes to the backend run-event stream and updates task state from the streamed events until the run finishes or disconnects

### Requirement: Remote run workflows do not require local transcript storage
Remote run initiation and continuation SHALL not depend on local access to the Hermes transcript database.

#### Scenario: Run from a machine without Hermes home mounted
- **WHEN** Hermes Desk runs on a machine that does not have the remote Hermes host's `~/.hermes` directory available
- **THEN** task creation, continuation, and progress streaming still work through backend APIs alone
