#!/usr/bin/env bash
set -euo pipefail

target_branch="main"
mobile_public_only_topic="research/aktualne-wydarzenia-mobile"
pulse_news_topic="research/puls-dnia-news"
reddit_radar_topic="research/reddit-radar"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
manifest_generator="$script_dir/generate_pavbot_manifest.py"
public_feed_exporter="$script_dir/export_public_feed.py"
publication_contract="$script_dir/pavbot_publication_contract.py"
usage_ledger="$script_dir/pavbot_usage_ledger.py"
jobs_data_validator="$script_dir/validate_jobs_data.py"
research_data_validator="$script_dir/validate_research_data.py"
mobile_news_data_validator="$script_dir/validate_mobile_news_data.py"
pulse_news_data_validator="$script_dir/validate_pulse_news_data.py"
cloudkit_publisher="${PAVBOT_CLOUDKIT_PUBLISHER:-$script_dir/publish_cloudkit_briefings.py}"
ledger_run_id=""
ledger_publish_status="not_started"
ledger_remote_verification_status="not_started"

usage() {
  cat >&2 <<'EOF'
usage: scripts/pavbot_commit_and_push_outputs.sh [--isolated] [--force-manifest] [--cloudkit-only] research/<topic>

Publishes one Pavbot automation output set by committing only app-visible files:
  - generated public outputs from the selected research/<topic>/
  - public/pavbot-manifest.json

Output allowlist:
  - research/<topic>/runs/
  - research/<topic>/pdfs/ (except research/puls-dnia-news)
  - research/<topic>/data/
  - research/<topic>/podcasts/*/podcast.mp3
  - research/<topic>/podcasts/*/brief.pdf
  - research/<topic>/podcasts/*/script.md
  - research/<topic>/podcasts/*/audio/*/podcast.mp3

Options:
  --isolated  publish from a temporary clean worktree based on origin/main,
              copying only allowlisted outputs from the current workspace
  --force-manifest
              refresh and stage public/pavbot-manifest.json even when topic
              outputs are otherwise unchanged
  --cloudkit-only
              do not commit or push files; verify the latest remote topic
              bundle and publish/verify its CloudKit Briefing record only

Optional environment:
  PAVBOT_MANIFEST_URL=https://raw.githubusercontent.com/<owner>/<repo>/<branch>/public/pavbot-manifest.json
      Overrides automatic manifest URL resolution.
  PAVBOT_RAW_BASE_URL=https://raw.githubusercontent.com/<owner>/<repo>/<branch>/
      Used to derive PAVBOT_MANIFEST_URL when PAVBOT_MANIFEST_URL is unset.
  PAVBOT_CLOUDKIT_CONTAINER_ID=iCloud.com.paweltanski.pavbotviewer
      CloudKit container used by scripts/publish_cloudkit_briefings.py.
  PAVBOT_CLOUDKIT_ENVIRONMENT=production
      CloudKit environment passed to cktool.
  PAVBOT_CLOUDKIT_TEAM_ID=SP774TZZU8
      Apple Developer Program team id passed to cktool.
  PAVBOT_CLOUDKIT_DRY_RUN=1
      Verify deterministic Briefing records without calling cktool.
  PAVBOT_CLOUDKIT_PUBLISHER=/path/to/publisher
      Override the CloudKit publisher executable for tests.
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
    if is_private_runtime_path "$path"; then
      continue
    fi
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
    if is_private_runtime_path "$path"; then
      continue
    fi
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
    "$topic_path/topic.md")
      return 0
      ;;
    *)
      if [[ "$topic_path" == "$mobile_public_only_topic" ]]; then
        is_mobile_public_publish_path "$path"
      elif [[ "$topic_path" == "$pulse_news_topic" ]]; then
        is_pulse_news_publish_path "$path"
      elif [[ "$topic_path" == "$reddit_radar_topic" ]]; then
        is_reddit_radar_publish_path "$path"
      else
        is_standard_public_publish_path "$path"
      fi
      ;;
  esac
}

is_private_runtime_path() {
  local path="$1"
  case "$path" in
    .pavbot/private|.pavbot/private/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_pulse_news_publish_path() {
  local path="$1"
  case "$path" in
    "$topic_path/runs"|"$topic_path/runs/"*.md)
      return 0
      ;;
    "$topic_path/data"|"$topic_path/data/"*-pulse-news.json)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_reddit_radar_publish_path() {
  local path="$1"
  case "$path" in
    "$topic_path/runs"|"$topic_path/runs/"*-reddit-radar.md)
      return 0
      ;;
    "$topic_path/data"|"$topic_path/data/"*-reddit-radar.json|"$topic_path/data/"*-reddit-radar-raw.json)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_standard_public_publish_path() {
  local path="$1"
  case "$path" in
    "$topic_path/runs"|"$topic_path/runs/"*.md)
      return 0
      ;;
    "$topic_path/pdfs"|"$topic_path/pdfs/"*.pdf)
      return 0
      ;;
    "$topic_path/data"|"$topic_path/data/"*.json)
      return 0
      ;;
    "$topic_path/podcasts")
      return 0
      ;;
    *)
      is_public_podcast_publish_path "$path"
      ;;
  esac
}

is_public_podcast_publish_path() {
  local path="$1"
  case "$path" in
    "$topic_path/podcasts/"*/podcast.mp3)
      return 0
      ;;
    "$topic_path/podcasts/"*/brief.pdf)
      return 0
      ;;
    "$topic_path/podcasts/"*/script.md)
      return 0
      ;;
    "$topic_path/podcasts/"*/audio/*/podcast.mp3)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_allowed_staged_path() {
  local path="$1"
  if is_allowed_publish_path "$path"; then
    return 0
  fi

  if is_staged_delete "$path" && is_private_public_feed_path "$path"; then
    return 0
  fi

  return 1
}

is_staged_delete() {
  local path="$1"
  local status
  status="$(git diff --cached --name-status -- "$path" | awk 'NR == 1 {print $1}')"
  [[ "$status" == D* ]]
}

is_private_public_feed_path() {
  local path="$1"
  case "$path" in
    .agents/*|backend/*|docs/*|integrations/*|ios/*|scripts/*|tests/*)
      return 0
      ;;
    */proposals/*|*/tools/*)
      return 0
      ;;
    */automation-prompt.md|*/automation-research-prompt.md|*/automation-podcast-prompt.md|*/backlog.md|*/draft.md|*/index.md|*/render.json|*/sources.md|*/topic.md|*/tts_variants.json)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_mobile_public_publish_path() {
  local path="$1"
  case "$path" in
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
    *)
      return 1
      ;;
  esac
}

mobile_public_output_stamp() {
  local rel_path="$1"
  local name stamp

  case "$rel_path" in
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

append_expected_path_if_exists() {
  local rel_path="$1"
  if [[ -f "$repo_root/$rel_path" ]]; then
    expected_remote_paths+=("$rel_path")
    expected_manifest_paths+=("$rel_path")
  fi
}

append_expected_paths_from_dir() {
  local rel_dir="$1"
  local abs_dir="$repo_root/$rel_dir"
  local path

  [[ -d "$abs_dir" ]] || return 0
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    [[ "$(basename "$path")" == ".gitkeep" ]] && continue
    expected_remote_paths+=("$path")
    expected_manifest_paths+=("$path")
  done < <(
    cd "$repo_root"
    find "$rel_dir" -type f | LC_ALL=C sort
  )
}

append_expected_public_paths_from_dir() {
  local rel_dir="$1"
  local abs_dir="$repo_root/$rel_dir"
  local path

  [[ -d "$abs_dir" ]] || return 0
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    [[ "$(basename "$path")" == ".gitkeep" ]] && continue
    if is_allowed_publish_path "$path"; then
      expected_remote_paths+=("$path")
      expected_manifest_paths+=("$path")
    fi
  done < <(
    cd "$repo_root"
    find "$rel_dir" -type f | LC_ALL=C sort
  )
}

stage_publishable_paths() {
  stage_matching_publishable_paths "$topic_path"
  stage_private_topic_deletions "$topic_path"
  stage_path_if_present_or_tracked "public/pavbot-manifest.json"
}

run_publication_contract() {
  local command="$1"
  local root="$2"
  shift 2
  python3 "$publication_contract" "$command" "$topic_path" --repo-root "$root" "$@"
}

stage_matching_publishable_paths() {
  local rel_root="$1"
  local path

  [[ -e "$rel_root" ]] || return 0
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if is_allowed_publish_path "$path"; then
      git add -A -- "$path"
    fi
  done < <(
    find "$rel_root" -type f | LC_ALL=C sort
  )
}

stage_private_topic_deletions() {
  local rel_root="$1"
  local entry status path

  while IFS= read -r -d '' entry; do
    status="${entry:0:2}"
    path="${entry:3}"
    if [[ "$status" == *D* ]] && (is_allowed_publish_path "$path" || is_private_public_feed_path "$path"); then
      git add -A -- "$path"
    fi
  done < <(git status --porcelain=v1 -z -- "$rel_root")
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

latest_jobs_run_rel_path() {
  if [[ "$topic_path" != "research/llm-ai-jobs-wroclaw" ]]; then
    return 1
  fi

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

latest_jobs_bundle_rel_paths() {
  local run_path stamp
  run_path="$(latest_jobs_run_rel_path)" || return 1
  stamp="$(basename "$run_path" .md)"
  printf '%s\n' \
    "$run_path" \
    "$topic_path/data/${stamp}-jobs.json" \
    "$topic_path/pdfs/${stamp}-llm-ai-jobs-wroclaw.pdf"
}

missing_latest_jobs_manifest_paths() {
  local manifest_path="public/pavbot-manifest.json"
  local -a latest_paths=()
  [[ -f "$manifest_path" ]] || return 1

  while IFS= read -r rel_path; do
    [[ -n "$rel_path" ]] || continue
    latest_paths+=("$rel_path")
  done < <(latest_jobs_bundle_rel_paths 2>/dev/null || true)
  ((${#latest_paths[@]} > 0)) || return 1

  python3 - "$manifest_path" "${latest_paths[@]}" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
expected = sys.argv[2:]

try:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
except Exception:
    for path in expected:
        print(path)
    raise SystemExit(1)

manifest_paths = {
    artifact.get("path")
    for artifact in manifest.get("artifacts", [])
    if isinstance(artifact, dict)
}
missing = [path for path in expected if path not in manifest_paths]
for path in missing:
    print(path)
raise SystemExit(1 if missing else 0)
PY
}

require_latest_jobs_bundle_in_manifest() {
  local missing_paths
  latest_jobs_run_rel_path >/dev/null 2>&1 || return 0

  if ! missing_paths="$(missing_latest_jobs_manifest_paths 2>/dev/null)"; then
    die "generated manifest missing latest Jobs bundle paths: ${missing_paths//$'\n'/ }"
  fi
}

needs_manifest_refresh_for_jobs() {
  latest_jobs_run_rel_path >/dev/null 2>&1 || return 1
  if missing_latest_jobs_manifest_paths >/dev/null 2>&1; then
    return 1
  fi
  return 0
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

build_mobile_public_expected_paths() {
  local src_root="$repo_root/$topic_path"
  local src rel_path stamp latest_stamp

  latest_stamp="$(latest_mobile_public_output_stamp "$src_root" 2>/dev/null || true)"
  [[ -n "$latest_stamp" ]] || return 0

  shopt -s nullglob
  for src in "$src_root"/data/*-mobile-news.json; do
    rel_path="${src#"$repo_root"/}"
    stamp="$(mobile_public_output_stamp "${src#"$src_root"/}")" || continue
    [[ "$stamp" == "$latest_stamp" ]] || continue
    expected_remote_paths+=("$rel_path")
    expected_manifest_paths+=("$rel_path")
  done

  for src in "$src_root"/pdfs/*-mobile-brief.pdf; do
    rel_path="${src#"$repo_root"/}"
    stamp="$(mobile_public_output_stamp "${src#"$src_root"/}")" || continue
    [[ "$stamp" == "$latest_stamp" ]] || continue
    expected_remote_paths+=("$rel_path")
    expected_manifest_paths+=("$rel_path")
  done

  for src in "$src_root"/pdfs/*-newspaper.pdf; do
    rel_path="${src#"$repo_root"/}"
    stamp="$(mobile_public_output_stamp "${src#"$src_root"/}")" || continue
    [[ "$stamp" == "$latest_stamp" ]] || continue
    expected_remote_paths+=("$rel_path")
    expected_manifest_paths+=("$rel_path")
  done

  for src in "$src_root"/podcasts/*/audio/*/podcast.mp3; do
    rel_path="${src#"$repo_root"/}"
    stamp="$(mobile_public_output_stamp "${src#"$src_root"/}")" || continue
    [[ "$stamp" == "$latest_stamp" ]] || continue
    expected_remote_paths+=("$rel_path")
    expected_manifest_paths+=("$rel_path")
  done

  for src in "$src_root"/podcasts/*/script.md; do
    rel_path="${src#"$repo_root"/}"
    stamp="$(mobile_public_output_stamp "${src#"$src_root"/}")" || continue
    [[ "$stamp" == "$latest_stamp" ]] || continue
    expected_remote_paths+=("$rel_path")
    expected_manifest_paths+=("$rel_path")
  done
  shopt -u nullglob
}

build_reddit_radar_expected_paths() {
  local src

  append_expected_public_paths_from_dir "$topic_path/runs"

  shopt -s nullglob
  for src in "$repo_root"/"$topic_path"/data/*-reddit-radar.json "$repo_root"/"$topic_path"/data/*-reddit-radar-raw.json; do
    [[ -f "$src" ]] || continue
    expected_remote_paths+=("${src#"$repo_root"/}")
    expected_manifest_paths+=("${src#"$repo_root"/}")
  done
  shopt -u nullglob
}

build_expected_publication_paths() {
  expected_remote_paths=("public/pavbot-manifest.json")
  expected_manifest_paths=()

  if [[ "$topic_path" == "$mobile_public_only_topic" ]]; then
    build_mobile_public_expected_paths
    return 0
  fi

  if [[ "$topic_path" == "$reddit_radar_topic" ]]; then
    build_reddit_radar_expected_paths
    return 0
  fi

  if [[ "$topic_path" == "$pulse_news_topic" ]]; then
    append_expected_public_paths_from_dir "$topic_path/runs"
    shopt -s nullglob
    for src in "$repo_root"/"$topic_path"/data/*-pulse-news.json; do
      [[ -f "$src" ]] || continue
      expected_remote_paths+=("${src#"$repo_root"/}")
      expected_manifest_paths+=("${src#"$repo_root"/}")
    done
    shopt -u nullglob
    return 0
  fi

  append_expected_public_paths_from_dir "$topic_path/runs"
  append_expected_public_paths_from_dir "$topic_path/pdfs"
  append_expected_public_paths_from_dir "$topic_path/data"
  append_expected_public_paths_from_dir "$topic_path/podcasts"
}

sync_local_manifest_from_remote() {
  mkdir -p "$repo_root/public"
  git show "origin/$target_branch:public/pavbot-manifest.json" > "$repo_root/public/pavbot-manifest.json"
}

verify_remote_publication() {
  local manifest_path path
  local missing_remote_paths=()
  local missing_manifest_paths=()

  build_expected_publication_paths
  git fetch origin "$target_branch" >/dev/null
  manifest_path="$(mktemp "${TMPDIR:-/tmp}/pavbot-manifest.XXXXXX.json")"
  git show "origin/$target_branch:public/pavbot-manifest.json" > "$manifest_path" || die "cannot read origin/$target_branch:public/pavbot-manifest.json"

  for path in "${expected_remote_paths[@]}"; do
    if ! git cat-file -e "origin/$target_branch:$path" 2>/dev/null; then
      missing_remote_paths+=("$path")
    fi
  done

  if ((${#expected_manifest_paths[@]} > 0)); then
    local manifest_check_output=""
    if ! manifest_check_output="$(
      python3 - "$manifest_path" "${expected_manifest_paths[@]}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    manifest = json.load(handle)
expected = sys.argv[2:]
manifest_paths = {
    artifact.get("path")
    for artifact in manifest.get("artifacts", [])
    if isinstance(artifact, dict)
}
missing = [path for path in expected if path not in manifest_paths]
for path in missing:
    print(path)
raise SystemExit(1 if missing else 0)
PY
    )"; then
      while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        missing_manifest_paths+=("$path")
      done <<< "$manifest_check_output"
    fi
  fi

  rm -f "$manifest_path"

  if ((${#missing_manifest_paths[@]} > 0 || ${#missing_remote_paths[@]} > 0)); then
    local messages=()
    if ((${#missing_manifest_paths[@]} > 0)); then
      messages+=("missing from remote manifest: ${missing_manifest_paths[*]}")
    fi
    if ((${#missing_remote_paths[@]} > 0)); then
      messages+=("missing from origin/$target_branch: ${missing_remote_paths[*]}")
    fi
    die "publication verification failed; ${messages[*]}"
  fi

  sync_local_manifest_from_remote
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

preflight_cloudkit_briefings_gate() {
  local container_id="${PAVBOT_CLOUDKIT_CONTAINER_ID:-iCloud.com.paweltanski.pavbotviewer}"
  local environment="${PAVBOT_CLOUDKIT_ENVIRONMENT:-production}"
  local team_id="${PAVBOT_CLOUDKIT_TEAM_ID:-SP774TZZU8}"
  local -a common_args=(
    "--manifest" "public/pavbot-manifest.json"
    "--manifest-url" "$PAVBOT_MANIFEST_URL"
    "--container-id" "$container_id"
    "--environment" "$environment"
    "--team-id" "$team_id"
    "--topic" "$topic_path"
  )

  [[ -f "$cloudkit_publisher" ]] || die "missing CloudKit publisher: $cloudkit_publisher"

  if [[ "${PAVBOT_CLOUDKIT_DRY_RUN:-0}" == "1" ]]; then
    return 0
  fi

  if ! run_cloudkit_publisher "preflight" "${common_args[@]}"; then
    die "CloudKit preflight failed"
  fi
  printf 'cloudkit briefing preflight verified\n'
}

publish_cloudkit_briefings_gate() {
  local mode="publish"
  local container_id="${PAVBOT_CLOUDKIT_CONTAINER_ID:-iCloud.com.paweltanski.pavbotviewer}"
  local environment="${PAVBOT_CLOUDKIT_ENVIRONMENT:-production}"
  local team_id="${PAVBOT_CLOUDKIT_TEAM_ID:-SP774TZZU8}"
  local -a common_args=(
    "--manifest" "public/pavbot-manifest.json"
    "--manifest-url" "$PAVBOT_MANIFEST_URL"
    "--container-id" "$container_id"
    "--environment" "$environment"
    "--team-id" "$team_id"
    "--topic" "$topic_path"
  )

  [[ -f "$cloudkit_publisher" ]] || die "missing CloudKit publisher: $cloudkit_publisher"

  if [[ "${PAVBOT_CLOUDKIT_DRY_RUN:-0}" == "1" ]]; then
    if ! run_cloudkit_publisher "dry-run" "${common_args[@]}"; then
      die "CloudKit publication failed"
    fi
    printf 'cloudkit briefing dry-run verified\n'
    return 0
  fi

  if ! run_cloudkit_publisher "preflight" "${common_args[@]}"; then
    die "CloudKit preflight failed"
  fi
  printf 'cloudkit briefing preflight verified\n'
  if ! run_cloudkit_publisher "$mode" "${common_args[@]}"; then
    die "CloudKit publication failed"
  fi
  if ! run_cloudkit_publisher "verify" "${common_args[@]}"; then
    die "CloudKit publication failed"
  fi
  printf 'cloudkit briefing publication verified\n'
}

publish_cloudkit_only() {
  git fetch origin "$target_branch" >/dev/null
  run_publication_contract verify-remote "$repo_root" --ref "origin/$target_branch"
  ledger_publish_status="skipped"
  ledger_remote_verification_status="ok"
  sync_local_manifest_from_remote
  publish_cloudkit_briefings_gate
  printf 'cloudkit-only publication verified for %s on origin/%s\n' "$topic_path" "$target_branch"
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

  if [[ "$topic_path" == "$reddit_radar_topic" ]]; then
    copy_reddit_radar_outputs_to_worktree "$dest_root"
    return 0
  fi

  copy_allowed_topic_outputs_to_worktree "$dest_root"
}

copy_allowed_topic_outputs_to_worktree() {
  local dest_root="$1"
  local src_root="$repo_root/$topic_path"
  local dest_topic_root="$dest_root/$topic_path"
  local src rel_path dest_path

  rm -rf "$dest_topic_root"
  [[ -d "$src_root" ]] || return 0

  while IFS= read -r src; do
    [[ -n "$src" ]] || continue
    rel_path="${src#"$repo_root"/}"
    if ! is_allowed_publish_path "$rel_path"; then
      continue
    fi
    dest_path="$dest_root/$rel_path"
    mkdir -p "$(dirname "$dest_path")"
    cp "$src" "$dest_path"
  done < <(
    find "$src_root" -type f | LC_ALL=C sort
  )
}

copy_manifest_context_to_worktree() {
  local dest_root="$1"
  local docs_path="docs/how-to-use.md"

  if [[ -f "$repo_root/$docs_path" ]]; then
    mkdir -p "$dest_root/docs"
    cp "$repo_root/$docs_path" "$dest_root/$docs_path"
  fi
}

copy_publication_helpers_to_worktree() {
  local dest_root="$1"
  local helper
  local helpers=(
    "generate_pavbot_manifest.py"
    "export_public_feed.py"
    "pavbot_publication_contract.py"
    "pavbot_pdf_theme.py"
    "render_mobile_news_data.py"
    "render_research_data.py"
    "render_research_pdf.py"
    "validate_jobs_data.py"
    "validate_mobile_news_data.py"
    "validate_pulse_news_data.py"
    "validate_research_data.py"
    "publish_cloudkit_briefings.py"
  )

  mkdir -p "$dest_root/scripts"
  for helper in "${helpers[@]}"; do
    if [[ -f "$script_dir/$helper" ]]; then
      cp "$script_dir/$helper" "$dest_root/scripts/$helper"
    fi
  done
}

verify_public_manifest_scope() {
  local manifest_path="public/pavbot-manifest.json"
  [[ -f "$manifest_path" ]] || die "missing generated manifest: $manifest_path"

  python3 - "$manifest_path" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

forbidden_prefixes = (
    ".agents/",
    "backend/",
    "docs/",
    "integrations/",
    "ios/",
    "scripts/",
    "tests/",
)
forbidden_basenames = {
    "automation-podcast-prompt.md",
    "automation-prompt.md",
    "automation-research-prompt.md",
    "backlog.md",
    "draft.md",
    "index.md",
    "render.json",
    "sources.md",
    "topic.md",
    "tts_variants.json",
}
forbidden_segments = {"/proposals/", "/tools/"}


def forbidden(value):
    if not isinstance(value, str) or not value:
        return False
    if value.startswith("https://raw.githubusercontent.com/"):
        try:
            value = value.split("/main/", 1)[1]
        except IndexError:
            pass
    return (
        value.startswith(forbidden_prefixes)
        or any(segment in f"/{value}/" for segment in forbidden_segments)
        or Path(value).name in forbidden_basenames
    )


bad = []
for automation in manifest.get("automations", []):
    if isinstance(automation, dict):
        for key in ("sourcePath", "sourceUrl", "outputUrl"):
            value = automation.get(key)
            if forbidden(value):
                bad.append(value)

for topic in manifest.get("topics", []):
    if isinstance(topic, dict):
        for key in ("topicFilePath", "url"):
            value = topic.get(key)
            if forbidden(value):
                bad.append(value)

for artifact in manifest.get("artifacts", []):
    if isinstance(artifact, dict) and forbidden(artifact.get("path")):
        bad.append(artifact.get("path"))

if bad:
    print("manifest contains private/developer paths:", file=sys.stderr)
    for path in sorted({str(item) for item in bad}):
        print(f"  {path}", file=sys.stderr)
    raise SystemExit(1)
PY
}

copy_reddit_radar_outputs_to_worktree() {
  local dest_root="$1"
  local src_root="$repo_root/$topic_path"
  local dest_topic_root="$dest_root/$topic_path"
  local src dest_path

  rm -rf "$dest_topic_root"
  mkdir -p "$dest_topic_root/runs" "$dest_topic_root/data"

  shopt -s nullglob
  for src in "$src_root"/runs/*-reddit-radar.md; do
    dest_path="$dest_topic_root/runs/$(basename "$src")"
    mkdir -p "$(dirname "$dest_path")"
    cp "$src" "$dest_path"
  done

  for src in "$src_root"/data/*-reddit-radar.json "$src_root"/data/*-reddit-radar-raw.json; do
    dest_path="$dest_topic_root/data/$(basename "$src")"
    mkdir -p "$(dirname "$dest_path")"
    cp "$src" "$dest_path"
  done
  shopt -u nullglob
}

copy_mobile_public_outputs_to_worktree() {
  local dest_root="$1"
  local src_root="$repo_root/$topic_path"
  local dest_topic_root="$dest_root/$topic_path"
  local src dest_path latest_stamp rel_path stamp

  rm -rf "$dest_topic_root"
  mkdir -p "$dest_topic_root"
  latest_stamp="$(latest_mobile_public_output_stamp "$src_root" 2>/dev/null || true)"
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
  shopt -u nullglob
}

cleanup_isolated_worktree() {
  local exit_status=$?
  if [[ -n "${isolated_worktree:-}" ]]; then
    git -C "$repo_root" worktree remove --force "$isolated_worktree" >/dev/null 2>&1 || true
  fi
  if [[ -n "${isolated_tmp:-}" ]]; then
    rm -rf "$isolated_tmp"
  fi
  finish_usage_ledger "$exit_status"
  exit "$exit_status"
}

start_usage_ledger() {
  local automation_id model output
  [[ -f "$usage_ledger" ]] || return 0
  automation_id="${PAVBOT_AUTOMATION_ID:-${topic_path#research/}-publish}"
  model="${PAVBOT_MODEL:-}"
  output="$(
    python3 "$usage_ledger" start \
      --automation-id "$automation_id" \
      --topic "$topic_path" \
      ${model:+--model "$model"} 2>/dev/null || true
  )"
  if [[ -n "$output" ]]; then
    ledger_run_id="$(
      python3 -c 'import json,sys; print(json.load(sys.stdin).get("runId",""))' <<< "$output" 2>/dev/null || true
    )"
  fi
}

finish_usage_ledger() {
  local exit_status="$1"
  local ledger_status="ok"
  [[ -n "$ledger_run_id" && -f "$usage_ledger" ]] || return 0
  if [[ "$exit_status" -ne 0 ]]; then
    ledger_status="failed"
  fi
  python3 "$usage_ledger" finish \
    --run-id "$ledger_run_id" \
    --status "$ledger_status" \
    --publish-status "$ledger_publish_status" \
    --remote-verification-status "$ledger_remote_verification_status" >/dev/null 2>&1 || true
}

publish_isolated() {
  local pushed_marker remote_ref topic_slug

  git fetch origin "$target_branch" >/dev/null
  remote_ref="$(git rev-parse --verify "origin/$target_branch")" || die "missing origin/$target_branch"

  run_publication_contract prepare "$repo_root"
  run_publication_contract verify-local "$repo_root"

  isolated_tmp="$(mktemp -d "${TMPDIR:-/tmp}/pavbot-publish.XXXXXX")"
  isolated_worktree="$isolated_tmp/worktree"
  pushed_marker="$isolated_tmp/pushed"
  trap cleanup_isolated_worktree EXIT

  git worktree add --detach "$isolated_worktree" "$remote_ref" >/dev/null
  copy_manifest_context_to_worktree "$isolated_worktree"
  copy_publication_helpers_to_worktree "$isolated_worktree"
  copy_publishable_outputs_to_worktree "$isolated_worktree"

  (
    cd "$isolated_worktree"

    if ! has_publishable_changes && ! needs_manifest_refresh_for_pulse_news && ! needs_manifest_refresh_for_jobs && ((force_manifest == 0)); then
      printf 'no publishable changes for %s\n' "$topic_path"
      exit 0
    fi

    if [[ "$topic_path" != "$mobile_public_only_topic" ]]; then
      run_publication_contract verify-local "$PWD"
    fi
    python3 "$manifest_generator" --repo-root "$PWD"
    verify_public_manifest_scope
    require_latest_pulse_news_data_in_manifest
    require_latest_jobs_bundle_in_manifest
    stage_publishable_paths

    if git diff --cached --quiet; then
      printf 'no publishable changes for %s\n' "$topic_path"
      exit 0
    fi

    require_staged_scope
    preflight_cloudkit_briefings_gate

    topic_slug="${topic_path#research/}"
    git commit -m "chore(pavbot): publish ${topic_slug} automation outputs" >/dev/null
    git push origin "HEAD:$target_branch" >/dev/null
    touch "$pushed_marker"
  )

  git fetch origin "$target_branch" >/dev/null
  if [[ -f "$pushed_marker" ]]; then
    ledger_publish_status="ok"
    run_publication_contract verify-remote "$repo_root" --ref "origin/$target_branch"
    ledger_remote_verification_status="ok"
    sync_local_manifest_from_remote
    publish_cloudkit_briefings_gate
    printf 'pushed pavbot outputs for %s to origin/%s\n' "$topic_path" "$target_branch"
  else
    ledger_publish_status="skipped"
    ledger_remote_verification_status="skipped"
  fi
}

isolated_mode=0
force_manifest=0
cloudkit_only=0
topic_arg=""

while (($# > 0)); do
  case "$1" in
    --isolated)
      isolated_mode=1
      shift
      ;;
    --force-manifest)
      force_manifest=1
      shift
      ;;
    --cloudkit-only)
      cloudkit_only=1
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

if [[ -z "$topic_arg" ]]; then
  usage
  exit 2
fi

topic_path="${topic_arg%/}"
[[ -n "$topic_path" ]] || die "topic path is required"
[[ "$topic_path" == research/* ]] || die "topic path must start with research/"
[[ "$topic_path" != "research/templates" && "$topic_path" != "research/templates/"* ]] || die "research/templates is not publishable"
[[ "$topic_path" != /* ]] || die "topic path must be relative"
[[ "$topic_path" != *"/../"* && "$topic_path" != "../"* && "$topic_path" != *"/.." && "$topic_path" != ".." ]] || die "topic path must not contain .."

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
cd "$repo_root"

[[ -d "$topic_path" ]] || die "topic path does not exist: $topic_path"
[[ -f "$manifest_generator" ]] || die "missing scripts/generate_pavbot_manifest.py"
[[ -f "$public_feed_exporter" ]] || die "missing scripts/export_public_feed.py"
[[ -f "$publication_contract" ]] || die "missing scripts/pavbot_publication_contract.py"
[[ -f "$jobs_data_validator" ]] || die "missing scripts/validate_jobs_data.py"
[[ -f "$research_data_validator" ]] || die "missing scripts/validate_research_data.py"
[[ -f "$mobile_news_data_validator" ]] || die "missing scripts/validate_mobile_news_data.py"
[[ -f "$pulse_news_data_validator" ]] || die "missing scripts/validate_pulse_news_data.py"
git remote get-url origin >/dev/null 2>&1 || die "missing git remote: origin"

start_usage_ledger
trap 'pavbot_exit_status=$?; finish_usage_ledger "$pavbot_exit_status"; exit "$pavbot_exit_status"' EXIT

pavbot_manifest_url="$(resolve_pavbot_manifest_url)"
export PAVBOT_MANIFEST_URL="$pavbot_manifest_url"
printf 'using Pavbot manifest URL: %s\n' "$PAVBOT_MANIFEST_URL"

git fetch origin "$target_branch" >/dev/null

remote_ref="$(git rev-parse --verify "origin/$target_branch")" || die "missing origin/$target_branch"
if ((cloudkit_only)); then
  publish_cloudkit_only
  exit 0
fi
if ((isolated_mode)); then
  publish_isolated
  exit 0
fi

local_ref="$(git rev-parse --verify HEAD)"
if [[ "$local_ref" != "$remote_ref" ]]; then
  die "local HEAD must match origin/$target_branch before publishing; sync the workspace first"
fi

require_clean_publish_scope

run_publication_contract prepare "$repo_root"
run_publication_contract verify-local "$repo_root"
python3 "$manifest_generator" --repo-root "$PWD"
verify_public_manifest_scope
require_latest_pulse_news_data_in_manifest
require_latest_jobs_bundle_in_manifest

require_clean_publish_scope

if ! has_publishable_changes && ! needs_manifest_refresh_for_pulse_news && ! needs_manifest_refresh_for_jobs && ((force_manifest == 0)); then
  ledger_publish_status="skipped"
  ledger_remote_verification_status="skipped"
  printf 'no publishable changes for %s\n' "$topic_path"
  exit 0
fi

stage_publishable_paths

if git diff --cached --quiet; then
  ledger_publish_status="skipped"
  ledger_remote_verification_status="skipped"
  printf 'no publishable changes for %s\n' "$topic_path"
  exit 0
fi

require_staged_scope
preflight_cloudkit_briefings_gate

topic_slug="${topic_path#research/}"
git commit -m "chore(pavbot): publish ${topic_slug} automation outputs" >/dev/null
git push origin "HEAD:$target_branch" >/dev/null
ledger_publish_status="ok"
run_publication_contract verify-remote "$repo_root" --ref "origin/$target_branch"
ledger_remote_verification_status="ok"
sync_local_manifest_from_remote
publish_cloudkit_briefings_gate

printf 'pushed pavbot outputs for %s to origin/%s\n' "$topic_path" "$target_branch"
