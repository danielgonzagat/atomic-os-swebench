#!/usr/bin/env bash
# swe_gate.sh — LOCAL feedback gate for a SWE-bench instance (used as --gate for both arms).
#
# Runs the instance's FAIL_TO_PASS + (a sample of) PASS_TO_PASS in a prepared venv, against the arm's
# CURRENT working tree. The hidden test_patch is applied TRANSIENTLY (added tests), then reverted, so:
#   - the arm never sees or edits the tests (no leak, can't game the gate)
#   - the arm's git diff stays SOURCE-ONLY (becomes the model_patch for the authoritative Docker gate)
# Emits node-style markers (# tests/# pass/# fail) that local_atomic_agent.py already parses, and exits
# with pytest's return code (0 only when every target passed).
#
# Usage: swe_gate.sh <workdir> <taskdir>   (env: SWE_VENV=/path/to/venv, SWE_P2P_SAMPLE=20)
set -uo pipefail
WD="$1"; TD="$2"
VENV="${SWE_VENV:-/tmp/swe/flask-venv}"
PY="$VENV/bin/python"
TP="$TD/.gold/test_patch.diff"
cd "$WD" || { echo "# tests 0"; echo "# pass 0"; echo "# fail 1"; exit 1; }

applied=0
revert() { [ "$applied" = "1" ] && git apply -R "$TP" 2>/dev/null; }
trap revert EXIT
if [ -f "$TP" ] && git apply --check "$TP" 2>/dev/null; then
  git apply "$TP" && applied=1
fi

TARGETS=()
while IFS= read -r line; do [ -n "$line" ] && TARGETS+=("$line"); done < <("$PY" - "$TD/meta.json" "${SWE_P2P_SAMPLE:-20}" <<'PYEOF'
import json,sys
m=json.load(open(sys.argv[1])); n=int(sys.argv[2])
print("\n".join(m["FAIL_TO_PASS"] + m["PASS_TO_PASS"][:n]))
PYEOF
)
out="$("$PY" -m pytest -p no:cacheprovider -q --no-header "${TARGETS[@]}" 2>&1)"
rc=$?
echo "$out" | tail -6
passed=$(echo "$out" | grep -oE "[0-9]+ passed" | grep -oE "[0-9]+" | head -1); passed=${passed:-0}
failed=$(echo "$out" | grep -oE "[0-9]+ (failed|error)" | grep -oE "[0-9]+" | head -1); failed=${failed:-0}
echo "# tests $(( ${#TARGETS[@]} ))"
echo "# pass ${passed}"
echo "# fail ${failed}"
exit $rc
