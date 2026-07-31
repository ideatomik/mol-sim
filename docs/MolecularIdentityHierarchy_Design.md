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

**Direction worth studying:** a minimal, one-per-strand-end marker — small
"5'" / "3'" tags at the two visible terminal residues (or at the
replication fork, where synthesis direction is actively relevant) — same
spirit and cost profile as the tier-3 base-identity badge above: placed
once per strand, not per-atom, giving a fixed anchor a student can read
the rest of the structural asymmetry against once they know which end is
which. Not yet designed in any further detail than that.

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
6. Where should the 5'/3' end markers actually anchor — the true terminal
   residues of each visible strand segment, the replication fork
   specifically, or both? Bears on whether this is a static per-strand
   label or something that needs to track a moving point during synthesis.
7. Does a debug-only togglable prime-labeling mode (C1'–C5', O3', O5' on
   backbone atoms only) get built as a short-term verification tool before
   the permanent end-marker answer is designed, or does it get skipped
   entirely once end-markers ship? Currently parked, not yet requested.

---

## Scope reminder

Nothing here is committed to a timeline or implementation. This document
exists to be discussed and contradicted in writing once ground-truth file
reads happen, per the project's usual Lattice-phase discipline. Not to be
picked up until the current visual-debug thread (antiparallel strand
orientation, P-glyph bond convergence, atom scale/label derivation) is
closed out.
