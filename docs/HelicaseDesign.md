# Helicase Visual Design — v71 (implemented)
_Implemented in v71 as the procedural helicase ring (`helicase_ring.gd`).
Retained as the design rationale and as a reference pattern for future enzyme
visuals — the body below is the original pre-implementation discussion; see
**As-Built (v71)** immediately below for where the shipped version diverged.
Companion to DESIGN.md's "Procedural enzyme visuals" architecture section._

---

## As-Built (v71)

What actually shipped, and where it diverged from the design below. The design
body is kept intact as reference; this note is the source of truth for the
current implementation.

- **Octagon, not a plain hexagon.** The subunit blob shipped as the shared
  rounded-corner **octagon** primitive (flat vertical sides + chamfered caps +
  generic corner-rounding), later reused verbatim by the polymerase clamp — not
  the plain 6-vertex `draw_polygon` hexagon this doc proposed. The corner-rounding
  the doc deferred did ship, and a small `skew_deg` was added that the design
  didn't call for.
- **Rotation math shipped as designed.** The `|cos θ|` width/height breathing,
  the `sin θ` vertical placement, and the front/back z-order split all shipped as
  described, driven purely by `helicase.gd`'s `current_slot_index` +
  `get_eased_step_t()` (no independent clock), so speed-multiplier /
  finishing-acceleration / scrub all fall out for free.
- **Parameters live in the "Helicase Ring" ThemeManager group.** Blob count and
  per-step angle are Inspector-tunable exports (`helicase_ring_blob_count`,
  `helicase_ring_step_angle_deg`) rather than hardcoded — treat that group as the
  source of truth for final values. It also holds `ring_radius`,
  `max_blob_height` / `max_blob_width`, `min_width_ratio`, `chamfer_ratio`,
  `corner_radius_ratio`, `corner_segments`, `skew_deg`, front/back colour, front/
  back z, and `rotation_enabled` (the low-info toggle the doc anticipated).
- **The export-group question is resolved.** The doc left open whether the new
  "Helicase Ring" group would replace the old "Helicase" group. It did: the Ring
  group shipped alongside, and the old "Helicase" group
  (`helicase_color`/`_thickness`/`_half_width`/`_height_margin`) was then removed
  in the v71 polymerase-clamp pass, once nothing read it.
- **Still open (unchanged from the design):** text labels, and the shared
  `_round_corners()` utility extraction (currently duplicated with
  `polymerase_clamp.gd`).

---

## Context

Current state: the helicase is a simple vertical object spanning the height
of the template DNA (with padding), representing the side view of the
DnaB hexameric ring as it travels along the unzipping point. This document
pins down the design for replacing that placeholder with an animated
six-subunit ring, viewed edge-on (side view), consistent with the flat
horizontal-ribbon perspective the rest of the scene uses.

A face-on circular ring was considered and rejected — it would break the
established flat/side-view perspective of the scene.

---

## Visual concept

Six blobs ("subunits") occupy the vertical band currently drawn as the
single blue rectangle. Each blob cycles through a vertical barrel-roll
motion: surging up from the bottom of the band, growing to full size at
the vertical center (directly on the unzipping point), then shrinking again
as it continues toward the top — simulating a subunit rotating around to
the back of the ring, viewed from the side. This is the same class of
illusion used by mechanical slot-machine reels (vertical cylinder rotation
depicted via vertical position + squash, viewed from the side).

ASCII sketch of the effect across frames (each line a frame, brackets a
blob at a given height):
```
[]-[   ]-[ ]
[ ]-[   ]-[]
[  ]-[   ]-[
-[   ]-[   ]-
]-[   ]-[   ]
[]-[   ]-[ ]
```

---

## Motion math

Each blob `i` (0–5) has a phase angle `θᵢ`, evenly spaced at 60° apart.

```
θᵢ = (current_slot_index + get_eased_step_t()) * 60° + i * 60°   (mod 360°)

y           = ring_center_y + ring_radius * sin(θᵢ)
blob_height = max_blob_height * abs(cos(θᵢ))
blob_width  = max_blob_width * (min_width_ratio + (1 - min_width_ratio) * abs(cos(θᵢ)))
z_order     = front if cos(θᵢ) > 0 else back
```

- `min_width_ratio` (suggested 0.15–0.25) prevents the blob from collapsing
  to a literal zero-width line at θ=90°/270° — keeps a visible edge-on
  sliver through the "going around the back" phase instead of a hard pop.
- Both width and height breathe together with `cos(θᵢ)`, not height alone —
  sells the roundness of a rotating body rather than a one-axis squash.

### Why this is driven by `helicase.gd`, not an independent clock

Rotation is defined entirely as a function of `helicase.gd`'s existing
`current_slot_index` and `get_eased_step_t()` — the same values that already
drive `helicase_x`'s smooth glide. Consequences:

- **Sync guarantee**: a blob reaches θ=0 (full height, full width, dead
  center) at the exact instant `step_t` reaches 1.0 — i.e. exactly when the
  helicase visually arrives at the next slot. This is the intended moment
  for the hydrogen bond at that slot to break — the fully-visible, full-width
  blob covers the gap between the strands at the unzipping point,
  visually masking the bond-breaking moment. No separate timer is needed to
  hit this timing; it falls out of the shared `step_t` input.
- **Speed multiplier / finishing acceleration**: already modulate
  `step_duration`, which `step_t` derives from — the ring automatically
  speeds up/slows down in lockstep with the helicase with no extra plumbing
  (same "derive, don't duplicate" pattern `helicase_x` already follows).
- **Scrubbing**: rotation is a pure function of `(current_slot_index,
  step_t)`, both of which scrub already sets directly and instantly (no
  tweening — consistent with the project's scrub-is-always-instant rule).
  The ring snaps to the geometrically correct rotation for free; no
  scrub-rebuild logic is needed for the ring specifically.

### Occlusion width requirement

`max_blob_width` at θ=0 must be sized to at least the visual gap between
the two template strands at the unzipping point, or the blob will reach
full height without being wide enough to actually occlude the hydrogen
bond breaking beneath it.

---

## Front/back depth cue

`sin`/`cos` alone cannot distinguish a blob coming around the front from
one going around the back — both produce identical position/size at
mirrored angles. Resolved via z-ordering:

- `cos(θᵢ) > 0` → front half → draws **above** the DNA ribbon/template strands
- `cos(θᵢ) < 0` → back half → draws **below** the DNA ribbon/template strands

This single mechanic also resolves the "does the DNA visibly unwrap through
the ring" question raised earlier in design discussion — it turns out to be
the same z-ordering split, not a separate problem. A blob passing behind the
DNA reads as "going around the back" without any additional visual cue
needed (optional further reinforcement: slight modulate/alpha dim on the
back half, not yet deemed necessary).

**Reuse note**: this front/back z-order split (ring behind vs. ring in
front of the DNA layer) is intended to be reused for the other enzymes
(leading/lagging polymerase) when their own vector art passes happen.

---

## Blob shape — procedural, not imported

Decision: draw the subunit blob procedurally rather than importing SVG path
data. A honeycomb-style hexagon — squished/stretched per-frame using the
same `blob_width`/`blob_height` values already driving the barrel-roll — is
sufficient and has a nice side benefit: the real DnaB helicase ring actually
is a hexamer of six subunits, so a hexagonal blob shape is incidentally
more biologically apt than an arbitrary blob, not just a rendering
convenience.

Approach: `draw_polygon()` (or `draw_colored_polygon()`) with 6 vertices
computed via polar placement around the blob's own local center, scaled
independently by `blob_width` and `blob_height` per frame (i.e. an ellipse-
proportioned hexagon, not a regular one) — same technique already used for
the ring's own 6-blob placement, just one level down. Optionally rounded
corners via a slightly higher vertex count with corner-smoothing, deferred
until the plain-hexagon version is validated visually.

---

## ThemeManager — new export group (proposed)

A new "Helicase Ring" export group is anticipated to hold, at minimum:

- `max_blob_height`, `max_blob_width`, `min_width_ratio`
- `ring_radius`, `ring_center_y` (or derived from existing `center_y`)
- Color, label color, label font, label font size (per earlier discussion —
  exact fields still open, noted as unresolved in that discussion)

Still open / not yet decided: whether this replaces the current Helicase
export group (color/thickness/half_width/height_margin) outright, or
coexists alongside it during transition.

---

## Open items (not yet resolved)

- Exact hexagon vertex geometry (regular vs. rounded corners) — deferred
  until a plain version is validated visually
- Final field list for the ThemeManager "Helicase Ring" export group
- SVG-to-GDScript conversion tooling — explicitly deferred; not needed for
  the procedural-hexagon approach, but may resurface for other enzymes
  later if their shapes end up too complex to draw procedurally
- Whether other enzymes (leading/lagging polymerase) will follow this same
  procedural-hexagon-family approach or need distinct shape treatment
