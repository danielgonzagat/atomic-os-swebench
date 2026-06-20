#!/usr/bin/env python3
"""Analyze the OFF-fail A/B: edit-landing + resolve rates, per-instance table, recoveries.

Reads the two .detail JSON arrays (preds-off21 / preds-on21) plus the two run logs,
and emits the honest comparison the mission asks for.
"""
import json, re, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
IDS = [l.strip() for l in Path("/tmp/off_fail_ids.txt").read_text().splitlines() if l.strip()]

def load_detail(p):
    p = Path(p)
    if not p.exists():
        return {}
    data = json.loads(p.read_text())
    return {d["instance_id"]: d for d in data if "instance_id" in d}

def landed(d):
    return bool((d.get("model_patch") or "").strip())

def resolved(d):
    return d.get("local_pass") is True

def gov_fired(iid, logtext):
    # governance refusals that are ATOMIC-specific
    block = "\n".join(l for l in logtext.splitlines() if l.startswith(f"[{iid}]"))
    neg = len(re.findall(r"REFUSED \(atomic governance\)", block))
    syn = len(re.findall(r"REFUSED \(atomic syntax guard\)", block))
    adm = len(re.findall(r"negative-bytes admitted", block))
    return neg, syn, adm, block

def node_ok(iid, logtext):
    block = "\n".join(l for l in logtext.splitlines() if l.startswith(f"[{iid}]"))
    if "headless-edit bundle staged + selftest GREEN" in block:
        return "OK"
    if "ATOMIC_PROVISION" in block:
        return "PROVISION_FAIL"
    if "atomic: node" in block or "installing nodejs" in block:
        return "PARTIAL"
    return "?"

def main():
    off = load_detail(HERE / "preds-off21.jsonl.detail")
    on  = load_detail(HERE / "preds-on21.jsonl.detail")
    off_log = (HERE / "../logs/off21.log").read_text(errors="replace") if (HERE/"../logs/off21.log").exists() else ""
    on_log  = (HERE / "../logs/on21.log").read_text(errors="replace") if (HERE/"../logs/on21.log").exists() else ""

    print(f"{'id':40s} | OFF land res st | ON  land res st gov node")
    print("-"*100)
    off_land=off_res=on_land=on_res=0
    recoveries=[]; regressions=[]; on_noredo=[]
    rows=[]
    for iid in IDS:
        o=off.get(iid,{}); n=on.get(iid,{})
        ol=landed(o); orr=resolved(o); ost=o.get("steps","-")
        nl=landed(n); nr=resolved(n); nst=n.get("steps","-")
        neg,syn,adm,_=gov_fired(iid,on_log); nok=node_ok(iid,on_log)
        gov = f"{neg}N/{syn}S/{adm}A" if (neg+syn+adm) else "-"
        off_land+=ol; off_res+=orr; on_land+=nl; on_res+=nr
        if nr and not orr: recoveries.append(iid)
        if orr and not nr: regressions.append(iid)
        if not nr:
            cls = "still-empty" if not nl else ("landed-wrong" if nl else "?")
            if nok in ("PROVISION_FAIL","PARTIAL","?") and not nl and n.get("error"):
                cls = "infra/" + nok
            on_noredo.append((iid,cls,n.get("error","")[:60]))
        oerr = (o.get("error","") or "")[:30]
        nerr = (n.get("error","") or "")[:30]
        rows.append((iid,ol,orr,ost,nl,nr,nst,gov,nok,oerr,nerr))
        print(f"{iid:40s} | {'Y' if ol else '.':>4s} {'Y' if orr else '.':>3s} {str(ost):>2s} | {'Y' if nl else '.':>4s} {'Y' if nr else '.':>3s} {str(nst):>2s} {gov:>7s} {nok}")

    n=len(IDS)
    print("\n=== RATES ===")
    print(f"EDIT-LANDING: OFF {off_land}/{n}  vs  ON {on_land}/{n}")
    print(f"RESOLVE:      OFF {off_res}/{n}  vs  ON {on_res}/{n}")
    print(f"\nRECOVERIES (ON resolved, OFF did not): {recoveries or 'NONE'}")
    print(f"REGRESSIONS (OFF resolved/landed, ON did not resolve): {regressions or 'NONE'}")
    print(f"\nON non-recoveries classified:")
    for iid,cls,err in on_noredo:
        print(f"  {iid:40s} {cls:18s} {err}")

    Path(HERE/"ab-summary.json").write_text(json.dumps({
        "n":n,"off_land":off_land,"off_res":off_res,"on_land":on_land,"on_res":on_res,
        "recoveries":recoveries,"regressions":regressions,
        "rows":[dict(zip(["id","off_land","off_res","off_steps","on_land","on_res","on_steps","gov","node","off_err","on_err"],r)) for r in rows]
    },indent=1))
    print(f"\nwrote {HERE/'ab-summary.json'}")

if __name__=="__main__":
    main()
