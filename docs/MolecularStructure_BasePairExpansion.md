# MolSim — Molecular Structure: Base-Pair Expansion (Growth Session 2)

_Resolution/expansion doc, following the `MolecularStructure_OpenQuestions_*.md`
naming convention. Companion to `MolecularStructureDesign.md` (the Lattice-
phase foundation, shared with Krebs) — this doc does NOT rewrite that file's
body; it records the decisions specific to expanding the DNA-first milestone
from "ribose + phosphodiester bond, synthesized strand only" to the full
double-ribbon view. No As-Built section yet — nothing here has shipped and
gotten a real editor round-trip at the time of writing._

---

## Scope statement

This is a milestone **expansion**, not scope drift. Growth Session 1 built
ribose + the phosphodiester operator + skeletal rendering for the
synthesized strand only, per the original scope fence. After a CQA pass
surfaced three real bugs (see below) and revealed the synthesized-strand-only
view read as confusing in isolation, the user explicitly expanded scope to:
the entire flat double ribbon — both strands (original template + newly
synthesized), full nitrogenous bases (purines and pyrimidines, not just the
sugar-phosphate backbone), and hydrogen bonds between paired bases — all in
the same CPK-style circles+labels rendering, still gated to deep free-camera
zoom only.

**The original scope fence's "stop" boundary still holds.** Base stacking,
major/minor groove geometry, and sugar pucker variants remain out of scope —
this expansion is base-PAIRING geometry (what the fence was drawn around,
per `MolecularStructureDesign.md`'s "First milestone: DNA, not Krebs"
section), not a step past it.

---

## Decision: base topology is a whole-nucleotide seed per base letter, no glycosidic-bond operator

`RiboseDeriver.build_incoming_nucleotide_seed()` now takes a `base_letter`
parameter and builds the base's ring atoms + substituents + the glycosidic
bond directly into the same topology as the ribose ring, via
`NitrogenBaseDeriver.build_base_seed_into()`. One topology object per
nucleotide — ribose + phosphate + base — matching how a real nucleotide is
one molecule.

**No `ReactionOperator` models base attachment.** A `ReactionOperator`
exists for simulated reaction *steps* with real `teaching_text` content —
phosphodiester bond formation is one; "the base is drawn attached to its
sugar" is not a taught mechanism this milestone models as happening mid-
simulation. The base is simply always present, on both synthesized and
template nucleotides. Wrapping it in the fold-engine's four-array diff
formalism would be unneeded machinery, no different in spirit from Q5's own
"don't build Option B before Q1 forces it" reasoning — formalism is earned
by an actual before/after state this simulation shows, not added
speculatively.

Glycosidic bond: purine N9 to ribose C1'; pyrimidine N1 to ribose C1' — real
Watson-Crick numbering, kept correct since it's the first connectivity fact
a chemistry-literate viewer would check.

Ring geometry: `RiboseDeriver.derive_ring()`'s regular-N-gon placement is a
**pure utility** (no tuned/behavioral value — straight trigonometry), so it
is extracted immediately as `NitrogenBaseDeriver.derive_regular_ring()`
rather than waiting for a third copy, per `SKILL.md`'s pure-utility-vs-
behavioral-constant extraction rule. `derive_ring()` becomes a thin wrapper.
Pyrimidines (single 6-ring) reuse it directly at N=6. Purines are genuinely
new work — a fused bicyclic system (6-ring + 5-ring sharing the C4-C5 edge)
is not expressible as one regular polygon; `derive_fused_ring()` places the
5-ring's remaining atoms by walking outward from the already-placed shared
edge, folding away from the 6-ring's centroid for a deterministic result.

---

## Decision: hydrogen bonds render at Tier 2 (named anchor atom, reused bond count) — not atom-exact donor/acceptor pairs

Each base gets **one named pairing-anchor role tag** (adenine/thymine: N1/N3
respectively; guanine/cytosine: their N1/N3-centered donor-acceptor cluster,
approximated by that one atom). The rendered bond **count** (AT = 2, CG = 3)
is read from `replication_manager.gd`'s existing, already-correct
`_spawn_leading_hydrogen_bonds()`/`_spawn_lagging_hydrogen_bonds()` logic —
never recomputed — and drawn as parallel offset lines around the one named
anchor, the same offset pattern the existing bead-glyph H-bond rendering
already uses via `tm.hydrogen_bond_spacing`.

**Deliberately rejected: Tier 3, full atom-exact donor/acceptor naming**
(N1↔N3 + N6↔O4 for A-T; N1↔N3 + N2↔O2 + O6↔N4 for G-C). This is the same
"biological accuracy is didactic, not exhaustive" boundary already drawn
elsewhere in this project (`SKILL.md`'s RNase H precedent: real role not
separately modeled, didactic scope). Tier 3 would triple the per-base atom-
naming burden for a distinction (2 vs. 3 bonds) already fully communicated
by line count, and risks an atom-count mismatch bug between the two purine
and two pyrimidine ring builders staying in lockstep. If a future pass wants
Tier 3, that is a deliberate re-decision, not a silent upgrade — named here
so it isn't drifted into without noticing.

---

## Bug fixes A/B/C — recorded as decisions, root-caused via code trace during Lattice discussion

These surfaced during a CQA pass on Growth Session 1's output. Each was
traced to a specific cause in the real code (not guessed) before being
folded into this expansion pass, since the renderer needed substantial
rework regardless.

**A — bead-glyph occlusion.** Growth Session 1 never suppressed the old
bead-glyph layer (circles, backbone lines, per-segment triangle "bond mark"
chevrons, hydrogen-bond lines) when skeletal mode activated — both layers
drew simultaneously, fully opaque. Fix: bead circles, bond-mark chevrons,
and H-bond lines are suppressed **per-slot** via `modulate.a`, driven by a
new `MoleculeStructureRenderer.is_slot_active(strand, slot) -> bool` public
accessor (polled live every frame by the owning scripts — never cached,
never touched by `scrub_rebuild()`, avoiding a second independently-tuned
hysteresis check that could disagree with the renderer's own).

**SUPERSEDED — backbone `Line2D`s now suppressed too (CQA follow-up).** The
original decision here was to leave backbone `Line2D`s (template AND
synthesized strand) always-visible, reasoning that `Line2D` has no
per-point alpha and hiding the whole line while only some slots are in
molecular-zoom range would un-draw backbone for slots still in bead mode.
User CQA on the shipped result found no reason to keep seeing backbone
lines/directional chevrons once atoms are visible, and pointed out this
document never actually stated that as a requirement — just a call I made.
**Reversed**: `MoleculeStructureRenderer.is_strand_active(strand) -> bool`
(whole-strand, not per-slot) now drives suppression of backbone `Line2D`s
AND their per-segment bond-mark chevrons, for all four strands
(`leading`/`lagging`/`template_bottom`/`template_top`). This works because
skeletal mode only activates at deep free-camera zoom, where the visible
window is narrow — a handful of nucleotides at most (see the culling note
below) — so hiding an entire strand's backbone whenever ANY of its slots
are skeletal-active is visually indistinguishable from true per-slot
suppression; the rest of the line is off-screen regardless. First
implementation attempt: a shared choke point per render path
(`_apply_lagging_backbone_occlusion()` in `replication_manager.gd` for the
two lagging merge paths, inline calls at each of the other three strands'
backbone-finalization sites).

**That first attempt shipped broken — CQA found only top-template
backbone/chevrons fully worked; bottom-template backbone stayed visible
(chevrons fine); synthesized strands' backbone AND chevrons both stayed
fully visible.** Root cause, confirmed by direct code trace: this project's
existing zoom-highlight-dimming feature — `_apply_highlight()`
(`replication_manager.gd`) and `_apply_zoom_highlight()` (`simulation.gd`)
— already legitimately writes `modulate.a` on every one of these same
properties (`leading_backbone_line`/`lagging_backbone_line`, their bond
marks, `leading_hydrogen_bonds`/`lagging_hydrogen_bonds`, per-fragment
`frag.backbone`/`frag.bond_marks`, `backbone_line`/`top_strand_backbone_line`),
and both run AFTER the new occlusion writes in the same frame — `_apply_highlight()`
unconditionally at the end of every `replication_manager.gd.render()` call,
`_apply_zoom_highlight()` mid-`simulation.gd._process()`. Every write placed
before either call got silently overwritten back to `strand_dim` (~1.0).
This is the exact "one writer per property" bug class `_apply_highlight()`'s
own comments already warn against (see the enzyme-dimming section above it)
— a second writer got added instead of composing into the existing one.
Explains the reported asymmetry exactly: top-template backbone happened to
be written after `_apply_zoom_highlight()` in `_process()`'s call order
(survived by accident); bottom-template backbone was written before it
(clobbered); bond marks aren't touched by either highlight function at all
(always survived, on both templates); leading/lagging got hit hardest since
`_apply_highlight()` also clobbers their hydrogen bonds.

**Actually fixed**: molecular-occlusion suppression is now folded directly
into `_apply_highlight()`/`_apply_zoom_highlight()` themselves — the single
legitimate writer for each property — rather than living as a competing
write elsewhere. `_apply_lagging_backbone_occlusion()` and the other
now-redundant inline writes were deleted, not left as dead paths. Molecular
suppression always wins outright (`0.0`, not multiplied with `strand_dim`)
when a residue is skeletal-active. One coverage gap fixed along the way:
`frag.primer_backbone`/`primer_bond_marks` (the RNA-primer segment) was
never covered by the original `_apply_highlight()` either — added rather
than silently dropped when the redundant per-fragment writer was removed.

**B — missing inter-residue phosphodiester bond.** The seed topology's
`chain.o3_prime` stub atom (added purely so `bonds_formed` can resolve
against a fresh per-nucleotide seed) never received a screen position, so
the renderer silently skipped drawing it. Fix: the renderer connects
nucleotide N's own already-positioned `incoming.o3_prime` to nucleotide
N+1's own already-positioned `incoming.alpha_phosphate` — both real computed
positions from each nucleotide's independent fold+derive call. The stub atom
stays in the topology (still needed for `bonds_formed` to resolve per-
nucleotide chemistry correctly) but is never looked up for rendering.

**B, follow-up — direction fix for reversed strands (see
`Handout_AntiparallelStrandOrientation.md` for the ring-rotation pass this
follows on from).** Once ring/substituent orientation became strand-aware,
`_build_backbone_bonds()` still silently assumed slot-index-increasing
always means the chemical 5'->3' direction — true for `sign >= 0` strands
(`lagging`/`template_top`, 5' at LOW slot index per `SKILL.md`'s polarity
table) but backwards for `sign < 0` strands (`leading`/`template_bottom`,
5' at HIGH slot index), where slot+1 is actually the more-5' residue and
slot is the more-3' one. The underlying rule never changes — the more-5'
residue's O3' always bonds to the more-3' residue's alpha-phosphate,
confirmed against the phosphodiester operator's own `bonds_formed`
direction (`resources/phosphodiester_bond_formation.tres`:
`chain.o3_prime` -> `incoming.alpha_phosphate`, i.e. existing/more-5' O3'
attacks incoming/more-3' alpha-P) — only which slot plays which role flips
with strand direction. Caught by Claude Desktop's chemistry review;
verified independently against both the operator's bond direction and the
polarity table before implementing, not applied on report alone. Does not
touch `apply_strand_direction()` or the ring-rotation fix itself, which
were confirmed correct and left unchanged.

**B, further follow-up — "long diagonal" reframed from stale-position bug to
render-approximation issue; fixed with curve-following polyline.** The
direction fix above did not fully resolve Claude Desktop's report: a
console diagnostic (`_report_if_bond_too_long`, temporary, since removed)
showed the long inter-residue bonds occurred exclusively on `template_top`,
transiently, tracking near the fork as it advances — never on
`leading`/`lagging`, and not fixed by re-checking the direction/rotation
logic a third time. Investigation ruled out a data bug entirely: both
endpoint positions are correct (confirmed against `_rebuild_rail()`'s
5-point `Curve2D`, whose control points are monotonic by construction). The
"long diagonal" is a straight chord between two genuinely correct points
that happen to straddle the steep bonded->unzipped transition kink in the
rail curve — a rendering approximation issue (chord vs. curve), not a
correctness bug. `leading`/`lagging` never show it because they use flat
algebraic Y formulas with no curve to cross.

Reframed as a real biology-correctness issue, not merely cosmetic: a
phosphodiester backbone bond is covalent and does not stretch — helicase
unwinding breaks H-bonds between strands, never backbone bonds within one.
A visibly elongating bond teaches something false about what's actually
flexing during unwinding (the curve's bend radius, not the covalent
backbone). Three options considered:
(A) accept the stretch — rejected, teaches the false "backbone flexes"
claim above;
(B) suppress/hide the bond past threshold — rejected, trades the stretch
problem for an equally-wrong "bond is broken here" claim, arguably a
stronger false claim than a stretch;
(C) sample the actual rail curve and draw a short polyline past threshold —
chosen: doesn't teach anything incorrect, and isn't inventing new geometry
since the curve being sampled was already confirmed correct — this only
fixes the renderer's chord approximation of data that was never wrong.

Mechanism: `_build_backbone_bonds()` now routes both endpoints through
`_build_bond_points(strand, from_pos, to_pos, threshold)`. Below
`threshold` (the existing diagnostic's value, `_slot_spacing()`, reused
directly as the mode-switch trigger rather than tuning a second number),
returns the cheap 2-point straight chord unchanged. Above threshold, and
only on `template_bottom`/`template_top` (the only strands with a
`template_sim`-owned curve to sample), samples
`tm.molecular_curve_sample_count` points between the two endpoints via the
new `simulation.gd` method `sample_template_curve_y(strand, world_x)`
(itself a thin wrapper reusing the existing `_sample_curve_y_at_x()` — no
duplicated curve math), offsetting each sampled curve-Y by the
endpoint-interpolated real vertical offset from the raw curve so the
polyline still passes exactly through both true atom positions. Scoped
narrowly by design: only bonds actually spanning the threshold switch
modes, so most of the structure (and all of `leading`/`lagging`) is
completely unaffected and pays no added cost. `_draw()`'s bond loop was
generalized from a fixed 2-point segment to an N-point polyline, insetting
only the true first/last points against atom radius (interior points are
curve waypoints, not atom centers) and drawing a round joint at every
vertex for visual continuity through the bend.

**C — ring anchored at centroid, not a meaningful atom.** The ring's world
anchor was the residue's raw `world_position` (the old bead-glyph's own
position), applied as a translation of the ring's centroid-at-origin local
frame. A point-like bead circle centered there looked fine; a ring with real
spatial extent centered there oversails past wherever the existing hydrogen-
bond line geometry actually terminates. Confirmed via code trace that both
the ring anchor and the H-bond line height read the same live `leading_y`/
`world_x` value each frame (`_leading_render()`) — ruling out a stale-data-
source bug (the class this project has hit before, e.g. a stale `straight_y`
read after a rename). Fix: anchor at the residue's **C1' atom** instead of
centroid — a minimal offset subtraction at the existing translation site, no
change to the ring-derivation geometry itself.

**D — base ring never rotated to face its pairing partner; span/overlap
symptoms this caused, and how each was resolved.** Diagnostic follow-up
(diagnosis/diag.py) to two separate CQA reports — a G-top/C-bottom H-bond
span differing wildly from C-top/G-bottom, and a purine's protruding
five-ring vertex facing inward on one strand and outward on the other —
found ONE shared root cause plus one independent, compounding defect, both
in `NitrogenBaseDeriver`:

1. `derive_base_layout()` only ever TRANSLATED the base ring so its
   glycosidic attachment atom (N9/N1) landed at the right spot along
   `pairing_direction`; the rest of the ring kept `derive_regular_ring()`'s
   fixed `start_angle = -90°` regardless of which way the residue actually
   faced its partner. Confirmed: G-top/C-bottom span = 108.90 vs.
   C-top/G-bottom = 4.50, with identical ribose-ring math both times (ruled
   out `RiboseDeriver.apply_strand_direction()`, confirmed unrelated and
   untouched).
2. `derive_fused_ring()`'s direction-selection picked the walk direction
   that reaches the ALREADY-KNOWN neighbor (shared_edge_b, e.g. C5) in one
   hop, then used that same direction to place the FIRST REMAINING atom
   (N9) — landing N9 exactly on top of C5 (confirmed: identical local
   coordinates to machine precision) instead of walking toward the actual
   unplaced neighbor. A real, separate defect, but tested and confirmed NOT
   sufficient on its own to explain the span asymmetry (flipping it alone:
   108.90/4.50 -> 137.40/34.74, still ~4x off).

Fix pass 1 (both defects together): `derive_fused_ring()`'s direction fixed
(swap which branch gets +1/-1). `derive_base_layout()` given a genuine
rotation (`Vector2.rotated()`, never a mirror — same no-chirality-flip
constraint as `apply_strand_direction()`) aligning the LOCAL
attachment-atom direction with `pairing_direction`, before translating.
Verified (diagnosis/diag_verify.py, diagnosis/diag_symmetry.py): G/C and
A/T spans became exactly symmetric (diff = 0.000000 both pairs), N9 no
longer coincides with C5 (30.58 apart), and a full base-atom dump confirmed
template_top/template_bottom placements of the same base are an exact
180-degree point-rotation of each other about the shared center (max error
2.3e-13) — consistent facing, not a mirror.

Fix pass 2 (rotation RETARGET, same session, follow-up once fix pass 1's
own numbers were examined further): symmetric was not the same as correct.
A `bond_length` sweep (diagnosis/diag_span_breakdown.py) showed span
increasing monotonically from 90 (the bare backbone gap) as `bond_length`
grew from 0 — meaning NO `bond_length` value could ever bring the two
anchors together. Root cause: pass 1 aligned the C1'->attachment direction
with `pairing_direction`, but the H-bond ANCHOR atom (N1/N3) sits roughly
180 degrees across the ring from the attachment atom (N9/N1) — so pointing
attachment at the partner necessarily pointed anchor away from it,
regardless of scale. Fixed by retargeting what the rotation aligns: the
LOCAL vector FROM the attachment atom TO the anchor atom is now aligned
with `pairing_direction` (still `Vector2.rotated()`, still no mirror); the
attachment atom still lands at exactly `c1_position + pairing_direction *
bond_length`, unchanged. Verified: span dropped from 138.16 to 36.96 at the
same `bond_length`, still exactly symmetric across G/C and A/T, and a finer
sweep now shows a genuine V-shaped minimum (span -> ~0 at
`bond_length` ~= 13.398) instead of the old monotonic-only-grows curve.

Fix pass 3 (`bond_length` retune, `molecular_ring_bond_length_ratio`
0.35 -> 0.287, i.e. `bond_length` 18.9 -> 15.5): with pass 2's rotation
fixed, the OLD `bond_length` (18.9) was independently confirmed to cause
the screenshot-reported same-strand purine overlap — the purine ring's own
widest local extent (62.54) actually EXCEEDED `nucleotide_slot_spacing`
(54.0). `bond_length` and `dna_ribbons_gap`/`nucleotide_slot_spacing` were
never tied together in the code (confirmed: independently-set exports, no
cross-reference) — same "two independently-tuned numbers" gap as the
earlier atom-radius/label-size CQA fix. Picked 0.287 (`bond_length` = 15.5)
from a fine sweep (diagnosis/diag_retarget.py) balancing two
constraints that trade off against each other across the whole range: span
needs >= 14 units to render 2 full dash+gap cycles of
`molecular_h_bond_dash_length`/`molecular_h_bond_gap_length` (4.0 + 3.0 =
7.0/cycle), while purine extent needs real margin under
`nucleotide_slot_spacing`. At 15.5: span = 14.12 (clears the dash-count
floor), extent = 51.29 (margin 2.71, ~5% — thin but real; every smaller
value fails the dash-count requirement, every larger value shrinks the
margin further for little extra span). Diagnostic scripts for this whole
chain live in `diagnosis/` (`diag.py`, `diag_verify.py`,
`diag_symmetry.py`, `diag_span_breakdown.py`, `diag_retarget.py`) —
self-contained Python replicas of the exact GDScript formulas, kept for
independent re-verification rather than trusting printed numbers alone.

**E — leading/lagging synthesized the WRONG (same-letter) base relative to
their real template — pre-existing bug, unrelated to A-D above, found via
the same diagnostic dump.** The dump's leading/template_top and
lagging/template_bottom sections showed IDENTICAL letters at every tested
slot (AA, TT, GG — never a real Watson-Crick pair). Root cause confirmed
against `docs/SKILL.md`'s own polarity table, not guessed: leading's
orientation (3' left, 5' right) is antiparallel to template_top's (5'
left, 3' right), confirming leading's real template is `template_top`
(matching `PARTNER_STRAND` in `molecule_structure_renderer.gd`, which
needed no change). But leading's base_type formula used
`dna_sequence.get_complement(i)` — the SAME formula as template_top's own
letter — instead of `get_base(i)` (the actual complement of template_top,
since template_top itself is `get_complement(i)`). Symmetric bug for
lagging/template_bottom (`get_base(i)` instead of `get_complement(i)`).

Never caught before because `NitrogenBaseDeriver.hydrogen_bond_count()`
only depends on AT-family (2 bonds) vs. GC-family (3 bonds), and a base
and its complement are always in the same family — so the bead-glyph
H-bond dash count/color looked correct regardless of which side of the
swap was used. The molecular renderer was the first consumer needing the
EXACT letter (real ring geometry cares whether it's A vs. T), which is
why the earlier rotation-retarget fix (D above) produced nonsensical
purine-purine/pyrimidine-pyrimidine spans on synthesized strands even
after being verified correct for genuinely complementary pairs.

Fixed by swapping which `dna_sequence` method leading/lagging call at
every base-identity call site in `replication_manager.gd` (12 sites:
`get_synthesized_nucleotides()`, both hydrogen-bond `template_base`
lookups, main live-synthesis spawn, primer placement/scrub-rebuild,
primer-to-DNA conversion, and both capture/catch-up paths) — never
`PARTNER_STRAND`, never the spatial `leading_y`/`lagging_y` layout
formulas, both confirmed already correct. User-facing effect:
leading/lagging's displayed base color changes to the true WC complement
of their template, a directly visible change, not just a
molecular-renderer-only fix. See `diagnosis/FINDINGS_SUMMARY.txt` for the
diagnostic trail that led here.

**E, CORRECTION — the fix above was itself wrong, in the opposite
direction of E's own bug.** After F (below) shipped, a live screenshot at
the normal (non-molecular) zoom level showed leading/lagging STILL
same-letter-paired against their template, even after a full project
reload. A new diagnostic (full-sequence same-letter scan, all 57 slots,
not just the first 10) came back completely clean — meaning the DATA E's
fix touched (`get_synthesized_nucleotides()`) was internally consistent
with `get_template_nucleotides()`, yet the actual on-screen rendering
still disagreed. Root cause: `simulation.gd` has TWO separate functions
describing the templates, and they had always disagreed with each other —
`get_template_nucleotides()` (used by the molecular renderer and the F9
diagnostic — the reference E's fix was validated against) claimed
`template_bottom = get_base(i)`, `template_top = get_complement(i)`; the
REAL bead-spawn functions that build what a user actually sees
(`_spawn_bottom_strand()`/`_spawn_top_strand()`) use the OPPOSITE
(`template_bottom = get_complement(i)`, `template_top = get_base(i)`) —
predating this entire session, unrelated to anything fixed today until
now. E's fix aligned leading/lagging to match `get_template_nucleotides()`
— which made them WRONG relative to the actually-rendered template beads,
even though `get_template_nucleotides()` itself, SKILL.md's polarity
table, and the diagnostic all appeared to agree with each other
throughout. The diagnostic scan being clean was real but insufficient — it
only proved internal consistency with the wrong reference, not that the
reference matched reality.

Fixed properly this time: reverted every one of E's 12
`replication_manager.gd` changes back to their ORIGINAL formulas (they
were correct all along), and fixed `get_template_nucleotides()` in
`simulation.gd` instead, swapping it to match the real spawn functions.
Never touch the spawn functions themselves. Lesson recorded plainly: when
a "ground truth" reference function disagrees with what's actually
rendered, trust the render, not the reference — and check that
independently, don't just re-derive from the same source that was already
wrong.

**F — base ring visibly overlaps its own ribose's substituent chain in
template-template pairing.** With D and E both fixed, the F9 diagnostic
was extended to measure `RiboseDeriver.derive_substituents()`'s chain
(O3'/C5'/O5'/alpha-phosphate — 3 successive `bond_length` steps outward
from C4', all in the same direction, never covered by the earlier "ribose
ring diameter" metric which only counts the 5 bare ring atoms). Real
numbers: template-template pairing's chain came within 0.56-4.26 units of
its own base (near-touching); leading/lagging pairing stayed a comfortable
34-38 units clear. Same root cause as D's rotation fix — RiboseDeriver's
ring rotation is tied to fixed strand identity (sign), while
NitrogenBaseDeriver's base rotation is tied to the actual momentary
pairing_direction; these two independent choices constructively align for
template-template pairing (small clearance) and destructively cancel for
leading/lagging-vs-template pairing (large clearance) — confirmed via the
diagnostic, not asserted.

Constraint: neither RiboseDeriver's ring rotation (the confirmed-correct
antiparallel fix) nor its substituent chain (Bug B's inter-residue
backbone bonds depend on its exact O3'/alpha-phosphate positions) can
move. The H-bond anchor position (span 12.5484, confirmed consistent
across all three real pairing relationships after E's fix) also had to
stay exactly where it was — explicitly required, not just nice-to-have,
since it took several rounds this session to get right.

Fix: reformulated `derive_base_layout()` so the ANCHOR's target position
is computed directly, algebraically identical to what the old
attachment-anchored formula already produced (verified bit-for-bit via
`diagnosis/diag_anchor_preserving.py` before shipping — both old and new
formulas produce the same anchor world coordinates to floating-point
precision). This frees up the base ring's rotation angle as a genuine
spare degree of freedom (previously fully consumed by aligning
attachment->anchor with `pairing_direction`), then picks whichever angle
maximizes the ring's minimum distance from the ribose's own substituent
chain (passed in as `avoid_points`, computed by the caller one line before
this call — no duplicated derivation). A single-vector heuristic (rotate
so attachment->anchor points opposite the chain's own direction) was
tried first — cheaper, more in-keeping with the rest of the file's
closed-form trig — and tested via `diagnosis/diag_anchor_preserving.py`:
it recovered ~80% of the achievable clearance gap for one strand sign but
only ~17% for the other (the purine fused five-ring's asymmetric bulk
isn't captured by one vector), so a real search
(`BASE_ROTATION_SEARCH_STEPS = 72`, i.e. 5-degree resolution) was used
instead. Still a deterministic, principled derivation — a maximization
over the one legitimately free rotation DOF, not a tuned constant — same
"derive, don't hardcode" spirit as every other fix in this file, just
expressed as a search rather than closed-form trig because the shape
genuinely doesn't reduce to one. Cost is negligible: skeletal mode only
ever renders a handful of residues at once (see the Culling note below).

**F, follow-up — the same crossing was still visible for UNPAIRED
residues, sign-dependent.** A live screenshot (post-F) of an unpaired
`template_bottom` residue — freshly split off the helicase, not yet
caught up to by the lagging polymerase — showed the exact same
ribose-through-base crossing F was supposed to fix. Root cause: an
unpaired residue has `pairing_direction = Vector2.ZERO` (no real partner
to compute a direction from), which fell back to a fixed `Vector2.DOWN` —
completely arbitrary, since there's no H-bond constraint to satisfy when
unpaired at all. That arbitrary choice happened to leave the clearance
search plenty of room for `sign=+1` strands (worst case 46.4, comfortably
clear) but not for `sign=-1` (worst case 4.8 for T/C — barely better than
the original bug). Confirmed via `diagnosis/diag_unpaired_case.py`
(segment-vs-base-atom distance, not just endpoint-vs-atom, since the
earlier metric wouldn't have caught a chain LINE cutting through the
base's interior between two far-apart points).

Fixed by making the fallback direction chain-aware instead of fixed: when
unpaired but the ribose's substituent chain (`avoid_points`) is available,
point away from the chain's own centroid instead of always `Vector2.DOWN`
— there's no real constraint being violated by doing this, since nothing
depends on an unpaired residue's exact anchor direction. Verified: raises
the `sign=-1` worst case from 4.8 to 45.9, comfortably clear, and doesn't
regress `sign=+1` (still 43.9+). Genuinely direction-only unpaired
fallback (`Vector2.DOWN`, no `avoid_points` at all) kept as a last-resort
fallback for any caller that doesn't supply `avoid_points`.

**F, correction — clearance search silently stretched the glycosidic
bond.** Flagged from a live atom-zoom screenshot of the bottom template
strand (no paired base yet): the vertical C1'-to-base line's length
visibly varied residue to residue, and the phosphodiester backbone lines
near it looked jumbled. Root cause, confirmed algebraically before
touching code: the clearance search (Bug F's core fix, above) pins the
H-bond ANCHOR atom (N1/N3) at a fixed target and rotates the whole base
ring freely around it to maximize distance from `avoid_points`. Nothing
in that search constrains where the ATTACHMENT atom (N9/N1) lands — it's
only exactly `bond_length` from C1' when the chosen rotation happens to
put `local_reach` (anchor minus attachment, fixed in the ring's local
frame) parallel to `pairing_direction`, which the search has no reason to
prefer. But the C1'-to-attachment bond is a real covalent bond in the
topology (`_attach_glycosidic_bond()`) — same category as the
phosphodiester backbone bond this codebase already treats as
non-stretching (see the Culling note's sibling reasoning in
`molecule_structure_renderer.gd`'s `_build_backbone_bonds()` comments).
The search was stretching it as a side effect, differently per residue
depending on avoid-point geometry — exactly the varying-length line seen
on screen.

Fixed by re-deriving `derive_base_layout()`'s search to pin the
ATTACHMENT atom at `c1_position + dir * bond_length` and rotate around
that instead of the anchor. Verified algebraically (not assumed) that
this is identical to the old formula whenever `avoid_points` is empty —
both converge on the same result when the rotation happens to align
`local_reach` with `dir` — so the no-search fallback path, and every
already-verified paired/unpaired clearance number from Bug F and its
unpaired follow-up above, are unaffected. The accepted tradeoff: the
H-bond anchor's exact position — and therefore its span, previously noted
above as "exactly right and must not move again" — is no longer perfectly
fixed across every paired case; it now varies with whichever angle the
search picks for that residue. This is judged correct: an H-bond is not a
rigid covalent bond, so letting its geometry flex is chemically more
honest than letting a real covalent bond stretch. **Confirmed** via a
fresh F9 dump: every `attachment atom ... distance from C1'` entry now
reads exactly `10.8000` (the live `bond_length`), paired and unpaired
alike, across the whole dump.

## Bug G — ghost H-bond between templates already past the helicase

Flagged from a live atom-zoom screenshot: cyan dashed H-bond lines
visible between `template_top`/`template_bottom` residues clearly already
separated by (to the left of) the helicase glyph, toggling fully on/off
with a single camera-zoom-wheel tick — a reproducible input-tied flicker,
not a one-off render glitch.

Root cause: `_pair_for_slot()`'s template-template branch decided
"unzipped" purely from whether `leading`/`lagging` had a synthesized base
at that slot yet, with a doc comment claiming this "mirrors
`template_hydrogen_bonds`' own existing visibility rule in simulation.gd."
That claim was never actually true: simulation.gd's own bead-glyph rule
(`template_hydrogen_bonds[i].visible = (world_x >= helicase_x)`) keys
purely off the helicase's physical position, while `_pair_for_slot()` keyed
off synthesis progress — two different positions, since
`polymerase_x_offset_slots` (simulation.gd, default 4) keeps both
polymerases trailing several slots behind the helicase. In that real gap —
already unwound, not yet reached by either polymerase — `_pair_for_slot()`
kept reporting the two templates as still paired, so the skeletal renderer
drew an H-bond between two strands no longer in contact. The zoom-tick
flicker was this gap-zone pair sitting right at the per-molecule cull
boundary (`_build_hydrogen_bonds()` only draws a pair when both residues'
anchors survive the current frame's cull rect, itself sized from the live
zoom level) — a symptom of the stale pairing decision, not a second bug.

Fixed by switching `_pair_for_slot()` to the same authoritative condition
simulation.gd already uses: compare the slot's own world-x position
(`position_by_key`, already threaded through both call sites) against
`template_sim.helicase_x` directly, rather than inferring it from
leading/lagging existence. `_dump_pairing()`'s diagnostic replica of this
logic updated to match (it now also marks a slot unzipped once past
`template_sim.helicase_x`, not only once leading/lagging exists), so the
diagnostic can't silently drift from the renderer's real behavior again.
Awaiting a live screenshot to confirm the ghost lines are gone and no
longer flicker with zoom.

## Bug H — same-strand backbone/chain overlaps its own neighbor (pre-fork "mess")

Flagged from a live atom-zoom screenshot of still-duplexed template DNA
(right of the helicase, not yet unwound): backbone bonds crossing diagonally
through the *next* residue's ring, base rings encroaching on their neighbor.
Confirmed numerically, not just visually, from the live F9 dump: each
residue's substituent chain (O3'/C5'/O5'/alpha-P) reaches **58.1368–58.1936
units** from its own C1', while consecutive residues along a strand are only
**54.0 units** (`nucleotide_slot_spacing`) apart. The chain is longer than
the gap to the next residue — an unavoidable overlap regardless of how well
any single residue's own geometry is derived, since (per `ribose_deriver.gd`'s
stated design principle) residues are never rotated to face their neighbor,
only translated along the strand with a fixed local orientation. Distinct
from Bug F (which only keeps a residue's chain clear of its OWN base, not
its neighbor's geometry) and independent of `dna_ribbons_gap` (checked
directly: `pairing_direction` is normalized before use in
`derive_base_layout()`, so at pre-fork — where it's purely vertical, same
slot x on both templates — its magnitude never reaches the placement math;
the base only ever travels one `bond_length` from C1', regardless of how far
the real partner is).

Since ring/base/chain geometry all scale linearly with `bond_length` (pure
derived trig, no fixed additive terms), the fix is shrinking
`molecular_ring_bond_length_ratio` — but this is a real trade-off, not a
free fix: the same shrink also shrinks the H-bond anchor-to-anchor span,
already measured at only ~8.17 units for real post-fork pairs (leading/
template_top) at the live ratio (0.2) — barely more than one dash+gap cycle
(7.0 units, `molecular_h_bond_dash_length` + `molecular_h_bond_gap_length`),
nowhere near the "2 full cycles" goal `molecular_ring_bond_length_ratio`'s
own comment records from when it was last tuned (0.287, chosen for the
ring-diameter-vs-dash-cycle trade-off at THAT time). A sweep (linear
scaling from the live measurements) found no ratio clears both the
chain-overlap margin and the 2-cycle dash target simultaneously — genuinely
a balance point. Picked the 5%-chain-margin row: `molecular_ring_bond_length_ratio`
0.2 -> **0.1763** (`bond_length` 10.8 -> 9.52), giving chain reach ~51.3
(under the 54.0 slot spacing with real margin) at the cost of post-fork
H-bond span shrinking further to ~7.2 (barely over one cycle).

Values backed up before changing anything: `diagnosis/ratios_bkp.txt` (every
tunable value touched or considered this session, plus the live-measured
derived quantities that justified this ratio, so the trade-off can be
re-evaluated or reverted without re-deriving it from scratch).

**Dots instead of dashes** (same change, requested alongside): since the
post-fork H-bond span is now this close to a single dash+gap cycle, a
dashed line (`draw_line` segments) degrades to reading as one short solid
blur rather than a visibly dashed line. Switched `_draw_dashed_line()` ->
`_draw_dotted_line()` (`molecule_structure_renderer.gd`) to draw fixed-radius
dots (`draw_circle`) at a fixed pitch instead of dash segments — a dot is a
fixed-size mark regardless of how few fit along a short span, so it doesn't
have the same failure mode. `theme_manager.gd`'s `molecular_h_bond_dash_length`/
`molecular_h_bond_gap_length` renamed to `molecular_h_bond_dot_radius`
(2.0)/`molecular_h_bond_dot_gap` (3.0) — center-to-center pitch
(2*radius + gap = 7.0) deliberately kept equal to the old dash+gap total, so
the "clears N cycles" reasoning above still applies unchanged to dot count.
Neither field had a scene override, so the rename is safe.

Awaiting a live screenshot to confirm the same-strand overlap is gone (or
at least substantially reduced) and the H-bond dots read cleanly at the new,
shorter post-fork span.

## Bug F, second correction — clearance search could flip the H-bond anchor to face away from its partner

Flagged from the SAME Bug H screenshot, by direct visual inspection (user's
own hypothesis, confirmed before any code was touched): every nucleotide
looked "flipped" — top-strand residues showing ribose below and base above,
bottom-strand residues the reverse. Confirmed numerically, not just
visually, using the new world-space diagnostic dump fields (below): for a
real paired residue, `pairing_direction` (toward the real partner) was
`(0, 60)` — straight down — while the H-bond anchor atom sat at local
`(-10.73, -13.71)`, i.e. ABOVE its own C1', on the opposite side from the
partner. Dot product of the two directions: **-271.4** — strictly negative,
not just off-axis.

Root cause: the attachment-fixed clearance search (this doc's Bug F
correction, above) pins the ATTACHMENT atom toward `pairing_direction`
(correctly fixing the glycosidic-bond stretch) but was left free to rotate
the rest of the ring through the FULL 360-degree sweep to maximize distance
from the ribose's own substituent chain — with nothing keeping the ANCHOR
atom (a different atom, on the far side of the ring) anywhere near the
intended direction. Since the ribose's own chain and the real partner
routinely sit on the same general side (both point "outward" from the
strand), the search's clearance-maximizing angle often flips the anchor to
the opposite side entirely — visually indistinguishable from the whole
nucleotide being mirrored, even though the ribose and attachment point were
both correctly placed the whole time.

Diagnostic improvement (requested alongside root-causing this): the F9 dump
already grouped atoms by molecule (`ring_named`/`base_named`/`chain_named`)
but only ever printed LOCAL coordinates, forcing a manual conversion to see
what's actually overlapping on screen. `_derive_full_residue()`/
`_write_residue_block()` (`molecule_structure_renderer.gd`) now print WORLD
coordinates alongside local for every atom in all three groups, plus a new
`DIRECTION CHECK` line per residue: `pairing_direction` and an
`anchor_alignment_dot` that explicitly flags "anchor faces AWAY from
partner" when negative — this is exactly what caught the -271.4 case above
directly off the dump, no manual arithmetic needed.

Fixed by bounding the search instead of leaving it unconstrained: swept
worst-case clearance AND worst-case `anchor_alignment_dot` across every
base letter x strand sign combination at increasing window half-widths
around the "aligned" angle (the one that points the anchor exactly at
`dir`, same formula the no-avoid_points fallback already used):

| window | worst-case clearance | worst-case alignment dot |
|---|---|---|
| 0 deg (old Bug D behavior) | 0.558 | 1.000 |
| 30 deg | 6.12-7.31 | 0.923 |
| **45 deg** | **6.45-8.09** | **0.864** |
| 60 deg | 6.85-8.09 | 0.779 |
| 90 deg | 9.47-10.88 | 0.32-0.50 |
| 120 deg | 14.6-18.0 | -0.187 (already flipped) |
| 180 deg (unconstrained, the bug) | 15.9-18.7 | -0.39 to -0.87 |

Almost all the real clearance win happens by 45 degrees (0.56 -> 6.45-8.09,
a 10-14x improvement over the original Bug D overlap); purines (A/G)
actually plateau exactly at 40 degrees in this sweep, so a 45-degree cap
costs them nothing, while pyrimidines keep finding marginal extra clearance
out to 90+ degrees — exactly the region where alignment collapses toward
sideways/flipped, so that extra clearance isn't worth taking. 45 degrees
picked as the point that captures essentially all the achievable clearance
without paying for any flip risk. Implemented as
`BASE_ROTATION_SEARCH_WINDOW_DEG` (`nitrogen_base_deriver.gd`) — the search
still spans `BASE_ROTATION_SEARCH_STEPS` (72) samples, now distributed
across `aligned_angle +/- window` instead of the full circle. The
no-avoid_points fallback branch is unaffected (it always used exactly
`aligned_angle`, now just named and shared instead of recomputed inline).

Awaiting a live screenshot to confirm nucleotides no longer read as
flipped.

## Bug F, third correction — windowed search still let the H-bond span collapse

The 45-degree window above fixed the flip, but the very next screenshot
(same session, still atom zoom) looked WORSE, not better — user reported
"can't make out what's what anymore." Confirmed via a fresh F9 dump: the
H-bond anchor-to-anchor span, previously a stable 81-84 for this pre-fork
template-template case, had collapsed to **6.4-11.25** — both strands'
entire base rings (diameter up to 46.4) landing almost on top of each
other.

Root cause: pinning the ATTACHMENT atom (the second correction, above)
means each residue's search runs completely independently — it only knows
about its OWN substituent chain, never about where the PARTNER residue's
own search left ITS anchor. The window (however wide) gave both sides
freedom to drift toward each other with nothing coordinating the two
searches. Swept the resulting cross-strand span at increasing window sizes
and found it genuinely unstable, not just off by a fixed amount:
non-monotonic, and in one combination collapsing to 1.127 at exactly the
window size (60 degrees) that looked fine for a different base combination
at the same window. There is no window value that fixes this under
attachment-pinning — the instability is structural, not a tuning problem.

Fixed by reverting to anchor-pinned placement (the design this doc's Bug D
follow-up originally shipped, before the second correction changed it) and
moving the window constraint onto the ATTACHMENT's stretch instead of the
anchor's rotation freedom. Anchor-pinning means `translation` is always
solved so the anchor lands exactly on `anchor_target` — by construction,
this is now stable and correct for every window size, base letter, and
strand sign, exactly as it always was pre-Bug-F. The window instead bounds
how far the attachment (and the real covalent glycosidic bond it
represents) is allowed to drift from `bond_length` while searching for
ribose-chain clearance — a smaller, bounded regression accepted
deliberately, since an unstable/collapsed H-bond span is far more visually
disruptive than a somewhat-stretched invisible bond length. Swept
clearance-vs-stretch (not clearance-vs-alignment this time, since alignment
is no longer a concern under anchor-pinning) and picked **15 degrees**:
already escapes the worst original overlap (0.56 -> 3.31+ worst case) for a
modest, bounded stretch (+1.6 to +3.7); stretch grows much faster than
clearance improves past that point, especially for purines. Implemented as
`BASE_ROTATION_SEARCH_WINDOW_DEG = 15.0` (`nitrogen_base_deriver.gd`) —
same constant, same window mechanism as the second correction, just now
governing the OTHER atom's drift, with the pinned/free roles swapped back.

This is the third distinct fix to the same rotation search this session
(Bug F core -> Bug F attachment-pin correction -> this anchor-pin
re-correction). Recorded explicitly as a caution for any future change
here: this function has exactly one free rotation DOF and at least three
things that would each like to own it (glycosidic bond length, H-bond
anchor position/span, ribose-chain clearance) — any future "fix" that
moves which atom is pinned needs to re-verify ALL THREE, not just the one
that prompted the change, ideally via the same kind of live F9 dump this
session repeatedly needed to catch the two regressions above.

Awaiting a live screenshot to confirm this actually looks better this
time — both the flip (should still be fixed, anchor-pinning cannot flip by
construction) and the span collapse (should now be fixed too).

**Confirmed fixed, but a genuinely new problem surfaced from the same
screenshot**: `anchor_alignment_dot = 1.0000` on every residue and a
rock-stable `12.5484`/`12.5485` H-bond span — the flip and the collapse are
both gone. But the render still looked wrong, and the "compare against
leading/lagging" idea the user proposed to triangulate it turned out to
rest on a false premise worth recording: in that dump, `leading`/`lagging`
had NO real partner yet (`pairing_direction = (0,0)`, every entry routed
through the UNPAIRED fallback path) — they looked clean because they were
using the roomy chain-away fallback with no cross-strand constraint, not
because there's a second, better-behaved code path. Once a synthesized
strand actually pairs with its template, it goes through the exact same
anchor-pinned search and will show the exact same crowding.

## Bug I — base rings overlap because dna_ribbons_gap doesn't leave room for them

The real cause: each base ring sits at a FIXED offset from its own C1'
(`anchor_target = c1_position + dir * (bond_length + reach_length)`,
`dir` normalized — `dna_ribbons_gap`'s magnitude never reaches this
calculation, confirmed in Bug H's investigation). The only place
`dna_ribbons_gap` actually enters the picture is how far apart the two
strands' C1' anchors themselves are. Ring diameter (up to 46.4) is much
larger than the anchor-to-anchor H-bond span this produces (12.5484) —
so at `dna_ribbons_gap = 60`, the worst-case "ring atom closest to the
opposite strand's own C1'" was `16.9577`, already inside the opposite
ring's own ~23-unit radius: guaranteed overlap, independent of anything
in the rotation search.

Since the ring's offset from its own C1' is fixed, "closest ring atom to
opposite center" scales 1:1 with `dna_ribbons_gap`. Solved directly:
target clearance ~40 (ring radius + margin) - current worst case
(16.9577) = +23.04 needed -> `dna_ribbons_gap` 60 -> **85** (scene
override, `scenes/simulation.tscn`; old value already recorded in
`diagnosis/ratios_bkp.txt`).

Known tradeoff, flagged before applying: `dna_ribbons_gap` is shared with
the normal-zoom bead-glyph rendering (row spacing) and several other
systems (polymerase clamp, ligase drop, etc.) — raising it for the
molecular view also widens the bead-glyph ribbon gap. Applied anyway per
explicit instruction, to check the result first; decoupling the molecular
renderer's spacing from the shared value is the planned follow-up if this
works but the bead-glyph-mode side effect isn't acceptable.

Awaiting a live screenshot to confirm the base rings clear each other at
the new gap.

**Confirmed working** at `dna_ribbons_gap = 100` — base rings clear, no
overlap. Follow-up needed: span was still tight, raised further to
`100` (from `85`) for real breathing room (`27.45` H-bond span,
comfortably past the ~72.5 combined-reach floor) — confirmed working via
live screenshot, user requested only minor further fine-tuning of the dot
styling after this.

**Decoupling** (requested from the start of Bug I, deferred until the fix
was confirmed working): `dna_ribbons_gap = 100` is far too wide for the
normal-zoom bead-glyph ribbon, which shares the same value. Reverted
`dna_ribbons_gap` to its original `60` and moved the extra separation
into a render-only offset that lives entirely inside
`molecule_structure_renderer.gd`, never touching the real simulated
positions:

- `theme_manager.gd`: new `molecular_extra_ribbons_gap` (`40.0` = the
  `100 - 60` this session already validated).
- `molecule_structure_renderer.gd`: new `MOLECULAR_ROW_PUSH` table and
  `_molecular_render_pos()` helper — adds a per-strand, render-only Y
  offset (`push * extra_gap / 2`) applied uniformly to every residue of a
  strand, never conditional on pairing state (so the backbone never kinks
  at a pairing/unpairing boundary). The two templates push apart from
  each other symmetrically (`template_top: -1`, `template_bottom: +1`);
  leading/lagging push an ADDITIONAL unit further in the same direction
  their own template partner already moved (`leading: -2`, `lagging:
  +2`) — mirrors how `simulation.gd`'s own row formulas cascade
  (`leading_y` is defined relative to `template_top`'s row), so the
  leading-vs-template_top separation grows by the same total amount as
  the template-vs-template separation, not half of it. A single fixed
  push per strand is sufficient even though a strand can be involved in
  two different real pairings over its lifetime, since `_pair_for_slot()`
  guarantees those pairings are never simultaneous.
- Applied consistently in both the real renderer (`_rebuild_layout()`)
  and the F9 diagnostic (`_derive_full_residue()`, all its call sites) —
  this session hit the "diagnostic silently drifts from the renderer's
  real behavior" trap more than once (Bug G, the unzip-check dump logic)
  and it's cheap to avoid here by routing both through the same
  `_molecular_render_pos()` helper.

Awaiting a live screenshot to confirm the molecular view still looks
correct with the decoupled offset, and that normal zoom looks right again
now that `dna_ribbons_gap` is back to 60.

**Confirmed working.** `molecular_extra_ribbons_gap` live-tuned from the
initial 40 up to **80** — every ring, base, and H-bond fully
distinguishable at atom zoom, not merely non-overlapping. `dna_ribbons_gap`
stays at 60 throughout (bead-glyph ribbon untouched). Script default
updated to match (80) so a fresh scene starts from the tuned value.

## Bug J — ribose/phosphate chain reaches toward the partner instead of away, on the two template strands

Flagged from a side-by-side pair of live screenshots the user set up
deliberately: one confirmed-correct "DNA copy" (leading strand) residue,
phosphate above the ribose ring and base below it, cleanly separated, H-bond
dots continuing further down past the base; then the equivalent
template_top residue, phosphate **below** the ribose ring instead — user's
exact words: "the ribose ring and phosphate are upside down."

Root cause, confirmed by tracing the actual local coordinates rather than
guessing: `RiboseDeriver.derive_substituents()` places the O3'/C5'/O5'/
alpha-phosphate chain radially outward from the ring, using whatever
direction the ring's own antiparallel-pucker rotation
(`apply_strand_direction`, driven by `STRAND_DIRECTION_SIGN`) happens to
leave it in — never told which way the real partner actually is, unlike
the base (which already gets `pairing_direction`). Worked out where each
strand's chain actually points relative to where its own real partner sits
on screen:

| strand | sign | partner is | chain points | correct? |
|---|---|---|---|---|
| leading | -1 (rotated) | below | up (away) | yes |
| lagging | +1 (identity) | above | down (away) | yes |
| template_top | +1 (identity) | below | down (toward) | no |
| template_bottom | -1 (rotated) | above | up (toward) | no |

Leading/lagging come out correct only as a side effect of sharing the same
rotation sign as their own case happens to need; the two templates come
out backwards — chain reaching straight into the H-bond zone toward the
partner, which is the same-strand mess visible in every template
screenshot this whole investigation, and invisible in every leading/
lagging screenshot. Confirmed this isn't fixable by touching
`STRAND_DIRECTION_SIGN` or the ring rotation itself — that sign is the
same one protecting the already-verified-correct ring chirality/nesting
(`docs/Handout_AntiparallelStrandOrientation.md`), and lagging proves the
correction can't be a fixed per-strand or per-sign table anyway: lagging
and template_top share the identical rotation sign (`+1`, identity) yet
need opposite corrections, since lagging's real partner is above it while
template_top's is below.

Fixed by giving the chain the same treatment the base already has:
`derive_substituents()` now takes an optional `pairing_direction` (real,
world-space, points toward the partner — same value/convention the caller
already computes for base placement, now computed earlier in
`_rebuild_layout()` so both consumers share it). When the chain's natural
outward direction agrees with `pairing_direction` (i.e. reaches toward the
partner), the whole substituent group is flipped by negating every local
position — a proper 180-degree rotation around the ring's own fixed
attachment point (C3' for O3', C4' for the C5' chain), verified
algebraically to be identical to that rotation for every atom in the
chain including the branching alpha-O1/alpha-O2 pair, never a single-axis
mirror (would silently invert the chain's own chirality while looking
like a fix — same rule `apply_strand_direction()` already documents).
Verified numerically against all four strands' real local coordinates:
leading/lagging (already correct) come out `flip=False`, unaffected;
template_top/template_bottom (confirmed backwards) come out `flip=True`.
Left at the default zero vector (unpaired residues, or any caller that
hasn't been updated), behaves exactly as before.

Awaiting a live screenshot to confirm the template strands' chains now
point away from their partner like leading/lagging always did.

**Confirmed via screenshot** (atom-zoom, template DNA): both strands now
show phosphate/ribose pointing away from the pairing partner and base
toward it, matching leading/lagging's known-correct orientation. Sequence
cross-checked against the H-bond dot color pattern (2 dots/green = AT
family, 3 dots/cyan = GC family) and matched exactly.

### Bug K: base ring crowds its own ribose ring (paired residues only)

Follow-up CQA, found via a deliberate before/after visual comparison (same
technique as Bug J): comparing a leading-strand nucleotide (unpaired,
fallback-direction rendering) against a template nucleotide (paired, real
H-bond rendering) side by side, flipped to a common orientation. The
leading one shows a clean "neck" — real background space — between the
ribose ring and the base ring below it. The template one shows the base
ring's own atoms crowded directly against the ribose ring's own atoms, no
visible gap, reading as one fused mass.

Verified quantitatively against the F9 dump (not assumed from the
screenshot alone): for template PAIR 1 slot 0 (top nucleotide), the
closest base-ring atom to a ribose-ring atom (excluding the attachment
bond itself) is C2 (218.8, 309.2) to C3' (221.4, 306.8) — distance ≈3.5
units, well inside two `molecular_atom_radius = 4.0` circles' combined
radius, i.e. genuinely overlapping on screen. The equivalent unpaired
leading-strand nucleotide's closest base-to-ribose distance is ≈23.5
units, ~7x more clearance, for structurally analogous atoms.

Root cause: `NitrogenBaseDeriver.derive_base_layout()`'s clearance-
maximizing rotation search (see its own extensive comment history — one
free rotation DOF, multiple competing needs) only ever receives
`avoid_points = substituent_positions.values()` from both call sites in
`molecule_structure_renderer.gd` (`_rebuild_layout()` and
`_derive_full_residue()`) — the ribose's own substituent chain
(O3'/C5'/O5'/alpha-P). The ribose RING itself (C1'-C4', O4') was never
included in `avoid_points`, so the search is structurally blind to base-
vs-ribose-ring collisions — it can (and does) happily maximize clearance
from the phosphate chain while rotating the base straight into its own
ribose ring, exactly the fused-mass overlap seen in the template
screenshot. This never showed up for leading/lagging's unpaired fallback
path because that path (`avoid_points.is_empty()` branch) doesn't run the
search at all — it just uses the natural `aligned_angle`, which happens to
leave enough clearance without ever having to defend against anything.

Fixed by passing `ring_positions.values() + substituent_positions.values()`
as `avoid_points` at both call sites, so the existing search (unchanged
otherwise) now also treats the ribose ring's own atoms as something to
maximize distance from. No change to `derive_base_layout()` itself, no
change to the anchor-pinning/window-bounding architecture — the search
mechanism was already correct, it was just being fed an incomplete
picture of what to avoid.

Awaiting a live screenshot to confirm the base ring now clears its own
ribose ring for paired (template) residues, without regressing
leading/lagging's already-correct unpaired spacing (their code path is
unaffected — `avoid_points.is_empty()` no longer applies once ring atoms
are always included, so this DOES now run the search for previously-
unpaired residues too once real chain/ring data exists; needs a live
check, not just an assumption).

**Follow-up CQA:** re-checked numerically against the next F9 dump — the
fix reduced crowding only marginally (closest base-to-ribose distance went
from ~3.5 to ~3.9 units, essentially noise). Root cause: the clearance
search is still bounded to the same ±15-degree window
(`BASE_ROTATION_SEARCH_WINDOW_DEG`) chosen to limit glycosidic-bond
stretch — feeding it the ribose ring as something to avoid didn't help
because no angle within that narrow window actually escapes the overlap.
This confirmed a separate, deeper issue (Bug L, below) was the real
source of what visually read as continued crowding.

### Bug L: ribose ring bulges toward the base while the phosphate chain reaches away (template strands only)

Found via the user's own before/after visual comparison (same technique
as Bug J): a leading-strand nucleotide (unpaired) shows a clean "neck"
between ribose and base; the equivalent template nucleotide shows the
sugar and base reading as one fused mass with no gap — described as "the
ribose pentagon's point is aiming the wrong way."

Verified quantitatively, not just visually: computed the ring's own
"bulge direction" (average of C2'/C3'/C4'/O4' relative to C1') and the
chain's own "reach direction" (alpha-phosphate relative to C1'), then
their dot product. Leading: +555 (aligned — ring and chain form one
continuous backbone shape). Lagging: +492 (aligned). Template_top: -110
(opposed). Template_bottom: -173 (opposed). Both template strands
specifically have the ring bulging one way and the chain reaching the
opposite way within the SAME residue — exactly what reads as a
wrong-facing pentagon.

Root cause: `RiboseDeriver.apply_strand_direction()`'s ring rotation is
driven by a FIXED per-strand sign (`STRAND_DIRECTION_SIGN` in
`molecule_structure_renderer.gd`, representing real 5'->3' reading
direction, checked against SKILL.md's polarity table) — it must stay
fixed regardless of live pairing state, or consecutive residues along the
same strand would zigzag. Bug J's chain flip, by contrast, is driven by
live `pairing_direction`. Before Bug J both used the ring's own
as-derived local frame and so always agreed (even though the chain
pointed at the partner — Bug J's original problem). Bug J fixed the chain
alone; for leading/lagging this was invisible (their needed flip is
always `false`, so nothing diverges from the ring), but for
template_top/template_bottom the chain's flip is always `true` while the
ring's fixed-sign rotation never changed — breaking their mutual
consistency specifically for the two strands Bug J touched.

**Options considered** (laid out for the user before implementing):
(A) apply the SAME flip decision to the ring too, as an additional
rotation on top of the fixed-sign one; (B) revert Bug J's chain flip
entirely and solve the original toward-partner overlap via spacing
instead; (C) check whether `STRAND_DIRECTION_SIGN`'s template_top/
template_bottom values are themselves wrong and swap them. Chosen: **A**
— most targeted, doesn't touch the separately-verified reading-direction
property, and keeps Bug J's confirmed-correct "chain away from partner"
behavior intact.

**Implementation** (`scripts/ribose_deriver.gd`): extracted the shared
180-degree point-reflection into `_rotate_180()` (used by both
`apply_strand_direction()` and the new function). Added
`apply_partner_flip(local_positions, pivot, probe_id, pairing_direction)`
— reuses Bug J's exact dot-product test (does the ring's own C4' local
position, un-normalized-relative-to-pivot, face toward the real partner?)
but applies the resulting 180-degree rotation to the RING instead of
negating the chain. Verified by hand against the dump that composing this
with the existing sign-rotation produces the correct net result for both
cases: template_top (sign-rotation off, this rotation fires: 0+1=1,
bulge flips to match chain) and template_bottom (sign-rotation on, this
rotation also fires: 1+1=2=identity, bulge flips back to match chain) —
two 180-degree rotations around the same pivot (C1') compose exactly as
expected either way. `derive_substituents()` itself is left completely
unchanged (still supports its own `pairing_direction` parameter) — the
call sites in `molecule_structure_renderer.gd` now call
`apply_partner_flip()` on the ring immediately after the existing
`apply_strand_direction()` call, then pass `Vector2.ZERO` to
`derive_substituents()` instead of the real `pairing_direction`, since
the chain now inherits the correct direction for free from wherever the
ring ends up.

**Easy revert** (explicitly requested): delete the two
`apply_partner_flip()` call sites in `molecule_structure_renderer.gd` and
restore their `derive_substituents()` calls to pass real
`pairing_direction` again — `apply_partner_flip()` itself is purely
additive and can be left in place unused. **Easy test of Option C**
instead: swap `STRAND_DIRECTION_SIGN`'s `template_top`/`template_bottom`
values — fully independent of this change, no interaction.

Awaiting a live screenshot to confirm the ring now visually reads as one
continuous piece with the chain for template strands, without regressing
leading/lagging (their flip decision is unaffected — always `false`, so
`apply_partner_flip()` is a no-op for them by construction, verified
above via the dot-product check staying positive).

**Confirmed via screenshot**: ring and chain now read as one continuous backbone unit for template strands, matching leading/lagging's known-correct shape. Remaining known issue (separate from this fix): the inter-residue phosphodiester backbone line (connecting one residue's O3' to the next residue's alpha-phosphate) crosses diagonally through the ring/base glyphs rather than routing cleanly around them — not yet investigated.

### Bug M: chain outward direction driven by ring-vertex angle, not by pairing_direction directly (EXPERIMENTAL)

Root cause of the crossing (identified by code inspection, not fresh
numeric verification — the diagnostic dumps on hand predate Bug L and are
stale for this specific check): `derive_substituents()`'s `outward`
direction was derived from wherever C3'/C4' happen to sit on the regular
pentagon — never purely vertical, since a 5-fold-symmetric shape has no
vertex exactly opposite the start angle. Over the chain's 3 bond-lengths
(C4'->C5'->O5'->alpha-phosphate) that unavoidable horizontal drift
compounds enough to land alpha-phosphate close to/past the NEXT residue's
own ring — the direct cause of the inter-residue backbone line crossing
through neighboring ring/base glyphs.

User proposed mirroring the ribose+phosphate group horizontally. Flagged
a real risk instead of implementing literally: a per-axis negate (mirror)
of just the chain would invert its shape relative to the ring's own,
already-chirality-correct orientation (the ring itself is untouched by
this), reintroducing the same category of problem Bug L just fixed — two
independently-oriented parts of one residue disagreeing with each other.

Implemented a chirality-safe alternative achieving the same practical
goal instead: since Bug L already established `pairing_direction` as the
reliable "away from partner" vector, `derive_substituents()` now uses
`-pairing_direction.normalized()` directly as `outward` for BOTH
substituent groups (when paired; unpaired residues keep the old
C3'/C4'-derived fallback), rather than deriving direction from wherever
the ring vertices happen to sit. This does not negate any axis or reflect
anything — it is a different, still-legitimate choice for what "outward"
means (documented in the original Bug J comment as "the simplest
idealized choice," never a hard constraint), so it cannot reintroduce the
mirror/chirality bug. Both call sites in
`molecule_structure_renderer.gd` (`_rebuild_layout()` and
`_derive_full_residue()`) now pass the real `pairing_direction` into
`derive_substituents()` again (previously `Vector2.ZERO`, disabled by
Bug L's redesign) since it's now load-bearing for direction, not just a
flip toggle.

**Explicitly experimental** (user: "if it doesn't work, we'll revert and
try to gather data from numbers"): easy revert is restoring the
`flip`-boolean block this replaced (preserved in git history) and
switching the two call sites back to `Vector2.ZERO`. Awaiting a live
screenshot to confirm the backbone line no longer crosses through
neighboring ring/base glyphs, without regressing anything Bug L already
fixed (base placement is untouched — `derive_base_layout()` never reads
`derive_substituents()`'s output, only the final positions via
`avoid_points`).


**REVERTED** — user tested it live and it did not fix the crossing; reverted immediately (git diff confirmed clean, both call sites back to Vector2.ZERO, flip-boolean logic restored verbatim). Per the original plan, next step is gathering real numbers (fresh F9 dump against the current Bug-L-fixed geometry) rather than reasoning from code alone.

**Fresh F9 dump provided, decisive test run**: temporarily forced
straight-chord mode unconditionally in `_build_bond_points()`
(bypassing curve-following entirely) and had the user screenshot. **The
crossing persisted** — ruling out curve-following as the cause (reverted
immediately after, one line, confirmed clean).

Re-verified with a proper point-to-line-segment distance check (not just
axis-aligned bounding-box overlap, which can miss a non-axis-aligned
pentagon) against every real atom of both the current and next residue,
using the fresh dump's actual coordinates. Result: the bond line never
comes within 10.8 units of the NEXT residue's ring, and not within range
of its base at all. The only atoms it passes near (4-15 units) are the
O3'/C5'/O5'/alpha-phosphate cluster it actually connects — i.e., its own
chain and the chain it terminates at, which is geometrically unavoidable.

**Conclusion so far**: the crossing is not the bond line passing through
a NEIGHBORING residue's ring or base — that hypothesis is now
conclusively ruled out by two independent checks (bounding-box and
point-to-segment) against real, current, post-Bug-L coordinates. The
visible crossing more likely reads as the bond passing near/behind its
OWN chain's tightly-clustered O5'/C5'/alpha-P atoms at the top of each
residue (a real proximity, ~4-15 units, plausible to misread as crossing
at deep zoom with rendered atom circles). Confirming this precisely needs
clearer atom-identity ground truth in the screenshot than pixel-position
guessing can provide — deferred to the atom-labeling work, which the user
independently wants to do next and should directly resolve this question
too.

### Atom identity labels (user request, unblocks the crossing-diagonal question directly)

Rendering previously labeled every atom with its bare element symbol only
("C", "N", "O", "P") — impossible to tell C3' from C1' from a base-ring
carbon at a glance, or which oxygen is the 3'-OH vs. the one that actually
bonds the alpha-phosphate, purely from the screen.

Added `ATOM_DISPLAY_LABELS` (`molecule_structure_renderer.gd`) — a pure
display lookup keyed by the atom's own role suffix (topology roles are
always `"incoming.<suffix>"` / `"chain.<suffix>"`, per
`molecule_topology.gd`'s `add_atom()`), mapping to real atom names:
ribose ring stays C1'-C4'/O4'; substituent chain O3' (this residue's own
3'-OH, its outgoing connection point) vs. O5' (the one that actually bonds
alpha-phosphate) are now visually distinct; triphosphate atoms get Greek-
letter labels (Pα/O1α/O2α/Oαβ etc., matching real biochemistry notation);
base-ring atoms use their real purine/pyrimidine numbering (N1, C2, N3...).
Falls back to the bare element for anything not in the table. Wired via a
new `_atom_display_label(role, element)` helper, stored as `label` in
`_atom_layout` alongside the existing `element` field (kept, still used
for circle coloring), and the draw loop now renders `a.label` instead of
`a.element`. Purely a rendering/display change — does not touch
topology, layout, or any geometry-derivation code from Bugs J-M.

Motivated directly by the crossing-diagonal investigation: prior analysis
narrowed the crossing down to "passes near the O5'/C5'/alpha-P cluster,
can't tell which atom exactly without real labels" — this should let the
next screenshot answer that precisely instead of guessing from pixel
positions.

---

## Culling note

Q9's decision (`MolecularStructure_OpenQuestions_RenderClusterResolution.md`)
— per-molecule bounding-box culling only, no per-atom fallback — is **not
re-litigated here**. The padding formula is widened to account for a base
pair's real extent now spanning both strands (the H-bond span), via a new
`estimated_pair_span` ThemeManager field (~`dna_ribbons_gap`, the same live
distance `_update_hydrogen_bond_height()` already reads) added alongside the
existing flat `molecular_cull_bbox_padding`. This is a parameter tweak
within the existing Q9 decision, not a new decision — full per-atom culling
remains deferred, same status as before.

**CQA follow-up (post-ship):** the working-set assumption behind Q9 ("a
handful of nucleotides visible") stopped holding once this pass shipped —
at the then-current `zoom_free_camera_max_zoom_in = 4.0` ceiling, the
per-molecule cull window (`viewport_size / zoom.x`) stayed wide enough to
keep 10+ nucleotides simultaneously in skeletal mode, each now carrying a
full base + backbone + H-bond lines across up to 4 strands — a real
performance drop. First interim fix tried: raised
`zoom_free_camera_max_zoom_in` to `8.0` (`theme_manager.gd`) alone.

**That alone wasn't enough — CQA follow-up #2.** Raising only the ceiling
narrows the cull window solely once actually zoomed to near it; for most of
the active range the window was still sized by `molecular_zoom_enter_threshold`
(3.0, unchanged at that point), which stayed wide enough (~427px at a
1280px viewport, ~8 nucleotides) to reproduce the same perf problem
anywhere short of the extreme max zoom. Fixed by raising the activation
thresholds themselves too: `molecular_zoom_enter_threshold` 3.0 -> 6.5,
`molecular_zoom_exit_threshold` 2.2 -> 5.5 (same hysteresis gap,
`theme_manager.gd`), so the cull window is already narrow (~197px, ~3.6
nucleotides) at the moment skeletal mode activates, not only at the
ceiling. Recorded as a parameter tweak, not a Q9 re-decision; if still
insufficient, the next lever is tightening `molecular_cull_bbox_padding`/
`molecular_pair_span_padding`, and the one after that is finally building
the deferred per-atom culling tier.
