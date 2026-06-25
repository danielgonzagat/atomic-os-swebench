#!/usr/bin/env bash
set -euo pipefail

REPO="/Users/danielpenin/atomic-os-swebench"
cd "$REPO"

patterns_file="$(mktemp)"
matches_file="$(mktemp)"
trap 'rm -f "$patterns_file" "$matches_file"' EXIT

{
  printf '%s\n' '/tmp/\.atomic_creds\.sh'
  printf '%s\n' '/tmp/ds\.env'
  printf '%s\n' 'source[[:space:]]+/tmp'
  printf '%s\n' '^[[:space:]]*(set[[:space:]]+-a;[[:space:]]*)?source[[:space:]]+.*(cred|env)'
  printf '%s\n' 'MODAL_TOML=~/.modal.toml'
  printf '%s\n' 'modal token set'
} >"$patterns_file"

if rg -n -f "$patterns_file" core/agent core/atomic-edit \
  --glob '!**/tests/**' \
  --glob '!**/evidence/**' \
  --glob '!**/LEDGER.md' \
  --glob '!**/*.log' \
  --glob '!**/*.jsonl' \
  --glob '!**/node_modules/**' \
  --glob '!**/dist/**' >"$matches_file"; then
  echo "agent runtime files must use env-only credentials; credential files and modal token persistence are forbidden" >&2
  cat "$matches_file" >&2
  exit 1
fi

echo "Agent runtime secret hygiene contract ok"
