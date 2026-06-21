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
@export var loop_floor_depth: float = 15.0
@export var max_loop_depth: float = 220.0
@export var gap_width: float = 168.0

@export_group("Speeds & Timing")
@export var sweep_speed: float = 90.0
@export var pulse_car_count: int = 6
@export var fade_duration: float = 0.6

@export_group("Car Visuals")
@export var car_size: Vector2 = Vector2(24, 24)
@export var car_color_even: Color = Color(0.2, 0.6, 0.9)
@export var car_color_odd: Color = Color(0.9, 0.6, 0.2)

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

enum Phase { SWEEPING, FINISHING_LAST_PULSE, DONE }
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
				# FIX: loop_depth was whatever value the pulse cycle
				# happened to be at the instant all cars passed the
				# position check -- could be anywhere from loop_floor_depth
				# (15) up, not necessarily 0. Since nothing in Phase.DONE
				# ever touches loop_depth again, that residual value got
				# frozen into RailVisual's curve forever, leaving a small
				# permanent bulge near the trailing end (visible as the
				# black curve remaining, with the last car's backbone
				# offset dipping toward it since the car's actual position
				# was still very slightly off straight_y/NEW_BOTTOM_
				# TEMPLATE_Y because of that residual curve). Snapping to
				# exactly 0 here guarantees a perfectly flat curve once we
				# stop animating it.
				loop_depth = 0.0
				phase = Phase.DONE
		Phase.DONE:
			if not synthesis_circle_faded:
				synthesis_circle_faded = true
				var fade_tween = create_tween()
				fade_tween.tween_property(synthesis_circle, "modulate:a", 0.0, fade_duration)

	_rebuild_rail()

	var synthesis_x = (factory_x + helicase_x) / 2.0
	synthesis_circle.position = Vector2(synthesis_x, synthesis_circle_y)

	# NewSynthesizedStrandPosition: starts at the left edge of the track,
	# right edge follows synthesis_x (the same x driving the yellow
	# circle) every frame. Once Phase.DONE, synthesis_circle fades out and
	# this stops being updated here too (the loop_depth==0 DONE-phase
	# early return in _rebuild_rail still runs every frame, but nothing
	# currently re-touches synthesis_x in that branch) -- so the line
	# naturally freezes at wherever the circle was when it faded, same as
	# everything else settles at DONE.
	new_synthesized_strand_position.points = PackedVector2Array([
		Vector2(0, new_synthesized_strand_y),
		Vector2(synthesis_x, new_synthesized_strand_y)
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
				if car_y >= straight_y + max_loop_depth:
					car_transfer_state[i] = CarTransferState.ARMED
					print("[t=%s] car[%d] ARMED (y=%.1f)" % [Time.get_ticks_msec(), i, car_y])
			CarTransferState.ARMED:
				if car_y < new_bottom_template_y:
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
	#   - On RailVisual (not yet transferred, resting at ~straight_y=300):
	#     backbone BELOW the cars -- LARGER y than the car.
	#   - On NewBottomTemplateStrandPosition (transferred, resting at
	#     ~new_bottom_template_y=390): backbone ABOVE the cars -- SMALLER y
	#     than the car.
	# These two cases now have GENUINELY OPPOSITE signs (previously they
	# coincidentally matched under the old "away from/inside reference_side"
	# framing, which was the wrong rule).
	# INSIDE THE LOOP: position doesn't matter (confirmed) -- kept the
	# existing simple consistent direction (toward the bulge).
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

		# FLICKER FIX: lerp the actually-applied delta toward target_delta
		# instead of snapping to it instantly -- smooths the visible
		# transition when classification flips rapidly near a threshold.
		car_backbone_delta[i] = lerp(car_backbone_delta[i], target_delta, clamp(backbone_offset_smoothing_speed * delta, 0.0, 1.0))
		backbone_points.append(Vector2(car.position.x, car.position.y + car_backbone_delta[i]))

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
	var h = backbone_line_width / 2.0
	var w = bond_mark_width

	# Bottom: black diamond, full size. 4 points: tip (right), top, back
	# (left), bottom.
	var black_diamond = Polygon2D.new()
	black_diamond.polygon = PackedVector2Array([
		Vector2(w / 2.0, 0),    # tip
		Vector2(0, -h),          # top
		Vector2(-w / 2.0, 0),    # back
		Vector2(0, h),           # bottom
	])
	black_diamond.color = bond_mark_black_color
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
	var back_inset = bond_mark_back_inset
	var magenta_diamond = Polygon2D.new()
	magenta_diamond.polygon = PackedVector2Array([
		Vector2(w / 2.0, 0),                  # tip: matches black's tip exactly, fully covers it
		Vector2(0, -h),                          # top: matches black's top exactly, fully covers it
		Vector2(-w / 2.0 + back_inset, 0),    # back: pulled inward from black's back point -- this gap is the visible sliver
		Vector2(0, h),                            # bottom: matches black's bottom exactly, fully covers it
	])
	magenta_diamond.color = backbone_color # matches the backbone line's own color
	holder.add_child(magenta_diamond)

	holder.z_index = 1 # above the backbone line
	add_child(holder)
	return holder

func _rebuild_rail():
	# FIX: once Phase.DONE, there is no more transition happening -- every
	# car has already settled at new_bottom_template_y. The normal
	# construction below ALWAYS includes a real step between the bulge
	# point (y=straight_y when loop_depth=0) and the anchor point
	# (y=anchor_rest_y=new_bottom_template_y once baseline_switched) --
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
		var rest_y = new_bottom_template_y if baseline_switched else straight_y
		flat_curve.add_point(Vector2(track_length, rest_y))
		flat_curve.add_point(Vector2(0, rest_y))
		loop_length = 0.0
		rail_path.curve = flat_curve
		rail_visual.points = flat_curve.get_baked_points()
		return

	var curve = Curve2D.new()

	curve.add_point(Vector2(track_length, straight_y))
	curve.add_point(Vector2(helicase_x, straight_y))

	var bulge_y = straight_y + loop_depth
	var handle_x = max(40.0, loop_depth * 0.6)

	curve.add_point(
		Vector2(helicase_x, straight_y),
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

	var anchor_rest_y = new_bottom_template_y if baseline_switched else straight_y

	curve.add_point(
		Vector2(factory_x, anchor_rest_y),
		Vector2(handle_x, loop_depth * 0.5),
		Vector2.ZERO
	)

	var loop_only_curve = Curve2D.new()
	loop_only_curve.add_point(
		Vector2(helicase_x, straight_y),
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

		rail_path.add_child(car)

		var x = row_start_x + i * car_spacing
		car_original_x.append(x)
		car.progress = track_length - x
		cars.append(car)
		car_transfer_state.append(CarTransferState.WAITING)
		car_max_y_reached.append(straight_y)
		car_backbone_delta.append(backbone_offset_distance) # starts matching the RailVisual case, since that's where cars begin
