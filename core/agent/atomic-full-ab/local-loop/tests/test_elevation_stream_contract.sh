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

cherrypicked_selftest="$("$SCRIPT" --selftest "$WEIGHTS" "$tmp/native_baseline.json" psf__requests-1921 pytest-dev__pytest-5262)"
grep -q '^selection_receipt_ok=false$' <<<"$cherrypicked_selftest"
grep -q '^anti_cherry_pick=false$' <<<"$cherrypicked_selftest"
grep -q '^elevation_valid_if_run=false$' <<<"$cherrypicked_selftest"

cat >"$tmp/selection_manifest.json" <<'JSON'
{
  "anti_leakage": {
    "patch": "omitted",
    "problem_statement": "omitted",
    "test_patch": "omitted"
  },
  "benchmark_label": "SWE-bench-Pro",
  "benchmark_suite": "swe_bench_pro",
  "dataset_name": "ScaleAI/SWE-bench_Pro",
  "dataset_split": "test",
  "eligible_count": 731,
  "metric_claim": false,
  "official_benchmark": true,
  "purpose": "held_out_candidate_manifest_not_elevation_result",
  "rows": [
    {"instance_id": "psf__requests-1921", "selection_rank_sha256": "001"},
    {"instance_id": "pytest-dev__pytest-5262", "selection_rank_sha256": "002"}
  ],
  "selected_count": 2,
  "selected_task_ids": ["psf__requests-1921", "pytest-dev__pytest-5262"],
  "selection_method": "sha256(seed + NUL + instance_id) over official dataset rows; excludes teach task ids",
  "selection_seed": "contract-seed",
  "teach_task_ids": ["django__django-0001"],
  "total_count": 731
}
JSON

selftest="$(ATOMIC_ELEVATION_SELECTION_MANIFEST="$tmp/selection_manifest.json" "$SCRIPT" --selftest "$WEIGHTS" "$tmp/native_baseline.json" psf__requests-1921 pytest-dev__pytest-5262)"

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
grep -q '^frontier_baseline_role=frontier$' <<<"$selftest"
grep -q '^frontier_baseline_benchmark_label=SWE-bench-Pro$' <<<"$selftest"
grep -q '^held_out=true$' <<<"$selftest"
grep -q '^selection_manifest_path='"$tmp"'/selection_manifest.json$' <<<"$selftest"
grep -q '^selection_manifest_sha256=[0-9a-f]\{64\}$' <<<"$selftest"
grep -q '^selection_receipt_ok=true$' <<<"$selftest"
grep -q '^anti_cherry_pick=true$' <<<"$selftest"
grep -q '^metric_scope=paired_frontier_solve_rate_delta$' <<<"$selftest"
grep -q '^within_task_efficiency_metric_admissible=false$' <<<"$selftest"

write_frontier_baseline "$tmp/native_reordered_top_level_baseline.json" psf__requests-1921:true pytest-dev__pytest-5262:false
python3 - "$tmp/native_reordered_top_level_baseline.json" <<'PYREORDEREDBASELINE'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)
data["task_ids"] = list(reversed(data["task_ids"]))
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYREORDEREDBASELINE
reordered_top_level_selftest="$("$SCRIPT" --selftest "$WEIGHTS" "$tmp/native_reordered_top_level_baseline.json" psf__requests-1921 pytest-dev__pytest-5262)"
grep -q '^frontier_baseline_paired_tasks=false$' <<<"$reordered_top_level_selftest"
grep -q '^frontier_baseline_provenance_ok=false$' <<<"$reordered_top_level_selftest"
grep -q '^elevation_valid_if_run=false$' <<<"$reordered_top_level_selftest"
grep -q '^anti_replay=true$' <<<"$selftest"
grep -q '^substrate_mode=accumulated_canonical_act$' <<<"$selftest"
grep -q '^control_arm=deepseek_v4_pro_without_substrate$' <<<"$selftest"
grep -q '^substrate_arm=deepseek_v4_pro_with_substrate$' <<<"$selftest"
grep -q '^resume_supported=true$' <<<"$selftest"
grep -q '^swebench_import_timeout_seconds=20$' <<<"$selftest"
grep -q 'summary_fields=.*atomic_base_resolved' <<<"$selftest"
grep -q 'summary_fields=.*atomic_substrate_resolved' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_resolved' <<<"$selftest"
grep -q 'summary_fields=.*frontier_solve_rate' <<<"$selftest"
grep -q 'summary_fields=.*selected_task_ids_sha256' <<<"$selftest"
grep -q 'summary_fields=.*selection_manifest_path' <<<"$selftest"
grep -q 'summary_fields=.*selection_manifest_sha256' <<<"$selftest"
grep -q 'summary_fields=.*selection_receipt_ok' <<<"$selftest"
grep -q 'summary_fields=.*anti_cherry_pick' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_path' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_sha256' <<<"$selftest"
grep -q 'summary_fields=.*benchmark_suite' <<<"$selftest"
grep -q 'summary_fields=.*metric_claim' <<<"$selftest"
grep -q 'summary_fields=.*benchmark_dataset_name' <<<"$selftest"
grep -q 'summary_fields=.*official_benchmark' <<<"$selftest"
grep -q 'summary_fields=.*metric_scope' <<<"$selftest"
grep -q 'summary_fields=.*within_task_efficiency_metric_admissible' <<<"$selftest"
grep -q 'summary_fields=.*task_provenance_ok' <<<"$selftest"
grep -q 'summary_fields=.*deepseek_control_resolved' <<<"$selftest"
grep -q 'summary_fields=.*student_solve_rate' <<<"$selftest"
grep -q 'summary_fields=.*deepseek_control_solve_rate' <<<"$selftest"
grep -q 'summary_fields=.*elevation_vs_frontier' <<<"$selftest"
grep -q 'summary_fields=.*elevation_vs_frontier_solve_rate' <<<"$selftest"
grep -q 'summary_fields=.*elevation_vs_deepseek_control' <<<"$selftest"
grep -q 'summary_fields=.*elevation_vs_deepseek_control_solve_rate' <<<"$selftest"
grep -q 'summary_fields=.*teacher_atomic' <<<"$selftest"
grep -q 'summary_fields=.*teacher_model' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_provenance_ok' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_evidence_receipt_ok' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_role' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_frozen' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_official_docker' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_benchmark_label' <<<"$selftest"
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

write_frontier_baseline "$tmp/native_non_atomic_frontier.json" psf__requests-1921:true
python3 - "$tmp/native_non_atomic_frontier.json" <<'PYNONATOMICFRONTIER'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)
data["atomic"] = False
data.pop("tooling", None)
data.pop("protocol", None)
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYNONATOMICFRONTIER
non_atomic_frontier_selftest="$("$SCRIPT" --selftest "$WEIGHTS" "$tmp/native_non_atomic_frontier.json" psf__requests-1921)"
grep -q '^frontier_baseline_provenance_ok=true$' <<<"$non_atomic_frontier_selftest"
grep -q '^teacher_atomic=false$' <<<"$non_atomic_frontier_selftest"
grep -q '^elevation_valid_if_run=false$' <<<"$non_atomic_frontier_selftest"
if "$SCRIPT" ELEVTEST "$tmp/native_non_atomic_frontier.json" "$WEIGHTS" psf__requests-1921 >"$tmp/non_atomic_frontier.out" 2>"$tmp/non_atomic_frontier.err"; then
  echo "expected non-atomic frontier teacher baseline to be rejected before run" >&2
  exit 1
fi
grep -q 'atomic frontier teacher baseline required for Elevação' "$tmp/non_atomic_frontier.err"
if grep -q 'official SWE-Bench Pro task provenance required' "$tmp/non_atomic_frontier.err"; then
  echo "teacher-atomic rejection must happen before task workspace/provenance checks" >&2
  exit 1
fi

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

write_frontier_baseline "$tmp/native_replay.json" psf__requests-1921:true
python3 - "$tmp/native_replay.json" <<'PYREPLAYBASELINE'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)
data["teach_task_ids"] = ["psf__requests-1921"]
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYREPLAYBASELINE
replay_selftest="$("$SCRIPT" --selftest "$WEIGHTS" "$tmp/native_replay.json" psf__requests-1921)"
grep -q '^frontier_baseline_provenance_ok=true$' <<<"$replay_selftest"
grep -q '^anti_replay=false$' <<<"$replay_selftest"
grep -q '^elevation_valid_if_run=false$' <<<"$replay_selftest"
if "$SCRIPT" ELEVTEST "$tmp/native_replay.json" "$WEIGHTS" psf__requests-1921 >"$tmp/replay.out" 2>"$tmp/replay.err"; then
  echo "expected replayed teach/held-out task overlap to be rejected before run" >&2
  exit 1
fi
grep -q 'held-out anti-replay required for Elevação' "$tmp/replay.err"
if grep -q 'official SWE-Bench Pro task provenance required' "$tmp/replay.err"; then
  echo "anti-replay rejection must happen before task workspace/provenance checks" >&2
  exit 1
fi

write_frontier_baseline "$tmp/native_no_teach_baseline.json" psf__requests-1921:true
python3 - "$tmp/native_no_teach_baseline.json" <<'PYNOTEACHBASELINE'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)
data.pop("teach_task_ids", None)
data.pop("teacher_task_ids", None)
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYNOTEACHBASELINE
no_teach_selftest="$("$SCRIPT" --selftest "$WEIGHTS" "$tmp/native_no_teach_baseline.json" psf__requests-1921)"
grep -q '^anti_replay=false$' <<<"$no_teach_selftest"
grep -q '^held_out=false$' <<<"$no_teach_selftest"
grep -q '^elevation_valid_if_run=false$' <<<"$no_teach_selftest"
if "$SCRIPT" ELEVTEST "$tmp/native_no_teach_baseline.json" "$WEIGHTS" psf__requests-1921 >"$tmp/no_teach.out" 2>"$tmp/no_teach.err"; then
  echo "expected baseline without teach task ids to be rejected before run" >&2
  exit 1
fi
grep -q 'held-out anti-replay required for Elevação' "$tmp/no_teach.err"
if grep -q 'official SWE-Bench Pro task provenance required' "$tmp/no_teach.err"; then
  echo "anti-replay gate should run before task provenance" >&2
  exit 1
fi

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
grep -q '"frontier_solve_rate"' "$SCRIPT"
grep -q '"selected_task_ids_sha256"' "$SCRIPT"
grep -q '"selection_manifest_path"' "$SCRIPT"
grep -q '"selection_manifest_sha256"' "$SCRIPT"
grep -q '"selection_receipt_ok"' "$SCRIPT"
grep -q '"anti_cherry_pick"' "$SCRIPT"
grep -q 'deterministic SWE-Bench Pro selection receipt required' "$SCRIPT"
grep -q '"frontier_baseline_path"' "$SCRIPT"
grep -q '"frontier_baseline_sha256"' "$SCRIPT"
grep -q '"frontier_baseline_role"' "$SCRIPT"
grep -q '"frontier_baseline_frozen"' "$SCRIPT"
grep -q '"frontier_baseline_official_docker"' "$SCRIPT"
grep -q '"frontier_baseline_benchmark_label"' "$SCRIPT"
grep -q '"metric_scope"' "$SCRIPT"
grep -q '"within_task_efficiency_metric_admissible"' "$SCRIPT"
grep -q '"deepseek_control_resolved"' "$SCRIPT"
grep -q '"student_solve_rate"' "$SCRIPT"
grep -q '"deepseek_control_solve_rate"' "$SCRIPT"
grep -q '"elevation_vs_frontier"' "$SCRIPT"
grep -q '"elevation_vs_frontier_solve_rate"' "$SCRIPT"
grep -q '"elevation_vs_deepseek_control"' "$SCRIPT"
grep -q '"elevation_vs_deepseek_control_solve_rate"' "$SCRIPT"
grep -q '"anti_replay"' "$SCRIPT"
grep -q '"elevation_valid"' "$SCRIPT"
grep -q 'DEEPSEEK_API_KEY' "$SCRIPT"
if grep -q '/tmp/.atomic_creds.sh' "$SCRIPT"; then
  echo "elevation stream must not source credential files; use env only" >&2
  exit 1
fi
if grep -q 'source /tmp' "$SCRIPT"; then
  echo "elevation stream must not source credentials from /tmp; use env only" >&2
  exit 1
fi

echo "Elevation stream contract ok"
