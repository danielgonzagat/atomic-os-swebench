#!/usr/bin/env python3
"""Live reproduction of the django runner wall.
Boots the harness sandbox for one django instance, applies the GOLD patch, and runs the
harness's OWN run_f2p script. If target stays F *with the gold fix applied*, the harness test
command is broken (the wall is mine, not the model's). Compares per-method (current harness) vs
per-module (official directive) invocation."""
import json, re, shlex
from datasets import load_dataset
from swebench.harness.test_spec.test_spec import make_test_spec
from swebench.harness.constants import MAP_REPO_VERSION_TO_SPECS
from swebench.harness.test_spec.python import get_test_directives
import modal
from swe_modal_agent import build_instance_image, sb_write, sbexec, fmt_test_id, CONDA, APP

IID = "django__django-10914"  # small-ish; target=F forever, 98 run_tests in the live run

ds = load_dataset("princeton-nlp/SWE-bench_Verified", split="test")
inst = next(r for r in ds if r["instance_id"] == IID)
repo, ver = inst["repo"], inst["version"]
test_cmd = MAP_REPO_VERSION_TO_SPECS[repo][ver]["test_cmd"]
f2p = json.loads(inst["FAIL_TO_PASS"]) if isinstance(inst["FAIL_TO_PASS"], str) else inst["FAIL_TO_PASS"]

mine_ids = [fmt_test_id(t) for t in f2p]
official_modules = get_test_directives(inst)
print("test_cmd          :", test_cmd)
print("f2p count         :", len(f2p))
print("MY per-method ids :", mine_ids[:3], "...")
print("OFFICIAL modules  :", official_modules)

ts = make_test_spec(inst)
img = build_instance_image(ts)
sb = modal.Sandbox.create("sleep", "infinity", image=img, app=APP, timeout=3600, cpu=2, memory=4096)
try:
    sb_write(sb, "/tmp/tp.diff", inst["test_patch"])
    sb_write(sb, "/tmp/gold.diff", inst["patch"])
    sbexec(sb, f"{CONDA} && git config user.email a@b.c && git config user.name a && git apply /tmp/tp.diff && git add -A && git commit -q -m tp")

    # build both invocations
    mine_cmd = f"{test_cmd} " + " ".join(shlex.quote(x) for x in mine_ids)
    off_cmd  = f"{test_cmd} " + " ".join(shlex.quote(x) for x in official_modules)

    def run(label, cmd):
        out, rc = sbexec(sb, f"{CONDA} && {cmd}")
        tail = "\n".join(out.splitlines()[-12:])
        print(f"\n===== {label} | rc={rc} =====\n{tail}")
        return rc

    print("\n########## BEFORE GOLD (bug present) ##########")
    rc_mine_before = run("MINE per-method  BEFORE", mine_cmd)
    rc_off_before  = run("OFFICIAL module  BEFORE", off_cmd)

    print("\n########## applying GOLD patch ##########")
    ap, _ = sbexec(sb, f"{CONDA} && git apply /tmp/gold.diff && echo APPLIED_OK")
    print(ap.strip()[-200:])

    print("\n########## AFTER GOLD (fix applied — should be PASS) ##########")
    rc_mine_after = run("MINE per-method  AFTER ", mine_cmd)
    rc_off_after  = run("OFFICIAL module  AFTER ", off_cmd)

    print("\n================= VERDICT =================")
    print(f"MINE  (per-method): before rc={rc_mine_before}  after rc={rc_mine_after}  -> {'✅ flips to PASS' if rc_mine_after==0 and rc_mine_before!=0 else '❌ BROKEN (never measures the fix)'}")
    print(f"OFFICIAL (module) : before rc={rc_off_before}  after rc={rc_off_after}  -> {'✅ flips to PASS' if rc_off_after==0 and rc_off_before!=0 else '❌ broken'}")
finally:
    sb.terminate()
