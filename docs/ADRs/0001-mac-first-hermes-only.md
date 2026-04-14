# ADR 0001: Mac-first, Hermes-only, Native-first bootstrap

- Status: Accepted
- Date: 2026-04-11

## Context
Hermes Desk Phase 0 / Phase 1 is meant to become a daily-use supervision layer for programmers running Hermes locally. Existing planning docs already constrain the first delivery to a native macOS experience, a single Hermes adapter, and a MenuBar-first workflow focused on task supervision instead of chat.

## Decision
1. Build the first client as a native macOS app with SwiftUI and small AppKit interop only where required.
2. Support Hermes as the only backend in product scope.
3. Use `MenuBarExtra` as the always-available entry point, with a separate main window for deeper task inspection.
4. Communicate with Hermes over local HTTP plus future SSE, starting with `GET /health`.
5. Keep Phase 0 / Phase 1 boundaries tight: bootstrap the shell, shared models, health monitoring, and task-oriented UI scaffolding before richer run / event flows.

## Consequences
- The repository is organized around one app target plus two local packages: `AppCore` and `HermesKit`.
- UI state and task-facing models stay separate from Hermes transport code.
- The initial build optimizes for compileability and architectural direction, not feature completeness or visual polish.
- Future work can add chat/runs/SSE features without reworking the app shell or package boundaries.

## Related documents
- `docs/plans/2026-04-11-hermes-desk-prd-v1-mac-first.md`
- `docs/plans/2026-04-11-hermes-desk-protocol-v0.1.md`
- `docs/plans/2026-04-11-hermes-desk-phase0-1-implementation-plan.md`
