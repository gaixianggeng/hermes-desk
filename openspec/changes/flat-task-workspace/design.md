## Context

Hermes Desk already has a three-column task workspace, but until this change the middle pane still rendered transcript content as left/right chat bubbles. That presentation did not match the product direction of a task-first workstation where execution context, task status, and user-facing output should live in one coherent document flow.

The current Hermes contract also matters:
- Live run events expose `reasoning.available`, `message.delta`, tool events, approval events, and terminal run outcomes.
- Durable transcript storage already persists `reasoning` alongside message content.
- No structured checklist or task-list event exists yet, even though the UI direction clearly wants something like an inline task list.

This means the redesign can ship immediately for the flat workspace, and `thinking` can follow using real data, but `task list` needs an explicit strategy instead of guessing.

## Goals / Non-Goals

**Goals:**
- Reframe the main workspace as a flat, task-first canvas rather than a chat transcript.
- Reuse existing transcript, pending-message, and task-state data without introducing a new persistence model.
- Record the real Hermes data contract for `thinking` and `task list`.
- Preserve the current inspector and run-control behavior while improving the main workspace presentation.

**Non-Goals:**
- Replacing the underlying task/run/session architecture.
- Removing the right-side inspector in this phase.
- Claiming full structured task-list support before Hermes exposes a stable contract.
- Introducing a new backend dependency just to restyle the workspace.

## Decisions

### 1. Keep the current data flow and refactor the view layer first

The first implementation step keeps `AppStateStore`, transcript loading, and run-event handling intact, and focuses the redesign in `DashboardView`.

- Chosen: Recompose existing `WorkspaceFeedEntry` data into flat semantic cards in the main workspace.
- Alternative considered: Introduce a brand-new persistent workspace-block model first.
- Why: The current state layer already contains the required signals, and the UI benefit can land faster with lower migration risk.

### 2. Build the workspace from semantic blocks, not bilateral bubbles

The workspace should render request, response, progress, state, and artifact content as block cards in a single-column document flow.

- Chosen: Treat content as a task document with block semantics.
- Alternative considered: Keep bubble alignment and only soften the styling.
- Why: Bubble alignment keeps the product mentally anchored to a chat app and makes future `thinking` / `task list` sections feel secondary.

### 3. Treat Hermes reasoning as real `thinking` input

Hermes already exposes reasoning in two places: live run events and durable transcript messages.

- Chosen: Use `reasoning.available` and transcript `reasoning` as the basis for future `thinking` UI.
- Alternative considered: Synthesize `thinking` only from `progressHint` or generic status text.
- Why: Hermes already emits a stronger signal; using it reduces guessing and makes the UI closer to the real system behavior.

### 4. Treat `task list` as a protocol gap, not a solved UI problem

There is no structured checklist payload in the current Hermes event or transcript model.

- Chosen: Record the gap in OpenSpec and keep follow-up work explicit.
- Alternative considered: Immediately infer a checklist from arbitrary progress text and present it as if it were authoritative.
- Why: Heuristic extraction may still be useful later, but presenting it as a true task list without a contract would be misleading.

## Risks / Trade-offs

- [Large `DashboardView` remains a hotspot] → Mitigation: keep the first refactor local, then extract view components in a later cleanup pass if the layout stabilizes.
- [Progress vs. answer classification may still be imperfect] → Mitigation: continue tuning `HermesWorkspaceContentClassifier` as more real transcripts are observed.
- [Users may expect task-list support immediately after seeing the new layout] → Mitigation: record the Hermes contract gap clearly and avoid fake structured checklist UI.
- [The flat layout may reveal missing hierarchy in long tasks] → Mitigation: follow up with inline `thinking` sections and better grouping once the signal wiring is in place.

## Migration Plan

No data migration is required.

1. Keep the existing task/session/run models unchanged.
2. Roll out the flat workspace UI on top of current data.
3. Add `thinking` presentation using existing reasoning signals.
4. Decide whether `task list` should be heuristic, protocol-driven, or both before shipping that UI.

## Open Questions

- Should the first `task list` iteration use a heuristic parser for markdown checklists / `todo:` lines, or wait for a Hermes protocol addition?
- Should future inline `thinking` blocks live only in the main workspace, or also be reflected in the right-side inspector?
- Once the flat layout is established, should the inspector shrink, move, or merge some of its cards back into the main pane?
