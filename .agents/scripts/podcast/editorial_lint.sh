#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  printf 'usage: %s SCRIPT_MD [SOURCES_MD]\n' "$0" >&2
  exit 64
fi

script_file=$1
sources_file=${2:-}

if [[ ! -f "$script_file" ]]; then
  printf 'script file not found: %s\n' "$script_file" >&2
  exit 66
fi

if [[ ! -s "$script_file" ]]; then
  printf 'script file is empty: %s\n' "$script_file" >&2
  exit 65
fi

if ! LC_ALL=en_US.UTF-8 grep -Eq '[ąćęłńóśźżĄĆĘŁŃÓŚŹŻ]' "$script_file"; then
  printf 'script must contain Polish diacritics: %s\n' "$script_file" >&2
  exit 65
fi

if grep -Eq 'https?://' "$script_file"; then
  printf 'script must not contain raw URLs; keep URLs in sources.md: %s\n' "$script_file" >&2
  exit 65
fi

if grep -Eq 'TODO|TBD|FIXME' "$script_file"; then
  printf 'script contains unfinished editorial marker: %s\n' "$script_file" >&2
  exit 65
fi

word_count=$(awk 'BEGIN { count = 0 } { count += NF } END { print count }' "$script_file")

if [[ -n "$sources_file" ]]; then
  if [[ ! -f "$sources_file" ]]; then
    printf 'sources file not found: %s\n' "$sources_file" >&2
    exit 66
  fi
  if ! grep -Eq 'https?://' "$sources_file"; then
    printf 'sources.md must contain at least one source link: %s\n' "$sources_file" >&2
    exit 65
  fi
fi

printf 'editorial lint passed: %s (%s words)\n' "$script_file" "$word_count"
