import modal
modal.enable_output()
APP=modal.App.lookup("swe-agent-parallel", create_if_missing=True)
# swebench normaliza __ -> _1776_ na tag do Docker Hub
key="pylint-dev__pylint-7277"
norm=key.replace("__","_1776_")
candidates=[
    f"docker.io/swebench/sweb.eval.x86_64.{norm}:latest",
    f"swebench/sweb.eval.x86_64.{norm}:latest",
    f"docker.io/swebench/sweb.eval.x86_64.{key}:latest",
]
for c in candidates:
    print(f"=== tentando {c} ===")
    try:
        img=modal.Image.from_registry(c)
        sb=modal.Sandbox.create("bash","-lc","cd /testbed && git rev-parse HEAD && echo PREBUILT_OK", image=img, app=APP, timeout=300)
        for l in sb.stdout: print("OUT:", l)
        sb.wait(); print("rc:", sb.returncode); sb.terminate()
        if sb.returncode==0: print(f"!!! WORKS: {c}"); break
    except Exception as e:
        print("  falhou:", str(e)[:150])
