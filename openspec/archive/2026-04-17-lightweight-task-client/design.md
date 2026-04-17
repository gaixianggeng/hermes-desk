## Context

Hermes Desk already has the right visible shell for a run-oriented client: it
can create tasks, stream run events, surface approvals, and keep working inside
the same workspace. The first phase does not need to solve full session
rehydration or transcript browsing. It only needs to make task-scoped run
delivery work with the same principle as Hermes messaging clients.

Telegram, Lark, Slack, and Discord clients are display-first:

- the user-visible assistant reply comes directly from the active run
- the platform adapter sends or edits that reply immediately
- persistence exists for continuity, but it does not gate whether the user sees
  the current answer

Desk should adopt that same delivery principle for the current turn while
remaining task-first. Transcript/session reconciliation is a later phase, not a
first-phase dependency.

## Goals / Non-Goals

**Goals:**
- Keep the existing Desk UI layout and user interaction model.
- Make the current turn's final answer visible directly from run transport data.
- Keep the first-phase backend contract limited to public run APIs.
- Preserve task continuation through stable `session_id` values when available.
- Avoid direct local Hermes storage reads in the default workflow.

**Non-Goals:**
- Building a full backend-powered history browser for all Hermes sessions.
- Enumerating or searching arbitrary Hermes sessions from Desk.
- Adding transcript/session API dependencies to the first-phase implementation.
- Depending on `state.db` or other direct local Hermes storage reads for the default workflow.
- Redesigning Dashboard or workspace UI structure in this change.

## Decisions

### 1. Desk stays task-first, but becomes display-first within a task

- Chosen: Keep Desk centered on tasks created and continued by the client, but make the current turn's visible assistant answer come directly from run transport (`message.delta` and `run.completed.output`).
- Alternative considered: Continue treating transcript synchronization as a prerequisite for showing the final answer.
- Why: Telegram/Lark/Slack/Discord already prove that users care first about seeing the answer, not about whether the transcript reconciliation finished. Desk should match that reliability model.

### 2. The first-phase backend contract is run-only

- Chosen: Require only:
  - `POST /v1/runs`
  - `GET /v1/runs/{id}/events`
  - run action endpoints
- Alternative considered: Add transcript/session APIs in the first phase.
- Why: The first milestone is to make Desk behave like tg/lark in current-turn delivery, not to build history reconciliation. Run APIs are sufficient for that narrower goal.

### 3. Session identifiers remain the continuity key

- Chosen: Keep stable `session_id` values on Desk tasks for follow-up continuity across runs in the same task.
- Alternative considered: Remove session IDs from the Desk task model and replay the whole conversation from local state on every turn.
- Why: Reusing `session_id` is already part of the run contract and keeps continuation semantics aligned with the messaging clients.

### 4. The existing UI stays intact while data priorities change underneath

- Chosen: Preserve the current task list, workspace, and transcript presentation, but change where their data comes from.
- Alternative considered: Redesign the UI to better fit an ephemeral chat/task model.
- Why: The request is explicitly to keep the interface unchanged and only adjust internal query logic.

### 5. Sync placeholders remain secondary to final-answer visibility

- Chosen: Keep "working" and "syncing" placeholders as status affordances, but never let them become the only visible artifact of a completed turn when `run.completed.output` is available.
- Alternative considered: Keep the current placeholder-driven state machine where the final answer appears only after transcript hydration.
- Why: Placeholders are useful for transparency, but they are not the product. The answer is the product.

### 6. SSE parsing must not depend on blank-line frame separators

- Chosen: Make the Desk SSE parser flush on explicit separators when present, but also tolerate streams where consecutive `data:` lines represent distinct events without intervening blank lines.
- Alternative considered: Assume URLSession line iteration will always preserve SSE blank lines exactly as the server wrote them.
- Why: Real Hermes gateway runs proved that valid `message.delta` / `run.completed` payloads could still be lost when the client-side line stream omitted expected blank separators. The parser has to be robust to transport quirks, not just spec-perfect framing.

### 7. Xcode-hosted Desk instances must not share the real user cache

- Chosen: Route test-hosted or Xcode-launched Desk processes to an ephemeral cache store.
- Alternative considered: Keep all local Desk processes pointed at the same Application Support cache file.
- Why: During debugging, multiple Xcode-hosted Desk instances could overwrite the same `task-cache.json`, obscuring whether a live run actually failed or whether a second process simply rewrote the local state.

### 8. Full transcript mode should include task event replay, and Inspector should merge “Now” + “Progress”

- Chosen: In the phase-1 debugging posture, the workspace full transcript includes task event replay (tool/log/status/approval/error events) alongside user and assistant messages, and the Inspector combines the former “Progress” content under the “Now” tab.
- Alternative considered: Keep tool/log/progress details isolated behind a separate Inspector tab and keep the center transcript limited to user/assistant messages only.
- Why: Telegram-style debugging makes the full call chain visible inline. Putting the event trail in the same timeline and reducing the Inspector to two tabs lowers navigation overhead while the lightweight task client is still being hardened.

### 9. New-task composition must pin selection until the new run exists

- Chosen: Introduce a temporary “new task” selection hold so background updates from other live runs cannot reclaim focus while the user is composing a fresh task.
- Alternative considered: Continue clearing selection outright and let automatic task prioritization re-select whichever task currently appears most urgent.
- Why: When another conversation was actively streaming, creating a new task could auto-switch the workspace back to the older run before the new request was submitted. The client should respect the explicit user intent to stay on the new-task draft.

## Risks / Trade-offs

- [Without transcript/session APIs, Desk relaunch and cross-device recovery remain limited in phase 1] → Mitigation: make that limit explicit and optimize only for active-task continuity in the first milestone.
- [Current turn data may still be lost if both live SSE and the final run payload fail] → Mitigation: make `run.completed.output` authoritative whenever it exists and keep SSE parsing resilient to single bad frames.
- [Tasks created outside this Desk client remain out of scope for the first phase] → Mitigation: keep the product task-first and avoid silently expanding into a full Hermes history browser.
- [Inlining task events into the full transcript view increases noise for non-debug scenarios] → Mitigation: keep this behavior scoped to full transcript mode and preserve the conversation-only mode for reduced-noise reading.
- [Retaining temporary debug logging can add disk churn and expose noisy internal payloads] → Mitigation: keep the log file local to Application Support and treat it as a temporary debugging aid to remove after stabilization.

## Migration Plan

1. Document the lightweight task-client model in OpenSpec.
2. Refactor the Desk delivery path so `run.completed.output` materializes a final visible assistant message immediately.
3. Keep Desk continuation, action handling, and live observation on the existing public Hermes run APIs.
4. Remove first-phase assumptions that transcript/session hydration is required before showing the final answer.
5. Harden SSE parsing and local client-state ownership against real transport/process edge cases.
6. Add tests proving the Desk matches the display-first behavior of Telegram/Lark-style clients.

## Open Questions

- What is the smallest durable client cache format that preserves fast relaunch without turning the first phase into a history-sync project?
- Should the task list persist across app relaunch in phase 1, or is it acceptable to scope restoration to active client-owned tasks only?
- When transcript/session APIs are added in a later phase, should they come from the existing dashboard server or be folded into the gateway service?
