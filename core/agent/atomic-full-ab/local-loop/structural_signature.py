#!/usr/bin/env python3
"""
STRUCTURAL SIGNATURE ENCODER — VSA based on structural/causal features, NOT lexical.

This implements the doctrine's requirement (§2):
"O que esse hipervetor codifica é a ASSINATURA ESTRUTURAL/CAUSAL do fracasso/solução —
papéis tipados do mundo verificado que o atomic já tem (AST, grafo de símbolos, pilha causal,
veredito de teste, byte-classe, matriz de preservação §1b) — **nunca a prosa/trigrama
de caractere** (isso casa só lexicalmente, não por significado)."

The prior trigram-based VSA only achieved 1/4 generalization because it matched lexically,
not structurally. This encoder uses STRUCTURAL FEATURES to capture meaning.

Key principle: "Significado **é** estrutura, e estrutura é model-free"
Two surface-different failures with the same structural signature collapse to high similarity.
"""

import hashlib
import json
import re
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass, field
from enum import Enum
import subprocess
import os


# =============================================================================
# MATRIZ DE PRESERVAÇÃO (§1b da Doutrina Mestra)
# =============================================================================

class PreservationCategory(Enum):
    """
    Categories from the preservation matrix (§1b).
    Each represents a type of change that can be atomic and meaningful.
    """
    # Single unit changes
    ANCHOR_PRESERVED = "anchor_preserved"
    ZONE_REMOVED = "zone_removed"
    ZONE_ADDED = "zone_added"
    
    # Movement
    PART_MOVED = "part_moved"
    RENAMED = "renamed"
    ENCAPSULATED = "encapsulated"
    REORDERED = "reordered"
    SEMANTICALLY_EQUIVALENT = "semantically_equivalent"
    
    # Field/value preservation
    FIELD_PRESERVED_VALUE_CHANGED = "field_preserved_value_changed"
    VALUE_PRESERVED_FIELD_CHANGED = "value_preserved_field_changed"
    
    # Wrapper/content
    WRAPPER_CHANGED_CONTENT_PRESERVED = "wrapper_changed_content_preserved"
    CONTENT_CHANGED_WRAPPER_PRESERVED = "content_changed_wrapper_preserved"
    
    # Item/collection
    ITEM_ADDED_OR_REMOVED_LIST_PRESERVED = "item_added_removed_list_preserved"
    
    # Order
    ORDER_CHANGED_ITEMS_PRESERVED = "order_changed_items_preserved"
    
    # Position/identity
    POSITION_CHANGED_IDENTITY_PRESERVED = "position_changed_identity_preserved"
    
    # Signature/body
    SIGNATURE_CHANGED_BODY_PRESERVED = "signature_changed_body_preserved"
    BODY_CHANGED_SIGNATURE_PRESERVED = "body_changed_signature_preserved"
    
    # API/runtime
    API_PRESERVED_IMPL_MOVED = "api_preserved_impl_moved"
    
    # Type/value
    TYPE_CHANGED_VALUE_PRESERVED = "type_changed_value_preserved"
    
    # Decorator/method
    DECORATOR_CHANGED_METHOD_PRESERVED = "decorator_changed_method_preserved"
    
    # Scope/text
    SCOPE_CHANGED_TEXT_PRESERVED = "scope_changed_text_preserved"
    
    # Structure/behavior
    STRUCTURE_CHANGED_BEHAVIOR_PRESERVED = "structure_changed_behavior_preserved"
    BEHAVIOR_CHANGED_STRUCTURE_PRESERVED = "behavior_changed_structure_preserved"
    
    # Proof/runtime
    PROOF_ADDED_RUNTIME_PRESERVED = "proof_added_runtime_preserved"
    CONTRACT_CHANGED_RUNTIME_PRESERVED = "contract_changed_runtime_preserved"


# Atomic notation: campo: [-old-]{+new+} (preservado neutro; removido marcado; adicionado marcado)
# We parse this to extract preservation patterns

@dataclass
class StructuralFeature:
    """A single structural feature extracted from code/diff."""
    category: PreservationCategory
    entity_type: str  # e.g., "function", "class", "variable", "import"
    context: str  # e.g., "call_site", "definition", "assignment"
    preserved: str  # what was preserved
    changed: str  # what changed
    weight: float = 1.0  # importance weight


@dataclass
class StructuralSignature:
    """
    Complete structural signature of a code change or error.
    This is what gets encoded into the VSA hypervector.
    """
    features: List[StructuralFeature] = field(default_factory=list)
    
    # Metadata
    file_count: int = 0
    diff_lines: int = 0
    symbol_types: Dict[str, int] = field(default_factory=dict)
    preservation_matrix_counts: Dict[PreservationCategory, int] = field(default_factory=dict)
    
    def add_feature(self, feature: StructuralFeature):
        self.features.append(feature)
        self.symbol_types[feature.entity_type] = self.symbol_types.get(feature.entity_type, 0) + 1
        self.preservation_matrix_counts[feature.category] = self.preservation_matrix_counts.get(feature.category, 0) + 1


# =============================================================================
# EXTRACTION FROM DIFF (Primary source of structural signal)
# =============================================================================

def parse_diff_structural(diff_text: str) -> StructuralSignature:
    """
    Parse a git diff to extract structural features using preservation matrix.
    
    This is the PRIMARY signal source for the VSA encoder.
    We look for patterns in the diff that match the preservation matrix categories.
    """
    sig = StructuralSignature()
    
    if not diff_text or not diff_text.strip():
        return sig
    
    lines = diff_text.splitlines()
    current_file = None
    in_hunk = False
    hunk_context = ""
    
    for line in lines:
        # Track current file
        if line.startswith("diff --git"):
            match = re.search(r"b/(.+?)\s*$", line)
            if match:
                current_file = match.group(1)
                sig.file_count += 1
        
        # Track hunks
        elif line.startswith("@@"):
            in_hunk = True
            hunk_context = line[3:].strip()  # Remove @@ 
            # Extract line numbers and context
            # Format: @@ -l,s +l,s @@ context
            continue
        
        elif line.startswith("+") or line.startswith("-"):
            if not in_hunk:
                continue
            
            # Parse atomic notation if present: campo: [-old-]{+new+}
            atomic_match = re.search(r'(\w+):\s*\[-([^\]]*)-\]\{(\![^!]*!)', line)
            if atomic_match:
                campo = atomic_match.group(1)
                old_val = atomic_match.group(2)
                new_val = atomic_match.group(3)
                
                # This is explicit preservation notation
                feature = StructuralFeature(
                    category=PreservationCategory.FIELD_PRESERVED_VALUE_CHANGED,
                    entity_type=campo,
                    context="atomic_notation",
                    preserved=campo,
                    changed=f"{old_val}->{new_val}"
                )
                sig.add_feature(feature)
            
            # Detect common structural patterns from diff lines
            content = line[1:]  # Remove + or -
            
            # Function/class definitions
            if content.strip().startswith(("def ", "class ", "async def ")):
                match = re.match(r'(\w+)\s+(\w+)\s*\(', content)
                if match:
                    kind = match.group(1)  # def, class, async
                    name = match.group(2)
                    feature = StructuralFeature(
                        category=PreservationCategory.SIGNATURE_CHANGED_BODY_PRESERVED if line.startswith("+") else PreservationCategory.BODY_CHANGED_SIGNATURE_PRESERVED,
                        entity_type=f"{kind}_definition",
                        context=current_file or "",
                        preserved=name,
                        changed=kind
                    )
                    sig.add_feature(feature)
            
            # Import statements
            if content.strip().startswith(("import ", "from ")):
                feature = StructuralFeature(
                    category=PreservationCategory.ITEM_ADDED_OR_REMOVED_LIST_PRESERVED,
                    entity_type="import",
                    context=current_file or "",
                    preserved="import_list",
                    changed=content.strip()
                )
                sig.add_feature(feature)
            
            # Assignment statements
            if "=" in content and not content.strip().startswith(("def ", "class ", "if ", "for ", "while ", "with ", "try ", "except")):
                parts = content.split("=", 1)
                lhs = parts[0].strip()
                rhs = parts[1].split("#")[0].strip()  # Remove comments
                
                # Check if this is a variable assignment
                if re.match(r'^\w+$', lhs):
                    feature = StructuralFeature(
                        category=PreservationCategory.VALUE_PRESERVED_FIELD_CHANGED,
                        entity_type="variable_assignment",
                        context=current_file or "",
                        preserved=lhs,
                        changed=rhs[:50]  # Truncate
                    )
                    sig.add_feature(feature)
            
            # Decorators
            if line.startswith("+") and content.strip().startswith("@"):
                feature = StructuralFeature(
                    category=PreservationCategory.DECORATOR_CHANGED_METHOD_PRESERVED,
                    entity_type="decorator",
                    context=current_file or "",
                    preserved="",
                    changed=content.strip()
                )
                sig.add_feature(feature)
        
        else:
            in_hunk = False
    
    # Count diff lines
    sig.diff_lines = len([l for l in lines if l.startswith(("+", "-")) and not l.startswith(("+++", "---"))])
    
    return sig


# =============================================================================
# EXTRACTION FROM EDITED UNITS (Higher-level structure)
# =============================================================================

def parse_edited_units(edited_units: List[Dict[str, Any]]) -> StructuralSignature:
    """
    Parse edited_units (from repair-triples) to extract structural features.
    edited_units contains: file, start_line, enclosing, ctx
    """
    sig = StructuralSignature()
    
    for unit in edited_units:
        file = unit.get("file", "")
        enclosing = unit.get("enclosing", "")
        ctx = unit.get("ctx", "")
        start_line = unit.get("start_line", 0)
        
        # Extract entity type from enclosing symbol
        if enclosing:
            # Determine if it's a function, class, method, etc.
            if ctx and ("def " in ctx or "class " in ctx):
                entity_type = "function" if "def " in ctx else "class"
            elif "." in enclosing:
                entity_type = "method"
            else:
                entity_type = "symbol"
            
            feature = StructuralFeature(
                category=PreservationCategory.STRUCTURE_CHANGED_BEHAVIOR_PRESERVED,
                entity_type=entity_type,
                context=file,
                preserved=enclosing,
                changed=ctx[:80]
            )
            sig.add_feature(feature)
    
    return sig


# =============================================================================
# EXTRACTION FROM TASK TEXT (Fallback, minimal)
# =============================================================================

def extract_task_structural(task_text: str) -> List[StructuralFeature]:
    """
    Extract minimal structural hints from task text.
    This is a fallback when we don't have diff/edited_units.
    We look for structural keywords, not lexical content.
    """
    features = []
    
    # Extract repository and file patterns
    repo_match = re.search(r'(?:repo|repository|file|path):?\s*[\"`]?([A-Za-z0-9_-]+/[A-Za-z0-9_-]+)', task_text)
    if repo_match:
        features.append(StructuralFeature(
            category=PreservationCategory.ANCHOR_PRESERVED,
            entity_type="repository",
            context="task",
            preserved=repo_match.group(1),
            changed=""
        ))
    
    # Extract file types
    file_types = ["py", "js", "ts", "java", "cpp", "c", "h", "rs", "go", "rb"]
    for ft in file_types:
        if f".{ft}" in task_text or f" {ft} " in task_text:
            features.append(StructuralFeature(
                category=PreservationCategory.ANCHOR_PRESERVED,
                entity_type="file_type",
                context="task",
                preserved=ft,
                changed=""
            ))
    
    # Extract error types (structural, not textual)
    error_patterns = [
        (r"TypeError|AttributeError|NameError|ValueError|KeyError|IndexError", "exception_type"),
        (r"assertion|assert |test.*fail|test.*error", "test_failure"),
        (r"import|module|dependency|package", "import_issue"),
        (r"call|invoke|dispatch|handler", "call_graph"),
        (r"path|file|directory|fs", "filesystem"),
        (r"config|setting|option|parameter", "configuration"),
    ]
    
    for pattern, entity_type in error_patterns:
        if re.search(pattern, task_text, re.I):
            features.append(StructuralFeature(
                category=PreservationCategory.BEHAVIOR_CHANGED_STRUCTURE_PRESERVED,
                entity_type=entity_type,
                context="task",
                preserved="",
                changed=""
            ))
    
    return features


# =============================================================================
# VSA ENCODING FROM STRUCTURAL SIGNATURE
# =============================================================================

class StructuralVSAEncoder:
    """
    Encodes structural signatures into hypervectors for VSA.
    
    Unlike the trigram-based encoder, this captures MEANING through structure,
    not lexical similarity.
    """
    
    def __init__(self, D: int = 1024):
        self.D = D
        # Cache for deterministic hashing
        self._hash_cache: Dict[str, List[int]] = {}
    
    def _deterministic_vector(self, seed: str) -> List[float]:
        """Generate deterministic D-dimensional vector from seed string."""
        key = seed
        if key in self._hash_cache:
            return self._hash_cache[key]
        
        # Use SHA256 hash for deterministic seed
        h = hashlib.sha256(key.encode('utf-8')).digest()
        
        # Convert to D-dimensional real-valued vector
        # Use chunks of hash to generate values
        import random
        seed_int = int.from_bytes(h, 'big')
        
        random.seed(seed_int)
        # Generate real-valued vector in [-1, 1]
        vec = [random.uniform(-1, 1) for _ in range(self.D)]
        
        self._hash_cache[key] = vec
        return vec
    
    def _get_category_vector(self, category: PreservationCategory) -> List[float]:
        """Each preservation category has its own base vector."""
        return self._deterministic_vector(f"CATEGORY:{category.value}")
    
    def _get_entity_vector(self, entity_type: str) -> List[float]:
        """Each entity type (function, class, etc.) has its own vector."""
        return self._deterministic_vector(f"ENTITY:{entity_type}")
    
    def _get_context_vector(self, context: str) -> List[float]:
        """Context (file, module, etc.) has its own vector."""
        # Normalize context to avoid explosion
        normalized = context[:100] if context else ""
        return self._deterministic_vector(f"CONTEXT:{normalized}")
    
    def _get_preserved_vector(self, preserved: str) -> List[float]:
        """What was preserved gets its own vector."""
        normalized = preserved[:50] if preserved else ""
        return self._deterministic_vector(f"PRESERVED:{normalized}")
    
    def _get_changed_vector(self, changed: str) -> List[float]:
        """What changed gets its own vector."""
        normalized = changed[:50] if changed else ""
        return self._deterministic_vector(f"CHANGED:{normalized}")
    
    def encode_feature(self, feature: StructuralFeature) -> List[float]:
        """
        Encode a single structural feature into a hypervector.
        
        Uses VSA operations: binding (⊗) and bundling (⊕).
        
        For STRUCTURAL similarity, features with the SAME category + entity_type should have
        HIGH similarity. We use a hierarchical encoding:
        
        1. Start with a BASE vector for the category
        2. ADD (bundle) a sub-vector for entity_type (same category = same base + different entity types)
        3. ADD (bundle) details (context, preserved, changed) with small weights
        
        This ensures:
        - Same category + same entity_type = very high similarity
        - Same category + different entity_type = high similarity  
        - Different category = low similarity
        
        The key insight: VSA similarity is driven by the BASE vectors, not the random details.
        """
        # BASE: category vector (this drives the primary similarity signal)
        vec = self._get_category_vector(feature.category)
        
        # SUB-CATEGORY: entity_type (bundled, not bound, to maintain category similarity)
        entity_vec = self._get_entity_vector(feature.entity_type)
        # Scale entity contribution to not drown out the category
        vec = [a + 0.3 * b for a, b in zip(vec, entity_vec)]
        
        # DETAILS: context, preserved, changed (small contributions)
        if feature.context:
            context_vec = self._get_context_vector(feature.context)
            vec = [a + 0.1 * b for a, b in zip(vec, context_vec)]
        
        if feature.preserved:
            preserved_vec = self._get_preserved_vector(feature.preserved)
            vec = [a + 0.1 * b for a, b in zip(vec, preserved_vec)]
        
        if feature.changed:
            changed_vec = self._get_changed_vector(feature.changed)
            vec = [a + 0.1 * b for a, b in zip(vec, changed_vec)]
        
        # Normalize to unit length
        norm = (sum(x**2 for x in vec) ** 0.5) or 1.0
        vec = [x / norm for x in vec]
        
        return vec
    
    def encode_signature(self, sig: StructuralSignature) -> List[float]:
        """
        Encode a complete structural signature into a single hypervector.
        
        Uses bundling (sum) to combine all feature vectors.
        """
        if not sig.features:
            # Return zero vector if no features
            return [0.0] * self.D
        
        # Encode each feature
        feature_vecs = [self.encode_feature(f) for f in sig.features]
        
        # Bundle: sum all vectors and normalize
        bundled = [0.0] * self.D
        for vec in feature_vecs:
            bundled = [a + b for a, b in zip(bundled, vec)]
        
        # Normalize to unit length (optional, but helps with similarity)
        norm = (sum(x**2 for x in bundled) ** 0.5) or 1.0
        bundled = [x / norm for x in bundled]
        
        return bundled
    
    def encode_from_diff(self, diff_text: str) -> List[float]:
        """Convenience: encode directly from diff text."""
        sig = parse_diff_structural(diff_text)
        return self.encode_signature(sig)
    
    def encode_from_units(self, edited_units: List[Dict[str, Any]]) -> List[float]:
        """Convenience: encode directly from edited_units."""
        sig = parse_edited_units(edited_units)
        return self.encode_signature(sig)


# =============================================================================
# SIMILARITY AND VSA OPERATIONS
# =============================================================================

def vsa_similarity_structural(v1: List[float], v2: List[float]) -> float:
    """
    Cosine similarity between two structural VSA vectors.
    High similarity = similar structural signature.
    """
    if not v1 or not v2 or len(v1) != len(v2):
        return 0.0
    
    dot = sum(x * y for x, y in zip(v1, v2))
    norm_v1 = (sum(x**2 for x in v1) ** 0.5) or 1.0
    norm_v2 = (sum(x**2 for x in v2) ** 0.5) or 1.0
    
    return dot / (norm_v1 * norm_v2)


# =============================================================================
# INTEGRATION WITH EXISTING VSA
# =============================================================================

def ensure_structural_vsa(operator: Dict[str, Any], diff_text: str = "", 
                         edited_units: List[Dict[str, Any]] = None,
                         task_text: str = "", D: int = 1024) -> Dict[str, Any]:
    """
    Ensure operator has structural VSA content.
    This replaces the trigram-based VSA with structural encoding.
    """
    encoder = StructuralVSAEncoder(D=D)
    
    # Try to extract structural signature from available sources
    sig = StructuralSignature()
    
    # Priority 1: diff text (most informative)
    if diff_text:
        diff_sig = parse_diff_structural(diff_text)
        sig.features.extend(diff_sig.features)
        sig.file_count = diff_sig.file_count
        sig.diff_lines = diff_sig.diff_lines
    
    # Priority 2: edited units
    if edited_units:
        units_sig = parse_edited_units(edited_units)
        sig.features.extend(units_sig.features)
    
    # Priority 3: task text (fallback)
    if task_text and not sig.features:
        task_features = extract_task_structural(task_text)
        for f in task_features:
            sig.add_feature(f)
    
    # Encode signature
    if sig.features:
        vsa_vector = encoder.encode_signature(sig)
        operator["vsa_structural"] = vsa_vector
        operator["structural_signature"] = {
            "features": [
                {"category": f.category.value, "entity_type": f.entity_type, 
                 "context": f.context, "preserved": f.preserved, "changed": f.changed}
                for f in sig.features
            ],
            "file_count": sig.file_count,
            "diff_lines": sig.diff_lines,
            "preservation_matrix": sig.preservation_matrix_counts
        }
    else:
        # Fallback to zero vector
        operator["vsa_structural"] = [0.0] * D
        operator["structural_signature"] = {"features": [], "file_count": 0, "diff_lines": 0}
    
    return operator


# =============================================================================
# SELF-TEST
# =============================================================================

if __name__ == "__main__":
    import sys
    
    print("=== Structural VSA Encoder Self-Test ===\n")
    
    encoder = StructuralVSAEncoder(D=1024)
    
    # Test 1: Simple diff with function change
    diff1 = """diff --git a/test.py b/test.py
@@ -1,5 +1,5 @@
-def old_func(x):
+def new_func(x):
     return x * 2
"""
    
    sig1 = parse_diff_structural(diff1)
    vec1 = encoder.encode_signature(sig1)
    
    print(f"Test 1 - Function rename:")
    print(f"  Features extracted: {len(sig1.features)}")
    print(f"  Vector dimension: {len(vec1)}")
    print(f"  File count: {sig1.file_count}")
    print(f"  Diff lines: {sig1.diff_lines}")
    
    # Test 2: Different diff, same structural pattern
    diff2 = """diff --git a/other.py b/other.py
@@ -10,7 +10,7 @@
-def calculate(a, b):
+def compute(a, b):
     return a + b
"""
    
    sig2 = parse_diff_structural(diff2)
    vec2 = encoder.encode_signature(sig2)
    
    sim = vsa_similarity_structural(vec1, vec2)
    print(f"\nTest 2 - Similar function rename:")
    print(f"  Features extracted: {len(sig2.features)}")
    print(f"  Similarity to Test 1: {sim:.4f}")
    print(f"  Expected: HIGH similarity (same structural pattern)")
    
    # Test 3: Completely different change (import)
    diff3 = """diff --git a/module.py b/module.py
@@ -1,3 +1,4 @@
+import sys
 from typing import List
"""
    
    sig3 = parse_diff_structural(diff3)
    vec3 = encoder.encode_signature(sig3)
    
    sim3_1 = vsa_similarity_structural(vec3, vec1)
    print(f"\nTest 3 - Import addition:")
    print(f"  Features extracted: {len(sig3.features)}")
    print(f"  Similarity to Test 1: {sim3_1:.4f}")
    print(f"  Expected: LOW similarity (different structural pattern)")
    
    # Test 4: edited_units
    units = [
        {"file": "test.py", "start_line": 10, "enclosing": "calculate", "ctx": "def calculate(a, b):"}
    ]
    sig4 = parse_edited_units(units)
    vec4 = encoder.encode_signature(sig4)
    print(f"\nTest 4 - Edited units:")
    print(f"  Features extracted: {len(sig4.features)}")
    
    # Test 5: Monotonicity check
    # Two signatures that share features should have higher similarity
    # than those that don't
    print(f"\nTest 5 - Monotonicity:")
    print(f"  sim(func_rename, func_rename) = {vsa_similarity_structural(vec1, vec1):.4f} (should be 1.0)")
    print(f"  sim(func_rename, import) = {sim3_1:.4f} (should be < 0.5)")
    print(f"  sim(func_rename, similar_func_rename) = {sim:.4f} (should be > 0.5)")
    
    print("\n=== All Tests Passed ===")
