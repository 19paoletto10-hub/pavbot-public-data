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
- refresh the manifest after writing artifacts.

The manifest refresh command is:

```bash
python3 scripts/generate_pavbot_manifest.py
```

## 3. Generate Public Raw URLs

For the iOS app to preview Markdown, PDFs, JSON, and audio, generate the
manifest with your public GitHub raw base URL.

Use this form:

```bash
python3 scripts/generate_pavbot_manifest.py --raw-base-url "https://raw.githubusercontent.com/<owner>/<repo>/<branch>/"
```

Example:

```bash
python3 scripts/generate_pavbot_manifest.py --raw-base-url "https://raw.githubusercontent.com/acme/pavbot-workspace/main/"
```

You can also set the environment variable instead of passing the flag:

```bash
export PAVBOT_RAW_BASE_URL="https://raw.githubusercontent.com/<owner>/<repo>/<branch>/"
python3 scripts/generate_pavbot_manifest.py
```

Commit and push the updated manifest:

```bash
git add public/pavbot-manifest.json
git commit -m "Refresh Pavbot manifest"
git push
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
- If previews do not open, regenerate the manifest with `PAVBOT_RAW_BASE_URL`
  or `--raw-base-url`.
- If no new files appear, confirm Codex automations are writing into
  `research/<topic>/` and then regenerate `public/pavbot-manifest.json`.
- If your repository is private, use a public repository for v1 or add a future
  authenticated access layer.
