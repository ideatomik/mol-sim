# Surface Blob Render Tier — Design (Nucleation phase, parked)

Status: captured from discussion, not yet a Lattice pass. No ground-truth
file reads have happened against this — the skeletal/bead-glyph renderer
this would sit alongside didn't exist yet when this was written. Explicitly
NOT part of the DNA milestone just shipped (ribose + phosphodiester operator
+ skeletal rendering). Pick this up as its own Nucleation -> Lattice pass
when it's actually next in line, starting with reading whatever the Growth
session just produced.

---

## Seed problem

The render-mode ladder currently has two stops: bead-glyph (existing,
identity icon — a nucleotide reads as a colored shape, not a molecule) and
skeletal (new, atoms + labels, Haworth convention for rings). The jump
between them is large for anyone without organic-chemistry vocabulary —
going straight from "here's a nucleotide icon" to "here's a ring drawn in
Haworth projection with up/down stereochemistry" skips the step where a
learner builds intuition for "this is a physical object with a shape"
before being asked to read it as notation.

Prompted directly by a PyMOL-style molecular surface render (flat-shaded
mesh blobs distinguishing protein domains by color) as a reference point
for what an intermediate, shape-only representation could look like.

## Proposed shape: a third tier, not a replacement

bead-glyph -> surface blob -> skeletal, riding the same continuous
free-camera zoom scalar already decided for the bead<->skeletal swap (see
MolecularStructure_OpenQuestions_RenderClusterResolution.md, questions 4/7).
Not a new camera state, not a new mechanism — an additional band on the
scalar already in use.

## The core fork: authored icon vs. derived from real positions

**Authored (rejected):** copy the Na/K pump spike's approach directly — a
small number of hand-tuned, discrete-looked-up blob poses, disconnected
from real atom data (the pump spike never modeled actual amino-acid
positions; its lobes are a stylized stand-in). Applying this as-is to the
molecular-structure tier would mean a second, hand-drawn source of truth
for "what does ribose look like," independent of the topology/layout data
the skeletal renderer actually computes — a direct violation of Model B
(derived, not stored) and of the render layer's own stated principle
("zooming in does not load new art, it swaps renderer on data that was
already there").

**Derived (recommended):** compute the blob envelope from the real 2D
atom positions the Layout layer already produces every frame regardless of
active render mode (per the transition-mechanics decision, question 10 in
the same resolution doc). Same underlying data, third fidelity level —
bead-glyph's icon, skeletal's full atom+label rendering, and this tier's
silhouette would all trace back to one topology, never disagreeing with
each other by construction.

What DOES carry over from the pump precedent: the visual language only —
soft, overlapping, rounded shapes reading as organic bulk. Not the
generation mechanism.

## Recommended generation approach

Reuse `procedural_shape_utils.gd`'s existing rounding/inset tooling
(already used for enzyme silhouettes, and for the ATP cofactor bead-chain's
bond rendering) to wrap a generously-rounded hull around the current
cluster of derived atom positions — rather than building true metaball
shader blending. Reasoning: a "simplified, flat" look, per the person's own
framing, doesn't need soft per-pixel falloff blending to read as one
organic shape; a rounded hull over real points is cheaper, reuses tooling
that already exists project-wide, and avoids a new shader-level subsystem
for a stated goal of simplicity.

## Threshold structure implication

Adding this tier means the free-camera zoom scalar needs two threshold
PAIRS (four constants: bead<->blob hysteresis band, blob<->skeletal
hysteresis band) instead of the one pair already decided for the two-tier
version. This is additive to the render-cluster resolution already
shipped, not a correction to it — matches "complexity layers build upward,
not sideways." One cheap thing already flagged to the just-finished Growth
session: keep the existing two thresholds in a structure that could extend
to four later (an ordered list/array) rather than two named constants
baked into branching logic, so this addition doesn't force a refactor of
code that's about to ship. Confirm whether that made it in when reviewing
the Growth session's results.

## Open questions carried into this lattice — none decided yet

- **Hull algorithm and granularity.** What point cluster defines one
  "blob" — a single ribose's atoms? A whole visible nucleotide including
  its base? A run of several nucleotides once zoomed out far enough that
  individual sugars aren't the unit of interest? Not decided; likely
  depends on where the threshold bands actually land once tuned in-engine.
- **Per-frame recompute vs. cached.** Layout positions are already
  recomputed every frame per existing discipline — does the hull wrapping
  those positions get recomputed every frame too (correct by construction,
  matches everything else in this project), or does it need caching with
  explicit change-detection for cost reasons? Unmeasured; likely fine to
  recompute given the small point counts already established for this
  milestone's working set, but not confirmed.
- **Threshold placement.** Does the blob tier eat into what's currently
  bead-glyph's zoom range, skeletal's, or carve a genuinely new band
  between them? No numbers exist yet — needs eyes on the actual two-tier
  version in motion first.
- **Scope beyond DNA.** Is this tier DNA/ribose-specific tuning, or does
  it generalize cleanly to Krebs and later modules once they exist? Likely
  the latter given it's derived from generic topology/layout data rather
  than anything ribose-specific, but not tested against a second molecule
  yet.

## Suggested next step

Once the DNA milestone's two-tier version has been through CQA and is
stable: read the actual shipped render-mode code (not assumed from this
doc), confirm whether the threshold-extensibility ask was honored, and
open this as a proper Lattice pass — starting with picking a concrete
first test case (one ribose, most likely) before touching hull-generation
code.
