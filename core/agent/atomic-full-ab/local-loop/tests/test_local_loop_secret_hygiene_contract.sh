#!/usr/bin/env bash
set -euo pipefail

HERE="/Users/danielpenin/atomic-os-swebench/core/agent/atomic-full-ab/local-loop"
cd "$HERE"

patterns_file="$(mktemp)"
matches_file="$(mktemp)"
trap 'rm -f "$patterns_file" "$matches_file"' EXIT

{
  printf '%s\n' '/tmp/\.atomic_creds\.sh'
  printf '%s\n' 'source[[:space:]]+/tmp'
  printf '%s\n' 'source[[:space:]].*cred'
} >"$patterns_file"

if rg -n -f "$patterns_file" \
  --glob '!tests/**' \
  --glob '!evidence/**' \
  --glob '!LEDGER.md' \
  --glob '!*.log' \
  --glob '!*.jsonl' \
  . >"$matches_file"; then
  echo "local-loop runtime files must not source credential files; use env only" >&2
  cat "$matches_file" >&2
  exit 1
fi

echo "Local loop secret hygiene contract ok"
