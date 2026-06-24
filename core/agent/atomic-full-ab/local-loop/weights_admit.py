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


def _get_symbol_vector(symbol, D=1024):
    """Deterministic bipolar vector for a typed structural role/value token."""
    h = hashlib.sha256(("structural-vsa:" + str(symbol)).encode("utf-8")).digest()
    import random
    seed = int.from_bytes(h, "big")
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


_SURFACE_KEYS = {
    "description", "message", "surface", "surface_words", "surface_words_ignored",
    "text", "task", "prompt", "path", "file", "filename", "name", "identifier",
    "literal", "source", "source_text", "patch", "diff", "edit_target",
    "symptom_loci", "causal_loci", "failing_stack_loci", "failure_stack_loci",
    "test_loci", "failing_test_loci", "symbol_graph_edges", "symbol_edges",
    "preservation_matrix",
}


def _as_list(value):
    if value is None:
        return []
    if isinstance(value, (list, tuple, set)):
        return [str(v) for v in value if str(v)]
    if isinstance(value, str) and value:
        return [value]
    return []


def _bucket_count(n):
    try:
        n = int(n)
    except Exception:
        return "unknown"
    if n <= 0:
        return "0"
    if n == 1:
        return "1"
    if n <= 3:
        return "2-3"
    return "4+"


def _surface_keylike(value):
    s = str(value or "").lower()
    leaf = s.split(".")[-1]
    return (
        leaf in _SURFACE_KEYS
        or "/" in s
        or "\\" in s
        or ":" in s
        or s.endswith((".py", ".js", ".ts", ".tsx", ".java", ".go", ".rs"))
    )


def _safe_role_token(value, default="typed"):
    token = str(value or "").strip().lower()
    token = re.sub(r"[^a-z0-9_-]+", "_", token).strip("_")
    return token or default


def _locus_file(locus):
    s = str(locus or "")
    if not s:
        return ""
    return s.split(":", 1)[0]


def _matches_locus(target, loci):
    target = str(target or "")
    return bool(target and target in set(_as_list(loci)))


def _matches_locus_file(target, loci):
    target_file = _locus_file(target)
    return bool(target_file and target_file in {_locus_file(locus) for locus in _as_list(loci)})


def _target_role(target, symptom_loci, causal_loci):
    target = str(target or "")
    symptoms = set(_as_list(symptom_loci))
    causal = set(_as_list(causal_loci))
    in_symptom = bool(target and target in symptoms)
    in_causal = bool(target and target in causal)
    if in_symptom and in_causal:
        return "symptom_and_causal"
    if in_symptom and not in_causal:
        return "symptom_not_causal"
    if in_causal and not in_symptom:
        return "causal_not_symptom"
    if causal:
        return "outside_known_causal"
    if symptoms:
        return "outside_symptom"
    return "unknown"


def _causal_stack_roles(event):
    target = event.get("edit_target")
    stack_loci = _as_list(event.get("failing_stack_loci") or event.get("failure_stack_loci") or event.get("stack_loci"))
    test_loci = _as_list(event.get("test_loci") or event.get("failing_test_loci"))
    symptom_loci = _as_list(event.get("symptom_loci"))
    causal_loci = _as_list(event.get("causal_loci"))
    if not target and not stack_loci and not test_loci:
        return []

    target_is_causal = _matches_locus(target, causal_loci)
    target_file_is_causal = _matches_locus_file(target, causal_loci)
    target_is_stack = _matches_locus(target, stack_loci)
    target_file_is_stack = _matches_locus_file(target, stack_loci)
    target_is_symptom = _matches_locus(target, symptom_loci)

    if target_is_causal:
        stack_role = "edited_causal_locus"
    elif target_file_is_causal:
        stack_role = "edited_causal_file"
    elif target_is_stack and target_is_symptom:
        stack_role = "edited_failure_stack_symptom_not_causal"
    elif target_is_stack:
        stack_role = "edited_failure_stack_locus_not_causal"
    elif target_file_is_stack:
        stack_role = "edited_failure_stack_file_not_causal"
    elif stack_loci:
        stack_role = "outside_failure_stack"
    else:
        stack_role = "stack_unknown"

    if _matches_locus(target, test_loci) or _matches_locus_file(target, test_loci):
        test_role = "edited_test_locus"
    elif test_loci:
        test_role = "outside_test_locus"
    else:
        test_role = "test_locus_unknown"

    roles = [
        {"role": "edited_stack_relation", "kind": stack_role},
        {"role": "edited_test_relation", "kind": test_role},
    ]
    if stack_loci:
        roles.append({"role": "stack_loci_count", "bucket": _bucket_count(len(stack_loci))})
    return roles


def _symbol_graph_roles(event):
    edges = event.get("symbol_graph_edges") or event.get("symbol_edges") or event.get("symbol_graph") or []
    if not isinstance(edges, (list, tuple)):
        return []
    target = event.get("edit_target")
    symptom_loci = _as_list(event.get("symptom_loci"))
    causal_loci = _as_list(event.get("causal_loci"))
    stack_loci = _as_list(event.get("failing_stack_loci") or event.get("failure_stack_loci") or event.get("stack_loci"))
    roles = []
    for edge in edges:
        if not isinstance(edge, dict):
            continue
        source = edge.get("source") or edge.get("caller") or edge.get("from")
        dest = edge.get("target") or edge.get("callee") or edge.get("to")
        kind = _safe_role_token(edge.get("kind") or edge.get("relation") or "edge")
        relation = None
        if _matches_locus(target, [source]) and _matches_locus(dest, causal_loci):
            relation = "edited_source_to_causal"
        elif _matches_locus_file(target, [source]) and _matches_locus_file(dest, causal_loci):
            relation = "edited_source_file_to_causal"
        elif _matches_locus(target, [dest]) and _matches_locus(source, symptom_loci):
            relation = "edited_target_from_symptom"
        elif _matches_locus_file(target, [dest]) and _matches_locus_file(source, symptom_loci):
            relation = "edited_target_file_from_symptom"
        elif _matches_locus(target, [source]) and _matches_locus(dest, stack_loci):
            relation = "edited_source_to_stack"
        elif _matches_locus(target, [dest]) and _matches_locus(source, stack_loci):
            relation = "edited_target_from_stack"
        if relation:
            roles.append({"role": "edited_relation", "kind": relation})
            roles.append({"role": "edge_kind", "kind": kind})
    unique = []
    seen = set()
    for role in roles:
        marker = tuple(sorted(role.items()))
        if marker not in seen:
            seen.add(marker)
            unique.append(role)
    return unique


def _preservation_roles(matrix):
    if not isinstance(matrix, dict):
        return matrix if isinstance(matrix, list) else []
    roles = []
    for key, value in sorted(matrix.items(), key=lambda kv: str(kv[0])):
        if _surface_keylike(key):
            continue
        role = "preserve_" + _safe_role_token(key)
        if isinstance(value, bool):
            status = "preserved" if value else "violated"
        else:
            token = _safe_role_token(value, default="unknown")
            if token in {"true", "pass", "passed", "ok", "preserved", "unchanged", "kept"}:
                status = "preserved"
            elif token in {"false", "fail", "failed", "broken", "changed", "violated", "removed"}:
                status = "violated"
            else:
                status = token
        roles.append({"role": role, "status": status})
    return roles


def _flatten_typed_features(prefix, value, out):
    """Flatten typed structural data while deliberately ignoring surface/prose fields."""
    key = str(prefix).lower()
    if _surface_keylike(key.split(".")[-1]):
        return
    if isinstance(value, dict):
        for k, v in sorted(value.items(), key=lambda kv: str(kv[0])):
            if _surface_keylike(k):
                continue
            _flatten_typed_features(f"{prefix}.{k}" if prefix else str(k), v, out)
        return
    if isinstance(value, (list, tuple)):
        for item in value:
            if isinstance(item, dict):
                role = item.get("role") or item.get("kind") or "item"
                for k, v in sorted(item.items(), key=lambda kv: str(kv[0])):
                    if k in {"name", "path", "file", "identifier", "literal"}:
                        continue
                    _flatten_typed_features(f"{prefix}.{role}.{k}", v, out)
            elif isinstance(item, (bool, int, float)):
                out.append((prefix, str(item).lower()))
        return
    if isinstance(value, bool):
        out.append((prefix, "true" if value else "false"))
    elif isinstance(value, (int, float)):
        out.append((prefix, str(value)))
    elif isinstance(value, str):
        token = value.strip().lower()
        if token and re.fullmatch(r"[a-z0-9_.-]+", token) and not _surface_keylike(token):
            out.append((prefix, token))


def structural_signature_from_event(event):
    """Extract a model-free structural/causal signature from a typed atomic event.

    The output intentionally drops concrete names, paths, prose, and natural-language
    descriptions. Meaning is encoded as verifiable roles: edited target relative to
    symptom/causal loci, verdict class, byte class, AST role/kind, and other typed
    machine facts supplied by the atomic world.
    """
    if not isinstance(event, dict):
        return None
    if isinstance(event.get("structural_signature"), dict):
        base = dict(event["structural_signature"])
    else:
        base = {}
    if any(k in event for k in ("edit_target", "symptom_loci", "causal_loci")):
        symptoms = _as_list(event.get("symptom_loci"))
        causal = _as_list(event.get("causal_loci"))
        base["edit_target_role"] = _target_role(event.get("edit_target"), symptoms, causal)
        base["symptom_loci_count"] = _bucket_count(len(symptoms))
        base["causal_loci_count"] = _bucket_count(len(causal))
        base["causal_loci_known"] = bool(causal)
    causal_stack = _causal_stack_roles(event)
    if causal_stack:
        base["causal_stack"] = causal_stack
    symbol_graph = _symbol_graph_roles(event)
    if symbol_graph:
        base["symbol_graph"] = symbol_graph
    for src, dst in (
        ("event", "event"),
        ("test_verdict", "test_verdict"),
        ("verdict", "test_verdict"),
        ("byte_class", "byte_class"),
        ("failure_stage", "failure_stage"),
        ("operation", "operation"),
        ("gate", "gate"),
    ):
        if src in event and isinstance(event[src], (str, bool, int, float)):
            base[dst] = event[src]
    if "ast" in event:
        base["ast"] = event["ast"]
    if "symbol_roles" in event:
        base["symbol_roles"] = event["symbol_roles"]
    if "preservation_matrix" in event:
        base["preservation"] = _preservation_roles(event["preservation_matrix"])
    elif "preservation" in event:
        base["preservation"] = _preservation_roles(event["preservation"])
    features = []
    _flatten_typed_features("", base, features)
    if not features:
        return None
    return {k: v for k, v in sorted(set(features))}


def encode_vsa_structure(signature, D=1024):
    """Encode typed structural/causal roles with bind/bundle/permute, model-free."""
    sig = structural_signature_from_event(signature) if isinstance(signature, dict) else None
    if sig is None and isinstance(signature, dict):
        sig = {str(k): str(v).lower() for k, v in signature.items() if isinstance(v, (str, bool, int, float))}
    if not sig:
        return [0] * D
    vectors = []
    for idx, (role, value) in enumerate(sorted(sig.items())):
        role_vec = _get_symbol_vector("role:" + str(role), D)
        value_vec = _get_symbol_vector("value:" + str(value), D)
        vectors.append(vsa_permute(vsa_bind(role_vec, value_vec), idx))
    return vsa_bundle(vectors)


def encode_vsa_signal(signal, D=1024):
    """Encode a signal, preferring structural/causal semantics over text.

    Dict/JSON signals are treated as typed atomic-world events. Plain strings remain a
    legacy recall fallback only; they are not the semantic substrate for travas.
    """
    if isinstance(signal, dict):
        return encode_vsa_structure(signal, D)
    if isinstance(signal, str):
        stripped = signal.strip()
        if stripped.startswith("{") and stripped.endswith("}"):
            try:
                parsed = json.loads(stripped)
            except Exception:
                parsed = None
            if isinstance(parsed, dict):
                return encode_vsa_structure(parsed, D)
        return encode_vsa_text(signal, D)
    return encode_vsa_text(str(signal), D)


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


def reinforce_success(operator, success_signal, lr=1.0):
    """Reinforce the operator VSA vector with a successful signal (acerto -> reforça).

    FINETUNING FIX: the prior single bipolar `vsa_bundle([op, sig])` sign-thresholds to +/-1, which SATURATES —
    bundling the signal once did NOT increase similarity (selftest measured reinforce 0.619->0.619 = a NO-OP that
    only passed the gate because it was >=). Real finetuning must ACCUMULATE evidence: the operator vsa becomes a
    real-valued memory trace; each success ADDS the signal (with learning rate), so repeated reinforcement of the
    same class STRICTLY increases similarity and the weights actually learn from use. Monotonic in evidence, no
    gradient. (admit() still seeds the prototype via bipolar vsa_bundle; reinforce/correct finetune it real-valued.)"""
    if "vsa" not in operator:
        ensure_act(operator)
    sig_vec = encode_vsa_signal(success_signal)
    operator["vsa"] = [v + lr * s for v, s in zip(operator["vsa"], sig_vec)]
    ensure_act(operator, force_vsa_update=False)


def correct_error(operator, error_signal, lr=1.0):
    """Correct/subtract the error signal from the operator VSA vector (erro -> corrige). Symmetric real-valued
    accumulation: each error SUBTRACTS the signal, so similarity to the error pattern strictly decreases with use."""
    if "vsa" not in operator:
        ensure_act(operator)
    err_vec = encode_vsa_signal(error_signal)
    operator["vsa"] = [v - lr * e for v, e in zip(operator["vsa"], err_vec)]
    ensure_act(operator, force_vsa_update=False)


# --- TRAVA: the first-class BLOCK primitive (the doctrine's Apêndice-A `papel: TRAVA`) -----------------------
# The decisive reframe (proven by number this session): FIXES don't recur (0 fix-classes in SWE-bench-Verified) but
# ERRORS do. So the substrate's transferable value is not suggesting unique fixes — it is (a) BLOCKING a move already
# proven wrong, and (b) suggesting its opposite. A trava is an operator carrying the VSA of a proven-wrong error
# pattern (fed by the disproof-corpus). When a candidate move's VSA is close enough to the trava's error pattern, the
# trava BLOCKS it. Because errors recur across DISTINCT bugs, the trava generalizes where instance-WHERE operators do
# not. The VSA match is finetuned by correct_error/reinforce (now real, cumulative), so the trava sharpens with use.
def make_trava(error_pattern, opposite_suggestion="", threshold=0.35):
    """Capture a proven-wrong pattern as a recoverable, finetunable TRAVA operator."""
    return {"role": "TRAVA",
            "vsa": encode_vsa_signal(error_pattern),
            "error_pattern": error_pattern,
            "structural_signature": structural_signature_from_event(error_pattern) if isinstance(error_pattern, dict) else None,
            "suggest_opposite": opposite_suggestion,
            "threshold": float(threshold),
            "hits": 0}


def trava_blocks(trava, candidate_signal):
    """Does this trava BLOCK the candidate move? (VSA-similarity of the candidate to the proven-wrong pattern >=
    threshold). Generalizes across distinct bugs because it matches the ERROR shape, not a specific fix. Returns
    (blocked: bool, similarity: float, opposite: str)."""
    sim = vsa_similarity(trava["vsa"], encode_vsa_signal(candidate_signal))
    blocked = sim >= trava.get("threshold", 0.35)
    return blocked, sim, trava.get("suggest_opposite", "")


def trava_reinforce(trava, recurring_error_signal, lr=1.0):
    """The error recurred (on a DISTINCT bug) → sharpen the trava so it blocks this pattern more strongly. Uses the
    fixed cumulative reinforce: repeated exposure strictly increases the trava's similarity to the error shape."""
    reinforce_success(trava, recurring_error_signal, lr=lr)
    trava["hits"] = trava.get("hits", 0) + 1
    return trava


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
        
        # Test reinforcement learning: acerto / erro — STRICT (a no-op reinforce must FAIL the gate, never fake-green).
        op_vsa_orig = list(op["vsa"])
        reinforce_success(op, "files not excluded by filter recursively")
        sim_reinf = vsa_similarity(op["vsa"], encode_vsa_text("files not excluded by filter recursively"))
        sim_reinf_orig = vsa_similarity(op_vsa_orig, encode_vsa_text("files not excluded by filter recursively"))
        reinforce_ok = sim_reinf > sim_reinf_orig          # STRICT: reinforcement must actually increase similarity
        # CUMULATIVE: a second reinforcement of the SAME class must increase similarity AGAIN (real finetuning, not one-shot)
        reinforce_success(op, "files not excluded by filter recursively")
        sim_reinf2 = vsa_similarity(op["vsa"], encode_vsa_text("files not excluded by filter recursively"))
        cumulative_ok = sim_reinf2 > sim_reinf

        op_for_err = dict(op); op_for_err["vsa"] = list(op_vsa_orig)
        correct_error(op_for_err, "wrong class pattern matched by mistake")
        sim_err = vsa_similarity(op_for_err["vsa"], encode_vsa_text("wrong class pattern matched by mistake"))
        sim_err_orig = vsa_similarity(op_vsa_orig, encode_vsa_text("wrong class pattern matched by mistake"))
        correct_ok = sim_err < sim_err_orig                # STRICT: correction must actually decrease similarity

        vsa_learning_ok = reinforce_ok and cumulative_ok and correct_ok

        # TRAVA primitive: a proven-wrong error pattern BLOCKS a matching move + suggests the opposite, and
        # GENERALIZES (blocks a surface-distinct re-occurrence of the same error shape), and SHARPENS with use.
        wrong_struct_a = {
            "event": "candidate_edit_rejected",
            "edit_target": "repo_a/module.py:visible_symptom",
            "symptom_loci": ["repo_a/module.py:visible_symptom"],
            "causal_loci": ["repo_a/root.py:decision_predicate"],
            "test_verdict": "fail",
            "byte_class": "byte_negative",
            "ast": [{"role": "edited_node", "kind": "FunctionDef"}],
            "surface_words_ignored": "edited the symptom site instead of root cause",
        }
        wrong_struct_b = {
            "event": "candidate_edit_rejected",
            "edit_target": "repo_b/callsite.py:observed_failure",
            "symptom_loci": ["repo_b/callsite.py:observed_failure"],
            "causal_loci": ["repo_b/causal.py:stored_policy"],
            "test_verdict": "fail",
            "byte_class": "byte_negative",
            "ast": [{"role": "edited_node", "kind": "FunctionDef"}],
            "surface_words_ignored": "modified the call site where the error appeared",
        }
        correct_struct = {
            "event": "candidate_edit_candidate",
            "edit_target": "repo_b/causal.py:stored_policy",
            "symptom_loci": ["repo_b/callsite.py:observed_failure"],
            "causal_loci": ["repo_b/causal.py:stored_policy"],
            "test_verdict": "candidate",
            "byte_class": "byte_candidate",
            "ast": [{"role": "edited_node", "kind": "FunctionDef"}],
        }
        sig_a = structural_signature_from_event(wrong_struct_a)
        sig_b = structural_signature_from_event(wrong_struct_b)
        structural_same = sig_a == sig_b and "repo_a" not in json.dumps(sig_a) and "repo_b" not in json.dumps(sig_a)
        structural_sim = vsa_similarity(encode_vsa_signal(wrong_struct_a), encode_vsa_signal(wrong_struct_b))
        structural_diff = vsa_similarity(encode_vsa_signal(wrong_struct_a), encode_vsa_signal(correct_struct))
        structural_vsa_ok = structural_same and structural_sim > 0.95 and structural_diff < 0.70
        trava = make_trava(wrong_struct_a,
                           opposite_suggestion="trace to the causal locus before editing", threshold=0.90)
        # blocks the same STRUCTURAL error on a DISTINCT-surface bug (error recurs even though the fix is unique):
        blk_recur, sim_recur, opp = trava_blocks(trava, wrong_struct_b)
        # does NOT block a candidate that edits the causal locus:
        blk_ok, sim_ok, _ = trava_blocks(trava, correct_struct)
        trava_generalizes = blk_recur and (not blk_ok) and bool(opp)
        # sharpens with use (recurring error → stronger block):
        trava_reinforce(trava, wrong_struct_b)
        _, sim_after, _ = trava_blocks(trava, wrong_struct_b)
        trava_sharpens = sim_after > sim_recur
        trava_ok = trava_generalizes and trava_sharpens
        print("STRUCTURAL/CAUSAL VSA model-free semantics:", structural_vsa_ok,
              f"(same={structural_sim:.3f}, different={structural_diff:.3f})")
        print("TRAVA blocks proven-wrong + generalizes + sharpens:", trava_ok,
              f"(recur_sim={sim_recur:.2f} block={blk_recur}, distinct_sim={sim_ok:.2f} block={blk_ok}, after_reinforce={sim_after:.2f})")

        print("VSA algebra and legacy text fallback:        ", vsa_algebra_ok, f"(similar={sim_similar:.3f}, dissimilar={sim_dissimilar:.3f})")
        print("VSA learns from usage (success/error loops): ", vsa_learning_ok, f"(reinforce: {sim_reinf_orig:.3f}->{sim_reinf:.3f}, correct: {sim_err_orig:.3f}->{sim_err:.3f})")
        
        print("ALL LAWS HOLD:", absorbed and created and ok_short and (not ok_long) and (not ok_break) and ok_keep and fid_ok and merged_ok and act_load_ok and act_absorb_ok and act_created_ok and act_update_ok and act_merge_ok and structural_vsa_ok and vsa_algebra_ok and vsa_learning_ok and trava_ok)
