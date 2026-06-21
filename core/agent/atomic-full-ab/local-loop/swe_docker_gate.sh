#!/usr/bin/env bash
# swe_docker_gate.sh <workdir> <taskdir> — TEST-FEEDBACK gate via a WARM container of the instance image.
#
# Faithful env (the instance's own conda env), fast (container stays warm across calls). Per call:
#   1. copy the arm's CURRENT source diff + the hidden test_patch into the container
#   2. reset /testbed, apply arm diff, apply test_patch (adds the F2P test), run F2P+P2P sample
#   3. reset /testbed (leave the warm container pristine for the next call)
# The arm never sees/edits the tests (no leak); the arm's host working tree is untouched.
# Emits node-style markers (# tests/# pass/# fail) parsed by local_atomic_agent.py; exit = pytest rc.
#
# Env: SWE_CONTAINER (warm container name, required), SWE_P2P_SAMPLE (default 15), SWE_CONDA_ENV (testbed)
set -uo pipefail
WD="$1"; TD="$2"
CONT="${SWE_CONTAINER:?set SWE_CONTAINER}"
META="$TD/meta.json"; TP="$TD/.gold/test_patch.diff"
CENV="${SWE_CONDA_ENV:-testbed}"

diff="$(cd "$WD" && git diff HEAD)"
if [ -z "$diff" ]; then echo "(empty diff — make an edit first, then test)"; echo "# tests 0"; echo "# pass 0"; echo "# fail 1"; exit 1; fi

TARGETS=""
while IFS= read -r l; do [ -n "$l" ] && TARGETS="$TARGETS $l"; done < <(python3 - "$META" "${SWE_P2P_SAMPLE:-15}" <<'PY'
import json,sys,re
m=json.load(open(sys.argv[1])); n=int(sys.argv[2])
# Keep only real pytest node ids; drop dataset junk like "[100%]" progress artifacts in PASS_TO_PASS.
def ok(t):
    t=t.strip()
    if not t or re.match(r'^\[\d+%\]$', t): return False
    return ("::" in t) or t.endswith(".py")
print("\n".join(t for t in (m["FAIL_TO_PASS"] + m["PASS_TO_PASS"][:n]) if ok(t)))
PY
)

tmpd="$(mktemp -d)"; printf '%s\n' "$diff" > "$tmpd/arm.diff"; cp "$TP" "$tmpd/test.diff" 2>/dev/null || true
docker cp "$tmpd/arm.diff" "$CONT":/tmp/arm.diff >/dev/null 2>&1
docker cp "$tmpd/test.diff" "$CONT":/tmp/test.diff >/dev/null 2>&1
rm -rf "$tmpd"

out="$(docker exec "$CONT" bash -lc "
cd /testbed || exit 9
git checkout -- . >/dev/null 2>&1; git clean -fdq >/dev/null 2>&1 || true
git apply /tmp/arm.diff 2>/tmp/aerr || { echo ARM_PATCH_FAILED; sed -n '1,5p' /tmp/aerr; git checkout -- . >/dev/null 2>&1; exit 3; }
git apply /tmp/test.diff >/dev/null 2>&1 || git apply --3way /tmp/test.diff >/dev/null 2>&1 || true
source /opt/miniconda3/bin/activate $CENV >/dev/null 2>&1 || source activate $CENV >/dev/null 2>&1 || true
python -m pytest -p no:cacheprovider -q $TARGETS 2>&1 | tail -12
rc=\${PIPESTATUS[0]}
git checkout -- . >/dev/null 2>&1; git clean -fdq >/dev/null 2>&1 || true
exit \$rc
")"
rc=$?
echo "$out" | grep -vE '^\s*$' | tail -10
passed=$(echo "$out" | grep -oE "[0-9]+ passed" | grep -oE "[0-9]+" | head -1); passed=${passed:-0}
failed=$(echo "$out" | grep -oE "[0-9]+ (failed|error)" | grep -oE "[0-9]+" | head -1); failed=${failed:-0}
ntargets=$(echo "$TARGETS" | wc -w | tr -d ' ')
echo "# tests ${ntargets}"
echo "# pass ${passed}"
echo "# fail ${failed}"
exit $rc
