# Topic Backlog: tech-news

## Active

| Priority | Item | Reason | Next Step | Status |
| --- | --- | --- | --- | --- |
| High | Review first three generated podcasts | Confirms pacing, topic selection, MP3 generation, and Polish narration quality | Listen to each MP3 and record notes | Open |
| Medium | Improve Reddit fallback | Direct public Reddit fetch failed in this run, limiting community-signal coverage | Decide whether HN plus secondary reporting is enough or add another public Reddit access path | Open |
| Medium | Tune source allowlist | Repeated good sources should become explicit topic guidance | Review source quality after three runs | Open |
| Medium | Tune XTTS long-form rendering | XTTS worked for short samples but was too slow for the 2026-06-18 full podcast and warned about sentence length limits | Consider sentence chunking or use Piper as scheduled-production default | Open |
| Medium | Track GitHub malware cleanup | The 2026-06-19 report surfaced a large campaign using copied GitHub repos and ZIP payloads | Recheck GitHub/OrchidFiles or reputable secondary coverage in the next run | Open |
| Medium | Track Midjourney Medical claims | The announcement is a strong podcast topic but has medical/regulatory risk | Separate product claims, research trials, FDA status, and independent validation in follow-up coverage | Open |
| Medium | Watch Android agent APIs | Android 17 AppFunctions and Android MCP may become a durable agent-platform storyline | Recheck developer adoption and examples after the initial release cycle | Open |
| Medium | Track AI in schools regulation | Norway introduced a strong age-based AI restriction signal that may spread in Europe | Recheck Nordic/EU education policy and Polish ministry commentary in later runs | Open |
| Medium | Track European AI sovereignty stack | France is pairing public-sector AI funding with ChapsVision/Palantir replacement and AI Gigafactories | Watch France, Mistral, EU AI Gigafactories and Polish equivalents | Open |
| Medium | Track AI chip alternatives | Google TPUs and Amazon Trainium are moving from internal cloud optimization toward external compute businesses | Watch customer adoption, financing risk and Nvidia response | Open |
| High | Track agent-ready deployment infrastructure | Cloudflare Temporary Accounts remove signup/auth friction for AI agents deploying code | Watch Cloudflare, Vercel, Netlify, Fly.io, Replit and auth.md-style flows | Open |
| High | Track AI control standards | Google DeepMind's AI Control Roadmap may become a reference point for agent permissions, monitoring and incident response | Recheck follow-up papers, policy reactions and competing frameworks | Open |
| High | Track Anthropic export-control resolution | Fable/Mythos shows frontier models becoming export-control and national-security assets | Watch Anthropic statements, Commerce actions, Axios/Bloomberg follow-ups and international response | Open |
| Medium | Track Teams workplace telemetry | Microsoft Teams workplace check-in via Wi-Fi is a clear privacy and work-policy podcast topic | Recheck rollout, user controls, EU/Polish privacy commentary and employer adoption | Open |
| Medium | Track AUR malware aftermath | AUR incident extends the supply-chain security storyline beyond GitHub clone malware | Recheck Arch updates, package counts and mitigations without recommending operational changes | Open |
| High | Track Samsung/OpenAI enterprise adoption | Samsung is one of OpenAI's largest enterprise deployments and expands Codex beyond pure developer workflows | Watch Samsung rollout notes, governance model, productivity claims and Korean market adoption | Open |
| High | Track Claude identity verification | Anthropic is adding visible identity verification for selected Claude use cases, platform integrity and compliance | Watch policy updates, user backlash, regional differences and enterprise carve-outs | Open |
| High | Track agent interoperability standards | Google ARD and A2A may become important infrastructure for discovering and trusting agent capabilities | Recheck adoption outside Google, MCP overlap, Linux Foundation AI Catalog work and security model | Open |
| Medium | Track physical agentic AI | Anthropic Project Fetch shows models moving toward using off-the-shelf physical tools, while still failing at precise closed-loop control | Watch robotics follow-ups, benchmark replication and safety framing | Open |
| Medium | Track Gemini CLI to Antigravity migration | Individual Gemini CLI users lost request serving on June 18, while enterprise access remains | Watch migration friction, feature parity, open-source community reaction and Polish developer coverage | Open |
| Medium | Track Apertus sovereign AI signal | Apertus resurfaced on HN as a strong European sovereign AI symbol even though the model itself is not new | Watch Apertus Mini, adoption, benchmark updates and EU public-sector usage | Open |
| Medium | Track AI cybersecurity startups | DREAM's $260M round and $3B valuation show state-oriented AI cyber as a growing market | Watch independent validation, customers, regulatory concerns and Europe/Israel security positioning | Open |

## Review Notes

- 2026-06-17: Topic created for Polish daily technology research and podcast
  automation.
- 2026-06-17: Manual research dry run created the first `tech-news` report and
  selected podcast candidates from public sources.
- 2026-06-17: Manual podcast dry run generated `script.md`, `sources.md`, and
  `podcast.mp3`; `ffprobe` measured the MP3 at about 7:51.
- 2026-06-18: Daily research run created a material update. Strongest podcast
  candidates: G7/frontier AI governance, GLM-5.2 open weights, UNC1151 Gmail
  phishing, AI fatigue, Polish autonomous-vehicle regulation.
- 2026-06-18: Daily tech podcast generated `draft.md`, `script.md`,
  `sources.md`, `render.json`, and `podcast.mp3`; final MP3 used Piper and
  measured about 7:41 by `ffprobe`.
- 2026-06-18: Added professional PDF generation to the research workflow and
  rendered `pdfs/2026-06-18-tech-news.pdf`.
- 2026-06-19: Daily research run created a material update. Strongest podcast
  candidates: enterprise AI spend controls, shadow AI policy in the USA,
  Android 17 as an agent platform, GitHub malware supply-chain risk and
  Midjourney Medical.
- 2026-06-19: Product Hunt homepage was usable in the morning run and showed a
  strong agentic-product signal; keep timing item open until three runs confirm
  repeatability.
- 2026-06-19: Daily tech podcast generated `draft.md`, `script.md`,
  `sources.md`, `render.json`, `brief.pdf`, and `podcast.mp3`; final MP3 used
  Piper and measured about 7:43 by `ffprobe`.
- 2026-06-20: Daily research run created a material update. Strongest podcast
  candidates: Norway AI school restrictions, French AI sovereignty, Google/Amazon
  chip competition with Nvidia, GitHub malware targeting agents, and Polish AI
  trust/deepfake data.
- 2026-06-20: Product Hunt homepage was usable again in the morning run and
  showed a strong agentic-product signal; the open timing question should likely
  be reframed toward using the homepage rather than the daily archive.
- 2026-06-20: GitHub malware follow-up found Cybernews coverage and
  `git-malware-finder` with 9,330 listed repositories; keep the item open because
  repo cleanup and agent-targeting risk remain active.
- 2026-06-20: Daily tech podcast generated `draft.md`, `script.md`,
  `sources.md`, `render.json`, `brief.pdf`, and `podcast.mp3`; final MP3 used
  Piper and measured about 8:15 by `ffprobe`.
- 2026-06-21: Daily research run created a material update. Strongest podcast
  candidates: Cloudflare temporary accounts for AI agents, Google DeepMind AI
  Control Roadmap, Anthropic/Fable/Mythos export-control dispute, AUR supply-chain
  malware, Teams workplace check-in privacy and Product Hunt agentic products.
- 2026-06-21: Product Hunt homepage was usable for the third consecutive morning
  run after 2026-06-19 and 2026-06-20. Prefer the homepage/current sections over
  the historical daily leaderboard in future runs.
- 2026-06-21: Daily tech podcast generated `draft.md`, `script.md`,
  `sources.md`, `render.json`, `brief.pdf`, and `podcast.mp3`; final MP3 used
  Piper and measured about 7:51 by `ffprobe`.
- 2026-06-22: Daily research run created a material update. Strongest podcast
  candidates: OpenAI/Samsung enterprise deployment, Claude identity verification,
  Anthropic Project Fetch physical agents, Google ARD/A2A agent interoperability,
  Gemini CLI -> Antigravity migration, Product Hunt agentic products, Apertus
  sovereign AI and DREAM AI cybersecurity.
- 2026-06-22: Product Hunt homepage remained useful in the morning run. Reddit
  remained weak as a direct public source without login, so HN plus primary
  sources should remain the default public community signal.
- 2026-06-22: Daily tech podcast generated `draft.md`, `script.md`,
  `sources.md`, `render.json`, `brief.pdf`, and `podcast.mp3`; final MP3 used
  Piper and measured about 7:51 by `ffprobe`.

## Done

| Date | Item | Outcome |
| --- | --- | --- |
| 2026-06-18 | Add PDF brief output | Generated `pdfs/2026-06-18-tech-news.pdf` and updated the research automation prompt to create PDFs in future runs |
| 2026-06-20 | Review first three tech research reports | Reports for 2026-06-17, 2026-06-18 and 2026-06-19 have review notes and provided enough source quality to continue the daily workflow |
| 2026-06-21 | Recheck Product Hunt timing | Homepage was useful on 2026-06-19, 2026-06-20 and 2026-06-21; use homepage/current sections instead of the weak daily archive path |
