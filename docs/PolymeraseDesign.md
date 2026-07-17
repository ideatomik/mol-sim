# Polymerase Visual Design — v71 (implemented)
_Implemented in v71 as the procedural two-piece clamp (`polymerase_clamp.gd`).
Retained as the design rationale and as a reference pattern for future enzyme
visuals — the body below is the original pre-implementation discussion; see
**As-Built (v71)** immediately below for where the shipped version diverged.
Companion to DESIGN.md's "Procedural enzyme visuals" architecture section and to
HelicaseDesign.md, which established the step-driven-animation and z-order
patterns this reuses._

---

## As-Built (v71)

What actually shipped, and where it diverged from the design below. The design
body is kept intact as reference; this note is the source of truth for the
current implementation.

- **Procedural, not authored art.** Drawn procedurally with the shared
  rounded-corner octagon primitive (same building block as the helicase ring),
  not hand-authored in SVG. The SVG pipeline (`polymerase_shape.gd`,
  `svg_to_polymerase_gd.py`) is retired-in-place.
- **Two pieces, not one ellipse.** Instead of a single oval sized to
  `dna_ribbons_gap`, the clamp is a **back body** (behind the strand) plus a
  **jaw** (in front), both the same octagon, straddling the DNA in z so it reads
  as encircling the duplex. The back's DOWN height spans the full duplex plus a
  margin, centred on the midline; its outer edge is pinned and it grows inward
  with the pump, and the fixed-height jaw is dragged along the growing edge.
- **One step-driven pump, not separate pulse + open/close.** The "synthesis
  pulse" and the lagging "clamp open/close at fragment boundary" are both
  subsumed by a single `set_pump(t)` scalar. `replication_manager.gd` feeds it
  the already-shaped step value (`sin(step_t*PI)` leading, `sin(phase*PI)`
  lagging), so the motion is inherited from the helicase step timing and is
  scrub-safe for free (rest pose at `t = 0`). No distinct per-capture pulse or
  fragment-boundary widen-snap was needed as its own mechanic.
- **Capture anchor moved to the jaw's OUTER edge.** The nucleotide-capture halo
  and two-leg follow shipped roughly as designed, but the exposed anchor
  (`get_jaw_cap_inner_anchor()`, name kept for the `_capture_*` call sites) now
  returns the jaw's **outer** edge, computed formulaically from the current pose
  and read live via `to_global()` — so on the down-stroke it sweeps the captured
  nucleotide outward toward the outer strand, rather than an eyeballed inner point.
- **Per-strand theming via ThemeManager.** All geometry and colours live in the
  new **"Polymerase Clamp"** export group (leading = the mirrored clamp, lagging =
  the non-mirrored one), read live each frame.
- **Both remaining open items from this list have since shipped.** Text
  labels: see EnzymeLabelsDesign.md (a `_label`/`EnzymeLabel.tscn` child,
  ThemeManager-driven config matching this file's own existing pattern for
  everything else). One further divergence from EnzymeLabelsDesign.md's own
  original As-Built worth flagging here specifically, since it's this file's
  own component: the label key became tier-conditional once Pol I shipped —
  `"ENZYME_POL3"` ("Pol III") instead of `"ENZYME_POLYMERASE"` ("Polymerase")
  when `pol1_enabled`, read live in `_apply()` via `%ComplexityManager`
  rather than fixed once in `_build()` — see OkazakiMaturationDesign.md's
  Pol I Implementation Status. `_round_corners()` extraction: shipped as
  `procedural_shape_utils.gd` (`ProceduralShapeUtils`, static methods,
  `class_name` so no preload needed) once a fifth procedural enzyme
  (`pol1.gd`) made the duplication five copies deep — this file kept its own
  unique asymmetric `_octagon()` (genuinely never duplicated elsewhere) and
  only switched `_round_corners()` over.

---

## Context

Current placeholder: a plain circle ("synthesis circle"), per TODO_List.
Both leading and lagging polymerase currently use this same stand-in shape.

Biologically, DNA Pol III is a clamp-shaped enzyme encircling the DNA via
the sliding clamp (β-clamp) — structurally and functionally distinct from
the helicase (which unwinds; the polymerase clamps and synthesizes). The
same enzyme (Pol III) performs both leading and lagging synthesis in the
E. coli model MolSim follows.

---

## Shape

An ellipse/oval, matching the scene's established side-view convention (a
face-on ring, as with the helicase, would break the flat perspective). The
ellipse's vertical extent is sized to `dna_ribbons_gap` — the gap between
the two strands at that point — so it visually reads as clamped around the
duplex rather than floating beside it. This is very likely what the
existing TODO note ("spans full strand height") was already gesturing at.

**Leading and lagging polymerase share this same visual** (mirrored/
recolored per strand via ThemeManager, not two distinct shapes) — consistent
with both being Pol III in the underlying biology.

---

## Animation — driven by events, not an independent clock

Per this project's non-negotiable scrub-safety rule (any animation on an
independent clock risks desync on scrub), the clamp has **no free-running
idle pulse**. All motion is derived from existing step/event state:

### Synthesis pulse
Each time a nucleotide is captured and locks into its slot (see Nucleotide
Capture below), the clamp performs a small synchronized squeeze/pulse timed
to the same duration already driving that nucleotide's travel tween. No
nucleotide incoming → no pulse → stillness correctly reads as "not currently
synthesizing." One animation system doing double duty instead of a separate
ambient loop plus a capture animation competing for attention.

### Clamp open/close (lagging strand only)
At each Okazaki fragment boundary — the same moment `_lagging_fire_step()`
already treats as a distinct positional event (the "jump back" to a new
fragment's start) — the clamp visually opens (briefly widens/gaps on one
side) then snaps shut around the new position. Driven by that same
fragment-boundary event, not a separate timer.

**The leading strand never triggers this** — one clamp, one continuous
glide, no open/close, since the leading strand has no fragment-boundary
event to key off. This asymmetry is itself a quiet teaching moment
(continuous vs. discontinuous synthesis) visible without any label.

---

## Nucleotide capture mechanic

Reconstructs the spirit of an early prototype system (free nucleotides with
physics-driven Brownian motion, closest-compatible-match sent to the
polymerase) in a lighter-weight form suited to a cosmetic/functional split.

### Two separate particle systems
- **Environmental field** (existing/cosmetic): ambient free nucleotides
  drifting across the scene (fake Brownian — a small per-frame random
  offset, no real physics/colliders), dimmable via a low-info theme toggle.
  Purely decorative; untouched by the mechanic below.
- **Polymerase halo** (new, functional): a small, fixed-size pool (~4–6) of
  fuzzy, low-alpha, anonymous particles always orbiting close to the
  polymerase. Separate system from the environmental field. Never empties,
  never needs external restocking — see Recycling below.

### Capture sequence
1. When the polymerase needs its next base, the nearest halo particle is
   selected.
2. It resolves into the specific required nucleotide type.
3. It animates forward (z-index rises above the polymerase) and travels
   (lerp/tween) to the clamp, arriving in sync with the polymerase's own
   step timing — same relationship as the helicase blob syncing to
   `get_eased_step_t()`, so the capture visibly completes exactly as the
   polymerase reaches that slot.
4. On arrival it locks into its slot, becoming the synthesized-strand base,
   and triggers the clamp's synthesis pulse (above).

### Recycling (solves repopulation with no new bookkeeping)
Once placed, the same particle object is **recycled**, not destroyed: z
lowered back behind the polymerase, repositioned into the halo, reactivated
as an anonymous fuzzy member again — ready to become whichever base type is
needed next. Nothing is ever instantiated or freed during play; the halo is
a fixed, self-sustaining object pool for the lifetime of a run. This avoids
both failure modes considered and rejected during design (radius-search
misses if the halo were sparse; field depletion if capture pulled directly
from the environmental layer).

---

## Z-layering (back to front)

```
DNA ribbon
→ idle halo particles (anonymous, low-alpha)
→ polymerase clamp
→ the one currently-resolving/traveling particle (arriving "in front")
```

---

## Open items (not yet resolved)

- Exact halo particle count (proposed default 4–6; not yet visually tested)
- Whether the halo's radius/orbit pattern needs its own tuning pass once a
  shape exists to test against
- ThemeManager export group shape for the polymerase (color, clamp
  dimensions, pulse amplitude, halo particle styling) — not yet itemized,
  same open-ended status HelicaseDesign.md left its own export group in
- Exact open/close animation timing/easing for the lagging clamp — not
  designed in detail, only the trigger condition (fragment boundary) is
  pinned down
- How the halo visually reads at very fast speed multipliers / during
  finishing-phase acceleration — not yet discussed
