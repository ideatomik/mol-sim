# Self-Paired Template Chain/Ring Collision Fix — Design

_Brainstormed 2026-08-03, follow-up to `2026-08-03-template-strand-self-paired-rendering-design.md`
("Branch B" / 1a shipped from that document, collision left explicitly open). Scope:
`scripts/ribose_deriver.gd` only — `derive_self_paired_ring()`'s body and a small
addition to `derive_substituents()`. No other file changes._

## Problem

`derive_self_paired_ring()`, as shipped (the prior design doc's Branch B / "1a"),
fixed the self-paired template's frame-to-frame flicker by picking a deterministic
0°/180° rotation from `bulge_vs_pairing_dot` alone. It never attempted to address
the backbone chain/ring collision (O3' landing on top of C4', C5' landing on top of
C3') — that document's own stop condition fired, and the collision was documented
as a known, open, un-fixed-by-that-pass issue.

Live F9 dumps taken 2026-08-03 confirm the collision is still present and severe:
`chain_closest_to_own_ribose` reads 0.008–0.2 world units (vs. `bond_length` =
10.8, and the project's collision-clearance target of 12.0 = `2 × molecular_atom_radius`)
for every sampled self-paired template residue in both strands.

## Prior investigation (do not repeat these failures)

`docs/MolecularStructure_BasePairExpansion.md` (Bug V/W) and this session both
independently arrived at the same root cause, from two different fix attempts:

- **Four prior attempts** (reflecting the ring, swapping which same-strand neighbor
  governs which substituent, and — this session — placing O3'/C5' at a fixed real
  bond angle off the ring instead of the real neighbor direction) all cleared the
  same-residue `chain_closest_to_own_ribose` check but would tear the *inter-residue*
  phosphodiester backbone bond, because `_build_backbone_bonds()` draws that bond
  against the exact same `toward_next`/`toward_previous`-derived O3'/C5' positions.
  Any fix that redirects O3'/C5' away from the real same-strand-neighbor direction
  repeats this failure, regardless of how the redirection is computed.
- **The abandoned "1b" elbow-flex construction** (prior design doc) tried flexing
  the ring's own C3'/C4' vertices within Gelbin ±2σ ring-internal tolerance; no
  candidate simultaneously cleared the 12.0 collision threshold and stayed in
  tolerance, so it was never shipped.

**Both established constraints stand for this fix too:**
1. O3'/C5' must extend in exactly the real `toward_next`/`toward_previous`
   direction — never redirected, tie-broken, or angle-substituted.
2. Any ring-shape change must stay within Gelbin et al. (1996) Table 4 tolerance,
   or must not flex the ring's internal shape at all (a rigid rotation sidesteps
   this constraint entirely, by construction).

## Fix: two-tier approach — refined rotation (primary), real-direction extension (fallback)

Ship both pieces together as one connected mechanism, verified in the order below
(matching this project's "prove it in Python first" convention,
`diagnosis/diag_self_paired_construction.py`'s established pattern) — not "ship A,
maybe add B later."

### Tier 1 (primary): closed-form continuous rotation angle

Replaces the current binary 0°/180° choice in `derive_self_paired_ring()` with a
single continuous rotation angle θ, computed directly from real inputs already
available to the function (`pairing_direction`, `toward_next`, `toward_previous`),
applied as one rigid rotation of the whole natural ring (C1'/C2'/C3'/C4'/O4'
together) around the pivot (C1').

1. **Bulge-away feasible arc (existing constraint, unchanged goal):** the set of θ
   keeping the ring's bulge (a fixed direction in the ring's own unrotated frame)
   facing away from `pairing_direction` — a ~180°-wide arc, as already
   characterized in the prior design doc's root-cause section.
2. **Chain-clearance target (new):** the angle that would point the ring's own
   C3'-C4' bond directly away from the strand's forward direction, derived from a
   blend of `toward_next` and `-toward_previous` (these agree in the common
   straight-strand case, so a single θ can satisfy both O3' and C5' simultaneously
   there; near a real curve they diverge modestly and the blend is a reasonable
   compromise, not an exact solution for both).
3. If the chain-clearance target angle falls inside the bulge-away feasible arc,
   use it exactly — both goals satisfied by one rotation. If it falls outside,
   clamp to the nearest arc edge instead of falling back to a disjoint candidate —
   continuous in the real inputs, avoiding the discrete-jump mechanism that caused
   the previously-reverted search's flicker.

Rigid rotation ⇒ automatically chirality-safe via the same rotation-equivalence
proof already established for the shipped 1a. No Gelbin ring-tolerance checking
required — the ring's internal shape is never altered, only its orientation.

### Tier 2 (fallback): per-substituent real-direction extension

After Tier 1 places the ring, compute O3' and C5' the normal way (`derive_substituents()`,
real direction, `bond_length`) and check each independently against the 12.0
collision threshold across all 5 ring atoms. **O3' and C5' are evaluated and
fixed independently** — the design doc's own note that a single ring rotation
angle can leave one clean and the other not still applies.

For whichever substituent(s) still fall under threshold: solve, closed-form, the
smallest distance `L ≥ bond_length` along the *same, untouched* real direction
that clears all 5 ring atoms by 12.0. This never changes direction — only how far
along the already-correct real ray the atom sits — so it cannot reproduce the
backbone-tearing failure mode named above.

- Applied per-substituent, opt-in only where Tier 1 didn't already achieve
  clearance on its own — most residues should see no visual change to bond
  length at all.
- Capped at a maximum stretch (starting value 2.5× `bond_length`, to be confirmed
  against real fixture data during the Python harness step). If even the capped
  distance can't clear 12.0 for some residue, that residue's collision is left
  open and explicitly documented — the same "stop condition, don't silently
  degrade further" pattern as the prior design doc, not an unbounded stretch.

## Verification plan

Matches this project's established convention: analytic proof in Python
(`diagnosis/`) before any GDScript, then live F9 dump confirmation, in that order.

1. Implement Tier 1's θ formula in a Python harness (extending
   `diagnosis/diag_self_paired_construction.py`'s existing fixtures — boundary and
   interior real residues already recorded there). Confirm chirality via the
   existing rotation-equivalence check (rigid rotation, no new proof machinery
   needed).
2. Confirm `bulge_vs_pairing_dot` stays negative for every fixture (the bulge-away
   constraint must never regress — reopening it would reintroduce the original
   Bug V ring-vs-partner overlap).
3. Measure real chain clearance for those fixtures with Tier 1 alone. Report
   honestly which fixtures still need Tier 2.
4. Implement Tier 2's per-substituent `L` solve in the same harness; confirm it
   clears 12.0 for whichever fixtures Tier 1 alone didn't, within the stretch cap.
5. Port the validated Python math to GDScript (`derive_self_paired_ring()` and a
   small addition to `derive_substituents()`), same line-for-line-translatable
   convention as the prior design doc's Task 5/6.
6. Live F9 dump before/after on a paused, fixed scene:
   `chain_closest_to_own_ribose`, `bulge_vs_pairing_dot`, `anchor_alignment_dot`
   (base rotation is untouched by this fix and should read identically to before).
7. Flicker check: multiple F9 dumps seconds apart during live simulation motion —
   confirm θ changes continuously with the real inputs, no discrete jumps.
8. Confirm leading/lagging output is byte-identical via dump diff — no code path
   reachable from `is_self_paired_template = false` is touched by this fix at all.
9. Live screenshot of the self-paired template region, confirming no visible
   overlap remains (or, for any residue that hits Tier 2's stretch cap, that the
   stretched bond is visually acceptable rather than a gross artifact).

## Rollback

This fix must be revertible with a single command from a single prompt. Concretely:

- The entire behavior change (Tier 1 + Tier 2, both inside `ribose_deriver.gd`)
  ships as **one commit**. Any earlier, non-behavioral commits in the same work
  (e.g. the Python harness under `diagnosis/`, which is never imported by the
  game) land separately, before it — so `git revert <that one commit>` undoes
  exactly the rendering change and nothing else, cleanly, with no conflicts
  expected against unrelated work.
- No existing function is deleted or renamed by this fix (`derive_self_paired_ring()`
  keeps its exact signature from the prior design doc's Task 5/6; `derive_substituents()`
  keeps its existing signature and default-`false` new parameter, if any is added
  for Tier 2) — a revert restores the prior (already-shipped, already-working)
  Branch B behavior exactly, with no follow-up cleanup required elsewhere.
- Verified directly as part of the implementation plan: after the fix commit,
  `git revert --no-commit <sha> && git diff --cached` should show only
  `ribose_deriver.gd` changing, reverting cleanly to the pre-fix state; then
  `git reset --hard` (or simply not committing the revert) to restore the fix
  for continued work.

## Leading/lagging safety (explicit, verifiable guarantee)

Restated directly, since it is the other hard constraint on this fix: no line
in `apply_strand_direction()`, `STRAND_DIRECTION_SIGN`, or either call site that
passes `is_self_paired_template = false` (leading/lagging's path through
`derive_substituents()`) may change. This is mechanically checkable, not just an
intention — the implementation plan's verification step must include a `git diff`
review confirming the only functions touched are `derive_self_paired_ring()` and,
for Tier 2, the existing `is_self_paired_template`-gated branch already present in
`derive_substituents()` (added, then reverted, earlier this session — see git
history on this branch), never the `else` branch leading/lagging takes.

## Out of scope

- Gelbin ring-internal tolerance checking (not applicable — Tier 1 is a rigid
  rotation, never distorts the ring's own shape).
- `NitrogenBaseDeriver`'s base-rotation logic (`anchor_alignment_dot` already
  reads a clean 1.0 for every sampled residue; untouched by this fix).
- Any change to leading/lagging geometry (`apply_strand_direction()`,
  `STRAND_DIRECTION_SIGN`) — confirmed correct, not touched by any code path this
  fix adds.
- The unpaired-first-base-pair symptom (Task 8/9 in the prior design doc's
  plan) — separate, independent bug.

## As-Built (2026-08-04)

Both tiers were implemented and reviewed exactly to this spec, in a git
worktree (`.claude/worktrees/self-paired-chain-fix`). Live testing found real
defects the design didn't anticipate, each fixed in turn: a floating-point
knife-edge in the rotation clamp's safety margin (`bulge_vs_pairing_dot`
landing exactly on `0.0` for every sampled fixture, not the intended
comfortably-negative value); a genuine game-freezing bistable oscillation at
the arc-clamp boundary (`theta_center`/`theta_ideal` are ~180° apart
structurally for this project's fixed layout, not occasionally — placing the
old sign-based tie-break permanently on the wraparound knife-edge); an
inter-residue collision from Tier 2's reach having no bound tied to the real
neighbor distance; and a collision-clearance threshold silently based on
`theme_manager.gd`'s script default (`molecular_atom_radius = 6.0`) rather
than the real scene's override (`4.0`).

After all four fixes, live testing found a residue where the real substituent
direction passes only 3.92 world units from its own C1' atom — below the
correct 8.0 threshold — a hard geometric floor Tier 2's reach-along-a-fixed-
direction approach cannot cross no matter how the reach is tuned. **This is
the design's real limit, not an unfixed bug**: a single live, closed-form
rotation plus a direction-preserving distance extension cannot satisfy this
residue class, for the same "~180° apart" structural reason this document's
own Fix section named as 1a's known limit before implementation began — it
resurfaced on the chain-clearance axis instead of the bulge-safety axis this
document anticipated, but it is the same underlying conflict.

**Superseded by a new Lattice-phase decision**, `docs/MolecularStructureDesign.md`'s
"Self-paired geometry is baked once per residue, not recomputed live" section
(2026-08-04): rather than a fifth live-formula patch, self-paired geometry
moves to a bake-once-cache-forever model, unlocking a real search budget
(impossible per-frame) without reintroducing flicker risk (impossible to
recompute what is never recomputed). Both tiers implemented here become
bake-time-only code under that new design, no longer part of the per-frame
render path. This document's own numbers (the 3.92-unit floor, the 8.0
threshold, the ~180° structural conflict) are exactly what motivated that
decision — recorded here rather than silently left to contradict it.
