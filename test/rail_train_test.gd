extends Node2D

# ==========================================
# RAIL/TRAIN TEST v22
# BASELINE SWITCH: instead of verifying every car independently crosses
# NEW_BOTTOM_TEMPLATE_Y across multiple runs, we only need the FIRST car to
# cross it once. That single crossing flips a global, one-time switch:
# from that moment on, EVERY car's "finished" resting position becomes
# NEW_BOTTOM_TEMPLATE_Y instead of STRAIGHT_Y -- no car, once pulled
# through the loop, ever returns to RailVisual again. RailVisual still
# holds cars the loop hasn't reached yet, exactly as before.
# ==========================================

@onready var rail_path: Path2D = $RailPath
@onready var rail_visual: Line2D = $RailVisual
@onready var new_strand_line: Line2D = $NewStrandLine
@onready var synthesis_circle: Node2D = $SynthesisCircle
@onready var new_bottom_template_strand_position: Line2D = $NewBottomTemplateStrandPosition
@onready var backbone_line: Line2D = $BackboneLine

const CAR_SPACING: float = 60.0
const NUM_CARS: int = 24
const STRAIGHT_Y: float = 300.0
const TRACK_LENGTH: float = 1920.0

const NEW_BOTTOM_TEMPLATE_OFFSET: float = 90.0
const NEW_BOTTOM_TEMPLATE_Y: float = STRAIGHT_Y + NEW_BOTTOM_TEMPLATE_OFFSET

const LOOP_FLOOR_DEPTH: float = 15.0
const MAX_LOOP_DEPTH: float = 220.0
const GAP_WIDTH: float = 168.0

const CAR_HEIGHT: float = 24.0
const NEW_STRAND_Y: float = STRAIGHT_Y + MAX_LOOP_DEPTH + CAR_HEIGHT

const SYNTHESIS_CIRCLE_RADIUS: float = 16.0
const SYNTHESIS_CIRCLE_Y: float = STRAIGHT_Y + MAX_LOOP_DEPTH
const FADE_DURATION: float = 0.6
var synthesis_circle_faded: bool = false

var helicase_x: float = 0.0
var factory_x: float = 0.0
var sweep_speed: float = 90.0
var collapse_speed: float = 90.0

enum Phase { SWEEPING, FINISHING_LAST_PULSE, DONE }
var phase: Phase = Phase.SWEEPING

const PULSE_CAR_COUNT: int = 6
const PULSE_WIDTH: float = PULSE_CAR_COUNT * CAR_SPACING
var pulse_time_budget: float = 0.0
var pulse_speed: float = 0.0

enum PulseState { GROWING, SHRINKING, DONE }
var pulse_state: PulseState = PulseState.GROWING

var pulse_offset: float = 0.0

var population_left_edge: float = 0.0

var loop_depth: float = LOOP_FLOOR_DEPTH

var loop_length: float = 0.0
const LOOP_POPULATION_GROUP := "loop_population"
const UNZIPPED_POPULATION_GROUP := "unzipped_population"

var cars: Array[PathFollow2D] = []
var car_original_x: Array[float] = []

# V19 step 4 (kept): per-car two-stage transfer state, still useful as a
# per-car diagnostic even though the actual baseline switch (below) is now
# a single global flag, not per-car.
enum CarTransferState { WAITING, ARMED, TRANSFERRED }
var car_transfer_state: Array[CarTransferState] = []
var car_max_y_reached: Array[float] = []

# V22: BASELINE SWITCH. Global, one-time flag. False = cars rest at
# STRAIGHT_Y (RailVisual) once released from the loop, same as before.
# True = cars rest at NEW_BOTTOM_TEMPLATE_Y instead, PERMANENTLY, for
# every car released from this point on (including cars already resting
# at STRAIGHT_Y from before the switch -- they get pulled down to the new
# baseline the next time the loop reaches them, not retroactively snapped).
var baseline_switched: bool = false
var baseline_switch_car_index: int = -1 # which car triggered it, for the debug log

# V25: BACKBONE TEST (purely additive, read-only observer of car
# positions -- never writes to any existing simulation state). Catmull-Rom
# style auto-tangent smoothing through the cars' current live positions.
# BACKBONE_SMOOTHING scales the estimated tangent at each point: lower =
# gentle/tight curve hugging actual positions, higher = loose/bulgy curve.
# Start gentle per the design discussion; easy to bump up to compare.
const BACKBONE_SMOOTHING: float = 0.15
const BACKBONE_SAMPLES_PER_SEGMENT: int = 12 # density of the baked curve between each pair of points
const BACKBONE_OFFSET_DISTANCE: float = 12.0 # half the car's 24px size -- puts the line at the car's edge, not through its center

func _ready():
	helicase_x = GAP_WIDTH
	factory_x = 0.0
	loop_depth = MAX_LOOP_DEPTH

	pulse_time_budget = PULSE_WIDTH / sweep_speed
	pulse_speed = (2.0 * PULSE_WIDTH) / pulse_time_budget

	_rebuild_rail()
	_spawn_cars()
	_setup_synthesis_circle()

	rail_visual.visible = true

	new_bottom_template_strand_position.points = PackedVector2Array([
		Vector2(0, NEW_BOTTOM_TEMPLATE_Y),
		Vector2(TRACK_LENGTH, NEW_BOTTOM_TEMPLATE_Y)
	])
	new_bottom_template_strand_position.visible = true

	# V25 FIX: set explicitly in code rather than relying solely on the
	# node's default_color/width properties set externally -- guaranteed
	# magenta, 8px, regardless of what the node's saved properties are.
	backbone_line.default_color = Color(1.0, 0.0, 1.0, 1.0)
	backbone_line.width = 8.0

	# V26: render order -- cars should draw ON TOP of the backbone line,
	# not be hidden behind it. z_index is explicit and doesn't depend on
	# scene tree sibling order (which would be fragile/easy to break
	# later). Cars are children of rail_path (default z_index 0);
	# negative z_index puts the backbone behind them reliably.
	backbone_line.z_index = -1

	print("=== RUN START === baseline_switched:%s" % baseline_switched)

func _process(delta):
	match phase:
		Phase.SWEEPING:
			helicase_x += sweep_speed * delta

			factory_x = helicase_x - GAP_WIDTH

			match pulse_state:
				PulseState.GROWING:
					pulse_offset = min(pulse_offset + pulse_speed * delta, PULSE_WIDTH)
					if pulse_offset >= PULSE_WIDTH:
						pulse_state = PulseState.SHRINKING
				PulseState.SHRINKING:
					pulse_offset = max(pulse_offset - pulse_speed * delta, 0.0)
					if pulse_offset <= 0.0:
						pulse_state = PulseState.GROWING
				PulseState.DONE:
					pulse_offset = 0.0

			var pulse_ratio = pulse_offset / PULSE_WIDTH
			loop_depth = lerp(LOOP_FLOOR_DEPTH, MAX_LOOP_DEPTH, pulse_ratio)

			population_left_edge = factory_x - pulse_offset

			# V22 FIX (round 3): instead of waiting for every car to be
			# fully settled (which only happens after the LAST pulse cycle
			# finishes, during which x-translation was still advancing the
			# whole time -- the actual "pulls the train right" bug), the
			# x-translation now freezes as soon as every car has been
			# UNZIPPED (factory_x has passed every car's original_x) -- the
			# moment there's no more new material to reach. Checked
			# directly against factory_x (same definition as
			# UNZIPPED_POPULATION_GROUP uses) rather than reading the group
			# itself, which only gets updated later this same frame and
			# would otherwise be one frame stale. The pulse itself keeps
			# running/finishing naturally in the next phase.
			var last_car_x = car_original_x[car_original_x.size() - 1]
			if factory_x > last_car_x:
				phase = Phase.FINISHING_LAST_PULSE
		Phase.FINISHING_LAST_PULSE:
			# x-translation is FROZEN here -- helicase_x/factory_x do not
			# move. Only the pulse (depth) keeps animating, exactly as
			# before, until it completes one full cycle and returns to
			# pulse_offset == 0 (back at PulseState.GROWING with offset 0,
			# i.e. a fresh cycle boundary) -- that's when every remaining
			# car has had its chance to be pulled through and settle.
			match pulse_state:
				PulseState.GROWING:
					pulse_offset = min(pulse_offset + pulse_speed * delta, PULSE_WIDTH)
					if pulse_offset >= PULSE_WIDTH:
						pulse_state = PulseState.SHRINKING
				PulseState.SHRINKING:
					pulse_offset = max(pulse_offset - pulse_speed * delta, 0.0)
					if pulse_offset <= 0.0:
						pulse_state = PulseState.GROWING
						# Pulse completed a full cycle while frozen -- check
						# if everything's settled now; if not, let it run
						# one more cycle (handled by staying in this phase
						# and looping GROWING again next frame).
				PulseState.DONE:
					pulse_offset = 0.0

			var pulse_ratio2 = pulse_offset / PULSE_WIDTH
			loop_depth = lerp(LOOP_FLOOR_DEPTH, MAX_LOOP_DEPTH, pulse_ratio2)

			population_left_edge = factory_x - pulse_offset

			var all_settled = baseline_switched
			if all_settled:
				for i in range(cars.size()):
					if abs(cars[i].position.y - NEW_BOTTOM_TEMPLATE_Y) > 2.0:
						all_settled = false
						break
			if all_settled:
				# FIX: previously transitioned to Phase.REVERSING here,
				# which then ran for 10+ seconds (its own slow eased
				# velocity + REVERSE_SHRINK_DISTANCE widening) for no real
				# purpose -- every car was already settled on
				# NewBottomTemplateStrandPosition, so flattening the curve
				# back to a straight line afterward accomplished nothing
				# visible. Going straight to DONE once the last pulse
				# settles is simpler and correct: there's nothing left to
				# animate.
				phase = Phase.DONE
		Phase.DONE:
			if not synthesis_circle_faded:
				synthesis_circle_faded = true
				var fade_tween = create_tween()
				fade_tween.tween_property(synthesis_circle, "modulate:a", 0.0, FADE_DURATION)

	_rebuild_rail()

	var synthesis_x = (factory_x + helicase_x) / 2.0
	synthesis_circle.position = Vector2(synthesis_x, SYNTHESIS_CIRCLE_Y)

	for i in range(cars.size()):
		cars[i].progress = TRACK_LENGTH - car_original_x[i]

	# V22: BASELINE SWITCH CHECK + per-car transfer state, merged into one
	# pass since both depend on each car's current y.
	for i in range(cars.size()):
		var car_y = cars[i].position.y

		if car_y > car_max_y_reached[i]:
			car_max_y_reached[i] = car_y

		# Trigger the global switch the FIRST time ANY car crosses --
		# one-shot, never re-checked after baseline_switched becomes true.
		if not baseline_switched and car_y >= NEW_BOTTOM_TEMPLATE_Y:
			baseline_switched = true
			baseline_switch_car_index = i
			print(">>> BASELINE SWITCH TRIGGERED by car[%d] at y=%.1f (t=%s) <<<" % [i, car_y, Time.get_ticks_msec()])

		match car_transfer_state[i]:
			CarTransferState.WAITING:
				if car_y >= STRAIGHT_Y + MAX_LOOP_DEPTH:
					car_transfer_state[i] = CarTransferState.ARMED
					print("[t=%s] car[%d] ARMED (y=%.1f)" % [Time.get_ticks_msec(), i, car_y])
			CarTransferState.ARMED:
				if car_y < NEW_BOTTOM_TEMPLATE_Y:
					car_transfer_state[i] = CarTransferState.TRANSFERRED
					print("[t=%s] car[%d] TRANSFERRED (y=%.1f)" % [Time.get_ticks_msec(), i, car_y])
			CarTransferState.TRANSFERRED:
				pass

	for i in range(cars.size()):
		var car = cars[i]
		var x = car_original_x[i]
		var in_loop = x >= population_left_edge and x <= helicase_x
		var unzipped = x < factory_x

		if in_loop and not car.is_in_group(LOOP_POPULATION_GROUP):
			car.add_to_group(LOOP_POPULATION_GROUP)
		elif not in_loop and car.is_in_group(LOOP_POPULATION_GROUP):
			car.remove_from_group(LOOP_POPULATION_GROUP)

		if unzipped and not car.is_in_group(UNZIPPED_POPULATION_GROUP):
			car.add_to_group(UNZIPPED_POPULATION_GROUP)
		elif not unzipped and car.is_in_group(UNZIPPED_POPULATION_GROUP):
			car.remove_from_group(UNZIPPED_POPULATION_GROUP)

	if Engine.get_physics_frames() % 60 == 0:
		var loop_count = get_tree().get_nodes_in_group(LOOP_POPULATION_GROUP).size()
		var unzipped_count = get_tree().get_nodes_in_group(UNZIPPED_POPULATION_GROUP).size()
		print("[%s] phase:%s | factory_x:%.1f helicase_x:%.1f loop_depth:%.1f | baseline_switched:%s (car %d) | loop_population:%d unzipped_population:%d" % [
			Time.get_ticks_msec(), Phase.keys()[phase], factory_x, helicase_x, loop_depth,
			baseline_switched, baseline_switch_car_index, loop_count, unzipped_count
		])

		# V22 DEBUG: every car's current y and transfer state, so we can
		# watch the whole population at a glance instead of just first/last.
		var line_parts: Array[String] = []
		for i in range(cars.size()):
			line_parts.append("%d:%.0f/%s" % [i, cars[i].position.y, CarTransferState.keys()[car_transfer_state[i]].substr(0, 1)])
		print("[%s]   cars (idx:y/state): %s" % [Time.get_ticks_msec(), " ".join(line_parts)])

	# V25: BACKBONE TEST -- purely additive, read-only. Gathers each car's
	# CURRENT live position (same data the debug log above already reads),
	# in array index order (0..23, matching fixed left-to-right spawn
	# order), and draws a smooth curve through them. Never writes to any
	# car, never touches helicase_x/factory_x/pulse state -- just observes
	# and draws.
	var car_positions: Array = []
	for car in cars:
		car_positions.append(car.position)
	backbone_line.points = _build_smooth_backbone(car_positions, BACKBONE_SMOOTHING, BACKBONE_OFFSET_DISTANCE)

func _rebuild_rail():
	var curve = Curve2D.new()

	curve.add_point(Vector2(TRACK_LENGTH, STRAIGHT_Y))
	curve.add_point(Vector2(helicase_x, STRAIGHT_Y))

	var bulge_y = STRAIGHT_Y + loop_depth
	var handle_x = max(40.0, loop_depth * 0.6)

	curve.add_point(
		Vector2(helicase_x, STRAIGHT_Y),
		Vector2.ZERO,
		Vector2(-handle_x, loop_depth * 0.5)
	)
	var mid_x = (factory_x + helicase_x) / 2.0
	var mid_handle_x = max(1.0, (helicase_x - factory_x) * 0.25)
	curve.add_point(
		Vector2(mid_x, bulge_y),
		Vector2(mid_handle_x, 0),
		Vector2(-mid_handle_x, 0)
	)

	# V22: the curve's ANCHOR-SIDE endpoint (where released cars come to
	# rest) switches from STRAIGHT_Y to NEW_BOTTOM_TEMPLATE_Y once
	# baseline_switched is true -- this is what actually makes "no car
	# returns to RailVisual" true geometrically, not just a position
	# override after the fact.
	var anchor_rest_y = NEW_BOTTOM_TEMPLATE_Y if baseline_switched else STRAIGHT_Y

	curve.add_point(
		Vector2(factory_x, anchor_rest_y),
		Vector2(handle_x, loop_depth * 0.5),
		Vector2.ZERO
	)

	var loop_only_curve = Curve2D.new()
	loop_only_curve.add_point(
		Vector2(helicase_x, STRAIGHT_Y),
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
		points.append(Vector2(cos(angle), sin(angle)) * SYNTHESIS_CIRCLE_RADIUS)
	poly.polygon = points
	poly.color = Color(1.0, 0.85, 0.1)
	synthesis_circle.add_child(poly)

func _build_smooth_backbone(points: Array, smoothing: float, offset_distance: float) -> PackedVector2Array:
	# V25/V26: pure function, no side effects, no reads of simulation state
	# beyond the points array it's given. Catmull-Rom style auto-tangent,
	# now distance-aware (see inside the loop below) to prevent overshoot/
	# self-crossing when neighboring points are unevenly spaced (e.g.
	# through the loop region).
	if points.size() < 2:
		return PackedVector2Array(points)

	var curve = Curve2D.new()
	var n = points.size()

	var tightest_spacing = INF
	var tightest_handle_len = 0.0
	var tightest_index = -1

	for i in range(n):
		var p: Vector2 = points[i]

		# Tangent estimation: direction from the previous point to the
		# next point. DISTANCE-AWARE FIX: previously this scaled the raw
		# (points[i+1] - points[i-1]) vector by a flat global constant
		# (smoothing), with no relationship to how far apart the actual
		# neighboring points were. When neighbors are far apart in
		# screen-space (e.g. one car still flat, the next deep in the
		# loop), that raw vector is large even though the real local
		# segment lengths are short -- producing a handle that overshoots
		# past the next point entirely, causing the curve to loop back on
		# itself (the same "cursive e" self-crossing we diagnosed earlier
		# for the loop's own Bezier curve, here showing up in this curve
		# instead). Standard fix: scale the tangent DIRECTION by
		# `smoothing`, but cap its MAGNITUDE relative to the shorter of
		# the two adjacent segment lengths, so the handle can never
		# extend further than roughly halfway to the nearest neighbor.
		var tangent: Vector2
		var dist_prev = 0.0
		var dist_next = 0.0
		if i > 0:
			dist_prev = p.distance_to(points[i - 1])
		if i < n - 1:
			dist_next = p.distance_to(points[i + 1])

		if i == 0:
			tangent = (points[1] - p) if n > 1 else Vector2.ZERO
		elif i == n - 1:
			tangent = (p - points[i - 1])
		else:
			tangent = (points[i + 1] - points[i - 1])

		if tangent.length() > 0.0:
			tangent = tangent.normalized()

		# V27 FIX: ANGLE-AWARE SCALING. The distance cap alone wasn't
		# enough -- confirmed by the screenshot: a small but real
		# self-crossing "pinch knot" forms at the loop's bottom turn,
		# where several points bend sharply over a short span. The
		# distance cap limits handle LENGTH relative to spacing, but
		# doesn't account for how SHARPLY the path turns at that point --
		# a sharp corner needs an even smaller handle than a gentle curve
		# at the same spacing, or the rounded Bezier segment swings past
		# the actual corner and crosses itself. Computed as the angle
		# between the incoming segment (p - prev) and outgoing segment
		# (next - p): 180 degrees = perfectly straight (no extra
		# shrinking needed), 0 degrees = a hairpin reversal (handle
		# should shrink toward zero).
		var angle_factor = 1.0
		if i > 0 and i < n - 1:
			var incoming = (p - points[i - 1])
			var outgoing = (points[i + 1] - p)
			if incoming.length() > 0.0 and outgoing.length() > 0.0:
				var cos_angle = incoming.normalized().dot(outgoing.normalized())
				# cos_angle: 1.0 = straight ahead, -1.0 = full reversal.
				# Remap so straight-ahead (1.0) keeps full handle length,
				# and anything sharper scales down toward 0.
				angle_factor = clamp((cos_angle + 1.0) / 2.0, 0.0, 1.0)

		var min_adjacent_dist = dist_prev if i == 0 else (dist_next if i == n - 1 else min(dist_prev, dist_next))
		var handle = tangent * min(smoothing * min_adjacent_dist * 2.0, min_adjacent_dist * 0.5) * angle_factor
		# Curve2D wants IN-handle (pointing backward) and OUT-handle
		# (pointing forward) as offsets FROM the point, not absolute
		# positions -- so in = -handle, out = +handle, giving a smooth
		# pass-through tangent at each point.
		curve.add_point(p, -handle, handle)

		# DIAGNOSTIC: track whichever point has the tightest neighbor
		# spacing (most likely spot for overshoot, e.g. deep in the loop),
		# and that point's resulting handle length -- if the cap is
		# working, handle length should never meaningfully exceed
		# min_adjacent_dist * 0.5.
		if min_adjacent_dist > 0.0 and min_adjacent_dist < tightest_spacing:
			tightest_spacing = min_adjacent_dist
			tightest_handle_len = handle.length()
			tightest_index = i

	# DIAGNOSTIC (new): check whether consecutive points are monotonic in
	# x. cars[0] is leftmost (smallest spawn x), cars[23] is rightmost --
	# so points[i+1].x SHOULD be >= points[i].x normally. The handle-length
	# cap was confirmed working (ratio stays ~0.3 every frame), so the
	# remaining twist must come from somewhere else -- a likely candidate
	# is the curve's bottom-of-loop turn briefly making car[i+1] sit BEHIND
	# car[i] in x (points[i+1].x < points[i].x), which a Catmull-Rom-style
	# curve isn't built to handle gracefully regardless of handle length.
	var order_violations: Array[String] = []
	for i in range(n - 1):
		if points[i + 1].x < points[i].x:
			order_violations.append("%d->%d (dx=%.1f)" % [i, i + 1, points[i + 1].x - points[i].x])

	if Engine.get_physics_frames() % 60 == 0:
		if order_violations.size() > 0:
			print("[%s]   BACKBONE ORDER DIAG | %d x-order violations (point[i+1].x < point[i].x -- went backward): %s" % [
				Time.get_ticks_msec(), order_violations.size(), ", ".join(order_violations)
			])
		print("[%s]   BACKBONE DIAG | tightest spacing at car_index~%d: %.2f | handle_len: %.2f | ratio: %.3f (should be <= 0.5)" % [
			Time.get_ticks_msec(), tightest_index, tightest_spacing, tightest_handle_len,
			tightest_handle_len / tightest_spacing if tightest_spacing > 0.0 else 0.0
		])

	# Bake at a fixed density per segment, not Godot's default tolerance-
	# based baking -- gives predictable smoothness regardless of how far
	# apart points happen to be (matters since car spacing can vary
	# visually as they move through the loop).
	curve.bake_interval = 1.0 # fine baked resolution; we resample explicitly below anyway
	var total_samples = max(2, (n - 1) * BACKBONE_SAMPLES_PER_SEGMENT)
	var result = PackedVector2Array()
	var curve_len = curve.get_baked_length()
	for s in range(total_samples + 1):
		var dist = (float(s) / float(total_samples)) * curve_len

		# V25 FIX: offset perpendicular to the curve's LOCAL tangent at
		# this point (rotation-aware sampling), not a flat vertical shift
		# -- a flat shift would look wrong through the curved loop section
		# (the offset needs to rotate with the curve, same principle as
		# loop_normal_angle in the real simulation). "Above the cars"
		# means toward lower y; same ambiguous-sign issue we solved before
		# (a fixed +90deg rotation can point either way depending on
		# tangent direction), so explicitly pick whichever perpendicular
		# candidate has the smaller (more negative) y component.
		var sample_t = curve.sample_baked_with_rotation(dist)
		var tangent_angle = sample_t.get_rotation()
		var candidate_a = Vector2.RIGHT.rotated(tangent_angle + PI / 2.0)
		var candidate_b = Vector2.RIGHT.rotated(tangent_angle - PI / 2.0)
		var normal = candidate_a if candidate_a.y < candidate_b.y else candidate_b
		result.append(sample_t.origin + normal * offset_distance)
	return result

func _spawn_cars():
	var row_span = (NUM_CARS - 1) * CAR_SPACING
	var row_start_x = (TRACK_LENGTH - row_span) / 2.0

	for i in range(NUM_CARS):
		var car = PathFollow2D.new()
		car.rotates = false
		car.loop = false

		var visual = ColorRect.new()
		visual.size = Vector2(24, 24)
		visual.position = Vector2(-12, -12)
		visual.color = Color(0.2, 0.6, 0.9) if i % 2 == 0 else Color(0.9, 0.6, 0.2)
		car.add_child(visual)

		rail_path.add_child(car)

		var x = row_start_x + i * CAR_SPACING
		car_original_x.append(x)
		car.progress = TRACK_LENGTH - x
		cars.append(car)
		car_transfer_state.append(CarTransferState.WAITING)
		car_max_y_reached.append(STRAIGHT_Y)
