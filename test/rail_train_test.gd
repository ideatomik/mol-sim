extends Node2D

# ==========================================
# RAIL/TRAIN TEST v8
# Exact spec, nothing extra:
# 1. Horizontal track, full screen width, static.
# 2. 24 cars, evenly spaced, visible across the whole track from the start.
# 3. The sweep (the loop) starts at the left, moves right at a steady pace
#    -- this is helicase_x advancing alone.
# 4. While the sweep moves, the cars oscillate left/right (visual aid only,
#    not meant to represent real sim behavior -- just lets us watch cars
#    repeatedly pass through the loop).
# 5. Once helicase_x reaches the end of the track, the sweep phase ends.
#    Then factory_x closes the gap toward helicase_x until the loop
#    collapses into a flat line.
# ==========================================

@onready var rail_path: Path2D = $RailPath
@onready var rail_visual: Line2D = $RailVisual
@onready var new_strand_line: Line2D = $NewStrandLine

const CAR_SPACING: float = 60.0
const NUM_CARS: int = 24
const STRAIGHT_Y: float = 300.0
const TRACK_LENGTH: float = 1800.0

const LOOP_FLOOR_DEPTH: float = 15.0
const MAX_LOOP_DEPTH: float = 90.0
const GAP_WIDTH: float = 168.0 # fixed gap between factory_x and helicase_x during the sweep phase

# NEW STRAND REFERENCE LINE: simple static horizontal line, offset down
# from the loop's max depth by one car-height -- "as if the pen tip sat
# CAR_HEIGHT pixels below the deepest point of the curve." Drawn once,
# never updated; not derived from any car or curve, just a fixed reference.
const CAR_HEIGHT: float = 24.0
const NEW_STRAND_Y: float = STRAIGHT_Y + MAX_LOOP_DEPTH + CAR_HEIGHT

var helicase_x: float = 0.0
var factory_x: float = 0.0
var sweep_speed: float = 90.0
var collapse_speed: float = 90.0

enum Phase { SWEEPING, COLLAPSING, DONE }
var phase: Phase = Phase.SWEEPING

var loop_depth: float = LOOP_FLOOR_DEPTH

var cars: Array[PathFollow2D] = []
var car_original_x: Array[float] = []

# NEW-STRAND CARS: same spacing as the template cars, sitting flat on
# NewStrandLine. No Path2D/PathFollow2D needed -- this line never curves,
# so plain Node2D positioning is simpler and correct. Each car becomes
# visible once factory_x (the growing line's leading edge) reaches its
# fixed x -- "appears at the synthesis point as it passes."
var new_strand_cars: Array[Node2D] = []
var new_strand_car_x: Array[float] = []

# Oscillation: cars move back and forth together, purely for repeated
# observation during the sweep phase.
const OSCILLATION_RANGE: float = 600.0
const OSCILLATION_SPEED: float = 0.6 # radians/sec
var oscillation_t: float = 0.0

func _ready():
	helicase_x = GAP_WIDTH
	factory_x = 0.0
	_rebuild_rail()
	_spawn_cars()
	_spawn_new_strand_cars()

func _process(delta):
	match phase:
		Phase.SWEEPING:
			helicase_x += sweep_speed * delta
			factory_x = helicase_x - GAP_WIDTH
			loop_depth = MAX_LOOP_DEPTH # constant depth during the sweep -- this test isn't about depth growth, just the sweep + oscillation + collapse
			if helicase_x >= TRACK_LENGTH:
				helicase_x = TRACK_LENGTH
				phase = Phase.COLLAPSING
		Phase.COLLAPSING:
			# Close the gap: factory_x advances toward the now-fixed
			# helicase_x until they meet, which is what makes the loop
			# visually straighten out into a flat line.
			factory_x += collapse_speed * delta
			if factory_x >= helicase_x:
				factory_x = helicase_x
				phase = Phase.DONE
		Phase.DONE:
			pass

	# Depth interpolates to 0 as the gap closes during collapse, so the
	# curve visibly straightens out instead of staying a deep U with zero
	# width (which would be a degenerate/invisible loop, not a clean
	# straight line).
	if phase == Phase.COLLAPSING or phase == Phase.DONE:
		var gap = helicase_x - factory_x
		loop_depth = lerp(LOOP_FLOOR_DEPTH, MAX_LOOP_DEPTH, clamp(gap / GAP_WIDTH, 0.0, 1.0))

	_rebuild_rail()

	# GROWING LINE: the new-strand reference line's right edge extends in
	# real time, tracking factory_x (the synthesis point) -- not a static
	# one-shot draw anymore. Reads as "the trail left behind as the
	# machine passes overhead," growing from 0 width up to full track
	# width as factory_x advances through both phases (sweep and collapse).
	new_strand_line.points = PackedVector2Array([
		Vector2(0, NEW_STRAND_Y),
		Vector2(factory_x, NEW_STRAND_Y)
	])

	# Reveal new-strand cars as factory_x sweeps past their fixed x --
	# same driver as the line's growth, just a visibility toggle instead
	# of extending a points array. No movement once revealed.
	for i in range(new_strand_cars.size()):
		new_strand_cars[i].visible = factory_x >= new_strand_car_x[i]

	# Oscillate cars only during the sweep phase -- once collapsing starts,
	# let them settle so the collapse itself is easy to watch cleanly.
	if phase == Phase.SWEEPING:
		oscillation_t += delta
		var offset = sin(oscillation_t * OSCILLATION_SPEED) * OSCILLATION_RANGE
		for i in range(cars.size()):
			cars[i].progress = clamp(car_original_x[i] + offset, 0.0, TRACK_LENGTH)
	else:
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
		car.visible = false # revealed in _process once factory_x reaches this car's x

		var visual = ColorRect.new()
		visual.size = Vector2(24, 24)
		visual.position = Vector2(-12, -12)
		visual.color = Color(0.5, 0.2, 0.9) # matches NewStrandLine's purple
		car.add_child(visual)

		add_child(car)

		var x = i * CAR_SPACING
		new_strand_car_x.append(x)
		car.position = Vector2(x, NEW_STRAND_Y)
		new_strand_cars.append(car)
