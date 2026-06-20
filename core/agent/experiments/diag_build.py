"""Diagnose pylint-7277 image build wall — force rebuild with output visible."""
import modal
modal.enable_output()  # surface build logs
from datasets import load_dataset
from swebench.harness.test_spec.test_spec import make_test_spec
from swe_modal_agent import build_instance_image, APP
ds=load_dataset("princeton-nlp/SWE-bench_Verified",split="test")
inst=next(r for r in ds if r["instance_id"]=="pylint-dev__pylint-7277")
ts=make_test_spec(inst)
print("=== forcing image build for pylint-7277 (output visible) ===")
img=build_instance_image(ts)
try:
    sb=modal.Sandbox.create("bash","-lc","echo BUILD_OK && python --version", image=img, app=APP, timeout=600)
    for line in sb.stdout: print("OUT:", line)
    sb.wait(); print("=== BUILD SUCCEEDED ===")
    sb.terminate()
except Exception as e:
    print("=== BUILD FAILED ===", str(e)[:500])
