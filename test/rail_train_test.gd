extends Node2D

# ==========================================
# RAIL/TRAIN TEST v10
# Adds SYNTHESIS CIRCLE: yellow circle marking the active synthesis point,
# traveling with the sweep, fading out once the last new-strand car appears.
# Everything else is unchanged from v9.
# ==========================================

@onready var rail_path: Path2D = $RailPath
@onready var rail_visual: Line2D = $RailVisual
@onready var new_strand_line: Line2D = $NewStrandLine
@onready var synthesis_circle: Node2D = $SynthesisCircle

const CAR_SPACING: float = 60.0
const NUM_CARS: int = 24
const STRAIGHT_Y: float = 300.0
const TRACK_LENGTH: float = 1800.0

const LOOP_FLOOR_DEPTH: float = 15.0
const MAX_LOOP_DEPTH: float = 90.0
const GAP_WIDTH: float = 168.0 # fixed gap between factory_x and helicase_x during the sweep phase

const CAR_HEIGHT: float = 24.0
const NEW_STRAND_Y: float = STRAIGHT_Y + MAX_LOOP_DEPTH + CAR_HEIGHT

# SYNTHESIS CIRCLE: yellow circle marking the active synthesis point.
# Spawned at the loop's max depth (the deepest point the curve reaches),
# x = synthesis_x (same midpoint value driving the new-strand line/cars).
# Travels with the sweep automatically since it just reads synthesis_x
# every frame -- no separate speed logic. Fades out once the last
# new-strand car has appeared (one-shot trigger, not re-checked after).
const SYNTHESIS_CIRCLE_RADIUS: float = 16.0
const SYNTHESIS_CIRCLE_Y: float = STRAIGHT_Y + MAX_LOOP_DEPTH
const FADE_DURATION: float = 0.6
var synthesis_circle_faded: bool = false

var helicase_x: float = 0.0
var factory_x: float = 0.0
var sweep_speed: float = 90.0
var collapse_speed: float = 90.0

enum Phase { SWEEPING, COLLAPSING, DONE }
var phase: Phase = Phase.SWEEPING

var loop_depth: float = LOOP_FLOOR_DEPTH

var cars: Array[PathFollow2D] = []
var car_original_x: Array[float] = []

var new_strand_cars: Array[Node2D] = []
var new_strand_car_x: Array[float] = []

func _ready():
	helicase_x = GAP_WIDTH
	factory_x = 0.0
	_rebuild_rail()
	_spawn_cars()
	_spawn_new_strand_cars()
	_setup_synthesis_circle()

func _process(delta):
	match phase:
		Phase.SWEEPING:
			helicase_x += sweep_speed * delta
			factory_x = helicase_x - GAP_WIDTH
			loop_depth = MAX_LOOP_DEPTH
			if helicase_x >= TRACK_LENGTH:
				helicase_x = TRACK_LENGTH
				phase = Phase.COLLAPSING
		Phase.COLLAPSING:
			factory_x += collapse_speed * delta
			if factory_x >= helicase_x:
				factory_x = helicase_x
				phase = Phase.DONE
		Phase.DONE:
			pass

	if phase == Phase.COLLAPSING or phase == Phase.DONE:
		var gap = helicase_x - factory_x
		loop_depth = lerp(LOOP_FLOOR_DEPTH, MAX_LOOP_DEPTH, clamp(gap / GAP_WIDTH, 0.0, 1.0))

	_rebuild_rail()

	var synthesis_x = (factory_x + helicase_x) / 2.0

	new_strand_line.points = PackedVector2Array([
		Vector2(0, NEW_STRAND_Y),
		Vector2(synthesis_x, NEW_STRAND_Y)
	])

	for i in range(new_strand_cars.size()):
		new_strand_cars[i].visible = synthesis_x >= new_strand_car_x[i]

	# SYNTHESIS CIRCLE: travels with the sweep by simply reading
	# synthesis_x every frame -- no separate speed logic needed, it's
	# "part of the sweep at that exact point" by construction.
	synthesis_circle.position = Vector2(synthesis_x, SYNTHESIS_CIRCLE_Y)

	# FADE TRIGGER: once the LAST new-strand car has appeared, fade the
	# circle out. One-shot.
	if not synthesis_circle_faded and new_strand_car_x.size() > 0:
		if synthesis_x >= new_strand_car_x[new_strand_car_x.size() - 1]:
			synthesis_circle_faded = true
			var fade_tween = create_tween()
			fade_tween.tween_property(synthesis_circle, "modulate:a", 0.0, FADE_DURATION)

	for i in range(cars.size()):
		cars[i].progress = car_original_x[i]

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

		var x = i * CAR_SPACING
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
