#!/usr/bin/env bash
set -euo pipefail

target_branch="${PAVBOT_PUBLISH_BRANCH:-main}"
mobile_public_only_topic="research/aktualne-wydarzenia-mobile"
pulse_news_topic="research/puls-dnia-news"
reddit_radar_topic="research/reddit-radar"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
manifest_generator="$script_dir/generate_pavbot_manifest.py"
cloudkit_publisher="${PAVBOT_CLOUDKIT_PUBLISHER:-$script_dir/publish_cloudkit_briefings.py}"
cktool_refresh_command="${PAVBOT_CKTOOL_REFRESH_COMMAND:-xcrun cktool save-token --type user --method keychain --force}"
jobs_data_validator="$script_dir/validate_jobs_data.py"
research_data_validator="$script_dir/validate_research_data.py"
mobile_news_data_validator="$script_dir/validate_mobile_news_data.py"
pulse_news_data_validator="$script_dir/validate_pulse_news_data.py"

usage() {
  cat >&2 <<'EOF'
usage: scripts/pavbot_commit_and_push_outputs.sh [--isolated] research/<topic>
       scripts/pavbot_commit_and_push_outputs.sh --all-topics

Publishes one Pavbot automation output set by committing only:
  - generated outputs from the selected research/<topic>/
  - public/pavbot-manifest.json

Output allowlist:
  - research/<topic>/runs/
  - research/<topic>/pdfs/
  - research/<topic>/data/
  - research/<topic>/podcasts/
  - research/<topic>/index.md
  - research/<topic>/backlog.md

Options:
  --isolated  publish from a temporary clean worktree based on origin/main,
              copying only allowlisted outputs from the current workspace
  --all-topics
              synchronize CloudKit Briefing and Artifact records for all
              current manifest topics without committing or pushing Git changes

Optional environment:
  PAVBOT_MANIFEST_URL=https://raw.githubusercontent.com/<owner>/<repo>/<branch>/public/pavbot-manifest.json
      Overrides automatic manifest URL resolution.
  PAVBOT_RAW_BASE_URL=https://raw.githubusercontent.com/<owner>/<repo>/<branch>/
      Used to derive PAVBOT_MANIFEST_URL when PAVBOT_MANIFEST_URL is unset.
  PAVBOT_CLOUDKIT_CONTAINER_ID=iCloud.com.paweltanski.pavbotviewer
      Production CloudKit container for Briefing and Artifact records.
  PAVBOT_CLOUDKIT_ENVIRONMENT=production
      CloudKit environment for cktool.
  PAVBOT_CLOUDKIT_TEAM_ID=SP774TZZU8
      Apple Developer team id for cktool.
  PAVBOT_CLOUDKIT_DRY_RUN=1
      Diagnostic-only mode. Validates the derived Briefing notification payload
      without calling cktool, then refuses production publish.
  PAVBOT_CKTOOL_REFRESH_COMMAND='xcrun cktool save-token --type user --method keychain --force'
      Command run before every production CloudKit action to refresh the
      cktool user token. Override only for tests or local diagnostics.
  PAVBOT_CKTOOL_USER_TOKEN=<Apple Developer user token>
      Optional secret for unattended runs. When set and no refresh-command
      override is provided, the script saves this token to the cktool keychain
      entry non-interactively before production CloudKit calls.
  PAVBOT_EXPECTED_MOBILE_NEWS_STAMP=YYYY-MM-DD-HHMM
      For research/aktualne-wydarzenia-mobile, require this exact native
      mobileNewsData package to exist and be promoted into the manifest.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_clean_publish_scope() {
  local bad_paths=()
  local entry status path old_path

  while IFS= read -r -d '' entry; do
    status="${entry:0:2}"
    path="${entry:3}"
    if ! is_allowed_publish_path "$path"; then
      bad_paths+=("$path")
    fi

    if [[ "$status" == *R* || "$status" == *C* ]]; then
      if IFS= read -r -d '' old_path; then
        if ! is_allowed_publish_path "$old_path"; then
          bad_paths+=("$old_path")
        fi
      fi
    fi
  done < <(git status --porcelain=v1 -z --untracked-files=all)

  if ((${#bad_paths[@]} > 0)); then
    printf 'Refusing to publish: changes outside allowed publish paths:\n' >&2
    printf '  %s\n' "${bad_paths[@]}" >&2
    printf 'Allowed paths are generated outputs under %s and public/pavbot-manifest.json.\n' "$topic_path" >&2
    exit 1
  fi
}

has_publishable_changes() {
  local entry path

  while IFS= read -r -d '' entry; do
    path="${entry:3}"
    if is_allowed_publish_path "$path"; then
      return 0
    fi
  done < <(git status --porcelain=v1 -z --untracked-files=all)

  return 1
}

require_staged_scope() {
  local bad_paths=()
  local path

  while IFS= read -r -d '' path; do
    if ! is_allowed_staged_path "$path"; then
      bad_paths+=("$path")
    fi
  done < <(git diff --cached --name-only -z)

  if ((${#bad_paths[@]} > 0)); then
    printf 'Refusing to commit: staged changes outside allowed publish paths:\n' >&2
    printf '  %s\n' "${bad_paths[@]}" >&2
    exit 1
  fi
}

is_allowed_publish_path() {
  local path="$1"
  case "$path" in
    "public/pavbot-manifest.json")
      return 0
      ;;
    *)
      if [[ "$topic_path" == "$mobile_public_only_topic" ]]; then
        is_mobile_public_publish_path "$path"
      else
        case "$path" in
          "$topic_path/index.md"|"$topic_path/backlog.md")
            return 0
            ;;
          "$topic_path/runs"|"$topic_path/runs/"*|"$topic_path/pdfs"|"$topic_path/pdfs/"*|"$topic_path/data"|"$topic_path/data/"*|"$topic_path/podcasts"|"$topic_path/podcasts/"*)
            return 0
            ;;
          *)
            return 1
            ;;
        esac
      fi
      ;;
  esac
}

is_allowed_staged_path() {
  local path="$1"
  if is_allowed_publish_path "$path"; then
    return 0
  fi

  if [[ "$topic_path" == "$mobile_public_only_topic" ]]; then
    case "$path" in
      "$topic_path/index.md"|"$topic_path/backlog.md"|"$topic_path/runs"|"$topic_path/runs/"*|"$topic_path/pdfs"|"$topic_path/pdfs/"*|"$topic_path/data"|"$topic_path/data/"*|"$topic_path/podcasts"|"$topic_path/podcasts/"*)
        return 0
        ;;
    esac
  fi

  return 1
}

is_mobile_public_publish_path() {
  local path="$1"
  case "$path" in
    "$topic_path/runs/"*.md)
      return 0
      ;;
    "$topic_path/data/"*-mobile-news.json)
      return 0
      ;;
    "$topic_path/pdfs/"*-mobile-brief.pdf)
      return 0
      ;;
    "$topic_path/pdfs/"*-newspaper.pdf)
      return 0
      ;;
    "$topic_path/podcasts/"*/audio/*/podcast.mp3)
      return 0
      ;;
    "$topic_path/podcasts/"*/script.md)
      return 0
      ;;
    "$topic_path/podcasts/"*/draft.md)
      return 0
      ;;
    "$topic_path/podcasts/"*/sources.md)
      return 0
      ;;
    "$topic_path/podcasts/"*/tts_variants.json)
      return 0
      ;;
    "$topic_path/podcasts/"*/audio/*/render.json)
      return 0
      ;;
    "$topic_path/podcasts/"*/audio/*/render.log)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

mobile_public_output_stamp() {
  local rel_path="$1"
  local name stamp

  case "$rel_path" in
    runs/*.md)
      name="$(basename "$rel_path")"
      stamp="${name%.md}"
      ;;
    data/*-mobile-news.json)
      name="$(basename "$rel_path")"
      stamp="${name%-mobile-news.json}"
      ;;
    pdfs/*-mobile-brief.pdf)
      name="$(basename "$rel_path")"
      stamp="${name%-mobile-brief.pdf}"
      ;;
    pdfs/*-newspaper.pdf)
      name="$(basename "$rel_path")"
      stamp="${name%-newspaper.pdf}"
      ;;
    podcasts/*/audio/*/podcast.mp3)
      stamp="${rel_path#podcasts/}"
      stamp="${stamp%%/*}"
      ;;
    podcasts/*/script.md)
      stamp="${rel_path#podcasts/}"
      stamp="${stamp%%/*}"
      ;;
    podcasts/*/draft.md)
      stamp="${rel_path#podcasts/}"
      stamp="${stamp%%/*}"
      ;;
    podcasts/*/sources.md)
      stamp="${rel_path#podcasts/}"
      stamp="${stamp%%/*}"
      ;;
    podcasts/*/tts_variants.json)
      stamp="${rel_path#podcasts/}"
      stamp="${stamp%%/*}"
      ;;
    podcasts/*/audio/*/render.json)
      stamp="${rel_path#podcasts/}"
      stamp="${stamp%%/*}"
      ;;
    podcasts/*/audio/*/render.log)
      stamp="${rel_path#podcasts/}"
      stamp="${stamp%%/*}"
      ;;
    *)
      return 1
      ;;
  esac

  [[ -n "$stamp" ]] || return 1
  printf '%s' "$stamp"
}

latest_mobile_public_output_stamp() {
  local src_root="$1"
  local src rel_path stamp latest=""

  shopt -s nullglob
  for src in "$src_root"/runs/*.md; do
    rel_path="${src#"$src_root"/}"
    stamp="$(mobile_public_output_stamp "$rel_path")" || continue
    [[ "$stamp" == "$latest_stamp" ]] || continue
    dest_path="$dest_topic_root/runs/$(basename "$src")"
    mkdir -p "$(dirname "$dest_path")"
    cp "$src" "$dest_path"
  done

  for src in "$src_root"/data/*-mobile-news.json; do
    rel_path="${src#"$src_root"/}"
    stamp="$(mobile_public_output_stamp "$rel_path")" || continue
    if [[ -z "$latest" || "$stamp" > "$latest" ]]; then
      latest="$stamp"
    fi
  done
  shopt -u nullglob

  [[ -n "$latest" ]] || return 1
  printf '%s' "$latest"
}

path_has_tracked_files() {
  [[ -n "$(git ls-files -- "$1")" ]]
}

normalize_raw_base_url() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  [[ -n "$value" ]] || return 1
  [[ "$value" == */ ]] || value="$value/"
  printf '%s' "$value"
}

manifest_url_from_raw_base_url() {
  local raw_base_url
  raw_base_url="$(normalize_raw_base_url "$1")" || return 1
  printf '%spublic/pavbot-manifest.json' "$raw_base_url"
}

manifest_url_from_existing_manifest() {
  local manifest_path="public/pavbot-manifest.json"
  [[ -f "$manifest_path" ]] || return 1
  python3 - "$manifest_path" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    raise SystemExit(1)

raw_base_url = str(data.get("rawBaseUrl") or "").strip()
if not raw_base_url:
    raise SystemExit(1)
if not raw_base_url.endswith("/"):
    raw_base_url += "/"
print(raw_base_url + "public/pavbot-manifest.json")
PY
}

manifest_url_from_github_origin() {
  local remote_url path owner repo
  remote_url="$(git config --get remote.origin.url || true)"
  [[ -n "$remote_url" ]] || return 1

  case "$remote_url" in
    https://github.com/*)
      path="${remote_url#https://github.com/}"
      ;;
    git@github.com:*)
      path="${remote_url#git@github.com:}"
      ;;
    ssh://git@github.com/*)
      path="${remote_url#ssh://git@github.com/}"
      ;;
    *)
      return 1
      ;;
  esac

  path="${path%.git}"
  owner="${path%%/*}"
  repo="${path#*/}"
  [[ -n "$owner" && -n "$repo" && "$repo" != */* ]] || return 1
  printf 'https://raw.githubusercontent.com/%s/%s/%s/public/pavbot-manifest.json' "$owner" "$repo" "$target_branch"
}

resolve_pavbot_manifest_url() {
  local resolved

  if [[ -n "${PAVBOT_MANIFEST_URL:-}" ]]; then
    printf '%s' "$PAVBOT_MANIFEST_URL"
    return 0
  fi

  if [[ -n "${PAVBOT_RAW_BASE_URL:-}" ]]; then
    manifest_url_from_raw_base_url "$PAVBOT_RAW_BASE_URL" || die "PAVBOT_RAW_BASE_URL is empty or invalid"
    return 0
  fi

  if resolved="$(manifest_url_from_existing_manifest 2>/dev/null)"; then
    printf '%s' "$resolved"
    return 0
  fi

  if resolved="$(manifest_url_from_github_origin 2>/dev/null)"; then
    printf '%s' "$resolved"
    return 0
  fi

  die "could not resolve PAVBOT_MANIFEST_URL; set PAVBOT_MANIFEST_URL or use a GitHub origin remote"
}

stage_path_if_present_or_tracked() {
  local path="$1"
  if [[ -e "$path" ]] || path_has_tracked_files "$path"; then
    git add -A -- "$path"
  fi
}

stage_publishable_paths() {
  stage_path_if_present_or_tracked "$topic_path/index.md"
  stage_path_if_present_or_tracked "$topic_path/backlog.md"
  stage_path_if_present_or_tracked "$topic_path/runs"
  stage_path_if_present_or_tracked "$topic_path/pdfs"
  stage_path_if_present_or_tracked "$topic_path/data"
  stage_path_if_present_or_tracked "$topic_path/podcasts"
  stage_path_if_present_or_tracked "public/pavbot-manifest.json"
}

validate_jobs_data_outputs() {
  if [[ "$topic_path" != "research/llm-ai-jobs-wroclaw" ]]; then
    return 0
  fi

  if [[ ! -d "$topic_path/data" ]]; then
    return 0
  fi

  shopt -s nullglob
  local files=("$topic_path"/data/*.json)
  shopt -u nullglob
  if ((${#files[@]} == 0)); then
    return 0
  fi

  python3 "$jobs_data_validator" "${files[@]}"
}

validate_research_data_outputs() {
  case "$topic_path" in
    "research/tech-news"|"research/polska-swiat")
      ;;
    *)
      return 0
      ;;
  esac

  if [[ ! -d "$topic_path/data" ]]; then
    return 0
  fi

  shopt -s nullglob
  local files=("$topic_path"/data/*.json)
  shopt -u nullglob
  if ((${#files[@]} == 0)); then
    return 0
  fi

  python3 "$research_data_validator" "${files[@]}"
}

latest_research_run_rel_path() {
  case "$topic_path" in
    "research/tech-news"|"research/polska-swiat")
      ;;
    *)
      return 1
      ;;
  esac

  if [[ ! -d "$topic_path/runs" ]]; then
    return 1
  fi

  local latest
  latest="$(
    find "$topic_path/runs" -type f -name '*.md' 2>/dev/null \
      | LC_ALL=C sort \
      | tail -n 1
  )"
  [[ -n "$latest" ]] || return 1
  printf '%s' "$latest"
}

research_data_rel_path_for_run() {
  local run_rel_path="$1"
  local stem
  stem="$(basename "$run_rel_path" .md)"
  [[ -n "$stem" ]] || return 1
  printf '%s/data/%s-research.json' "$topic_path" "$stem"
}

require_latest_research_data_for_latest_run() {
  local latest_run_rel_path data_rel_path
  latest_run_rel_path="$(latest_research_run_rel_path 2>/dev/null || true)"
  [[ -n "$latest_run_rel_path" ]] || return 0

  data_rel_path="$(research_data_rel_path_for_run "$latest_run_rel_path")" || return 0
  if [[ ! -f "$data_rel_path" ]]; then
    die "missing researchData for latest research run: $data_rel_path (from $latest_run_rel_path)"
  fi
}

validate_mobile_news_data_outputs() {
  if [[ "$topic_path" != "$mobile_public_only_topic" ]]; then
    return 0
  fi

  if [[ ! -d "$topic_path/data" ]]; then
    return 0
  fi

  shopt -s nullglob
  local files=("$topic_path"/data/*-mobile-news.json)
  shopt -u nullglob
  if ((${#files[@]} == 0)); then
    return 0
  fi

  python3 "$mobile_news_data_validator" "${files[@]}"
}

validate_pulse_news_data_outputs() {
  if [[ "$topic_path" != "$pulse_news_topic" ]]; then
    return 0
  fi

  if [[ ! -d "$topic_path/data" ]]; then
    return 0
  fi

  shopt -s nullglob
  local files=("$topic_path"/data/*-pulse-news.json)
  shopt -u nullglob
  if ((${#files[@]} == 0)); then
    return 0
  fi

  python3 "$pulse_news_data_validator" "${files[@]}"
}

latest_pulse_news_data_rel_path() {
  if [[ "$topic_path" != "$pulse_news_topic" ]]; then
    return 1
  fi

  if [[ ! -d "$topic_path/data" ]]; then
    return 1
  fi

  local latest
  latest="$(
    find "$topic_path/data" -type f -name '*-pulse-news.json' 2>/dev/null \
      | LC_ALL=C sort \
      | tail -n 1
  )"
  [[ -n "$latest" ]] || return 1
  printf '%s' "$latest"
}

manifest_contains_pulse_news_data_path() {
  local rel_path="$1"
  local manifest_path="public/pavbot-manifest.json"
  [[ -f "$manifest_path" ]] || return 1

  python3 - "$manifest_path" "$rel_path" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
rel_path = sys.argv[2]

try:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
except Exception:
    raise SystemExit(1)

for artifact in manifest.get("artifacts", []):
    if (
        artifact.get("path") == rel_path
        and artifact.get("topic") == "puls-dnia-news"
        and artifact.get("type") == "pulseNewsData"
    ):
        raise SystemExit(0)

raise SystemExit(1)
PY
}

require_latest_pulse_news_data_in_manifest() {
  local latest_rel_path
  latest_rel_path="$(latest_pulse_news_data_rel_path 2>/dev/null || true)"
  [[ -n "$latest_rel_path" ]] || return 0

  if ! manifest_contains_pulse_news_data_path "$latest_rel_path"; then
    die "generated manifest missing pulseNewsData for $latest_rel_path"
  fi
}

needs_manifest_refresh_for_pulse_news() {
  local latest_rel_path
  latest_rel_path="$(latest_pulse_news_data_rel_path 2>/dev/null || true)"
  [[ -n "$latest_rel_path" ]] || return 1

  if manifest_contains_pulse_news_data_path "$latest_rel_path"; then
    return 1
  fi

  return 0
}

latest_reddit_radar_data_rel_path() {
  if [[ "$topic_path" != "$reddit_radar_topic" ]]; then
    return 1
  fi

  if [[ ! -d "$topic_path/data" ]]; then
    return 1
  fi

  local latest
  latest="$(
    find "$topic_path/data" -type f -name '*-reddit-radar.json' 2>/dev/null \
      | LC_ALL=C sort \
      | tail -n 1
  )"
  [[ -n "$latest" ]] || return 1
  printf '%s' "$latest"
}

manifest_contains_reddit_radar_data_path() {
  local rel_path="$1"
  local manifest_path="public/pavbot-manifest.json"
  [[ -f "$manifest_path" ]] || return 1

  python3 - "$manifest_path" "$rel_path" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
rel_path = sys.argv[2]

try:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
except Exception:
    raise SystemExit(1)

for artifact in manifest.get("artifacts", []):
    if (
        artifact.get("path") == rel_path
        and artifact.get("topic") == "reddit-radar"
        and artifact.get("type") == "redditRadarData"
    ):
        raise SystemExit(0)

raise SystemExit(1)
PY
}

require_latest_reddit_radar_data_in_manifest() {
  local latest_rel_path
  latest_rel_path="$(latest_reddit_radar_data_rel_path 2>/dev/null || true)"
  [[ -n "$latest_rel_path" ]] || return 0

  if ! manifest_contains_reddit_radar_data_path "$latest_rel_path"; then
    die "generated manifest missing redditRadarData for $latest_rel_path"
  fi
}

require_latest_reddit_radar_original_comment_bodies() {
  local latest_rel_path
  latest_rel_path="$(latest_reddit_radar_data_rel_path 2>/dev/null || true)"
  [[ -n "$latest_rel_path" ]] || return 0

  python3 - "$latest_rel_path" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    payload = json.loads(path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"redditRadarData is not readable JSON: {path}: {exc}", file=sys.stderr)
    raise SystemExit(1)

highlight_count = 0
original_body_count = 0
items = payload.get("items") if isinstance(payload, dict) else None
for item in items if isinstance(items, list) else []:
    if not isinstance(item, dict):
        continue
    highlights = item.get("commentHighlights")
    if not isinstance(highlights, list):
        continue
    for highlight in highlights:
        if not isinstance(highlight, dict):
            continue
        highlight_count += 1
        original_body = highlight.get("originalBody")
        if isinstance(original_body, str) and original_body.strip():
            original_body_count += 1

if highlight_count > 0 and original_body_count == 0:
    print(
        "redditRadarData missing original comment bodies: "
        f"{path} has {highlight_count} commentHighlights but 0 usable originalBody fields",
        file=sys.stderr,
    )
    raise SystemExit(1)
PY
}

needs_manifest_refresh_for_reddit_radar() {
  local latest_rel_path
  latest_rel_path="$(latest_reddit_radar_data_rel_path 2>/dev/null || true)"
  [[ -n "$latest_rel_path" ]] || return 1

  if manifest_contains_reddit_radar_data_path "$latest_rel_path"; then
    return 1
  fi

  return 0
}

latest_mobile_news_data_rel_path() {
  if [[ "$topic_path" != "$mobile_public_only_topic" ]]; then
    return 1
  fi

  if [[ ! -d "$topic_path/data" ]]; then
    return 1
  fi

  local latest
  latest="$(
    find "$topic_path/data" -type f -name '*-mobile-news.json' 2>/dev/null \
      | LC_ALL=C sort \
      | tail -n 1
  )"
  [[ -n "$latest" ]] || return 1
  printf '%s' "$latest"
}

expected_mobile_news_stamp() {
  if [[ "$topic_path" != "$mobile_public_only_topic" ]]; then
    return 1
  fi

  local stamp="${PAVBOT_EXPECTED_MOBILE_NEWS_STAMP:-}"
  [[ -n "$stamp" ]] || return 1

  if [[ ! "$stamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{4}$ ]]; then
    die "invalid PAVBOT_EXPECTED_MOBILE_NEWS_STAMP: $stamp (expected YYYY-MM-DD-HHMM)"
  fi

  printf '%s' "$stamp"
}

mobile_news_data_rel_path_for_stamp() {
  local stamp="$1"
  printf '%s/data/%s-mobile-news.json' "$topic_path" "$stamp"
}

manifest_contains_mobile_news_data_path() {
  local rel_path="$1"
  local manifest_path="public/pavbot-manifest.json"
  [[ -f "$manifest_path" ]] || return 1

  python3 - "$manifest_path" "$rel_path" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
rel_path = sys.argv[2]

try:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
except Exception:
    raise SystemExit(1)

for artifact in manifest.get("artifacts", []):
    if (
        artifact.get("path") == rel_path
        and artifact.get("topic") == "aktualne-wydarzenia-mobile"
        and artifact.get("type") == "mobileNewsData"
    ):
        raise SystemExit(0)

raise SystemExit(1)
PY
}

require_latest_mobile_news_data_in_manifest() {
  local latest_rel_path
  latest_rel_path="$(latest_mobile_news_data_rel_path 2>/dev/null || true)"
  [[ -n "$latest_rel_path" ]] || return 0

  if ! manifest_contains_mobile_news_data_path "$latest_rel_path"; then
    die "generated manifest missing mobileNewsData for $latest_rel_path"
  fi
}

require_expected_mobile_news_data_in_manifest() {
  local expected_stamp expected_rel_path
  expected_stamp="$(expected_mobile_news_stamp 2>/dev/null || true)"
  [[ -n "$expected_stamp" ]] || return 0

  expected_rel_path="$(mobile_news_data_rel_path_for_stamp "$expected_stamp")"
  if ! manifest_contains_mobile_news_data_path "$expected_rel_path"; then
    die "generated manifest missing expected mobileNewsData for $expected_rel_path"
  fi
}

latest_mobile_news_package_stamp() {
  if [[ "$topic_path" != "$mobile_public_only_topic" ]]; then
    return 1
  fi

  python3 - "$topic_path" <<'PY'
import re
import sys
from pathlib import Path

topic = Path(sys.argv[1])
stamp_re = re.compile(r"(?P<date>\d{4}-\d{2}-\d{2})-(?P<time>\d{4})")
stamps: set[str] = set()

for base in ("runs", "data", "pdfs", "podcasts"):
    root = topic / base
    if not root.exists():
        continue
    for path in root.rglob("*"):
        text = path.name if base == "podcasts" and path.is_dir() else path.stem
        match = stamp_re.search(text)
        if match:
            stamps.add(f"{match.group('date')}-{match.group('time')}")

if not stamps:
    raise SystemExit(1)

print(sorted(stamps)[-1])
PY
}

required_mobile_news_package_stamp() {
  local expected_stamp
  expected_stamp="$(expected_mobile_news_stamp 2>/dev/null || true)"
  if [[ -n "$expected_stamp" ]]; then
    printf '%s' "$expected_stamp"
    return 0
  fi

  latest_mobile_news_package_stamp
}

require_latest_mobile_news_data_for_latest_package() {
  local required_stamp data_rel_path reason
  required_stamp="$(required_mobile_news_package_stamp 2>/dev/null || true)"
  [[ -n "$required_stamp" ]] || return 0

  data_rel_path="$(mobile_news_data_rel_path_for_stamp "$required_stamp")"
  if [[ ! -f "$data_rel_path" ]]; then
    reason="latest"
    if [[ -n "${PAVBOT_EXPECTED_MOBILE_NEWS_STAMP:-}" ]]; then
      reason="expected"
    fi
    die "missing mobileNewsData for $reason mobile package: $data_rel_path"
  fi
}

needs_manifest_refresh_for_mobile_news() {
  local expected_stamp rel_path
  expected_stamp="$(expected_mobile_news_stamp 2>/dev/null || true)"
  if [[ -n "$expected_stamp" ]]; then
    rel_path="$(mobile_news_data_rel_path_for_stamp "$expected_stamp")"
  else
    rel_path="$(latest_mobile_news_data_rel_path 2>/dev/null || true)"
  fi
  [[ -n "$rel_path" ]] || return 1

  if manifest_contains_mobile_news_data_path "$rel_path"; then
    return 1
  fi

  return 0
}

run_cloudkit_publisher() {
  local mode="$1"
  shift

  if [[ "$cloudkit_publisher" == *.py ]]; then
    python3 "$cloudkit_publisher" "$mode" "$@"
  else
    "$cloudkit_publisher" "$mode" "$@"
  fi
}

refresh_cktool_user_token() {
  if [[ -z "${cktool_refresh_command//[[:space:]]/}" ]]; then
    die "empty PAVBOT_CKTOOL_REFRESH_COMMAND"
  fi

  if [[ -z "${PAVBOT_CKTOOL_REFRESH_COMMAND:-}" && -n "${PAVBOT_CKTOOL_USER_TOKEN:-}" ]]; then
    printf 'refreshing cktool user token from PAVBOT_CKTOOL_USER_TOKEN\n'
    printf 'e\n%s\n' "$PAVBOT_CKTOOL_USER_TOKEN" \
      | xcrun cktool save-token --type user --method keychain --force \
      || die "cktool user token refresh failed from PAVBOT_CKTOOL_USER_TOKEN"
    printf 'cktool user token refreshed\n'
    return 0
  fi

  if [[ -z "${PAVBOT_CKTOOL_REFRESH_COMMAND:-}" && ! -t 0 ]]; then
    printf 'cktool user token refresh skipped: non-interactive terminal; using existing keychain token\n'
    return 0
  fi

  printf 'refreshing cktool user token\n'
  bash -lc "$cktool_refresh_command" || die "cktool user token refresh failed; run manually and retry: xcrun cktool save-token --type user --method keychain --force"
  printf 'cktool user token refreshed\n'
}

run_cloudkit_publisher_with_fresh_token() {
  local mode="$1"
  shift

  refresh_cktool_user_token
  run_cloudkit_publisher "$mode" "$@"
}

preflight_cloudkit_briefings_gate() {
  local args=(--manifest "public/pavbot-manifest.json" --manifest-url "$PAVBOT_MANIFEST_URL" --topic "$topic_path")
  [[ -f "$cloudkit_publisher" ]] || die "missing CloudKit publisher: $cloudkit_publisher"
  if [[ "${PAVBOT_CLOUDKIT_DRY_RUN:-}" == "1" ]]; then
    run_cloudkit_publisher "dry-run" "${args[@]}" >/dev/null || die "CloudKit dry-run failed"
    die "PAVBOT_CLOUDKIT_DRY_RUN=1 is diagnostic-only; production publish requires real CloudKit Briefing create/update. Unset PAVBOT_CLOUDKIT_DRY_RUN; the publish script refreshes cktool automatically before production CloudKit calls."
  fi
  run_cloudkit_publisher_with_fresh_token "preflight" "${args[@]}" >/dev/null || die "CloudKit preflight failed"
  printf 'cloudkit briefing/artifact preflight verified\n'
}

publish_cloudkit_briefings_gate() {
  local args=(--manifest "public/pavbot-manifest.json" --manifest-url "$PAVBOT_MANIFEST_URL" --topic "$topic_path")
  [[ -f "$cloudkit_publisher" ]] || die "missing CloudKit publisher: $cloudkit_publisher"
  if [[ "${PAVBOT_CLOUDKIT_DRY_RUN:-}" == "1" ]]; then
    run_cloudkit_publisher "dry-run" "${args[@]}" >/dev/null || die "CloudKit publication dry-run failed"
    die "PAVBOT_CLOUDKIT_DRY_RUN=1 is diagnostic-only; production publish requires real CloudKit Briefing create/update. Unset PAVBOT_CLOUDKIT_DRY_RUN; the publish script refreshes cktool automatically before production CloudKit calls."
  fi
  run_cloudkit_publisher_with_fresh_token "publish" "${args[@]}" >/dev/null || die "CloudKit publication failed"
  run_cloudkit_publisher_with_fresh_token "verify" "${args[@]}" >/dev/null || die "CloudKit verification failed"
  printf 'cloudkit briefing/artifact publication verified\n'
}

publish_cloudkit_all_topics_gate() {
  local args=(--manifest "public/pavbot-manifest.json" --manifest-url "$PAVBOT_MANIFEST_URL" --all-topics)
  [[ -f "$cloudkit_publisher" ]] || die "missing CloudKit publisher: $cloudkit_publisher"
  if [[ "${PAVBOT_CLOUDKIT_DRY_RUN:-}" == "1" ]]; then
    run_cloudkit_publisher "dry-run" "${args[@]}" >/dev/null || die "CloudKit all-topics dry-run failed"
    die "PAVBOT_CLOUDKIT_DRY_RUN=1 is diagnostic-only; production publish requires real CloudKit Briefing create/update. Unset PAVBOT_CLOUDKIT_DRY_RUN; the publish script refreshes cktool automatically before production CloudKit calls."
  fi
  run_cloudkit_publisher_with_fresh_token "publish" "${args[@]}" >/dev/null || die "CloudKit all-topics publication failed"
  run_cloudkit_publisher_with_fresh_token "verify" "${args[@]}" >/dev/null || die "CloudKit all-topics verification failed"
  printf 'cloudkit all-topics publication verified\n'
}

manifest_artifact_paths() {
  local manifest_path="public/pavbot-manifest.json"
  [[ -f "$manifest_path" ]] || return 0

  python3 - "$manifest_path" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
try:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
except Exception as exc:
    raise SystemExit(f"cannot read manifest artifact paths: {exc}")

for artifact in manifest.get("artifacts", []):
    if not isinstance(artifact, dict):
        continue
    path = str(artifact.get("path") or "").strip()
    if path:
        print(path)
PY
}

fail_missing_manifest_artifact_paths() {
  local scope="$1"
  shift
  printf 'error: manifest references missing artifact paths (%s):\n' "$scope" >&2
  printf '  %s\n' "$@" >&2
  exit 1
}

verify_manifest_artifact_paths_local() {
  local missing=()
  local path

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if [[ ! -f "$path" ]]; then
      missing+=("$path")
    fi
  done < <(manifest_artifact_paths)

  if ((${#missing[@]} > 0)); then
    fail_missing_manifest_artifact_paths "local worktree" "${missing[@]}"
  fi
}

verify_manifest_artifact_paths_remote() {
  local missing=()
  local path

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if ! git cat-file -e "origin/$target_branch:$path" 2>/dev/null; then
      missing+=("$path")
    fi
  done < <(manifest_artifact_paths)

  if ((${#missing[@]} > 0)); then
    fail_missing_manifest_artifact_paths "origin/$target_branch" "${missing[@]}"
  fi
}

verify_remote_publication() {
  git fetch origin "$target_branch" >/dev/null
  git cat-file -e "origin/$target_branch:public/pavbot-manifest.json" \
    || die "remote verification failed: missing public/pavbot-manifest.json on origin/$target_branch"
  verify_manifest_artifact_paths_remote
  printf 'remote publication verified on origin/%s\n' "$target_branch"
}

copy_or_remove_publish_path() {
  local rel_path="$1"
  local dest_root="$2"
  local src_path="$repo_root/$rel_path"
  local dest_path="$dest_root/$rel_path"

  rm -rf "$dest_path"
  if [[ -e "$src_path" ]]; then
    mkdir -p "$(dirname "$dest_path")"
    cp -R "$src_path" "$dest_path"
  fi
}

copy_publishable_outputs_to_worktree() {
  local dest_root="$1"

  if [[ "$topic_path" == "$mobile_public_only_topic" ]]; then
    copy_mobile_public_outputs_to_worktree "$dest_root"
    return 0
  fi

  copy_or_remove_publish_path "$topic_path/index.md" "$dest_root"
  copy_or_remove_publish_path "$topic_path/backlog.md" "$dest_root"
  copy_or_remove_publish_path "$topic_path/runs" "$dest_root"
  copy_or_remove_publish_path "$topic_path/pdfs" "$dest_root"
  copy_or_remove_publish_path "$topic_path/data" "$dest_root"
  copy_or_remove_publish_path "$topic_path/podcasts" "$dest_root"
}

copy_mobile_public_outputs_to_worktree() {
  local dest_root="$1"
  local src_root="$repo_root/$topic_path"
  local dest_topic_root="$dest_root/$topic_path"
  local src dest_path latest_stamp rel_path stamp

  rm -rf \
    "$dest_topic_root/index.md" \
    "$dest_topic_root/backlog.md" \
    "$dest_topic_root/runs" \
    "$dest_topic_root/data" \
    "$dest_topic_root/pdfs" \
    "$dest_topic_root/podcasts"

  mkdir -p "$dest_topic_root"
  latest_stamp="$(expected_mobile_news_stamp 2>/dev/null || true)"
  if [[ -z "$latest_stamp" ]]; then
    latest_stamp="$(latest_mobile_public_output_stamp "$src_root" 2>/dev/null || true)"
  fi
  [[ -n "$latest_stamp" ]] || return 0

  shopt -s nullglob
  for src in "$src_root"/data/*-mobile-news.json; do
    rel_path="${src#"$src_root"/}"
    stamp="$(mobile_public_output_stamp "$rel_path")" || continue
    [[ "$stamp" == "$latest_stamp" ]] || continue
    dest_path="$dest_topic_root/data/$(basename "$src")"
    mkdir -p "$(dirname "$dest_path")"
    cp "$src" "$dest_path"
  done

  for src in "$src_root"/pdfs/*-mobile-brief.pdf; do
    rel_path="${src#"$src_root"/}"
    stamp="$(mobile_public_output_stamp "$rel_path")" || continue
    [[ "$stamp" == "$latest_stamp" ]] || continue
    dest_path="$dest_topic_root/pdfs/$(basename "$src")"
    mkdir -p "$(dirname "$dest_path")"
    cp "$src" "$dest_path"
  done

  for src in "$src_root"/pdfs/*-newspaper.pdf; do
    rel_path="${src#"$src_root"/}"
    stamp="$(mobile_public_output_stamp "$rel_path")" || continue
    [[ "$stamp" == "$latest_stamp" ]] || continue
    dest_path="$dest_topic_root/pdfs/$(basename "$src")"
    mkdir -p "$(dirname "$dest_path")"
    cp "$src" "$dest_path"
  done

  for src in "$src_root"/podcasts/*/audio/*/podcast.mp3; do
    rel_path="${src#"$src_root"/}"
    stamp="$(mobile_public_output_stamp "$rel_path")" || continue
    [[ "$stamp" == "$latest_stamp" ]] || continue
    dest_path="$dest_topic_root/${src#"$src_root"/}"
    mkdir -p "$(dirname "$dest_path")"
    cp "$src" "$dest_path"
  done

  for src in "$src_root"/podcasts/*/script.md; do
    rel_path="${src#"$src_root"/}"
    stamp="$(mobile_public_output_stamp "$rel_path")" || continue
    [[ "$stamp" == "$latest_stamp" ]] || continue
    dest_path="$dest_topic_root/${src#"$src_root"/}"
    mkdir -p "$(dirname "$dest_path")"
    cp "$src" "$dest_path"
  done

  for src in "$src_root"/podcasts/*/draft.md; do
    rel_path="${src#"$src_root"/}"
    stamp="$(mobile_public_output_stamp "$rel_path")" || continue
    [[ "$stamp" == "$latest_stamp" ]] || continue
    dest_path="$dest_topic_root/${src#"$src_root"/}"
    mkdir -p "$(dirname "$dest_path")"
    cp "$src" "$dest_path"
  done

  for src in "$src_root"/podcasts/*/sources.md; do
    rel_path="${src#"$src_root"/}"
    stamp="$(mobile_public_output_stamp "$rel_path")" || continue
    [[ "$stamp" == "$latest_stamp" ]] || continue
    dest_path="$dest_topic_root/${src#"$src_root"/}"
    mkdir -p "$(dirname "$dest_path")"
    cp "$src" "$dest_path"
  done

  for src in "$src_root"/podcasts/*/tts_variants.json; do
    rel_path="${src#"$src_root"/}"
    stamp="$(mobile_public_output_stamp "$rel_path")" || continue
    [[ "$stamp" == "$latest_stamp" ]] || continue
    dest_path="$dest_topic_root/${src#"$src_root"/}"
    mkdir -p "$(dirname "$dest_path")"
    cp "$src" "$dest_path"
  done

  for src in "$src_root"/podcasts/*/audio/*/render.json; do
    rel_path="${src#"$src_root"/}"
    stamp="$(mobile_public_output_stamp "$rel_path")" || continue
    [[ "$stamp" == "$latest_stamp" ]] || continue
    dest_path="$dest_topic_root/${src#"$src_root"/}"
    mkdir -p "$(dirname "$dest_path")"
    cp "$src" "$dest_path"
  done

  for src in "$src_root"/podcasts/*/audio/*/render.log; do
    rel_path="${src#"$src_root"/}"
    stamp="$(mobile_public_output_stamp "$rel_path")" || continue
    [[ "$stamp" == "$latest_stamp" ]] || continue
    dest_path="$dest_topic_root/${src#"$src_root"/}"
    mkdir -p "$(dirname "$dest_path")"
    cp "$src" "$dest_path"
  done
  shopt -u nullglob
}

cleanup_isolated_worktree() {
  local status=$?
  if [[ -n "${isolated_worktree:-}" ]]; then
    git -C "$repo_root" worktree remove --force "$isolated_worktree" >/dev/null 2>&1 || true
  fi
  if [[ -n "${isolated_tmp:-}" ]]; then
    rm -rf "$isolated_tmp"
  fi
  exit "$status"
}

publish_isolated() {
  local pushed_marker remote_ref topic_slug

  git fetch origin "$target_branch" >/dev/null
  remote_ref="$(git rev-parse --verify "origin/$target_branch")" || die "missing origin/$target_branch"
  require_latest_mobile_news_data_for_latest_package

  isolated_tmp="$(mktemp -d "${TMPDIR:-/tmp}/pavbot-publish.XXXXXX")"
  isolated_worktree="$isolated_tmp/worktree"
  pushed_marker="$isolated_tmp/pushed"
  trap cleanup_isolated_worktree EXIT

  git worktree add --detach "$isolated_worktree" "$remote_ref" >/dev/null
  copy_publishable_outputs_to_worktree "$isolated_worktree"

  (
    cd "$isolated_worktree"

    if ! has_publishable_changes && ! needs_manifest_refresh_for_pulse_news && ! needs_manifest_refresh_for_reddit_radar && ! needs_manifest_refresh_for_mobile_news; then
      require_latest_mobile_news_data_for_latest_package
      require_latest_reddit_radar_original_comment_bodies
      verify_manifest_artifact_paths_local
      publish_cloudkit_briefings_gate
      printf 'no publishable changes for %s\n' "$topic_path"
      exit 0
    fi

    validate_jobs_data_outputs
    require_latest_research_data_for_latest_run
    validate_research_data_outputs
    require_latest_mobile_news_data_for_latest_package
    validate_mobile_news_data_outputs
    validate_pulse_news_data_outputs
    require_latest_reddit_radar_original_comment_bodies
    python3 "$manifest_generator" --repo-root "$PWD"
    verify_manifest_artifact_paths_local
    require_expected_mobile_news_data_in_manifest
    require_latest_mobile_news_data_in_manifest
    require_latest_pulse_news_data_in_manifest
    require_latest_reddit_radar_data_in_manifest
    stage_publishable_paths

    if git diff --cached --quiet; then
      publish_cloudkit_briefings_gate
      printf 'no publishable changes for %s\n' "$topic_path"
      exit 0
    fi

    require_staged_scope
    preflight_cloudkit_briefings_gate

    topic_slug="${topic_path#research/}"
    git commit -m "chore(pavbot): publish ${topic_slug} automation outputs" >/dev/null
    git push origin "HEAD:$target_branch" >/dev/null
    verify_remote_publication
    publish_cloudkit_briefings_gate
    touch "$pushed_marker"
  )

  git fetch origin "$target_branch" >/dev/null
  if [[ -f "$pushed_marker" ]]; then
    printf 'pushed pavbot outputs for %s to origin/%s\n' "$topic_path" "$target_branch"
  fi
}

isolated_mode=0
all_topics_mode=0
topic_arg=""

while (($# > 0)); do
  case "$1" in
    --all-topics)
      all_topics_mode=1
      shift
      ;;
    --isolated)
      isolated_mode=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      usage
      exit 2
      ;;
    *)
      if [[ -n "$topic_arg" ]]; then
        usage
        exit 2
      fi
      topic_arg="$1"
      shift
      ;;
  esac
done

if ((all_topics_mode)) && [[ -n "$topic_arg" ]]; then
  usage
  exit 2
fi

if ((all_topics_mode)) && ((isolated_mode)); then
  die "--all-topics does not support --isolated because it only heals CloudKit from the current manifest"
fi

if ((! all_topics_mode)) && [[ -z "$topic_arg" ]]; then
  usage
  exit 2
fi

topic_path="${topic_arg%/}"
if ((! all_topics_mode)); then
  [[ -n "$topic_path" ]] || die "topic path is required"
  [[ "$topic_path" == research/* ]] || die "topic path must start with research/"
  [[ "$topic_path" != "research/templates" && "$topic_path" != "research/templates/"* ]] || die "research/templates is not publishable"
  [[ "$topic_path" != /* ]] || die "topic path must be relative"
  [[ "$topic_path" != *"/../"* && "$topic_path" != "../"* && "$topic_path" != *"/.." && "$topic_path" != ".." ]] || die "topic path must not contain .."
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
cd "$repo_root"

if ((! all_topics_mode)); then
  [[ -d "$topic_path" ]] || die "topic path does not exist: $topic_path"
fi
[[ -f "$manifest_generator" ]] || die "missing scripts/generate_pavbot_manifest.py"
[[ -f "$cloudkit_publisher" ]] || die "missing scripts/publish_cloudkit_briefings.py"
[[ -f "$jobs_data_validator" ]] || die "missing scripts/validate_jobs_data.py"
[[ -f "$research_data_validator" ]] || die "missing scripts/validate_research_data.py"
[[ -f "$mobile_news_data_validator" ]] || die "missing scripts/validate_mobile_news_data.py"
[[ -f "$pulse_news_data_validator" ]] || die "missing scripts/validate_pulse_news_data.py"
git remote get-url origin >/dev/null 2>&1 || die "missing git remote: origin"

pavbot_manifest_url="$(resolve_pavbot_manifest_url)"
export PAVBOT_MANIFEST_URL="$pavbot_manifest_url"
printf 'using Pavbot manifest URL: %s\n' "$PAVBOT_MANIFEST_URL"

if ((all_topics_mode)); then
  publish_cloudkit_all_topics_gate
  exit 0
fi

git fetch origin "$target_branch" >/dev/null

remote_ref="$(git rev-parse --verify "origin/$target_branch")" || die "missing origin/$target_branch"
if ((isolated_mode)); then
  publish_isolated
  exit 0
fi

local_ref="$(git rev-parse --verify HEAD)"
if [[ "$local_ref" != "$remote_ref" ]]; then
  die "local HEAD must match origin/$target_branch before publishing; sync the workspace first"
fi

require_clean_publish_scope

if ! has_publishable_changes && ! needs_manifest_refresh_for_pulse_news && ! needs_manifest_refresh_for_reddit_radar && ! needs_manifest_refresh_for_mobile_news; then
  require_latest_mobile_news_data_for_latest_package
  require_latest_reddit_radar_original_comment_bodies
  verify_manifest_artifact_paths_local
  publish_cloudkit_briefings_gate
  printf 'no publishable changes for %s\n' "$topic_path"
  exit 0
fi

validate_jobs_data_outputs
require_latest_research_data_for_latest_run
validate_research_data_outputs
require_latest_mobile_news_data_for_latest_package
validate_mobile_news_data_outputs
validate_pulse_news_data_outputs
require_latest_reddit_radar_original_comment_bodies
python3 "$manifest_generator" --repo-root "$PWD"
verify_manifest_artifact_paths_local
require_expected_mobile_news_data_in_manifest
require_latest_mobile_news_data_in_manifest
require_latest_pulse_news_data_in_manifest
require_latest_reddit_radar_data_in_manifest

require_clean_publish_scope

stage_publishable_paths

if git diff --cached --quiet; then
  publish_cloudkit_briefings_gate
  printf 'no publishable changes for %s\n' "$topic_path"
  exit 0
fi

require_staged_scope
preflight_cloudkit_briefings_gate

topic_slug="${topic_path#research/}"
git commit -m "chore(pavbot): publish ${topic_slug} automation outputs" >/dev/null
git push origin "HEAD:$target_branch" >/dev/null
verify_remote_publication
publish_cloudkit_briefings_gate

printf 'pushed pavbot outputs for %s to origin/%s\n' "$topic_path" "$target_branch"
