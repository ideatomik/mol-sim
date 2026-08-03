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

### Confirmed live: the shipped tie-break epsilon does not fix the flicker

Two F9 dumps taken moments apart on 2026-08-03 (during this brainstorm,
against the current, already-shipped code — not a hypothetical) show the
tie-broken winner itself changing between dumps: `template_top` slot 56 went
from 165° (clearance 2.844) to 195° (clearance 2.624); `template_bottom`
slot 0 went from 15° to 10°. Inspecting the full candidate table for the
165°→195° case shows this is **not** a near-tie flip of the kind the epsilon
was built for — 165° is a fully **invalid** candidate in the second dump
(`o3_side` fails its margin) because the real `toward_previous` vector
shifted substantially between the two presses (y-component -0.126 → -0.986,
consistent with the live template-rail curve moving between frames). The
true optimum did not wobble between near-ties; it discretely jumped to a
different valid region once the old winner left the feasible set.

This rules out "tighten the tie-break window" as a fix: an epsilon only
merges candidates that are genuinely near each other on a landscape that
holds still. It cannot prevent a discrete argmax search from jumping between
disjoint valid regions when the landscape itself moves frame to frame, which
is what a search over rotation-angle candidates structurally is. This is
independent evidence — not merely the design doc's own reasoning — that the
search-based approach cannot be patched into stability; the fix has to stop
being a per-frame independent search.

## Fix: derive the ring from both real neighbor directions at once

A single rigid rotation of the natural pentagon has exactly one free
parameter (the angle around the C1' pivot). Bug V/W's own history already
demonstrates, empirically, that one angle cannot simultaneously satisfy both
real constraints — bulge facing away from the partner, and the chain (built
from real `toward_next`/`toward_previous`) clearing the ring's own atoms —
without a forced trade-off (measured collision 0.04-0.21 at the tightest,
2.5-2.9 with today's net-side constraint added, worse than leading/lagging's
clean 10.8). Rotating one fixed shape is not sufficient parameter space for
two independent real-world directional constraints.

The fix is to stop treating self-paired ring placement as "rotate a
pre-built pentagon" and instead derive the ring's vertex positions directly
from the real direction data available — the same "derive, don't rotate a
guess into place" principle `derive_fused_ring()` already uses elsewhere in
this file (it builds the purine's second ring from a real shared edge plus a
fold-away direction, not by rotating an independently-placed ring). Concrete
mechanism (to be worked out against live F9 data during implementation, not
guessed here): use the real same-strand-neighbor vectors as part of the
ring's own construction — e.g. anchoring the C4'-side of the ring toward
whichever of `toward_next`/`toward_previous` is physically adjacent to it —
so the chain and ring are built from the same real vector and cannot
disagree by construction, while the bulge-vs-partner requirement is
satisfied as a consequence of the antiparallel geometry rather than forced
by an independent rotation search.

### Chirality safety is a first-class, up-front requirement — not a post-hoc screenshot check

`apply_strand_direction()`'s existing 180°-rotation approach is chirality-safe
*for free*: any rotation of a rigid shape around a fixed pivot has
determinant +1 by construction, so it can never silently produce the L-ribose
mirror image the way a reflection would (`derive_ring()`'s own "HARDCODED
HANDEDNESS" comment, and the `reverse=true` L-ribose demo already proven and
reverted in this codebase, both exist specifically to guard against this).
Deriving a genuinely new local frame from two independent real-world
direction vectors does **not** inherit that guarantee automatically — it is
new geometry construction, not a rotation, and must be proven safe rather
than assumed safe.

**Required before this fix ships**, as part of implementation, not deferred
to visual inspection:
1. State the construction as an explicit, closed-form function of the real
   input vectors (`toward_next`, `toward_previous`, `pairing_direction`) —
   no free parameter chosen by search or eyeballing.
2. For a representative sample of self-paired residues (both strands, both
   "only one real neighbor present" boundary cases, and an interior residue
   with both neighbors present), compute the construction's output ring
   vertex positions, then independently solve for the rigid rotation angle
   (around the same C1' pivot) that would map the *canonical* D-ribose
   pentagon (`derive_ring()`'s unrotated output) onto at least two
   non-collinear vertices of that output.
3. Confirm the **entire** vertex set matches that single rotation exactly
   (not just the two solved-for points) — proving the construction is
   everywhere equivalent to one proper rotation of the canonical pentagon,
   never a reflection or an independently-placed vertex set that only
   coincidentally resembles one from two points. This is the same
   "compute it, compare to the mirror formula, confirm they don't match"
   analytic-proof discipline already used once in this file for the
   `reverse=true` L-ribose demo — applied here as a mandatory pre-ship gate,
   not an optional demo.
4. Only after step 3 passes for every sampled case does a live screenshot
   serve as confirmation of visual correctness — it is not a substitute for
   the analytic proof, since a chirality bug and a merely-ugly-but-correct
   layout can look similar in a single screenshot.

**Deleted:** `resolve_self_paired_ring_rotation()`, `debug_self_paired_
candidates()`, `SELF_PAIRED_ROTATION_SEARCH_STEPS`, `SELF_PAIRED_BULGE_
DOT_MARGIN`, `SELF_PAIRED_NET_SIDE_MARGIN_RATIO`, `SELF_PAIRED_TIE_BREAK_
EPSILON_RATIO`, `_dump_self_paired_boundary_trace()`, and the dead
`apply_partner_flip()`.

This is real, unscoped design work — the exact construction is not fixed by
this document, only its required properties (grounded in real vectors,
provably chirality-safe, no discrete search). If no construction satisfying
both real constraints simultaneously and passing the chirality proof is
found, that is a legitimate outcome to report back before shipping anything,
not a reason to quietly fall back to the rejected search or the rejected
always-flip rule.

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

**Sequencing: lands as its own commit, before the rotation fix**, not
bundled together — verified independently (dump-diff, no behavior change)
so that if the rotation fix needs debugging later, isolating the cause
doesn't require reviewing a ~700-line file move at the same time.

## Out of scope

- Any change to leading/lagging geometry (confirmed correct, untouched).
- Any change to the three-layer model, fold engine, or topology layer.
- Base-stacking, major/minor groove, sugar pucker variants — the existing
  scope fence in `MolecularStructureDesign.md` still applies.
- Re-deriving `derive_substituents()`'s `pairing_direction`-based flip for
  leading/lagging (Open Question 10 in `MolecularStructureDesign.md`,
  already carried as a named exception) — not touched by this fix.

## Testing / verification plan

- Diagnostics-extraction move verified first, on its own, by diffing full
  dump output before/after the file split for one identical scene state.
- Chirality proof (see above) run and passing for every sampled case
  *before* any visual check of the rotation fix — analytic, not screenshot.
- F9 live geometry dump, before and after, on a scene with the self-paired
  template state visible (no enzymes active, fresh sequence load) —
  confirm `chain_closest_to_own_base`/`chain_closest_to_own_ribose` and the
  ring-vs-chain clearance numbers at the previously-affected slots, and
  record whatever they are honestly (this fix is not assumed to reach
  leading/lagging's clean 10.8 — only to stop trading collision for flicker
  or vice versa).
- Multiple F9 dumps taken seconds apart, including at least one where the
  underlying template curve has visibly moved between presses (not a static
  scene) — confirm byte-identical ring rotation output despite that motion,
  since the flicker root-caused above only reproduces under real curve
  movement, not a frozen scene.
- Live screenshot of the first base pair in the sequence — confirm it
  renders paired with hydrogen bonds and correct orientation.
