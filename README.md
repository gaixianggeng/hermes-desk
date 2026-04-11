# Agent Hub

Mac-first Agent supervision control layer for Hermes.

## Current scope
- macOS native app skeleton
- Hermes single adapter
- MenuBar-first UX with a separate main window
- Phase 0 / Phase 1 foundations only

## What is implemented in this bootstrap
- `XcodeGen` project definition in `project.yml`
- macOS SwiftUI app skeleton under `apps/mac/AgentHubApp`
- local Swift packages:
  - `Packages/AppCore`: shared task / event / approval / artifact models
  - `Packages/HermesKit`: Hermes endpoint configuration, `/health` client stub, connection state model
- `MenuBarExtra` entry, main dashboard window, Connection / Diagnostics placeholder
- ADR capturing Mac-first / Hermes-only / Native-first decisions

## Repository layout
```text
agent-hub/
├── apps/mac/AgentHubApp/
├── Packages/AppCore/
├── Packages/HermesKit/
├── docs/ADRs/
├── docs/plans/
└── project.yml
```

## Build
```bash
xcodegen generate
xcodebuild -project AgentHub.xcodeproj -scheme AgentHubApp -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

## Hermes health stub assumptions
- default endpoint: `http://127.0.0.1:8642`
- current app build only performs a lightweight `GET /health`
- non-2xx, timeout, and transport errors are mapped into connection state summaries for UI display

## Key docs
- `docs/plans/2026-04-11-agent-hub-prd-v1-mac-first.md`
- `docs/plans/2026-04-11-agent-hub-protocol-v0.1.md`
- `docs/plans/2026-04-11-agent-hub-phase0-1-implementation-plan.md`
- `docs/plans/2026-04-11-agent-hub-dogfooding-plan.md`
- `docs/ADRs/0001-mac-first-hermes-only.md`
