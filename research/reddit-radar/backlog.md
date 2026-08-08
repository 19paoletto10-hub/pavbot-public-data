# Topic Backlog: reddit-radar

## Active

| Priority | Item | Reason | Next Step | Status |
| --- | --- | --- | --- | --- |
| High | Watch notifier webhook timeout noise | `POST /v1/humor/digest` now succeeds again, but `/status` still reports the last GitHub webhook as `timeout` | Check notifier tunnel/logs and confirm whether webhook processing needs cleanup after successful manual humor ingest | Open |
| High | Restore topic automation prompt | The run request pointed to `research/reddit-radar/automation-prompt.md`, but the file was missing and the workflow contract had become implicit | Recreated the topic-local prompt and restored a topic index on Sunday, July 26, 2026 | Done |

## Review Notes

- 2026-08-08: 12:07 CEST material update found exactly four fresh public-safe
  survivors after filtering `2026-08-07-1909` and `2026-08-07-2008`, so the
  topic rotates to a thinner midday bundle with one mainstream movie-audio
  meme plus three clean programmer cards about agent review loops,
  localStorage-as-database absurdity, and `read only Fridays`.
- 2026-08-08: The same 12:07 CEST run rendered a readable three-page mobile
  PDF, published successfully, and then confirmed through fresh `origin/main`
  inspection plus raw GitHub HTTP checks that the new run, PDF, bundle, and
  refreshed manifest are remotely visible.
- 2026-08-08: After positive remote verification, production notifier
  `POST /v1/humor/digest` stored `humor-2026-08-08-1207`, and read-only
  `GET /v1/humor/latest` now serves the same four-card digest; the remaining
  notifier risk is the stale GitHub webhook timeout record still visible in
  `/status`.
- 2026-08-08: The same 12:07 CEST slot started from a current remote state:
  `git fetch origin` confirmed that `origin/main` already exposes both
  published Friday no-change audits before this run's own publication step,
  while the active public bundle at run start was still
  `2026-08-06-1807`.
- 2026-08-07: 20:08 CEST second same-day no-change audit confirmed that after
  filtering `2026-08-06-1807` and `2026-08-07-1909`, the freshest shortlist
  still only produced one clearly clean new survivor (`goodOldDays`) plus
  multiple rejected challengers that drifted into fertility/adoption,
  crack-workaround, or translation-explainer comment layers, so the active
  public payload remains `2026-08-06-1807` and no new digest should be sent.
- 2026-08-07: The same 20:08 CEST follow-up slot again started from a current
  remote state: `git fetch origin` confirmed that `origin/main` already
  exposes the published `2026-08-07-1909` run/PDF pair and the active public
  bundle `2026-08-06-1807` before this audit's own publication step.
- 2026-08-07: 19:09 CEST no-change audit confirmed that after filtering
  `2026-08-05-1807` and `2026-08-06-1807`, the fresh shortlist only held two
  clean survivors plus one borderline meme challenger, so the active public
  payload remains `2026-08-06-1807` and no new digest should be sent.
- 2026-08-07: The same 19:09 CEST slot started from a current remote state:
  `git fetch origin` confirmed that `origin/main` already exposes the
  published `2026-08-06-1807` run/PDF/data set before this audit's own
  publication step.
- 2026-08-06: 18:07 CEST material update prepared and published a fresh
  five-card successor bundle with one mystery-bruises meme, two compact dev
  anchors about regex magic and AI README trust, plus worseminton and 750 MB
  menu closers after filtering `2026-08-04-1758` and `2026-08-05-1807`.
- 2026-08-06: The same 18:07 CEST slot rendered a readable four-page mobile
  PDF and, after the shared publish script plus fresh remote checks, confirmed
  that `origin/main` now exposes the run, PDF, raw audit, bundle
  `2026-08-06-1807`, and refreshed `public/pavbot-manifest.json` with
  `generatedAt` `2026-08-06T16:19:24.408769+00:00`.
- 2026-08-06: Final production notifier delivery remains blocked even after
  repo publication recovery: `POST /v1/humor/digest` timed out, and read-only
  checks to `/healthz`, `/status`, and `/v1/humor/latest` timed out too, so
  the live humor panel state is still unverified.
- 2026-08-05: 18:07 CEST material update prepared a fresh five-card local
  successor bundle with one respawn-points meme, three dev closers about prod
  handoff, startup thinking theatre, and database-forensics absurdity, plus a
  `NULL` sweater closer after filtering `2026-08-03-0608` and
  `2026-08-04-1758`.
- 2026-08-05: The same 18:07 CEST slot rendered a readable four-page mobile
  PDF and confirmed that `git fetch origin` now succeeds again, so fetch-timeout
  preflight is no longer the active repo-health blocker.
- 2026-08-05: The publish attempt for the 18:07 slot refreshed the local
  manifest in the clean worktree and passed CloudKit briefing/artifact
  preflight, but the final SSH push failed with `Connection to github.com
  closed by remote host`, `send-pack: unexpected disconnect while reading
  sideband packet`, and `fatal: the remote end hung up unexpectedly`; remote
  verification and `/v1/humor/digest` remain blocked.
- 2026-08-03: 06:08 CEST material update prepared a fresh five-card local
  successor bundle with two lighter meme cards, one dev closer, one
  tater-tot-layout absurd, and one John Lewis retail-label facepalm after
  filtering `2026-08-02-0609` and `2026-08-02-1209`.
- 2026-08-03: The same 06:08 CEST pre-publication repo-health check showed a
  new blocker shape: `git fetch origin` timed out after 20 seconds with no
  stdout or stderr, so the run still needs explicit remote verification before
  any `/v1/humor/digest` request can be considered.
- 2026-08-02: 12:09 CEST material update prepared a broader five-card local
  successor bundle with two memes anchors, one light-IDE dev closer, one
  upside-down-drawers facepalm, and one Olive Garden cheese-grating closer
  after filtering `2026-08-02-0609` and `2026-08-01-1808`.
- 2026-08-02: The same 12:09 CEST slot rendered a readable three-page mobile
  PDF, but post-publish verification still confirmed that `origin/main` does
  not expose the run, PDF, or data bundle `2026-08-02-1209`, and the public
  manifest remains stale at `generatedAt` `2026-07-30T08:41:10.579726+00:00`.
- 2026-08-02: The publish attempt for the 12:09 slot refreshed the local clean
  worktree manifest and passed CloudKit briefing/artifact preflight, but the
  final push failed again on GitHub HTTPS auth with `could not read Username
  for 'https://github.com': Device not configured`; remote verification and
  `/v1/humor/digest` remain blocked.
- 2026-08-02: 06:09 CEST material update prepared a compact four-card local
  successor bundle with two everyday meme cards and two dev closers after
  filtering `2026-08-01-1808` and `2026-08-01-1154`.
- 2026-08-02: The same 06:09 CEST preflight confirmed that `origin/main` still
  does not expose the unpublished local `2026-08-01-1808` reddit-radar run,
  PDF, or data bundle, so the next publish attempt is again both a fresh
  rotation and a remote-state catch-up.
- 2026-08-02: The publish sequence for the 06:09 slot failed twice in two
  different ways: first on a CloudKit Web Services timeout during artifact
  preflight, then on the final GitHub HTTPS auth error `could not read Username
  for 'https://github.com': Device not configured`, so remote verification and
  notifier delivery remain blocked.
- 2026-08-01: 18:08 CEST material update prepared a five-card local successor
  bundle with two mainstream meme cards and three lighter dev closers after
  filtering `2026-08-01-1154` and `2026-07-31-2208`.
- 2026-08-01: The publish attempt for the 18:08 slot refreshed the local
  manifest and passed CloudKit/artifact preflight, but the final push still
  failed on GitHub HTTPS auth with `could not read Username for 'https://github.com':
  Device not configured`; remote verification and `/v1/humor/digest` remain
  blocked.
- 2026-08-01: 12:14 CEST no-change audit confirmed that after filtering the
  fresh local `2026-08-01-1154` bundle and the earlier `2026-07-31-2208`
  bundle, the remaining challengers do not clear a second four-card rotation,
  so the intended next public payload remains `2026-08-01-1154`.
- 2026-08-01: A publish retry repaired the missing git blob for
  `research/reddit-radar/data/2026-07-31-2208-reddit-radar-raw.json` and got
  through artifact/manifest preflight, but the final push still failed on
  GitHub HTTPS auth with `could not read Username for 'https://github.com':
  Device not configured`; remote verification and any notifier action remain
  blocked.
- 2026-08-01: 11:54 CEST material update prepared a five-card local successor
  to `2026-07-29-2208`, but the shared publish script failed first on corrupted
  local Git objects (`invalid object ... 2026-07-31-1808-reddit-radar-raw.json`)
  and the clean temporary fallback then stalled during GitHub shallow fetch, so
  remote verification and `/v1/humor/digest` remain blocked on publication
  health rather than topic quality.
- 2026-07-31: 18:08 CEST material update prepared a six-card local successor to
  `2026-07-29-2208`, but the shared publish script could not push because
  GitHub HTTPS auth was invalid and SSH returned `Permission denied
  (publickey)`, so remote verification and `/v1/humor/digest` are still
  blocked on repo access.
- 2026-07-31: 18:08 CEST material update started from a current `origin/main`
  state that still exposed `2026-07-29-2208`, so the Friday evening slot is a
  standard fresh rotation rather than a remote catch-up publish.
- 2026-07-29: 22:08 CEST material update started from a current `origin/main`
  state that already exposed `2026-07-29-1808`, so the late-evening slot
  remained a standard rotation rather than a remote catch-up publish; after
  publication, `/v1/humor/latest` also moved to `humor-2026-07-29-2208`.
- 2026-07-29: 18:08 CEST material update again started from a current
  `origin/main` state, so the evening slot remained a standard rotation rather
  than a remote catch-up publish.
- 2026-07-29: 12:07 CEST material update started from a stale `origin/main`
  state that still exposed `2026-07-28-2208`, so remote verification remains
  mandatory and this publish should also catch up the missing `2026-07-29-0608`
  bundle.
- 2026-07-29: 06:08 CEST material update again started from a current
  `origin/main` state, so the morning slot remained a standard rotation rather
  than a remote catch-up publish.
- 2026-07-28: 22:08 CEST material update again started from a current
  `origin/main` state, so the late-evening slot remained a standard rotation
  rather than a remote catch-up publish.
- 2026-07-28: 12:07 CEST material update again started from a current
  `origin/main` state, so the noon slot remained a standard rotation rather
  than a remote catch-up publish.
- 2026-07-27: 22:08 CEST material update found that `origin/main` still exposed
  `2026-07-27-0607` and did not yet contain the local `2026-07-27-1809`
  bundle before publish, so remote verification remains mandatory even after a
  successful local research pass.
- 2026-07-22: Added a single actionable follow-up after the 22:08 CEST audit confirmed the missing topic-local workflow prompt.
- 2026-07-23: 06:08 CEST material update succeeded through the logged-in Safari session, but `automation-prompt.md` and `index.md` are still missing topic-local contract files.
- 2026-07-25: 00:08 CEST material update succeeded through read-only Safari / Computer Use, but `automation-prompt.md` and `index.md` are still missing topic-local contract files.
- 2026-07-26: 18:08 CEST no-change audit restored both `automation-prompt.md` and `index.md`, so the topic now has an explicit local workflow contract again.
