#!/usr/bin/env bash
set -euo pipefail

HERE="/Users/danielpenin/atomic-os-swebench/core/agent/atomic-full-ab/local-loop"
cd "$HERE"

RUNNER="$HERE/run_frontier_baseline.sh"
FREEZER="$HERE/freeze_frontier_baseline.py"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

empty_selftest="$($RUNNER --selftest 2>"$tmp/empty-selftest.err")"
grep -q '^metric=frontier_baseline_receipt$' <<<"$empty_selftest"
grep -q '^task_provenance_sha256=$' <<<"$empty_selftest"
test ! -s "$tmp/empty-selftest.err"

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
grep -q '^frontier_model=frontier-teacher$' <<<"$selftest"
grep -q '^freezer_path=' <<<"$selftest"
grep -q '^task_provenance_enforced=true$' <<<"$selftest"
grep -q '^task_provenance_ok=false$' <<<"$selftest"
grep -q '^task_provenance_sha256=$' <<<"$selftest"
grep -q '^suite_preflight_enforced=true$' <<<"$selftest"
grep -q '^score_timeout_seconds=1200$' <<<"$selftest"
grep -q '^sample_timeout_seconds=3600$' <<<"$selftest"
grep -q 'summary_fields=.*baseline_role' <<<"$selftest"
grep -q 'summary_fields=.*frozen' <<<"$selftest"
grep -q 'summary_fields=.*official_docker' <<<"$selftest"
grep -q 'summary_fields=.*benchmark_label' <<<"$selftest"
grep -q 'summary_fields=.*frontier_model' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_path' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_sha256' <<<"$selftest"
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
cat >"$tmp/tasks/SWE-pro__layout-a/PROBLEM.md" <<'MD'
# SWE-bench-Pro: pro__layout-a

Issue text
MD

cat >"$tmp/pred_layout.jsonl" <<'JSONL'
{"instance_id":"pro__layout-a","model_name_or_path":"frontier-teacher","model_patch":""}
JSONL
cat >"$tmp/score_layout.log" <<'LOG'
swebench.harness.run_evaluation
Official SWE-bench harness
Instances resolved: 0
LOG
frontier_baseline="$tmp/frontier-baseline.json"
python3 "$FREEZER" \
  --out "$frontier_baseline" \
  --model frontier-teacher \
  --teach-task-id teach__frontier-verify \
  --task pro__layout-a "$tmp/pred_layout.jsonl" "$tmp/score_layout.log" >/dev/null
frontier_baseline_sha="$(shasum -a 256 "$frontier_baseline" | awk '{print $1}')"
summary="$tmp/frontier-summary.json"
task_hash="$(python3 - <<'PY'
import hashlib
print(hashlib.sha256("pro__layout-a".encode()).hexdigest())
PY
)"
cat >"$summary" <<JSON
{
  "baseline_role": "frontier",
  "benchmark_dataset_name": "ScaleAI/SWE-bench_Pro",
  "benchmark_label": "SWE-bench-Pro",
  "benchmark_suite": "swe_bench_pro",
  "frontier_baseline_evidence_receipt_ok": true,
  "frontier_baseline_path": "$frontier_baseline",
  "frontier_baseline_sha256": "$frontier_baseline_sha",
  "frontier_model": "frontier-teacher",
  "frozen": true,
  "metric": "frontier_baseline_receipt",
  "metric_claim": false,
  "official_benchmark": true,
  "official_docker": true,
  "sample_failures": 0,
  "score_failures": 0,
  "suite_preflight_ok": true,
  "task_ids": ["pro__layout-a"],
  "task_ids_sha256": "$task_hash",
  "task_provenance_ok": true,
  "task_provenance_sha256": "$layout_provenance_sha"
}
JSON
verify_summary="$(ATOMIC_FRONTIER_TASK_ROOT="$tmp/tasks" ATOMIC_FRONTIER_SUITE_ROOT="$tmp/suite" "$RUNNER" --verify-summary "$summary")"
grep -q '^metric=frontier_baseline_summary_verification$' <<<"$verify_summary"
grep -q '^metric_claim=false$' <<<"$verify_summary"
grep -q "^frontier_summary_path=$summary$" <<<"$verify_summary"
grep -q '^frontier_summary_exists=true$' <<<"$verify_summary"
grep -q '^frontier_summary_schema_ok=true$' <<<"$verify_summary"
grep -q '^frontier_summary_matches_current=true$' <<<"$verify_summary"
grep -q '^frontier_summary_ok=true$' <<<"$verify_summary"
grep -q '^task_provenance_ok=true$' <<<"$verify_summary"
grep -q "^task_provenance_sha256=$layout_provenance_sha$" <<<"$verify_summary"
grep -q '^frontier_baseline_sha256_ok=true$' <<<"$verify_summary"
grep -q '^frontier_baseline_evidence_receipt_ok=true$' <<<"$verify_summary"
grep -q '^no_model_run=true$' <<<"$verify_summary"
grep -q '^no_scorer_run=true$' <<<"$verify_summary"

wrong_frontier_sha="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
sed "s/\"frontier_baseline_sha256\": \"[^\"]*\"/\"frontier_baseline_sha256\": \"$wrong_frontier_sha\"/" "$summary" >"$tmp/frontier-summary-tampered.json"
if ATOMIC_FRONTIER_TASK_ROOT="$tmp/tasks" ATOMIC_FRONTIER_SUITE_ROOT="$tmp/suite" "$RUNNER" --verify-summary "$tmp/frontier-summary-tampered.json" >"$tmp/frontier-summary-tampered.out" 2>"$tmp/frontier-summary-tampered.err"; then
  echo "expected tampered frontier summary receipt to fail" >&2
  exit 1
fi
grep -q '^frontier_summary_schema_ok=true$' "$tmp/frontier-summary-tampered.out"
grep -q '^frontier_summary_ok=false$' "$tmp/frontier-summary-tampered.out"
grep -q '^frontier_summary_matches_current=false$' "$tmp/frontier-summary-tampered.out"
grep -q '^frontier_baseline_sha256_ok=false$' "$tmp/frontier-summary-tampered.out"

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
