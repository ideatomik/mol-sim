extends Camera2D

const STRAND_WIDTH_PERCENTAGE: float = 0.90

var _last_viewport_size: Vector2 = Vector2.ZERO
var track_length: float = 0.0  # not @export

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
		push_warning("new_camera_controller: parent has no track_length, cannot frame strand.")
		return

	var track_length: float = simulation.track_length
	var straight_y: float = simulation.straight_y if "straight_y" in simulation else 300.0

	if track_length <= 0.0:
		push_warning("new_camera_controller: track_length is %.1f, cannot frame strand." % track_length)
		return

	var viewport_width: float = get_viewport_rect().size.x
	var target_zoom: float = (viewport_width * STRAND_WIDTH_PERCENTAGE) / track_length
	zoom = Vector2(target_zoom, target_zoom)
	global_position = Vector2(track_length / 2.0, straight_y)

	print("[CAM] Framed strand: track_length=%.1f viewport_width=%.1f zoom=%.4f pos=%s" % [
		track_length, viewport_width, target_zoom, global_position
	])