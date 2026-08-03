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

Two structurally different fixes exist for symptoms 1-3, with different
achievable outcomes, and this document has to commit to one rather than
leave it ambiguous:

- **1a — closed-form rigid rotation.** Same one-parameter family the current
  search already explores (a single rotation angle around C1'), just picked
  by a formula instead of a search. Fixes the flicker. Cannot fix the
  collision, provably (see Root cause) — this is not a risk to discover
  during implementation, it is known now.
- **1b — flexible ring construction.** Derives C3'/C4' more independently
  from the two real neighbor vectors, adding a genuine second degree of
  freedom instead of rotating one fixed shape. The only version that could
  touch the collision, because it's the only version with room to.

**This document proposes 1b**, with 1a as the explicit, named fallback if 1b
does not pan out (see the Fix section's stop condition) — not "try 1b, and
if it's hard, quietly ship something in between."

## Root cause

Leading/lagging strands derive ring orientation from a **fixed constant per
strand identity** (`STRAND_DIRECTION_SIGN` / `apply_strand_direction()`) —
not from real vectors at all, and not a per-frame derivation of anything.
This works because each of those strands has exactly one real partner for
its entire life (leading always pairs with template_top, lagging with
template_bottom): a fixed convention is correct precisely because nothing
about the correct orientation ever changes.

**That is the actual root cause of why the self-paired case cannot reuse
leading/lagging's trick, not a detail to note in passing:** a self-paired
template residue's correct partner genuinely changes over its lifetime — it
starts self-paired with the other template strand, then (once the
polymerase catches up) its real biological partner becomes the newly
synthesized leading/lagging strand. No fixed constant can be correct across
that transition; the self-paired case is structurally required to consult
live position data, which is exactly why it was built around a per-frame
search in the first place and why that search cannot simply be replaced with
another fixed convention.

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

## Fix: 1b, flexible ring construction from both real neighbor directions

A single rigid rotation of the natural pentagon (1a) has exactly one free
parameter: the angle around the C1' pivot. Bug V/W's own history already
proves, empirically, that one angle cannot simultaneously satisfy both real
constraints — bulge facing away from the partner, and the chain (built from
real `toward_next`/`toward_previous`) clearing the ring's own atoms —
without a forced trade-off (measured collision 0.04-0.21 at the tightest,
2.5-2.9 with today's net-side constraint added, worse than leading/lagging's
clean 10.8). This is stated plainly, up front, as a known limit of 1a, not a
risk to rediscover during implementation: **1a can fix the flicker (it is
a closed-form formula instead of a search, so it cannot jump between
discrete candidates the way the search does) but it cannot fix the
collision — there is no angle to find that a formula would find instead of
a search missing.**

This document proposes **1b**: give the construction a genuine second
degree of freedom instead of rotating one fixed shape, by deriving C3'/C4'
more independently from the two real neighbor vectors rather than as fixed
vertices of a rigid pentagon that only ever rotates as a unit. This is the
only version of the fix with room to address the collision at all.

**This is new geometric territory with no existing function in this
codebase to model the construction on.** `derive_fused_ring()` is precedent
for the _principle_ only — "derive from real data instead of rotating a
guess into place" — not for the math: it solves a different problem (a
second ring folded off an already-placed shared edge, one discrete
fold-direction choice, not a continuously flexed single ring). Nobody
implementing this should go looking for a reusable pattern in
`derive_fused_ring()`, `derive_regular_ring()`, or `apply_strand_direction()`
— none of them build a non-rigid single ring, and the construction here has
to be designed from scratch against live F9 data, the same way every other
piece of real geometry in this file was.

Concrete mechanism is deliberately not fixed by this document — only its
required properties are (see below). The starting idea to investigate: let
`toward_next`/`toward_previous` (whichever is physically adjacent to the
C4' side) directly influence where C3'/C4' land, rather than deriving them
only via `derive_substituents()`'s downstream chain after the ring has
already been rigidly placed — so the ring and the chain are grounded in the
same real vector where they meet, instead of a rigid ring fighting an
independently-aimed chain for the same space.

### Chemical tolerance bound — sourced

Because 1b lets C3'/C4' deviate from the canonical regular-pentagon
positions, the construction needs an explicit upper bound on how far that
deviation is allowed to go before the result stops being defensible ribose
geometry — not "whatever the other constraints happen to need."

Source: Gelbin, Schneider, Clowney, Hsieh, Olson, Berman (1996), "Geometric
Parameters in Nucleic Acids: Sugar and Phosphate Constituents," J. Am. Chem.
Soc. 118, 519-529, Table 4 — deoxyribose values (the correct sugar for this
project; DNA, not RNA), combined across sugar pucker conformations, N=47 real
crystal structures. Mean ± σ (standard deviation):

| Angle | Mean | σ | Governs |
| --- | --- | --- | --- |
| C2'-C3'-C4' | 103.2° | 1.0° | ring shape (internal) |
| C3'-C4'-O4' | 105.6° | 1.0° | ring shape (internal) |
| C4'-O4'-C1' | 109.7° | 1.4° | ring shape (internal) |
| C5'-C4'-C3' | 114.7° | 1.5° | C5' substituent swing (exocyclic) |
| C5'-C4'-O4' | 109.4° | 1.6° | C5' substituent swing (exocyclic) |
| C4'-C3'-O3' | 110.3° | 2.2° | O3' substituent swing (exocyclic) |
| C2'-C3'-O3' | 110.6° | 2.7° | O3' substituent swing (exocyclic) |

The top three (ring-internal) angles bound how far the ring's own shape may
deviate from the canonical pentagon; the bottom four (exocyclic) bound how
far the O3'/C5' substituent directions may swing independent of the ring —
looser than the ring-internal angles, matching the real physical
expectation that substituents flex more than the ring itself.

**Hard construction limit: ±2σ per angle**, applied per-angle from the table
above (tighter on the three ring-internal angles, looser on the four
exocyclic ones — not one flat number for all seven). Any candidate
construction whose resulting bond angles exceed ±2σ on any listed angle, for
any sampled residue, is rejected outright — regardless of whether it would
otherwise resolve the collision. This is step 4 of the required proof below,
made concrete rather than left as a TBD gap.

### Orientation-preservation proof — chirality safety for a flexible construction

`apply_strand_direction()`'s existing 180°-rotation approach (1a, and every
other rigid rotation already in this file) is chirality-safe for free: any
rotation of a rigid shape around a fixed pivot has determinant +1 by
construction, so it can never silently produce the L-ribose mirror image the
way a reflection would (`derive_ring()`'s own "HARDCODED HANDEDNESS" comment,
and the `reverse=true` L-ribose demo already proven and reverted in this
codebase, both exist specifically to guard against this).

**A flexible construction (1b) does not inherit that guarantee, and the
rotation-equivalence proof that would gate 1a does not apply to it.** A
correctly-built flexed pentagon will _not_ equal any rotation of the
canonical regular pentagon — that is expected and correct, not a failure —
so testing "does the output match some single rotation of the canonical
shape" would reject good 1b output, not merely catch mirrors. 1b needs a
different, real safety check:

**Required before 1b ships, as part of implementation, not deferred to
visual inspection:**

1. State the construction as an explicit, closed-form function of the real
   input vectors (`toward_next`, `toward_previous`, `pairing_direction`) —
   no free parameter chosen by search or eyeballing.
2. For a representative sample of self-paired residues (both strands, both
   "only one real neighbor present" boundary cases, and an interior residue
   with both neighbors present), compute the construction's output ring
   vertex positions in the fixed atom-walk order `RING_ROLE_SUFFIXES`
   already uses (C1'→C2'→C3'→C4'→O4').
3. Compute the signed area of that vertex polygon (shoelace formula) and
   confirm its sign matches the signed area of the canonical D-ribose
   pentagon (`derive_ring()`'s unrotated output), walked in the same atom
   order, for every sampled residue. A flipped sign means the construction
   produced the mirror-image (L-ribose) vertex ordering regardless of how
   plausible the shape looks — this is the flexible-construction equivalent
   of the rotation-equivalence proof, verifying orientation preservation
   instead of exact rigid-rotation equivalence.
4. Confirm every sampled residue's relevant bond angles (the seven listed in
   the chemical tolerance bound above) fall within ±2σ of their Gelbin et
   al. mean.
5. Only after steps 3 and 4 pass for every sampled case does a live
   screenshot serve as confirmation of visual correctness — it is not a
   substitute for either proof, since a chirality bug or an out-of-tolerance
   deviation can look plausible in a single screenshot.

### Stop condition

If no construction is found that satisfies both real constraints, the
orientation-preservation proof, and the chemical tolerance bound, **ship 1a
alone instead**: the closed-form rigid rotation (bulge-away-from-partner
test, gated by the rotation-equivalence proof described in the prior
revision of this document). That ships with the flicker fixed and the
collision explicitly documented as a known, open, un-fixed-by-this-pass
issue — not silently reverted to the rejected search, and not a decision
deferred to be made mid-implementation.

**Deleted either way:** `resolve_self_paired_ring_rotation()`,
`debug_self_paired_candidates()`, `SELF_PAIRED_ROTATION_SEARCH_STEPS`,
`SELF_PAIRED_BULGE_DOT_MARGIN`, `SELF_PAIRED_NET_SIDE_MARGIN_RATIO`,
`SELF_PAIRED_TIE_BREAK_EPSILON_RATIO`, `_dump_self_paired_boundary_trace()`,
and the dead `apply_partner_flip()`.

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

Each check below names which construction (1a or 1b — see Fix section) it
verifies, so this plan cannot silently drift out of sync with whichever one
actually ships.

- Diagnostics-extraction move (applies to either branch) verified first, on
  its own, by diffing full dump output before/after the file split for one
  identical scene state.
- **If 1b ships:** the orientation-preservation proof (signed-area check,
  step 3 above) and the chemical-tolerance check (step 4 above, ±2σ per
  angle against the Gelbin et al. Table 4 values) both run and pass for
  every sampled case _before_ any visual check — analytic, not screenshot.
  **If 1a ships instead (stop condition fired):** the
  rotation-equivalence proof (full vertex set matches one rotation of the
  canonical pentagon) runs and passes instead — the two proofs are not
  interchangeable and only one applies to whichever branch actually shipped.
- F9 live geometry dump, before and after, on a scene with the self-paired
  template state visible (no enzymes active, fresh sequence load) — applies
  to either branch — confirm `chain_closest_to_own_base`/
  `chain_closest_to_own_ribose` and the ring-vs-chain clearance numbers at
  the previously-affected slots, and record whatever they are honestly (1b
  is not assumed to reach leading/lagging's clean 10.8; 1a is not expected
  to move these numbers from today's baseline at all, since it only
  addresses the rotation-angle choice, not the collision).
- Multiple F9 dumps taken seconds apart, including at least one where the
  underlying template curve has visibly moved between presses (not a static
  scene) — applies to either branch — confirm byte-identical ring rotation
  output despite that motion, since the flicker root-caused above only
  reproduces under real curve movement, not a frozen scene.
- Live screenshot of the first base pair in the sequence (unpaired-first-pair
  fix, independent of 1a/1b) — confirm it renders paired with hydrogen bonds
  and correct orientation.
