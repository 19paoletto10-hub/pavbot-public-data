#!/usr/bin/env bash
set -euo pipefail

target_branch="${PAVBOT_PUBLISH_BRANCH:-main}"

usage() {
  cat >&2 <<'EOF'
usage: scripts/pavbot_commit_and_push_outputs.sh [--isolated] research/<topic>

Publishes one Pavbot automation output set by committing only:
  - generated outputs from the selected research/<topic>/
  - public/pavbot-manifest.json

Output allowlist:
  - research/<topic>/runs/
  - research/<topic>/pdfs/
  - research/<topic>/podcasts/
  - research/<topic>/index.md
  - research/<topic>/backlog.md

Options:
  --isolated  publish from a temporary clean worktree based on origin/main,
              copying only allowlisted outputs from the current workspace

Required environment:
  PAVBOT_MANIFEST_URL=https://raw.githubusercontent.com/<owner>/<repo>/<branch>/public/pavbot-manifest.json
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
    if ! is_allowed_publish_path "$path"; then
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
    "$topic_path/index.md"|"$topic_path/backlog.md")
      return 0
      ;;
    "$topic_path/runs"|"$topic_path/runs/"*|"$topic_path/pdfs"|"$topic_path/pdfs/"*|"$topic_path/podcasts"|"$topic_path/podcasts/"*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

path_has_tracked_files() {
  [[ -n "$(git ls-files -- "$1")" ]]
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
  stage_path_if_present_or_tracked "$topic_path/podcasts"
  stage_path_if_present_or_tracked "public/pavbot-manifest.json"
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

  copy_or_remove_publish_path "$topic_path/index.md" "$dest_root"
  copy_or_remove_publish_path "$topic_path/backlog.md" "$dest_root"
  copy_or_remove_publish_path "$topic_path/runs" "$dest_root"
  copy_or_remove_publish_path "$topic_path/pdfs" "$dest_root"
  copy_or_remove_publish_path "$topic_path/podcasts" "$dest_root"
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

    if ! has_publishable_changes; then
      printf 'no publishable changes for %s\n' "$topic_path"
      exit 0
    fi

    python3 scripts/generate_pavbot_manifest.py
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

[[ -n "${PAVBOT_MANIFEST_URL:-}" ]] || die "PAVBOT_MANIFEST_URL is required"

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
cd "$repo_root"

[[ -d "$topic_path" ]] || die "topic path does not exist: $topic_path"
[[ -f "scripts/generate_pavbot_manifest.py" ]] || die "missing scripts/generate_pavbot_manifest.py"
git remote get-url origin >/dev/null 2>&1 || die "missing git remote: origin"

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

if ! has_publishable_changes; then
  printf 'no publishable changes for %s\n' "$topic_path"
  exit 0
fi

python3 scripts/generate_pavbot_manifest.py

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
