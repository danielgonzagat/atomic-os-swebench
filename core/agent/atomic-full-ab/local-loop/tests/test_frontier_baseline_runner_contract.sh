#!/usr/bin/env bash
set -euo pipefail

HERE="/Users/danielpenin/atomic-os-swebench/core/agent/atomic-full-ab/local-loop"
cd "$HERE"

RUNNER="$HERE/run_frontier_baseline.sh"
FREEZER="$HERE/freeze_frontier_baseline.py"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

selftest="$($RUNNER --selftest pro__task-a pro__task-b)"
grep -q '^metric=frontier_baseline_receipt$' <<<"$selftest"
grep -q '^metric_claim=false$' <<<"$selftest"
grep -q '^benchmark_suite=swe_bench_pro$' <<<"$selftest"
grep -q '^benchmark_dataset_name=ScaleAI/SWE-bench_Pro$' <<<"$selftest"
grep -q '^official_benchmark=true$' <<<"$selftest"
grep -q '^requires_frontier_agent_cmd=false$' <<<"$selftest"
grep -q '^default_frontier_agent_cmd=' <<<"$selftest"
grep -q '^requires_model_credentials=true$' <<<"$selftest"
grep -q '^credential_source=env$' <<<"$selftest"
grep -q '^credential_file_allowed=false$' <<<"$selftest"
grep -q '^requires_official_scorer=true$' <<<"$selftest"
grep -q '^freezer_path=' <<<"$selftest"
grep -q '^task_provenance_enforced=true$' <<<"$selftest"
grep -q '^task_provenance_ok=false$' <<<"$selftest"
grep -q '^task_provenance_sha256=$' <<<"$selftest"
grep -q '^suite_preflight_enforced=true$' <<<"$selftest"
grep -q '^score_timeout_seconds=1200$' <<<"$selftest"
grep -q '^sample_timeout_seconds=3600$' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_path' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_evidence_receipt_ok' <<<"$selftest"

mkdir -p "$tmp/tasks/SWE-pro__layout-a" "$tmp/suite/pro__layout-a/pristine"
git -C "$tmp/suite/pro__layout-a/pristine" init -q
git -C "$tmp/suite/pro__layout-a/pristine" config user.email atomic@example.invalid
git -C "$tmp/suite/pro__layout-a/pristine" config user.name Atomic
printf 'seed\n' >"$tmp/suite/pro__layout-a/pristine/README.md"
git -C "$tmp/suite/pro__layout-a/pristine" add README.md
git -C "$tmp/suite/pro__layout-a/pristine" commit -q -m seed
layout_base="$(git -C "$tmp/suite/pro__layout-a/pristine" rev-parse HEAD)"
cat >"$tmp/tasks/SWE-pro__layout-a/PROBLEM.md" <<'MD'
# SWE-bench-Pro: pro__layout-a

Issue text
MD
cat >"$tmp/tasks/SWE-pro__layout-a/meta.json" <<JSON
{
  "base_commit": "$layout_base",
  "benchmark_label": "SWE-bench-Pro",
  "dataset_name": "ScaleAI/SWE-bench_Pro",
  "instance_id": "pro__layout-a"
}
JSON
layout_selftest="$(ATOMIC_FRONTIER_TASK_ROOT="$tmp/tasks" ATOMIC_FRONTIER_SUITE_ROOT="$tmp/suite" "$RUNNER" --selftest pro__layout-a)"
grep -q '^task_layout_ok=true$' <<<"$layout_selftest"
grep -q '^task_provenance_ok=true$' <<<"$layout_selftest"
grep -q '^suite_pristine_layout_ok=true$' <<<"$layout_selftest"
layout_provenance_sha="$(awk -F= '/^task_provenance_sha256=/{print $2}' <<<"$layout_selftest")"
[[ "$layout_provenance_sha" =~ ^[0-9a-f]{64}$ ]] || {
  echo "expected valid task provenance sha256, got: $layout_provenance_sha" >&2
  exit 1
}
printf '\nChanged issue text\n' >>"$tmp/tasks/SWE-pro__layout-a/PROBLEM.md"
changed_layout_selftest="$(ATOMIC_FRONTIER_TASK_ROOT="$tmp/tasks" ATOMIC_FRONTIER_SUITE_ROOT="$tmp/suite" "$RUNNER" --selftest pro__layout-a)"
grep -q '^task_provenance_ok=true$' <<<"$changed_layout_selftest"
changed_layout_provenance_sha="$(awk -F= '/^task_provenance_sha256=/{print $2}' <<<"$changed_layout_selftest")"
[[ "$changed_layout_provenance_sha" =~ ^[0-9a-f]{64}$ ]] || {
  echo "expected changed task provenance sha256, got: $changed_layout_provenance_sha" >&2
  exit 1
}
if [[ "$changed_layout_provenance_sha" == "$layout_provenance_sha" ]]; then
  echo "expected task provenance sha256 to change when task evidence content changes" >&2
  exit 1
fi

if "$RUNNER" FRONTIERTEST "$tmp/frontier.json" pro__task-a >"$tmp/no_creds.out" 2>"$tmp/no_creds.err"; then
  echo "expected missing DEEPSEEK_API_KEY to be rejected for the default frontier adapter" >&2
  exit 1
fi
grep -q 'DEEPSEEK_API_KEY is required' "$tmp/no_creds.err"

verified_dataset="$(ATOMIC_FRONTIER_DATASET_NAME=princeton-nlp/SWE-bench_Verified "$RUNNER" --selftest pro__task-a)"
grep -q '^official_benchmark=false$' <<<"$verified_dataset"
if ATOMIC_FRONTIER_DATASET_NAME=princeton-nlp/SWE-bench_Verified ATOMIC_FRONTIER_AGENT_CMD='unused' "$RUNNER" FRONTIERTEST "$tmp/frontier.json" pro__task-a >"$tmp/verified.out" 2>"$tmp/verified.err"; then
  echo "expected non-Pro frontier baseline run to be rejected" >&2
  exit 1
fi
grep -q 'official SWE-Bench Pro dataset required' "$tmp/verified.err"

grep -q 'freeze_frontier_baseline.py' "$RUNNER"
grep -q 'swebench.harness.run_evaluation' "$RUNNER"
grep -q 'ATOMIC_FRONTIER_AGENT_CMD' "$RUNNER"
grep -q 'metric_claim=false' "$RUNNER"
grep -q 'frontier_baseline_evidence_receipt_ok' "$RUNNER"
if grep -q '/tmp/.atomic_creds.sh' "$RUNNER"; then
  echo "frontier baseline runner must not source credential files; use env only" >&2
  exit 1
fi
test -x "$RUNNER"
test -f "$FREEZER"

echo "Frontier baseline runner contract ok"
