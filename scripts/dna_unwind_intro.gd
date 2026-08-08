extends ColorRect

## Startup animation: a simplified version of the real strand about to be
## shown, playing a twisted double helix that settles into the live rail
## view's exact flat layout before handing off. Colors and sizing passed
## into play() are the real on-screen values the live rail view itself
## would use (see player_ui.gd's _play_dna_intro()) — this script does no
## ThemeManager or simulation lookups of its own, and the settle phase
## (below) lands every bead at the exact real position, so the handoff to
## the live view is seamless, not a hard cut. Still a bead-tier
## abstraction — no base-letter labels, no 5'->3' direction arrowheads, no
## derived molecular geometry.
##
## Motion model: two sequential phases. First, one continuous rotation —
## only rotation_angle moves, reproducing the reference p5.js sketch's
## `angle += frequency` every frame, at a constant rate through every lap
## except the last, which eases out (see _rotation_state()) so the eventual
## freeze reads as a smooth glide-to-a-stop rather than a fast sweep hitting
## a wall. Every other quantity (rotation radius, strand gap, horizontal
## spacing, bead radius, H-bond bundle width/spacing) is a plain constant
## throughout this phase — no easing/growing-in of its own — same as the
## reference sketch's fixed h/space/size. Rotation freezes not at a fixed
## clock time but at the natural moment the rightmost bead pair's rotating
## Y already coincides with its real resting Y (see _process()), so the
## first bead to move needs zero motion to "start" — falls back to freezing
## at ROTATION_DURATION_SECONDS if that coincidence never occurs. Second,
## the settle phase (see _draw()'s per-slot loop): once rotation has frozen,
## each bead individually glides in Y from that frozen pose to its real
## resting row, staggered right to left so the strand appears to settle
## into place as a wave — see SETTLE_STAGGER_SECONDS/SETTLE_LERP_SECONDS
## below. A small ambient wobble (see _wobble_y()) is layered on top of
## both phases throughout, reproducing the real strand's own per-base
## jitter.
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
## via click/keypress) — a specific point within the full rotation+settle
## timeline. Set back to false once the geometry looks right — not a
## shipped feature, remove when no longer needed.
const FREEZE_AT_TWISTED_STATE: bool = false
const FREEZE_T: float = 0.15

const ROTATION_DURATION_SECONDS: float = 4.4
## Span across which per-bead settle START delays are spread, right to
## left — the rightmost slot begins settling the instant this phase
## starts, the leftmost slot begins SETTLE_STAGGER_SECONDS later. Scales
## automatically with however many beads are loaded (see _draw()), so the
## cascade's total length stays this constant regardless of sequence
## length. Live-tune by eye.
const SETTLE_STAGGER_SECONDS: float = 1.0
## How long each individual bead's own glide from its frozen rotating
## position to its real resting Y takes, once its turn arrives. Live-tune
## by eye.
const SETTLE_LERP_SECONDS: float = 0.4
## Derived, not tuned directly: the last bead to start settling (the
## leftmost slot, at SETTLE_STAGGER_SECONDS in) still needs
## SETTLE_LERP_SECONDS more to finish, so this is the true full-timeline
## length _process()'s finish-trigger and the FREEZE_T debug freeze above
## both key off.
const TOTAL_DURATION_SECONDS: float = ROTATION_DURATION_SECONDS + SETTLE_STAGGER_SECONDS + SETTLE_LERP_SECONDS

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
## strand throughout. Rotation runs at this constant rate through every lap
## but the last, which eases out instead (see _rotation_state()) — never
## holding or stopping before that. With no connecting backbone curve, this
## rotation speed is the main cue that reads as "two winding strands"
## rather than a static dot scatter — a faster spin gives the eye a
## traveling-wave motion cue to infer continuity from, standing in for
## what a connecting line would otherwise show explicitly. Decorative
## only — no real quantity to derive this from — live-tune by eye.
const TOTAL_SPIN_TURNS: float = 3.0

var _elapsed: float = 0.0
var _playing: bool = false

## Settle-phase trigger state: rather than starting the settle cascade at
## a fixed clock time, _process() watches the rightmost bead pair during
## the rotation's final lap for the natural moment its rotating Y already
## coincides with its real resting Y, and fires the whole settle phase
## right then (zero discontinuity for the first bead to move). See
## _process()/_rotation_state(). _settle_start_elapsed is only meaningful
## once _settle_triggered is true. _prev_rightmost_diff(_valid) track the
## previous frame's (rotating - target) offset for zero-crossing detection.
var _settle_triggered: bool = false
var _settle_start_elapsed: float = 0.0
var _prev_rightmost_diff: float = 0.0
var _prev_rightmost_diff_valid: bool = false

var _top_colors: Array[Color] = []
var _bottom_colors: Array[Color] = []
var _bond_colors: Array[Color] = []
var _bond_counts: Array[int] = []
var _pixel_spacing: float = 0.0
var _strand_gap_px: float = 0.0
var _bead_diameter_px: float = 0.0
var _bond_width_px: float = 0.0
var _bond_spacing_px: float = 0.0
var _wobble_amplitude_px: float = 0.0
var _wobble_speed: float = 0.0
var _wobble_enabled: bool = false
var _backbone_offset_px: float = 0.0
var _backbone_color: Color = Color.WHITE
var _backbone_width_px: float = 0.0

## Free-running clock driving the per-bead wobble jitter (see _wobble_y()) —
## simulation.gd's own wobble_time is a persistent whole-session accumulator
## and this is a fresh temporary animation each play(), so restarting at 0
## each time is simplest; the wobble's per-bead hash phases already keep it
## from ever looking synchronized/flag-like regardless of starting phase.
var _wobble_time: float = 0.0


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
## wobble_amplitude_px is likewise pre-scaled (simulation.wobble_amplitude *
## zoom_x); wobble_speed is a temporal rate so it's passed through as-is;
## wobble_enabled mirrors ThemeManager.wobble_enabled so the intro respects
## the same accessibility toggle the real strand's wobble does.
func play(top_colors: Array[Color], bottom_colors: Array[Color],
		bond_colors: Array[Color], bond_counts: Array[int],
		pixel_spacing: float, strand_gap_px: float,
		bead_diameter_px: float, bond_width_px: float,
		bond_spacing_px: float, wobble_amplitude_px: float,
		wobble_speed: float, wobble_enabled: bool,
		backbone_offset_px: float, backbone_color: Color,
		backbone_width_px: float) -> void:
	_top_colors = top_colors
	_bottom_colors = bottom_colors
	_bond_colors = bond_colors
	_bond_counts = bond_counts
	_pixel_spacing = pixel_spacing
	_strand_gap_px = strand_gap_px
	_bead_diameter_px = bead_diameter_px
	_bond_width_px = bond_width_px
	_bond_spacing_px = bond_spacing_px
	_wobble_amplitude_px = wobble_amplitude_px
	_wobble_speed = wobble_speed
	_wobble_enabled = wobble_enabled
	_backbone_offset_px = backbone_offset_px
	_backbone_color = backbone_color
	_backbone_width_px = backbone_width_px
	_wobble_time = 0.0

	_elapsed = FREEZE_T * TOTAL_DURATION_SECONDS if FREEZE_AT_TWISTED_STATE else 0.0
	_playing = true
	_settle_triggered = false
	_settle_start_elapsed = 0.0
	_prev_rightmost_diff = 0.0
	_prev_rightmost_diff_valid = false
	visible = true
	queue_redraw()


## Rotation geometry as a function of how much of the rotation phase has
## elapsed — shared by _process()'s settle-trigger detection and _draw()'s
## rendering so the two can never drift out of sync. rotation_elapsed is
## typically _elapsed (still rotating) or the frozen _settle_start_elapsed
## (once triggered) — see call sites.
##
## Constant angular speed through every lap except the last: the final lap
## (the same window _process() watches for the natural settle-coincidence)
## decelerates to a stop instead, so rotation is already slowing by the
## time any trigger fires — freezing then reads as a glide-to-a-stop
## rather than a fast sweep hitting an instant wall. Both branches sweep
## the exact same phase range either way (only the pacing within the final
## lap changes), so this has no effect on whether a natural coincidence
## exists or where in phase-space it's found — only on how gently the
## motion gets there.
##
## eased_lap_t = -u^3 + u^2 + u (a cubic Hermite curve from 0 to 1 with
## start slope 1 and end slope 0) is used instead of a plain ease-out
## (1-(1-u)^3) deliberately: a plain ease-out's slope AT u=0 is 3, not 1 —
## it would make rotation suddenly speed up 3x right at the lap boundary,
## the opposite of smooth. This Hermite curve's slope is continuous with
## the incoming constant angular speed at u=0 and eases down to exactly 0
## at u=1, so there's no velocity discontinuity anywhere in the whole
## rotation phase, only a true deceleration to rest.
func _rotation_state(rotation_elapsed: float, num_slots: int) -> Dictionary:
	var turns: float = max(1.0, float(num_slots) / BP_PER_TURN) * SPATIAL_TWIST_DENSITY
	var clamped_elapsed: float = clamp(rotation_elapsed, 0.0, ROTATION_DURATION_SECONDS)
	var lap_duration: float = ROTATION_DURATION_SECONDS / TOTAL_SPIN_TURNS
	var final_lap_start: float = ROTATION_DURATION_SECONDS - lap_duration
	var rotation_angle: float
	if clamped_elapsed <= final_lap_start:
		rotation_angle = (clamped_elapsed / ROTATION_DURATION_SECONDS) * TOTAL_SPIN_TURNS * TAU
	else:
		var u: float = clamp((clamped_elapsed - final_lap_start) / lap_duration, 0.0, 1.0)
		var eased_lap_t: float = -pow(u, 3.0) + pow(u, 2.0) + u
		rotation_angle = (TOTAL_SPIN_TURNS - 1.0) * TAU + eased_lap_t * TAU
	var theta: float = turns * TAU
	var mean_cos: float = (sin(rotation_angle + theta) - sin(rotation_angle)) / theta
	var rotation_radius: float = _strand_gap_px * 0.5 * ROTATION_RADIUS_RATIO
	return {
		"turns": turns,
		"rotation_angle": rotation_angle,
		"theta": theta,
		"mean_cos": mean_cos,
		"rotation_radius": rotation_radius,
	}


func _process(delta: float) -> void:
	if not _playing:
		return

	if FREEZE_AT_TWISTED_STATE:
		return

	# Settle-phase trigger: watch the rightmost bead pair during the
	# rotation's final lap for the natural instant its rotating Y already
	# coincides with its real resting Y (see top-of-file "Rotation math"
	# and the class-level comment above _settle_triggered). Both beads at
	# a slot reach their target simultaneously (they're always exact
	# mirrors of each other), so only one zero-crossing check is needed.
	if not _settle_triggered:
		var num_slots: int = _top_colors.size()
		if num_slots >= 2:
			var st: Dictionary = _rotation_state(min(_elapsed, ROTATION_DURATION_SECONDS), num_slots)
			if st.rotation_angle >= (TOTAL_SPIN_TURNS - 1.0) * TAU:
				var phase_rightmost: float = st.theta + st.rotation_angle
				var diff: float = st.rotation_radius * (cos(phase_rightmost) - st.mean_cos) - _strand_gap_px * 0.5
				if _prev_rightmost_diff_valid and sign(diff) != sign(_prev_rightmost_diff):
					_settle_triggered = true
					_settle_start_elapsed = _elapsed
				_prev_rightmost_diff = diff
				_prev_rightmost_diff_valid = true
		# Fallback — never found a natural crossing (e.g. mean_cos made it
		# mathematically unreachable this lap): start the settle phase at
		# the rotation's fixed duration anyway, so the animation is never
		# stuck spinning forever.
		if not _settle_triggered and _elapsed >= ROTATION_DURATION_SECONDS:
			_settle_triggered = true
			_settle_start_elapsed = _elapsed

	_elapsed = min(_elapsed + delta, TOTAL_DURATION_SECONDS)
	_wobble_time += delta
	queue_redraw()

	# The real total is dynamic now (rotation can end before
	# ROTATION_DURATION_SECONDS on a natural coincidence) — TOTAL_DURATION_SECONDS
	# remains only a worst-case ceiling (used above for the _elapsed cap and
	# by play()'s debug freeze), not the real finish condition.
	if _settle_triggered and _elapsed >= _settle_start_elapsed + SETTLE_STAGGER_SECONDS + SETTLE_LERP_SECONDS:
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


## Deterministic pseudo-random [0,1) value from a seed — reproduced verbatim
## from simulation.gd's _wobble_hash01() so the intro's wobble has the exact
## same "chaotic per-bead personality" feel as the real strand's, not just a
## similar-looking one.
func _wobble_hash01(seed: float) -> float:
	var x: float = sin(seed) * 43758.5453
	return x - floor(x)


## Per-slot wobble Y-offset, reproduced verbatim from simulation.gd's
## get_wobble_y() (same hash-seeded blend of two sine waves per index, same
## 0.7/0.3 blend weights) so a slot's wobble looks identical in style to the
## live view it hands off to — just not phase-synced with it (_wobble_time
## restarts at 0 each play(), see its own comment). Real _strand_gap_px-scale
## amplitude, not a decorative guess — see play()'s wobble_amplitude_px doc.
func _wobble_y(index: int, wobble_t: float) -> float:
	if not _wobble_enabled or _wobble_amplitude_px <= 0.0:
		return 0.0
	var phase_a: float = _wobble_hash01(float(index) * 12.9898) * TAU
	var freq_a: float = 0.85 + _wobble_hash01(float(index) * 78.233) * 0.5
	var phase_b: float = _wobble_hash01(float(index) * 39.425) * TAU
	var freq_b: float = 1.1 + _wobble_hash01(float(index) * 91.731) * 0.6

	var wave_a: float = sin(wobble_t * _wobble_speed * freq_a * TAU + phase_a)
	var wave_b: float = sin(wobble_t * _wobble_speed * freq_b * TAU + phase_b)
	return (wave_a * 0.7 + wave_b * 0.3) * _wobble_amplitude_px


func _draw() -> void:
	if not visible:
		return

	var num_slots: int = _top_colors.size()
	if num_slots < 2:
		return

	var center_x: float = size.x * 0.5
	var center_y: float = size.y * 0.5
	var final_span: float = float(num_slots - 1) * _pixel_spacing
	var final_left_x: float = center_x - final_span * 0.5

	# Rotation freezes at _settle_start_elapsed once the settle phase has
	# triggered (either the natural coincidence or the _process() fallback
	# — see there), instead of always at the fixed ROTATION_DURATION_SECONDS
	# clock boundary: the whole point of this round's change is that the
	# freeze point is now dynamic, whatever instant the rightmost bead pair
	# naturally lined up with its target. Before that, it's still just
	# _elapsed, rotating continuously (reproducing the reference sketch's
	# `angle += frequency` every frame). Nothing else about the rotation is
	# eased in from a collapsed state — see the constants below.
	var rotation_elapsed: float = _settle_start_elapsed if _settle_triggered else _elapsed
	var st: Dictionary = _rotation_state(rotation_elapsed, num_slots)
	var turns: float = st.turns
	var rotation_angle: float = st.rotation_angle
	var theta: float = st.theta
	var mean_cos: float = st.mean_cos
	var rotation_radius: float = st.rotation_radius

	# No growing-in: every quantity below is a plain constant instead of
	# easing from a collapsed start toward a real/flat target, matching the
	# reference sketch's fixed h/space/size — only rotation animates.
	# rotation_radius is derived directly from the real dna_ribbons_gap
	# (_strand_gap_px), so the pair's resting Y-extent matches the real
	# strand's gap by construction (see ROTATION_RADIUS_RATIO's own
	# comment). bead_radius/bond_width/bond_spacing are pinned to their
	# real final sizes rather than 0/invisible.
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

		# Settle phase: once _process() has triggered it (either the
		# natural rightmost-pair coincidence during the final lap, or the
		# fallback at ROTATION_DURATION_SECONDS — see _process()), each
		# bead individually glides from that shared frozen pose to its
		# real resting Y — center_y -+ _strand_gap_px * 0.5, exactly where
		# the live template_top/template_bottom glyph for this slot
		# actually sits (see player_ui.gd's _play_dna_intro()) — so the
		# fully-settled frame matches the live rail view exactly. Before
		# triggering, settle_elapsed is 0 for every slot (slot_t stays 0).
		# Staggered right to left: stagger_fraction is 0 for the rightmost
		# slot (starts immediately once triggered) and 1 for the leftmost
		# (starts last), scaling automatically with however many beads are
		# loaded so the cascade's total span stays SETTLE_STAGGER_SECONDS
		# regardless of sequence length. slot_t is a literal linear lerp, 0
		# before this slot's delay has elapsed, ramping to 1 over
		# SETTLE_LERP_SECONDS.
		var settle_elapsed: float = max(0.0, _elapsed - _settle_start_elapsed) if _settle_triggered else 0.0
		var stagger_fraction: float = float(num_slots - 1 - slot) / float(num_slots - 1)
		var settle_delay: float = stagger_fraction * SETTLE_STAGGER_SECONDS
		var slot_t: float = clamp((settle_elapsed - settle_delay) / SETTLE_LERP_SECONDS, 0.0, 1.0)
		y_top = lerp(y_top, center_y - _strand_gap_px * 0.5, slot_t)
		y_bottom = lerp(y_bottom, center_y + _strand_gap_px * 0.5, slot_t)

		# Ambient wobble, reproducing simulation.gd's real per-base jitter
		# (get_wobble_y()) — applied last, on top of whatever y_top/y_bottom
		# currently are (still rotating, mid-settle, or fully settled),
		# exactly like the real strand adds it as a final offset over its
		# own resting position. Both beads at a slot use the SAME wobble_y
		# (same index), moving together as a rigid pair rather than
		# independently, matching how the real top/bottom strand calls both
		# pass the same index into get_wobble_y().
		var wobble_y: float = _wobble_y(slot, _wobble_time)
		y_top += wobble_y
		y_bottom += wobble_y

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
