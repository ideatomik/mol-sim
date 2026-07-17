# Vertical Mode — Design (pre-implementation)
_Design discussion, not yet implemented. Companion to ZoomDesign.md (whose
frame-provider contract this extends), LongSequenceDesign.md (whose windowed
level-1 math this re-axes), and EnzymeLabelsDesign.md (whose `set_mirror()`
composition this reuses). Motivated by a product need, not the roadmap: the
Instagram vertical teaser generated interest but viewers reported not
understanding what they were looking at. Vertical mode exists so the
simulation reads natively in a 1080×1920 frame instead of being a letterboxed
crop of a landscape scene._

---

## Status

### Shipped and QCA-confirmed

- **Step 5 — ThemeManager cross-axis rename (§1b).** Done first, out of order.
  Verified a pure rename: with comments stripped and identifiers normalised,
  both files were byte-identical to their originals.

| Old | New |
|---|---|
| `zoom_strand_width_percentage` | `zoom_along_axis_percentage` |
| `zoom_height_fit_percentage` | `zoom_cross_axis_fit_percentage` |
| `zoom_vertical_content_span` | `zoom_cross_axis_content_span` |
| `_compute_height_fit()` | `_compute_cross_axis_fit()` |
| `viewport_width` (2 params + 1 local) | `along_extent` |
| `NEW_STRAND_LEVEL{2,3}_VERTICAL_FIT` | `..._CROSS_AXIS_FIT` |

  Rule applied: **rename what names a SCREEN axis; leave what names a WORLD
  span.** `footprint_height` is world-y and stayed.

- **Step 1 — `vertical_mode` + the axis mapping.** `zoom_manager.gd` gained
  `vertical_mode`, `_apply_orientation()` (clears `ignore_rotation`
  unconditionally), `get_along_extent()` / `get_cross_extent()` **as public
  API**, `_screen_to_world_offset()`, and `_pan_action_negative/positive()`.
  All eight viewport-reading fit sites across `zoom_manager.gd`,
  `simulation.gd` and `replication_manager.gd` now route through the extent
  helpers. Confirmed working in-engine.

- **Step 2 — glyph counter-rotation.** `nitrogen_base.gd` `pivot_offset` fix
  + `set_label_rotation()`; `get_label_counter_rotation()` on
  `zoom_manager.gd`; pushed at all six spawn sites.
  Also `polymerase_halo.gd` and `nucleotide_field.gd` (both `draw_string`).

- **Step 3 — enzyme labels.** `EnzymeLabel.set_counter_rotation()`, wired into
  `helicase_ring.gd`, `polymerase_clamp.gd`, `primase_blip.gd`.

- **Step 4 — `scrub_drag_delta` widened to `Vector2`.** Confirmed working in
  BOTH orientations. The enzyme side was four changed lines each with zero net
  new; the purification held (checked with comments stripped, neither enzyme
  holds a real `vertical_mode` reference, and `helicase_ring.gd` still has zero
  external references of any kind). Both clamps already funnelled through
  `_request_clamp_drag_scrub()`, so there were only TWO decision points, not
  three — each one line, inserted where `zoom_mgr` was already in hand.

**Vertical mode is now behaviourally complete.** Framing, free camera,
arrow-key pan, glyphs, and all three enzyme drag-scrub targets work in both
orientations. Everything still outstanding is cosmetic or is the UI.

### Corrections to this document, found by reading the real files

1. **`_fit_points()` is dead code.** Every registered target returns a
   `Dictionary`; nothing returns an `Array`. §1a's claim that bounding-box
   targets "survive free" described a path with no callers. Kept axis-correct
   anyway so it isn't a trap for the next provider.
2. **Eight viewport reads across three files, not five in one.**
   `_polymerase_footprint_frame()` is a cross-axis-only fit serving leading
   L3, lagging L2/L3 and leading L2's fallback — the polymerase targets were
   never bounding-box targets either.
3. **The mirror sign belongs in `EnzymeLabel`, not the callers** (§2b had it
   backwards). `EnzymeLabel` already owns `_mirror`, so `_apply_rotation()`
   owns the negation and all five call sites pass the value verbatim.
4. **`nucleotide_field.gd` needs the OPPOSITE fix from `polymerase_halo.gd`.**
   The halo has a real `Node2D` per particle, so it rotates about
   `Vector2.ZERO`. The field draws every particle in ONE `_draw()` on a single
   node, so it must pass each particle's own centre `c` as the transform
   origin — and must reset the transform afterward, since the loop continues
   and the next body uses absolute `c`.
5. **`_anchor_centered_frame()` is byte-identical in `simulation.gd` and
   `replication_manager.gd`** — another `_round_corners()`. Untouched.

### Outstanding

- **Steps 6–7 — PlayerUI.** The unique-name refactor, then
  `VerticalPlayerUI.tscn`. **The only remaining item in this document.**

### Resolved since the last pass (not originally scoped in this doc)

- **`ligase.gd` / `pol1.gd` labels** — wired, same one-line shape as
  `primase_blip.gd`. All five `EnzymeLabel` owners now counter-rotate.
- **PINNED polymerase label issue** — resolved on the user's side (label box
  wasn't resizing to its text) before it reached diagnosis here. Closed.
- **Topology-conditional polymerase labels** (Pol epsilon/delta) + the
  "Cell Type" popup rename — a parallel thread this doc didn't originally
  scope, now shipped: `_mirror` → `_is_leading` rename in
  `polymerase_clamp.gd`, `_polymerase_label_key()`, two new CSV rows in
  `enzyme_labels.csv`, and three rows renamed in `ui_strings.csv`
  (`UI_TOPOLOGY_MODE_LABEL` → "Cell Type"; options → "Prokaryotic
  (circular)" / "Eukaryotic (linear)"). See
  `EnzymeLabelsDesign_TopologyAddendum.md` for the full design record —
  that work has its own document and isn't duplicated here, but is noted
  since it shared several of this pass's files (`enzyme_label.gd`,
  `polymerase_clamp.gd`) and landed in the same session.
- Three items now queued for one native-speaker review pass rather than
  three separate ones: the `_FULL` key word-order inconsistency, the
  "Pol épsilon" accent, and "Tipo de Célula"'s option text.

### Verification debt

The claim "that closes the glyph inventory" was made by globbing
`/mnt/user-data/uploads/*.gd`, which only ever contained the files uploaded so
far — `nucleotide_field.gd` was not among them and had a `draw_string`. Before
calling the glyph pass done, grep **the real project directory** for
`draw_string` and `EnzymeLabel`.

---

## The approach, and why it's the right one

Rotate the **camera**, not the simulation.

Every world-space quantity in this project — `center_y`, `helicase_x`,
`nucleotide_original_x[i]`, `track_length`, slot positions, every
frame-provider's return value — stays exactly as it is. The track still runs
along world **+x**. Only the view transform changes.

Rotating a simulation root node instead would look equivalent and isn't: it
would drag `Camera2D.global_position` into rotated space, so every fit
formula that currently computes a world position (`Vector2(track_length /
2.0, mid_y)`) would need to be transformed on the way out. Camera rotation
keeps that boundary clean — world math stays world math, and exactly one
layer knows about orientation.

**This introduces no new scrub-safety surface.** `vertical_mode` is set once
at load and never animated (see "Lifecycle" below), so the camera's rotation
is a constant, not a tween. Nothing in `scrub_snap()` /
`_transition_to_level()` / `_apply_live_frame()` gains a new timing
dependency. This is the one significant thing the design gets for free, and
it's the reason this pass is small.

### Direction and sign

Confirmed: the fork runs **top→bottom** — "unzipping" reads more naturally
downward, and it matches how vertical video is consumed.

World **+x** must appear as screen **+y** (down). That is a +90° apparent
rotation of world content. Content at world rotation ψ appears on screen at
ψ − φ where φ is the camera's rotation, so:

```
camera.rotation_degrees = -90    # vertical mode
camera.rotation_degrees = 0      # horizontal (today, unchanged)
```

Glyph counter-rotation then targets a world rotation of **φ** (= −90°) to
cancel back to upright on screen.

> **The derivation is sound but the sign is a first-run check, not something
> to defend on paper.** If everything renders upside down, both constants flip
> together — there is no configuration where one is right and the other wrong.

### `Camera2D.ignore_rotation` defaults to `true` in Godot 4

Set it `false` in `zoom_manager.gd`'s `_ready()` or `rotation` silently does
nothing. This belongs on the project's silent-failure trap list alongside CSV
registration and `unique_name_in_owner` — same signature: no crash, no error,
the feature just isn't there.

---

## Ownership: where `vertical_mode` lives

`zoom_manager.gd` owns it, as an `@export`. **Explicit toggle, not
aspect-derived** — confirmed; predictability during recording beats
elegance.

It is *not* a ThemeManager value. ThemeManager holds tunable visual
constants; this is a layout mode that changes behavior, and one of its two
consumers (`nitrogen_base.gd`) is contractually forbidden from reading
ThemeManager at all (SKILL.md hard rule). Making it a ThemeManager export
would create a reader that can't read it.

Consumers query `zoom_mgr.vertical_mode` (`player_ui.gd`, `simulation.gd`) or
are **pushed** the derived value (`nitrogen_base.gd`, `EnzymeLabel`).

---

## Part 1 — `zoom_manager.gd`

### 1a. The axis swap is five viewport-extent reads

The insight that makes this cheap: **the rotation is exactly 90°, so
world-axis-aligned bounding boxes stay axis-aligned in camera space.** No
point transformation is needed anywhere. Only the *correspondence* between
world axis and viewport dimension swaps.

Two helpers:

```gdscript
## The viewport extent the track runs ALONG (world x).
func _along_extent() -> float:
	var vp := get_viewport_rect().size
	return vp.y if vertical_mode else vp.x

## The viewport extent ACROSS the track (world y — strand thickness,
## replisome height).
func _cross_extent() -> float:
	var vp := get_viewport_rect().size
	return vp.x if vertical_mode else vp.y
```

Five reads route through them:

| Site | Today | Becomes |
|---|---|---|
| `_compute_strand_fit()` | `get_viewport_rect().size.x` → `_compute_track_fit_zoom` | `_along_extent()` |
| `_compute_reference_zoom()` | receives `viewport_width` | receives `_along_extent()` |
| `_compute_free_camera_min_zoom()` | `get_viewport_rect().size.x` | `_along_extent()` |
| `_compute_height_fit()` | `viewport_size.y * tm.zoom_height_fit_percentage` | `_cross_extent() * ...` |
| `_fit_points()` | `min(vp.x / size.x, vp.y / size.y)` | see below |

`_fit_points()` is the only one that isn't a substitution:

```gdscript
var target_zoom: float
if vertical_mode:
	target_zoom = minf(_along_extent() / size.x, _cross_extent() / size.y)
else:
	target_zoom = minf(viewport_size.x / size.x, viewport_size.y / size.y)
```

which collapses, since the helpers already encode the branch, to a single
un-branched line:

```gdscript
var target_zoom := minf(_along_extent() / size.x, _cross_extent() / size.y)
```

`size.x` is always the world-x span and `size.y` always the world-y span —
the helpers supply whichever viewport dimension each currently maps to. The
horizontal path is bit-identical to today's.

(`minf()` not `min()`, per the project's own typed-inference rule. The
existing line uses `min()` on an untyped var, which is fine as written;
the replacement is typed.)

### 1b. The naming rot is real, and it reaches ThemeManager

`_compute_height_fit()`, `tm.zoom_height_fit_percentage`, and
`tm.zoom_vertical_content_span` all mean **cross-axis**, which in vertical
mode is horizontal. `tm.zoom_strand_width_percentage` means **along-axis**.
Once vertical_mode exists these names are actively misleading, in exactly the
way that produces a wrong fix six months from now.

Proposed rename:

| Today | Proposed |
|---|---|
| `_compute_height_fit()` | `_compute_cross_axis_fit()` |
| `tm.zoom_height_fit_percentage` | `tm.zoom_cross_axis_fit_percentage` |
| `tm.zoom_vertical_content_span` | `tm.zoom_cross_axis_content_span` |
| `tm.zoom_strand_width_percentage` | `tm.zoom_along_axis_percentage` |

**Cost**: renaming an `@export` loses its saved value in the `.tscn`. Here
that cost is near zero — `zoom_vertical_content_span` and
`zoom_height_fit_percentage` are both flagged NOT YET TUNED (placeholder
values) in `_compute_height_fit()`'s own doc comment, so there is nothing
to lose. Only `zoom_strand_width_percentage` holds a real tuned value
(0.90-ish) and would need re-entering once.

This is the only part of the design that reaches outside the four files
under discussion. It is also the only part that is optional — the code works
unrenamed, it just lies. **Recommend doing it, in this pass, while the reason
is fresh.**

### 1c. Arrow-key pan needs an input swap, not a vector rotation

`pan_offset_x` is applied as `Vector2(pan_offset_x, 0.0)` in world space, in
four places (`_apply_live_frame`, `_frame_strand`, `scrub_snap`, and the
`_process` accumulation). World x is **along the track**, and it stays along
the track in vertical mode.

**So `pan_offset_x` is already correct and needs no change.** Only the input
binding moves:

```gdscript
# _process()
var pan_neg := "ui_up" if vertical_mode else "ui_left"
var pan_pos := "ui_down" if vertical_mode else "ui_right"
```

with the same pair swapped in `_input()`, which consumes those actions
specifically to stop the Scrubber `HSlider` from ever seeing them.

Note the pleasing lockstep: an `HSlider` responds to `ui_left`/`ui_right` and
a `VSlider` to `ui_up`/`ui_down`. If the vertical layout uses a `VSlider`
(see Part 3), the same swap protects it, for the same reason, with no extra
logic. If it keeps an `HSlider`, the swap is still correct — arrow keys pan
along the track and the slider never sees them either way.

### 1d. Free camera is genuinely broken in vertical, and needs real rotation

This is the one place a 90°-swap doesn't suffice, because these are the only
paths that convert **screen** deltas into **world** deltas:

- `_unhandled_input()` drag: `_free_camera_position -= delta_screen / _free_camera_zoom`
- `_free_camera_scroll_zoom()`: `world_before/world_after = _free_camera_position + (mouse_screen - viewport_size * 0.5) / zoom`

Both are identity mappings today. Unrotated in vertical mode, dragging right
pans the camera along world x — which appears as the canvas sliding
*vertically* while the mouse moves horizontally. Cursor-anchored scroll-zoom
would anchor to the wrong world point and drift sideways. Both are
immediately, obviously wrong on first use.

One helper, three call sites:

```gdscript
## Screen-space pixel offset -> world-space offset, accounting for both the
## current zoom and (in vertical mode) the camera's own rotation. The ONLY
## screen->world conversion in this file; everything else is world-native.
func _screen_to_world_offset(screen_delta: Vector2, zoom_value: float) -> Vector2:
	if zoom_value <= 0.0:
		return Vector2.ZERO
	return (screen_delta / zoom_value).rotated(rotation)
```

`rotation` is 0.0 in horizontal mode, so `.rotated(0.0)` is identity and the
existing behavior is preserved exactly — no branch needed.

### 1e. Untouched

`reset_zoom_instant()`, `_transition_to_level()`, `scrub_snap()`,
`_recenter_free_camera()`, `_compute_strand_fit()`'s returned *position*,
target registration, the visibility guards, and the highlight query API all
operate in world space or on level state. No changes.

---

## Part 2 — Counter-rotating the glyphs

Everything that isn't text rotates correctly for free: enzyme silhouettes,
the helicase barrel-roll (still a barrel roll, now vertical), bond marks
(perpendicular to the strand, stays perpendicular), backbones, the halo
particles (a rounded square rotated 90° is the same rounded square, so the
RNA/DNA shape distinction survives intact), and the front/back z-swap (draw
order, not orientation).

Text does not. There are two families.

### 2a. `nitrogen_base.gd` — the good case, with one trap

**Good news first**: the base glyph is a real `Label` **node** child (`var
label: Label`, created in `_ready()`), not `draw_string()` inside `_draw()`.
So counter-rotation is a property assignment, not a rendering rewrite. This
is what makes this a small pass rather than a medium one.

**Confirmed**: `base_type`'s own doc comment reads `"A", "T"/"U", "C", or "G"
(or "5'" / "3'" for markers)`. The polarity markers **are this node**. One
fix covers all four bases, the RNA `U`, and every 5'/3' marker in the scene —
including the per-fragment Okazaki markers.

**The trap**: `_center_label()` does

```gdscript
label.position = -label.size / 2.0
```

and never touches `pivot_offset`, which therefore stays at its default
`(0, 0)` — the label's **top-left corner**. Setting `label.rotation` would
pivot about that corner, swinging each glyph off-center by roughly half its
own diagonal. On 300 bases that reads as "the letters all fell over and
scattered," which is a much more alarming symptom than its one-line cause.

```gdscript
func _center_label():
	if label:
		label.pivot_offset = label.size / 2.0   # NEW — rotate about the glyph's
		                                        # own center, not its corner
		label.position = -label.size / 2.0
		label.rotation = _label_rotation
```

`EnzymeLabel` already got this right (`pivot_offset = size * 0.5`, per
EnzymeLabelsDesign.md's As-Built); `nitrogen_base.gd` never needed it because
nothing had ever rotated it.

**Injection, not lookup.** SKILL.md hard rule: `nitrogen_base.gd` is
ThemeManager-free; colors and fonts are injected externally. The rotation
follows the identical convention:

```gdscript
var _label_rotation: float = 0.0

## Counter-rotation for the base's own glyph, cancelling the camera's
## rotation in vertical mode so letters stay upright. Injected by the
## spawner (simulation.gd) exactly like set_colors()/set_font()/set_radius(),
## per the ThemeManager-free contract in this file's header.
func set_label_rotation(radians: float) -> void:
	_label_rotation = radians
	_center_label.call_deferred()
```

Called by the spawner in the established order (`add_child()` → `set_colors()`
→ `set_font()` → `set_label_rotation()`).

**Both prior concerns are now closed against `simulation.gd`:**

1. **Nothing ever unfreezes a base.** `stay_frozen` is never set `false`
   anywhere, and `freeze` is never touched outside `nitrogen_base.gd`'s own
   `_ready()`. The bodies are always frozen, so `label.rotation = φ` *is* the
   world rotation. No guard needed. (`Control` exposes no `global_rotation`
   setter, so this mattered.)
2. **`set_base_type()` always precedes `set_font()`** — at all three spawn
   sites, in the identical order `set_base_type()` → `set_radius()` →
   `set_colors()` → `set_font()`. `set_font()`'s deferred `_center_label()`
   therefore always lands after the text is final, so `size` is correct when
   `pivot_offset` is computed from it. This is a consistent convention across
   every site, not luck.

**Also confirmed safe: wobble.** `wobble_y` is applied as
`nucleotide_bases[i].position.y` / `Vector2(0, wobble_y)` — pure translation
along world y, no rotation. World y is the **cross-axis**, i.e. perpendicular
to the strand in *both* orientations. So thermal jitter stays perpendicular to
the backbone on screen and needs no change. Same for the bond marks'
`mark.rotation = segment.angle()`: geometric, world-space, rotates correctly
with everything else.

### The spawn sites

`simulation.gd` has exactly **three**, all sharing that identical four-call
shape — the two base spawners (bottom template, top strand) and
`_spawn_marker()`, which is a single function that all four template 5'/3'
markers already route through:

```gdscript
base.set_font(%ThemeManager.base_label_font_size, %ThemeManager.base_label_font)
base.set_label_rotation(zoom_mgr.get_label_counter_rotation())   # NEW
```

**`replication_manager.gd` has more** — the leading/lagging base spawners, the
RNA primer bases via primase, and the per-fragment Okazaki 5'/3' markers. That
file hasn't been uploaded, so the total isn't enumerable yet. It's one line
per site either way.

This is the price of the ThemeManager-free contract: the value must be pushed,
so it costs one line wherever a base is born. Acceptable, because a missed
spawn site produces **a visibly sideways glyph family** — the Okazaki markers
all lying on their side while every base is upright — not a subtle bug. Same
self-diagnosing property as the mirror sign.

### 2b. `EnzymeLabel` — the mirror inverts the sign

`set_counter_rotation(radians)`, the natural sibling to the existing
`set_mirror(bool)`. Both compose around `pivot_offset`, which is already
maintained at `size * 0.5`, so the anchor point never moves — the same
property that made `set_mirror()` work without special-casing.

**The sign flips under mirror.** The leading clamp is `scale.y = -1` on the
whole node, and the label already carries its own `scale.y = -1` to cancel
it. Reflection conjugates rotation: for a reflection S, `S · R(θ) · S = R(−θ)`.
So a local θ under the mirrored clamp renders at world −θ.

```gdscript
label.set_counter_rotation(-camera_rotation if _mirror else camera_rotation)
```

Concretely at φ = −90°: **+90° local** under the leading clamp, **−90° local**
everywhere else (lagging clamp, helicase ring, ligase, primase, Pol I).

If this sign is wrong, the symptom is specific and diagnostic: every enzyme
label upright *except* the leading polymerase's, which reads upside down.

**Anchor positions need no change.** Labels sit perpendicular to the strand
(local ±y); rotated, that puts them beside the strands rather than
above/below — which is where the screen room now is. The geometry is correct
by construction.

**But every `*_label_margin` will need retuning**, because the cross-axis
budget inverts: labels that had ~1920px of room now have ~1080px, and that's
precisely the axis they stick out along. And that retune happens in **two
places**, because `helicase_ring.gd` keeps its label params as local
`@export`s while `polymerase_clamp.gd` reads ThemeManager (a deliberate split
per EnzymeLabelsDesign.md's As-Built — each file follows its own existing
convention). That split cost nothing when there was one axis. It now costs
one extra Inspector location per tuning pass.

**Open**: should margins be per-orientation (`*_label_margin_vertical`), or
should vertical mode simply be tuned to whatever margins the horizontal mode
already uses? Defer until it's visible in-engine — this is a "look at real
numbers" question, not a paper one.

### 2c. The wiring

`camera_rotation` is pushed, not polled: `zoom_manager.gd` exposes
`get_label_counter_rotation() -> float` (returns `rotation`, i.e. −90° or 0),
and `simulation.gd` / `replication_manager.gd` push it to the nodes they own
at spawn time — same direction every other injected value already flows. No
enzyme script reaches into the camera, and the camera writes nothing it
doesn't own (its existing banner contract).

---

## Part 3 — `PlayerUI`

### 3a. The finding that changes the plan

**`PlayerUI.tscn` has zero `unique_name_in_owner` flags.** All 24 node
references in `player_ui.gd` are hardcoded deep paths:

```gdscript
@onready var play_pause_button: Button = $Panel/MarginContainer/VBoxContainer/HBoxContainer/TransportButtons/PlayPauseButton
```

A vertical layout is a *different container structure* by definition. Every
one of those 24 paths breaks.

So "one script, two scenes" — still the right target — has a **prerequisite
refactor**: convert all 24 `@onready` paths to `%Name`, and tick "Access as
Unique Name" on 24 nodes in the existing, working, shipped scene.

**This is the safe kind of 24-node change.** A missed unique name makes a
typed `@onready` resolve to null and fail **loudly, at startup, immediately**
— the opposite of the `LocaleManager` trap, which failed silently and cost
real debugging time. There is no version of this that ships broken and
undiscovered. It still wants a QCA pass on the horizontal UI, because it
touches working code for no user-visible benefit.

The alternative — a second `vertical_player_ui.gd` — is the "layer the new
system beside the old" trap in fresh paint, and this project already has a
recorded decision (the trombone loop removal) that says don't.

### 3b. Dropping `SequenceLabel` isn't only a null guard

Confirmed: no `SequenceLabel` in vertical mode. Guard surface is small — four
signal connects, four handler bodies, one sizing block. `get_node_or_null()`
plus early returns.

But there's a real coupling underneath:

```gdscript
var label_width = sequence_label.get_content_width()
scrubber.custom_minimum_size.x = max(label_width, 100)
```

**The scrubber is deliberately sized to match the sequence text's content
width** — that's what makes a scrub position align with the glyph under it.
That's not incidental; it's the whole reason both live in the same inner
`VBoxContainer`. Drop `SequenceLabel` and the scrubber silently falls back to
container-driven width. Probably fine, but that would be a rule arrived at by
omission. **The vertical layout should state its own scrubber sizing rule
deliberately** — most likely just `size_flags_horizontal = EXPAND_FILL` and
be done.

Vertical mode also loses one of three scrub affordances. Slider and
enzyme-drag both survive, so it isn't left without one — noting the count,
not objecting.

### 3c. `HSlider` → `Slider` opens the door for free

`@onready var scrubber: HSlider` is the only thing forcing the vertical
layout to keep a horizontal scrubber. Everything `player_ui.gd` actually does
with it — `min_value`, `max_value`, `step`, `value`, `set_value_no_signal()`,
`value_changed` — is defined on `Range`, which both `HSlider` and `VSlider`
inherit through `Slider`.

Retype the var to `Slider`. One line, and the vertical scene is free to use a
`VSlider` (with a scrub axis that matches the strand's on-screen direction —
which is arguably the whole point) or keep an `HSlider`. The decision moves
to the `.tscn` where it belongs.

The one orientation-specific line, `custom_minimum_size.x`, lives in the
`SequenceLabel` block that's already being guarded. **The `SequenceLabel`
drop and the `VSlider` option are the same fix.**

---

## Part 4 — Enzyme drag-to-scrub

Resolved against `helicase_ring.gd` and `polymerase_clamp.gd`. Both files
carry an identical drag block, so everything below applies twice.

### 4a. The hit-tests are already orientation-safe — no change

```gdscript
if not _dragging and _point_in_click_region(get_global_mouse_position()):
...
func _point_in_click_region(global_point: Vector2) -> bool:
	var local_point = to_local(global_point)
	return abs(local_point.x) <= _click_half_width and abs(local_point.y) <= _click_half_height
```

`CanvasItem.get_global_mouse_position()` applies the inverse canvas
transform — which includes the camera's rotation — so it returns a **world**
point, and `to_local()` takes it the rest of the way into the node's own
frame. Both are rotation-agnostic by construction. The clamp's cached
`_click_half_width`/`_click_half_height` come from `_apply()`'s own local-space
geometry and are equally unaffected.

Nothing here changes. Worth recording *why*: the hit-test is expressed in
world/local space rather than screen space, which is what makes it fall out
for free.

### 4b. `event.position.x` is the entire problem

```gdscript
var _drag_start_screen_x: float = 0.0
...
_drag_start_screen_x = event.position.x
...
scrub_drag_delta.emit(event.position.x - _drag_start_screen_x)
```

`event.position` is the raw **viewport** position — the one genuinely
screen-space quantity in either file. In vertical mode the along-track screen
axis is y, so this reads the wrong component.

**The sign needs no negation.** Horizontal: drag right (+screen x) → world +x
→ forward. Vertical: world +x appears as screen +y, and screen +y is down, so
drag down (+screen y) → forward. Positive is forward in both. A plain
component swap is correct.

The px→index conversion in the owning scripts is also unchanged: `zoom` is
uniform (`Vector2(z, z)`), so pixels-per-slot is identical on both axes.

### 4c. The fix does not go in these files — the banner says so

`helicase_ring.gd`'s own header states the contract:

> This node stays exactly as simulation-agnostic as the rest of the file — it
> only reports raw SCREEN-space mouse movement while a drag is active.
> Converting that into a scrub index (which needs `nucleotide_slot_spacing`,
> current zoom, and `simulation.gd` itself) is entirely the owning script's
> job, not this one's.

Injecting `vertical_mode` into the ring would break that contract for one
bool. `helicase_ring.gd` also reads no ThemeManager at all by its own
convention, so there is nowhere natural to put it.

**Widen the signal to `Vector2` instead:**

```gdscript
signal scrub_drag_delta(cumulative_px: Vector2)  # screen-space, since drag start

var _drag_start_screen: Vector2 = Vector2.ZERO
...
_drag_start_screen = event.position
...
scrub_drag_delta.emit(event.position - _drag_start_screen)
```

The owning scripts — `simulation.gd` (ring) and `replication_manager.gd`
(both clamps) — pick the component at the same site where they already do the
zoom/spacing conversion:

```gdscript
var along_px: float = cumulative_px.y if vertical_mode else cumulative_px.x
```

This is a **purification, not a compromise**: the enzyme ends up knowing
strictly *less* than it does today. It no longer pre-judges which screen axis
is meaningful — it reports raw screen movement, full stop, and the axis
question is decided by the layer that already owns every other
simulation-aware decision about that drag. The file's own banner told us
where the fix belongs.

**Cost**: a signal signature change (`float` → `Vector2`) on working code, at
two consumer sites. Both of those scripts are already being touched in this
pass anyway — they're the ones pushing label counter-rotation (Part 2c) — so
the marginal cost is near zero. Rename `_drag_start_screen_x` →
`_drag_start_screen` while there.

---

## Lifecycle: when can `vertical_mode` change?

**Recommendation: at sequence-load time only, never mid-run.**

The forcing constraint is `nitrogen_base.gd`'s ThemeManager-free contract.
Because the counter-rotation must be *pushed* to each base rather than read,
a mid-run toggle means looping every one of up to 300 base nodes plus every
5'/3' marker plus every enzyme label and re-pushing. That's not hard, it's
just a second code path that exists only to serve a case the actual use — set
it, load, record — never exercises.

Gating it to load time means vertical_mode piggybacks entirely on the
sequence-reload path that already rebuilds every base from scratch. Zero new
traversal code.

**Concretely**: `vertical_mode` is an Inspector `@export`. Changing it in the
Inspector and pressing play works. Changing it at runtime requires a sequence
reload to take effect on the glyphs. If a runtime toggle is ever wanted (a
"Vertical" button in the UI), it calls the existing reload.

---

## What this does NOT change

Worth stating explicitly, since the value of this approach is mostly in what
it leaves alone:

- Any biology. A 90° rotation preserves 5'→3' polarity exactly; the markers
  point down instead of right. No `COMPLEXITY_MODEL.md` tier is affected.
- Any position math: `center_y`, `helicase_x`, `nucleotide_original_x[]`,
  `track_length`, `get_slot_position()`, every frame-provider body.
- Any frame-provider's **contract** — providers still return world points or
  a world `{zoom, position}`. They never learn orientation exists. This is
  the frame-provider pattern paying off exactly as ZoomDesign.md predicted,
  for a case it didn't anticipate.
- Scrub-safety, in any respect.
- The enzyme **click hit-tests**. See Part 4 — they're already orientation-safe.

---

## Open questions

All factual unknowns are now closed. What remains are decisions.

- **Approve widening `scrub_drag_delta` to `Vector2`?** (Part 4c.) The
  alternative is injecting `vertical_mode` into both enzyme scripts, which
  costs less code and breaks their stated contract.
- **Does the ThemeManager rename (1b) happen in this pass or a follow-up?**
  Recommend this pass; it's cheap now (two of three values are untuned
  placeholders) and gets expensive later.
- **Per-orientation label margins, or one shared set?** Defer to in-engine.
- **`VSlider` or `HSlider` in the vertical layout?** Enabled by 3c either
  way; a taste call once it's on screen.
- **Vertical `Panel` placement**: the horizontal UI is a full-width bottom
  bar. In 1080×1920 the same controls need either a taller bottom stack or a
  different arrangement — this is a layout design question, not an
  architectural one, and is the part best done directly in the Godot editor
  rather than specified here.

**One file still needed before step 2 can be written**:
`replication_manager.gd`, to enumerate its base/marker spawn sites (Part 2a).
Not a design unknown — just an inventory.

---

## Suggested implementation order

Each step is independently QCA-able, and each leaves the build working.

1. ~~**`zoom_manager.gd`**~~ — **SHIPPED**: `vertical_mode` export, `ignore_rotation = false`,
   `rotation` set in `_ready()`, the two extent helpers, the five call sites,
   `_screen_to_world_offset()`. Vertical now *works* — everything is framed
   correctly and the free camera behaves — but all text is sideways.
   Verifiable on its own.
2. ~~**`nitrogen_base.gd`**~~ — **SHIPPED** + spawner call site: `pivot_offset` fix and
   `set_label_rotation()`. Bases and 5'/3' markers come upright. The
   `pivot_offset` fix is worth confirming in *horizontal* mode first, where it
   should be a strict no-op.
3. **`EnzymeLabel.set_counter_rotation()`** — SHIPPED except `ligase.gd`/`pol1.gd`: + the five owning enzyme scripts.
   Watch the leading clamp specifically — it's the one the mirror sign can
   get wrong, and it's self-diagnosing.
4. ~~**`scrub_drag_delta` → `Vector2`** (Part 4)~~ — **SHIPPED** + the two consumer sites.
   Small, and best done alongside step 3 since it touches the same two owning
   scripts. QCA target: drag both clamps and the ring in *horizontal* mode
   first — this step should be a strict no-op there.
5. ~~**ThemeManager rename** (1b)~~ — **SHIPPED**, done first. See Status above.
6. **`player_ui.gd` unique-name refactor** — horizontal only, no vertical
   scene yet. Pure no-op refactor; QCA the existing UI hard here.
7. **`VerticalPlayerUI.tscn`** + the `Slider` retype + `SequenceLabel`
   guards.

Steps 1–4 are the actual feature. 5 is hygiene. 6–7 are the UI, and are where
the real time goes.

Note that steps 2, 4, and 6 each have a **no-op check in horizontal mode** —
the `pivot_offset` fix, the `Vector2` widening, and the unique-name refactor
should all be invisible with `vertical_mode = false`. Those are the cheapest
QCA gates in the whole pass; use them.
