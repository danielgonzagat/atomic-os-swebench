"""Run pylint-7277's setup_env in a RAW base sandbox (miniconda image, no pre-baked setup) and
capture the exact failing command/output — bypasses Modal's cached-failed image entirely."""
import modal, os, tempfile
modal.enable_output()
from datasets import load_dataset
from swebench.harness.test_spec.test_spec import make_test_spec
APP=modal.App.lookup("swe-agent-parallel", create_if_missing=True)
ds=load_dataset("princeton-nlp/SWE-bench_Verified",split="test")
inst=next(r for r in ds if r["instance_id"]=="pylint-dev__pylint-7277")
ts=make_test_spec(inst)
# base image: ubuntu+miniconda ONLY (the part that builds fine for every other instance)
base=(modal.Image.from_registry("ubuntu:22.04", add_python="3.11")
    .run_commands("apt update").env({"DEBIAN_FRONTEND":"noninteractive","TZ":"Etc/UTC"})
    .apt_install("wget","git","build-essential","libffi-dev","libtiff-dev","jq","curl","locales","locales-all","tzdata")
    .run_commands(
        "wget 'https://repo.anaconda.com/miniconda/Miniconda3-py311_23.11.0-2-Linux-x86_64.sh' -O miniconda.sh",
        "bash miniconda.sh -b -p /opt/miniconda3",
        "/opt/miniconda3/bin/conda init --all",
        "/opt/miniconda3/bin/conda config --append channels conda-forge"))
sb=modal.Sandbox.create("sleep","infinity",image=base,app=APP,timeout=1800,cpu=4,memory=8192)
try:
    env=ts.setup_env_script.replace("python -m pip install -r $HOME/requirements.txt",
        "python -m pip install -r $HOME/requirements.txt --trusted-host pypi-mirror.modal.local")
    with sb.open("/tmp/setup_env.sh","w") as f: f.write(env)
    print("=== running setup_env.sh in raw sandbox (this is what breaks the build) ===")
    p=sb.exec("bash","-lc","source ~/.bashrc 2>/dev/null; bash -x /tmp/setup_env.sh 2>&1 | tail -80")
    out=p.stdout.read()
    print(out if isinstance(out,str) else out.decode('utf-8','replace'))
    p.wait()
    print("=== setup_env exit code:", p.returncode, "===")
finally:
    sb.terminate()
