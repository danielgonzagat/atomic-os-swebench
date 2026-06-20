"""Find WHERE pylint-7277's image setup breaks — run setup_env + install_repo step-by-step in a
base sandbox, capturing the exact failing command (Modal cached the failed image, so we rebuild raw)."""
import modal
modal.enable_output()
from datasets import load_dataset
from swebench.harness.test_spec.test_spec import make_test_spec
ds=load_dataset("princeton-nlp/SWE-bench_Verified",split="test")
inst=next(r for r in ds if r["instance_id"]=="pylint-dev__pylint-7277")
ts=make_test_spec(inst)
print("=== setup_env_script ===")
print(ts.setup_env_script[:1500])
print("\n=== install_repo_script ===")
print(ts.install_repo_script[:1500])
print("\n=== ENV info ===")
print("repo:", inst["repo"], "version:", inst["version"], "base_commit:", inst["base_commit"][:12])
# pip packages / python version requested
import re
for pat in ["python=", "PYTHON_VERSION", "pip install", "conda create", "setuptools", "astroid"]:
    for l in (ts.setup_env_script+ts.install_repo_script).splitlines():
        if pat in l: print(f"  [{pat}] {l.strip()[:120]}")
