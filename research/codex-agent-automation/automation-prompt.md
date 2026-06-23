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

After writing run artifacts, publish the outputs for the iOS app and push
notification webhook. The script runs `python3 scripts/generate_pavbot_manifest.py`,
refreshes `public/pavbot-manifest.json`, commits only allowed paths, and pushes
to `origin/main`. `PAVBOT_MANIFEST_URL` must be set in the Codex or repository
environment to the same public raw manifest URL used in iOS
`Settings -> Manifest URL`; the iOS app does not send this value back to Codex.
Then run:
`scripts/pavbot_commit_and_push_outputs.sh research/codex-agent-automation`.

Use the risk gate from `docs/architecture.md`. If a recommended action would
change automations, repo-wide instructions, skills, hooks, MCP configuration,
dependencies, or files outside the active topic, create a proposal in
`research/codex-agent-automation/proposals/` instead of applying it. The final
publish step may commit only `research/codex-agent-automation/` and
`public/pavbot-manifest.json`.

If there are no material changes, still create a short dated report with
`Status: No material change`, a concise summary, and the sources checked.
```
