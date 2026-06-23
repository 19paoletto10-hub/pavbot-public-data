#!/usr/bin/env bash
set -euo pipefail

target_branch="${PAVBOT_PUBLISH_BRANCH:-main}"

usage() {
  cat >&2 <<'EOF'
usage: scripts/pavbot_commit_and_push_outputs.sh research/<topic>

Publishes one Pavbot automation output set by committing only:
  - the selected research/<topic>/ tree
  - public/pavbot-manifest.json

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
    printf 'Allowed paths are %s/ and public/pavbot-manifest.json.\n' "$topic_path" >&2
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
  [[ "$path" == "$topic_path" || "$path" == "$topic_path"/* || "$path" == "public/pavbot-manifest.json" ]]
}

if (($# != 1)); then
  usage
  exit 2
fi

topic_path="${1%/}"
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

git add "$topic_path" public/pavbot-manifest.json

if git diff --cached --quiet; then
  printf 'no publishable changes for %s\n' "$topic_path"
  exit 0
fi

require_staged_scope

topic_slug="${topic_path#research/}"
git commit -m "chore(pavbot): publish ${topic_slug} automation outputs" >/dev/null
git push origin "HEAD:$target_branch" >/dev/null

printf 'pushed pavbot outputs for %s to origin/%s\n' "$topic_path" "$target_branch"
