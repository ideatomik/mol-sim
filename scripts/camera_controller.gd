extends Camera2D

# ==========================================
# CAMERA CONTROLLER
# Frames the nucleotide strand to 90% of the screen width and centers
# vertically on the midline between the two template strands, so the
# full double-helix system sits in the center of the screen.
# Re-frames automatically on window resize.
# ==========================================

const STRAND_WIDTH_PERCENTAGE: float = 0.90

var _last_viewport_size: Vector2 = Vector2.ZERO

func _ready():
	_frame_strand()

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

	var straight_y: float = simulation.straight_y if "straight_y" in simulation else 300.0
	var dna_ribbons_gap: float = simulation.dna_ribbons_gap if "dna_ribbons_gap" in simulation else 90.0

	# Vertical center: midpoint between top template strand (straight_y - dna_ribbons_gap)
	# and bottom template strand (straight_y). This keeps the full double-helix
	# system centered on screen regardless of dna_ribbons_gap value.
	var mid_y: float = straight_y - dna_ribbons_gap / 2.0

	var viewport_width: float = get_viewport_rect().size.x
	var target_zoom: float = (viewport_width * STRAND_WIDTH_PERCENTAGE) / track_length
	zoom = Vector2(target_zoom, target_zoom)
	global_position = Vector2(track_length / 2.0, mid_y)

	print("[CAM] Framed strand: track_length=%.1f zoom=%.4f mid_y=%.1f" % [
		track_length, target_zoom, mid_y
	])
