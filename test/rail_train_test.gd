extends Node2D

# ==========================================
# RAIL/TRAIN TEST v15
# Same mechanics as v14 (round 2 fix), plus new debug output for the
# first/last car's actual rendered position vs. their fixed progress --
# to investigate the reported "train shrinking from the right" behavior
# during the pulse.
# ==========================================

@onready var rail_path: Path2D = $RailPath
@onready var rail_visual: Line2D = $RailVisual
@onready var new_strand_line: Line2D = $NewStrandLine
@onready var synthesis_circle: Node2D = $SynthesisCircle

const CAR_SPACING: float = 60.0
const NUM_CARS: int = 24
const STRAIGHT_Y: float = 300.0
const TRACK_LENGTH: float = 1920.0

const LOOP_FLOOR_DEPTH: float = 15.0
const MAX_LOOP_DEPTH: float = 90.0
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

enum Phase { SWEEPING, REVERSING, DONE }
var phase: Phase = Phase.SWEEPING

const REVERSE_SHRINK_DISTANCE: float = 200.0
var reverse_speed: float = 90.0

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

var new_strand_cars: Array[Node2D] = []
var new_strand_car_x: Array[float] = []

func _ready():
	helicase_x = GAP_WIDTH
	factory_x = 0.0
	loop_depth = MAX_LOOP_DEPTH

	pulse_time_budget = PULSE_WIDTH / sweep_speed
	pulse_speed = (2.0 * PULSE_WIDTH) / pulse_time_budget

	_rebuild_rail()
	_spawn_cars()
	# _spawn_new_strand_cars()  # V11: commented out
	_setup_synthesis_circle()

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

			if helicase_x >= TRACK_LENGTH:
				helicase_x = TRACK_LENGTH
				phase = Phase.REVERSING
		Phase.REVERSING:
			factory_x -= reverse_speed * delta

			var widened_by = (helicase_x - factory_x) - GAP_WIDTH
			loop_depth = lerp(MAX_LOOP_DEPTH, 0.0, clamp(widened_by / REVERSE_SHRINK_DISTANCE, 0.0, 1.0))

			if loop_depth <= 0.0:
				loop_depth = 0.0
				phase = Phase.DONE
		Phase.DONE:
			pass

	_rebuild_rail()

	var synthesis_x = (factory_x + helicase_x) / 2.0

	synthesis_circle.position = Vector2(synthesis_x, SYNTHESIS_CIRCLE_Y)

	for i in range(cars.size()):
		cars[i].progress = car_original_x[i]

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
		print("[%s] phase:%s | factory_x:%.1f helicase_x:%.1f loop_depth:%.1f | loop_length:%.1f | loop_population:%d unzipped_population:%d" % [
			Time.get_ticks_msec(), Phase.keys()[phase], factory_x, helicase_x, loop_depth,
			loop_length, loop_count, unzipped_count
		])

		# DEBUG: first and last car's ACTUAL rendered position (not their
		# fixed original_x/progress) -- to check whether the train is
		# genuinely shrinking from one side, or whether progress (which
		# never changes) is being misread as position.
		if cars.size() > 0:
			var first_car = cars[0]
			var last_car = cars[cars.size() - 1]
			print("[%s]   first_car: progress=%.1f position=%s | last_car: progress=%.1f position=%s" % [
				Time.get_ticks_msec(),
				first_car.progress, first_car.position,
				last_car.progress, last_car.position
			])

func _rebuild_rail():
	var curve = Curve2D.new()

	curve.add_point(Vector2(0, STRAIGHT_Y))
	curve.add_point(Vector2(factory_x, STRAIGHT_Y))

	var bulge_y = STRAIGHT_Y + loop_depth
	var handle_x = max(40.0, loop_depth * 0.6)

	curve.add_point(
		Vector2(factory_x, STRAIGHT_Y),
		Vector2.ZERO,
		Vector2(handle_x, loop_depth * 0.5)
	)
	var mid_x = (factory_x + helicase_x) / 2.0
	var mid_handle_x = max(1.0, (helicase_x - factory_x) * 0.25)
	curve.add_point(
		Vector2(mid_x, bulge_y),
		Vector2(-mid_handle_x, 0),
		Vector2(mid_handle_x, 0)
	)
	curve.add_point(
		Vector2(helicase_x, STRAIGHT_Y),
		Vector2(-handle_x, loop_depth * 0.5),
		Vector2.ZERO
	)

	var loop_only_curve = Curve2D.new()
	loop_only_curve.add_point(
		Vector2(factory_x, STRAIGHT_Y),
		Vector2.ZERO,
		Vector2(handle_x, loop_depth * 0.5)
	)
	loop_only_curve.add_point(
		Vector2(mid_x, bulge_y),
		Vector2(-mid_handle_x, 0),
		Vector2(mid_handle_x, 0)
	)
	loop_only_curve.add_point(
		Vector2(helicase_x, STRAIGHT_Y),
		Vector2(-handle_x, loop_depth * 0.5),
		Vector2.ZERO
	)
	loop_length = loop_only_curve.get_baked_length()

	curve.add_point(Vector2(TRACK_LENGTH, STRAIGHT_Y))

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
		car.progress = x
		cars.append(car)

func _spawn_new_strand_cars():
	for i in range(NUM_CARS):
		var car = Node2D.new()
		car.visible = false

		var visual = ColorRect.new()
		visual.size = Vector2(24, 24)
		visual.position = Vector2(-12, -12)
		visual.color = Color(0.5, 0.2, 0.9)
		car.add_child(visual)

		add_child(car)

		var x = i * CAR_SPACING
		new_strand_car_x.append(x)
		car.position = Vector2(x, NEW_STRAND_Y)
		new_strand_cars.append(car)
