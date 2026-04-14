## 1. OpenSpec Adoption

- [x] 1.1 Install the OpenSpec CLI on the current machine
- [x] 1.2 Initialize this repository for Codex with `openspec init`
- [x] 1.3 Capture the workspace redesign and follow-up work as an OpenSpec change

## 2. Flat Workspace UI

- [x] 2.1 Replace the bubble-based middle pane with a flat task-first canvas
- [x] 2.2 Recompose workspace content into semantic request, response, progress, status, and result blocks
- [x] 2.3 Restyle the task composer and workspace chrome to match the flat layout

## 3. Hermes Signal Research

- [x] 3.1 Confirm how Hermes exposes live reasoning/thinking data through run events
- [x] 3.2 Confirm how Hermes persists durable reasoning data in transcript storage
- [x] 3.3 Confirm that Hermes does not currently expose a structured task-list payload

## 4. Follow-up Implementation

- [ ] 4.1 Surface inline thinking blocks from Hermes reasoning events and transcript reasoning
- [ ] 4.2 Decide whether the first task-list iteration should be heuristic, protocol-driven, or both
- [ ] 4.3 Implement the chosen task-list strategy without misrepresenting unstructured progress text as authoritative checklist data
- [ ] 4.4 Re-validate the workspace UX after thinking/task-list follow-up work lands
- [ ] 4.5 Add a Settings entry for `API_SERVER_KEY` so Hermes Desk can edit runtime auth configuration without manual `.env` changes
