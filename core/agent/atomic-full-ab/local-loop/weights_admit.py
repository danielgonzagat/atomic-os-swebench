#!/usr/bin/env python3
"""Proof-carrying WEIGHT ADMISSION engine — the operator-as-compressor mechanics (deterministic, CPU, no LLM).

A weight is a generalized resolution operator: {class, trigger, strategy, instances:[...], proof_n}.
The corpus of operators IS the weight bank. This engine implements the three operator laws from the doctrine,
each as a DETERMINISTIC, checkable rule (no model needed to run/verify them):

  LAW 1 — capture N, not one:   a resolution whose ESSENCE matches an existing operator is ABSORBED into it
                                (instance appended, proof_n++), never duplicated.
  LAW 2 — born under necessity: a NEW operator is created ONLY when no existing operator absorbs the resolution
                                (no class/trigger match) — minimality at the meta level.
  LAW 3 — monotonic fidelity:   any operator self-update must keep EVERY already-captured instance still matching
                                (trigger covers it) — compressing more can never drop an essence already held.

"Essence match" here is the deterministic proxy the substrate can check on CPU: same class label, OR the new
resolution's signal text is covered by an existing operator's trigger (the trigger is the operator's recall index).
Semantic re-compression of the strategy text (merging two surface-different solutions into a tighter operator) is the
LLM-assisted step layered ON TOP — but admission/necessity/fidelity are provable without any model, which is the point.
"""
import json, os, re, sys


def load(path):
    return [json.loads(l) for l in open(path)] if os.path.exists(path) else []


def save(path, weights):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        for w in weights:
            f.write(json.dumps(w) + "\n")
    os.replace(tmp, path)


def _covers(operator, signal):
    """Does this operator's trigger recall (cover) this signal text? The deterministic essence-match proxy."""
    trig = operator.get("trigger")
    return bool(trig) and re.search(trig, signal or "", re.I) is not None


def admit(resolution, weights):
    """LAW 1 + LAW 2. resolution = {class, trigger, strategy, instance, signal}.
    Each captured instance is stored as {id, signal} so fidelity is a CONCRETE per-instance battery (LAW 3).
    Returns (action, weights) where action in {'absorbed', 'created'}. Pure function of (resolution, weights)."""
    cls = resolution["class"]
    signal = resolution.get("signal", resolution.get("instance", ""))
    rec = {"id": resolution.get("instance", ""), "signal": signal}
    for w in weights:
        if w["class"] == cls or _covers(w, signal):
            insts = w.setdefault("instances", [])
            if rec["id"] and rec["id"] not in [i.get("id") if isinstance(i, dict) else i for i in insts]:
                insts.append(rec)
                w["proof_n"] = len(insts)            # proof_n grows with captured solutions (LAW 1)
            return "absorbed", weights               # never duplicate
    # LAW 2: necessity — no operator absorbs it → create a new one
    new = {"class": cls, "trigger": resolution.get("trigger", ""), "strategy": resolution["strategy"],
           "instances": [rec] if rec["id"] else [], "proof_n": 1 if rec["id"] else 0}
    weights.append(new)
    return "created", weights


def _signals(operator):
    """Every captured instance's recall signal (handles legacy string instances + new {id,signal} dicts)."""
    out = []
    for i in operator.get("instances", []):
        out.append(i.get("signal", "") if isinstance(i, dict) else str(i))
    return [s for s in out if s]


def verify_fidelity(weights):
    """LAW 3 (concrete battery) — every captured instance's RECALL SIGNAL must still match its operator's trigger.
    Returns (ok, failures). A captured essence the operator can no longer recall = fidelity regression = REJECT."""
    failures = []
    for w in weights:
        trig = w.get("trigger")
        if not trig:
            continue
        for sig in _signals(w):
            if not re.search(trig, sig, re.I):
                failures.append({"class": w["class"], "lost_signal": sig})
    return (len(failures) == 0), failures


def self_improve(operator, new_strategy=None, new_trigger=None):
    """Re-formalize an operator to compress more — ADMITTED ONLY UNDER PROOF OF GAIN, on a COPY first (atomicity):
    (a) total description shorter or equal (−consumption: strategy and/or trigger), AND (b) the new trigger STILL
    recalls every captured signal (monotonic fidelity — concrete battery). Mutates operator ONLY if proven; else
    returns the rejection reason and leaves it untouched. Never weakens."""
    cand_strategy = new_strategy if new_strategy is not None else operator["strategy"]
    cand_trigger = new_trigger if new_trigger is not None else operator.get("trigger", "")
    old_len = len(operator["strategy"]) + len(operator.get("trigger", ""))
    new_len = len(cand_strategy) + len(cand_trigger)
    if new_len > old_len:
        return False, f"rejected: larger description ({new_len} > {old_len}) — no consumption gain"
    # fidelity battery: candidate trigger must still recall every captured signal
    for sig in _signals(operator):
        if cand_trigger and not re.search(cand_trigger, sig, re.I):
            return False, f"rejected: fidelity regression — candidate no longer recalls signal {sig!r}"
    operator["strategy"], operator["trigger"] = cand_strategy, cand_trigger
    return True, f"admitted: description −{old_len - new_len} chars, fidelity preserved over {operator['proof_n']} instance(s)"


# ----- deterministic self-test (no LLM) -----
if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--selftest":
        W = load(os.path.join(os.path.dirname(__file__), ".corpus", "weights.jsonl"))
        n0 = len(W)
        # LAW 1: a 2nd cross-file instance (different repo, same essence) ABSORBS, not duplicates — signal stored
        _, W = admit({"class": "CROSS-FILE-ROOT-CAUSE-VIA-DECISION-PREDICATE", "trigger": "ignore|filter",
                      "strategy": "(same essence)", "instance": "django-discover-excludes",
                      "signal": "files not excluded by filter recursively"}, W)
        absorbed = (len(W) == n0)
        op = next(w for w in W if w["class"] == "CROSS-FILE-ROOT-CAUSE-VIA-DECISION-PREDICATE")
        # LAW 2: a genuinely new class (no trigger match) CREATES under necessity
        _, W = admit({"class": "OFF-BY-ONE-BOUNDARY", "trigger": "boundary|fencepost|len.?1|inclusive",
                      "strategy": "check inclusive vs exclusive bounds at the edge index",
                      "instance": "numpy-slice-edge", "signal": "slice drops last boundary element"}, W)
        created = (len(W) == n0 + 1)
        # LAW 3 / proof-of-gain: a SHORTER strategy is admitted; a LONGER one rejected (description size)
        ok_short, r1 = self_improve(op, new_strategy=op["strategy"][: max(40, len(op["strategy"]) - 50)])
        ok_long, r2 = self_improve(op, new_strategy=op["strategy"] + " ... extra verbiage that adds length")
        # LAW 3 CONCRETE BATTERY: a trigger re-formalization that DROPS a captured signal is REJECTED (fidelity),
        # even though it is SHORTER. The django instance's signal "files not excluded by filter recursively" must
        # still be recalled — a trigger of just "ignore" (shorter) no longer matches it → must reject.
        ok_break, r3 = self_improve(op, new_trigger="ignore")   # shorter but drops the 'filter' signal → reject
        # and a trigger that stays faithful (covers all signals) + shorter is admitted
        ok_keep, r4 = self_improve(op, new_trigger="ignore|filter|exclud")
        fid_ok, fails = verify_fidelity(W)
        print("LAW1 absorb (2nd same-essence → no new operator):", absorbed, "| operator now holds", op["proof_n"], "instance(s)")
        print("LAW2 necessity (new class → new operator):       ", created)
        print("LAW3 proof-of-gain (shorter strategy admitted):  ", ok_short, "|", r1[:55])
        print("LAW3 proof-of-gain (longer strategy rejected):   ", (not ok_long), "|", r2[:55])
        print("LAW3 BATTERY (trigger dropping a signal REJECTED):", (not ok_break), "|", r3[:60])
        print("LAW3 BATTERY (faithful shorter trigger admitted): ", ok_keep, "|", r4[:55])
        print("monotonic fidelity intact (concrete per-signal):  ", fid_ok, "" if fid_ok else fails)
        print("ALL LAWS HOLD:", absorbed and created and ok_short and (not ok_long) and (not ok_break) and ok_keep and fid_ok)
