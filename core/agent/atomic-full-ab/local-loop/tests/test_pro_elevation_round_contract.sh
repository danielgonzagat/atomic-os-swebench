#!/usr/bin/env bash
set -euo pipefail

HERE="/Users/danielpenin/atomic-os-swebench/core/agent/atomic-full-ab/local-loop"
cd "$HERE"

ROUND="$HERE/run_pro_elevation_round.sh"
FRONTIER_RUNNER="$HERE/run_frontier_baseline.sh"
ELEVATION_STREAM="$HERE/run_elevation_stream.sh"
WEIGHTS="$HERE/.corpus/weights.jsonl"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

manifest="$tmp/pro_manifest.json"
cat >"$manifest" <<'JSON'
{
  "benchmark_suite": "swe_bench_pro",
  "dataset_name": "ScaleAI/SWE-bench_Pro",
  "benchmark_label": "SWE-bench-Pro",
  "official_benchmark": true,
  "metric_claim": false,
  "selected_task_ids": ["pro__task-a", "pro__task-b"],
  "selected_count": 2
}
JSON

selftest="$(ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" "$ROUND" --selftest)"
frontier_runner_sha="$(shasum -a 256 "$FRONTIER_RUNNER" | awk '{print $1}')"
elevation_stream_sha="$(shasum -a 256 "$ELEVATION_STREAM" | awk '{print $1}')"
grep -q '^metric=pro_elevation_round$' <<<"$selftest"
grep -q '^metric_claim=false$' <<<"$selftest"
grep -q '^benchmark_suite=swe_bench_pro$' <<<"$selftest"
grep -q '^benchmark_dataset_name=ScaleAI/SWE-bench_Pro$' <<<"$selftest"
grep -q '^official_benchmark=true$' <<<"$selftest"
grep -q '^selected_task_count=2$' <<<"$selftest"
grep -q '^requires_deepseek_api_key=true$' <<<"$selftest"
grep -q '^credential_source=env$' <<<"$selftest"
grep -q '^credential_file_allowed=false$' <<<"$selftest"
grep -q "^frontier_baseline_runner=$FRONTIER_RUNNER$" <<<"$selftest"
grep -q "^frontier_baseline_runner_sha256=$frontier_runner_sha$" <<<"$selftest"
grep -q "^elevation_stream=$ELEVATION_STREAM$" <<<"$selftest"
grep -q "^elevation_stream_sha256=$elevation_stream_sha$" <<<"$selftest"
grep -q '^weights_path=' <<<"$selftest"
grep -q '^no_synthetic=true$' <<<"$selftest"
grep -q '^no_replay=true$' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_runner' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_runner_sha256' <<<"$selftest"
grep -q 'summary_fields=.*elevation_stream' <<<"$selftest"
grep -q 'summary_fields=.*elevation_stream_sha256' <<<"$selftest"
grep -q 'summary_fields=.*weights_path' <<<"$selftest"
grep -q 'summary_fields=.*weights_sha256' <<<"$selftest"
grep -q 'summary_fields=.*task_provenance_ok' <<<"$selftest"
grep -q 'summary_fields=.*task_provenance_sha256' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_path' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_sha256' <<<"$selftest"
grep -q 'summary_fields=.*preflight_receipt_path' <<<"$selftest"
grep -q 'summary_fields=.*preflight_receipt_sha256' <<<"$selftest"
grep -q 'summary_fields=.*preflight_verification_ok' <<<"$selftest"
grep -q 'summary_fields=.*elevation_summary_path' <<<"$selftest"
grep -q 'summary_fields=.*elevation_summary_sha256' <<<"$selftest"
grep -q 'summary_fields=.*round_receipt_path' <<<"$selftest"
grep -q 'summary_fields=.*round_receipt_sha256' <<<"$selftest"
grep -q 'summary_fields=.*round_receipt_verification_ok' <<<"$selftest"

preflight_json="$tmp/preflight.json"
preflight="$(ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" "$ROUND" --preflight "$preflight_json")"
grep -q '^metric=pro_elevation_preflight$' <<<"$preflight"
grep -q '^metric_claim=false$' <<<"$preflight"
grep -q '^official_benchmark=true$' <<<"$preflight"
grep -q '^selected_task_count=2$' <<<"$preflight"
grep -q '^deepseek_api_key_present=false$' <<<"$preflight"
grep -q '^credential_source=env$' <<<"$preflight"
grep -q '^credential_file_allowed=false$' <<<"$preflight"
grep -q "^frontier_baseline_runner=$FRONTIER_RUNNER$" <<<"$preflight"
grep -q "^frontier_baseline_runner_sha256=$frontier_runner_sha$" <<<"$preflight"
grep -q "^elevation_stream=$ELEVATION_STREAM$" <<<"$preflight"
grep -q "^elevation_stream_sha256=$elevation_stream_sha$" <<<"$preflight"
grep -q '^task_layout_ok=false$' <<<"$preflight"
grep -q '^task_provenance_ok=false$' <<<"$preflight"
grep -q '^task_provenance_sha256=$' <<<"$preflight"
grep -q '^suite_pristine_layout_ok=false$' <<<"$preflight"
grep -q '^ready_to_run=false$' <<<"$preflight"
grep -q '^no_model_run=true$' <<<"$preflight"
grep -q '^no_scorer_run=true$' <<<"$preflight"
grep -q '"metric": "pro_elevation_preflight"' "$preflight_json"
grep -q '"metric_claim": false' "$preflight_json"
grep -q '"deepseek_api_key_present": false' "$preflight_json"
grep -q '"credential_source": "env"' "$preflight_json"
grep -q '"credential_file_allowed": false' "$preflight_json"
grep -q "\"frontier_baseline_runner_sha256\": \"$frontier_runner_sha\"" "$preflight_json"
grep -q "\"elevation_stream_sha256\": \"$elevation_stream_sha\"" "$preflight_json"
grep -q '"task_provenance_ok": false' "$preflight_json"
grep -q '"task_provenance_sha256": ""' "$preflight_json"
grep -q '"ready_to_run": false' "$preflight_json"
if grep -q 'DEEPSEEK_API_KEY' "$preflight_json"; then
  echo "preflight receipt must not serialize secret names or values" >&2
  exit 1
fi

blocked_ready_json="$tmp/blocked-ready.json"
if ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" "$ROUND" --ready "$blocked_ready_json" >"$tmp/blocked-ready.out" 2>"$tmp/blocked-ready.err"; then
  echo "expected --ready to exit nonzero when preflight is not ready" >&2
  exit 1
fi
grep -q '^metric=pro_elevation_preflight$' "$tmp/blocked-ready.out"
grep -q '^ready_to_run=false$' "$tmp/blocked-ready.out"
grep -q '^no_model_run=true$' "$tmp/blocked-ready.out"
grep -q '^no_scorer_run=true$' "$tmp/blocked-ready.out"
grep -q '"ready_to_run": false' "$blocked_ready_json"

bad_manifest="$tmp/verified_manifest.json"
cat >"$bad_manifest" <<'JSON'
{
  "benchmark_suite": "swe_bench_verified",
  "dataset_name": "princeton-nlp/SWE-bench_Verified",
  "official_benchmark": false,
  "selected_task_ids": ["verified__task"]
}
JSON
if ATOMIC_PRO_ELEVATION_MANIFEST="$bad_manifest" DEEPSEEK_API_KEY=dummy "$ROUND" BADROUND >"$tmp/bad.out" 2>"$tmp/bad.err"; then
  echo "expected non-Pro manifest to be rejected" >&2
  exit 1
fi
grep -q 'official SWE-Bench Pro manifest required' "$tmp/bad.err"

nokey_outroot="$tmp/nokey-out"
mkdir -p "$nokey_outroot"
if ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_ELEVATION_OUTROOT="$nokey_outroot" \
ATOMIC_PRO_ELEVATION_RUN_ID="nokey-preflight" \
  "$ROUND" NOKEY >"$tmp/nokey.out" 2>"$tmp/nokey.err"; then
  echo "expected missing DEEPSEEK_API_KEY to be rejected by preflight" >&2
  exit 1
fi
grep -q 'Pro elevation preflight failed' "$tmp/nokey.err"
grep -q 'deepseek_api_key_present=false' "$tmp/nokey.err"
grep -q 'ready_to_run=false' "$tmp/nokey.err"
grep -q '"deepseek_api_key_present": false' "$nokey_outroot/nokey-preflight/preflight.json"
grep -q '"ready_to_run": false' "$nokey_outroot/nokey-preflight/preflight.json"

fake_provenance_sha="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
fake_frontier="$tmp/fake_frontier.sh"
cat >"$fake_frontier" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--selftest" ]; then
  echo 'task_layout_ok=true'
  echo 'task_provenance_ok=true'
  echo 'task_provenance_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  echo 'suite_pristine_layout_ok=true'
  exit 0
fi
printf 'frontier_args=%s\n' "$*" >"$ATOMIC_FAKE_FRONTIER_ARGS"
out="$2"
mkdir -p "$(dirname "$out")"
printf '{"baseline_role":"frontier","frontier_receipt":{"format":"swebench_pro_frontier_baseline_v1"}}\n' >"$out"
SH
chmod +x "$fake_frontier"

fake_stream="$tmp/fake_stream.sh"
cat >"$fake_stream" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--selftest" ]; then
  echo 'frontier_baseline_evidence_receipt_ok=true'
  echo 'elevation_valid_if_run=true'
  exit 0
fi
printf 'stream_args=%s\n' "$*" >"$ATOMIC_FAKE_STREAM_ARGS"
mkdir -p "$ATOMIC_FAKE_ELEVATION_OUT"
printf '{"metric":"elevation","metric_claim":false,"benchmark_suite":"swe_bench_pro","benchmark_dataset_name":"ScaleAI/SWE-bench_Pro","official_benchmark":true,"task_ids":["pro__task-a","pro__task-b"],"elevation_valid":true,"task_provenance_ok":true,"suite_preflight_ok":true,"frontier_baseline_evidence_receipt_ok":true,"frontier_baseline_provenance_ok":true,"teacher_atomic":true,"anti_replay":true,"distinct_tasks":true}\n' >"$ATOMIC_FAKE_ELEVATION_OUT/elevation_summary.json"
echo "elevation_summary=$ATOMIC_FAKE_ELEVATION_OUT/elevation_summary.json"
SH
chmod +x "$fake_stream"
fake_frontier_sha="$(shasum -a 256 "$fake_frontier" | awk '{print $1}')"
fake_stream_sha="$(shasum -a 256 "$fake_stream" | awk '{print $1}')"

ready_preflight_json="$tmp/ready-preflight.json"
ready_preflight="$(ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$fake_stream" \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" --preflight "$ready_preflight_json")"
grep -q '^deepseek_api_key_present=true$' <<<"$ready_preflight"
grep -q '^credential_source=env$' <<<"$ready_preflight"
grep -q '^credential_file_allowed=false$' <<<"$ready_preflight"
grep -q '^frontier_runner_ok=true$' <<<"$ready_preflight"
grep -q "^frontier_baseline_runner=$fake_frontier$" <<<"$ready_preflight"
grep -q "^frontier_baseline_runner_sha256=$fake_frontier_sha$" <<<"$ready_preflight"
grep -q '^elevation_stream_ok=true$' <<<"$ready_preflight"
grep -q "^elevation_stream=$fake_stream$" <<<"$ready_preflight"
grep -q "^elevation_stream_sha256=$fake_stream_sha$" <<<"$ready_preflight"
grep -q '^weights_ok=true$' <<<"$ready_preflight"
grep -q '^task_layout_ok=true$' <<<"$ready_preflight"
grep -q '^task_provenance_ok=true$' <<<"$ready_preflight"
grep -q "^task_provenance_sha256=$fake_provenance_sha$" <<<"$ready_preflight"
grep -q '^suite_pristine_layout_ok=true$' <<<"$ready_preflight"
grep -q '^ready_to_run=true$' <<<"$ready_preflight"
grep -q '"ready_to_run": true' "$ready_preflight_json"
grep -q "\"frontier_baseline_runner_sha256\": \"$fake_frontier_sha\"" "$ready_preflight_json"
grep -q "\"elevation_stream_sha256\": \"$fake_stream_sha\"" "$ready_preflight_json"
grep -q '"task_provenance_ok": true' "$ready_preflight_json"
grep -q "\"task_provenance_sha256\": \"$fake_provenance_sha\"" "$ready_preflight_json"
grep -q '"no_model_run": true' "$ready_preflight_json"
grep -q '"no_scorer_run": true' "$ready_preflight_json"

verify_ready="$(ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$fake_stream" \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" --verify-preflight "$ready_preflight_json")"
grep -q '^metric=pro_elevation_preflight_verification$' <<<"$verify_ready"
grep -q '^metric_claim=false$' <<<"$verify_ready"
grep -q '^preflight_receipt_ok=true$' <<<"$verify_ready"
grep -q '^receipt_ready_to_run=true$' <<<"$verify_ready"
grep -q '^current_ready_to_run=true$' <<<"$verify_ready"
grep -q '^receipt_matches_current=true$' <<<"$verify_ready"
grep -q '^no_model_run=true$' <<<"$verify_ready"
grep -q '^no_scorer_run=true$' <<<"$verify_ready"

ready_cmd_json="$tmp/ready-cmd.json"
ready_cmd_out="$(ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$fake_stream" \
ATOMIC_FAKE_FRONTIER_ARGS="$tmp/ready-frontier.args" \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" --ready "$ready_cmd_json")"
grep -q '^metric=pro_elevation_preflight$' <<<"$ready_cmd_out"
grep -q '^ready_to_run=true$' <<<"$ready_cmd_out"
grep -q '^no_model_run=true$' <<<"$ready_cmd_out"
grep -q '^no_scorer_run=true$' <<<"$ready_cmd_out"
grep -q '"ready_to_run": true' "$ready_cmd_json"
test ! -f "$tmp/ready-frontier.args"

tampered_preflight_json="$tmp/tampered-preflight.json"
sed 's/"selected_task_ids_sha256": "[^"]*"/"selected_task_ids_sha256": "stale"/' "$ready_preflight_json" >"$tampered_preflight_json"
if ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$fake_stream" \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" --verify-preflight "$tampered_preflight_json" >"$tmp/tampered-verify.out" 2>"$tmp/tampered-verify.err"; then
  echo "expected tampered preflight receipt to be rejected" >&2
  exit 1
fi
grep -q '^preflight_receipt_ok=false$' "$tmp/tampered-verify.out"
grep -q '^receipt_matches_current=false$' "$tmp/tampered-verify.out"

tampered_toolchain_json="$tmp/tampered-toolchain-preflight.json"
sed 's/"frontier_baseline_runner_sha256": "[^"]*"/"frontier_baseline_runner_sha256": "stale"/' "$ready_preflight_json" >"$tampered_toolchain_json"
if ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$fake_stream" \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" --verify-preflight "$tampered_toolchain_json" >"$tmp/tampered-toolchain-verify.out" 2>"$tmp/tampered-toolchain-verify.err"; then
  echo "expected tampered toolchain hash to be rejected" >&2
  exit 1
fi
grep -q '^preflight_receipt_ok=false$' "$tmp/tampered-toolchain-verify.out"
grep -q '^receipt_matches_current=false$' "$tmp/tampered-toolchain-verify.out"

tampered_provenance_json="$tmp/tampered-provenance-preflight.json"
sed 's/"task_provenance_sha256": "[^"]*"/"task_provenance_sha256": "stale"/' "$ready_preflight_json" >"$tampered_provenance_json"
if ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$fake_stream" \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" --verify-preflight "$tampered_provenance_json" >"$tmp/tampered-provenance-verify.out" 2>"$tmp/tampered-provenance-verify.err"; then
  echo "expected tampered task provenance hash to be rejected" >&2
  exit 1
fi
grep -q '^preflight_receipt_ok=false$' "$tmp/tampered-provenance-verify.out"
grep -q '^receipt_matches_current=false$' "$tmp/tampered-provenance-verify.out"

if ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
  "$ROUND" --verify-preflight "$preflight_json" >"$tmp/blocked-verify.out" 2>"$tmp/blocked-verify.err"; then
  echo "expected blocked preflight receipt to fail verification" >&2
  exit 1
fi
grep -q '^preflight_receipt_ok=false$' "$tmp/blocked-verify.out"
grep -q '^receipt_ready_to_run=false$' "$tmp/blocked-verify.out"
grep -q '^current_ready_to_run=false$' "$tmp/blocked-verify.out"

bad_layout_frontier="$tmp/bad_layout_frontier.sh"
cat >"$bad_layout_frontier" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--selftest" ]; then
  echo 'task_layout_ok=false'
  echo 'suite_pristine_layout_ok=true'
  exit 0
fi
printf 'frontier sampling should not run after failed preflight\n' >"$ATOMIC_BAD_FRONTIER_MARKER"
exit 99
SH
chmod +x "$bad_layout_frontier"
bad_outroot="$tmp/bad-out"
mkdir -p "$bad_outroot"
if ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$bad_layout_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$fake_stream" \
ATOMIC_PRO_ELEVATION_OUTROOT="$bad_outroot" \
ATOMIC_PRO_ELEVATION_RUN_ID="bad-preflight" \
ATOMIC_BAD_FRONTIER_MARKER="$tmp/bad-frontier.marker" \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" BADPREFLIGHT >"$tmp/badpre.out" 2>"$tmp/badpre.err"; then
  echo "expected failed preflight to abort the Pro round" >&2
  exit 1
fi
grep -q 'Pro elevation preflight failed' "$tmp/badpre.err"
test ! -f "$tmp/bad-frontier.marker"
grep -q 'ready_to_run=false' "$tmp/badpre.err"
grep -q '"ready_to_run": false' "$bad_outroot/bad-preflight/preflight.json"

bad_provenance_frontier="$tmp/bad_provenance_frontier.sh"
cat >"$bad_provenance_frontier" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--selftest" ]; then
  echo 'task_layout_ok=true'
  echo 'task_provenance_ok=false'
  echo 'suite_pristine_layout_ok=true'
  exit 0
fi
printf 'frontier sampling should not run after bad task provenance\n' >"$ATOMIC_BAD_PROVENANCE_MARKER"
exit 99
SH
chmod +x "$bad_provenance_frontier"
bad_provenance_outroot="$tmp/bad-provenance-out"
mkdir -p "$bad_provenance_outroot"
if ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$bad_provenance_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$fake_stream" \
ATOMIC_PRO_ELEVATION_OUTROOT="$bad_provenance_outroot" \
ATOMIC_PRO_ELEVATION_RUN_ID="bad-provenance-preflight" \
ATOMIC_BAD_PROVENANCE_MARKER="$tmp/bad-provenance-frontier.marker" \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" BADPROVENANCE >"$tmp/bad-provenance.out" 2>"$tmp/bad-provenance.err"; then
  echo "expected bad task provenance to abort the Pro round" >&2
  exit 1
fi
grep -q 'Pro elevation preflight failed' "$tmp/bad-provenance.err"
test ! -f "$tmp/bad-provenance-frontier.marker"
grep -q 'task_provenance_ok=false' "$tmp/bad-provenance.err"
grep -q 'ready_to_run=false' "$tmp/bad-provenance.err"
grep -q '"task_provenance_ok": false' "$bad_provenance_outroot/bad-provenance-preflight/preflight.json"
grep -q '"ready_to_run": false' "$bad_provenance_outroot/bad-provenance-preflight/preflight.json"

missing_summary_stream="$tmp/missing_summary_stream.sh"
cat >"$missing_summary_stream" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--selftest" ]; then
  echo 'frontier_baseline_evidence_receipt_ok=true'
  echo 'elevation_valid_if_run=true'
  exit 0
fi
echo "elevation_summary=$ATOMIC_MISSING_SUMMARY_PATH"
SH
chmod +x "$missing_summary_stream"
missing_summary_outroot="$tmp/missing-summary-out"
mkdir -p "$missing_summary_outroot"
if ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$missing_summary_stream" \
ATOMIC_PRO_ELEVATION_OUTROOT="$missing_summary_outroot" \
ATOMIC_PRO_ELEVATION_RUN_ID="missing-summary" \
ATOMIC_FAKE_FRONTIER_ARGS="$tmp/missing-frontier.args" \
ATOMIC_MISSING_SUMMARY_PATH="$tmp/missing-summary.json" \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" MISSINGSUMMARY >"$tmp/missing-summary.out" 2>"$tmp/missing-summary.err"; then
  echo "expected missing elevation summary to abort the Pro round" >&2
  exit 1
fi
grep -q 'elevation summary missing or invalid' "$tmp/missing-summary.err"

bad_evidence_stream="$tmp/bad_evidence_stream.sh"
cat >"$bad_evidence_stream" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--selftest" ]; then
  echo 'frontier_baseline_evidence_receipt_ok=true'
  echo 'elevation_valid_if_run=true'
  exit 0
fi
mkdir -p "$ATOMIC_BAD_EVIDENCE_OUT"
printf '{"metric":"elevation","metric_claim":false,"benchmark_suite":"swe_bench_pro","benchmark_dataset_name":"ScaleAI/SWE-bench_Pro","official_benchmark":true,"task_ids":["pro__task-a","pro__task-b"],"elevation_valid":true,"task_provenance_ok":true,"suite_preflight_ok":true,"frontier_baseline_evidence_receipt_ok":true,"frontier_baseline_provenance_ok":true,"teacher_atomic":true,"anti_replay":false,"distinct_tasks":true}\n' >"$ATOMIC_BAD_EVIDENCE_OUT/elevation_summary.json"
echo "elevation_summary=$ATOMIC_BAD_EVIDENCE_OUT/elevation_summary.json"
SH
chmod +x "$bad_evidence_stream"
bad_evidence_outroot="$tmp/bad-evidence-out"
mkdir -p "$bad_evidence_outroot"
if ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$bad_evidence_stream" \
ATOMIC_PRO_ELEVATION_OUTROOT="$bad_evidence_outroot" \
ATOMIC_PRO_ELEVATION_RUN_ID="bad-evidence" \
ATOMIC_FAKE_FRONTIER_ARGS="$tmp/bad-evidence-frontier.args" \
ATOMIC_BAD_EVIDENCE_OUT="$tmp/bad-evidence" \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" BADEVIDENCE >"$tmp/bad-evidence.out" 2>"$tmp/bad-evidence.err"; then
  echo "expected anti-circularity-invalid elevation summary to abort the Pro round" >&2
  exit 1
fi
grep -q 'elevation summary missing or invalid' "$tmp/bad-evidence.err"

outroot="$tmp/out"
mkdir -p "$outroot"
ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$fake_stream" \
ATOMIC_PRO_ELEVATION_OUTROOT="$outroot" \
ATOMIC_PRO_ELEVATION_RUN_ID="round-contract" \
ATOMIC_FAKE_FRONTIER_ARGS="$tmp/frontier.args" \
ATOMIC_FAKE_STREAM_ARGS="$tmp/stream.args" \
ATOMIC_FAKE_ELEVATION_OUT="$tmp/fake-elevation" \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" ROUNDTEST >"$tmp/round.out"

grep -q 'frontier_args=round-contract-frontier' "$tmp/frontier.args"
grep -q 'pro__task-a' "$tmp/frontier.args"
grep -q 'pro__task-b' "$tmp/frontier.args"
grep -q 'stream_args=ROUNDTEST' "$tmp/stream.args"
grep -q 'pro__task-a' "$tmp/stream.args"
grep -q 'pro__task-b' "$tmp/stream.args"
grep -q '^metric=pro_elevation_round metric_claim=false' "$tmp/round.out"
grep -q "manifest_path=$manifest" "$tmp/round.out"
grep -q "frontier_baseline_runner=$fake_frontier" "$tmp/round.out"
grep -q "frontier_baseline_runner_sha256=$fake_frontier_sha" "$tmp/round.out"
grep -q "elevation_stream=$fake_stream" "$tmp/round.out"
grep -q "elevation_stream_sha256=$fake_stream_sha" "$tmp/round.out"
weights_sha="$(shasum -a 256 "$WEIGHTS" | awk '{print $1}')"
grep -q "weights_path=$WEIGHTS" "$tmp/round.out"
grep -q "weights_sha256=$weights_sha" "$tmp/round.out"
task_ids_sha="$(printf 'pro__task-a\npro__task-b' | shasum -a 256 | awk '{print $1}')"
grep -q "selected_task_ids_sha256=$task_ids_sha" "$tmp/round.out"
grep -q 'task_provenance_ok=true' "$tmp/round.out"
grep -q "task_provenance_sha256=$fake_provenance_sha" "$tmp/round.out"
grep -q 'frontier_baseline_evidence_receipt_ok=true' "$tmp/round.out"
baseline_sha="$(shasum -a 256 "$outroot/round-contract/frontier_baseline.json" | awk '{print $1}')"
grep -q "frontier_baseline_sha256=$baseline_sha" "$tmp/round.out"
grep -q 'elevation_valid_if_run=true' "$tmp/round.out"
grep -q 'preflight_receipt_path=' "$tmp/round.out"
preflight_sha="$(shasum -a 256 "$outroot/round-contract/preflight.json" | awk '{print $1}')"
grep -q "preflight_receipt_sha256=$preflight_sha" "$tmp/round.out"
grep -q 'preflight_verification_ok=true' "$tmp/round.out"
grep -q "elevation_summary_path=$tmp/fake-elevation/elevation_summary.json" "$tmp/round.out"
summary_sha="$(shasum -a 256 "$tmp/fake-elevation/elevation_summary.json" | awk '{print $1}')"
grep -q "elevation_summary_sha256=$summary_sha" "$tmp/round.out"
round_receipt="$outroot/round-contract/round_receipt.json"
test -f "$round_receipt"
round_receipt_sha="$(shasum -a 256 "$round_receipt" | awk '{print $1}')"
grep -q "round_receipt_path=$round_receipt" "$tmp/round.out"
grep -q "round_receipt_sha256=$round_receipt_sha" "$tmp/round.out"
grep -q 'round_receipt_verification_ok=true' "$tmp/round.out"
grep -q '"metric": "pro_elevation_round"' "$round_receipt"
grep -q '"metric_claim": false' "$round_receipt"
grep -q '"benchmark_suite": "swe_bench_pro"' "$round_receipt"
grep -q '"benchmark_dataset_name": "ScaleAI/SWE-bench_Pro"' "$round_receipt"
grep -q '"official_benchmark": true' "$round_receipt"
grep -q "\"manifest_path\": \"$manifest\"" "$round_receipt"
grep -q "\"selected_task_ids_sha256\": \"$task_ids_sha\"" "$round_receipt"
grep -q '"task_provenance_ok": true' "$round_receipt"
grep -q "\"task_provenance_sha256\": \"$fake_provenance_sha\"" "$round_receipt"
grep -q "\"frontier_baseline_runner_sha256\": \"$fake_frontier_sha\"" "$round_receipt"
grep -q "\"elevation_stream_sha256\": \"$fake_stream_sha\"" "$round_receipt"
grep -q "\"weights_sha256\": \"$weights_sha\"" "$round_receipt"
grep -q "\"preflight_receipt_sha256\": \"$preflight_sha\"" "$round_receipt"
grep -q "\"frontier_baseline_sha256\": \"$baseline_sha\"" "$round_receipt"
grep -q "\"elevation_summary_sha256\": \"$summary_sha\"" "$round_receipt"
grep -q '"frontier_baseline_evidence_receipt_ok": true' "$round_receipt"
grep -q '"elevation_valid_if_run": true' "$round_receipt"
grep -q '"task_ids": \[' "$round_receipt"
grep -q '"pro__task-a"' "$round_receipt"
grep -q '"pro__task-b"' "$round_receipt"
if grep -q 'DEEPSEEK_API_KEY' "$round_receipt"; then
  echo "round receipt must not serialize secret names or values" >&2
  exit 1
fi
verify_round="$("$ROUND" --verify-round-receipt "$round_receipt")"
grep -q '^metric=pro_elevation_round_receipt_verification$' <<<"$verify_round"
grep -q '^metric_claim=false$' <<<"$verify_round"
grep -q "^round_receipt_path=$round_receipt$" <<<"$verify_round"
grep -q '^round_receipt_exists=true$' <<<"$verify_round"
grep -q '^round_receipt_schema_ok=true$' <<<"$verify_round"
grep -q '^round_receipt_artifact_hashes_ok=true$' <<<"$verify_round"
grep -q '^round_receipt_task_ids_ok=true$' <<<"$verify_round"
grep -q '^round_receipt_ok=true$' <<<"$verify_round"
grep -q "^round_receipt_sha256=$round_receipt_sha$" <<<"$verify_round"
grep -q '^no_model_run=true$' <<<"$verify_round"
grep -q '^no_scorer_run=true$' <<<"$verify_round"

tampered_round_provenance_receipt="$tmp/tampered-round-provenance-receipt.json"
sed 's/"task_provenance_sha256": "[^"]*"/"task_provenance_sha256": "stale"/' "$round_receipt" >"$tampered_round_provenance_receipt"
if "$ROUND" --verify-round-receipt "$tampered_round_provenance_receipt" >"$tmp/tampered-round-provenance-verify.out" 2>"$tmp/tampered-round-provenance-verify.err"; then
  echo "expected tampered round task provenance hash to fail verification" >&2
  exit 1
fi
grep -q '^round_receipt_ok=false$' "$tmp/tampered-round-provenance-verify.out"
grep -q '^round_receipt_schema_ok=false$' "$tmp/tampered-round-provenance-verify.out"

tampered_round_receipt="$tmp/tampered-round-receipt.json"
sed 's/"weights_sha256": "[^"]*"/"weights_sha256": "stale"/' "$round_receipt" >"$tampered_round_receipt"
if "$ROUND" --verify-round-receipt "$tampered_round_receipt" >"$tmp/tampered-round-verify.out" 2>"$tmp/tampered-round-verify.err"; then
  echo "expected tampered round receipt to fail verification" >&2
  exit 1
fi
grep -q '^round_receipt_ok=false$' "$tmp/tampered-round-verify.out"
grep -q '^round_receipt_artifact_hashes_ok=false$' "$tmp/tampered-round-verify.out"

if "$ROUND" --verify-round-receipt "$tmp/missing-round-receipt.json" >"$tmp/missing-round-verify.out" 2>"$tmp/missing-round-verify.err"; then
  echo "expected missing round receipt to fail verification" >&2
  exit 1
fi
grep -q '^round_receipt_exists=false$' "$tmp/missing-round-verify.out"
grep -q '^round_receipt_ok=false$' "$tmp/missing-round-verify.out"
grep -q '^no_model_run=true$' "$tmp/missing-round-verify.out"
grep -q '^no_scorer_run=true$' "$tmp/missing-round-verify.out"
grep -q '"ready_to_run": true' "$outroot/round-contract/preflight.json"
grep -q '"no_model_run": true' "$outroot/round-contract/preflight.json"
grep -q '"no_scorer_run": true' "$outroot/round-contract/preflight.json"

test -x "$ROUND"
grep -q 'run_frontier_baseline.sh' "$ROUND"
grep -q 'run_elevation_stream.sh' "$ROUND"
grep -q 'DEEPSEEK_API_KEY' "$ROUND"
grep -q 'elevation_pro_suite_manifest.json' "$ROUND"
if grep -q '/tmp/.atomic_creds.sh' "$ROUND"; then
  echo "Pro round runner must not source credential files; use env only" >&2
  exit 1
fi

echo "Pro elevation round runner contract ok"
