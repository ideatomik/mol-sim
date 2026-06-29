extends Node2D

# ==========================================
# loop_test.gd
# Standalone testbed for the deterministic trombone loop curve.
# No dependencies on ThemeManager, replication_manager, or simulation.gd.
#
# Left/Right arrows: move helicase one slot (drives pulse mechanic)
# Up/Down arrows:    adjust okazaki_fragment_size live
# ==========================================

# ---------- LAYOUT ----------
@export var num_slots: int = 20
@export var slot_spacing: float = 54.0
@export var origin_x: float = 80.0
@export var straight_y: float = 180.0
@export var bottom_y: float = 380.0
@export var gap_width: float = 168.0

# ---------- LOOP SHAPE ----------
@export var max_loop_depth: float = 220.0
@export var loop_floor_depth: float = 15.0

# ---------- PULSE MECHANIC ----------
@export var okazaki_fragment_size: int = 6

# ---------- BULGE SHAPE ----------
# peak_bias > 1.0 shifts peak toward F, < 1.0 shifts toward H
@export var peak_bias: float = 1.5
# smoothstep_strength: 0.0 = pure sine, 1.0 = fully smoothstepped (flat bottom)
@export var smoothstep_strength: float = 0.4

# ---------- CATMULL-ROM ----------
@export var spline_resolution: int = 12

# ---------- ANIMATION ----------
@export var auto_play: bool = false
@export var step_duration: float = 0.4  # Seconds per helicase slot step

# ---------- STATE ----------
var helicase_slot: int = 5
var loop_slots_extra: int = 0  # 0 → okazaki_fragment_size, then resets

# pulse_ratio fully derived from loop_slots_extra
var pulse_ratio: float = 0.0

# Auto-play accumulator
var _step_timer: float = 0.0

# ---------- VISUALS ----------
const SLOT_RADIUS := 10.0
const DOT_COLOR := Color(0.4, 0.85, 1.0)
const DOT_IN_LOOP_COLOR := Color(1.0, 0.6, 0.2)
const BACKBONE_COLOR := Color(0.5, 0.7, 1.0)
const HELICASE_COLOR := Color(1.0, 0.8, 0.2)
const FACTORY_COLOR := Color(1.0, 0.4, 0.4)
const LABEL_COLOR := Color(1.0, 1.0, 1.0, 0.7)
const GUIDE_COLOR := Color(1.0, 1.0, 1.0, 0.12)

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.1, 0.12, 0.18))
	_update_pulse_ratio()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_RIGHT:
				if helicase_slot < num_slots - 1:
					helicase_slot += 1
					loop_slots_extra += 1
					if loop_slots_extra >= okazaki_fragment_size:
						loop_slots_extra = 0  # Fragment complete — loop releases
				_update_pulse_ratio()
				queue_redraw()
			KEY_LEFT:
				if helicase_slot > 0:
					helicase_slot -= 1
					loop_slots_extra = max(0, loop_slots_extra - 1)
				_update_pulse_ratio()
				queue_redraw()
			KEY_UP:
				okazaki_fragment_size = min(okazaki_fragment_size + 1, 20)
				_update_pulse_ratio()
				queue_redraw()
			KEY_DOWN:
				okazaki_fragment_size = max(okazaki_fragment_size - 1, 2)
				_update_pulse_ratio()
				queue_redraw()

func _update_pulse_ratio() -> void:
	pulse_ratio = float(loop_slots_extra) / float(okazaki_fragment_size)

func _process(delta: float) -> void:
	if not auto_play:
		return
	_step_timer += delta
	if _step_timer >= step_duration:
		_step_timer -= step_duration
		# Advance helicase; wrap back to start when it reaches the end
		helicase_slot += 1
		if helicase_slot >= num_slots:
			helicase_slot = 3  # Leave some flat slots on the left
			loop_slots_extra = 0
		else:
			loop_slots_extra += 1
			if loop_slots_extra >= okazaki_fragment_size:
				loop_slots_extra = 0
		_update_pulse_ratio()
		queue_redraw()

func _draw() -> void:
	var helicase_x := origin_x + helicase_slot * slot_spacing
	var factory_x := helicase_x - gap_width
	var loop_depth := lerp(loop_floor_depth, max_loop_depth, pulse_ratio)

	# loop_right_x is always helicase_x — the gap is fixed.
	# pulse_ratio drives depth, not gap width.
	var loop_right_x := helicase_x

	# ---- Guide lines ----
	draw_line(Vector2(0, straight_y), Vector2(origin_x + num_slots * slot_spacing, straight_y), GUIDE_COLOR, 1.0)
	draw_line(Vector2(0, bottom_y), Vector2(origin_x + num_slots * slot_spacing, bottom_y), GUIDE_COLOR, 1.0)

	# ---- Helicase and factory markers ----
	draw_line(Vector2(helicase_x, straight_y - 30), Vector2(helicase_x, straight_y + loop_depth + 30), HELICASE_COLOR, 2.0)
	draw_line(Vector2(factory_x, straight_y - 30), Vector2(factory_x, bottom_y + 30), FACTORY_COLOR, 2.0)

	# ---- Compute all slot anchor positions ----
	var anchors: Array[Vector2] = []
	var in_loop_flags: Array[bool] = []
	for i in range(num_slots):
		var x := origin_x + i * slot_spacing
		var in_loop := x > factory_x and x <= loop_right_x
		in_loop_flags.append(in_loop)
		anchors.append(_get_anchor(x, factory_x, loop_right_x, loop_depth))

	# ---- Draw Catmull-Rom spline ----
	var p_start := Vector2(anchors[0].x - slot_spacing, bottom_y)
	var p_end := Vector2(anchors[anchors.size() - 1].x + slot_spacing, straight_y)
	var padded: Array[Vector2] = []
	padded.append(p_start)
	padded.append_array(anchors)
	padded.append(p_end)

	var spline_points: Array[Vector2] = []
	for seg in range(anchors.size() - 1):
		var p0 := padded[seg]
		var p1 := padded[seg + 1]
		var p2 := padded[seg + 2]
		var p3 := padded[seg + 3]
		for step in range(spline_resolution):
			var t := float(step) / float(spline_resolution)
			spline_points.append(_catmull_rom(p0, p1, p2, p3, t))
	spline_points.append(anchors[anchors.size() - 1])

	for i in range(spline_points.size() - 1):
		draw_line(spline_points[i], spline_points[i + 1], BACKBONE_COLOR, 3.0)

	# ---- Draw slot dots ----
	for i in range(anchors.size()):
		var color := DOT_IN_LOOP_COLOR if in_loop_flags[i] else DOT_COLOR
		draw_circle(anchors[i], SLOT_RADIUS, color)

	# ---- Labels ----
	draw_string(ThemeDB.fallback_font, Vector2(helicase_x + 6, straight_y - 18), "H", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, HELICASE_COLOR)
	draw_string(ThemeDB.fallback_font, Vector2(factory_x + 6, straight_y - 18), "F", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, FACTORY_COLOR)
	draw_string(ThemeDB.fallback_font, Vector2(8, 24),
		"← → : move helicase    ↑ ↓ : okazaki size    slot=%d   extra=%d/%d   pulse=%.2f   depth=%.1f" % [helicase_slot, loop_slots_extra, okazaki_fragment_size, pulse_ratio, loop_depth],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, LABEL_COLOR)

# ==========================================
# ANCHOR POSITION — one per slot
# ==========================================

func _get_anchor(x: float, factory_x: float, loop_right_x: float, loop_depth: float) -> Vector2:
	if x > loop_right_x:
		return Vector2(x, straight_y)
	elif x <= factory_x:
		return Vector2(x, bottom_y)
	else:
		# t = 0.0 at factory_x (exit, bottom_y), t = 1.0 at helicase_x (entry, straight_y)
		var t := (x - factory_x) / (loop_right_x - factory_x)
		return Vector2(x, _sine_loop_y(t, loop_depth))

func _sine_loop_y(t: float, loop_depth: float) -> float:
	# Base lerp from bottom_y (t=0) to straight_y (t=1)
	var base_y := lerp(bottom_y, straight_y, t)
	# Biased sine: peak_bias > 1.0 shifts peak toward F, < 1.0 shifts toward H
	var raw := sin(pow(t, peak_bias) * PI)
	# Smoothstep shaping: flattens the bottom of the loop
	var shaped := lerp(raw, smoothstep(0.0, 1.0, raw), smoothstep_strength)
	return base_y + shaped * loop_depth

# ==========================================
# CATMULL-ROM INTERPOLATION
# ==========================================

func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		(2.0 * p1) +
		(-p0 + p2) * t +
		(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
		(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)
