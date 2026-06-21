#!/usr/bin/env bash
# swe_diagnose.sh <container> <taskdir> — run the FAIL_TO_PASS test on the UNMODIFIED tree in the instance's
# real env and capture the failing traceback. This is the localization anchor any developer sees first;
# the atomic agent gets it up front so it can localize without blindly exploring (generalist: any
# failing-test task). Resets /testbed afterward (warm container stays pristine).
set -uo pipefail
CONT="${1:?container}"; TD="${2:?taskdir}"; CENV="${SWE_CONDA_ENV:-testbed}"
F2P="$(python3 -c "import json;print(' '.join(json.load(open('$TD/meta.json'))['FAIL_TO_PASS']))")"
docker cp "$TD/.gold/test_patch.diff" "$CONT":/tmp/test.diff >/dev/null 2>&1
docker exec "$CONT" bash -lc "
cd /testbed || exit 9
git checkout -- . >/dev/null 2>&1; git clean -fdq >/dev/null 2>&1 || true
git apply /tmp/test.diff >/dev/null 2>&1 || git apply --3way /tmp/test.diff >/dev/null 2>&1 || true
source /opt/miniconda3/bin/activate $CENV >/dev/null 2>&1 || source activate $CENV >/dev/null 2>&1 || true
python -m pytest -p no:cacheprovider -q $F2P 2>&1 | tail -40
git checkout -- . >/dev/null 2>&1; git clean -fdq >/dev/null 2>&1 || true
"
