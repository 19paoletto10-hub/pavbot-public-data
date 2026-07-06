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

After writing run artifacts, publish the outputs for the iOS app through the
only required production gate:
`scripts/pavbot_commit_and_push_outputs.sh --isolated research/codex-agent-automation`.

Skrypt publikacji jest jedyną bramką produkcyjną; sam odświeża manifest,
publikuje artefakty na origin/main, weryfikuje zdalny stan oraz tworzy i
weryfikuje CloudKit Briefing. Produkcyjny flow iOS pozostaje: artefakty +
`public/pavbot-manifest.json` na origin/main, potem CloudKit Briefing w
`iCloud.com.paweltanski.pavbotviewer` / `production` / `SP774TZZU8`, potem
APNs. Skrypt sam wyprowadza `PAVBOT_MANIFEST_URL` z override środowiskowego,
`PAVBOT_RAW_BASE_URL`, istniejącego `rawBaseUrl` w manifeście albo GitHub
`origin`; ustaw zmienną ręcznie tylko dla niestandardowego URL. Jeśli skrypt
zwróci błąd, traktuj przebieg jako failed albo partially published; ręczne
komendy są dozwolone wyłącznie do diagnostyki, nie do dokańczania produkcyjnej
publikacji.

Use the risk gate from `docs/architecture.md`. If a recommended action would
change automations, repo-wide instructions, skills, hooks, MCP configuration,
dependencies, or files outside the active topic, create a proposal in
`research/codex-agent-automation/proposals/` instead of applying it. The final
publish step may commit only `research/codex-agent-automation/runs/`,
`research/codex-agent-automation/pdfs/`,
`research/codex-agent-automation/podcasts/`,
`research/codex-agent-automation/index.md`,
`research/codex-agent-automation/backlog.md`, and
`public/pavbot-manifest.json`.

If there are no material changes, still create a short dated report with
`Status: No material change`, a concise summary, and the sources checked.
```
