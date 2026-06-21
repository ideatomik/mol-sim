extends Node2D

# ==========================================
# RAIL/TRAIN TEST v31
# Reverted the omega-flare loop geometry change (back to the original
# mid_handle_x = 0.25x multiplier) -- that was a loop-geometry edit made
# specifically to chase the backbone's self-crossing problem, and it's
# being undone now that we're rebuilding the backbone from scratch with a
# simpler approach. Loop mechanic (baseline switch, FINISHING_LAST_PULSE)
# is otherwise unchanged from its known-good state.
#
# Backbone: REMOVED the Curve2D/Catmull-Rom auto-tangent implementation
# entirely (V25-V30). Starting over with a plain polyline -- straight
# Line2D segments directly between car positions, no curve math, no
# tangent estimation, no handle capping. Accepts the "jagged" look in
# exchange for guaranteed correctness (no self-crossing is possible with a
# straight polyline through points in a fixed, known order).
# ==========================================

@onready var rail_path: Path2D = $RailPath
@onready var rail_visual: Line2D = $RailVisual
@onready var new_strand_line: Line2D = $NewStrandLine
@onready var synthesis_circle: Node2D = $SynthesisCircle
@onready var new_bottom_template_strand_position: Line2D = $NewBottomTemplateStrandPosition
@onready var new_synthesized_strand_position: Line2D = $NewSynthesizedStrandPosition
@onready var backbone_line: Line2D = $BackboneLine

const CAR_SPACING: float = 60.0
const NUM_CARS: int = 24
const STRAIGHT_Y: float = 300.0
const TRACK_LENGTH: float = 1920.0

const NEW_BOTTOM_TEMPLATE_OFFSET: float = 90.0
const NEW_BOTTOM_TEMPLATE_Y: float = STRAIGHT_Y + NEW_BOTTOM_TEMPLATE_OFFSET
# As far below NewBottomTemplateStrandPosition as that line is below
# RailVisual -- same NEW_BOTTOM_TEMPLATE_OFFSET applied a second time.
const NEW_SYNTHESIZED_STRAND_Y: float = NEW_BOTTOM_TEMPLATE_Y + NEW_BOTTOM_TEMPLATE_OFFSET

const LOOP_FLOOR_DEPTH: float = 15.0
const MAX_LOOP_DEPTH: float = 220.0
const GAP_WIDTH: float = 168.0

const CAR_HEIGHT: float = 24.0
const BACKBONE_OFFSET_DISTANCE: float = 12.0 # half the car's 24px size -- puts the line at the car's edge, not through its center
const BACKBONE_LINE_WIDTH: float = 8.0 # also used directly in _ready() when setting backbone_line.width, kept as a named constant so the bond marks can reference the same value
const BOND_MARK_WIDTH: float = 14.0 # horizontal size of each placeholder ">" mark -- tune to taste
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

enum CarTransferState { WAITING, ARMED, TRANSFERRED }
var car_transfer_state: Array[CarTransferState] = []
var car_max_y_reached: Array[float] = []

var baseline_switched: bool = false
var baseline_switch_car_index: int = -1

# PHOSPHODIESTER BOND MARKS: one Node2D (holding a Polygon2D placeholder
# ">" shape) per bond/segment, created lazily in _update_bond_marks(),
# repositioned and rotated every frame to track the backbone.
var bond_marks: Array[Node2D] = []

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

	# NewSynthesizedStrandPosition: starts spanning x=0 to wherever
	# synthesis_x (the yellow circle's x) is at the very first frame --
	# updated every frame after this in _process to keep tracking it.
	new_synthesized_strand_position.points = PackedVector2Array([
		Vector2(0, NEW_SYNTHESIZED_STRAND_Y),
		Vector2((factory_x + helicase_x) / 2.0, NEW_SYNTHESIZED_STRAND_Y)
	])
	new_synthesized_strand_position.visible = true

	backbone_line.default_color = Color(1.0, 0.0, 1.0, 1.0)
	backbone_line.width = BACKBONE_LINE_WIDTH
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

			var last_car_x = car_original_x[car_original_x.size() - 1]
			if factory_x > last_car_x:
				phase = Phase.FINISHING_LAST_PULSE
		Phase.FINISHING_LAST_PULSE:
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
				# FIX: loop_depth was whatever value the pulse cycle
				# happened to be at the instant all cars passed the
				# position check -- could be anywhere from LOOP_FLOOR_DEPTH
				# (15) up, not necessarily 0. Since nothing in Phase.DONE
				# ever touches loop_depth again, that residual value got
				# frozen into RailVisual's curve forever, leaving a small
				# permanent bulge near the trailing end (visible as the
				# black curve remaining, with the last car's backbone
				# offset dipping toward it since the car's actual position
				# was still very slightly off STRAIGHT_Y/NEW_BOTTOM_
				# TEMPLATE_Y because of that residual curve). Snapping to
				# exactly 0 here guarantees a perfectly flat curve once we
				# stop animating it.
				loop_depth = 0.0
				phase = Phase.DONE
		Phase.DONE:
			if not synthesis_circle_faded:
				synthesis_circle_faded = true
				var fade_tween = create_tween()
				fade_tween.tween_property(synthesis_circle, "modulate:a", 0.0, FADE_DURATION)

	_rebuild_rail()

	var synthesis_x = (factory_x + helicase_x) / 2.0
	synthesis_circle.position = Vector2(synthesis_x, SYNTHESIS_CIRCLE_Y)

	# NewSynthesizedStrandPosition: starts at the left edge of the track,
	# right edge follows synthesis_x (the same x driving the yellow
	# circle) every frame. Once Phase.DONE, synthesis_circle fades out and
	# this stops being updated here too (the loop_depth==0 DONE-phase
	# early return in _rebuild_rail still runs every frame, but nothing
	# currently re-touches synthesis_x in that branch) -- so the line
	# naturally freezes at wherever the circle was when it faded, same as
	# everything else settles at DONE.
	new_synthesized_strand_position.points = PackedVector2Array([
		Vector2(0, NEW_SYNTHESIZED_STRAND_Y),
		Vector2(synthesis_x, NEW_SYNTHESIZED_STRAND_Y)
	])

	for i in range(cars.size()):
		cars[i].progress = TRACK_LENGTH - car_original_x[i]

	for i in range(cars.size()):
		var car_y = cars[i].position.y

		if car_y > car_max_y_reached[i]:
			car_max_y_reached[i] = car_y

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
		# FIX: once Phase.DONE, the loop mechanic has concluded and
		# population_left_edge/helicase_x are frozen at whatever values
		# they last held -- if a car's FIXED spawn x happens to still fall
		# within that frozen window, it stays classified as "in the loop"
		# PERMANENTLY, even though nothing is animating it anymore (this
		# is exactly what kept car[23] -- and loop_population:2 overall --
		# stuck forever in the log). Once DONE, nothing should ever be
		# considered "in the loop".
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

	if Engine.get_physics_frames() % 60 == 0:
		var loop_count = get_tree().get_nodes_in_group(LOOP_POPULATION_GROUP).size()
		var unzipped_count = get_tree().get_nodes_in_group(UNZIPPED_POPULATION_GROUP).size()
		print("[%s] phase:%s | factory_x:%.1f helicase_x:%.1f loop_depth:%.1f | baseline_switched:%s (car %d) | loop_population:%d unzipped_population:%d" % [
			Time.get_ticks_msec(), Phase.keys()[phase], factory_x, helicase_x, loop_depth,
			baseline_switched, baseline_switch_car_index, loop_count, unzipped_count
		])

		var line_parts: Array[String] = []
		for i in range(cars.size()):
			line_parts.append("%d:%.0f/%s" % [i, cars[i].position.y, CarTransferState.keys()[car_transfer_state[i]].substr(0, 1)])
		print("[%s]   cars (idx:y/state): %s" % [Time.get_ticks_msec(), " ".join(line_parts)])

		# DIAGNOSTIC: which cars exactly are in loop_population, and the
		# LAST car's full state -- to find out why it's stuck (y=363,
		# never reaching 390) and why loop_population stays at 2 forever
		# even after Phase.DONE, when nothing should still be "in the loop".
		var loop_members: Array[int] = []
		for i in range(cars.size()):
			if cars[i].is_in_group(LOOP_POPULATION_GROUP):
				loop_members.append(i)
		var last_i = cars.size() - 1
		print("[%s]   LOOP_POPULATION members: %s | last_car[%d]: progress=%.1f position=%s original_x=%.1f | population_left_edge=%.1f helicase_x=%.1f (in_loop_range=%s)" % [
			Time.get_ticks_msec(), loop_members, last_i,
			cars[last_i].progress, cars[last_i].position, car_original_x[last_i],
			population_left_edge, helicase_x,
			car_original_x[last_i] >= population_left_edge and car_original_x[last_i] <= helicase_x
		])

	# BACKBONE: plain polyline through PER-CAR OFFSET positions, in fixed
	# spawn-array order (cars[0]..cars[23]). Still no curve math, no
	# tangent estimation -- a straight polyline through points in a known,
	# fixed order cannot self-cross at those joints.
	#
	# OFFSET DIRECTION (corrected per explicit instruction):
	#   - On RailVisual (not yet transferred, resting at ~STRAIGHT_Y=300):
	#     backbone BELOW the cars -- LARGER y than the car.
	#   - On NewBottomTemplateStrandPosition (transferred, resting at
	#     ~NEW_BOTTOM_TEMPLATE_Y=390): backbone ABOVE the cars -- SMALLER y
	#     than the car.
	# These two cases now have GENUINELY OPPOSITE signs (previously they
	# coincidentally matched under the old "away from/inside reference_side"
	# framing, which was the wrong rule).
	# INSIDE THE LOOP: position doesn't matter (confirmed) -- kept the
	# existing simple consistent direction (toward the bulge).
	var backbone_points = PackedVector2Array()
	for i in range(cars.size()):
		var car = cars[i]
		var on_rail_visual = abs(car.position.y - STRAIGHT_Y) < 1.0
		var on_new_bottom = abs(car.position.y - NEW_BOTTOM_TEMPLATE_Y) < 1.0
		var y_delta: float
		if on_rail_visual:
			y_delta = BACKBONE_OFFSET_DISTANCE # below the car
		elif on_new_bottom:
			y_delta = -BACKBONE_OFFSET_DISTANCE # above the car
		else:
			y_delta = BACKBONE_OFFSET_DISTANCE # inside the loop: toward the bulge, consistent direction (position doesn't matter here)
		backbone_points.append(Vector2(car.position.x, car.position.y + y_delta))

	# REJECTED APPROACH (kept as a comment for reference, see retry below):
	# inserting a notch point at every segment midpoint, offset
	# perpendicular -- this read as a continuous zig-zag/sawtooth wave
	# rather than discrete ">" marks, since every single segment got
	# notched in the same fixed direction. Confirmed wrong by screenshot.
	backbone_line.points = backbone_points

	# PHOSPHODIESTER BOND MARKS, v2: separate small Polygon2D sprites (one
	# per bond), positioned at each segment's midpoint and ROTATED to match
	# that segment's local tangent direction -- placeholder for an eventual
	# real vector asset. Each mark's height matches BACKBONE line width, so
	# it reads as sized-to-fit rather than arbitrary.
	_update_bond_marks(backbone_points)

func _update_bond_marks(points: PackedVector2Array):
	# Ensures bond_marks has exactly (points.size() - 1) Polygon2D children
	# -- one per segment/bond -- creating or removing as the car count
	# changes (it doesn't in this test, but written generally). Each one
	# repositioned/rotated every frame to track its segment.
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
	# PLACEHOLDER v3: TWO LAYERED SOLID DIAMONDS, not a single outline
	# polygon -- the actual intended technique (clarified after v2's
	# hexagon-outline approach never rendered anything visible). A larger
	# BLACK diamond sits underneath; a smaller MAGENTA diamond (same color
	# as the backbone) sits on top, shifted slightly toward the tip (+X)
	# direction. The magenta diamond covers most of the black one, leaving
	# only a small ">"-shaped sliver of black exposed around the back/left
	# edges -- the chevron mark comes from LAYERING/OCCLUSION, not from a
	# single precisely-wound outline shape. Much simpler to get right than
	# a 6-point self-winding polygon.
	var holder = Node2D.new()
	var h = BACKBONE_LINE_WIDTH / 2.0
	var w = BOND_MARK_WIDTH

	# Bottom: black diamond, full size. 4 points: tip (right), top, back
	# (left), bottom.
	var black_diamond = Polygon2D.new()
	black_diamond.polygon = PackedVector2Array([
		Vector2(w / 2.0, 0),    # tip
		Vector2(0, -h),          # top
		Vector2(-w / 2.0, 0),    # back
		Vector2(0, h),           # bottom
	])
	black_diamond.color = Color(0.0, 0.0, 0.0, 1.0)
	holder.add_child(black_diamond)

	# Top: magenta diamond, built with EXPLICIT, independently-placed
	# points -- not a uniform shrink+shift of the black diamond's shape.
	# A uniform shrink-then-partial-shift doesn't guarantee any one edge
	# fully covers: confirmed by screenshot, black bled through on ALL
	# sides (including the tip) because the shift wasn't large enough to
	# compensate for the shrink there too. Instead: the magenta tip and
	# top/bottom points are placed to fully cover (extend to or past) the
	# black diamond's corresponding points, while ONLY the back point is
	# pulled inward -- guaranteeing black is hidden everywhere except a
	# deliberate gap at the back, which is what actually produces a clean
	# one-sided ">" sliver instead of a thin outline all around.
	var back_inset = w * 0.45 # how far the magenta back point sits inward from the black diamond's own back point -- this distance IS the visible ">" sliver's depth
	var magenta_diamond = Polygon2D.new()
	magenta_diamond.polygon = PackedVector2Array([
		Vector2(w / 2.0, 0),                  # tip: matches black's tip exactly, fully covers it
		Vector2(0, -h),                          # top: matches black's top exactly, fully covers it
		Vector2(-w / 2.0 + back_inset, 0),    # back: pulled inward from black's back point -- this gap is the visible sliver
		Vector2(0, h),                            # bottom: matches black's bottom exactly, fully covers it
	])
	magenta_diamond.color = Color(1.0, 0.0, 1.0, 1.0) # same as backbone_line.default_color
	holder.add_child(magenta_diamond)

	holder.z_index = 1 # above the backbone line
	add_child(holder)
	return holder

func _rebuild_rail():
	# FIX: once Phase.DONE, there is no more transition happening -- every
	# car has already settled at NEW_BOTTOM_TEMPLATE_Y. The normal
	# construction below ALWAYS includes a real step between the bulge
	# point (y=STRAIGHT_Y when loop_depth=0) and the anchor point
	# (y=anchor_rest_y=NEW_BOTTOM_TEMPLATE_Y once baseline_switched) --
	# that step is correct WHILE the loop is active (it's literally the
	# transition geometry), but has no reason to exist once DONE. A car
	# whose fixed .progress happens to sample a point inside that lingering
	# step segment gets stuck at an in-between y forever (confirmed: car[23]
	# stuck at y=362.66, neither 300 nor 390), even though loop_depth
	# itself was already correctly snapped to 0. The real fix is to stop
	# building ANY step/transition geometry once DONE -- just one flat
	# line at the correct resting height, full stop.
	if phase == Phase.DONE:
		var flat_curve = Curve2D.new()
		var rest_y = NEW_BOTTOM_TEMPLATE_Y if baseline_switched else STRAIGHT_Y
		flat_curve.add_point(Vector2(TRACK_LENGTH, rest_y))
		flat_curve.add_point(Vector2(0, rest_y))
		loop_length = 0.0
		rail_path.curve = flat_curve
		rail_visual.points = flat_curve.get_baked_points()
		return

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
	# Reverted to the original 0.25x multiplier (omega-flare experiment
	# undone, per decision to roll the loop geometry back to its
	# known-good pre-backbone-chase state).
	var mid_handle_x = max(1.0, (helicase_x - factory_x) * 0.25)
	curve.add_point(
		Vector2(mid_x, bulge_y),
		Vector2(mid_handle_x, 0),
		Vector2(-mid_handle_x, 0)
	)

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
