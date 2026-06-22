# Proposal: Official Docs Network Access For Daily Research

Date: 2026-06-17
Topic: codex-agent-automation
Risk: Medium

## Proposed Change

Decide how unattended daily research runs should refresh official OpenAI Codex
documentation when the command sandbox blocks network access.

## Reason

During the first heartbeat run, the official Codex manual helper failed to
resolve `developers.openai.com` inside the sandboxed command context. The same
helper succeeded after explicit network approval and reported that the cached
manual was current.

The daily research workflow depends on current official docs for changing
Codex behavior. Without a policy, unattended runs can silently fall back to
stale cached docs or stop before producing useful research.

## Files Or Settings Affected

- Codex sandbox or rules configuration for this project.
- Daily research automation prompt and operating notes.
- Optional future MCP/OpenAI Docs setup.

## Acceptance Criteria

- Unattended runs either have approved access to official Codex documentation
  sources or explicitly report that they used cached documentation.
- Reports cite whether official docs were freshly refreshed or cached.
- The solution does not grant broad network access beyond what the research
  workflow needs.

## Rollback

Remove the network allowance or revert the prompt/config change. Future reports
should then state when docs could not be refreshed and use the last cached
manual only as a bounded fallback.
