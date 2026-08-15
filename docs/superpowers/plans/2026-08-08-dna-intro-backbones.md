# DNA Intro Backbones Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reintroduce a backbone line per strand in the DNA startup intro (`scripts/dna_unwind_intro.gd`), rendered as a rotating point on the same rigid rod as each bead, with correct front/behind occlusion, settling to the live rail view's own backbone position for a seamless handoff.

**Architecture:** Pure `_draw()`-driven, no new nodes. Each backbone point reuses the bead's own `phase`/`mean_cos` at a larger radius (`rotation_radius + backbone_offset_px`). `_draw()`'s single per-slot pass is restructured into two passes (compute-all-slots, then draw) so a segment's far endpoint is known before it's drawn. Z-order between a bead and its own backbone point reuses the existing `top_is_front` flag directly — no new trig.

**Tech Stack:** Godot 4.x, GDScript.

**Spec:** `docs/superpowers/specs/2026-08-08-dna-intro-backbones-design.md` — read it before starting; this plan implements it task-by-task and repeats the exact formulas rather than paraphrasing them.

## Global Constraints

- **No multiline `or` expressions in GDScript** — a parser bug causes indentation errors when `or` spans multiple lines; always write conditions on one line (`docs/skills/zymulador-gdscript_SKILL.md`, GDScript Hard Rules).
- **ThemeManager is a scene node, not an autoload** — access it via `%ThemeManager` (already how `player_ui.gd`'s `_play_dna_intro()` gets `tm`); never add a global singleton reference.
- **No automated test coverage exists for `dna_unwind_intro.gd`, and none is added by this plan** — this is a pure `_draw()`-driven visual animation (confirmed in the spec's own Testing section); every task's verification step is a manual run-and-look check in the Godot editor, not a `pytest`-style assertion.
- **Reuse real `ThemeManager` values instead of inventing new decorative constants whenever a real on-screen analog exists** — established throughout this file (e.g. `ROTATION_RADIUS_RATIO` ties to the real strand gap, `BOND_INSET_RATIO` ties to the real bead radius); the new backbone constants follow the same rule (`tm.backbone_offset_distance`, `tm.template_backbone_color`, `tm.backbone_line_width`), all zoom-scaled the same way every other pixel value already passed into `play()` is.

## File Structure

- `scripts/dna_unwind_intro.gd` — all rendering logic. Modified: `play()` signature + 3 new instance vars (Task 1); `_draw()` restructured into two passes with backbone geometry and drawing (Tasks 2–3); top-of-file doc comment updated to describe backbones (Task 3, final step).
- `scripts/player_ui.gd` — modified: `_play_dna_intro()` computes and passes the 3 new `play()` arguments (Task 1).

No new files.

---

### Task 1: Plumb backbone styling parameters through `play()`

**Files:**
- Modify: `scripts/dna_unwind_intro.gd:161-179` (instance var declarations), `scripts/dna_unwind_intro.gd:205-232` (`play()`)
- Modify: `scripts/player_ui.gd:656-666` (the `dna_intro.play(...)` call inside `_play_dna_intro()`)

**Interfaces:**
- Produces: three new instance vars on `dna_unwind_intro.gd` — `_backbone_offset_px: float`, `_backbone_color: Color`, `_backbone_width_px: float` — populated by `play()`, consumed by `_draw()` starting in Task 2.
- Produces: `play()`'s new signature (3 trailing params appended, all existing params unchanged) — Task 2/3 code assumes this signature.

- [ ] **Step 1: Add the three new instance vars**

In `scripts/dna_unwind_intro.gd`, right after the existing `var _wobble_enabled: bool = false` line (part of the block declared at line 172) and before the `_wobble_time` comment/var block, add:

```gdscript
var _backbone_offset_px: float = 0.0
var _backbone_color: Color = Color.WHITE
var _backbone_width_px: float = 0.0
```

- [ ] **Step 2: Extend `play()`'s signature and body**

Change the `play()` function signature from:

```gdscript
func play(top_colors: Array[Color], bottom_colors: Array[Color],
		bond_colors: Array[Color], bond_counts: Array[int],
		pixel_spacing: float, strand_gap_px: float,
		bead_diameter_px: float, bond_width_px: float,
		bond_spacing_px: float, wobble_amplitude_px: float,
		wobble_speed: float, wobble_enabled: bool) -> void:
```

to:

```gdscript
func play(top_colors: Array[Color], bottom_colors: Array[Color],
		bond_colors: Array[Color], bond_counts: Array[int],
		pixel_spacing: float, strand_gap_px: float,
		bead_diameter_px: float, bond_width_px: float,
		bond_spacing_px: float, wobble_amplitude_px: float,
		wobble_speed: float, wobble_enabled: bool,
		backbone_offset_px: float, backbone_color: Color,
		backbone_width_px: float) -> void:
```

Then, in the function body, right after the existing `_wobble_enabled = wobble_enabled` line, add:

```gdscript
	_backbone_offset_px = backbone_offset_px
	_backbone_color = backbone_color
	_backbone_width_px = backbone_width_px
```

- [ ] **Step 3: Pass the new arguments from `player_ui.gd`**

In `scripts/player_ui.gd`'s `_play_dna_intro()`, change the `dna_intro.play(...)` call from:

```gdscript
	dna_intro.play(
		top_colors, bottom_colors, bond_colors, bond_counts,
		simulation.nucleotide_slot_spacing * zoom_x,
		simulation.dna_ribbons_gap * zoom_x,
		tm.base_radius * 2.0 * zoom_x,
		tm.hydrogen_bond_width * zoom_x,
		tm.hydrogen_bond_spacing * zoom_x,
		simulation.wobble_amplitude * zoom_x,
		simulation.wobble_speed,
		tm.wobble_enabled
	)
```

to:

```gdscript
	dna_intro.play(
		top_colors, bottom_colors, bond_colors, bond_counts,
		simulation.nucleotide_slot_spacing * zoom_x,
		simulation.dna_ribbons_gap * zoom_x,
		tm.base_radius * 2.0 * zoom_x,
		tm.hydrogen_bond_width * zoom_x,
		tm.hydrogen_bond_spacing * zoom_x,
		simulation.wobble_amplitude * zoom_x,
		simulation.wobble_speed,
		tm.wobble_enabled,
		tm.backbone_offset_distance * zoom_x,
		tm.template_backbone_color,
		tm.backbone_line_width * zoom_x
	)
```

- [ ] **Step 4: Verify**

Open the project in the Godot editor, run the main scene, and load a DNA sequence to trigger the intro. Expected: the intro plays exactly as it did before this change — bare rungs, no visible backbone yet (`_draw()` doesn't read the new vars yet). No script errors in the Output/Debugger panel (a signature mismatch would show as a call-argument-count error at the `dna_intro.play(...)` call site).

- [ ] **Step 5: Commit**

```bash
git add scripts/dna_unwind_intro.gd scripts/player_ui.gd
git commit -m "Plumb backbone styling params into DNA intro's play()"
```

---

### Task 2: Two-pass restructure — backbone geometry + naive rendering

**Files:**
- Modify: `scripts/dna_unwind_intro.gd:373-519` (`_draw()`)

**Interfaces:**
- Consumes: `_backbone_offset_px`, `_backbone_color`, `_backbone_width_px` (Task 1).
- Produces: per-slot arrays `xs`, `ys_top`, `ys_bottom`, `fronts`, `backbone_ys_top`, `backbone_ys_bottom` (local to `_draw()`, one entry per slot) — Task 3's drawing pass consumes these by index.

**Step 1: Replace `_draw()`'s per-slot loop with a two-pass version**

Everything before the per-slot loop (`num_slots` through `bond_inset_now`, i.e. `scripts/dna_unwind_intro.gd:377-414` in the current file) stays exactly as-is. Replace the single per-slot `for slot in range(num_slots):` loop and everything after it (from the `# No connecting backbone curve...` comment through the end of the function, i.e. lines 433-519 in the current file) with:

```gdscript
	var backbone_radius: float = rotation_radius + _backbone_offset_px

	# ---- Pass 1: compute every slot's geometry, no drawing ----
	# A backbone segment from slot i to i+1 needs both endpoints' Y before
	# either can be drawn, so geometry is computed for every slot first and
	# stored, then Pass 2 (Task 3) draws using these arrays by index.
	var xs: Array[float] = []
	var ys_top: Array[float] = []
	var ys_bottom: Array[float] = []
	var fronts: Array[bool] = []
	var backbone_ys_top: Array[float] = []
	var backbone_ys_bottom: Array[float] = []

	for slot in range(num_slots):
		var x: float = final_left_x + float(slot) * _pixel_spacing
		var phase: float = float(slot) / float(num_slots - 1) * turns * TAU + rotation_angle

		# Bead Y: unchanged from the single-pass version — see top-of-file
		# "Rotation math" comment.
		var y_offset: float = rotation_radius * (cos(phase) - mean_cos)
		var y_top: float = center_y - y_offset
		var y_bottom: float = center_y + y_offset
		var top_is_front: bool = sin(phase) > 0.0

		# Backbone Y: the exact same phase/mean_cos as the bead, just a
		# larger radius — a second point on the same rotating rod (see
		# design spec's "Geometry" section).
		var backbone_offset: float = backbone_radius * (cos(phase) - mean_cos)
		var backbone_y_top: float = center_y - backbone_offset
		var backbone_y_bottom: float = center_y + backbone_offset

		# Settle phase: identical slot_t to the existing bead lerp, applied
		# to both bead and backbone so they arrive home the same instant
		# (see design spec's "Settle-phase target" section). The backbone
		# target mirrors on_bonded=true in simulation.gd's own backbone
		# logic (the whole strand is still bonded pre-replication): outward
		# from each strand's own flat resting row by _backbone_offset_px.
		var settle_elapsed: float = max(0.0, _elapsed - _settle_start_elapsed) if _settle_triggered else 0.0
		var stagger_fraction: float = float(num_slots - 1 - slot) / float(num_slots - 1)
		var settle_delay: float = stagger_fraction * SETTLE_STAGGER_SECONDS
		var slot_t: float = clamp((settle_elapsed - settle_delay) / SETTLE_LERP_SECONDS, 0.0, 1.0)

		y_top = lerp(y_top, center_y - _strand_gap_px * 0.5, slot_t)
		y_bottom = lerp(y_bottom, center_y + _strand_gap_px * 0.5, slot_t)
		backbone_y_top = lerp(backbone_y_top, center_y - _strand_gap_px * 0.5 - _backbone_offset_px, slot_t)
		backbone_y_bottom = lerp(backbone_y_bottom, center_y + _strand_gap_px * 0.5 + _backbone_offset_px, slot_t)

		# Ambient wobble: same call, same index, added last — applied to
		# the backbone too so it stays visually attached to its own strand.
		var wobble_y: float = _wobble_y(slot, _wobble_time)
		y_top += wobble_y
		y_bottom += wobble_y
		backbone_y_top += wobble_y
		backbone_y_bottom += wobble_y

		xs.append(x)
		ys_top.append(y_top)
		ys_bottom.append(y_bottom)
		fronts.append(top_is_front)
		backbone_ys_top.append(backbone_y_top)
		backbone_ys_bottom.append(backbone_y_bottom)

	# ---- Pass 2: draw ----
	# Naive z-order for now — the whole backbone drawn first (behind
	# everything). Task 3 replaces this with correct per-segment,
	# per-bead-pair interleaving.
	for slot in range(num_slots - 1):
		draw_line(Vector2(xs[slot], backbone_ys_top[slot]), Vector2(xs[slot + 1], backbone_ys_top[slot + 1]), _backbone_color, _backbone_width_px)
		draw_line(Vector2(xs[slot], backbone_ys_bottom[slot]), Vector2(xs[slot + 1], backbone_ys_bottom[slot + 1]), _backbone_color, _backbone_width_px)

	for slot in range(num_slots):
		var x: float = xs[slot]
		var y_top: float = ys_top[slot]
		var y_bottom: float = ys_bottom[slot]
		var top_is_front: bool = fronts[slot]

		var span: float = y_bottom - y_top
		var dir: float = sign(span) if span != 0.0 else 1.0
		var line_top: float = y_top + dir * bond_inset_now
		var line_bottom: float = y_bottom - dir * bond_inset_now

		var bond_count: int = _bond_counts[slot]
		var bond_color: Color = _bond_colors[slot]
		var bundle_span: float = float(bond_count - 1) * bond_spacing_now
		var bundle_start_x: float = x - bundle_span * 0.5
		for b in range(bond_count):
			var bx: float = bundle_start_x + float(b) * bond_spacing_now
			draw_line(Vector2(bx, line_top), Vector2(bx, line_bottom), bond_color, bond_width_now)
			draw_circle(Vector2(bx, line_top), bond_width_now * 0.5, bond_color)
			draw_circle(Vector2(bx, line_bottom), bond_width_now * 0.5, bond_color)

		if top_is_front:
			draw_circle(Vector2(x, y_bottom), bead_radius_now, _bottom_colors[slot], true, -1.0, true)
			draw_circle(Vector2(x, y_top), bead_radius_now, _top_colors[slot], true, -1.0, true)
		else:
			draw_circle(Vector2(x, y_top), bead_radius_now, _top_colors[slot], true, -1.0, true)
			draw_circle(Vector2(x, y_bottom), bead_radius_now, _bottom_colors[slot], true, -1.0, true)
```

- [ ] **Step 2: Verify**

Run the app, load a sequence, watch the intro. Expected: bond bundles and beads look and move identically to before Task 2 (pure refactor — bead geometry math is untouched, just moved into an array-based pass). New: a grey backbone line now traces through each strand's beads, staying behind them at all times (naive ordering) — confirm it visibly rotates in sync with the beads (same phase), is offset further from center than the beads at each bead's own Y extreme, and coincides with the beads at each bead's own midpoint. Confirm the fully-settled final frame's backbone sits at a fixed offset outside each strand's flat row (not still oscillating).

- [ ] **Step 3: Commit**

```bash
git add scripts/dna_unwind_intro.gd
git commit -m "Add rotating backbone geometry to DNA intro (naive draw-behind ordering)"
```

---

### Task 3: Correct per-segment z-order + doc comment update

**Files:**
- Modify: `scripts/dna_unwind_intro.gd` (Pass 2 of `_draw()`, written in Task 2; top-of-file doc comment, lines 1-76)

**Interfaces:**
- Consumes: the same per-slot arrays Task 2 produces (`xs`, `ys_top`, `ys_bottom`, `fronts`, `backbone_ys_top`, `backbone_ys_bottom`).

- [ ] **Step 1: Replace the naive backbone-first loop with correct interleaved ordering**

Remove the Task 2 `for slot in range(num_slots - 1):` pre-loop (the one that draws all backbone segments before any beads). Replace the per-slot bead-drawing loop's body — from `var span: float = y_bottom - y_top` (the bond bundle block, keep unchanged) through the closing `if top_is_front: ... else: ...` bead-drawing block — by keeping the bond bundle block as-is and replacing only the final `if top_is_front:`/`else:` block with:

```gdscript
		# This slot's own outgoing backbone segments (to slot+1), owned by
		# this slot ("left-slot ownership" — see design spec's "Segments
		# and draw order" section). None for the rightmost slot.
		var has_segment: bool = slot < num_slots - 1
		var top_backbone_from: Vector2 = Vector2(x, backbone_ys_top[slot])
		var bottom_backbone_from: Vector2 = Vector2(x, backbone_ys_bottom[slot])
		var top_backbone_to: Vector2
		var bottom_backbone_to: Vector2
		if has_segment:
			top_backbone_to = Vector2(xs[slot + 1], backbone_ys_top[slot + 1])
			bottom_backbone_to = Vector2(xs[slot + 1], backbone_ys_bottom[slot + 1])

		# Z-order: a bead's own backbone point shares that bead's own
		# front/back status (real backbone sits outside the helix, bases
		# inside — see design spec's "Z-order" section) — never the
		# opposite. Whichever bead is this pair's "back" bead draws as
		# [backbone, bead] (backbone behind it); the "front" bead draws as
		# [bead, backbone] (backbone in front of it, momentarily covering
		# it right at each crossing). The two units compose back-then-front,
		# same as the existing top/bottom order.
		if top_is_front:
			if has_segment:
				draw_line(bottom_backbone_from, bottom_backbone_to, _backbone_color, _backbone_width_px)
			draw_circle(Vector2(x, y_bottom), bead_radius_now, _bottom_colors[slot], true, -1.0, true)
			draw_circle(Vector2(x, y_top), bead_radius_now, _top_colors[slot], true, -1.0, true)
			if has_segment:
				draw_line(top_backbone_from, top_backbone_to, _backbone_color, _backbone_width_px)
		else:
			if has_segment:
				draw_line(top_backbone_from, top_backbone_to, _backbone_color, _backbone_width_px)
			draw_circle(Vector2(x, y_top), bead_radius_now, _top_colors[slot], true, -1.0, true)
			draw_circle(Vector2(x, y_bottom), bead_radius_now, _bottom_colors[slot], true, -1.0, true)
			if has_segment:
				draw_line(bottom_backbone_from, bottom_backbone_to, _backbone_color, _backbone_width_px)
```

- [ ] **Step 2: Update the top-of-file doc comment**

In `scripts/dna_unwind_intro.gd`'s header comment block, find the "Geometry technique" paragraph (currently reads: `## Geometry technique: one rung per real nucleotide slot, no connecting` / `## backbone curve — bare rungs only, matching the reference sketch's` / `## structure exactly. ...`). Replace it with a paragraph describing the backbone as implemented:

```gdscript
## Geometry technique: one rung per real nucleotide slot, connected by a
## per-strand backbone polyline (straight draw_line segments between
## consecutive slots' backbone points, no Line2D/Curve2D — matching how
## the real strand's own backbone is just a polyline through per-slot
## points). Each backbone point is a second point on the same rotating rod
## as its bead — same phase and mean_cos, a larger radius
## (rotation_radius + backbone_offset_px) — so it traces the bead's own
## curve at a wider swing, coinciding with the bead at the bead's own
## midpoint and separating fully at the bead's own Y extremes. Z-order
## between a bead and its own backbone point reuses top_is_front directly:
## a bead's backbone shares that bead's own front/back status (real
## backbone sits outside the helix, bases inside), so the front bead's own
## backbone momentarily covers it right at each crossing — see
## docs/superpowers/specs/2026-08-08-dna-intro-backbones-design.md for the
## full derivation. Each rung's two endpoints are drawn as real
## nucleotide bead glyphs (plain filled circles, colored by the base's
## real ThemeManager.base_color_{a,t,c,g}, no outline — reproducing
## nitrogen_base.gd's _draw() exactly), connected by a real hydrogen-bond
## bundle (2 parallel lines for A-T, 3 for C-G, colored by pair family via
## ThemeManager.at_bond_color/cg_bond_color — reproducing
## simulation.gd's _spawn_template_hydrogen_bonds()) instead of a single
## generic-colored line.
```

- [ ] **Step 3: Verify**

Run the app, load a sequence, watch the intro closely at a crossing (where a strand's beads pass near the center line). Expected: right at each crossing, the currently-front bead is briefly, partially covered by its own backbone line — no bead reads as a full, unoccluded circle exactly at the crossing point. Away from crossings, beads render fully on top of their own backbone as before. Confirm no popping/tearing at segment midpoints where a segment's two endpoints disagree on z-order (should be imperceptible at this line width). Let the intro fully settle and compare the final frame's backbone lines (position, color, width) against the live rail view's own `backbone_line`/`top_strand_backbone_line` — they should match exactly. Confirm skip-via-click/keypress still works at any point during the animation.

- [ ] **Step 4: Commit**

```bash
git add scripts/dna_unwind_intro.gd
git commit -m "Correct DNA intro backbone z-order to per-segment interleaving"
```
