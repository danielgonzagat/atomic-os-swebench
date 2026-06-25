#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_AGENT="${ATOMIC_FRONTIER_LOCAL_AGENT:-$HERE/local_atomic_agent.py}"
TASKROOT="${ATOMIC_FRONTIER_TASK_ROOT:-$HERE/tasks}"
GATE="${ATOMIC_FRONTIER_GATE:-NONE}"
MAX_STEPS="${ATOMIC_FRONTIER_MAX_STEPS:-60}"
MODEL="${ATOMIC_FRONTIER_MODEL:-frontier-teacher}"
PYTHON_BIN="${ATOMIC_FRONTIER_AGENT_PYTHON:-${PYTHON:-python3}}"

emit_selftest() {
  cat <<EOF
metric=frontier_atomic_agent_cmd
metric_claim=false
requires_frontier_env=true
requires_deepseek_api_key=true
uses_local_atomic_agent=true
writes_final_diff=true
default_gate=NONE
local_agent_path=$LOCAL_AGENT
EOF
}

require_env() {
  local name="$1"
  local value="${!name:-}"
  if [[ -z "$value" ]]; then
    echo "$name is required" >&2
    exit 2
  fi
}

resolve_task_file() {
  local task_ref="$1"
  local candidate
  if [[ -n "${ATOMIC_FRONTIER_TASK_FILE:-}" ]]; then
    candidate="$ATOMIC_FRONTIER_TASK_FILE"
  elif [[ -f "$task_ref" ]]; then
    candidate="$task_ref"
  elif [[ -f "$TASKROOT/$task_ref/PROBLEM.md" ]]; then
    candidate="$TASKROOT/$task_ref/PROBLEM.md"
  elif [[ -f "$TASKROOT/SWE-$task_ref/PROBLEM.md" ]]; then
    candidate="$TASKROOT/SWE-$task_ref/PROBLEM.md"
  else
    echo "PROBLEM.md for ATOMIC_FRONTIER_TASK=$task_ref was not found under $TASKROOT" >&2
    exit 2
  fi
  if [[ ! -f "$candidate" ]]; then
    echo "frontier task file does not exist: $candidate" >&2
    exit 2
  fi
  printf '%s\n' "$candidate"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'USAGE'
Usage:
  frontier_atomic_agent_cmd.sh --selftest
  frontier_atomic_agent_cmd.sh

The runtime form is intended as ATOMIC_FRONTIER_AGENT_CMD for run_frontier_baseline.sh.
Required env: ATOMIC_FRONTIER_WORKDIR, ATOMIC_FRONTIER_TASK, ATOMIC_FRONTIER_OUT,
DEEPSEEK_API_KEY. Optional env: ATOMIC_FRONTIER_TASK_ROOT, ATOMIC_FRONTIER_TASK_FILE,
ATOMIC_FRONTIER_LOCAL_AGENT, ATOMIC_FRONTIER_GATE, ATOMIC_FRONTIER_MAX_STEPS.
USAGE
  exit 0
fi

if [[ "${1:-}" == "--selftest" ]]; then
  emit_selftest
  exit 0
fi

require_env ATOMIC_FRONTIER_WORKDIR
require_env ATOMIC_FRONTIER_TASK
require_env ATOMIC_FRONTIER_OUT
require_env DEEPSEEK_API_KEY

if [[ ! -d "$ATOMIC_FRONTIER_WORKDIR/.git" ]]; then
  echo "ATOMIC_FRONTIER_WORKDIR must be a git checkout: $ATOMIC_FRONTIER_WORKDIR" >&2
  exit 2
fi
if [[ ! -f "$LOCAL_AGENT" ]]; then
  echo "local atomic agent is required: $LOCAL_AGENT" >&2
  exit 2
fi

task_file="$(resolve_task_file "$ATOMIC_FRONTIER_TASK")"
tmp_result="$(mktemp "${ATOMIC_FRONTIER_OUT}.local-agent.XXXXXX")"
trap 'rm -f "$tmp_result"' EXIT

"$PYTHON_BIN" "$LOCAL_AGENT" \
  --workdir "$ATOMIC_FRONTIER_WORKDIR" \
  --task "$task_file" \
  --gate "$GATE" \
  --out "$tmp_result" \
  --max-steps "$MAX_STEPS"

"$PYTHON_BIN" - "$tmp_result" "$ATOMIC_FRONTIER_OUT" "$ATOMIC_FRONTIER_TASK" "$task_file" "$MODEL" "$GATE" <<'PYWRAP'
import json
import sys
from pathlib import Path

source_path, out_path, instance_id, task_file, model, gate = sys.argv[1:7]
try:
    source = json.load(open(source_path, encoding="utf-8"))
except Exception as exc:
    print(f"local atomic agent output is not valid JSON: {exc}", file=sys.stderr)
    sys.exit(1)
final_diff = source.get("final_diff")
if not isinstance(final_diff, str):
    print("local atomic agent output must contain string field final_diff", file=sys.stderr)
    sys.exit(1)
payload = {
    "frontier_agent_adapter": True,
    "frontier_instance_id": instance_id,
    "frontier_model": model,
    "frontier_gate": gate,
    "frontier_task_file": task_file,
    "final_diff": final_diff,
    "source_result": source,
}
out = Path(out_path)
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PYWRAP
