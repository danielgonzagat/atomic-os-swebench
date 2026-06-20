import json, modal, shlex
from datasets import load_dataset
from swebench.harness.test_spec.test_spec import make_test_spec
from swebench.harness.constants import MAP_REPO_VERSION_TO_SPECS
import swe_modal_agent as S
iid="django__django-10097"
ds=load_dataset("princeton-nlp/SWE-bench_Verified",split="test")
inst=next(dict(r) for r in ds if r["instance_id"]==iid)
ts=make_test_spec(inst)
f2p=json.loads(inst["FAIL_TO_PASS"]) if isinstance(inst["FAIL_TO_PASS"],str) else inst["FAIL_TO_PASS"]
tc=MAP_REPO_VERSION_TO_SPECS[inst["repo"]][inst["version"]]["test_cmd"]
print("test_cmd:",tc,"| f2p[0]:",f2p[0])
sb=modal.Sandbox.create("sleep","infinity",image=S.build_instance_image(ts),app=S.APP,timeout=1800,cpu=2,memory=4096)
try:
    S.sb_write(sb,"/tmp/tp.diff",inst["test_patch"]); S.sb_write(sb,"/tmp/gold.diff",inst["patch"])
    S.sb_write(sb,"/tmp/run.sh",f"{tc} "+" ".join(shlex.quote(S.fmt_test_id(t)) for t in f2p))
    S.sbexec(sb,f"{S.CONDA} && git config user.email a@b.c && git config user.name a && git apply /tmp/tp.diff && git add -A && git commit -q -m tp")
    ob,rb=S.sbexec(sb,f"{S.CONDA} && bash /tmp/run.sh"); print("BASE rc=",rb,"(want !=0)"); print(ob[-400:])
    S.sbexec(sb,f"{S.CONDA} && git apply /tmp/gold.diff")
    og,rg=S.sbexec(sb,f"{S.CONDA} && bash /tmp/run.sh"); print("GOLD rc=",rg,"(want 0)"); print(og[-400:])
    print("=== VERDICT: test_cmd VÁLIDO?", (rb!=0 and rg==0), "===")
finally: sb.terminate()
