#!/usr/bin/env bash
set -euo pipefail

target_branch="${PAVBOT_PUBLISH_BRANCH:-main}"
mobile_public_only_topic="research/aktualne-wydarzenia-mobile"
pulse_news_topic="research/puls-dnia-news"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
manifest_generator="$script_dir/generate_pavbot_manifest.py"
jobs_data_validator="$script_dir/validate_jobs_data.py"
research_data_validator="$script_dir/validate_research_data.py"
mobile_news_data_validator="$script_dir/validate_mobile_news_data.py"
pulse_news_data_validator="$script_dir/validate_pulse_news_data.py"

usage() {
  cat >&2 <<'EOF'
usage: scripts/pavbot_commit_and_push_outputs.sh [--isolated] research/<topic>

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

Optional environment:
  PAVBOT_MANIFEST_URL=https://raw.githubusercontent.com/<owner>/<repo>/<branch>/public/pavbot-manifest.json
      Overrides automatic manifest URL resolution.
  PAVBOT_RAW_BASE_URL=https://raw.githubusercontent.com/<owner>/<repo>/<branch>/
      Used to derive PAVBOT_MANIFEST_URL when PAVBOT_MANIFEST_URL is unset.
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

  isolated_tmp="$(mktemp -d "${TMPDIR:-/tmp}/pavbot-publish.XXXXXX")"
  isolated_worktree="$isolated_tmp/worktree"
  pushed_marker="$isolated_tmp/pushed"
  trap cleanup_isolated_worktree EXIT

  git worktree add --detach "$isolated_worktree" "$remote_ref" >/dev/null
  copy_publishable_outputs_to_worktree "$isolated_worktree"

  (
    cd "$isolated_worktree"

    if ! has_publishable_changes && ! needs_manifest_refresh_for_pulse_news; then
      printf 'no publishable changes for %s\n' "$topic_path"
      exit 0
    fi

    validate_jobs_data_outputs
    validate_research_data_outputs
    validate_mobile_news_data_outputs
    validate_pulse_news_data_outputs
    python3 "$manifest_generator" --repo-root "$PWD"
    require_latest_pulse_news_data_in_manifest
    stage_publishable_paths

    if git diff --cached --quiet; then
      printf 'no publishable changes for %s\n' "$topic_path"
      exit 0
    fi

    require_staged_scope

    topic_slug="${topic_path#research/}"
    git commit -m "chore(pavbot): publish ${topic_slug} automation outputs" >/dev/null
    git push origin "HEAD:$target_branch" >/dev/null
    touch "$pushed_marker"
  )

  git fetch origin "$target_branch" >/dev/null
  if [[ -f "$pushed_marker" ]]; then
    printf 'pushed pavbot outputs for %s to origin/%s\n' "$topic_path" "$target_branch"
  fi
}

isolated_mode=0
topic_arg=""

while (($# > 0)); do
  case "$1" in
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
[[ -f "$jobs_data_validator" ]] || die "missing scripts/validate_jobs_data.py"
[[ -f "$research_data_validator" ]] || die "missing scripts/validate_research_data.py"
[[ -f "$mobile_news_data_validator" ]] || die "missing scripts/validate_mobile_news_data.py"
[[ -f "$pulse_news_data_validator" ]] || die "missing scripts/validate_pulse_news_data.py"
git remote get-url origin >/dev/null 2>&1 || die "missing git remote: origin"

pavbot_manifest_url="$(resolve_pavbot_manifest_url)"
export PAVBOT_MANIFEST_URL="$pavbot_manifest_url"
printf 'using Pavbot manifest URL: %s\n' "$PAVBOT_MANIFEST_URL"

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

if ! has_publishable_changes && ! needs_manifest_refresh_for_pulse_news; then
  printf 'no publishable changes for %s\n' "$topic_path"
  exit 0
fi

validate_jobs_data_outputs
validate_research_data_outputs
validate_mobile_news_data_outputs
validate_pulse_news_data_outputs
python3 "$manifest_generator" --repo-root "$PWD"
require_latest_pulse_news_data_in_manifest

require_clean_publish_scope

stage_publishable_paths

if git diff --cached --quiet; then
  printf 'no publishable changes for %s\n' "$topic_path"
  exit 0
fi

require_staged_scope

topic_slug="${topic_path#research/}"
git commit -m "chore(pavbot): publish ${topic_slug} automation outputs" >/dev/null
git push origin "HEAD:$target_branch" >/dev/null

printf 'pushed pavbot outputs for %s to origin/%s\n' "$topic_path" "$target_branch"
