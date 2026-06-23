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
import hashlib, json, os, re, sys


# --- VSA (Vector Symbolic Architecture) Hyperdimensional Computing Substrate ---
def _get_char_vector(char, D=1024):
    """Deterministic random D-dimensional bipolar vector (+1/-1) for a character."""
    h = hashlib.sha256(char.encode('utf-8')).digest()
    import random
    seed = int.from_bytes(h, 'big')
    state = random.getstate()
    random.seed(seed)
    v = [random.choice([1, -1]) for _ in range(D)]
    random.setstate(state)
    return v


def encode_vsa_text(text, D=1024):
    """Encode a text string into a D-dimensional bipolar hypervector using trigram random projection."""
    if not text:
        return [0] * D
    text = "_" + text.lower().strip() + "_"
    accum = [0] * D
    for i in range(len(text) - 2):
        tg = text[i:i+3]
        v1 = _get_char_vector(tg[0], D)
        v2 = _get_char_vector(tg[1], D)
        v3 = _get_char_vector(tg[2], D)
        # Permute: cyclic shift
        v1_p = v1[2:] + v1[:2]
        v2_p = v2[1:] + v2[:1]
        # Bind: element-wise multiplication
        tg_vec = [x1 * x2 * x3 for x1, x2, x3 in zip(v1_p, v2_p, v3)]
        # Bundle: sum
        accum = [a + b for a, b in zip(accum, tg_vec)]
    # Threshold to bipolar +/-1
    return [1 if x >= 0 else -1 for x in accum]


def vsa_bind(v1, v2):
    """Coordinate-wise multiplication of two hypervectors (bind ⊗)."""
    return [x * y for x, y in zip(v1, v2)]


def vsa_bundle(vectors):
    """Coordinate-wise sum and thresholding of multiple hypervectors (bundle ⊕)."""
    if not vectors:
        return [0] * 1024
    D = len(vectors[0])
    accum = [0] * D
    for v in vectors:
        accum = [a + b for a, b in zip(accum, v)]
    return [1 if x >= 0 else -1 for x in accum]


def vsa_permute(v, shift):
    """Cyclic shift of a hypervector (permute ρ)."""
    shift = shift % len(v)
    return v[shift:] + v[:shift]


def vsa_similarity(v1, v2):
    """Cosine similarity (normalized dot product) between two hypervectors."""
    if not v1 or not v2 or len(v1) != len(v2):
        return 0.0
    dot = sum(x * y for x, y in zip(v1, v2))
    return dot / len(v1)


def reinforce_success(operator, success_signal):
    """Reinforce the operator VSA vector with a successful signal (acerto -> reforça)."""
    if "vsa" not in operator:
        ensure_act(operator)
    sig_vec = encode_vsa_text(success_signal)
    operator["vsa"] = vsa_bundle([operator["vsa"], sig_vec])
    ensure_act(operator, force_vsa_update=False)


def correct_error(operator, error_signal):
    """Correct/subtract the error signal from the operator VSA vector (erro -> corrige)."""
    if "vsa" not in operator:
        ensure_act(operator)
    err_vec = encode_vsa_text(error_signal)
    neg_err_vec = [-x for x in err_vec]
    operator["vsa"] = vsa_bundle([operator["vsa"], neg_err_vec])
    ensure_act(operator, force_vsa_update=False)


ACT_FIELDS = ("preconditions", "transformation", "effects", "cost", "receipt", "fidelity_battery")


def _stable_sha256(obj):
    data = json.dumps(obj, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(data).hexdigest()


def _normalize_instance(inst):
    if isinstance(inst, dict):
        ident = str(inst.get("id", "") or "")
        signal = str(inst.get("signal", "") or ident)
    else:
        ident = str(inst or "")
        signal = ident
    return {"id": ident, "signal": signal}


def _dedupe_battery(entries):
    seen, out = set(), []
    for entry in entries:
        rec = _normalize_instance(entry)
        key = (rec["id"], rec["signal"])
        if key in seen or not (rec["id"] or rec["signal"]):
            continue
        seen.add(key)
        out.append(rec)
    return out


def has_act_schema(operator):
    act = operator.get("act") if isinstance(operator, dict) else None
    return isinstance(act, dict) and all(field in act for field in ACT_FIELDS)


def build_act(operator):
    """Build the first-class ACT envelope for a learned weight.

    The ACT is the executable transfer contract: match the preconditions, apply the learned
    resolution operator, preserve the proof receipt, and keep the concrete fidelity battery.
    Legacy prose weights are wrapped as an executable substrate action (strategy injection +
    verification pressure); weights with an executable spec also carry that deterministic apply path.
    """
    cls = operator.get("class", "")
    trigger = operator.get("trigger", "")
    strategy = operator.get("strategy", "")
    proof_n = int(operator.get("proof_n", 0) or 0)
    instances = _dedupe_battery(operator.get("instances", []))
    existing_act = operator.get("act") if isinstance(operator.get("act"), dict) else {}
    battery = _dedupe_battery(instances + existing_act.get("fidelity_battery", []))
    existing_transformation = existing_act.get("transformation") if isinstance(existing_act.get("transformation"), dict) else {}
    executable = operator.get("executable") or existing_transformation.get("executable")
    transformation = {
        "op": "apply_learned_resolution_operator",
        "class": cls,
        "strategy": strategy,
    }
    if executable:
        transformation["executable"] = executable
    preconditions = [{"kind": "trigger_regex_matches_task", "pattern": trigger}] if trigger else [{"kind": "class_selected", "class": cls}]
    preconditions.append({"kind": "fidelity_battery_available", "min_items": len(battery)})
    effects = [
        {"kind": "inject_learned_strategy", "class": cls},
        {"kind": "require_post_apply_verification", "battery_items": len(battery)},
    ]
    if executable:
        effects.append({"kind": "execute_deterministic_apply_path", "op": executable.get("op", "unknown") if isinstance(executable, dict) else "unknown"})
    cost = {
        "strategy_chars": len(strategy),
        "trigger_chars": len(trigger),
        "proof_n": proof_n,
        "battery_items": len(battery),
    }
    receipt_payload = {
        "class": cls,
        "trigger": trigger,
        "strategy_sha256": hashlib.sha256(strategy.encode("utf-8")).hexdigest(),
        "transformation_sha256": _stable_sha256(transformation),
        "proof_n": proof_n,
        "battery_items": len(battery),
    }
    return {
        "preconditions": preconditions,
        "transformation": transformation,
        "effects": effects,
        "cost": cost,
        "receipt": {"kind": "act-receipt-v1", "sha256": _stable_sha256(receipt_payload), "payload": receipt_payload},
        "fidelity_battery": battery,
        "content": operator.get("vsa"),
    }


def ensure_act(operator, force_vsa_update=False):
    if not isinstance(operator, dict):
        return operator
    operator["instances"] = _dedupe_battery(operator.get("instances", []))
    if operator["instances"]:
        operator["proof_n"] = max(int(operator.get("proof_n", 0) or 0), len(operator["instances"]))
    else:
        operator["proof_n"] = int(operator.get("proof_n", 0) or 0)
    
    # Generate/update VSA content (bipolar D-dimensional hypervector representing essence)
    if "vsa" not in operator or force_vsa_update:
        sigs = _signals(operator)
        if sigs:
            vectors = [encode_vsa_text(s) for s in sigs]
            operator["vsa"] = vsa_bundle(vectors)
        else:
            operator["vsa"] = encode_vsa_text(operator.get("strategy", "") or operator.get("class", ""))
            
    operator["act"] = build_act(operator)
    return operator


def normalize_weights(weights):
    return [ensure_act(w) for w in weights]


def load(path):
    return normalize_weights([json.loads(l) for l in open(path)]) if os.path.exists(path) else []


def save(path, weights):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        for w in normalize_weights(weights):
            f.write(json.dumps(w) + "\n")
    os.replace(tmp, path)


def _covers(operator, signal):
    """Does this operator's trigger recall (cover) this signal text? The deterministic essence-match proxy."""
    trig = operator.get("trigger")
    return bool(trig) and re.search(trig, signal or "", re.I) is not None


def admit(resolution, weights):
    """LAW 1 + LAW 2. resolution = {class, trigger, strategy, instance, signal}.
    Each captured instance is stored as {id, signal} and mirrored into ACT.fidelity_battery (LAW 3).
    Returns (action, weights) where action in {'absorbed', 'created'}. Pure function of (resolution, weights)."""
    weights = normalize_weights(weights)
    cls = resolution["class"]
    signal = resolution.get("signal", resolution.get("instance", ""))
    rec = _normalize_instance({"id": resolution.get("instance", ""), "signal": signal})
    # LAW 1 essence-match is by CLASS LABEL (the semantic identity the model assigns) — NOT trigger overlap. The
    # trigger is a RETRIEVAL index (recall), not an essence identity: two distinct-essence operators (e.g. navigation
    # vs path-normalization) can share trigger tokens, and absorbing on overlap would wrongly merge them. Absorb only
    # on same class; a new class label = a new operator (necessity, LAW 2). Semantic same-essence-different-class
    # merging is the MODEL's job (it re-tags or proposes a compression), verified by admit_merge under proof-of-gain.
    for w in weights:
        if w["class"] == cls:
            insts = w.setdefault("instances", [])
            if rec["id"] and rec["id"] not in [i.get("id") if isinstance(i, dict) else i for i in insts]:
                insts.append(rec)
            ensure_act(w, force_vsa_update=True)       # ACT battery grows and VSA re-bundles captured solutions (LAW 1)
            return "absorbed", weights               # never duplicate
    # LAW 2: necessity — no operator absorbs it → create a new one
    new = {"class": cls, "trigger": resolution.get("trigger", ""), "strategy": resolution["strategy"],
           "instances": [rec] if rec["id"] else [], "proof_n": 1 if rec["id"] else 0}
    if isinstance(resolution.get("executable"), dict):
        new["executable"] = resolution["executable"]
    if isinstance(resolution.get("act"), dict):
        new["act"] = resolution["act"]
    weights.append(ensure_act(new, force_vsa_update=True))
    return "created", weights


def _signals(operator):
    """Every captured instance's recall signal (instances plus ACT.fidelity_battery)."""
    out = []
    for i in operator.get("instances", []):
        rec = _normalize_instance(i)
        out.append(rec["signal"] or rec["id"])
    act = operator.get("act") if isinstance(operator.get("act"), dict) else {}
    for i in act.get("fidelity_battery", []):
        rec = _normalize_instance(i)
        out.append(rec["signal"] or rec["id"])
    return [s for s in dict.fromkeys(out) if s]


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
    ensure_act(operator)
    return True, f"admitted: description −{old_len - new_len} chars, fidelity preserved over {operator['proof_n']} instance(s)"


def compression_candidates(weights, min_shared=2):
    """Detect operator clusters that SHARE ESSENCE (overlapping trigger tokens) — merge candidates (deterministic).
    Returns list of index-lists. The substrate proposes a merge only for these; necessity (LAW 2) keeps the rest split."""
    toks = [set(re.split(r"[|]", w.get("trigger", ""))) - {""} for w in weights]
    clusters, used = [], set()
    for i in range(len(weights)):
        if i in used:
            continue
        grp = [i]
        for j in range(i + 1, len(weights)):
            if j in used:
                continue
            if len(toks[i] & toks[j]) >= min_shared:
                grp.append(j); used.add(j)
        if len(grp) > 1:
            used.add(i); clusters.append(grp)
    return clusters


def admit_merge(members, meta_strategy, meta_trigger, meta_class, weights):
    """LAW 1 at the META level (poucos operadores, cada um cobrindo muito): replace N essence-sharing operators with
    ONE — ADMITTED ONLY UNDER PROOF OF GAIN: (a) the meta's description is SMALLER than the members' combined, AND
    (b) the meta's trigger STILL recalls EVERY captured signal of EVERY member (monotonic fidelity). Atomic: verifies
    on a candidate before mutating. Returns (admitted, proof_or_reason, new_weights)."""
    old_desc = sum(len(m["strategy"]) + len(m.get("trigger", "")) for m in members)
    new_desc = len(meta_strategy) + len(meta_trigger)
    if new_desc >= old_desc:
        return False, f"rejected: not smaller ({new_desc} >= {old_desc})", weights
    all_sigs = [s for m in members for s in _signals(m)]
    for s in all_sigs:
        if not re.search(meta_trigger, s, re.I):
            return False, f"rejected: fidelity regression — meta no longer recalls {s!r}", weights
    insts = [i for m in members for i in m.get("instances", [])]
    meta = ensure_act({"class": meta_class, "trigger": meta_trigger, "strategy": meta_strategy,
                       "instances": insts, "proof_n": len(insts), "absorbed": [m["class"] for m in members]})
    kept = [w for w in weights if w not in members]
    kept.append(meta)
    pct = 100 * (old_desc - new_desc) // old_desc
    return True, f"admitted: {len(members)} operators -> 1, description -{old_desc - new_desc} chars ({pct}% smaller), fidelity preserved over {len(all_sigs)} signal(s)", kept


# ----- deterministic self-test (no LLM) -----
if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--selftest":
        W = load(os.path.join(os.path.dirname(__file__), ".corpus", "weights.jsonl"))
        act_load_ok = all(has_act_schema(w) for w in W)
        n0 = len(W)
        # LAW 1: a 2nd cross-file instance (different repo, same essence) ABSORBS, not duplicates — signal stored
        _, W = admit({"class": "CROSS-FILE-ROOT-CAUSE-VIA-DECISION-PREDICATE", "trigger": "ignore|filter",
                      "strategy": "(same essence)", "instance": "django-discover-excludes",
                      "signal": "files not excluded by filter recursively"}, W)
        absorbed = (len(W) == n0)
        op = next(w for w in W if w["class"] == "CROSS-FILE-ROOT-CAUSE-VIA-DECISION-PREDICATE")
        act_absorb_ok = has_act_schema(op) and any(i.get("id") == "django-discover-excludes" for i in op["act"]["fidelity_battery"])
        # LAW 2: a genuinely new class (no trigger match) CREATES under necessity
        _, W = admit({"class": "OFF-BY-ONE-BOUNDARY", "trigger": "boundary|fencepost|len.?1|inclusive",
                      "strategy": "check inclusive vs exclusive bounds at the edge index",
                      "instance": "numpy-slice-edge", "signal": "slice drops last boundary element"}, W)
        created = (len(W) == n0 + 1)
        created_op = next(w for w in W if w["class"] == "OFF-BY-ONE-BOUNDARY")
        act_created_ok = has_act_schema(created_op) and created_op["act"]["fidelity_battery"][0]["id"] == "numpy-slice-edge"
        # LAW 3 / proof-of-gain: a SHORTER strategy is admitted; a LONGER one rejected (description size)
        ok_short, r1 = self_improve(op, new_strategy=op["strategy"][: max(40, len(op["strategy"]) - 50)])
        ok_long, r2 = self_improve(op, new_strategy=op["strategy"] + " ... extra verbiage that adds length")
        # LAW 3 CONCRETE BATTERY: a trigger re-formalization that DROPS a captured signal is REJECTED (fidelity),
        # even though it is SHORTER. The django instance's signal "files not excluded by filter recursively" must
        # still be recalled — a trigger of just "ignore" (shorter) no longer matches it → must reject.
        ok_break, r3 = self_improve(op, new_trigger="ignore")   # shorter but drops the 'filter' signal → reject
        # and a trigger that stays faithful (covers all signals) + shorter is admitted
        ok_keep, r4 = self_improve(op, new_trigger="ignore|filter|exclud")
        act_update_ok = has_act_schema(op) and op["act"]["receipt"]["payload"]["strategy_sha256"] == hashlib.sha256(op["strategy"].encode("utf-8")).hexdigest()
        fid_ok, fails = verify_fidelity(W)
        print("ACT load/admit schema (loaded, absorbed, created):", act_load_ok and act_absorb_ok and act_created_ok)
        print("LAW1 absorb (2nd same-essence → no new operator):", absorbed, "| operator now holds", op["proof_n"], "instance(s)")
        print("LAW2 necessity (new class → new operator):       ", created)
        print("LAW3 proof-of-gain (shorter strategy admitted):  ", ok_short, "|", r1[:55])
        print("LAW3 proof-of-gain (longer strategy rejected):   ", (not ok_long), "|", r2[:55])
        print("LAW3 BATTERY (trigger dropping a signal REJECTED):", (not ok_break), "|", r3[:60])
        print("LAW3 BATTERY (faithful shorter trigger admitted): ", ok_keep, "|", r4[:55])
        print("monotonic fidelity intact (concrete per-signal):  ", fid_ok, "" if fid_ok else fails)

        # ---- COMPRESSION LAW (meta-minimality): N essence-sharing operators -> 1, smaller, fidelity preserved ----
        B = load(os.path.join(os.path.dirname(__file__), ".corpus", "weights.jsonl"))
        upstream = {"CROSS-FILE-ROOT-CAUSE-VIA-DECISION-PREDICATE": "ignore-paths not excluded recursively by the filter predicate",
                    "FIX-AT-WRITE-SITE-NOT-READ-SITE": "marks read are stale because stored wrong at the registration site",
                    "DISPATCH-HANDLER-LIVES-IN-REGISTRY-FILE": "is_subset wrong for a type because its dispatch handler is missing"}
        for w in B:
            if w["class"] in upstream:
                w["instances"] = [{"id": w["class"].lower(), "signal": upstream[w["class"]]}]; w["proof_n"] = 1
                ensure_act(w)
        members = [w for w in B if w["class"] in upstream]
        meta_trigger = ("ignore|filter|exclud|discover|path|recursiv|match|skip|mark|attribute|store|inherit|mro|"
                        "registr|stale|propagat|dispatch|singledispatch|overload|generic|handler|visitor")
        meta_strategy = ("The bug's ROOT is usually NOT where the wrong behavior is OBSERVED — it is UPSTREAM, at the "
                         "site that DECIDES, STORES, or REGISTERS the behavior. Trace from symptom to that site and fix "
                         "there: (a) wrong filter/discovery -> a DECISION PREDICATE (is_X/should_Y/_ignore), often in "
                         "another file; (b) a value wrong at READ time -> the WRITE/STORE/REGISTER site, so it is right "
                         "for ALL readers; (c) a type wrong in a dispatched generic -> the HANDLER that registers that "
                         "type. Use atomic_callers/atomic_grep to reach the site; fix the small decision, not the symptom.")
        cands = compression_candidates(B)
        merged_ok, mproof, merged_weights = admit_merge(members, meta_strategy, meta_trigger, "ROOT-IS-UPSTREAM-OF-SYMPTOM", B)
        meta_op = next((w for w in merged_weights if w["class"] == "ROOT-IS-UPSTREAM-OF-SYMPTOM"), {})
        act_merge_ok = has_act_schema(meta_op) and len(meta_op.get("act", {}).get("fidelity_battery", [])) == len(_signals(meta_op))
        print("COMPRESSION detect (essence-sharing cluster found):", any(len(c) >= 3 for c in cands))
        print("COMPRESSION admit (3 operators -> 1, proof-of-gain):", merged_ok, "|", mproof[:62])
        print("ACT self-update/merge schema:", act_update_ok and act_merge_ok)
        # ---- VSA operations and feedback learning self-test ----
        v1 = encode_vsa_text("pylint recursive ignore-paths")
        v2 = encode_vsa_text("pylint ignore-paths recursively")
        v3 = encode_vsa_text("sympy matrix dimensions")
        sim_similar = vsa_similarity(v1, v2)
        sim_dissimilar = vsa_similarity(v1, v3)
        vsa_algebra_ok = (sim_similar > 0.3) and (sim_dissimilar < 0.2)
        
        # Test reinforcement learning: acerto / erro
        op_vsa_orig = list(op["vsa"])
        reinforce_success(op, "files not excluded by filter recursively")
        sim_reinf = vsa_similarity(op["vsa"], encode_vsa_text("files not excluded by filter recursively"))
        sim_reinf_orig = vsa_similarity(op_vsa_orig, encode_vsa_text("files not excluded by filter recursively"))
        reinforce_ok = sim_reinf >= sim_reinf_orig
        
        correct_error(op, "wrong class pattern matched by mistake")
        sim_err = vsa_similarity(op["vsa"], encode_vsa_text("wrong class pattern matched by mistake"))
        sim_err_orig = vsa_similarity(op_vsa_orig, encode_vsa_text("wrong class pattern matched by mistake"))
        correct_ok = sim_err <= sim_err_orig
        
        vsa_learning_ok = reinforce_ok and correct_ok
        print("VSA algebra and trigram random projection:   ", vsa_algebra_ok, f"(similar={sim_similar:.3f}, dissimilar={sim_dissimilar:.3f})")
        print("VSA learns from usage (success/error loops): ", vsa_learning_ok, f"(reinforce: {sim_reinf_orig:.3f}->{sim_reinf:.3f}, correct: {sim_err_orig:.3f}->{sim_err:.3f})")
        
        print("ALL LAWS HOLD:", absorbed and created and ok_short and (not ok_long) and (not ok_break) and ok_keep and fid_ok and merged_ok and act_load_ok and act_absorb_ok and act_created_ok and act_update_ok and act_merge_ok and vsa_algebra_ok and vsa_learning_ok)

