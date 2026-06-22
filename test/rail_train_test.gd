extends Node2D

# ==========================================
# RAIL/TRAIN TEST v49
# Added end-of-run sweep at Phase.DONE transition: any nucleotide
# currently INSIDE the polymerase zone with push direction
# (nucleotide_entered_push_direction=true) gets immediately marked
# COMPLETED and turned magenta. Fixes the Ending Issue where the last
# nucleotide entered the zone mid-push but the simulation ended before
# its full OUTSIDE->INSIDE->OUTSIDE cycle could complete.
# ==========================================

const NewNitrogenBaseScene := preload("res://test/new_nitrogen_base.tscn")

@onready var rail_path: Path2D = $RailPath
@onready var template_strand_original_track: Line2D = $TemplateStrandOriginalTrack
@onready var new_strand_line: Line2D = $NewStrandLine
@onready var synthesis_circle: Node2D = $SynthesisCircle
@onready var synthesis_area: Area2D = $SynthesisCircle/SynthesisArea
@onready var template_strand_new_track: Line2D = $TemplateStrandNewTrack
@onready var new_synthesized_strand_position: Line2D = $NewSynthesizedStrandPosition
@onready var backbone_line: Line2D = $BackboneLine

@export_group("Track Layout")
@export var nucleotide_slot_spacing: float = 60.0
@export var num_nucleotide_slots: int = 24
@export var straight_y: float = 300.0
@export var track_length: float = 1920.0
@export var new_bottom_template_offset: float = 90.0 # gap between TemplateStrandOriginalTrack and TemplateStrandNewTrack (and again to NewSynthesizedStrandPosition)

@export_group("Loop Geometry")
## How deep the trombone loop bulges at its SHALLOWEST point during a pulse cycle (in pixels, below the flat track). The pulse never goes fully flat -- this is the floor it bounces back to before growing again.
@export var loop_floor_depth: float = 15.0
## How deep the trombone loop bulges at its DEEPEST point during a pulse cycle (in pixels, below the flat track). This is the peak of each pulse's depth oscillation.
@export var max_loop_depth: float = 220.0
## The fixed horizontal distance (in pixels) the loop spans between its two anchor points (helicase_x and factory_x) while actively sweeping. Also used as the reference width when scaling the loop's bulge handles.
@export var gap_width: float = 168.0
## UNUSED -- leftover from an earlier 5-point "neck" experiment that was abandoned. Has no effect on the current 3-point loop construction. Safe to ignore or remove.
@export var neck_depth_fraction: float = 0.15
## How wide the loop's bottom (waist) bulges, as a fraction of gap_width, when loop_depth is near its SHALLOWEST (loop_floor_depth) -- the loop is flatter here, so it's safe to flare wider without the curve crossing itself.
@export var waist_flare_shallow: float = 0.45
## How wide the loop's bottom (waist) bulges, as a fraction of gap_width, when loop_depth is near its DEEPEST (max_loop_depth) -- kept narrower here, since a wide flare at maximum depth risks the curve's handles overshooting and crossing itself.
@export var waist_flare_deep: float = 0.22
## Fraction of max_loop_depth a nucleotide_slot's y must reach to count as "genuinely pulled deep into the loop" (the ARMED state, a prerequisite for the magenta TRANSFERRED color trigger). NOT 1.0: only a nucleotide_slot whose .progress happens to sample the curve's exact geometric midpoint ever reaches the full theoretical max_loop_depth -- most template_strand_bottom peak somewhat short of it, so a 1.0 threshold (520px) was confirmed unreachable in practice (no nucleotide_slot ever triggered ARMED). 0.7 (~454px) is comfortably within what real template_strand_bottom actually reach.
@export var armed_depth_fraction: float = 0.7

@export_group("Speeds & Timing")
@export var sweep_speed: float = 90.0
@export var pulse_nucleotide_count: int = 5
@export var fade_duration: float = 0.6
@export var settling_duration: float = 0.5 # how long the curve eases flat instead of snapping instantly at the end of the run -- fixes the "teleport" when transitioning to DONE

@export_group("Nucleotide Slot Visuals (DEPRECATED -- will be replaced by nitrogen_base child)")
@export var nucleotide_slot_size: Vector2 = Vector2(24, 24)
@export var nucleotide_color_even: Color = Color(0.2, 0.6, 0.9)
@export var nucleotide_color_odd: Color = Color(0.9, 0.6, 0.2)
## CURRENTLY UNUSED -- was previously triggered when a nucleotide_slot's fixed spawn x passed factory_x (unzipped_population group), but that trigger fired prematurely for template_strand_bottom that hadn't actually been visually pulled through the loop yet (it compared spawn position, not real position). Removed in favor of nucleotide_color_sequence_complete, which triggers on the genuinely correct NucleotideTransferState.ARMED -> TRANSFERRED transition instead.
@export var nucleotide_color_unzipped: Color = Color(0.0, 1.0, 1.0, 1.0) # full cyan
## Color a nucleotide_slot switches to permanently once it completes the directional two-stage synthesis-circle crossing: PRIMED (touches the polymerase collision area while moving deeper into the loop, y increasing) then COMPLETED (touches it again while moving back out toward the strand, y decreasing). Overrides any other nucleotide_slot color from that point on.
@export var nucleotide_color_sequence_complete: Color = Color(1.0, 0.0, 1.0, 1.0) # full magenta

@export_group("Backbone")
@export var backbone_color: Color = Color(1.0, 0.0, 1.0, 1.0)
@export var backbone_line_width: float = 8.0
@export var backbone_offset_distance: float = 12.0 # half the nucleotide_slot's size by default -- puts the line at the nucleotide_slot's edge, not through its center
@export var backbone_offset_smoothing_speed: float = 10.0 # how fast the backbone's per-nucleotide_slot y offset lerps toward its target -- higher = snappier, lower = smoother/slower. Set very high (e.g. 1000) to effectively disable smoothing.

@export_group("Bond Marks")
@export var bond_mark_width: float = 14.0
@export var bond_mark_black_color: Color = Color(0.0, 0.0, 0.0, 1.0)
@export var bond_mark_back_inset: float = 6.3 # how far the magenta diamond's back point sits inward from the black diamond's -- this distance IS the visible ">" sliver's depth (was "w * 0.45"; now an absolute value so it doesn't silently rescale if bond_mark_width changes)

@export_group("Synthesis Circle")
@export var synthesis_circle_color: Color = Color(1.0, 0.85, 0.1)
@export var synthesis_circle_radius: float = 16.0
## Distance threshold (from synthesis_circle's center) a nucleotide's center must drop BELOW to count as having genuinely entered the polymerase, for the new distance-based pass-counting system (replaces raw area_entered signal counting, which was confirmed too noisy -- same nucleotide could re-trigger 4-7 times per real visual pass due to edge/corner grazing).
@export var synthesis_inside_threshold: float = 16.0
## Distance threshold a nucleotide's center must rise ABOVE to count as having fully exited again, before the NEXT entry can register as a new genuine pass. Deliberately larger than synthesis_inside_threshold (hysteresis band) so a nucleotide hovering right at one single boundary value doesn't flicker between states.
@export var synthesis_outside_threshold: float = 24.0

var new_bottom_template_y: float = 0.0
var new_synthesized_strand_y: float = 0.0
var new_strand_y: float = 0.0
var synthesis_circle_y: float = 0.0
var pulse_width: float = 0.0

var synthesis_circle_faded: bool = false

var helicase_x: float = 0.0
var factory_x: float = 0.0

enum Phase { SWEEPING, FINISHING_LAST_PULSE, SETTLING, DONE }
var phase: Phase = Phase.SWEEPING

var pulse_time_budget: float = 0.0
var pulse_speed: float = 0.0

enum PulseState { GROWING, SHRINKING, DONE }
var pulse_state: PulseState = PulseState.GROWING

var pulse_offset: float = 0.0

var population_left_edge: float = 0.0

var loop_depth: float = 0.0

var loop_length: float = 0.0
const LOOP_POPULATION_GROUP := "loop_population"
const UNZIPPED_POPULATION_GROUP := "unzipped_population"

var template_strand_bottom: Array[PathFollow2D] = []
var nucleotide_bases: Array[NewNitrogenBase] = [] # parallel to template_strand_bottom; replaces the removed ColorRect-based nucleotide_slot_visuals
var nucleotide_original_x: Array[float] = []

enum NucleotideTransferState { WAITING, ARMED, TRANSFERRED }
var nucleotide_transfer_state: Array[NucleotideTransferState] = []
var nucleotide_max_y_reached: Array[float] = []
var nucleotide_previous_y: Array[float] = []
var nucleotide_crossing_count: Array[int] = [] # total number of GENUINE passes near the polymerase (distance-based, hysteresis-debounced) -- replaces the old raw area_entered signal count, which was confirmed too noisy (same nucleotide could re-trigger 4-7 times per real visual pass)

# Per-nucleotide x position from the previous frame -- used to determine
# the nucleotide's x-direction at the moment it enters the polymerase's
# inner threshold zone. Updated every frame at the END of the loop body,
# after all proximity checks have run (safe to do every frame here since
# this is entirely within _process(), no physics signal cross-frame issues).
var nucleotide_previous_x: Array[float] = []

# Whether the most recent OUTSIDE->INSIDE transition happened while the
# nucleotide was moving LEFT (decreasing x, toward factory_x) -- the
# push/synthesis direction. Set at the moment of entry; read at the
# moment of exit to decide whether this pass counts as the synthesis event.
var nucleotide_entered_push_direction: Array[bool] = []

# PROXIMITY STATE (new): tracks whether each nucleotide's center is
# currently OUTSIDE or INSIDE the polymerase's inner threshold distance,
# checked every frame via direct distance math -- not via the area_entered
# signal at all. A genuine pass is counted on the OUTSIDE->INSIDE->OUTSIDE
# full cycle (specifically, counted at the moment it re-exits past
# synthesis_outside_threshold, confirming it was genuinely INSIDE at some
# point first).
enum ProximityState { OUTSIDE, INSIDE }
var nucleotide_proximity_state: Array[ProximityState] = []

# COMPLETION STATE (simplified, no PRIMED/direction distinction for this
# test round, per instruction to validate the simpler version first):
# NONE until the 3rd genuine pass is reached, then COMPLETED (magenta),
# permanently.
enum SynthesisCrossState { NONE, COMPLETED }
var nucleotide_synthesis_state: Array[SynthesisCrossState] = []

var nucleotide_backbone_delta: Array[float] = []

var baseline_switched: bool = false
var baseline_switch_nucleotide_index: int = -1

var settling_t: float = 0.0
var settling_loop_depth_start: float = 0.0
var settle_blend: float = 0.0

var bond_marks: Array[Node2D] = []

func _ready():
	new_bottom_template_y = straight_y + new_bottom_template_offset
	new_synthesized_strand_y = new_bottom_template_y + new_bottom_template_offset
	new_strand_y = straight_y + max_loop_depth + nucleotide_slot_size.y
	synthesis_circle_y = straight_y + max_loop_depth
	pulse_width = pulse_nucleotide_count * nucleotide_slot_spacing

	helicase_x = gap_width
	factory_x = 0.0
	loop_depth = max_loop_depth

	pulse_time_budget = pulse_width / sweep_speed
	pulse_speed = (2.0 * pulse_width) / pulse_time_budget

	_rebuild_rail()
	_spawn_nucleotide_slots()
	_setup_synthesis_circle()

	template_strand_original_track.visible = true

	template_strand_new_track.points = PackedVector2Array([
		Vector2(0, new_bottom_template_y),
		Vector2(track_length, new_bottom_template_y)
	])
	template_strand_new_track.visible = true

	new_synthesized_strand_position.points = PackedVector2Array([
		Vector2(0, new_synthesized_strand_y),
		Vector2((factory_x + helicase_x) / 2.0, new_synthesized_strand_y)
	])
	new_synthesized_strand_position.visible = true

	backbone_line.default_color = backbone_color
	backbone_line.width = backbone_line_width
	backbone_line.z_index = -1
	backbone_line.joint_mode = Line2D.LINE_JOINT_ROUND
	backbone_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	backbone_line.end_cap_mode = Line2D.LINE_CAP_ROUND

	print("=== RUN START === baseline_switched:%s pulse_nucleotide_count:%d" % [baseline_switched, pulse_nucleotide_count])

func _process(delta):
	match phase:
		Phase.SWEEPING:
			helicase_x += sweep_speed * delta
			factory_x = helicase_x - gap_width
			match pulse_state:
				PulseState.GROWING:
					pulse_offset = min(pulse_offset + pulse_speed * delta, pulse_width)
					if pulse_offset >= pulse_width:
						pulse_state = PulseState.SHRINKING
				PulseState.SHRINKING:
					pulse_offset = max(pulse_offset - pulse_speed * delta, 0.0)
					if pulse_offset <= 0.0:
						pulse_state = PulseState.GROWING
				PulseState.DONE:
					pulse_offset = 0.0
			var pulse_ratio = pulse_offset / pulse_width
			loop_depth = lerp(loop_floor_depth, max_loop_depth, pulse_ratio)
			population_left_edge = factory_x - pulse_offset
			var last_nucleotide_x = nucleotide_original_x[nucleotide_original_x.size() - 1]
			if factory_x > last_nucleotide_x:
				phase = Phase.FINISHING_LAST_PULSE
		Phase.FINISHING_LAST_PULSE:
			match pulse_state:
				PulseState.GROWING:
					pulse_offset = min(pulse_offset + pulse_speed * delta, pulse_width)
					if pulse_offset >= pulse_width:
						pulse_state = PulseState.SHRINKING
				PulseState.SHRINKING:
					pulse_offset = max(pulse_offset - pulse_speed * delta, 0.0)
					if pulse_offset <= 0.0:
						pulse_state = PulseState.GROWING
				PulseState.DONE:
					pulse_offset = 0.0
			var pulse_ratio2 = pulse_offset / pulse_width
			loop_depth = lerp(loop_floor_depth, max_loop_depth, pulse_ratio2)
			population_left_edge = factory_x - pulse_offset
			var all_settled = baseline_switched
			if all_settled:
				for i in range(template_strand_bottom.size()):
					if abs(template_strand_bottom[i].position.y - new_bottom_template_y) > 2.0:
						all_settled = false
						break
			if all_settled:
				settling_t = 0.0
				settling_loop_depth_start = loop_depth
				phase = Phase.SETTLING
		Phase.SETTLING:
			settling_t += delta
			var t = clamp(settling_t / settling_duration, 0.0, 1.0)
			var eased_t = smoothstep(0.0, 1.0, t)
			loop_depth = lerp(settling_loop_depth_start, 0.0, eased_t)
			settle_blend = eased_t
			if t >= 1.0:
				loop_depth = 0.0
				settle_blend = 1.0
				phase = Phase.DONE
				# FINAL SWEEP: catch any nucleotide that was mid-push
				# inside the polymerase zone when the simulation ended --
				# confirmed via log that the last nucleotide enters the
				# zone with moving_left=true but never completes its
				# OUTSIDE->INSIDE->OUTSIDE cycle because the run ends
				# first. If it entered in the push direction, it's close
				# enough to "synthesized" for educational purposes.
				for j in range(template_strand_bottom.size()):
					if nucleotide_proximity_state[j] == ProximityState.INSIDE \
					and nucleotide_entered_push_direction[j] \
					and nucleotide_synthesis_state[j] == SynthesisCrossState.NONE:
						nucleotide_synthesis_state[j] = SynthesisCrossState.COMPLETED
						nucleotide_bases[j].set_body_color(nucleotide_color_sequence_complete)
						print("[t=%s] nucleotide_slot[%d] COMPLETED via end-of-run sweep (was mid-push at DONE)" % [
							Time.get_ticks_msec(), j
						])
		Phase.DONE:
			settle_blend = 1.0
			if not synthesis_circle_faded:
				synthesis_circle_faded = true
				var fade_tween = create_tween()
				fade_tween.tween_property(synthesis_circle, "modulate:a", 0.0, fade_duration)

	_rebuild_rail()

	synthesis_circle.position = Vector2(factory_x, new_bottom_template_y)

	var new_strand_tracking_x = (factory_x + helicase_x) / 2.0
	new_synthesized_strand_position.points = PackedVector2Array([
		Vector2(0, new_synthesized_strand_y),
		Vector2(new_strand_tracking_x, new_synthesized_strand_y)
	])

	for i in range(template_strand_bottom.size()):
		template_strand_bottom[i].progress = track_length - nucleotide_original_x[i]

	for i in range(template_strand_bottom.size()):
		var nucleotide_y = template_strand_bottom[i].position.y

		if nucleotide_y > nucleotide_max_y_reached[i]:
			nucleotide_max_y_reached[i] = nucleotide_y

		if not baseline_switched and nucleotide_y >= new_bottom_template_y:
			baseline_switched = true
			baseline_switch_nucleotide_index = i
			print(">>> BASELINE SWITCH TRIGGERED by nucleotide_slot[%d] at y=%.1f (t=%s) <<<" % [i, nucleotide_y, Time.get_ticks_msec()])

		match nucleotide_transfer_state[i]:
			NucleotideTransferState.WAITING:
				if nucleotide_max_y_reached[i] >= straight_y + max_loop_depth * armed_depth_fraction:
					nucleotide_transfer_state[i] = NucleotideTransferState.ARMED
					print("[t=%s] nucleotide_slot[%d] ARMED (max_y_reached=%.1f)" % [Time.get_ticks_msec(), i, nucleotide_max_y_reached[i]])
			NucleotideTransferState.ARMED:
				if nucleotide_y < new_bottom_template_y:
					nucleotide_transfer_state[i] = NucleotideTransferState.TRANSFERRED
					print("[t=%s] nucleotide_slot[%d] TRANSFERRED (y=%.1f)" % [Time.get_ticks_msec(), i, nucleotide_y])
			NucleotideTransferState.TRANSFERRED:
				pass

		# NOTE: previous_y update REMOVED from here (v41 fix) -- updating
		# it unconditionally every single frame meant that by the time
		# _on_synthesis_area_entered() (a physics-step signal) fired and
		# read it, _process() had already overwritten it to match the
		# CURRENT position, making y == previous_y always (confirmed by
		# diagnostic log: every single collision showed them exactly
		# equal). The comparison snapshot now lives entirely inside
		# _on_synthesis_area_entered() itself -- captured only at the
		# moment of each collision, compared against the PREVIOUS
		# collision's snapshot for that same nucleotide, not against a
		# continuously-refreshed per-frame value.

		# DISTANCE-BASED GENUINE PASS DETECTION (replaces raw
		# area_entered signal counting, confirmed too noisy -- same
		# nucleotide could re-trigger 4-7 times per real visual pass due
		# to shape-edge grazing). Checked every frame via direct distance
		# math between the nucleotide's center and synthesis_circle's
		# center, with hysteresis (separate inside/outside thresholds) so
		# a nucleotide hovering right at one boundary doesn't flicker.
		# Skip proximity state updates entirely once completed -- nothing
		# to gain from continuing to count passes after magenta is set,
		# and it was confirmed producing spurious pass #3 logs for
		# nucleotides that had already correctly completed on pass #2.
		if nucleotide_synthesis_state[i] == SynthesisCrossState.COMPLETED:
			continue

		var current_x = template_strand_bottom[i].position.x
		var distance_to_polymerase = template_strand_bottom[i].position.distance_to(synthesis_circle.position)
		match nucleotide_proximity_state[i]:
			ProximityState.OUTSIDE:
				if distance_to_polymerase < synthesis_inside_threshold:
					nucleotide_proximity_state[i] = ProximityState.INSIDE
					# Snapshot x-direction at the moment of entry --
					# this is the real push/pull signal. Moving LEFT
					# (x decreasing, toward factory_x) = push/synthesis.
					# Moving RIGHT (x increasing, away from factory_x)
					# = pull direction, not the synthesis event.
					var moving_left = current_x < nucleotide_previous_x[i]
					nucleotide_entered_push_direction[i] = moving_left
					print("[t=%s] nucleotide_slot[%d] ENTERED polymerase zone (moving_left=%s x=%.1f prev_x=%.1f)" % [
						Time.get_ticks_msec(), i, moving_left, current_x, nucleotide_previous_x[i]
					])
			ProximityState.INSIDE:
				if distance_to_polymerase > synthesis_outside_threshold:
					nucleotide_proximity_state[i] = ProximityState.OUTSIDE
					nucleotide_crossing_count[i] += 1
					print("[t=%s] nucleotide_slot[%d] GENUINE PASS #%d push=%s (distance=%.1f)" % [
						Time.get_ticks_msec(), i, nucleotide_crossing_count[i],
						nucleotide_entered_push_direction[i], distance_to_polymerase
					])
					# Only trigger magenta if this pass was in the PUSH
					# direction (nucleotide moving left, from loop toward
					# factory_x / new strand). Pull-direction passes
					# are just the nucleotide being drawn INTO the loop
					# and don't represent synthesis.
					if nucleotide_entered_push_direction[i] and nucleotide_synthesis_state[i] == SynthesisCrossState.NONE:
						nucleotide_synthesis_state[i] = SynthesisCrossState.COMPLETED
						nucleotide_bases[i].set_body_color(nucleotide_color_sequence_complete)
						print("[t=%s] nucleotide_slot[%d] COMPLETED on pass #%d PUSH (magenta)" % [
							Time.get_ticks_msec(), i, nucleotide_crossing_count[i]
						])

		# Update x snapshot AFTER proximity check so next frame can compare
		# against this frame's position -- same pattern as nucleotide_previous_y.
		nucleotide_previous_x[i] = current_x


	for i in range(template_strand_bottom.size()):
		var nucleotide_slot = template_strand_bottom[i]
		var x = nucleotide_original_x[i]
		var in_loop = (phase != Phase.DONE) and x >= population_left_edge and x <= helicase_x

		if in_loop and not nucleotide_slot.is_in_group(LOOP_POPULATION_GROUP):
			nucleotide_slot.add_to_group(LOOP_POPULATION_GROUP)
		elif not in_loop and nucleotide_slot.is_in_group(LOOP_POPULATION_GROUP):
			nucleotide_slot.remove_from_group(LOOP_POPULATION_GROUP)

	var backbone_points = PackedVector2Array()
	for i in range(template_strand_bottom.size()):
		var nucleotide_slot = template_strand_bottom[i]
		var on_rail_visual = abs(nucleotide_slot.position.y - straight_y) < 1.0
		var on_new_bottom = abs(nucleotide_slot.position.y - new_bottom_template_y) < 1.0
		var target_delta: float
		if on_rail_visual:
			target_delta = backbone_offset_distance
		elif on_new_bottom:
			target_delta = -backbone_offset_distance
		else:
			target_delta = backbone_offset_distance

		nucleotide_backbone_delta[i] = lerp(nucleotide_backbone_delta[i], target_delta, clamp(backbone_offset_smoothing_speed * delta, 0.0, 1.0))
		backbone_points.append(Vector2(nucleotide_slot.position.x, nucleotide_slot.position.y + nucleotide_backbone_delta[i]))

	backbone_line.points = backbone_points
	# FIX: width was only ever set once, in _ready() -- tweaking
	# backbone_line_width live in the Inspector during a running scene
	# never visually updated, since nothing re-applied it after startup.
	# default_color, by contrast, only needs setting once since Line2D
	# re-reads it every frame internally for rendering -- but width is a
	# Line2D property we were never re-pushing. Re-applying here, same
	# place points itself gets updated every frame, fixes this.
	backbone_line.width = backbone_line_width

	_update_bond_marks(backbone_points)

func _update_bond_marks(points: PackedVector2Array):
	var needed = max(0, points.size() - 1)
	while bond_marks.size() < needed:
		bond_marks.append(_create_bond_mark_sprite())
	while bond_marks.size() > needed:
		var extra = bond_marks.pop_back()
		extra.queue_free()

	for i in range(needed):
		var a = points[i]
		var b = points[i + 1]
		var mid = (a + b) / 2.0
		var segment = b - a
		var mark = bond_marks[i]
		mark.position = mid
		if segment.length() > 0.0:
			mark.rotation = segment.angle()
			mark.visible = true
		else:
			mark.visible = false

func _create_bond_mark_sprite() -> Node2D:
	var holder = Node2D.new()
	var h = backbone_line_width / 2.0
	var w = bond_mark_width

	var black_diamond = Polygon2D.new()
	black_diamond.polygon = PackedVector2Array([
		Vector2(w / 2.0, 0),
		Vector2(0, -h),
		Vector2(-w / 2.0, 0),
		Vector2(0, h),
	])
	black_diamond.color = bond_mark_black_color
	holder.add_child(black_diamond)

	var back_inset = bond_mark_back_inset
	var magenta_diamond = Polygon2D.new()
	magenta_diamond.polygon = PackedVector2Array([
		Vector2(w / 2.0, 0),
		Vector2(0, -h),
		Vector2(-w / 2.0 + back_inset, 0),
		Vector2(0, h),
	])
	magenta_diamond.color = backbone_color
	holder.add_child(magenta_diamond)

	holder.z_index = 1
	add_child(holder)
	return holder

func _rebuild_rail():
	if phase == Phase.DONE:
		var flat_curve = Curve2D.new()
		var rest_y = new_bottom_template_y if baseline_switched else straight_y
		flat_curve.add_point(Vector2(track_length, rest_y))
		flat_curve.add_point(Vector2(0, rest_y))
		loop_length = 0.0
		rail_path.curve = flat_curve
		template_strand_original_track.points = flat_curve.get_baked_points()
		return

	var curve = Curve2D.new()
	var blended_straight_y = lerp(straight_y, new_bottom_template_y, settle_blend) if baseline_switched else straight_y

	curve.add_point(Vector2(track_length, blended_straight_y))
	curve.add_point(Vector2(helicase_x, blended_straight_y))

	var bulge_y = blended_straight_y + loop_depth
	var handle_x = max(40.0, loop_depth * 0.6)

	curve.add_point(
		Vector2(helicase_x, blended_straight_y),
		Vector2.ZERO,
		Vector2(-handle_x, loop_depth * 0.5)
	)
	var mid_x = (factory_x + helicase_x) / 2.0
	var depth_ratio = loop_depth / gap_width
	var max_depth_ratio = max_loop_depth / gap_width
	var flare_t = clamp(depth_ratio / max_depth_ratio, 0.0, 1.0) if max_depth_ratio > 0.0 else 0.0
	var omega_flare = lerp(waist_flare_shallow, waist_flare_deep, flare_t)
	var mid_handle_x = max(1.0, (helicase_x - factory_x) * omega_flare)

	curve.add_point(
		Vector2(mid_x, bulge_y),
		Vector2(mid_handle_x, 0),
		Vector2(-mid_handle_x, 0)
	)

	var anchor_rest_y = new_bottom_template_y if baseline_switched else blended_straight_y

	curve.add_point(
		Vector2(factory_x, anchor_rest_y),
		Vector2(handle_x, loop_depth * 0.5),
		Vector2.ZERO
	)

	var loop_only_curve = Curve2D.new()
	loop_only_curve.add_point(
		Vector2(helicase_x, blended_straight_y),
		Vector2.ZERO,
		Vector2(-handle_x, loop_depth * 0.5)
	)
	loop_only_curve.add_point(
		Vector2(mid_x, bulge_y),
		Vector2(mid_handle_x, 0),
		Vector2(-mid_handle_x, 0)
	)
	loop_only_curve.add_point(
		Vector2(factory_x, anchor_rest_y),
		Vector2(handle_x, loop_depth * 0.5),
		Vector2.ZERO
	)
	loop_length = loop_only_curve.get_baked_length()

	curve.add_point(Vector2(0, anchor_rest_y))

	rail_path.curve = curve
	template_strand_original_track.points = curve.get_baked_points()

func _setup_synthesis_circle():
	# FIX: synthesis_circle had no z_index set (defaults to 0), while the
	# bond mark diamonds (_create_bond_mark_sprite) use z_index=1 -- so
	# the diamonds rendered OVER the circle. Set to 2, above both the
	# bond marks and the backbone line (z_index=-1).
	synthesis_circle.z_index = 2

	var poly = Polygon2D.new()
	var points = PackedVector2Array()
	const SEGMENTS = 32
	for i in range(SEGMENTS):
		var angle = (float(i) / SEGMENTS) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * synthesis_circle_radius)
	poly.polygon = points
	poly.color = synthesis_circle_color
	synthesis_circle.add_child(poly)

	var synthesis_collision_shape = synthesis_area.get_node("SynthesisCollisionShape")
	var circle_shape = CircleShape2D.new()
	circle_shape.radius = synthesis_circle_radius
	synthesis_collision_shape.shape = circle_shape
	synthesis_area.monitoring = true
	synthesis_area.monitorable = true
	synthesis_area.area_entered.connect(_on_synthesis_area_entered)
	print("[SETUP] synthesis_area ready: monitoring=%s monitorable=%s shape_radius=%.1f collision_layer=%d collision_mask=%d" % [
		synthesis_area.monitoring, synthesis_area.monitorable, circle_shape.radius,
		synthesis_area.collision_layer, synthesis_area.collision_mask
	])

func _on_synthesis_area_entered(area: Area2D):
	# SIMPLIFIED (v44): the raw area_entered signal is no longer used for
	# pass-counting or the magenta trigger at all -- confirmed too noisy
	# (same nucleotide could re-trigger 4-7 times per real visual pass due
	# to shape-edge grazing). That logic moved to a per-frame
	# distance-based check in _process() instead. Kept here only for the
	# UNZIPPED_POPULATION_GROUP membership (still a reasonable coarse
	# signal for "has been near the polymerase at all") and the raw signal
	# print, in case it's still useful to compare against the new genuine
	# pass count.
	print("[t=%s] SYNTHESIS AREA ENTERED by: %s" % [Time.get_ticks_msec(), area.name])

	if not area.name.begins_with("NucleotideArea_"):
		return
	var nucleotide_index = int(area.name.substr("NucleotideArea_".length()))
	if nucleotide_index < 0 or nucleotide_index >= template_strand_bottom.size():
		return

	var nucleotide_slot = template_strand_bottom[nucleotide_index]
	if not nucleotide_slot.is_in_group(UNZIPPED_POPULATION_GROUP):
		nucleotide_slot.add_to_group(UNZIPPED_POPULATION_GROUP)

func _spawn_nucleotide_slots():
	var row_span = (num_nucleotide_slots - 1) * nucleotide_slot_spacing
	var row_start_x = (track_length - row_span) / 2.0

	for i in range(num_nucleotide_slots):
		var nucleotide_slot = PathFollow2D.new()
		nucleotide_slot.rotates = false
		nucleotide_slot.loop = false

		var nucleotide_area = Area2D.new()
		nucleotide_area.name = "NucleotideArea_%d" % i
		nucleotide_area.monitoring = true
		nucleotide_area.monitorable = true
		var nucleotide_collision_shape = CollisionShape2D.new()
		var nucleotide_shape = RectangleShape2D.new()
		nucleotide_shape.size = nucleotide_slot_size
		nucleotide_collision_shape.shape = nucleotide_shape
		nucleotide_area.add_child(nucleotide_collision_shape)
		nucleotide_slot.add_child(nucleotide_area)

		# NEW NITROGEN BASE (v38/v39): instantiate the user-built template
		# scene as a child of this slot -- positioned at the slot's own
		# origin (default Vector2.ZERO offset), so it rides exactly
		# wherever the slot's PathFollow2D places it. stay_frozen=true
		# (the template's default) keeps it purely positional for now.
		# Reference stored in nucleotide_bases[] (replaces the removed
		# ColorRect-based nucleotide_slot_visuals[]) so later code (the
		# magenta synthesis-completion trigger) can call set_body_color().
		#
		# FIX: previously force-applied an even/odd blue/orange color here
		# unconditionally, silently overriding whatever body_color the
		# user configured directly in the template scene's Inspector
		# (e.g. #cc0064) -- every instance, every time. Removed entirely;
		# each instance now simply keeps the template's own configured
		# default, exactly as intended when the template scene was set up
		# specifically so the Inspector could control this.
		var nitrogen_base: NewNitrogenBase = NewNitrogenBaseScene.instantiate()
		nucleotide_slot.add_child(nitrogen_base)
		nucleotide_bases.append(nitrogen_base)
		# Label now shows the nucleotide's index (was "X") -- makes it
		# possible to identify and track a specific nucleotide across
		# screenshots, which the X placeholder didn't allow.
		nitrogen_base.set_label_text(str(i))

		rail_path.add_child(nucleotide_slot)

		var x = row_start_x + i * nucleotide_slot_spacing
		nucleotide_original_x.append(x)
		nucleotide_slot.progress = track_length - x
		template_strand_bottom.append(nucleotide_slot)
		nucleotide_transfer_state.append(NucleotideTransferState.WAITING)
		nucleotide_max_y_reached.append(straight_y)
		nucleotide_previous_y.append(straight_y)
		nucleotide_crossing_count.append(0)
		nucleotide_proximity_state.append(ProximityState.OUTSIDE)
		nucleotide_previous_x.append(x)
		nucleotide_entered_push_direction.append(false)
		nucleotide_synthesis_state.append(SynthesisCrossState.NONE)
		nucleotide_backbone_delta.append(backbone_offset_distance)
