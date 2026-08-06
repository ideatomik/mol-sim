# Fork-flip hover disclaimer — design

**Status:** approved 2026-08-04. Completes the "Self-paired fork-flip as a
deliberate, labeled 2D mirror" entry in `docs/MolecularStructureDesign.md`
(recorded 2026-08-04, "design intent, not yet built"), which requires an
on-screen disclaimer while (and only while) a residue is in the mirrored
state, and left two things undecided: the disclaimer's trigger/visual
treatment, and whether this round of work includes the animated-turn
alternative to today's instant flip.

**Decisions made in this spec:**
- Trigger/visual treatment: hover-only tooltip (not a persistent HUD banner,
  not click-to-pin).
- Animated turn: explicitly out of scope for this round. The instant flip
  (already implemented, uncommitted, in `_rebuild_layout()`'s
  `self_paired_sign < 0` branch and its `molecule_geometry_diagnostics.gd`
  mirror) ships as-is. Animation is a separate, independently-schedulable
  follow-up with its own open questions (duration, easing, interruptibility)
  — not designed here.

## Problem

`RiboseDeriver.reflect_about_backbone_axis()` and its two call sites
(`molecule_structure_renderer.gd`'s `_rebuild_layout()`,
`molecule_geometry_diagnostics.gd`'s `_derive_full_residue()`) already
implement the fork-flip mirror, uncommitted in this worktree. The mirror's
own doc comment states callers "MUST pair this with the on-screen didactic
disclaimer the design doc requires — this function does not and cannot
enforce that itself." No disclaimer exists yet. This spec designs it.

## Architecture

No new nodes, no Control-based tooltip UI. `molecule_structure_renderer.gd`
already draws everything — atoms, bonds, atom labels — via `_draw()` with
`draw_string()` against a themed font (see the existing atom-label code,
`molecule_structure_renderer.gd:925-939`). The disclaimer follows the same
convention: a drawn string, gated on a per-frame hover check, no picking
framework, no Area2D nodes.

## Components

1. **`RiboseDeriver.reflect_about_backbone_axis()`** — already implemented.
   Unchanged by this spec.

2. **`molecule_structure_renderer.gd`:**
   - New member `_mirrored_residue_layout: Array[Dictionary]`. Cleared and
     repopulated in `_rebuild_layout()` at the exact call site of the
     `self_paired_sign < 0` branch (currently `molecule_structure_renderer.
     gd:534`) — registration happens inline with the mirror transform
     itself, not as a separate opt-in step, so a residue cannot be mirrored
     without becoming hoverable. Each entry: `{world_pos: Vector2, radius:
     float, key: String}`.
     - `world_pos` is the residue's existing anchor (the same `world_pos`
       already computed for that residue in the loop — anchored at C1',
       per the Bug-C fix comment at `molecule_structure_renderer.gd:559`).
       The mirror only transforms positions relative to this anchor, so the
       anchor itself needs no new computation.
     - `radius` is the max distance from `c1_local` across every atom this
       residue places into `local_positions` (ring + substituents + base),
       computed in the same loop that already iterates `topology.atoms` to
       build `_atom_layout` (`molecule_structure_renderer.gd:581-591`) — no
       extra pass. Padded by `tm.molecular_atom_radius` so the atom's own
       drawn radius counts as part of the hoverable footprint.
     - `key` is the same `"%s:%d" % [entry.strand, entry.slot]` convention
       used elsewhere in this file (e.g. `self_paired_cache_key`).
   - New member `_hovered_mirrored_key: String`, recomputed once per frame
     in `_process()` (after `_rebuild_layout()`, before `queue_redraw()`):
     `get_global_mouse_position()` compared against every entry in
     `_mirrored_residue_layout`; nearest anchor whose distance is within its
     `radius` wins. Empty string when nothing qualifies or the array is
     empty.
   - `_draw()` gains, gated on `_hovered_mirrored_key != ""`: a small
     semi-transparent background rect sized to the disclaimer text's
     measured extent (`Font.get_string_size()`, same pattern as the
     atom-label sizing at `molecule_structure_renderer.gd:935`), positioned
     near the hovered residue's `world_pos`, then `draw_string()` of the
     disclaimer text on top, using `tm.base_label_font` /
     `ThemeDB.fallback_font` and `tm.base_label_color` — same font/color
     source the rest of this file already uses, no new theme fields.

3. **`molecule_geometry_diagnostics.gd`** — no changes beyond what's already
   uncommitted (the mirror-sync branch that keeps the F9 dump matching live
   geometry). A text dump has no hover state; the disclaimer is a rendering
   concern only.

## Disclaimer text

Verbatim, from `docs/MolecularStructureDesign.md`'s already-recorded
framing:

> in 2D molecular representations this rotation doesn't really exist, but
> for didactic reasons, we're showing you this way.

## Data flow

Per frame while `_active` (skeletal zoom tier):
`_rebuild_layout()` → mirror branch fires for `direction_sign < 0`
self-paired residues → same branch appends to `_mirrored_residue_layout` →
`_process()` computes `_hovered_mirrored_key` against the mouse →
`queue_redraw()` → `_draw()` reads `_hovered_mirrored_key` and draws the
tooltip if set.

## Edge cases

- **Zoom tier:** `_rebuild_layout()` already early-returns without touching
  any layout arrays when `not _active` (`molecule_structure_renderer.gd:
  375-376`). `_mirrored_residue_layout` inherits this for free — no extra
  gating needed; it's simply empty while inactive, so nothing is ever
  hoverable at bead-glyph zoom.
- **Overlapping residues:** nearest-anchor-within-radius wins. No stacking,
  no multi-tooltip case — self-paired residues are spaced at real
  base-pair distance, never close enough for this to be ambiguous in
  practice, but the tie-break is defined regardless.
- **No residues currently mirrored:** `_mirrored_residue_layout` is empty,
  `_hovered_mirrored_key` stays `""`, `_draw()`'s tooltip branch never
  fires. Zero cost beyond the array being empty.

## Testing

No Python harness — this is interaction/rendering, not geometry math (the
project's `diagnosis/*.py` convention is for the latter only, per the
parent plan's Global Constraints). Verified live in the test chamber
(`scenes/test_chamber.tscn`, this worktree):
1. Hover over a `direction_sign < 0` self-paired residue (`template_bottom`
   in a self-paired region) — tooltip appears with the exact text above.
2. Move the mouse away — tooltip disappears.
3. Hover a non-mirrored residue (leading/lagging, or `template_top`) —
   no tooltip.
4. F9 dump still matches live geometry (already true via the existing
   uncommitted diagnostics mirror branch — confirm it hasn't regressed).
