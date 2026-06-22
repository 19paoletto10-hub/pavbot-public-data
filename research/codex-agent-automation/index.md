# Topic Index: codex-agent-automation

Last updated: 2026-06-17

## Current Understanding

The MVP should use Codex App/CLI as the local agent runtime and this repository
as durable memory. Each research topic should have a dedicated Codex thread, a
daily heartbeat automation, and Markdown artifacts under `research/<topic>/`.
The reusable workflow lives in `.agents/skills/daily-research-agent/SKILL.md`.
Daily runs need an explicit policy for official docs refreshes when sandboxed
network access blocks command-line fetches.

## Stable Facts

- Codex automations can run recurring background tasks and can be paired with
  skills for more complex workflows. Source:
  [Codex Automations](https://developers.openai.com/codex/app/automations).
- Project-scoped Codex automations depend on the local Codex app machine being
  powered on, Codex running, and the selected project still existing on disk at
  the scheduled time. Source:
  [Codex Automations](https://developers.openai.com/codex/app/automations).
- Thread automations are heartbeat-style recurring wakeups attached to a
  conversation, useful when scheduled work should preserve thread context.
  Source: [Codex Automations](https://developers.openai.com/codex/app/automations).
- In Git repositories, automations can run in the local project or in a
  dedicated worktree; worktrees isolate automation changes from unfinished local
  work, while local mode may change files currently being edited. Source:
  [Codex Automations](https://developers.openai.com/codex/app/automations).
- Automations use the default sandbox settings. Read-only mode blocks writes,
  network access, and app control; full access raises unattended-write risk; and
  automations use `approval_policy = "never"` when organization policy allows.
  Source: [Codex Automations](https://developers.openai.com/codex/app/automations).
- Codex skills package task-specific instructions, resources, and optional
  scripts. Source: [Codex Skills](https://developers.openai.com/codex/skills).
- Codex supports MCP servers for tools and context such as docs, browsers,
  Figma, Sentry, and GitHub. Source:
  [Codex MCP](https://developers.openai.com/codex/mcp).
- Codex hooks can run lifecycle scripts around tool use, prompts, compaction,
  subagents, and stop events. Source:
  [Codex Hooks](https://developers.openai.com/codex/hooks).
- The Codex SDK can control Codex programmatically and is the preferred path
  for future CI/CD or server orchestration. Source:
  [Codex SDK](https://developers.openai.com/codex/sdk).

## Open Questions

- Which exact research topics should be added after the pilot passes three
  reviewed daily runs?
- Should V2 use the TypeScript Codex SDK or Python SDK for server orchestration?
- Which sources should be allowlisted per topic to reduce low-signal web
  research?
- Should unattended runs receive narrow network access for official OpenAI docs,
  or should reports explicitly use cached docs when refresh is blocked?

## Watch Items

- Changes to Codex automation scheduling, worktree handling, and permissions.
- Local app uptime, project availability, and sandbox mode for scheduled runs.
- Changes to skill discovery paths or metadata requirements.
- Availability and stability of SDK/app-server APIs for a future VPS runner.
- Cost, token usage, and report noise after the first three daily runs.
- Official docs refresh behavior in sandboxed automations.

## Recent Reports

- [2026-06-17](runs/2026-06-17.md)
