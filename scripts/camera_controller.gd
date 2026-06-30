extends Camera2D

# ==========================================
# CAMERA CONTROLLER
# Frames the nucleotide strand to 90% of the screen width and centers
# vertically on center_y — the helicase's y position and single source of
# truth for replisome positioning (v70.6 helicase-anchored refactor) — so
# the helicase sits at the vertical center of the screen.
# Re-frames automatically on window resize.
# ==========================================

const STRAND_WIDTH_PERCENTAGE: float = 0.90

var _last_viewport_size: Vector2 = Vector2.ZERO

func _ready():
	# Defer so simulation._ready() has time to call initialize_simulation()
	# and compute track_length before we try to frame the strand.
	_frame_strand.call_deferred()

func _process(_delta):
	var current_size = get_viewport_rect().size
	if current_size != _last_viewport_size:
		_last_viewport_size = current_size
		_frame_strand()

func _frame_strand():
	var simulation = get_parent()

	if not "track_length" in simulation:
		push_warning("camera_controller: parent has no track_length, cannot frame strand.")
		return

	var track_length: float = simulation.track_length
	if track_length <= 0.0:
		push_warning("camera_controller: track_length is %.1f, cannot frame strand." % track_length)
		return

	# Vertical center: the helicase is the single source of truth for replisome
	# positioning (center_y), so the camera centers on that directly rather than
	# deriving a midpoint from the template strands.
	var mid_y: float = simulation.center_y if "center_y" in simulation else 360.0

	var viewport_width: float = get_viewport_rect().size.x
	var target_zoom: float = (viewport_width * STRAND_WIDTH_PERCENTAGE) / track_length
	zoom = Vector2(target_zoom, target_zoom)
	global_position = Vector2(track_length / 2.0, mid_y)

	print("[CAM] Framed strand: track_length=%.1f zoom=%.4f mid_y=%.1f" % [
		track_length, target_zoom, mid_y
	])
