## Why

Hermes Desk currently mixes two integration models: task execution already uses HTTP and SSE, but session history and transcript loading still depend on direct local access to `~/.hermes/state.db`. That coupling blocks a real remote deployment story and keeps security assumptions tied to localhost instead of authenticated service access.

Recent Hermes Agent work also shows a split backend surface: the dashboard exposes session APIs without general authentication, while the API server supports Bearer auth but only enforces it when a key is configured. Capturing a stricter remote contract in OpenSpec gives Hermes Desk a clear target before more client code hard-codes local assumptions.

## What Changes

- Define a service-backed session API contract for listing, searching, inspecting, and loading Hermes sessions without direct SQLite access from Hermes Desk.
- Define remote task-run behavior for starting and continuing Hermes work over HTTP/SSE using stable session identifiers.
- Require a shared authentication policy for remote session endpoints and run endpoints so non-loopback access never relies on implicit localhost trust.
- Treat direct `state.db` reads as a local-only fallback path instead of Hermes Desk's primary integration surface.
- Track the implementation work needed in Hermes Desk and the upstream Hermes backend dependency needed to make remote mode fully viable.

## Capabilities

### New Capabilities
- `service-backed-sessions`: Hermes Desk can obtain session lists, search results, metadata, and message history from a backend API instead of requiring direct local SQLite access.
- `authenticated-remote-access`: Remote Hermes access enforces a consistent authentication policy across session and run endpoints and fails closed when remote credentials are missing.
- `remote-task-runs`: Hermes Desk can start, continue, and observe remote Hermes task runs using HTTP requests plus SSE event streams tied to backend session IDs.

### Modified Capabilities
- None.

## Impact

- Affects [`Packages/HermesKit/Sources/HermesKit/HermesLocalAdapter.swift`](/Users/gxg/Code/hermes-desk/Packages/HermesKit/Sources/HermesKit/HermesLocalAdapter.swift) and related backend abstractions because transcript access must no longer assume local SQLite.
- Affects [`Packages/HermesKit/Sources/HermesKit/HermesAPIModels.swift`](/Users/gxg/Code/hermes-desk/Packages/HermesKit/Sources/HermesKit/HermesAPIModels.swift), [`Packages/HermesKit/Sources/HermesKit/RunClient.swift`](/Users/gxg/Code/hermes-desk/Packages/HermesKit/Sources/HermesKit/RunClient.swift), and health/diagnostics flows because remote configuration and auth become first-class.
- Affects [`apps/mac/HermesDeskApp/AppShell/AppStateStore.swift`](/Users/gxg/Code/hermes-desk/apps/mac/HermesDeskApp/AppShell/AppStateStore.swift) and settings/diagnostics UI because the app must distinguish local fallback mode from authenticated remote mode.
- Depends on upstream Hermes service support for authenticated session endpoints that match the contract documented here.
