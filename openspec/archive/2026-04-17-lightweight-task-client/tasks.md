## 1. Product Scope

- [x] 1.1 Record the task-first, display-first Desk model as the active product direction
- [x] 1.2 Explicitly mark direct local Hermes storage reads as out of scope for the default workflow
- [x] 1.3 Confirm that Desk should align with Telegram/Lark/Slack/Discord delivery semantics: show the answer first, reconcile history second

## 2. Current-Turn Delivery

- [x] 2.1 Materialize the final assistant reply from `run.completed.output` directly into the Desk transcript/cache
- [x] 2.2 Keep draft/live streaming messages visible through run completion without making transcript hydration a prerequisite
- [x] 2.3 Treat `syncing` placeholders as secondary status UI only; never let them replace a known final answer
- [x] 2.4 Make Desk SSE parsing resilient when event frames are not separated by blank lines
- [x] 2.5 Expose task event replay alongside assistant replies in the workspace full transcript view for debugging parity with messaging clients

## 3. Run-Only Backend Contract

- [x] 3.1 Keep `AgentBackend` and `HermesLocalAdapter` centered on run start, run action, and run SSE transport for phase 1
- [x] 3.2 Reuse stable `session_id` values for follow-up prompts inside the same task
- [x] 3.3 Ensure the current turn succeeds visibly even when no transcript/session reconciliation path exists
- [x] 3.4 Accept both legacy and newer run-event envelope shapes (`event`/`type` aliases) on the Desk client side

## 4. Client State Ownership

- [x] 4.1 Keep the client-owned task state minimal and scoped to active task/workspace rendering
- [x] 4.2 Remove any remaining assumptions that transcript hydration must complete before the current answer is shown
- [x] 4.3 Avoid introducing direct local Hermes storage reads as a fallback path
- [x] 4.4 Keep Xcode-hosted/test app instances off the real Desk cache to prevent cross-process state pollution
- [x] 4.5 Prevent a new-task draft from auto-switching back to another live task while background runs continue streaming

## 5. Verification

- [x] 5.1 Add tests covering task creation, continuation, approvals, and final-answer visibility when transcript hydration never arrives
- [x] 5.2 Add tests covering task-scoped relaunch behavior from lightweight client-owned state
- [x] 5.3 Add tests covering malformed or unknown SSE frames without losing the final answer
- [x] 5.4 Validate that the existing Dashboard/workspace UI still renders correctly with the new internal data flow
- [x] 5.5 Add regression coverage for SSE streams that omit blank-line event separators
- [x] 5.6 Add regression coverage for keeping selection pinned while composing a new task

## 6. Later Phase (Explicitly Deferred)

- [ ] 6.1 Evaluate transcript/session APIs for restoration and reconciliation after the run-only milestone is stable
- [ ] 6.2 Decide whether those later APIs should come from the dashboard server or the gateway service
