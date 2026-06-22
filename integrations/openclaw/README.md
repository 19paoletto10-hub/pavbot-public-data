# OpenClaw Integration Option

This folder documents how OpenClaw could observe Pavbot later. It is not an
OpenClaw installation and does not start any OpenClaw process.

## Recommendation

Keep Pavbot Codex-native until the `codex-agent-automation` pilot has three
reviewed daily reports. Add OpenClaw only if you need:

- A persistent personal assistant running 24/7.
- Messaging channels such as Telegram, WhatsApp, Discord, or Slack.
- Multi-agent routing with separate workspaces and identities.
- A VPS or Mac Mini agent runtime outside the Codex app.

Do not use OpenClaw as the primary writer for this repository at first. Use it
as an observer that reads Pavbot reports and creates proposals.

## Safe Shape

Recommended initial shape:

- One OpenClaw agent named `pavbot-observer`.
- A dedicated OpenClaw workspace outside this repo.
- Read-only access to Pavbot research artifacts where possible.
- Sandbox enabled before the agent receives write access.
- No OpenClaw credentials, sessions, or state committed to this repository.

## Why Not Put OpenClaw Inside This Repo?

OpenClaw has its own state, credentials, session history, and workspace model.
Its workspace is the default working directory for tools, but OpenClaw documents
that a workspace is not a hard sandbox unless sandboxing is enabled.

Putting the runtime inside this repository would mix source-controlled Pavbot
artifacts with agent state and credentials. Keep those separate.

## Files In This Folder

- `openclaw.sample.json5` - non-secret config sketch for a future observer
  agent.
- `workspace/AGENTS.md` - example operating rules for the OpenClaw observer.
- `workspace/SOUL.md` - example tone/personality file.
- `workspace/TOOLS.md` - example tool boundaries.
- `workspace/HEARTBEAT.md` - example recurring checklist.

Copy these into an OpenClaw workspace only after explicitly deciding to test
OpenClaw.

## Sources

- OpenClaw workspace docs:
  https://docs.openclaw.ai/concepts/agent-workspace
- OpenClaw agent config docs:
  https://docs.openclaw.ai/gateway/config-agents
- OpenClaw context docs:
  https://docs.openclaw.ai/concepts/context
- OpenClaw sandboxing docs:
  https://docs.openclaw.ai/gateway/sandboxing
- OpenClaw security docs:
  https://docs.openclaw.ai/gateway/security
