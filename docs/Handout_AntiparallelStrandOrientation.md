# Handout: Antiparallel Strand Orientation Bug (Molecular Structure, ball-and-stick tier)

## Ground-truth discipline first

Before touching anything: read the actual current state of `RiboseDeriver`,
`NitrogenBaseDeriver`, and `MoleculeFoldEngine` (whatever files/functions
those calls actually live in now — names above are from prior design-doc
discussion and may not match current source). Do not assume from the design
docs what these currently do. If anything below contradicts the real code,
the real code wins — note the divergence, don't silently patch around it.

## Symptom

At the ball-and-stick zoom tier, `template_bottom` and `template_top` ribose
rings are both facing/puckering the same visual direction, so adjacent
strands' sugar rings bulge into each other instead of nesting into the gaps
between residues. Confirmed NOT caused by shared/copied position data —
`get_template_nucleotides()` reads two genuinely separate node arrays
(`nucleotide_bases[i].global_position` vs `top_strand_bases[i].global_position`),
each already positioned by its own independent curve math
(`rail_path` vs `top_rail_path`, including per-strand wobble). Pairing is
computed per-residue via `_pair_for_slot()` against the real partner
position, not a hardcoded flip. Fold cache keys (`"strand:slot"`) confirm
no cross-strand cache reuse either.

So this is not a copy/translate bug. World anchors, pairing, and caching
are all independently correct per strand.

## Diagnostic step — do this FIRST, before any fix

`template_bottom` and `template_top` run **antiparallel**: their 5'→3'
reading direction runs opposite screen-directions relative to each other,
even though both strands' residues are laid out left-to-right on screen.

Check: does the ring/substituent orientation derivation (whatever function
currently sets which way the furanose ring's local "up"/pucker-forward axis
points) take strand directionality as an explicit input — i.e., which way
5'→3' is running on screen for *that specific strand* — or is that axis
implicit/constant across all four strand calls (`leading`, `lagging`,
`template_bottom`, `template_top`)?

Fastest way to confirm: grep every call site that invokes the
ring-orientation/fold step for `template_bottom` vs `template_top`, and
diff what directionality-related argument (if any) each call passes in.
If both calls pass the same value, or if no such parameter exists at all,
that's the bug — a missing directionality input on the orientation step,
not a positioning problem anywhere else in the pipeline.

Report back what you find here before writing any fix. If the diagnosis
above is wrong — if there's already a directionality parameter and it's
being computed correctly — stop and flag that; don't invent a different
explanation to make the fix land.

## The fix constraint — rotate, not mirror

Once the missing/wrong directionality input is confirmed: the correction
must be a **180° rotation** of the ring's local orientation around the axis
perpendicular to the screen — never a mirror/reflection across an axis.

Why this matters specifically here: a rotation preserves chirality in 2D.
A mirror reflection inverts it. The ribose ring's derivation already
carries a fixed-chirality convention (this is the same convention the
aconitase backbone-reorientation problem is tracking as a named open
exception in `MolecularStructureDesign.md`). A naive mirror would visually
fix the overlap while silently flipping the sugar to the wrong
enantiomer on screen — a correctness bug masquerading as a fixed layout
bug, and one that wouldn't be obvious from a screenshot.

Concretely: whatever parameter currently drives the ring's forward/pucker
axis should take antiparallel direction as an explicit sign (+1 for one
strand's screen-direction, −1 for the other) feeding into a rotation of
the derived positions, not into a coordinate reflection (no negated x or y
axis on the ring's local frame).

## Where this belongs

Per the three-layer model in `MolecularStructureDesign.md`: this is a
**Layout**-layer concern (deterministic function from topology to 2D
positions), not a render-mode concern. If the fix ends up touching
render-time code instead of the layout/fold derivation itself, stop and
flag that — it likely means the directionality information isn't
reaching the layer that should own it, which is a bigger finding than a
one-line fix.

## Scope fence

Fix the orientation input for `template_bottom`/`template_top` (and check
whether `leading`/`lagging` have the same latent bug, even if it's not
visually obvious yet — they're antiparallel to their respective templates
too). Do not touch bond rendering, label placement, atom radius/scale, or
anything from the earlier P-glyph-overlap or atom-scale threads — those
are separate, already-tracked issues.

## Report back

- What the directionality input currently looks like (or its absence) at
  each of the four strand call sites.
- Whether the fix was a rotation as specified, and where it landed
  (Layout layer, confirmed).
- Whether `leading`/`lagging` show the same latent issue.
- Anything in the real files that contradicts this handout's assumptions.
