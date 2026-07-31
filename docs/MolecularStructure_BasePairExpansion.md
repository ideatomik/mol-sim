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
