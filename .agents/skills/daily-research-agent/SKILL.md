---
name: daily-research-agent
description: Run a daily research workflow for a Pavbot topic. Use when Codex is asked to create a dated research report, update a topic index or backlog, deduplicate repeated findings, or operate a risk-gated Web and repo research automation in a topic folder under research.
---

# Daily Research Agent

Run one research cycle for a single Pavbot topic.

## Inputs

1. Identify the active topic folder from the user prompt. If no topic is named,
   use the only folder under `research/` that contains `topic.md`. If multiple
   topics exist and none is named, ask the user which topic to run.
2. Read, in this order:
   - `AGENTS.md`
   - `docs/architecture.md`
   - `research/<topic>/topic.md`
   - `research/<topic>/index.md`
   - `research/<topic>/backlog.md`
   - the latest file in `research/<topic>/runs/`, if one exists

## Workflow

1. Determine today's date in the user's locale.
2. Build a short research plan from the topic goal, keywords, source policy,
   and "Report When" criteria.
3. Search or inspect current sources when the topic depends on changing facts.
   Prefer official or primary sources. Record every material source link.
4. Compare findings with the topic index and latest report.
5. Write `research/<topic>/runs/YYYY-MM-DD.md`.
6. Render a professional PDF version of the report to
   `research/<topic>/pdfs/YYYY-MM-DD-<topic>.pdf` using
   `scripts/render_research_pdf.py` when that script exists.
7. Update `research/<topic>/index.md` when the current understanding changes.
8. Update `research/<topic>/backlog.md` when there are actionable follow-ups,
   review notes, open questions, or resolved items.
9. Use the risk gate before making any change.

## Risk Gate

Low-risk changes may be applied directly:

- Create the dated report inside the active topic.
- Create the PDF version of the dated report inside the active topic.
- Update the active topic index or backlog.
- Add source links and concise notes.
- Mark an existing topic backlog item as done.

Create a proposal instead of applying medium-risk or high-risk changes:

- Creating, updating, deleting, or rescheduling automations.
- Changing skills, hooks, MCP config, repo-level instructions, dependencies, or
  files outside the active topic folder.
- Running destructive commands or broad filesystem operations.
- Taking action based on legal, medical, financial, security, or safety claims.

Write proposals to `research/<topic>/proposals/YYYY-MM-DD-<slug>.md` using
`research/templates/proposal-template.md`.

## Report Format

Use `research/templates/run-report-template.md`. Include:

- Date and materiality status.
- Scope checked.
- Summary.
- New facts.
- Changes since previous run.
- Risks or uncertainty.
- Recommended actions.
- Sources.

## PDF Output

When the topic request asks for a PDF or when `scripts/render_research_pdf.py`
exists, create the PDF after writing the Markdown report:

```bash
python3 scripts/render_research_pdf.py research/<topic>/runs/YYYY-MM-DD.md research/<topic>/pdfs/YYYY-MM-DD-<topic>.pdf --topic <topic>
```

Prefer the bundled Codex workspace Python runtime when available because it
includes PDF dependencies. Render the PDF pages with `pdftoppm` and visually
check legibility, spacing, page numbers, Polish characters, tables, and links
before claiming success.

If nothing material changed, still create a short report with
`Status: No material change`, the sources checked, and one concise summary
sentence. Do not pad it with filler.

## Quality Rules

- Do not duplicate yesterday's findings unless there is a new material change.
- Separate sourced facts from interpretation.
- Prefer fewer, better sources over broad low-quality source lists.
- Keep recommendations actionable.
- Ask for user input when the topic contract is missing, ambiguous, or has
  multiple plausible active topic folders.
