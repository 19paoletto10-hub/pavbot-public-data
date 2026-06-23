# Connect The iOS App To Your Codex Repository

This guide explains how to connect the Pavbot iOS app to your own
Codex-backed repository. Version 1 uses a public GitHub raw manifest URL. The
iOS app does not sign in to GitHub, store tokens, or read private repositories.

## Requirements

- A GitHub repository that contains this Pavbot workspace structure.
- Codex automations connected to that repository or project.
- Automation outputs written under `research/<topic>/`.
- A public `public/pavbot-manifest.json` file committed to the repository.

Private repositories are not supported in v1. Supporting private repositories
would require a later GitHub OAuth/token flow or a backend proxy.

## 1. Prepare Your Repository

Fork or copy this repository into your own GitHub account or organization.
Keep the core folders:

- `.agents/`
- `docs/`
- `public/`
- `research/`
- `scripts/`

Codex should write reports, PDFs, podcast files, and proposals inside
`research/<topic>/`. The iOS app reads those outputs through the generated
manifest.

## 2. Connect Codex Automations

Create or configure Codex automations for your repository. Each automation
should:

- run the relevant Pavbot skill, such as `$daily-research-agent`;
- write outputs under `research/<topic>/`;
- set `PAVBOT_MANIFEST_URL` to the same public raw manifest URL that the user
  enters in the iOS app;
- publish the topic outputs after writing artifacts.

The recommended publication command is:

```bash
export PAVBOT_MANIFEST_URL="https://raw.githubusercontent.com/<owner>/<repo>/<branch>/public/pavbot-manifest.json"
scripts/pavbot_commit_and_push_outputs.sh --isolated research/<topic>
```

The iOS app does not send this value back to Codex automations. Keep the same
URL configured in the automation or repository environment.

## 3. Generate Public Raw URLs

For the iOS app to preview Markdown, PDFs, JSON, and audio, the manifest must
contain public GitHub raw URLs. The generator derives those artifact URLs from
`PAVBOT_MANIFEST_URL`.

Use this form, which is the same URL you paste into the iOS app:

```bash
export PAVBOT_MANIFEST_URL="https://raw.githubusercontent.com/<owner>/<repo>/<branch>/public/pavbot-manifest.json"
scripts/pavbot_commit_and_push_outputs.sh --isolated research/<topic>
```

Example:

```bash
export PAVBOT_MANIFEST_URL="https://raw.githubusercontent.com/acme/pavbot-workspace/main/public/pavbot-manifest.json"
scripts/pavbot_commit_and_push_outputs.sh --isolated research/tech-news
```

Example for the current public Pavbot data repository:

```bash
export PAVBOT_MANIFEST_URL="https://raw.githubusercontent.com/19paoletto10-hub/pavbot-public-data/main/public/pavbot-manifest.json"
scripts/pavbot_commit_and_push_outputs.sh --isolated research/tech-news
```

The isolated publish script creates a temporary clean worktree from
`origin/main`, copies only generated outputs from the selected topic, runs
`python3 scripts/generate_pavbot_manifest.py`, commits those outputs with
`public/pavbot-manifest.json`, and pushes to `origin/main`. This lets
automation results publish even when a separate app/backend development branch
has local changes.

Only `runs/`, `pdfs/`, `podcasts/`, `index.md`, `backlog.md`, and
`public/pavbot-manifest.json` are allowed in these output commits. Code, docs,
prompt edits, credentials, configuration changes, and topic `tools/` changes
must be committed separately.

Advanced compatibility mode is still available when you want to pass the repo
root raw URL directly:

```bash
python3 scripts/generate_pavbot_manifest.py --raw-base-url "https://raw.githubusercontent.com/<owner>/<repo>/<branch>/"
```

If you only need to regenerate the manifest without publishing topic artifacts,
you can still run:

```bash
python3 scripts/generate_pavbot_manifest.py
```

## 4. Copy The Manifest URL

The URL to paste into the iOS app is:

```text
https://raw.githubusercontent.com/<owner>/<repo>/<branch>/public/pavbot-manifest.json
```

Example:

```text
https://raw.githubusercontent.com/acme/pavbot-workspace/main/public/pavbot-manifest.json
```

The URL must use `https` and must point to a `.json` file.

## 5. Configure The iOS App

Open the Pavbot iOS app and go to:

```text
Settings -> Manifest URL -> Save and reload
```

Paste the public manifest URL, then tap `Save and reload`.

After reload:

- `Automations` should show your enabled Codex automations.
- `Artifacts` should show generated files grouped by day.
- `Diagnostics` should show manifest freshness, URL status, and any missing
  public raw URL warnings.

## Troubleshooting

- If the app says the URL is invalid, confirm it starts with `https://` and
  ends with `.json`.
- If previews do not open, publish the topic with `PAVBOT_MANIFEST_URL` set to
  the same URL used in iOS `Settings -> Manifest URL`.
- If no new files appear, confirm Codex automations are writing into
  `research/<topic>/` and then running
  `scripts/pavbot_commit_and_push_outputs.sh --isolated research/<topic>`.
- If your repository is private, use a public repository for v1 or add a future
  authenticated access layer.
