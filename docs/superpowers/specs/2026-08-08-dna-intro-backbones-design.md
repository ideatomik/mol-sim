# DNA spiral intro: bring the backbone lines back

## Context

`scripts/dna_unwind_intro.gd` currently draws "bare rungs only" — per-slot
bead glyphs connected by hydrogen-bond bundles, no connecting backbone
curve, matching the p5.js reference sketch this animation was originally
built against. The real live rail view (`simulation.gd`) always has a
backbone: `backbone_line`/`top_strand_backbone_line`, a `Line2D` per
strand whose points are offset from each bead's own row by a per-slot
signed delta (`nucleotide_backbone_delta`/`top_strand_backbone_delta`)
that lerps toward `+backbone_offset_distance` or `-backbone_offset_distance`
depending on whether that slot is currently on the bonded or unzipped side
of the helicase fork (`_rebuild_rail()`/the per-slot loop in
`simulation.gd`'s `_process()`). That mechanism is state-driven (bonded vs.
unbonded), not rotation-driven, and doesn't translate directly to the
intro's twisted-pair phase — this spec defines the intro's own version.

Goal: reintroduce a backbone line per strand in the intro, consistent with
the file's existing "every real quantity is a real value, decorative
quantities are explicitly labeled and live-tuned" philosophy, and with the
existing rotation/occlusion model already established
(`_rotation_state()`, the `sin(phase)`-sign depth trick documented at the
top of the file).

## Design

### Geometry: the backbone point is a second point on the same rotating rod

For a given slot, the bead's own screen Y already comes from
`y_offset = rotation_radius*(cos(phase)-mean_cos)` (`y_top = center_y -
y_offset`, `y_bottom = center_y + y_offset`). The backbone point at that
same slot uses the *exact same* `phase` and `mean_cos` — it is not an
independently-driven wave — just a different (larger) radius:
`rotation_radius + backbone_offset_px`. Concretely:

```gdscript
backbone_offset = (rotation_radius + backbone_offset_px) * (cos(phase) - mean_cos)
backbone_y_top    = center_y - backbone_offset
backbone_y_bottom = center_y + backbone_offset
```

`backbone_offset_px` is a new `play()` parameter: `tm.backbone_offset_distance * zoom_x`,
computed in `player_ui.gd`'s `_play_dna_intro()` exactly like every other
real pixel value already passed in (`bead_diameter_px`, `bond_width_px`,
etc.) — no new decorative ratio constant, since this quantity already has
a real on-screen analog.

This reproduces the confirmed checkpoints: at a bead's own Y extreme
(phase 0°/180°), its backbone point is at its own extreme too, offset
further out (fully separated); at the bead's own midpoint (phase
90°/270°), the backbone point coincides with it exactly (offset is 0,
since both curves share the same zero-crossing). Wobble
(`_wobble_y(slot, _wobble_time)`) is added on top of the backbone Y
exactly like it already is for the bead — same index, same call, added
last, matching how the real strand layers wobble onto its own backbone
points.

### Z-order: reuse `top_is_front`, no new sign logic

A bead's own backbone point shares that bead's own front/back status —
never the opposite. Real backbone (sugar-phosphate) sits on the *outside*
of a double helix; bases sit on the *inside* and meet near the axis. Since
the backbone point is on a strictly larger radius than the bead at the
same phase (see Geometry above), it's always further along whichever
direction — toward or away from the viewer — the bead is currently
leaning: when the bead is the "front" one of its pair, its backbone is
*even more* forward, i.e. drawn in front of the bead; when the bead is
the "back" one, its backbone is *even more* recessed, i.e. drawn behind
it. Concretely:

- Top strand: in front when `top_is_front`, behind when `not top_is_front`.
- Bottom strand: in front when `not top_is_front`, behind when `top_is_front`.

No new trig or sign rule — this is the existing `sin(phase) > 0` flag,
reused, just applied with the same sign rather than flipped. Net visual
effect: right at a crossing (a bead's own vertical midpoint, where its
backbone offset passes through 0), the *front* bead's own backbone is
what's drawn last of the four primitives at that slot, momentarily
covering part of that bead — we never see a full bead exactly at the
midpoint between strands, since the backbone is the outermost thing at
that instant. (The 0°/180° boundary where `top_is_front` itself flips is
still where a bead's own backbone offset is *maximal*, i.e. `sin(phase) =
0` there, so that flip is still invisible — same "flip only happens where
it can't be seen" property the existing top/bottom bead-pair occlusion
relies on; it's the crossing at 90°/270° where the backbone-over-bead
effect is actually visible, not the 0°/180° flip point.)

### Segments and draw order (two-pass restructure)

The backbone is rendered as straight `draw_line` segments between
consecutive slots' backbone points — no `Line2D`, no `Curve2D`, matching
how the real strand's own backbone is just a polyline through per-slot
points, and matching this file's existing pure-`_draw()` style (bond
bundles are already `draw_line` calls, not nodes).

Adjacent slots differ in phase by a lot on average (the spiral spread is
roughly 50° per slot for a typical sequence), so a segment between slot
`i` and `i+1` will often span a front/behind boundary where the two
endpoints "want" opposite z-order. Resolved by **left-slot ownership**:
segment `i → i+1` uses slot `i`'s own front/behind flag — the same one
that already decides slot `i`'s own bead occlusion. Where the segment's
other end technically disagrees, the line crosses the boundary a beat
early/late; invisible at this line width, and consistent with this file's
existing tolerance for decorative-approximation seams elsewhere (e.g. the
mid-segment turn density is tuned by eye, not derived).

Because segment `i → i+1`'s far endpoint isn't known until slot `i+1` is
processed, `_draw()`'s per-slot loop is restructured into two passes:

1. **Pass 1** (pure computation, no drawing): for every slot, compute and
   store in parallel arrays — `x`, `y_top`, `y_bottom`, `top_is_front`,
   `backbone_y_top`, `backbone_y_bottom` — applying settle-lerp and wobble
   exactly as today's single-pass loop already does per slot.
2. **Pass 2** (drawing): for each slot, draw the bond bundle (unchanged),
   then compose the four remaining primitives (top bead, top backbone
   segment to `i+1`, bottom bead, bottom backbone segment to `i+1`).
   Whichever bead is the pair's "back" bead (per `top_is_front`) draws as
   `[backbone, bead]` — its backbone drawn before it, i.e. behind it, per
   the z-order rule above. Whichever bead is the pair's "front" bead draws
   as `[bead, backbone]` — its backbone drawn after it, i.e. in front of
   it. The two units compose in the existing back-then-front order:
   - `top_is_front` (back = bottom, front = top):
     `bottom_backbone, bottom_bead, top_bead, top_backbone`
   - `not top_is_front` (back = top, front = bottom):
     `top_backbone, top_bead, bottom_bead, bottom_backbone`

   The rightmost slot (`num_slots - 1`) has no outgoing segment (nothing
   to its right) — same as a `Line2D`'s last point.

### Settle-phase target

Once a slot's settle phase completes, its backbone offset must land
exactly where the live rail view's own backbone sits for an untouched,
fully-paired strand (helicase hasn't started yet at hand-off): a flat
line offset by `backbone_offset_px` to the *outward* side of the flat
bead row — above the top strand's row, below the bottom strand's row
(mirroring `on_bonded = true` in `simulation.gd`'s own backbone-delta
logic, since the whole strand is still bonded at this point in time).
This reuses the exact same per-slot `slot_t` the bead itself already uses
to glide home — the backbone rides the same cascade and arrives the same
instant, so the fully-settled frame matches the live view's backbone
lines exactly, consistent with this file's existing seamless-handoff
guarantee for bead position.

### Styling

New `play()` parameters, plumbed the same way every other real value
already is (computed once in `player_ui.gd`'s `_play_dna_intro()`):

- `backbone_offset_px` = `tm.backbone_offset_distance * zoom_x`
- `backbone_color` = `tm.template_backbone_color` (grey — matches what
  `backbone_line`/`top_strand_backbone_line` actually render for an
  unreplicated template strand; *not* `tm.backbone_color`, which is the
  synthesized-strand color and doesn't apply here — nothing has been
  synthesized yet)
- `backbone_width_px` = `tm.backbone_line_width * zoom_x`

### Out of scope

- No change to the bond-bundle geometry, bead styling, rotation speed/turn
  density, or settle stagger/lerp timing constants.
- No change to `simulation.gd`'s real backbone-offset mechanism
  (bonded/unbonded state-driven) — the intro's rotation-driven version is
  its own thing, only converging with the real one at the settle target.
- No masking-circle end caps or per-fragment backbone splitting (no
  Okazaki-style fragmentation exists in this animation).

## Testing

Visual only, as with every round on this file — no automated coverage
exists for this script and none is being added (pure `_draw()`-driven
animation). Run the app, load a sequence, and confirm:

1. Each strand shows a continuous backbone line through its beads during
   the rotation phase; at each 90°/270°-adjacent crossing (a bead's own
   vertical midpoint), the currently-front bead's own backbone briefly
   covers part of it, so no bead reads as a full, unoccluded circle right
   at the strands' crossing point.
2. No visible popping/tearing at segment boundaries where left-slot
   ownership disagrees with the segment's right endpoint.
3. The fully-settled frame's backbone lines match the live rail view's
   own `backbone_line`/`top_strand_backbone_line` position exactly (color,
   width, offset side).
4. Skip-via-click/keypress still works at any point.
