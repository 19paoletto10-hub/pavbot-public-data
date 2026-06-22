# Automation Prompt: codex-agent-automation

```text
$daily-research-agent

Run the daily research workflow for `research/codex-agent-automation`.
Read `AGENTS.md`, `docs/architecture.md`, the topic contract, index, backlog,
and latest run report before researching.

Use current sources for facts that may have changed. Prefer official OpenAI
Codex documentation and verified current-session tool behavior. Record source
links for every material claim.

Write today's report to `research/codex-agent-automation/runs/YYYY-MM-DD.md`.
Update `research/codex-agent-automation/index.md` when the current
understanding changes. Update `research/codex-agent-automation/backlog.md`
when there are actionable follow-ups, review notes, open questions, or resolved
items.

After writing run artifacts, refresh the public iOS manifest with:
`python3 scripts/generate_pavbot_manifest.py`.

Use the risk gate from `docs/architecture.md`. If a recommended action would
change automations, repo-wide instructions, skills, hooks, MCP configuration,
dependencies, or files outside the active topic, create a proposal in
`research/codex-agent-automation/proposals/` instead of applying it.

If there are no material changes, still create a short dated report with
`Status: No material change`, a concise summary, and the sources checked.
```
