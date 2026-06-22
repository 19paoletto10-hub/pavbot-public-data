# Pavbot SDLC

## Stage 1: Foundation

- Create repository structure and templates.
- Define the reusable `daily-research-agent` skill.
- Add one pilot topic.
- Verify workspace structure.

## Stage 2: Manual Pilot

- Run the pilot topic manually before scheduling.
- Confirm the report format is useful.
- Confirm the risk gate creates proposals instead of unsafe changes.
- Update the skill or templates when repeated corrections appear.

## Stage 3: Daily Automation

- Attach one daily heartbeat automation to the pilot topic thread.
- Review the first three daily reports.
- Track quality issues in the pilot backlog.
- Only add more topics after three acceptable pilot runs.

## Stage 4: Scale Topics

- Create one thread and one topic folder per research area.
- Keep topic contracts narrow.
- Reuse the same templates and skill.
- Archive or pause topics that stop producing useful signal.

## Stage 5: Server Orchestrator

- Add a Node.js 20 service using `@openai/codex-sdk`.
- Move scheduling, retry, and run metadata to the service.
- Keep reports and topic contracts in this repo.
- Deploy on VPS/Docker only after local automation quality is stable.
