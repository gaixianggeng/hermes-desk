## Context

Hermes Desk currently resolves Hermes connection settings from environment and talks to the run API over HTTP/SSE, but it still loads transcript history by opening the local Hermes home directory and reading `state.db` directly. That works for the current localhost-only deployment model, yet it breaks the moment Hermes Desk is expected to connect to Hermes running on another machine.

Recent upstream Hermes Agent work is useful but incomplete for this need:
- The web dashboard uses a local FastAPI backend to expose `/api/sessions` style APIs backed by `SessionDB`.
- The API server exposes `/v1/runs` and `/v1/runs/{id}/events` and supports Bearer auth.
- The dashboard APIs are documented as local-only and do not have general authentication.
- The API server only enforces Bearer auth when `API_SERVER_KEY` is configured.

That means Hermes Desk needs a cleaner remote contract than "reuse whatever local dashboard endpoints happen to exist today."

## Goals / Non-Goals

**Goals:**
- Define a remote integration model where Hermes Desk can operate without direct filesystem access to the Hermes host.
- Make session history, session search, and transcript loading service-backed capabilities.
- Keep `/v1/runs` and `/v1/runs/{id}/events` as the run transport while making session continuity explicit.
- Require a fail-closed authentication policy for non-loopback remote access.
- Preserve a local-only fallback mode for developers who still run Hermes and Hermes Desk on the same machine.

**Non-Goals:**
- Replacing Hermes's existing run/event protocol.
- Designing a public multi-tenant SaaS auth model.
- Removing all local mode support from Hermes Desk.
- Implementing the upstream Hermes backend changes inside this repository.

## Decisions

### 1. Split Hermes Desk backend access into local mode and remote mode

- Chosen: Keep a local mode that can still read local transcript storage, but add a remote mode that uses HTTP-only session and run APIs.
- Alternative considered: Remove all local transcript access immediately and require backend support before any further Desk work.
- Why: Hermes Desk still needs a usable path for current dogfooding, but the architecture should stop assuming local filesystem access is universal.

### 2. Treat service-backed session APIs as the primary remote contract

- Chosen: Define authenticated session endpoints for list/search/detail/messages as the required remote contract for Hermes Desk.
- Alternative considered: Continue sending full conversation history from the client on every request and avoid session APIs entirely.
- Why: Hermes Desk needs searchable history, durable transcripts, and task continuity. Those are better expressed as backend session resources than as client-managed replay blobs.

### 3. Reuse stable backend session IDs across transcript loading and run continuation

- Chosen: The same backend session identifier should be used to fetch message history and to continue new runs for an existing task.
- Alternative considered: Separate "history session" and "run session" identifiers with client-side mapping glue.
- Why: A single session identity keeps task continuation, transcript hydration, and SSE event routing aligned and reduces reconciliation logic in `AppStateStore`.

### 4. Remote access must fail closed when auth is missing

- Chosen: Non-loopback endpoints require configured credentials, and Hermes Desk surfaces configuration/auth errors instead of silently attempting unauthenticated access.
- Alternative considered: Mirror upstream API server behavior where auth is optional unless a key happens to be configured.
- Why: Optional auth is acceptable for localhost experimentation but unsafe for the remote mode Hermes Desk wants to support.

### 5. Do not depend on the current dashboard server shape as a production remote surface

- Chosen: Use the upstream dashboard implementation as proof that service-backed session APIs are viable, but document a unified authenticated backend surface as the target contract.
- Alternative considered: Point Hermes Desk directly at the current dashboard endpoints for remote usage.
- Why: The current dashboard is intentionally local-first and unauthenticated; baking that shape into Hermes Desk would turn a local admin tool into an accidental remote control plane.

## Risks / Trade-offs

- [Upstream Hermes may not expose authenticated session APIs on the same timeline as Desk changes] → Mitigation: keep local mode intact and document the backend dependency clearly in tasks and diagnostics.
- [Supporting both local and remote backends can complicate HermesKit abstractions] → Mitigation: introduce an explicit backend protocol for sessions/runs instead of scattering mode checks through UI code.
- [Fail-closed remote auth can make initial setup feel stricter than current localhost usage] → Mitigation: keep loopback development ergonomics unchanged while making remote diagnostics and setup guidance explicit.
- [Session identity mismatches could duplicate tasks or orphan transcripts] → Mitigation: treat backend session IDs as canonical and avoid client-generated aliases in remote mode.

## Migration Plan

1. Document the backend contract and security baseline in OpenSpec.
2. Refactor Hermes Desk backend access so session retrieval is abstracted behind service/local implementations.
3. Add remote configuration and diagnostics surfaces that clearly indicate auth requirements.
4. Integrate remote session APIs once the backend exists, while preserving local fallback behavior.
5. Only treat remote mode as complete after session APIs and run APIs share one authenticated deployment path.

## Open Questions

- Should the authenticated session endpoints live under `/api/sessions/*`, `/v1/sessions/*`, or another namespace that matches the run API more cleanly?
- Should remote auth remain a single Bearer key for self-hosted deployments, or should Hermes Desk plan for a future user-scoped token model?
- When remote mode is active, should Hermes Desk hide local transcript fallback entirely or expose it as an explicit diagnostic-only fallback?
