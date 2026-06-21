extends Node2D

# ==========================================
# RAIL/TRAIN TEST v36
# FIXED a real "permanent skip" bug: the ARMED check compared
# INSTANTANEOUS car_y against a fixed threshold, but the pulse is a
# triangle wave with a fixed period (pulse_car_count car-widths) -- cars
# whose transit through the loop happened to align with the shallower
# portion of a cycle could NEVER satisfy that check, no matter how long
# the simulation ran. Confirmed empirically: cars 0, 1, 6, 7, 12, 13, 18,
# 19 never triggered ARMED at all, a predictable "2 skipped every 6 cars"
# pattern matching pulse_car_count exactly. Now checks car_max_y_reached
# (each car's TRUE historical peak, already tracked but previously
# unused for this) instead of the instantaneous value -- guarantees every
# car eventually qualifies once its real peak clears the threshold,
# regardless of pulse timing.
# ==========================================

@onready var rail_path: Path2D = $RailPath
@onready var rail_visual: Line2D = $RailVisual
@onready var new_strand_line: Line2D = $NewStrandLine
@onready var synthesis_circle: Node2D = $SynthesisCircle
@onready var new_bottom_template_strand_position: Line2D = $NewBottomTemplateStrandPosition
@onready var new_synthesized_strand_position: Line2D = $NewSynthesizedStrandPosition
@onready var backbone_line: Line2D = $BackboneLine

# ==========================================
# INSPECTOR-EXPOSED TUNABLES
# Every color, size, thickness, and speed value lives here, grouped by
# purpose, so future tweaks happen in the Inspector instead of hunting
# through code. Anything purely structural/logical (group name strings,
# enums) stays as a plain const further below, since those aren't meant
# to be tuned.
# ==========================================

@export_group("Track Layout")
@export var car_spacing: float = 60.0
@export var num_cars: int = 24
@export var straight_y: float = 300.0
@export var track_length: float = 1920.0
@export var new_bottom_template_offset: float = 90.0 # gap between RailVisual and NewBottomTemplateStrandPosition (and again to NewSynthesizedStrandPosition)

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
## Fraction of max_loop_depth a car's y must reach to count as "genuinely pulled deep into the loop" (the ARMED state, a prerequisite for the magenta TRANSFERRED color trigger). NOT 1.0: only a car whose .progress happens to sample the curve's exact geometric midpoint ever reaches the full theoretical max_loop_depth -- most cars peak somewhat short of it, so a 1.0 threshold (520px) was confirmed unreachable in practice (no car ever triggered ARMED). 0.7 (~454px) is comfortably within what real cars actually reach.
@export var armed_depth_fraction: float = 0.7

@export_group("Speeds & Timing")
@export var sweep_speed: float = 90.0
@export var pulse_car_count: int = 5
@export var fade_duration: float = 0.6
@export var settling_duration: float = 0.5 # how long the curve eases flat instead of snapping instantly at the end of the run -- fixes the "teleport" when transitioning to DONE

@export_group("Car Visuals")
@export var car_size: Vector2 = Vector2(24, 24)
@export var car_color_even: Color = Color(0.2, 0.6, 0.9)
@export var car_color_odd: Color = Color(0.9, 0.6, 0.2)
## CURRENTLY UNUSED -- was previously triggered when a car's fixed spawn x passed factory_x (unzipped_population group), but that trigger fired prematurely for cars that hadn't actually been visually pulled through the loop yet (it compared spawn position, not real position). Removed in favor of car_color_sequence_complete, which triggers on the genuinely correct CarTransferState.ARMED -> TRANSFERRED transition instead.
@export var car_color_unzipped: Color = Color(0.0, 1.0, 1.0, 1.0) # full cyan
## Color a car switches to permanently once it completes the genuine ARMED->TRANSFERRED transition: pulled deep into the loop (reaching straight_y+max_loop_depth), then pushed onto NewBottomTemplateStrandPosition -- the real, position-based "passed through the polymerase" event. Overrides any other car color from that point on.
@export var car_color_sequence_complete: Color = Color(1.0, 0.0, 1.0, 1.0) # full magenta

@export_group("Backbone")
@export var backbone_color: Color = Color(1.0, 0.0, 1.0, 1.0)
@export var backbone_line_width: float = 8.0
@export var backbone_offset_distance: float = 12.0 # half the car's size by default -- puts the line at the car's edge, not through its center
@export var backbone_offset_smoothing_speed: float = 10.0 # how fast the backbone's per-car y offset lerps toward its target -- higher = snappier, lower = smoother/slower. Set very high (e.g. 1000) to effectively disable smoothing.

@export_group("Bond Marks")
@export var bond_mark_width: float = 14.0
@export var bond_mark_black_color: Color = Color(0.0, 0.0, 0.0, 1.0)
@export var bond_mark_back_inset: float = 6.3 # how far the magenta diamond's back point sits inward from the black diamond's -- this distance IS the visible ">" sliver's depth (was "w * 0.45"; now an absolute value so it doesn't silently rescale if bond_mark_width changes)

@export_group("Synthesis Circle")
@export var synthesis_circle_color: Color = Color(1.0, 0.85, 0.1)
@export var synthesis_circle_radius: float = 16.0

# ==========================================
# DERIVED VALUES (computed once in _ready() from the exports above) and
# internal state -- not meant to be tuned directly.
# ==========================================

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

var cars: Array[PathFollow2D] = []
var car_visuals: Array[ColorRect] = [] # parallel to cars[], for direct color changes (e.g. cyan once unzipped) without searching the scene tree each frame
var car_original_x: Array[float] = []

enum CarTransferState { WAITING, ARMED, TRANSFERRED }
var car_transfer_state: Array[CarTransferState] = []
var car_max_y_reached: Array[float] = []

# BACKBONE FLICKER FIX: per-car smoothed y_delta, lerped toward whatever
# the classification (on_rail_visual / on_new_bottom / in-loop) currently
# targets, instead of snapping instantly. A car hovering right at one of
# the < 1.0 classification thresholds can flip between two OPPOSITE-SIGN
# deltas frame to frame (e.g. +12 on RailVisual vs -12 on
# NewBottomTemplateStrandPosition), which reads as flicker. Smoothing the
# applied delta (not the classification itself) keeps the visual
# transition gradual without touching the classification logic.
var car_backbone_delta: Array[float] = []

var baseline_switched: bool = false
var baseline_switch_car_index: int = -1

# SETTLING PHASE: eases the curve flat over settling_duration instead of
# snapping instantly. settling_t tracks progress (0 to settling_duration);
# the *_start values capture loop_depth/factory_x/helicase_x at the moment
# settling begins, so we can lerp FROM the actual current geometry TO the
# final flat target, rather than from some arbitrary fixed starting point.
var settling_t: float = 0.0
var settling_loop_depth_start: float = 0.0
# Blends the WHOLE curve's y-coordinates toward the final flat target
# (new_bottom_template_y everywhere) as SETTLING progresses -- 0 during
# normal operation/SWEEPING/FINISHING_LAST_PULSE, eases to 1 by the end of
# SETTLING. Needed because loop_depth alone reaching 0 doesn't make the
# curve match Phase.DONE's flat construction: the anchor_rest_y step
# (straight_y -> new_bottom_template_y) is independent of loop_depth and
# was never eased, causing a real ~27px single-frame jump at the
# SETTLING->DONE boundary (confirmed by frame-by-frame log).
var settle_blend: float = 0.0

# PHOSPHODIESTER BOND MARKS: one Node2D (holding a Polygon2D placeholder
# ">" shape) per bond/segment, created lazily in _update_bond_marks(),
# repositioned and rotated every frame to track the backbone.
var bond_marks: Array[Node2D] = []

func _ready():
	# Compute derived values from the exported tunables FIRST -- everything
	# below this point (curve building, car spawning, etc.) depends on them.
	new_bottom_template_y = straight_y + new_bottom_template_offset
	new_synthesized_strand_y = new_bottom_template_y + new_bottom_template_offset
	new_strand_y = straight_y + max_loop_depth + car_size.y
	synthesis_circle_y = straight_y + max_loop_depth
	pulse_width = pulse_car_count * car_spacing

	helicase_x = gap_width
	factory_x = 0.0
	loop_depth = max_loop_depth

	pulse_time_budget = pulse_width / sweep_speed
	pulse_speed = (2.0 * pulse_width) / pulse_time_budget

	_rebuild_rail()
	_spawn_cars()
	_setup_synthesis_circle()

	rail_visual.visible = true

	new_bottom_template_strand_position.points = PackedVector2Array([
		Vector2(0, new_bottom_template_y),
		Vector2(track_length, new_bottom_template_y)
	])
	new_bottom_template_strand_position.visible = true

	# NewSynthesizedStrandPosition: starts spanning x=0 to wherever
	# synthesis_x (the yellow circle's x) is at the very first frame --
	# updated every frame after this in _process to keep tracking it.
	new_synthesized_strand_position.points = PackedVector2Array([
		Vector2(0, new_synthesized_strand_y),
		Vector2((factory_x + helicase_x) / 2.0, new_synthesized_strand_y)
	])
	new_synthesized_strand_position.visible = true

	backbone_line.default_color = backbone_color
	backbone_line.width = backbone_line_width
	backbone_line.z_index = -1
	# QoL: round points instead of square -- joint_mode rounds where
	# segments meet (every interior car-to-car joint), cap_mode rounds the
	# very first and last endpoints of the whole line.
	backbone_line.joint_mode = Line2D.LINE_JOINT_ROUND
	backbone_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	backbone_line.end_cap_mode = Line2D.LINE_CAP_ROUND

	print("=== RUN START === baseline_switched:%s" % baseline_switched)

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

			var last_car_x = car_original_x[car_original_x.size() - 1]
			if factory_x > last_car_x:
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
				for i in range(cars.size()):
					if abs(cars[i].position.y - new_bottom_template_y) > 2.0:
						all_settled = false
						break
			if all_settled:
				settling_t = 0.0
				settling_loop_depth_start = loop_depth
				phase = Phase.SETTLING
		Phase.SETTLING:
			# Eases loop_depth from its captured starting value toward 0,
			# AND settle_blend from 0 toward 1, both over settling_duration
			# using the same eased_t. settle_blend is what actually fixes
			# the SETTLING->DONE jump: it blends every curve y-coordinate
			# in _rebuild_rail() toward new_bottom_template_y, so by t=1.0
			# the eased curve already matches what Phase.DONE's flat
			# construction would produce -- making the handoff seamless.
			settling_t += delta
			var t = clamp(settling_t / settling_duration, 0.0, 1.0)
			var eased_t = smoothstep(0.0, 1.0, t)
			loop_depth = lerp(settling_loop_depth_start, 0.0, eased_t)
			settle_blend = eased_t

			if t >= 1.0:
				loop_depth = 0.0
				settle_blend = 1.0
				phase = Phase.DONE
		Phase.DONE:
			settle_blend = 1.0 # stays fully blended once DONE
			if not synthesis_circle_faded:
				synthesis_circle_faded = true
				var fade_tween = create_tween()
				fade_tween.tween_property(synthesis_circle, "modulate:a", 0.0, fade_duration)

	_rebuild_rail()

	# synthesis_circle tracks the loop's LEFTMOST anchor (factory_x) in x,
	# with y FIXED at new_bottom_template_y (not depth-dependent) -- per
	# explicit instruction, distinct from synthesis_circle_y (which is
	# derived from max_loop_depth and no longer used here).
	synthesis_circle.position = Vector2(factory_x, new_bottom_template_y)

	# NewSynthesizedStrandPosition keeps tracking the midpoint, unchanged.
	var new_strand_tracking_x = (factory_x + helicase_x) / 2.0
	new_synthesized_strand_position.points = PackedVector2Array([
		Vector2(0, new_synthesized_strand_y),
		Vector2(new_strand_tracking_x, new_synthesized_strand_y)
	])

	for i in range(cars.size()):
		cars[i].progress = track_length - car_original_x[i]

	for i in range(cars.size()):
		var car_y = cars[i].position.y

		if car_y > car_max_y_reached[i]:
			car_max_y_reached[i] = car_y

		if not baseline_switched and car_y >= new_bottom_template_y:
			baseline_switched = true
			baseline_switch_car_index = i
			print(">>> BASELINE SWITCH TRIGGERED by car[%d] at y=%.1f (t=%s) <<<" % [i, car_y, Time.get_ticks_msec()])

		match car_transfer_state[i]:
			CarTransferState.WAITING:
				# FIX: was checking instantaneous car_y, which only
				# catches a car if it happens to be deep enough in THIS
				# exact frame. Since the pulse is a triangle wave with a
				# fixed period (pulse_car_count car-widths), cars whose
				# transit through the loop happened to land during the
				# shallower portion of a cycle could NEVER satisfy an
				# instantaneous check, no matter how long the run went on
				# -- confirmed empirically: cars 0,1,6,7,12,13,18,19 never
				# triggered ARMED at all, a predictable 2-out-of-6 pattern
				# matching pulse_car_count. car_max_y_reached[i] (updated
				# just above, every frame, unconditionally) is each car's
				# TRUE historical peak depth -- checking THAT instead
				# guarantees every car eventually qualifies once its real
				# peak (whenever it occurred) clears the threshold.
				if car_max_y_reached[i] >= straight_y + max_loop_depth * armed_depth_fraction:
					car_transfer_state[i] = CarTransferState.ARMED
					print("[t=%s] car[%d] ARMED (max_y_reached=%.1f)" % [Time.get_ticks_msec(), i, car_max_y_reached[i]])
			CarTransferState.ARMED:
				if car_y < new_bottom_template_y:
					car_transfer_state[i] = CarTransferState.TRANSFERRED
					car_visuals[i].color = car_color_sequence_complete
					print("[t=%s] car[%d] TRANSFERRED (y=%.1f)" % [Time.get_ticks_msec(), i, car_y])
			CarTransferState.TRANSFERRED:
				pass

	for i in range(cars.size()):
		var car = cars[i]
		var x = car_original_x[i]
		var in_loop = (phase != Phase.DONE) and x >= population_left_edge and x <= helicase_x
		var unzipped = x < factory_x

		if in_loop and not car.is_in_group(LOOP_POPULATION_GROUP):
			car.add_to_group(LOOP_POPULATION_GROUP)
		elif not in_loop and car.is_in_group(LOOP_POPULATION_GROUP):
			car.remove_from_group(LOOP_POPULATION_GROUP)

		if unzipped and not car.is_in_group(UNZIPPED_POPULATION_GROUP):
			car.add_to_group(UNZIPPED_POPULATION_GROUP)
		elif not unzipped and car.is_in_group(UNZIPPED_POPULATION_GROUP):
			car.remove_from_group(UNZIPPED_POPULATION_GROUP)

	var backbone_points = PackedVector2Array()
	for i in range(cars.size()):
		var car = cars[i]
		var on_rail_visual = abs(car.position.y - straight_y) < 1.0
		var on_new_bottom = abs(car.position.y - new_bottom_template_y) < 1.0
		var target_delta: float
		if on_rail_visual:
			target_delta = backbone_offset_distance # below the car
		elif on_new_bottom:
			target_delta = -backbone_offset_distance # above the car
		else:
			target_delta = backbone_offset_distance # inside the loop: toward the bulge, consistent direction (position doesn't matter here)

		car_backbone_delta[i] = lerp(car_backbone_delta[i], target_delta, clamp(backbone_offset_smoothing_speed * delta, 0.0, 1.0))
		backbone_points.append(Vector2(car.position.x, car.position.y + car_backbone_delta[i]))

	backbone_line.points = backbone_points

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
		Vector2(w / 2.0, 0),    # tip
		Vector2(0, -h),          # top
		Vector2(-w / 2.0, 0),    # back
		Vector2(0, h),           # bottom
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
		rail_visual.points = flat_curve.get_baked_points()
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
	rail_visual.points = curve.get_baked_points()

func _setup_synthesis_circle():
	var poly = Polygon2D.new()
	var points = PackedVector2Array()
	const SEGMENTS = 32
	for i in range(SEGMENTS):
		var angle = (float(i) / SEGMENTS) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * synthesis_circle_radius)
	poly.polygon = points
	poly.color = synthesis_circle_color
	synthesis_circle.add_child(poly)

func _spawn_cars():
	var row_span = (num_cars - 1) * car_spacing
	var row_start_x = (track_length - row_span) / 2.0

	for i in range(num_cars):
		var car = PathFollow2D.new()
		car.rotates = false
		car.loop = false

		var visual = ColorRect.new()
		visual.size = car_size
		visual.position = Vector2(-car_size.x / 2.0, -car_size.y / 2.0)
		visual.color = car_color_even if i % 2 == 0 else car_color_odd
		car.add_child(visual)
		car_visuals.append(visual)

		rail_path.add_child(car)

		var x = row_start_x + i * car_spacing
		car_original_x.append(x)
		car.progress = track_length - x
		cars.append(car)
		car_transfer_state.append(CarTransferState.WAITING)
		car_max_y_reached.append(straight_y)
		car_backbone_delta.append(backbone_offset_distance) # starts matching the RailVisual case, since that's where cars begin
