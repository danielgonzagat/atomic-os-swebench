#!/usr/bin/env bash
set -euo pipefail

HERE="/Users/danielpenin/atomic-os-swebench/core/agent/atomic-full-ab/local-loop"
cd "$HERE"

ADAPTER="$HERE/frontier_atomic_agent_cmd.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

selftest="$($ADAPTER --selftest)"
grep -q '^metric=frontier_atomic_agent_cmd$' <<<"$selftest"
grep -q '^metric_claim=false$' <<<"$selftest"
grep -q '^requires_frontier_env=true$' <<<"$selftest"
grep -q '^requires_deepseek_api_key=true$' <<<"$selftest"
grep -q '^uses_local_atomic_agent=true$' <<<"$selftest"
grep -q '^writes_final_diff=true$' <<<"$selftest"
grep -q '^default_gate=NONE$' <<<"$selftest"
grep -q '^local_agent_path=' <<<"$selftest"

if "$ADAPTER" >"$tmp/missing.out" 2>"$tmp/missing.err"; then
  echo "expected missing ATOMIC_FRONTIER_WORKDIR to be rejected" >&2
  exit 1
fi
grep -q 'ATOMIC_FRONTIER_WORKDIR is required' "$tmp/missing.err"

workdir="$tmp/workdir"
mkdir -p "$workdir"
git -C "$workdir" init -q
git -C "$workdir" config user.email test@example.invalid
git -C "$workdir" config user.name test
printf 'base\n' >"$workdir/file.txt"
git -C "$workdir" add file.txt
git -C "$workdir" commit -q -m base
printf 'changed\n' >"$workdir/file.txt"

taskroot="$tmp/tasks"
mkdir -p "$taskroot/pro__task-a"
printf '# SWE-bench-Pro: pro__task-a\n\nIssue text\n' >"$taskroot/pro__task-a/PROBLEM.md"

fake_agent="$tmp/fake_local_atomic_agent.py"
cat >"$fake_agent" <<'PYFAKE'
#!/usr/bin/env python3
import argparse
import json
import subprocess
from pathlib import Path
ap = argparse.ArgumentParser()
ap.add_argument('--workdir', required=True)
ap.add_argument('--task', required=True)
ap.add_argument('--gate', required=True)
ap.add_argument('--out', required=True)
ap.add_argument('--max-steps', required=True)
args = ap.parse_args()
assert args.gate == 'NONE'
assert Path(args.task).name == 'PROBLEM.md'
diff = subprocess.run(['git', 'diff', 'HEAD'], cwd=args.workdir, text=True, capture_output=True, check=True).stdout
Path(args.out).write_text(json.dumps({'final_diff': diff, 'gate_pass': False, 'edits_applied': 1, 'source': 'fake'}))
PYFAKE
chmod +x "$fake_agent"

out="$tmp/frontier-agent-output.json"
ATOMIC_FRONTIER_WORKDIR="$workdir" \
ATOMIC_FRONTIER_TASK="pro__task-a" \
ATOMIC_FRONTIER_TASK_ROOT="$taskroot" \
ATOMIC_FRONTIER_OUT="$out" \
ATOMIC_FRONTIER_LOCAL_AGENT="$fake_agent" \
ATOMIC_FRONTIER_MODEL="frontier-teacher" \
DEEPSEEK_API_KEY="dummy" \
  "$ADAPTER"

python3 - "$out" <<'PYASSERT'
import json
import sys
payload = json.load(open(sys.argv[1], encoding='utf-8'))
assert payload['frontier_agent_adapter'] is True
assert payload['frontier_instance_id'] == 'pro__task-a'
assert payload['frontier_model'] == 'frontier-teacher'
assert payload['frontier_gate'] == 'NONE'
assert isinstance(payload['final_diff'], str) and 'diff --git' in payload['final_diff']
assert payload['source_result']['source'] == 'fake'
PYASSERT

echo "Frontier atomic agent command contract ok"
