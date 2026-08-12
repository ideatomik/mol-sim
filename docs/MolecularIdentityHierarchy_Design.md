# Molecular Identity Hierarchy — Design (Nucleation phase, captured from discussion)

Status: captured from a live debugging session, not yet a Lattice pass. No
ground-truth file reads have happened against this yet. Parked here to be
picked up as its own Nucleation → Lattice pass in a future session, starting
with reading whatever the current bead-glyph and ball-and-stick code
actually does before committing to anything below.

---

## Seed problem

Switching the ball-and-stick tier to standard CPK (element) coloring solved
element legibility but lost something the bead-glyph tier had: a way to
tell, at a glance, *which molecule* you're looking at — not which atoms.
CPK is element-identity, not molecule-identity, and structurally cannot
carry molecule-identity, because two different molecules can be built from
the same handful of elements and look identical under pure CPK (adenine vs.
guanine now; citrate vs. isocitrate later in Krebs).

This surfaced first in DNA but is not a DNA-specific bug — it's the general
shape of a problem every future molecular module (Krebs first) will hit the
same way. Worth solving once, generally, rather than per-module.

## Accessibility constraint

Whatever channel replaces the lost color-identity cannot be color-only.
The bead-glyph tier's precedent (if confirmed — needs ground-truth check)
combines color with a letter/label; any new channel at the ball-and-stick
tier should follow the same pattern rather than reintroducing a
color-only encoding that quietly repeats the accessibility gap.

## The hierarchy

For DNA specifically, molecular identity information exists at three
nested tiers. Not all of them need an explicit *added* channel — some are
already self-encoded by real chemical structure, and adding a redundant
channel on top is noise, not signal.

### 1. Base pair (A-T vs. G-C) — self-encoding, no new channel needed

A-T forms two hydrogen bonds; G-C forms three. This is a chemical fact
already rendered as soon as H-bond dashes are visible (two lines vs.
three). No color or label needed at this tier — it would duplicate
information the geometry already carries.

### 2. Purine vs. pyrimidine — mostly self-encoding, contingent on legibility

Purines (A, G) are fused bicyclic (two rings); pyrimidines (C, T) are a
single ring. This is also structurally self-evident *if the ring
silhouette actually reads clearly* at the zoom tier in question. At high
atom-overlap density this can get lost — the likely fix is not a new
channel but ensuring whatever backdrop/halo shape is added at tier 3
(below) is fit to the real ring boundary rather than a generic shape, so
ring-count legibility comes essentially for free.

### 3. Specific identity (A vs. G, or T vs. C) — needs an explicit channel

This is the tier structure does NOT disambiguate on its own. A and G are
both purines, same generic two-ring shape, differing only in substituent
detail easy to lose in visual noise. This is where an explicit identity
channel is justified.

**Proposed shape:** a low-opacity identity backdrop/halo behind the
residue's atom cluster, colored by base identity (ideally reading from the
same identity-color source the bead-glyph tier already uses, not a second
hand-tuned palette), shaped to the actual ring boundary rather than a
generic circle (serving tier 2's legibility for free), plus a small
letter/abbreviation badge — placed outside the atom cluster itself so it
doesn't compete with CPK element labels (N/C/O/P) already dense inside it.

Rejected alternatives, recorded so they aren't proposed again:
- **Recoloring atoms by molecule identity instead of element** — destroys
  the CPK convention the tier is also trying to teach; the option most
  likely to need re-deciding per future module.
- **Border pattern (solid/dashed/dotted) instead of a letter badge** —
  cheaper to read at a glance but doesn't scale past ~4 identities; Krebs
  will need a dozen-plus metabolite identities, and pattern vocabularies
  run out fast where letter/abbreviation badges don't.

## Related question: strand directionality legibility (5'/3' ends)

Surfaced during the antiparallel-orientation bugfix, not originally part of
the identity-hierarchy seed problem, but the same shape of question:
**information that is structurally present in the render is not the same
as information a first-time viewer can actually read.**

Context: the bead-glyph tier carries an explicit directional strand rail
(colored bar with triangle arrowheads) unambiguously showing 5'→3'
direction. That rail is currently suppressed at the ball-and-stick tier
and not replaced with an equivalent — the plan instead is to let the real
phosphodiester connectivity (each ribose's phosphate sitting on the 5'
side, free O3' on the other) stand in for it, since that connectivity is
the actual chemistry rather than a symbolic add-on.

**The open concern:** structural asymmetry being genuinely present doesn't
mean it's legible without prior knowledge. The rail's arrowhead required no
interpretation — follow the triangle. "The phosphate cluster sits closer to
this side of the ring" is real information, but reading direction from it
is an inference a first-time viewer has to construct, not something they
can just look at. This is the identical gap the accessibility constraint
above is about (color-only encoding requiring the viewer already know the
convention) — same failure shape, applied to spatial/structural asymmetry
instead of color.

**Two explicit rejections already made, both to preserve chirality
correctness established during the orientation fix:**
- No full per-atom prime labeling (C1'–C5' on every backbone atom) as the
  general solution — reconstructs directionality via chemistry-major
  detail rather than a purpose-built cue, and reintroduces the exact
  label-density problem the atom-scale/label thread this session fought to
  reduce. May still be worth a narrow, togglable debug-only version, kept
  separate from any permanent student-facing answer.
- No horizontal mirror of either strand to make top/bottom "look
  symmetric" — a mirror inverts sugar chirality; the asymmetric look
  between antiparallel strands is the expected, correct result of a proper
  180° rotation, not a bug to visually correct away.

**First superseded direction (recorded, not pursued):** a minimal,
one-per-strand-end marker — small "5'"/"3'" tags at the two visible
terminal residues (or at the replication fork) — was floated as a
low-cost option in the same spirit as the tier-3 base-identity badge.
Superseded before being designed further.

**Second superseded direction (recorded, not pursued):** a per-bond
arrowhead (small triangular arrowhead centered on each phosphodiester
bond, pointing toward the alpha-phosphate end per
`_build_backbone_bonds()`'s own point ordering). Live review found it
still relied on comparing adjacent atom labels (O3' vs. O5') to confirm
direction, which reads ambiguously to a first-time viewer — seeing "3"
appear before "5" in sequence looks like counting backward even though it
correctly represents 5'→3' progress across the residue boundary.

**Third superseded direction (recorded, not pursued) — the continuous
backbone ribbon.** A continuous ribbon/outline threading through every
backbone atom center in sequence
(...C3'-O3'-Pα-O5'-C5'-C4'...), tapering to a point at the 3' end, was
designed and written up as "decided" in an earlier pass of this document.
**Deprecated on review, before implementation began, for being redundant
rather than wrong:** the inter-residue path this ribbon would trace is
already fully covered by the existing backbone bond render plus the
directional arrow on it — re-threading through Pα/O3'/O5' a second time
added a second visual layer saying the same thing the bond+arrow already
say, not new information. Replaced by the resolution below, which adds
information the bond+arrow do NOT already carry (see next section).

### Resolution — intra-residue directional capsule (decided, shipped)

**What ships:** a discrete, border-only, unfilled capsule per residue,
spanning only the intra-residue segment from that residue's C5' to its
own C3' (not threading between residues — the inter-residue path stays
exactly as it already renders today, bond + arrow, untouched by this
work). Every residue at the full-label zoom tier gets one. The capsule
tapers to rounded semicircular caps at each end, radius = atom radius +
padding, so C5' and C3' sit fully enclosed with visible breathing room
between atom edge and capsule border — not a shape avoiding the atoms.

**Why this and not the ribbon:** the ribbon over-solved the problem by
re-stating direction at the inter-residue boundary, where it was already
legible. The capsule instead adds a *repeated, high-frequency* directional
cue at a point the bond+arrow don't cover — inside each residue — so a
viewer gets confirmation at every single sugar, not just at the junctions
between them. This is also what makes it read "instinctively": repetition
density, not a single continuous shape to trace.

**Construction:** implemented as `ProceduralShapeUtils.capsule_outline()`
in `procedural_shape_utils.gd` — a new, purpose-built method (not a reuse
of `round_corners()`, which rounds a pre-built polygon's sharp vertices
via sampled bezier pullback and was confirmed not to be a fit for
synthesizing a true semicircular cap from two bare endpoints + a radius).
Takes `from`, `to`, `radius`, `segments`; returns a closed-loop
`PackedVector2Array` walking both straight sides and both semicircular
caps, swept in a consistent rotational direction (both arcs decreasing
from `perp_angle`) — an earlier attempt swept both caps through the same
side and produced a self-intersecting bowtie/pointed-petal shape instead
of a smooth capsule; documented in the function's own header comment as a
guard against reintroducing that bug. Degenerate-safe: `from == to`
collapses to a zero-area loop rather than crashing.

- **Rendering:** border/outline only, drawn with `draw_polyline()` /
  `draw_polygon(..., filled=false)` — never filled. This was a deliberate
  requirement, not an oversight, so the capsule reads as a highlight
  outline rather than an opaque overlay competing with the atoms and
  labels inside it.
- **Tunables exposed on ThemeManager** (not hardcoded), matching the
  project's usual `@export`-on-Inspector convention for this kind of
  visual knob: capsule padding/width (distance from the C5'-C3' line to
  the capsule edge), border thickness, border color.
- **Gating:** full-label zoom tier only, same rationale as both
  superseded approaches — shares a threshold with label-tier staging
  rather than introducing a third independent one.
- **Accessibility:** shape-based, not color-only — satisfies the existing
  "shape + thickness, never color alone" rule.
- **Scrub-safe:** capsule geometry is a pure function of the residue's
  current C5'/C3' derived positions — no stored or animated state.
- **Nick handling — resolved as a side effect of the shape itself, not a
  special case.** Unlike the ribbon (which would have needed explicit
  logic to avoid bridging an unsealed Okazaki fragment boundary), the
  capsule is inherently per-residue and self-contained — a nick between
  two residues simply means there's a gap between two independent
  capsules, the same way the backbone bond itself already shows the gap.
  No extra nick-awareness code needed in the capsule logic.
- **Dependency bug found and fixed during testing, unrelated to the
  capsule itself:** while validating against a base-complexity-tier
  sequence (`ligase_enabled = false`), an Okazaki fragment nick was found
  rendering where it shouldn't exist at all yet — fragment
  boundaries/nicks are a maturation-tier concept, and the base tier should
  render the lagging strand as continuous. The nick's own rendering was
  confirmed correct (right visual); the bug was a missing/incorrect
  complexity-tier gate on when that rendering path runs at all. Fixed
  separately from this capsule work — noted here because it's what
  blocked a clean screenshot-based validation of the nick case above
  until resolved.
- **Still open:** exact default padding width / border thickness / color
  values — tunables are exposed and adjustable live, no committed defaults
  recorded here yet.

**Status of the "functional-group grouping" cross-reference in
`AtomTier_VisualDesign.md`:** the ribbon's deprecation removes the
cross-reference the earlier version of this document drew to that doc's
parked "outline/boundary line" option — the capsule is a narrower,
different-shaped tool (short, per-residue, direction-specific) and
doesn't straightforwardly generalize to that doc's broader phosphate/
ribose/base grouping question the way a continuous derived-outline tool
might have. That question remains open and un-informed by this work.

## Generalization beyond DNA (why this matters now, not just for DNA)

Krebs cycle metabolites will hit the same three-tier shape:

- **Self-encoding, no channel needed:** gross carbon-skeleton size
  (6-carbon citrate vs. 5-carbon α-ketoglutarate) — structurally evident
  the same way ring count is for purine/pyrimidine.
- **Needs the explicit channel:** citrate vs. isocitrate — same 6 carbons,
  differing only in hydroxyl position. This is Krebs's equivalent of A vs.
  G: chemically real, structurally near-identical, genuinely ambiguous
  without an explicit tag.

This is the same territory the aconitase backbone-reorientation problem
already occupies as a named open exception in `MolecularStructureDesign.md`
(the citrate/isocitrate stereo question). Worth resolving the identity-
hierarchy design and the aconitase stereo question together rather than as
two separate passes, since they're pointing at the same underlying need —
distinguishing near-identical carbon skeletons at a glance.

## Open questions for the future Lattice pass

1. Does the bead-glyph tier's current base-identity encoding actually
   combine color + letter today, or is it color-only? (Needs ground-truth
   check before anything above is trusted as "already accessible.")
2. Where does the bead-glyph tier's identity-color value live — can the
   ball-and-stick halo cheaply read the same source of truth, or does it
   need its own?
3. Does the purine/pyrimidine tier need an explicit channel independent of
   ring-shape legibility, or is "make the ring silhouette read clearly"
   sufficient once halo shaping is in place? (Left open in discussion —
   worth deciding explicitly before implementation.)
4. For Krebs specifically: what is the full inventory of near-identical
   carbon-skeleton pairs (beyond citrate/isocitrate) that will need the
   tier-3 explicit channel? Bears directly on how much badge/color-palette
   real estate the design needs to support.
5. Does this identity-hierarchy framing get its own doc long-term, or does
   it fold into `MolecularStructureDesign.md` as an extension of the
   three-layer model (topology/layout/render-mode) — since identity
   channel choice arguably belongs in the render-mode layer specifically?
6. ~~Where should the 5'/3' end markers actually anchor~~ — moot; superseded
   by the capsule resolution.
7. ~~Does a debug-only togglable prime-labeling mode... get built as a
   short-term verification tool~~ — superseded; not needed by the capsule
   resolution.
8. ~~How does the ribbon render across an unsealed Okazaki fragment
   nick?~~ — moot; the capsule resolution is inherently per-residue and
   needs no special nick handling (see Resolution section above).
9. **Still open:** default padding width, border thickness, and border
   color for the capsule — tunables exist on ThemeManager, values not yet
   settled.
10. **New:** does the "functional-group grouping" open question in
    `AtomTier_VisualDesign.md` still benefit from `capsule_outline()`
    existing, even though the capsule itself doesn't generalize to that
    broader grouping question directly? Worth a look next time that doc's
    question is picked up, now that this shape-generation tool exists in
    the codebase either way.

---

## Scope reminder

Nothing here is committed to a timeline or implementation. This document
exists to be discussed and contradicted in writing once ground-truth file
reads happen, per the project's usual Lattice-phase discipline. Not to be
picked up until the current visual-debug thread (antiparallel strand
orientation, P-glyph bond convergence, atom scale/label derivation) is
closed out.
