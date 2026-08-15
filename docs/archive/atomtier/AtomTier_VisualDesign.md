# Atom-Tier Visual Work — Design (pre-implementation)

_Lattice-phase doc per the Crystal Building Method. Written the evening of
the template-DNA self-pairing fix, as a same-session handoff — **not
grounded against source**. Nothing in `molecule_structure_renderer.gd`,
`zoom_manager.gd`, `theme_manager.gd`, or `procedural_shape_utils.gd` was
read while drafting this. Ground before implementing._

---

## Nucleation — two visual problems from the same pedagogical goal

The atom-level tier's real payoff is letting a learner see structure they
can't see anywhere else in the sim. Right now it only partly delivers
that: labels exist, but at only one zoom band and one font size; and the
biological hierarchy (base pair → nucleotide → functional group) that a
learner is meant to build a mental model of is present in the *topology*
but invisible on screen — it has to be reconstructed by the viewer from
label text alone.

Two related but separable pieces:

1. **Label font scaling across zoom tiers** — small addition, discussed
   and settled last session (see below).
2. **Nested visual grouping** — a new open design problem, not yet scoped.

---

## Part 1 — Label font scaling by zoom tier

### Settled by design conversation (2026-08-06) — record here so it survives to implementation

Per the existing continuous-zoom-with-hysteresis architecture
(`ZoomDesign.md`'s free-camera model, and the two-threshold structure
`SurfaceBlobRenderTier_Design_Parked.md` already flagged as worth
reserving room for), the molecular tier gets a **second internal
threshold**, not a new tier:

- **Wider band** (both strands filling most of vertical screen space,
  full base-pair/H-bond view): labels show **element letter only** (C, O,
  P, N) — this already exists as the fallback path in
  `_atom_display_label()` per `MolecularStructure_BasePairExpansion.md`'s
  "Atom identity labels" entry, so this band may already be correct by
  default if the full-geometry labels are gated behind the new threshold
  rather than always-on.
- **Closer band** (single nucleotide filling vertical screen space): full
  geometry labels — `C3'`, `O5'`, `Pα`, etc. — exactly what's shipped
  today (`ATOM_DISPLAY_LABELS`).

**Font size is not a separate tunable to solve for** — explicitly
rejected as unnecessary complexity in the design conversation. Circle
radius (`molecular_atom_radius`) is fixed; a 1-2 character element label
naturally fits at a larger font than a 2-3 character geometry label at
the same circle size, and the closer band's extra zoom level compensates
for the smaller font automatically. **Two font sizes, one per band,
picked for legibility inside the fixed circle radius — no continuous
interpolation, no per-frame font recompute.**

### What still needs grounding/deciding at implementation time

- Confirm whether `ZoomManager` already has (per the "keep it as an
  ordered array of threshold pairs" recommendation flagged in
  `SurfaceBlobRenderTier_Design_Parked.md`) infrastructure that makes
  adding a second threshold band inside the molecular tier cheap, or
  whether that refactor never landed and this is now the thing that
  forces it.
- Confirm hysteresis is needed on this new threshold too (almost
  certainly yes, matching every other zoom-driven mode switch in this
  project) and that it gets its own ThemeManager-tunable band, not a
  shared constant with the bead-glyph↔molecular threshold.
- The two label states need their own font-size constants in
  ThemeManager, following the existing "never let two independently-tuned
  numbers coincidentally agree" rule — don't derive one from the other
  even though they'll likely end up looking related.

---

## Part 2 — Nested visual grouping (base pair → nucleotide → functional group)

### The problem, stated precisely

At atom zoom today, a base pair is ~20-40 discrete circles with labels.
The topology already encodes three real levels of grouping — which atoms
belong to the same base pair, which belong to the same nucleotide/residue,
and which belong to the same functional group (ribose ring / base ring /
phosphate group) within a residue — but nothing on screen shows it. A
learner has to infer grouping from label text and rough position alone.

This is explicitly the point of going to atom level in the first place —
the labels prompted this ideation because they let you see structure that
was previously invisible; grouping is the next layer of that same payoff.

### Candidate mechanisms — none decided, need to be worked through before this is buildable

- **Background shading/halo per group.** A soft, low-opacity rounded
  region behind each nucleotide's atoms (and a fainter one behind the
  whole base pair). Cheapest to reason about given the project already
  has `procedural_shape_utils.gd`'s rounding/inset tooling
  (`SurfaceBlobRenderTier_Design_Parked.md` recommends exactly this
  approach for the *unrelated* future surface-blob tier — worth checking
  whether that parked doc's hull-generation approach is directly reusable
  here, since both problems reduce to "wrap a soft boundary around a
  cluster of derived atom positions").
- **Outline/boundary line**, not filled shading — a drawn perimeter around
  each group instead of a background tint. Cheaper to keep legible against
  varying backgrounds (theme-dependent), more linework in an already
  busy view.
- **Color-family tinting**, distinct from the existing per-element circle
  coloring — e.g. functional-group membership shown via a tinted ring or
  label color, independent of the atom's own element color. Risk: this
  project already has a real accessibility commitment (shape+thickness,
  never color alone, per the RNA/DNA primer distinction work) — any
  grouping cue that's color-only would need a non-color companion signal,
  which likely rules this option out as a *sole* mechanism even if used
  as a secondary cue.
- **Spacing alone** (increase gap between groups, tighten gap within a
  group) — no new draw calls, but likely too subtle to read clearly at
  the density this view already has, and risks visually contradicting the
  bond-line geometry that already implies connectivity.

**No recommendation yet** — this needs to be worked through live, ideally
with 2-3 quick mockups compared side by side before committing to
building any of them out fully, rather than picking on paper.

### Open question — does grouping unlock progressively with the label tiers?

Raised but not settled last session: does functional-group-level grouping
(ribose/base/phosphate) only become visible at the closer zoom band
(alongside full geometry labels), while the wider band only shows
nucleotide- and base-pair-level grouping (alongside element-only labels)?
This would mirror the same pedagogical staging the label tiers already
establish — coarser structure visible first, finer structure revealed on
approach — and would mean grouping and labels share one threshold rather
than needing independent tuning. **Leaning toward yes**, since inventing
a third independent threshold for grouping alone seems like unnecessary
complexity given the label tiers already carve the zoom range at a
sensible point — but not confirmed, and worth deciding explicitly before
implementation rather than defaulting into it.

### Architecture note carried over from Part 1

Any of the candidate mechanisms above are drawn *underneath* the existing
atom circles/bonds, which matters for the "one `_draw()` per molecule"
immediate-mode constraint (`MolecularStructureDesign.md`'s ground-truth
correction #3/#6): draw order within that single call needs the group
shapes emitted before the atom circles, not as a separate pass, or the
rendering ceiling (~1000 glyphs before FPS drop) gets a second budget
line item (group shapes) competing with the existing one (atoms/labels)
that hasn't been accounted for yet.

---

## Suggested session order for tomorrow

1. Ground this doc — confirm current `ZoomManager` threshold structure
   and whether the array-of-thresholds refactor landed.
2. Part 1 (label font scaling) — small, well-specified, likely fast.
3. Part 2 (grouping) — spend time on 2-3 live mockups of the candidate
   mechanisms before writing any real implementation; this is the piece
   most likely to need a real back-and-forth with a screenshot before
   converging, not something to build once from this doc alone.
