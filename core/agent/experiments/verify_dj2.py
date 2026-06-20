import json, modal, shlex, re
from datasets import load_dataset
from swebench.harness.test_spec.test_spec import make_test_spec
from swebench.harness.constants import MAP_REPO_VERSION_TO_SPECS
from swebench.harness.log_parsers import MAP_REPO_TO_PARSER
import swe_modal_agent as S
iid="django__django-10097"
ds=load_dataset("princeton-nlp/SWE-bench_Verified",split="test")
inst=next(dict(r) for r in ds if r["instance_id"]==iid)
ts=make_test_spec(inst)
f2p=json.loads(inst["FAIL_TO_PASS"]); p2p=json.loads(inst["PASS_TO_PASS"])
tc=MAP_REPO_VERSION_TO_SPECS[inst["repo"]][inst["version"]]["test_cmd"]
parser=MAP_REPO_TO_PARSER[inst["repo"]]
def label(tid):  # 'method (module.Class)' -> 'module.Class' (runtests runs the class)
    m=re.search(r'\(([^)]+)\)\s*$',tid); return m.group(1) if m else tid.split('::')[0]
labels=sorted(set(label(t) for t in f2p+p2p))
print(f"f2p={len(f2p)} p2p={len(p2p)} -> {len(labels)} unique class labels to run")
sb=modal.Sandbox.create("sleep","infinity",image=S.build_instance_image(ts),app=S.APP,timeout=1800,cpu=2,memory=8192)
try:
    S.sb_write(sb,"/tmp/tp.diff",inst["test_patch"]); S.sb_write(sb,"/tmp/gold.diff",inst["patch"])
    S.sb_write(sb,"/tmp/run.sh", tc+" "+" ".join(shlex.quote(l) for l in labels))
    S.sbexec(sb,f"{S.CONDA} && git config user.email a@b.c && git config user.name a && git apply /tmp/tp.diff && git add -A && git commit -q -m tp")
    S.sbexec(sb,f"{S.CONDA} && git apply /tmp/gold.diff")
    out,rc=S.sbexec(sb,f"{S.CONDA} && bash /tmp/run.sh")
    status=parser(out, ts)
    f2p_ok=all(status.get(t)=="PASSED" for t in f2p); p2p_ok=all(status.get(t)=="PASSED" for t in p2p)
    print("parsed statuses:", len(status), "| f2p PASSED:", sum(status.get(t)=="PASSED" for t in f2p),"/",len(f2p),"| p2p PASSED:", sum(status.get(t)=="PASSED" for t in p2p),"/",len(p2p))
    print("=== GOLD com parser+módulos: f2p_ok",f2p_ok,"p2p_ok",p2p_ok,"-> PAREDE REMOVÍVEL?", f2p_ok and p2p_ok,"===")
finally: sb.terminate()
