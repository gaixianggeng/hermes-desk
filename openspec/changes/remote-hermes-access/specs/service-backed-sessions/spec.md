## ADDED Requirements

### Requirement: Hermes Desk can list remote sessions
Hermes Desk SHALL be able to retrieve session metadata from a backend session API without direct access to the Hermes host filesystem.

#### Scenario: Load recent sessions from a backend
- **WHEN** Hermes Desk is configured to use a remote Hermes backend
- **THEN** it retrieves recent session metadata from a service endpoint instead of reading `~/.hermes/state.db` locally

### Requirement: Hermes Desk can search remote session history
The backend SHALL provide searchable session history so Hermes Desk can locate prior work without replaying all transcripts client-side.

#### Scenario: Search prior sessions by text
- **WHEN** a user searches for text in Hermes Desk while connected to a remote backend
- **THEN** Hermes Desk receives matching sessions and snippets from a backend search endpoint

### Requirement: Hermes Desk can load remote session detail and messages
The backend SHALL provide session detail and message-history endpoints that let Hermes Desk inspect an existing task transcript without local SQLite access.

#### Scenario: Open a remote task transcript
- **WHEN** a user opens an existing remote Hermes task in Hermes Desk
- **THEN** Hermes Desk loads the session metadata and messages from backend APIs tied to that session identifier
