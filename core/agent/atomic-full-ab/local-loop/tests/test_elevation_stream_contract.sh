#!/usr/bin/env bash
set -euo pipefail

HERE="/Users/danielpenin/atomic-os-swebench/core/agent/atomic-full-ab/local-loop"
cd "$HERE"

SCRIPT="$HERE/run_elevation_stream.sh"
WEIGHTS="$HERE/.corpus/weights.jsonl"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/native_baseline.json" <<'JSON'
{
  "model": "frontier-teacher",
  "atomic": true,
  "teach_task_ids": ["django__django-0001"],
  "instances": {
    "psf__requests-1921": {"resolved": true, "tool_uses": 7},
    "pytest-dev__pytest-5262": {"resolved": false, "tool_uses": 5}
  }
}
JSON

selftest="$("$SCRIPT" --selftest "$WEIGHTS" "$tmp/native_baseline.json" psf__requests-1921 pytest-dev__pytest-5262)"

grep -q '^metric=elevation$' <<<"$selftest"
grep -q '^canonical_act=true$' <<<"$selftest"
grep -q '^native_baseline_resolved_fields=true$' <<<"$selftest"
grep -q '^distinct_tasks=true$' <<<"$selftest"
grep -q '^student_model=deepseek-v4-pro$' <<<"$selftest"
grep -q '^teacher_model=frontier-teacher$' <<<"$selftest"
grep -q '^teacher_atomic=true$' <<<"$selftest"
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
grep -q 'summary_fields=.*deepseek_control_resolved' <<<"$selftest"
grep -q 'summary_fields=.*elevation_vs_frontier' <<<"$selftest"
grep -q 'summary_fields=.*elevation_vs_deepseek_control' <<<"$selftest"
grep -q 'summary_fields=.*teacher_atomic' <<<"$selftest"
grep -q 'summary_fields=.*teacher_model' <<<"$selftest"
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
