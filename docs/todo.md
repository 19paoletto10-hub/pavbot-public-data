# Pavbot TODO

## Now

- Keep CloudKit/APNs production identifiers aligned across iOS, publisher
  docs, and Apple Developer: team `SP774TZZU8`, APNs key `YWVNV6YGXJ`, topic
  `com.paweltanski.pavbotviewer`, container `iCloud.com.paweltanski.pavbotviewer`.
- Keep `tech-news` as the active scheduled topic.
- Keep `polska-swiat` as the active scheduled general-news topic.
- Review the first three 08:00 research reports manually.
- Review the first three 09:00 podcast MP3 outputs manually.
- Review the first three 08:30 Poland/world research reports manually.
- Review the first three 09:30 Poland/world podcast MP3 outputs manually.
- Review the first three LLM/AI jobs Wrocław timestamped reports manually.
- Record quality notes in `research/tech-news/backlog.md`.
- Record Poland/world quality notes in `research/polska-swiat/backlog.md`.
- Record LLM/AI jobs quality notes in
  `research/llm-ai-jobs-wroclaw/backlog.md`.

## Next

- Add a short post-publish checklist that records CloudKit verify status and
  whether a TestFlight device received the expected alert.
- Add a lightweight local APNs smoke-test note template for Apple Push
  Notifications Console; never store `.p8`, JWT, or device tokens in the repo.
- Tune the `daily-research-agent` skill if reports are noisy or duplicated.
- Tune the `daily-tech-podcast-agent` skill if scripts are too long, too short,
  or not broadcast-ready.
- Tune the `daily-news-podcast-agent` skill if scripts lack Polish diacritics,
  neutrality, or broadcast pacing.
- Add source allowlist guidance after seeing repeated useful sources.
- Pick the next two topic threads only after the tech-news review loop passes.
- Use `docs/how-to-use.md` and `research/templates/new-topic-checklist.md`
  before scheduling any new topic.

## Later

- Consider a CloudKit delivery metrics dashboard once the App Store/TestFlight
  notification path has three verified production runs.
- Add structured run metadata if Markdown reports become hard to query.
- Consider hooks only after there is a concrete enforcement need.
- Evaluate OpenClaw as an optional external observer runtime after the pilot
  has three reviewed reports.
