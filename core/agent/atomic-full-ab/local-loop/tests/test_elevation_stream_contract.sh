#!/usr/bin/env bash
set -euo pipefail

HERE="/Users/danielpenin/atomic-os-swebench/core/agent/atomic-full-ab/local-loop"
cd "$HERE"

SCRIPT="$HERE/run_elevation_stream.sh"
WEIGHTS="$HERE/.corpus/weights.jsonl"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

write_frontier_baseline(){
  local out="$1"; shift
  python3 - "$out" "$tmp" "$@" <<'PY'
import hashlib, json, os, re, sys
from pathlib import Path

out = Path(sys.argv[1])
tmp = Path(sys.argv[2])
specs = sys.argv[3:]
evidence_dir = tmp / "frontier_receipts"
evidence_dir.mkdir(parents=True, exist_ok=True)
ids = []
instances = {}
evidence = {}
for spec in specs:
    iid, raw_resolved = spec.rsplit(":", 1)
    resolved = raw_resolved == "true"
    ids.append(iid)
    instances[iid] = {"resolved": resolved, "tool_uses": 7 if resolved else 5}
    safe = re.sub(r"[^A-Za-z0-9_.-]", "_", iid)
    pred = evidence_dir / f"pred_{safe}.jsonl"
    score = evidence_dir / f"score_{safe}.log"
    pred.write_text(json.dumps({"instance_id": iid, "model_name_or_path": "frontier-teacher", "model_patch": ""}) + "\n", encoding="utf-8")
    score.write_text(f"Official SWE-bench harness\nInstances resolved: {1 if resolved else 0}\n", encoding="utf-8")
    evidence[iid] = {
        "prediction_jsonl": os.path.relpath(pred, out.parent),
        "prediction_sha256": hashlib.sha256(pred.read_bytes()).hexdigest(),
        "score_log": os.path.relpath(score, out.parent),
        "score_log_sha256": hashlib.sha256(score.read_bytes()).hexdigest(),
        "resolved": resolved,
    }
data = {
    "model": "frontier-teacher",
    "teacher_model": "frontier-teacher",
    "baseline_role": "frontier",
    "frontier_baseline": True,
    "frozen": True,
    "official_docker": True,
    "scoring_harness": "swebench.harness.run_evaluation",
    "benchmark_suite": "swe_bench_pro",
    "dataset_name": "ScaleAI/SWE-bench_Pro",
    "dataset_split": "test",
    "benchmark_label": "SWE-bench-Pro",
    "task_ids": ids,
    "atomic": True,
    "teach_task_ids": ["django__django-0001"],
    "instances": instances,
    "frontier_receipt": {
        "format": "swebench_pro_frontier_baseline_v1",
        "frozen": True,
        "official_docker": True,
        "scoring_harness": "swebench.harness.run_evaluation",
        "benchmark_suite": "swe_bench_pro",
        "dataset_name": "ScaleAI/SWE-bench_Pro",
        "dataset_split": "test",
        "benchmark_label": "SWE-bench-Pro",
        "task_ids": ids,
        "evidence": evidence,
    },
}
out.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

write_frontier_baseline "$tmp/native_baseline.json" psf__requests-1921:true pytest-dev__pytest-5262:false

selftest="$("$SCRIPT" --selftest "$WEIGHTS" "$tmp/native_baseline.json" psf__requests-1921 pytest-dev__pytest-5262)"

grep -q '^metric=elevation$' <<<"$selftest"
grep -q '^benchmark_suite=swe_bench_pro$' <<<"$selftest"
grep -q '^benchmark_dataset_name=ScaleAI/SWE-bench_Pro$' <<<"$selftest"
grep -q '^official_benchmark=true$' <<<"$selftest"
grep -q '^task_root=' <<<"$selftest"
grep -q '^suite_root=' <<<"$selftest"
grep -q '^task_provenance_enforced=true$' <<<"$selftest"
grep -q '^suite_preflight_enforced=true$' <<<"$selftest"
grep -q '^canonical_act=true$' <<<"$selftest"
grep -q '^native_baseline_resolved_fields=true$' <<<"$selftest"
grep -q '^distinct_tasks=true$' <<<"$selftest"
grep -q '^student_model=deepseek-v4-pro$' <<<"$selftest"
grep -q '^teacher_model=frontier-teacher$' <<<"$selftest"
grep -q '^teacher_atomic=true$' <<<"$selftest"
grep -q '^frontier_baseline_provenance_ok=true$' <<<"$selftest"
grep -q '^frontier_baseline_frozen=true$' <<<"$selftest"
grep -q '^frontier_baseline_official_docker=true$' <<<"$selftest"
grep -q '^frontier_baseline_paired_tasks=true$' <<<"$selftest"
grep -q '^frontier_baseline_evidence_receipt_ok=true$' <<<"$selftest"
grep -q '^held_out=true$' <<<"$selftest"
grep -q '^anti_replay=true$' <<<"$selftest"
grep -q '^substrate_mode=accumulated_canonical_act$' <<<"$selftest"
grep -q '^control_arm=deepseek_v4_pro_without_substrate$' <<<"$selftest"
grep -q '^substrate_arm=deepseek_v4_pro_with_substrate$' <<<"$selftest"
grep -q '^resume_supported=true$' <<<"$selftest"
grep -q '^swebench_import_timeout_seconds=20$' <<<"$selftest"
grep -q 'summary_fields=.*atomic_base_resolved' <<<"$selftest"
grep -q 'summary_fields=.*atomic_substrate_resolved' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_resolved' <<<"$selftest"
grep -q 'summary_fields=.*benchmark_suite' <<<"$selftest"
grep -q 'summary_fields=.*benchmark_dataset_name' <<<"$selftest"
grep -q 'summary_fields=.*official_benchmark' <<<"$selftest"
grep -q 'summary_fields=.*task_provenance_ok' <<<"$selftest"
grep -q 'summary_fields=.*deepseek_control_resolved' <<<"$selftest"
grep -q 'summary_fields=.*elevation_vs_frontier' <<<"$selftest"
grep -q 'summary_fields=.*elevation_vs_deepseek_control' <<<"$selftest"
grep -q 'summary_fields=.*teacher_atomic' <<<"$selftest"
grep -q 'summary_fields=.*teacher_model' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_provenance_ok' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_evidence_receipt_ok' <<<"$selftest"
grep -q 'summary_fields=.*anti_replay' <<<"$selftest"
grep -q 'summary_fields=.*elevation_vs_atomic_base' <<<"$selftest"
grep -q 'summary_fields=.*elevation_vs_native' <<<"$selftest"
grep -q 'summary_fields=.*accumulation_index' <<<"$selftest"
grep -q 'summary_fields=.*weights_snapshot_path' <<<"$selftest"
grep -q 'summary_fields=.*weights_sha256_initial' <<<"$selftest"
grep -q 'summary_fields=.*weights_sha256_final' <<<"$selftest"
grep -q 'summary_fields=.*reused_samples' <<<"$selftest"
grep -q 'summary_fields=.*rerun_timeout_samples' <<<"$selftest"
grep -q 'summary_fields=.*elevation_valid' <<<"$selftest"

cat >"$tmp/weights.jsonl" <<'JSONL'
{"class":"FAKE","trigger":"x","strategy":"not an ACT"}
JSONL
if "$SCRIPT" --selftest "$tmp/weights.jsonl" "$tmp/native_baseline.json" psf__requests-1921 >/tmp/elevation_fake.out 2>/tmp/elevation_fake.err; then
  echo "noncanonical non-ACT weights unexpectedly accepted" >&2
  exit 1
fi
grep -q 'noncanonical or non-ACT substrate bank rejected' /tmp/elevation_fake.err

cat >"$tmp/native_no_resolved.json" <<'JSON'
{"instances":{"psf__requests-1921":{"tool_uses":7}}}
JSON
missing_resolved="$("$SCRIPT" --selftest "$WEIGHTS" "$tmp/native_no_resolved.json" psf__requests-1921)"
grep -q '^native_baseline_resolved_fields=false$' <<<"$missing_resolved"
grep -q '^elevation_valid_if_run=false$' <<<"$missing_resolved"

cat >"$tmp/native_no_atomic.json" <<'JSON'
{"model":"legacy-native","instances":{"psf__requests-1921":{"resolved":true}}}
JSON
no_atomic="$("$SCRIPT" --selftest "$WEIGHTS" "$tmp/native_no_atomic.json" psf__requests-1921)"
grep -q '^teacher_atomic=false$' <<<"$no_atomic"
grep -q '^elevation_valid_if_run=false$' <<<"$no_atomic"

cat >"$tmp/native_no_frontier.json" <<'JSON'
{
  "model": "legacy-frontier-claim",
  "atomic": true,
  "instances": {
    "psf__requests-1921": {"resolved": true}
  }
}
JSON
no_frontier="$("$SCRIPT" --selftest "$WEIGHTS" "$tmp/native_no_frontier.json" psf__requests-1921)"
grep -q '^frontier_baseline_provenance_ok=false$' <<<"$no_frontier"
grep -q '^elevation_valid_if_run=false$' <<<"$no_frontier"
if "$SCRIPT" ELEVTEST "$tmp/native_no_frontier.json" "$WEIGHTS" psf__requests-1921 >"$tmp/no_frontier.out" 2>"$tmp/no_frontier.err"; then
  echo "expected baseline without paired Pro frontier metadata to be rejected" >&2
  exit 1
fi
grep -q 'paired official SWE-Bench Pro frontier baseline required' "$tmp/no_frontier.err"

cat >"$tmp/native_no_receipt.json" <<'JSON'
{
  "model": "frontier-teacher",
  "baseline_role": "frontier",
  "frontier_baseline": true,
  "frozen": true,
  "official_docker": true,
  "scoring_harness": "swebench.harness.run_evaluation",
  "benchmark_suite": "swe_bench_pro",
  "dataset_name": "ScaleAI/SWE-bench_Pro",
  "dataset_split": "test",
  "benchmark_label": "SWE-bench-Pro",
  "task_ids": ["psf__requests-1921"],
  "atomic": true,
  "teach_task_ids": ["django__django-0001"],
  "instances": {
    "psf__requests-1921": {"resolved": true}
  }
}
JSON
no_receipt="$("$SCRIPT" --selftest "$WEIGHTS" "$tmp/native_no_receipt.json" psf__requests-1921)"
grep -q '^frontier_baseline_paired_tasks=true$' <<<"$no_receipt"
grep -q '^frontier_baseline_evidence_receipt_ok=false$' <<<"$no_receipt"
grep -q '^frontier_baseline_provenance_ok=false$' <<<"$no_receipt"
grep -q '^elevation_valid_if_run=false$' <<<"$no_receipt"
if "$SCRIPT" ELEVTEST "$tmp/native_no_receipt.json" "$WEIGHTS" psf__requests-1921 >"$tmp/no_receipt.out" 2>"$tmp/no_receipt.err"; then
  echo "expected baseline without scorer evidence receipt to be rejected" >&2
  exit 1
fi
grep -q 'evidence_receipt=false' "$tmp/no_receipt.err"

verified_dataset="$(ATOMIC_ELEVATION_DATASET_NAME=princeton-nlp/SWE-bench_Verified "$SCRIPT" --selftest "$WEIGHTS" "$tmp/native_baseline.json" psf__requests-1921)"
grep -q '^benchmark_dataset_name=princeton-nlp/SWE-bench_Verified$' <<<"$verified_dataset"
grep -q '^official_benchmark=false$' <<<"$verified_dataset"
grep -q '^elevation_valid_if_run=false$' <<<"$verified_dataset"
if ATOMIC_ELEVATION_DATASET_NAME=princeton-nlp/SWE-bench_Verified "$SCRIPT" ELEVTEST "$tmp/native_baseline.json" "$WEIGHTS" psf__requests-1921 >"$tmp/verified_run.out" 2>"$tmp/verified_run.err"; then
  echo "expected Verified dataset to be rejected as non-Pro Elevação" >&2
  exit 1
fi
grep -q 'official SWE-Bench Pro dataset required' "$tmp/verified_run.err"

write_frontier_baseline "$tmp/native_baseline_one.json" psf__requests-1921:true

mkdir -p "$tmp/tasks/SWE-psf__requests-1921"
cat >"$tmp/tasks/SWE-psf__requests-1921/PROBLEM.md" <<'MD'
# SWE-bench-Verified: psf__requests-1921

repo: psf/requests  base_commit: abc
MD
cat >"$tmp/tasks/SWE-psf__requests-1921/meta.json" <<'JSON'
{"instance_id":"psf__requests-1921","dataset_name":"princeton-nlp/SWE-bench_Verified"}
JSON
if ATOMIC_ELEVATION_TASK_ROOT="$tmp/tasks" ATOMIC_ELEVATION_IMPORT_TIMEOUT_SECONDS=1 "$SCRIPT" ELEVTEST "$tmp/native_baseline_one.json" "$WEIGHTS" psf__requests-1921 >"$tmp/verified_task.out" 2>"$tmp/verified_task.err"; then
  echo "expected Verified task directory to be rejected as non-Pro Elevação" >&2
  exit 1
fi
grep -q 'official SWE-Bench Pro task provenance required' "$tmp/verified_task.err"
grep -q 'SWE-bench-Verified' "$tmp/verified_task.err"

write_frontier_baseline "$tmp/native_baseline_preflight.json" pro__suite-preflight:true
mkdir -p "$tmp/tasks/SWE-pro__suite-preflight"
cat >"$tmp/tasks/SWE-pro__suite-preflight/PROBLEM.md" <<'MD'
# SWE-bench-Pro: pro__suite-preflight

repo: owner/repo  base_commit: abc
dataset: ScaleAI/SWE-bench_Pro  split: test
MD
cat >"$tmp/tasks/SWE-pro__suite-preflight/meta.json" <<'JSON'
{"instance_id":"pro__suite-preflight","repo":"owner/repo","base_commit":"abc","dataset_name":"ScaleAI/SWE-bench_Pro","benchmark_label":"SWE-bench-Pro"}
JSON
if ATOMIC_ELEVATION_TASK_ROOT="$tmp/tasks" ATOMIC_ELEVATION_SUITE_ROOT="$tmp/suite" ATOMIC_ELEVATION_IMPORT_TIMEOUT_SECONDS=1 "$SCRIPT" ELEVTEST "$tmp/native_baseline_preflight.json" "$WEIGHTS" pro__suite-preflight >"$tmp/missing_suite.out" 2>"$tmp/missing_suite.err"; then
  echo "expected missing Pro pristine checkout to be rejected before run" >&2
  exit 1
fi
grep -q 'official SWE-Bench Pro suite checkout required' "$tmp/missing_suite.err"
grep -q "$tmp/suite/pro__suite-preflight/pristine" "$tmp/missing_suite.err"

mkdir -p "$tmp/suite/pro__suite-preflight/pristine"
git -C "$tmp/suite/pro__suite-preflight/pristine" init -q
touch "$tmp/suite/pro__suite-preflight/pristine/file.txt"
git -C "$tmp/suite/pro__suite-preflight/pristine" add file.txt
git -C "$tmp/suite/pro__suite-preflight/pristine" -c user.email=atomic@example.com -c user.name=Atomic commit -q -m init
if ATOMIC_ELEVATION_TASK_ROOT="$tmp/tasks" ATOMIC_ELEVATION_SUITE_ROOT="$tmp/suite" ATOMIC_ELEVATION_IMPORT_TIMEOUT_SECONDS=1 "$SCRIPT" ELEVTEST "$tmp/native_baseline_preflight.json" "$WEIGHTS" pro__suite-preflight >"$tmp/wrong_base.out" 2>"$tmp/wrong_base.err"; then
  echo "expected Pro pristine checkout at the wrong base commit to be rejected before run" >&2
  exit 1
fi
grep -q 'official SWE-Bench Pro pristine checkout base mismatch' "$tmp/wrong_base.err"
grep -q 'expected_base=abc' "$tmp/wrong_base.err"

grep -q 'ATOMIC_ELEVATION_TASK_ROOT' "$SCRIPT"
grep -q 'task_provenance_ok' "$SCRIPT"
grep -q 'suite_preflight_ok' "$SCRIPT"
grep -q 'validate_suite_preflight' "$SCRIPT"
grep -q 'frontier_baseline_provenance_ok' "$SCRIPT"
grep -q 'paired official SWE-Bench Pro frontier baseline required' "$SCRIPT"
grep -q 'unset ATOMIC_WEIGHTS_FILE' "$SCRIPT"
grep -q 'export ATOMIC_WEIGHTS_FILE="$WEIGHTS_SNAPSHOT"' "$SCRIPT"
grep -q 'substrate_weights.jsonl' "$SCRIPT"
grep -q 'substrate_weights.meta.json' "$SCRIPT"
grep -q 'cannot resume elevation run without substrate_weights.jsonl snapshot' "$SCRIPT"
grep -q 'ATOMIC_ELEVATION_IMPORT_TIMEOUT_SECONDS' "$SCRIPT"
grep -q 'ATOMIC_ELEVATION_RESUME' "$SCRIPT"
grep -q 'ATOMIC_ELEVATION_RERUN_TIMEOUTS' "$SCRIPT"
grep -q 'reused=1' "$SCRIPT"
grep -q 'swebench.harness.run_evaluation' "$SCRIPT"
grep -q '"weights_snapshot_path"' "$SCRIPT"
grep -q '"weights_sha256_initial"' "$SCRIPT"
grep -q '"weights_sha256_final"' "$SCRIPT"
grep -q '"frontier_baseline_resolved"' "$SCRIPT"
grep -q '"deepseek_control_resolved"' "$SCRIPT"
grep -q '"elevation_vs_frontier"' "$SCRIPT"
grep -q '"elevation_vs_deepseek_control"' "$SCRIPT"
grep -q '"anti_replay"' "$SCRIPT"
grep -q '"elevation_valid"' "$SCRIPT"

echo "Elevation stream contract ok"
