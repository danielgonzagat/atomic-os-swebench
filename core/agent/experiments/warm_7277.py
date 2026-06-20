import os; os.environ["FORCE_BUILD"]="1"
import modal
from datasets import load_dataset
from swebench.harness.test_spec.test_spec import make_test_spec
from swe_modal_agent import build_instance_image, APP
ds=load_dataset("princeton-nlp/SWE-bench_Verified",split="test")
inst=next(r for r in ds if r["instance_id"]=="pylint-dev__pylint-7277")
img=build_instance_image(make_test_spec(inst))
print("=== rebuilding pylint-7277 image from scratch (cache-bust) ===")
sb=modal.Sandbox.create("bash","-lc","cd /testbed && git rev-parse HEAD && python --version && echo BUILD_OK", image=img, app=APP, timeout=600)
for line in sb.stdout: print("OUT:", line)
sb.wait(); print("=== rc:", sb.returncode, "==="); sb.terminate()
