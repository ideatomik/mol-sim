class_name HelicaseAtpCycle
extends Node2D

# ==========================================
# helicase_atp_cycle.gd — the helicase's cofactor-activation lens (ATPCycleDesign.md)
#
# PURE FUNCTION OF TWO FLOATS plus one pre-resolved origin. There is no clock,
# no state, no memory, and no signal subscription in this file. update() alone
# fully determines every bead's pose, exactly as helicase_ring.gd's set_roll()
# does for the barrel roll — which is what makes it scrub-safe for free.
#
# WHY IT IS DERIVED AND NOT EVENT-DRIVEN. helicase.gd's scrub_to_slot() sets
# current_slot_index directly and NEVER emits slot_reached, so any
# signal-triggered spark would be unreconstructible by scrub. Deriving
# everything from (slot_index, step_t) — the same two values helicase_x and
# the barrel roll already derive from — removes the problem rather than
# working around it.
#
# THE EASING TRAP, AND WHY THIS FILE HOLDS NO EASING LOGIC. helicase.gd's
# get_eased_step_t() is a cubic ease-out; raw 0.7 maps to eased 0.973. Testing
# the spawn threshold against the eased value would fire the approach at
# effectively 97% of the step, leaving nothing visible. Rather than share the
# curve with a second consumer, simulation.gd resolves BOTH values at the
# boundary and passes them already in their final space, named for that space.
# The _raw / _eased suffixes on update()'s parameters are load-bearing, not
# decoration: a swapped assignment reads as visibly incoherent rather than
# plausible. Do not add an easing call to this file.
#
# LOCAL SPACE, NOT WORLD SPACE — a recorded divergence from the design doc.
# ATPCycleDesign.md specifies byproduct positions be written via
# global_position, reasoning that ADP recedes while its parent advances and a
# local offset would "carry the parent's own motion in every term." True as
# stated, but simulation.gd already owns helicase_x and can subtract it ONCE,
# at the same boundary where it resolves the easing — so the parent's motion
# is carried in exactly one term, in the file that owns it, and this node
# stays in pure local space. That also means the connector links can be drawn
# without a to_local() round-trip per bead per frame. Same principle the doc
# itself adopted for the easing; applied one step further.
#
# THEMEMANAGER-FREE, matching helicase_ring.gd (its sibling under
# helicase_node) rather than polymerase_clamp.gd. Every value below is pushed
# in by simulation.gd before add_child(). Parenting under helicase_node rather
# than at the scene root is deliberate: it inherits helicase_node.modulate, so
# the end-of-run enzyme fade reaches these beads for free instead of leaving
# them as the one object still on screen.
# ==========================================

# ---------- POOL ----------
# 8 beads, never instantiated or freed during play. Two independent clusters
# of 4, because the generations genuinely overlap: this step's spent ADP + Pi
# are still fading while the next step's whole ATP is already approaching.
# Sharing one cluster of 4 would make any tuning that overlaps the two windows
# silently delete the byproducts — a trap rather than a saving. 8 pooled
# Node2Ds is cheap even under the low-end-hardware constraint.
const SPENT_BEADS: int = 4     # indices 0-3: ADP (head + 2 P) and Pi (1 P)
const WHOLE_BEADS: int = 4     # indices 4-7: whole ATP (head + 3 P)
const BEAD_COUNT: int = SPENT_BEADS + WHOLE_BEADS

# ---------- GLYPH IDENTITY (ThemeManager "Cofactor" group) ----------
var bead_radius: float = 7.0
var adenine_radius: float = 11.0
var bead_spacing: float = 20.0
var bead_color: Color = Color(0.95, 0.80, 0.25, 1.0)
## Pushed as ThemeManager.base_color_a VERBATIM, never as its own field. The
## adenine in ATP IS the adenine in DNA, and that identity is the whole
## pedagogical payoff of sharing the head glyph — so the two colors must
## agree, which means deriving from one authoritative source rather than
## letting a second tunable drift away from it.
var adenine_color: Color = Color(0.8, 0.2, 0.2, 1.0)
var link_color: Color = Color(0.95, 0.80, 0.25, 1.0)
var link_width: float = 4.0
var label_font_size: int = 10
var label_color: Color = Color(1, 1, 1, 1)
var label_font: Font = null
var spark_color: Color = Color(1.0, 0.95, 0.6, 1.0)
var spark_radius: float = 34.0
var spark_width: float = 3.0

# ---------- TIMELINE (ThemeManager "Helicase Ring" group) ----------
## RAW step_t threshold. The approach begins at 70% of the PRIOR step so the
## whole ATP is already docked when the step it fuels begins — the same way
## primase pre-places a primer ahead of where Pol III will need it. The
## helicase's own pace is not touched by any of this.
var spawn_lead_ratio: float = 0.7
## RAW step_t width of the spark's visible band, sitting just past the
## boundary. A width, not a duration: it scales with the speed multiplier, so
## at 8x it may fall below one frame. That is accepted — at 8x the barrel roll
## and nucleotide capture are equally illegible, and a spark that stayed
## prominent while everything else blurred would look wrong.
var spark_window: float = 0.10
## EASED step_t at which ADP and Pi have finished fading. Note this is a
## POSITION ON THE EASED CURVE, not a duration in seconds — the design doc
## called it cofactor_fade_duration, which would have invited someone to pass it a
## number of seconds. Renamed on that basis; a seconds-based fade belongs to
## the ligase pass, whose cycle is genuinely tween-driven.
var byproduct_fade_end_eased: float = 0.9
## Pi escapes forward and UP ("2 o'clock") — spent to drive the motion, as
## against ADP which recedes level and backward, discarded. These two get
## their own tunables rather than reusing slot spacing: the angle is a thing
## to eyeball against the real scene, not a fact about slot geometry.
var pi_x_ratio: float = 0.6
var pi_rise_distance: float = 90.0
## Where the whole ATP drifts in from, in this node's local space. Ahead of
## and above the fork, so it reads as arriving from solution rather than being
## emitted by the DNA. Not specified in the design doc at all — the timeline
## diagram says "spawns, approaches" without ever saying from where.
var approach_offset: Vector2 = Vector2(150.0, -130.0)

# ---------- GEOMETRY PUSHED FROM SIMULATION ----------
## ADP recedes by exactly one slot spacing over the step — equal and opposite
## to the helicase's own advance, which is the visual point. Reuses the
## simulation's real value rather than an independently-tuned lookalike.
var nucleotide_slot_spacing: float = 40.0

# ---------- LIVE FLAGS ----------
## Written every frame by simulation.gd, same idiom as helicase_ring's
## rotation_frozen. Mechanism-vs-waste boundary: this hides DISCARDED
## byproducts only. Ligase's carried AMP and its hop onto the nick are
## mechanism and stay visible regardless — see ATPCycleDesign.md's Toggles.
var byproducts_visible: bool = true

## Glyph counter-rotation for vertical mode, PUSHED in by simulation.gd, same
## contract as helicase_ring.label_counter_rotation. Forwarded to every bead.
var label_counter_rotation: float = 0.0:
	set(value):
		label_counter_rotation = value
		for b in _beads:
			if is_instance_valid(b):
				b.set_label_rotation(value)

# ---------- INTERNAL ----------
var _beads: Array[CofactorBead] = []
## Precomputed in update(), consumed by _draw(). Each entry is
## [from: Vector2, to: Vector2, alpha: float] in this node's local space.
var _links: Array = []
var _spark_alpha: float = 0.0
var _spark_t: float = 0.0

func _ready() -> void:
	_build_pool()

func _build_pool() -> void:
	for b in _beads:
		if is_instance_valid(b):
			b.queue_free()
	_beads.clear()
	for i in range(BEAD_COUNT):
		var bead := CofactorBead.new()
		add_child(bead)
		bead.set_label_style(label_font_size, label_color, label_font)
		bead.set_label_rotation(label_counter_rotation)
		bead.visible = false
		_beads.append(bead)

# ==========================================
# PUBLIC — the entire API
# ==========================================

## `spawn_progress_raw`   — helicase_mgr.get_step_t(), NOT eased.
## `drift_progress_eased` — helicase_mgr.get_eased_step_t().
## `discard_origin_local` — where this step's cleave happened, already
##                          expressed relative to the helicase's current
##                          position by simulation.gd.
## `active`               — the lens is on AND the helicase is actually
##                          stepping (SWEEPING or FINISHING_LAST_PULSE).
func update(spawn_progress_raw: float, drift_progress_eased: float, discard_origin_local: Vector2, active: bool) -> void:
	_links.clear()
	if not active:
		for b in _beads:
			b.visible = false
		_spark_alpha = 0.0
		queue_redraw()
		return

	_update_spent_cluster(drift_progress_eased, discard_origin_local)
	_update_whole_cluster(spawn_progress_raw)
	_update_spark(spawn_progress_raw)
	queue_redraw()

# ==========================================
# INTERNAL
# ==========================================

## ADP and Pi: three simultaneous, opposite-reading motions (counting the
## helicase's own forward glide, which this file does not touch). ADP recedes
## level and backward; Pi escapes forward and up. Both share one fade curve —
## biology argues for staggering them, since Pi release precedes ADP release,
## but the whole drift window is roughly 0.45s at 1x and splitting that is
## likely imperceptible. Deferred deliberately, not overlooked.
func _update_spent_cluster(eased: float, origin: Vector2) -> void:
	var fade_end: float = max(byproduct_fade_end_eased, 0.0001)
	var alpha: float = clamp(1.0 - eased / fade_end, 0.0, 1.0)
	var show: bool = byproducts_visible and alpha > 0.01

	for i in range(SPENT_BEADS):
		_beads[i].visible = show
	if not show:
		return

	var adp_head := Vector2(origin.x - nucleotide_slot_spacing * eased, origin.y)
	var pi_pos := Vector2(
		origin.x + nucleotide_slot_spacing * pi_x_ratio * eased,
		origin.y - pi_rise_distance * eased
	)

	_place_bead(0, adp_head, adenine_radius, adenine_color, "A", alpha)
	_place_bead(1, adp_head + Vector2(bead_spacing, 0.0), bead_radius, bead_color, "P", alpha)
	_place_bead(2, adp_head + Vector2(bead_spacing * 2.0, 0.0), bead_radius, bead_color, "P", alpha)
	_place_bead(3, pi_pos, bead_radius, bead_color, "P", alpha)

	_links.append([_beads[0].position, _beads[1].position, alpha])
	_links.append([_beads[1].position, _beads[2].position, alpha])
	# Pi carries no link on purpose: a single loose bead is what "free
	# inorganic phosphate" has to read as. PPi (ligase's byproduct, next pass)
	# is the opposite case — two beads FUSED by a visibly thicker connector,
	# drifting as one rigid unit, and it must never read as two loose Pi that
	# happen to be adjacent.

## The whole, uncleaved ATP drifting in from solution and docking at the
## helicase. The dock point needs no blob math: the theta=0 blob sits at the
## ring's own local origin, and the ring is a sibling of this node under
## helicase_node — so the dock is simply Vector2.ZERO here.
func _update_whole_cluster(raw: float) -> void:
	var show: bool = raw >= spawn_lead_ratio
	for i in range(SPENT_BEADS, BEAD_COUNT):
		_beads[i].visible = show
	if not show:
		return

	var span: float = max(1.0 - spawn_lead_ratio, 0.0001)
	var approach_t: float = clamp((raw - spawn_lead_ratio) / span, 0.0, 1.0)
	var head: Vector2 = approach_offset.lerp(Vector2.ZERO, approach_t)

	_place_bead(4, head, adenine_radius, adenine_color, "A", 1.0)
	_place_bead(5, head + Vector2(bead_spacing, 0.0), bead_radius, bead_color, "P", 1.0)
	_place_bead(6, head + Vector2(bead_spacing * 2.0, 0.0), bead_radius, bead_color, "P", 1.0)
	_place_bead(7, head + Vector2(bead_spacing * 3.0, 0.0), bead_radius, bead_color, "P", 1.0)

	_links.append([_beads[4].position, _beads[5].position, 1.0])
	_links.append([_beads[5].position, _beads[6].position, 1.0])
	_links.append([_beads[6].position, _beads[7].position, 1.0])

## The spark marks the beta-gamma cleave, pinned to the step boundary itself.
## It precedes the helicase's motion rather than coinciding with it, which is
## an honest dramatization: hydrolysis happens ON the enzyme with nothing yet
## moved, and it is Pi RELEASE that triggers the force-generating change.
##
## Note that helicase.gd's scrub_to_slot() sets step_t to exactly 0.0, which
## always falls inside this window — so every scrub target renders a frozen
## spark plus un-drifted byproducts. That is the honest state for "the cleave
## at this slot" and is kept deliberately, but it does mean the arcade-flash
## reading only exists during live play.
func _update_spark(raw: float) -> void:
	var window: float = max(spark_window, 0.0001)
	if raw >= window:
		_spark_alpha = 0.0
		return
	_spark_t = clamp(raw / window, 0.0, 1.0)
	_spark_alpha = 1.0 - _spark_t

func _place_bead(index: int, pos: Vector2, r: float, fill: Color, text: String, alpha: float) -> void:
	var bead := _beads[index]
	bead.position = pos
	bead.modulate.a = alpha
	bead.configure(r, fill, text)

func _draw() -> void:
	for link in _links:
		var c := link_color
		c.a = link_color.a * float(link[2])
		draw_line(link[0], link[1], c, link_width, true)
	if _spark_alpha > 0.01:
		var sc := spark_color
		sc.a = spark_color.a * _spark_alpha
		# Expanding ring rather than a filled disc: a disc at the dock would
		# occlude the docked ATP it is meant to be cleaving.
		draw_circle(Vector2.ZERO, lerp(spark_radius * 0.35, spark_radius, _spark_t), sc, false, spark_width, true)
