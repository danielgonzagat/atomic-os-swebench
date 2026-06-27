/- NwayConfluence.lean - machine-checked P7-lean: the N-way confluence induction
   principle for the verified-edit algebra. Self-contained (Lean 4 core only). -/
namespace AtomicAlgebra
variable {σ : Type}
def Comm (f g : σ → σ) : Prop := ∀ s, f (g s) = g (f s)
def applyAll (l : List (σ → σ)) (s : σ) : σ := l.foldr (fun f acc => f acc) s
def AllComm (l : List (σ → σ)) : Prop := ∀ f ∈ l, ∀ g ∈ l, Comm f g

theorem comm_past (f : σ → σ) :
    ∀ (l : List (σ → σ)), (∀ g ∈ l, Comm f g) → ∀ s, f (applyAll l s) = applyAll l (f s)
  | [], _, _ => rfl
  | a :: l, h, s => by
      have hfa : Comm f a := h a List.mem_cons_self
      have hrest : ∀ g ∈ l, Comm f g := fun g hg => h g (List.mem_cons_of_mem a hg)
      show f (a (applyAll l s)) = a (applyAll l (f s))
      rw [hfa (applyAll l s), comm_past f l hrest s]

theorem applyAll_append (xs ys : List (σ → σ)) (s : σ) :
    applyAll (xs ++ ys) s = applyAll xs (applyAll ys s) := by
  simp [applyAll, List.foldr_append]

theorem applyAll_reverse :
    ∀ (l : List (σ → σ)), AllComm l → ∀ s, applyAll l s = applyAll l.reverse s
  | [], _, _ => rfl
  | a :: l, h, s => by
      have hal : ∀ g ∈ l, Comm a g := fun g hg => h a List.mem_cons_self g (List.mem_cons_of_mem a hg)
      have hrest : AllComm l := fun f hf g hg => h f (List.mem_cons_of_mem a hf) g (List.mem_cons_of_mem a hg)
      have ih := applyAll_reverse l hrest (a s)
      calc applyAll (a :: l) s = a (applyAll l s) := rfl
        _ = applyAll l (a s) := (comm_past a l hal s)
        _ = applyAll l.reverse (a s) := ih
        _ = applyAll (l.reverse ++ [a]) s := (applyAll_append l.reverse [a] s).symm
        _ = applyAll (a :: l).reverse s := by rw [List.reverse_cons]

theorem allComm_of_perm {l l' : List (σ → σ)} (hp : l.Perm l') (h : AllComm l) : AllComm l' :=
  fun f hf g hg => h f (hp.mem_iff.mpr hf) g (hp.mem_iff.mpr hg)

/-- FULL N-WAY CONFLUENCE: any two permutations of a pairwise-commuting batch
    apply to the same state. Induction on the permutation derivation (all N). -/
theorem applyAll_perm :
    ∀ {l l' : List (σ → σ)}, l.Perm l' → AllComm l → ∀ s, applyAll l s = applyAll l' s := by
  intro l l' hp
  induction hp with
  | nil => intro _ _; rfl
  | cons a p ih =>
      intro h s
      have hrest : AllComm _ := fun f hf g hg =>
        h f (List.mem_cons_of_mem a hf) g (List.mem_cons_of_mem a hg)
      show a (applyAll _ s) = a (applyAll _ s)
      rw [ih hrest s]
  | swap a b l =>
      intro h s
      have hcab : Comm b a :=
        h b List.mem_cons_self a (List.mem_cons_of_mem b List.mem_cons_self)
      exact hcab (applyAll l s)
  | trans p1 p2 ih1 ih2 =>
      intro h s
      exact (ih1 h s).trans (ih2 (allComm_of_perm p1 h) s)
end AtomicAlgebra
#print axioms AtomicAlgebra.applyAll_perm
