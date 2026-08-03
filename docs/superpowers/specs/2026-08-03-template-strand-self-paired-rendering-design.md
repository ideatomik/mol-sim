# Template-Strand Self-Paired Rendering Fix — Design

_Brainstormed 2026-08-03. Scope: `scripts/molecule_structure_renderer.gd`,
`scripts/ribose_deriver.gd`. Follows the three-layer model and the "Layout
rule: substituent direction must be grounded, not shared" principle already
recorded in `docs/MolecularStructureDesign.md`._

## Problem

The molecular-zoom skeletal renderer produces visually correct geometry for
leading and lagging strands (confirmed by the user: "perfect result"), but
the template strands show three defects while in the self-paired state (both
template strands still hydrogen-bonded to each other, before either
polymerase has caught up):

1. Backbone overlap: C5' overlaps C3'.
2. Frame-to-frame flicker in ring/base orientation.
3. Backbone overlap: O3' overlaps C4'.
4. The first base pair in the sequence renders unpaired — wrong orientation,
   no hydrogen bonds drawn — even though it should be a real pair.

## Root cause

Leading/lagging strands derive ring orientation with a simple, deterministic
rule: a fixed per-strand sign (`STRAND_DIRECTION_SIGN` /
`apply_strand_direction()`), no search. This is grounded, cheap, and — per
the confirmed visual result — correct.

The self-paired-template case instead runs
`RiboseDeriver.resolve_self_paired_ring_rotation()`: a 72-step brute-force
search over candidate rotation angles, picking whichever maximizes a
"clearance" score against several constraints (bulge-vs-partner direction,
O3'/C5' net-side, self-collision), with a hand-tuned tie-break epsilon added
specifically to fight a previously-observed flicker. This is the exact
failure pattern `MolecularStructureDesign.md`'s own "Layout rule" section
already names twice (Bug D/F, Bug J/L): a proxy metric search standing in
for grounded, derived geometry.

Consequences of the search approach, as designed:
- **Flicker (symptom 2):** near-tied candidate angles can flip which one
  "wins" from small real (not floating-point-noise) frame-to-frame input
  changes — the tie-break epsilon mitigates but does not eliminate this,
  and is itself evidence the underlying approach is unstable.
- **Overlaps (symptoms 1, 3):** the search's candidate set and clearance
  metric are not guaranteed to contain or select the chemically real
  configuration — there is a diagnostic already in the codebase
  (`_derive_full_residue()`'s `chain_closest_to_own_base` /
  `chain_far_from_c1`, added under a "slot-0-broken-render investigation"
  comment) built specifically to trace an O3'-over-C4' overlap at slot 0,
  indicating this exact symptom was previously observed and never resolved.

Symptom 4 (unpaired first base pair) is very likely a **separate** bug, not
caused by the rotation search — most plausibly in `_pair_for_slot()`'s
helicase-position fallback, which has no `slot-1` neighbor to reference at
the strand's first slot. It is investigated and fixed independently.

Also found in passing: `RiboseDeriver.apply_partner_flip()` is dead code —
implemented and documented as "the fix" for an earlier bug (Bug L), but no
call site invokes it anywhere in the codebase (verified via grep). The
self-paired branch uses the search instead; the fixed-sign branch (leading/
lagging) doesn't use it either. It is deleted rather than resurrected.

## Fix: deterministic, grounded self-paired rotation

Replace the search with a single deterministic geometric test, restoring the
approach the design doc's own history shows was tried first (Bug V) before
being replaced by the search (Bug W) — but this time also fixing the chain
placement that motivated Bug W's replacement in the first place, rather than
reverting to the exact same broken combination.

- **Ring rotation:** one dot-product test — does the ring's natural bulge
  direction face toward or away from the real partner (`pairing_direction`,
  computed from real template_top/template_bottom world positions, same as
  today)? Rotate 180° around the C1' pivot if it faces the partner, identity
  otherwise. This is the same test `resolve_self_paired_ring_rotation()`
  already computes internally (`bulge_vs_pairing_dot`) — reused as the sole
  decision, not one of several constraints fed into a search.
- **Substituent chain (O3'/C5'/O5'/alpha-phosphate):** continues to derive
  from real `toward_next`/`toward_previous` same-strand-neighbor vectors
  (already the case — this part is not a search and is not the suspected
  cause of the overlap). The exact anchoring fix for the O3'-over-C4'
  overlap is determined during implementation using the existing F9 live
  dump (`chain_closest_to_own_base`), the same evidence-before-assertion
  discipline every other bug in this file was resolved with — not guessed
  in this document.
- **Deleted:** `resolve_self_paired_ring_rotation()`, `debug_self_paired_
  candidates()`, `SELF_PAIRED_ROTATION_SEARCH_STEPS`, `SELF_PAIRED_BULGE_
  DOT_MARGIN`, `SELF_PAIRED_NET_SIDE_MARGIN_RATIO`, `SELF_PAIRED_TIE_BREAK_
  EPSILON_RATIO`, `_dump_self_paired_boundary_trace()`, and the dead
  `apply_partner_flip()`.

This eliminates the flicker by construction (no near-tied candidates to
choose between — the same input always produces the same output via one
comparison) and is expected to resolve the overlaps by using the same
grounded-derivation approach already confirmed correct for leading/lagging,
rather than a proxy search.

## Fix: unpaired first base pair

Root-cause `_pair_for_slot()`'s behavior at the template strand's first
slot via a live F9 dump before changing anything (same discipline as every
other fix in this file). The leading hypothesis — no real `slot-1`
same-strand neighbor to compare against `helicase_x`, or an off-by-one in
that boundary check — is a hypothesis to verify, not an assumed fix.

## Diagnostics extraction

`molecule_structure_renderer.gd` is 1568 lines; roughly the back half
(`_dump_geometry_diagnostic()` and its ~10 helper functions — the F9
dump, pairing scan, same-letter scan, full-residue derivation for
diagnostics, boundary trace) is a self-contained diagnostic subsystem, not
part of the render path itself.

Move it to a new file, `scripts/molecule_geometry_diagnostics.gd`, as a
static-function utility (mirroring `RiboseDeriver`/`NitrogenBaseDeriver`'s
own `class_name ... extends RefCounted` pattern) taking the renderer,
replication manager, and template-sim references it needs as parameters.
`molecule_structure_renderer.gd` keeps only the F9 keypress listener
(`_process()`'s existing debounce logic) and delegates the dump call
itself. Pure move — no behavior change, no logic rewritten — verified by
diffing dump output before/after the move for an identical scene state.

This is done in the same pass since the file is already being edited for
the rotation fix, and a smaller file makes the rotation fix itself easier
to review.

## Out of scope

- Any change to leading/lagging geometry (confirmed correct, untouched).
- Any change to the three-layer model, fold engine, or topology layer.
- Base-stacking, major/minor groove, sugar pucker variants — the existing
  scope fence in `MolecularStructureDesign.md` still applies.
- Re-deriving `derive_substituents()`'s `pairing_direction`-based flip for
  leading/lagging (Open Question 10 in `MolecularStructureDesign.md`,
  already carried as a named exception) — not touched by this fix.

## Testing / verification plan

- F9 live geometry dump, before and after, on a scene with the self-paired
  template state visible (no enzymes active, fresh sequence load) —
  confirm `chain_closest_to_own_base` and the ring-vs-chain clearance
  numbers clear their overlap thresholds at the previously-affected slots.
- Two F9 dumps ~3 seconds apart on the same static scene — confirm
  byte-identical ring rotation output (flicker regression check).
- Live screenshot of the first base pair in the sequence — confirm it
  renders paired with hydrogen bonds and correct orientation.
- Diagnostics-extraction move verified by diffing full dump output
  before/after the file split for one identical scene state.
