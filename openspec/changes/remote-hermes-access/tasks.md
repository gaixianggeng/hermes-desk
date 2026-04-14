## 1. Backend Contract

- [ ] 1.1 Document the required remote session endpoints and response shapes for list, search, detail, and messages
- [ ] 1.2 Document the shared authentication policy Hermes Desk expects for remote session and run endpoints
- [ ] 1.3 Confirm the upstream Hermes implementation path for exposing authenticated session APIs alongside the existing run APIs

## 2. HermesKit Backend Abstraction

- [ ] 2.1 Introduce a backend abstraction that separates local transcript access from service-backed session access
- [ ] 2.2 Add remote configuration fields and diagnostics for endpoint URL, auth state, and backend mode selection
- [ ] 2.3 Preserve local-only transcript fallback behavior without making it a requirement for remote mode

## 3. Remote Session Workflows

- [ ] 3.1 Implement HTTP clients for remote session list, search, detail, and message-history APIs
- [ ] 3.2 Update task hydration and transcript loading flows to use service-backed session APIs in remote mode
- [ ] 3.3 Add failure handling for remote session lookup, auth rejection, and partial transcript availability

## 4. Remote Run Workflows

- [ ] 4.1 Reuse backend session identifiers when starting or continuing remote Hermes runs
- [ ] 4.2 Keep `/v1/runs` and `/v1/runs/{id}/events` integrated with remote auth and diagnostics
- [ ] 4.3 Validate remote SSE behavior for progress, approvals, failures, and completion states

## 5. Verification and Rollout

- [ ] 5.1 Add tests covering loopback-local mode versus authenticated remote mode
- [ ] 5.2 Add user-facing setup guidance for remote Hermes access and security expectations
- [ ] 5.3 Re-run the remote workflow against an upstream Hermes build that exposes the required session APIs
