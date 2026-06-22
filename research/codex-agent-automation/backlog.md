# Topic Backlog: codex-agent-automation

## Active

| Priority | Item | Reason | Next Step | Status |
| --- | --- | --- | --- | --- |
| High | Review first three daily reports | Confirms source quality, deduplication, and risk gate behavior before scaling topics | Add notes after each scheduled run | Open |
| High | Resolve official docs network access for unattended runs | Fresh Codex documentation required explicit network approval during the first heartbeat | Review proposal `proposals/2026-06-17-docs-network-access.md` | Open |
| Medium | Decide next two topic threads | Scaling should wait until pilot quality is proven | Choose topics after three reviewed runs | Open |
| Medium | Evaluate SDK language for V2 | Server orchestration can use TypeScript or Python, but MVP should stay local | Compare after local automation stabilizes | Open |
| Low | Add source allowlist guidance | Reduces low-signal web results over time | Convert repeated good sources into topic policy | Open |

## Review Notes

- 2026-06-17: Bootstrap scaffold created. First scheduled automation run still
  needs manual review.
- 2026-06-17: First heartbeat run completed. Official docs refresh succeeded
  only after explicit network approval, so a risk-gated proposal was created
  before changing automation or sandbox policy.
- 2026-06-17: Same-day manual refresh reported the local Codex manual cache was
  current. Added automation runtime and sandbox prerequisites to the index; the
  unattended docs access proposal remains open.

## Done

| Date | Item | Outcome |
| --- | --- | --- |
| 2026-06-17 | Create pilot topic scaffold | Topic contract, index, backlog, bootstrap report, and automation prompt added |
