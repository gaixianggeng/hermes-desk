## ADDED Requirements

### Requirement: Remote Hermes endpoints require configured authentication
Hermes Desk SHALL treat non-loopback Hermes backends as authenticated services and SHALL not attempt remote session or run requests when required credentials are missing.

#### Scenario: Remote backend is configured without credentials
- **WHEN** Hermes Desk resolves a Hermes endpoint that is not loopback-local and no valid remote credential is configured
- **THEN** Hermes Desk reports a configuration/authentication error and does not attempt unauthenticated remote access

### Requirement: Session and run endpoints share one authentication policy
Remote session endpoints and remote run endpoints SHALL be protected by the same authentication policy so Hermes Desk does not need separate trust models for history and execution.

#### Scenario: Authenticated client calls both session and run APIs
- **WHEN** Hermes Desk sends authenticated requests to remote session endpoints and remote run endpoints
- **THEN** both endpoint families accept the same configured credential type and reject invalid credentials consistently

### Requirement: Loopback-local development remains explicitly local
Hermes Desk MAY continue to use unauthenticated local access for loopback-only development, but that behavior SHALL not be treated as valid remote security.

#### Scenario: Local developer uses loopback Hermes
- **WHEN** Hermes Desk connects to a loopback-local Hermes deployment for local development
- **THEN** it may use local-mode access rules while still distinguishing that mode from authenticated remote operation in diagnostics
