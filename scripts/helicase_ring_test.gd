extends Node2D

# ==========================================
# helicase_ring_test.gd  —  STANDALONE HARNESS (not shipped into the sim)
#
# Isolates the barrel-roll animation from everything proven: no helicase_x, no
# x-stepping, no fork, no intro, no scrub_rebuild, no fade. Just the ring
# against a dummy DNA ladder so the see-through front/back pass is visible.
#
# USAGE
#   1. New scene, Node2D root, attach this script, run.
#   2. Drag the ROLL slider to scrub to any pose (play auto-yields to the drag).
#   3. PLAY advances roll with the SAME cubic ease-out the real helicase uses
#      (1 - (1-t)^3 per step), STEP DURATION seconds per step — so the ratchet
#      feel matches what the sim will feed in.
#   4. FROZEN previews rotation_frozen: the static symmetric pose the sim will
#      show during scrub and under the low-info theme. Toggling this while
#      PLAY is on shows the freeze/unfreeze transition itself.
#   5. Select the "HelicaseRing" node in the REMOTE scene tree while running and
#      poke its exports (step_angle_deg, max_blob_width, back_z, ...) live.
#
# WHAT TO WATCH
#   - Does the z-flip land invisibly? A blob flips front<->back at theta=90/270,
#     where it's ~0px tall. Look for any pop as blobs cross the strands.
#   - Flip step_angle_deg 120 -> 60: on odd steps the big blob lands center-BACK
#     (behind the ladder, occluding nothing) instead of center-front.
#   - Back-pass depth: raise/lower the ring's back_z, and try back_alpha < 1.
# ==========================================

@export var dna_ribbons_gap: float = 90.0     # vertical gap between the two dummy strands (sim default)
@export var ladder_rungs: int = 17            # base-pair rungs drawn on the dummy DNA
@export var ladder_width: float = 520.0       # horizontal span of the dummy DNA
@export var dna_line_width: float = 4.0
@export var rung_width: float = 2.0
@export var dna_color: Color = Color(0.55, 0.58, 0.62)
@export var step_duration: float = 0.5        # seconds per step when playing (matches helicase base_step_duration)

const ROLL_RANGE: float = 6.0                 # slider spans 6 steps (a full loop at 60/step, two loops at 120/step)

var ring: HelicaseRing = null
var _slider: HSlider = null
var _play_btn: CheckButton = null
var _frozen_btn: CheckButton = null
var _readout: Label = null

var _playing: bool = false
var _step_index: int = 0
var _t: float = 0.0
var _dragging: bool = false
var _current_roll: float = 0.0

func _ready() -> void:
	z_index = 2   # this node draws the dummy DNA ladder at the sim's real base z; blobs straddle it via absolute front_z/back_z
	_setup_camera()
	_setup_ring()
	_setup_ui()
	_apply_roll(0.0)
	queue_redraw()

func _process(delta: float) -> void:
	if _playing and not _dragging:
		_t += delta / max(step_duration, 0.0001)
		while _t >= 1.0:
			_t -= 1.0
			_step_index += 1
			if _step_index >= int(ROLL_RANGE):
				_step_index = 0
		var eased = 1.0 - pow(1.0 - _t, 3.0)   # mirrors helicase.gd get_eased_step_t()
		var roll = float(_step_index) + eased
		_slider.set_value_no_signal(roll)
		_apply_roll(roll)
	_update_readout()

# ---------- SETUP ----------

func _setup_camera() -> void:
	var cam = Camera2D.new()
	add_child(cam)
	cam.make_current()

func _setup_ring() -> void:
	ring = HelicaseRing.new()
	ring.name = "HelicaseRing"
	add_child(ring)   # sits at (0,0); in the sim it will ride helicase_node.position instead

func _setup_ui() -> void:
	var layer = CanvasLayer.new()
	add_child(layer)

	var panel = VBoxContainer.new()
	panel.position = Vector2(24, 24)
	panel.custom_minimum_size = Vector2(360, 0)
	layer.add_child(panel)

	_readout = Label.new()
	panel.add_child(_readout)

	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = ROLL_RANGE
	_slider.step = 0.001
	_slider.custom_minimum_size = Vector2(360, 24)
	panel.add_child(_slider)
	_slider.value_changed.connect(_on_slider_value_changed)
	_slider.drag_started.connect(_on_slider_drag_started)
	_slider.drag_ended.connect(_on_slider_drag_ended)

	_play_btn = CheckButton.new()
	_play_btn.text = "Play"
	panel.add_child(_play_btn)
	_play_btn.toggled.connect(_on_play_toggled)

	_frozen_btn = CheckButton.new()
	_frozen_btn.text = "Frozen (scrub / low-info pose)"
	panel.add_child(_frozen_btn)
	_frozen_btn.toggled.connect(_on_frozen_toggled)

# ---------- CONTROL ----------

func _apply_roll(roll: float) -> void:
	_current_roll = roll
	if ring != null:
		ring.set_roll(roll)

func _on_slider_value_changed(v: float) -> void:
	# Raw scrub: land on exactly this pose, and reseat the play cursor so
	# resuming continues smoothly from here.
	_apply_roll(v)
	_step_index = int(floor(v))
	_t = v - floor(v)

func _on_slider_drag_started() -> void:
	_dragging = true

func _on_slider_drag_ended(_value_changed: bool) -> void:
	_dragging = false

func _on_play_toggled(pressed: bool) -> void:
	_playing = pressed
	if pressed:
		_step_index = int(floor(_current_roll))
		_t = _current_roll - floor(_current_roll)

func _on_frozen_toggled(pressed: bool) -> void:
	if ring != null:
		ring.rotation_frozen = pressed

# ---------- READOUT ----------

func _update_readout() -> void:
	if _readout == null or ring == null:
		return
	var lines: Array[String] = []
	lines.append("roll %.3f   step_angle %.0f°   blobs %d   frozen %s" % [_current_roll, ring.step_angle_deg, ring.blob_count, ring.rotation_frozen])
	var spacing = TAU / float(max(1, ring.blob_count))
	var step = 0.0 if ring.rotation_frozen else deg_to_rad(ring.step_angle_deg)
	var roll = 0.0 if ring.rotation_frozen else _current_roll
	for i in range(ring.blob_count):
		var theta = roll * step + i * spacing
		var deg = fmod(rad_to_deg(theta), 360.0)
		if deg < 0.0:
			deg += 360.0
		var side = "FRONT" if cos(theta) >= 0.0 else "back"
		lines.append("  blob %d: θ=%3.0f°  %s" % [i, deg, side])
	_readout.text = "\n".join(lines)

# ---------- DUMMY DNA ----------

func _draw() -> void:
	var half = ladder_width * 0.5
	var yt = -dna_ribbons_gap * 0.5
	var yb = dna_ribbons_gap * 0.5
	# rungs first (base pairs), then the two strands on top
	for r in range(ladder_rungs):
		var f = float(r) / float(max(1, ladder_rungs - 1))
		var x = -half + ladder_width * f
		draw_line(Vector2(x, yt), Vector2(x, yb), dna_color, rung_width)
	draw_line(Vector2(-half, yt), Vector2(half, yt), dna_color, dna_line_width)
	draw_line(Vector2(-half, yb), Vector2(half, yb), dna_color, dna_line_width)
