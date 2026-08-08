extends ColorRect

## Startup animation: a simplified version of the real strand about to be
## shown, playing a twisted double helix at fixed geometry before handing
## off to the live rail view. Colors and sizing passed into play() are the
## real on-screen values the live rail view itself would use (see
## player_ui.gd's _play_dna_intro()) — this script does no ThemeManager or
## simulation lookups of its own — but the twisted pose itself does NOT
## ease into the live view's flat layout: the overlay just disappears when
## it finishes, handing off with a hard cut rather than a seamless morph
## (a deliberate, current trade-off — see the Motion model paragraph
## below). Still a bead-tier abstraction — no base-letter labels, no
## 5'->3' direction arrowheads, no derived molecular geometry.
##
## Motion model: one continuous rotation, nothing else animated. Only
## rotation_angle moves — a pure linear function of elapsed time,
## reproducing the reference p5.js sketch's `angle += frequency` every
## frame, forever. Every other quantity (rotation radius, strand gap,
## horizontal spacing, bead radius, H-bond bundle width/spacing) is a
## plain constant for the whole animation — no easing/growing-in — same as
## the reference sketch's fixed h/space/size. This means the overlay's
## final frame does NOT match the live rail view's flat layout; the
## disappearance at the end of the animation is a visible hard cut, not a
## pixel-matched handoff. Accepted deliberately for now, to isolate and
## tune the rotation itself; revisit if the handoff needs to be seamless
## again.
##
## Geometry technique: one rung per real nucleotide slot, no connecting
## backbone curve — bare rungs only, matching the reference sketch's
## structure exactly. Each rung's two endpoints are drawn as real
## nucleotide bead glyphs (plain filled circles, colored by the base's
## real ThemeManager.base_color_{a,t,c,g}, no outline — reproducing
## nitrogen_base.gd's _draw() exactly), connected by a real hydrogen-bond
## bundle (2 parallel lines for A-T, 3 for C-G, colored by pair family via
## ThemeManager.at_bond_color/cg_bond_color — reproducing
## simulation.gd's _spawn_template_hydrogen_bonds()) instead of a single
## generic-colored line.
##
## Rotation math (see _draw()): the two beads at a slot are a real
## rotating pair, not an ad hoc vertical wobble — this reuses the exact
## technique docs/HelicaseDesign.md shipped for the helicase ring's own
## barrel-roll (and that docs/Topoisomerase.md explicitly names as "the
## z-order + periodic-crossing pattern" to reuse for any twisted-pair
## visual): a body rotating in the Y-Z plane, viewed edge-on. Screen Y
## comes from cos(phase) (one bead's Y, its pair's Y is the exact
## negative — always a true mirror around center); a second term,
## sin(phase), is the unrendered depth axis, and its SIGN decides which
## bead draws in front this frame. That sign only flips at phase's
## extremes (0, PI, ...) — exactly where the pair is at maximum Y
## separation, so the flip is invisible — and stays constant all the way
## through each approach-cross-depart cycle in between, so whichever bead
## is "front" going into a crossing stays front coming out the other side,
## precisely the barber-pole look. A fixed sin-for-one/cos-for-other
## offset (this script's original approach) produces a similar-looking
## curve but is physically a vertical oscillation with no depth/occlusion
## concept at all — it was a workaround for not having solved occlusion,
## not a rotation.
##
## rotation_radius (the pair's Y-extent) is derived directly from the real
## dna_ribbons_gap (via _strand_gap_px, ROTATION_RADIUS_RATIO defaulting to
## 1.0), so the twisted pose's footprint matches the real strand's by
## construction rather than needing separate tuning against it. Each
## curve's own mean cos offset over the visible turn range is subtracted
## out (see _draw()) so neither strand drifts higher/lower on average —
## turns is essentially never a whole number, so cos would otherwise
## average non-zero over the visible range; since both curves are exact
## negatives of each other, one shared correction handles both. Skippable
## via any key press or mouse click.

signal intro_finished

## Temporary debug scaffolding for iterating on the geometry in isolation:
## freezes _elapsed at FREEZE_T * TOTAL_DURATION_SECONDS (still dismissible
## via click/keypress) — a specific point within the single continuous
## timeline. Set back to false once the geometry looks right — not a
## shipped feature, remove when no longer needed.
const FREEZE_AT_TWISTED_STATE: bool = false
const FREEZE_T: float = 0.15

const TOTAL_DURATION_SECONDS: float = 4.4

const BP_PER_TURN: float = 10.5
## Multiplies the biologically-derived spatial winding (num_slots /
## BP_PER_TURN) for decorative purposes only — packs more visible twists
## into the same fixed dot count (num_slots is real data, not something
## this script can add more samples to), so the winding pattern is dense
## enough to read as a spiral from the dots alone, without a connecting
## backbone curve. Kept modest (not much higher) since too few dots per
## revolution starts looking undersampled/jagged rather than smooth.
## Live-tune by eye alongside TOTAL_SPIN_TURNS below.
const SPATIAL_TWIST_DENSITY: float = 1.5
## Rotation radius (each bead's Y-distance from center) as a multiple of
## half the real strand gap (_strand_gap_px) — not an extra "wobble" added
## on top of a separate gap baseline. With the corrected rotation model, a
## bead pair at rest (phase = 0 or PI) sits exactly rotation_radius apart
## from center on each side, i.e. the pair's total Y-extent is
## _strand_gap_px * ratio: at 1.0 that's exactly the real strand's own
## gap — the twisted pose's footprint matches the real strand by
## construction, not by tuning a separate amplitude constant against it
## (the old AMPLITUDE_RATIO/gap_bias split this replaces needed exactly
## that kind of tuning, and still overshot). Live-tune by eye if a
## deliberately larger/smaller twist is wanted later.
const ROTATION_RADIUS_RATIO: float = 1.0
## Real hydrogen-bond lines are inset from each bead's center by roughly
## base_radius - 3.0 (theme_manager.gd's real geometry: 15.0 - 3.0 = 12.0)
## so they don't run into the bead circle. Reproduced here as a ratio of
## the bead radius (12.0 / 15.0) rather than a separate pixel constant.
const BOND_INSET_RATIO: float = 0.8
## Full rotations over the whole animation, on top of the spatial sin/cos
## winding — this is what makes the pattern visibly spin/travel along the
## strand throughout. Rotation runs at this constant rate the entire time,
## never holding or stopping. With no connecting backbone curve, this
## rotation speed is the main cue that reads as "two winding strands"
## rather than a static dot scatter — a faster spin gives the eye a
## traveling-wave motion cue to infer continuity from, standing in for
## what a connecting line would otherwise show explicitly. Decorative
## only — no real quantity to derive this from — live-tune by eye.
const TOTAL_SPIN_TURNS: float = 3.0

var _elapsed: float = 0.0
var _playing: bool = false

var _top_colors: Array[Color] = []
var _bottom_colors: Array[Color] = []
var _bond_colors: Array[Color] = []
var _bond_counts: Array[int] = []
var _pixel_spacing: float = 0.0
var _strand_gap_px: float = 0.0
var _bead_diameter_px: float = 0.0
var _bond_width_px: float = 0.0
var _bond_spacing_px: float = 0.0


func _ready() -> void:
	visible = false


## top_colors[i] / bottom_colors[i] are the resolved fill colors (via
## ThemeManager.get_base_color()) for the base at slot i and its Watson-Crick
## complement, one entry per real base in the loaded sequence — uncapped,
## matching the real live strand's own nitrogen_base glyph count exactly
## (simulation.gd spawns one glyph per base regardless of length; only
## camera/windowing decisions are capped to legible_reference_length, not
## glyph count) — see player_ui.gd's _play_dna_intro().
## bond_colors[i] is ThemeManager.cg_bond_color/at_bond_color for the slot's
## real base-pair family; bond_counts[i] is
## NitrogenBaseDeriver.hydrogen_bond_count() for that same base (2 for A/T,
## 3 for C/G) — together these reproduce the real per-pair H-bond bundle
## styling instead of a single generic line.
## pixel_spacing/strand_gap_px/bead_diameter_px/bond_width_px/bond_spacing_px
## are all already real on-screen pixel values (world units pre-multiplied
## by the real camera fit zoom) — see player_ui.gd's _play_dna_intro().
func play(top_colors: Array[Color], bottom_colors: Array[Color],
		bond_colors: Array[Color], bond_counts: Array[int],
		pixel_spacing: float, strand_gap_px: float,
		bead_diameter_px: float, bond_width_px: float,
		bond_spacing_px: float) -> void:
	_top_colors = top_colors
	_bottom_colors = bottom_colors
	_bond_colors = bond_colors
	_bond_counts = bond_counts
	_pixel_spacing = pixel_spacing
	_strand_gap_px = strand_gap_px
	_bead_diameter_px = bead_diameter_px
	_bond_width_px = bond_width_px
	_bond_spacing_px = bond_spacing_px

	_elapsed = FREEZE_T * TOTAL_DURATION_SECONDS if FREEZE_AT_TWISTED_STATE else 0.0
	_playing = true
	visible = true
	queue_redraw()


func _process(delta: float) -> void:
	if not _playing:
		return

	if FREEZE_AT_TWISTED_STATE:
		return

	_elapsed = min(_elapsed + delta, TOTAL_DURATION_SECONDS)
	queue_redraw()

	if _elapsed >= TOTAL_DURATION_SECONDS:
		_finish()


func _input(event: InputEvent) -> void:
	if not _playing:
		return

	var is_press: bool = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventKey and event.pressed)
	if is_press:
		get_viewport().set_input_as_handled()
		_finish()


func _finish() -> void:
	_playing = false
	visible = false
	intro_finished.emit()


func _draw() -> void:
	if not visible:
		return

	var num_slots: int = _top_colors.size()
	if num_slots < 2:
		return

	var center_x: float = size.x * 0.5
	var center_y: float = size.y * 0.5
	var turns: float = max(1.0, float(num_slots) / BP_PER_TURN) * SPATIAL_TWIST_DENSITY
	var final_span: float = float(num_slots - 1) * _pixel_spacing
	var final_left_x: float = center_x - final_span * 0.5

	# One continuous animation from a single elapsed-time clock. t drives
	# rotation_angle, linearly, so rotation never holds or stops for the
	# whole duration (reproducing the reference sketch's `angle +=
	# frequency` every frame, forever). Nothing else is eased in from a
	# collapsed state anymore — see the constants below.
	var t: float = clamp(_elapsed / TOTAL_DURATION_SECONDS, 0.0, 1.0)

	# rotation_angle advances at a constant rate for the whole animation, no
	# offset — phase 0 is a valid, physically sensible resting pose (one
	# bead at max Y, its pair at min Y), unlike the old sin/cos-oscillation
	# model this replaces, which needed a PI/4 fudge to avoid an ugly
	# literal-zero start. Not needed here.
	var rotation_angle: float = t * TOTAL_SPIN_TURNS * TAU

	# No growing-in: every quantity below is a plain constant instead of
	# easing from a collapsed start toward a real/flat target, matching the
	# reference sketch's fixed h/space/size — only rotation animates.
	# rotation_radius is derived directly from the real dna_ribbons_gap
	# (_strand_gap_px), so the pair's resting Y-extent matches the real
	# strand's gap by construction (see ROTATION_RADIUS_RATIO's own
	# comment). bead_radius/bond_width/bond_spacing are pinned to their
	# real final sizes rather than 0/invisible.
	var rotation_radius: float = _strand_gap_px * 0.5 * ROTATION_RADIUS_RATIO
	var bead_radius_now: float = _bead_diameter_px * 0.5
	var bond_width_now: float = _bond_width_px
	var bond_spacing_now: float = _bond_spacing_px
	var bond_inset_now: float = bead_radius_now * BOND_INSET_RATIO

	# Both beads' Y comes from the SAME function, cos(phase) — one bead
	# positive, its pair the exact negative — a true mirror around center,
	# not two different trig functions offset from each other. See the
	# top-of-file "Rotation math" comment for why this (plus the
	# depth/z-order term below) is the physically correct technique, reused
	# from docs/HelicaseDesign.md's shipped ring rotation.
	#
	# The catch: cos only averages to zero over an *exact whole* number of
	# periods, and turns = num_slots/10.5 essentially never is one — so
	# without correction, the pair visibly drifts off-center on average.
	# Fixed by subtracting cos's own mean over the actually-sampled range
	# [rotation_angle, rotation_angle + Θ] (general closed form; reduces to
	# the simpler zero-offset formula when rotation_angle is 0). Since both
	# beads are exact negatives of each other, this single correction
	# re-centers both at once — no separate mean_sin/mean_cos needed like
	# the old two-different-functions model required.
	var theta: float = turns * TAU
	var mean_cos: float = (sin(rotation_angle + theta) - sin(rotation_angle)) / theta

	# No connecting backbone curve — bare rungs only, matching the
	# reference sketch's structure. Each rung is a real hydrogen-bond
	# bundle (bond_counts[slot] parallel lines, 2 for A-T / 3 for C-G,
	# colored by pair family) connecting two real-colored nucleotide bead
	# glyphs, reproducing simulation.gd's/nitrogen_base.gd's actual
	# bead-tier rendering rather than a generic colored shape. The bond
	# bundle is drawn first so it visually plugs into the bead edges
	# rather than the beads sitting under a line.
	for slot in range(num_slots):
		var x: float = final_left_x + float(slot) * _pixel_spacing
		var phase: float = float(slot) / float(num_slots - 1) * turns * TAU + rotation_angle
		# True mirror pair: y_bottom is the exact negative of y_top's
		# offset from center, both driven by the same cos(phase). The
		# unrendered depth axis is sin(phase) — its sign says which bead
		# is currently nearer the viewer, used below to decide draw order.
		var y_offset: float = rotation_radius * (cos(phase) - mean_cos)
		var y_top: float = center_y - y_offset
		var y_bottom: float = center_y + y_offset
		var top_is_front: bool = sin(phase) > 0.0

		# Inset each bond line's endpoints away from the bead centers by
		# bond_inset_now, same as simulation.gd's real H-bond lines, using
		# the sign of the top-to-bottom span so this holds regardless of
		# which of y_top/y_bottom is numerically larger at this phase.
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
			# Small end-cap circles approximate Line2D's round caps, which
			# the real hydrogen-bond lines use but raw draw_line has no
			# equivalent for.
			draw_circle(Vector2(bx, line_top), bond_width_now * 0.5, bond_color)
			draw_circle(Vector2(bx, line_bottom), bond_width_now * 0.5, bond_color)

		# Draw order follows top_is_front so the nearer bead actually
		# occludes the farther one right at a crossing, instead of an
		# arbitrary fixed top-then-bottom order.
		if top_is_front:
			draw_circle(Vector2(x, y_bottom), bead_radius_now, _bottom_colors[slot], true, -1.0, true)
			draw_circle(Vector2(x, y_top), bead_radius_now, _top_colors[slot], true, -1.0, true)
		else:
			draw_circle(Vector2(x, y_top), bead_radius_now, _top_colors[slot], true, -1.0, true)
			draw_circle(Vector2(x, y_bottom), bead_radius_now, _bottom_colors[slot], true, -1.0, true)
