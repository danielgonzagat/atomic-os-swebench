#!/usr/bin/env python3
"""
WEIGHTS ADMIT with STRUCTURAL VSA — replaces trigram encoding with structural encoding.

This module extends weights_admit.py to use structural signatures (based on preservation matrix §1b)
instead of trigram-based lexical encoding for the VSA layer.

KEY INSIGHT from doctrine: The prior trigram-based VSA only generalized 1/4 because it
matched LEXICALLY, not STRUCTURALLY. "Significado **é** estrutura, e estrutura é model-free"

This implements the correct encoding: "O que esse hipervetor codifica é a ASSINATURA
ESTRUTURAL/CAUSAL do fracasso/solução — papéis tipados do mundo verificado que o atomic
já tem (AST, grafo de símbolos, pilha causal, veredito de teste, byte-classe, matriz de
preservação §1b) — **nunca a prosa/trigrama de caractere**"
"""

import sys
import os

# Add current directory to path so we can import structural_signature
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from structural_signature import (
    StructuralVSAEncoder,
    parse_diff_structural,
    parse_edited_units,
    extract_task_structural,
    StructuralSignature,
    StructuralFeature,
    vsa_similarity_structural,
    ensure_structural_vsa,
)
from typing import Dict, List, Any, Optional
import hashlib
import json


# =============================================================================
# STRUCTURAL VSA IMPLEMENTATION (replaces trigram-based)
# =============================================================================

class StructuralWeightsAdmit:
    """
    Weight admission engine with STRUCTURAL VSA encoding.
    
    This replaces the trigram-based encode_vsa_text with structural encoding.
    """
    
    def __init__(self, D: int = 1024):
        self.D = D
        self.encoder = StructuralVSAEncoder(D=D)
    
    def encode_structural(self, diff_text: str = "", edited_units: List[Dict[str, Any]] = None,
                         task_text: str = "", task_id: str = "") -> List[float]:
        """
        Encode structural signature into VSA hypervector.
        
        Priority:
        1. diff_text (most informative - contains actual code changes)
        2. edited_units (from repair-triples, contains symbols/functions changed)
        3. task_text (fallback, extracts structural hints)
        """
        sig = StructuralSignature()
        
        # Priority 1: diff text
        if diff_text:
            diff_sig = parse_diff_structural(diff_text)
            sig.features.extend(diff_sig.features)
            sig.file_count = diff_sig.file_count
            sig.diff_lines = diff_sig.diff_lines
        
        # Priority 2: edited units
        if edited_units:
            units_sig = parse_edited_units(edited_units)
            sig.features.extend(units_sig.features)
        
        # Priority 3: task text
        if task_text and not sig.features:
            task_features = extract_task_structural(task_text)
            for f in task_features:
                sig.add_feature(f)
        
        # Priority 4: task ID (as fallback)
        if task_id and not sig.features:
            # Extract structural hints from task ID (e.g., "psf__requests-1142")
            parts = task_id.split("__")
            if len(parts) >= 2:
                org, repo_task = parts[0], parts[1]
                # Extract org and task number
                sig.add_feature(StructuralFeature(
                    category=structural_signature.PreservationCategory.ANCHOR_PRESERVED,
                    entity_type="organization",
                    context="task_id",
                    preserved=org,
                    changed=""
                ))
                # Extract task number
                task_num = repo_task.split("-")[1] if "-" in repo_task else repo_task
                sig.add_feature(StructuralFeature(
                    category=structural_signature.PreservationCategory.ANCHOR_PRESERVED,
                    entity_type="task_number",
                    context="task_id",
                    preserved=task_num,
                    changed=""
                ))
        
        return self.encoder.encode_signature(sig)
    
    def ensure_operator_structural_vsa(self, operator: Dict[str, Any],
                                     diff_text: str = "",
                                     edited_units: List[Dict[str, Any]] = None,
                                     task_text: str = "",
                                     task_id: str = "") -> Dict[str, Any]:
        """
        Ensure operator has structural VSA content.
        Stores both the vector and the human-readable signature.
        """
        if "vsa_structural" not in operator or not operator.get("vsa_structural"):
            vsa_vector = self.encode_structural(diff_text, edited_units, task_text, task_id)
            operator["vsa_structural"] = vsa_vector
            
            # Store the structural signature for debugging
            sig = StructuralSignature()
            if diff_text:
                sig = parse_diff_structural(diff_text)
            elif edited_units:
                sig = parse_edited_units(edited_units)
            
            operator["structural_signature"] = {
                "features": [
                    {"category": f.category.value, "entity_type": f.entity_type,
                     "context": f.context, "preserved": f.preserved, "changed": f.changed}
                    for f in sig.features
                ],
                "file_count": sig.file_count,
                "diff_lines": sig.diff_lines
            }
        
        return operator


# =============================================================================
# REINFORCE/CORRECT with Structural VSA
# =============================================================================

import structural_signature


def reinforce_success_structural(operator: Dict[str, Any], success_signal: str,
                                  diff_text: str = "", edited_units: List[Dict[str, Any]] = None,
                                  lr: float = 1.0):
    """
    Reinforce the operator VSA vector with a successful signal (acerto -> reforça).
    
    STRUCTURAL VERSION: Uses structural signature from diff/edited_units, not lexical.
    
    FINETUNING FIX: the prior single bipolar `vsa_bundle([op, sig])` sign-thresholds to +/-1, which SATURATES —
    bundling the signal once did NOT increase similarity. Real finetuning must ACCUMULATE evidence:
    the operator vsa becomes a real-valued memory trace; each success ADDS the signal (with learning rate),
    so repeated reinforcement of the same class STRICTLY increases similarity and the weights actually
    learn from use. Monotonic in evidence, no gradient.
    """
    encoder = StructuralVSAEncoder()
    
    if "vsa_structural" not in operator:
        # Initialize with structural encoding of the signal
        sig = StructuralSignature()
        
        # Try to extract from signal (might be a diff or task description)
        if success_signal:
            # Try as diff first
            if "diff --git" in success_signal or "@@" in success_signal:
                diff_sig = parse_diff_structural(success_signal)
                sig = diff_sig
            else:
                # Try as task text
                task_features = extract_task_structural(success_signal)
                for f in task_features:
                    sig.add_feature(f)
        
        if not sig.features and diff_text:
            sig = parse_diff_structural(diff_text)
        
        if not sig.features and edited_units:
            sig = parse_edited_units(edited_units)
        
        if sig.features:
            operator["vsa_structural"] = encoder.encode_signature(sig)
        else:
            operator["vsa_structural"] = [0.0] * encoder.D
    
    # Encode the success signal structurally
    signal_vec = encoder.encode_structural(diff_text, edited_units, success_signal, "")
    
    # Accumulate: add signal to operator vector (real-valued, not thresholded)
    current = operator["vsa_structural"]
    operator["vsa_structural"] = [v + lr * s for v, s in zip(current, signal_vec)]


def correct_error_structural(operator: Dict[str, Any], error_signal: str,
                               diff_text: str = "", edited_units: List[Dict[str, Any]] = None,
                               lr: float = 1.0):
    """
    Correct/subtract the error signal from the operator VSA vector (erro -> corrige).
    Symmetric real-valued accumulation: each error SUBTRACTS the signal, so similarity
    to the error pattern strictly decreases with use.
    """
    encoder = StructuralVSAEncoder()
    
    if "vsa_structural" not in operator:
        # Initialize
        sig = StructuralSignature()
        if error_signal:
            if "diff --git" in error_signal or "@@" in error_signal:
                sig = parse_diff_structural(error_signal)
            else:
                task_features = extract_task_structural(error_signal)
                for f in task_features:
                    sig.add_feature(f)
        
        if not sig.features and diff_text:
            sig = parse_diff_structural(diff_text)
        
        if not sig.features and edited_units:
            sig = parse_edited_units(edited_units)
        
        if sig.features:
            operator["vsa_structural"] = encoder.encode_signature(sig)
        else:
            operator["vsa_structural"] = [0.0] * encoder.D
    
    # Encode the error signal structurally
    signal_vec = encoder.encode_structural(diff_text, edited_units, error_signal, "")
    
    # Subtract: correct the operator vector
    current = operator["vsa_structural"]
    operator["vsa_structural"] = [v - lr * s for v, s in zip(current, signal_vec)]


def vsa_similarity_structural_mixed(v1: List[float], v2: List[float]) -> float:
    """Wrapper for structural similarity."""
    return vsa_similarity_structural(v1, v2)


# =============================================================================
# COMPATIBILITY LAYER with existing weights_admit.py
# =============================================================================

class UnifiedWeightsAdmit:
    """
    Unified weight admission that supports BOTH lexical (trigram) and structural VSA.
    
    During transition period, we maintain both for backward compatibility.
    The plan is to migrate fully to structural.
    """
    
    def __init__(self):
        # Import original weights_admit functions
        import weights_admit
        self.weights_admit = weights_admit
        
        # Initialize structural encoder
        self.structural_encoder = StructuralVSAEncoder()
    
    def encode_lexical(self, text: str, D: int = 1024) -> List[int]:
        """Original trigram-based encoding (bipolar)."""
        return self.weights_admit.encode_vsa_text(text, D)
    
    def encode_structural(self, diff_text: str = "", edited_units: List[Dict[str, Any]] = None,
                         task_text: str = "", task_id: str = "") -> List[float]:
        """New structural encoding (real-valued)."""
        return self.structural_encoder.encode_structural(diff_text, edited_units, task_text, task_id)
    
    def encode_combined(self, text: str, diff_text: str = "", edited_units: List[Dict[str, Any]] = None) -> Dict[str, Any]:
        """
        Encode using BOTH methods for transition period.
        Returns dict with both vectors.
        """
        lexical = self.encode_lexical(text)
        structural = self.encode_structural(diff_text, edited_units, text)
        
        return {
            "vsa_lexical": lexical,
            "vsa_structural": structural,
            "encoding_method": "combined"
        }


# =============================================================================
# SELF-TEST
# =============================================================================

if __name__ == "__main__":
    print("=== Structural Weights Admit Self-Test ===\n")
    
    admit = StructuralWeightsAdmit()
    
    # Test 1: Encode a diff
    diff = """diff --git a/test.py b/test.py
@@ -1,5 +1,5 @@
-def old_func(x):
+def new_func(x):
     return x * 2
"""
    
    vec = admit.encode_structural(diff_text=diff)
    print(f"Test 1 - Encode diff:")
    print(f"  Vector dimension: {len(vec)}")
    print(f"  Vector type: {type(vec[0]).__name__} (should be float)")
    
    # Test 2: Reinforce and verify similarity increases
    op = {"class": "TEST", "trigger": "test", "strategy": "test"}
    admit.ensure_operator_structural_vsa(op, diff_text=diff)
    
    initial_sim = vsa_similarity_structural(op["vsa_structural"], vec)
    print(f"\nTest 2 - Initial similarity: {initial_sim:.4f}")
    
    # Reinforce with same signal
    reinforce_success_structural(op, "success", diff_text=diff)
    new_sim = vsa_similarity_structural(op["vsa_structural"], vec)
    print(f"  After reinforce: {new_sim:.4f}")
    print(f"  Similarity increased: {new_sim > initial_sim}")
    
    # Test 3: Different structural pattern
    diff2 = """diff --git a/other.py b/other.py
@@ -1,3 +1,4 @@
+import sys
 from typing import List
"""
    
    vec2 = admit.encode_structural(diff_text=diff2)
    sim_diff = vsa_similarity_structural(vec, vec2)
    print(f"\nTest 3 - Different diff:")
    print(f"  Similarity between func_rename and import: {sim_diff:.4f}")
    print(f"  Expected: LOW (< 0.5)")
    
    print("\n=== Structural Weights Admit Ready ===")
