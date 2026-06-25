#!/usr/bin/env bash
set -euo pipefail

HERE="/Users/danielpenin/atomic-os-swebench/core/agent/atomic-full-ab/local-loop"
cd "$HERE"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

canonical="$HERE/.corpus/weights.jsonl"
fake_canonical="$tmp/weights.jsonl"
experimental="$tmp/weights_act.jsonl"

cat >"$fake_canonical" <<'JSONL'
{"class":"TEST-ACT","trigger":"test","strategy":"test strategy","proof_n":1,"instances":[{"task":"held-out","repo":"demo"}],"act":{"preconditions":{"trigger":"test"},"transformation":{"op":"apply_learned_resolution_operator","class":"TEST-ACT","strategy":"test strategy"},"effects":{"requires_verification":true},"cost":{"strategy_chars":13},"receipt":{"kind":"act-receipt-v1","payload_sha256":"demo"},"fidelity_battery":[{"task":"held-out","repo":"demo"}]}}
JSONL

cp "$fake_canonical" "$experimental"

selftest_out="$tmp/selftest.out"
bash ./run_weight_lift.sh --selftest "$canonical" >"$selftest_out"

grep -q 'canonical_act=true' "$selftest_out"
grep -q 'run_id=' "$selftest_out"
grep -q 'teacher_model=deepseek-v4-pro' "$selftest_out"
grep -q 'student_model=deepseek-v4-pro' "$selftest_out"
grep -q 'cross_model=false' "$selftest_out"
grep -q 'base_only=false' "$selftest_out"
grep -q 'sample_timeout_seconds=600' "$selftest_out"
grep -q 'score_timeout_seconds=900' "$selftest_out"
grep -q 'score_attempts=2' "$selftest_out"
grep -q 'min_free_kb=2097152' "$selftest_out"
grep -q 'docker_timeout_seconds=20' "$selftest_out"
grep -q 'swebench_import_timeout_seconds=120' "$selftest_out"
grep -q 'swe_python=/opt/homebrew/bin/python3' "$selftest_out"
grep -q 'swebench_importable=' "$selftest_out"
grep -q 'summary_fields=base_resolved,weight_resolved,N,lift,weights_sha256,canonical_act,teacher_model,student_model,cross_model,base_only,sample_timeouts,score_failures,goldilocks_baseline,fail_floor_positive_lift,matched_weight_fidelity_ok,unproven_matched_weight_classes,g2_valid' "$selftest_out"

cross_out="$tmp/cross.out"
ATOMIC_WLIFT_STUDENT_MODEL=deepseek-v3 ATOMIC_WLIFT_SWEBENCH_IMPORT_TIMEOUT_SECONDS=1 bash ./run_weight_lift.sh --selftest "$canonical" >"$cross_out"
grep -q 'student_model=deepseek-v3' "$cross_out"
grep -q 'cross_model=true' "$cross_out"

probe_out="$tmp/probe_selftest.out"
ATOMIC_WLIFT_BASE_ONLY=1 ATOMIC_WLIFT_STUDENT_MODEL=deepseek-v3 ATOMIC_WLIFT_SWEBENCH_IMPORT_TIMEOUT_SECONDS=1 bash ./run_weight_lift.sh --selftest "$canonical" >"$probe_out"
grep -q 'base_only=true' "$probe_out"
grep -q 'cross_model=true' "$probe_out"

timeout_out="$tmp/timeout_selftest.out"
ATOMIC_WLIFT_SAMPLE_TIMEOUT_SECONDS=7 ATOMIC_WLIFT_SCORE_TIMEOUT_SECONDS=11 ATOMIC_WLIFT_SCORE_ATTEMPTS=3 ATOMIC_WLIFT_MIN_FREE_KB=13 ATOMIC_WLIFT_DOCKER_TIMEOUT_SECONDS=5 ATOMIC_WLIFT_SWEBENCH_IMPORT_TIMEOUT_SECONDS=4 bash ./run_weight_lift.sh --selftest "$canonical" >"$timeout_out"
grep -q 'sample_timeout_seconds=7' "$timeout_out"
grep -q 'score_timeout_seconds=11' "$timeout_out"
grep -q 'score_attempts=3' "$timeout_out"
grep -q 'min_free_kb=13' "$timeout_out"
grep -q 'docker_timeout_seconds=5' "$timeout_out"
grep -q 'swebench_import_timeout_seconds=4' "$timeout_out"
grep -q 'TimeoutExpired' ./run_weight_lift.sh
grep -q 'SWE_SCORE_TIMEOUT' ./run_weight_lift.sh
grep -q 'SWE_SCORE_RETRY' ./run_weight_lift.sh
grep -q 'docker API unavailable for official SWE-bench scoring' ./run_weight_lift.sh
grep -q 'integrity_ok and (goldilocks_baseline or fail_floor_positive_lift)' ./run_weight_lift.sh
grep -q '"goldilocks_baseline": goldilocks_baseline' ./run_weight_lift.sh
grep -q '"fail_floor_positive_lift": fail_floor_positive_lift' ./run_weight_lift.sh
grep -q 'insufficient free space for WLIFT scratch' ./run_weight_lift.sh
grep -q 'scratch_setup_failed' ./run_weight_lift.sh
grep -q 'rm -rf "$wd"' ./run_weight_lift.sh

if ATOMIC_WLIFT_STUDENT_MODEL=deepseek-v3 ATOMIC_WLIFT_MIN_FREE_KB=999999999999 bash ./run_weight_lift.sh pylint-dev__pylint-7080 1 "$canonical" >"$tmp/no_space.out" 2>"$tmp/no_space.err"; then
  echo "expected impossible free-space requirement to reject before expensive G2 work" >&2
  exit 1
fi

grep -q 'insufficient free space for WLIFT scratch' "$tmp/no_space.err"

if ATOMIC_WLIFT_STUDENT_MODEL=deepseek-v4-pro bash ./run_weight_lift.sh pylint-dev__pylint-7080 1 "$canonical" >"$tmp/model_equal.out" 2>"$tmp/model_equal.err"; then
  echo "expected model-equal normal run to be rejected unless explicitly experimental" >&2
  exit 1
fi

grep -q 'model-equal lift is not G2' "$tmp/model_equal.err"

if ATOMIC_WLIFT_STUDENT_MODEL=deepseek-v3 bash ./run_weight_lift.sh pylint-dev__pylint-4661 1 "$canonical" >"$tmp/unproven_match.out" 2>"$tmp/unproven_match.err"; then
  echo "expected proofless matched ACTs to be rejected before a full G2 run" >&2
  exit 1
fi

grep -q 'matched weights lack proof-carrying fidelity battery' "$tmp/unproven_match.err"
grep -q 'MISSED-COMPANION-CONFIG-FILE' "$tmp/unproven_match.err"
grep -q 'matched_weight_fidelity_ok' ./run_weight_lift.sh
grep -q 'unproven_matched_weight_classes' ./run_weight_lift.sh

if SWE_PYTHON=/usr/bin/python3 ATOMIC_WLIFT_STUDENT_MODEL=deepseek-v3 ATOMIC_WLIFT_SWEBENCH_IMPORT_TIMEOUT_SECONDS=1 ATOMIC_WLIFT_ALLOW_UNPROVEN_MATCHED_WEIGHTS=1 bash ./run_weight_lift.sh pylint-dev__pylint-7080 1 "$canonical" >"$tmp/missing_swebench.out" 2>"$tmp/missing_swebench.err"; then
  echo "expected normal run to reject a Python interpreter without swebench" >&2
  exit 1
fi

grep -q 'swebench import failed for SWE_PYTHON=/usr/bin/python3' "$tmp/missing_swebench.err"

repo_root="/Users/danielpenin/atomic-os-swebench"
relative_out="$tmp/relative.out"
(
  cd "$repo_root"
  bash core/agent/atomic-full-ab/local-loop/run_weight_lift.sh --selftest core/agent/atomic-full-ab/local-loop/.corpus/weights.jsonl >"$relative_out"
)
grep -q 'canonical_act=true' "$relative_out"

if bash ./run_weight_lift.sh --selftest "$fake_canonical" >"$tmp/fake_canonical.out" 2>"$tmp/fake_canonical.err"; then
  echo "expected same-basename noncanonical weights.jsonl to be rejected without explicit experimental opt-in" >&2
  exit 1
fi

grep -qi 'noncanonical' "$tmp/fake_canonical.err"

if bash ./run_weight_lift.sh --selftest "$experimental" >"$tmp/experimental.out" 2>"$tmp/experimental.err"; then
  echo "expected noncanonical weights_act bank to be rejected without explicit experimental opt-in" >&2
  exit 1
fi

grep -qi 'noncanonical' "$tmp/experimental.err"
