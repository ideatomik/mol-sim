extends Node

# ==========================================
# screenshot_capture.gd
# Attach as a child node of the simulation scene root.
# Captures one screenshot per helicase slot step, after all visuals update.
# Filename encodes step, slot, queue size, and release state for easy parsing.
#
# Screenshots saved to: res://screenshots/
# ==========================================

const SCREENSHOT_DIR := "res://screenshots/"

var sim: Node = null
var helicase_mgr: Node = null
var step_count: int = 0
var pending_capture: bool = false
var pending_slot: int = -1

func _ready() -> void:
	# Find simulation root — assumes this node is a child of it
	sim = get_parent()
	if sim == null:
		push_error("[Screenshot] Could not find simulation parent node.")
		return

	# Create screenshot directory if it doesn't exist
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(SCREENSHOT_DIR)
	)

	# Connect after one frame so helicase_mgr is initialized
	call_deferred("_connect_to_helicase")

func _connect_to_helicase() -> void:
	helicase_mgr = sim.helicase_mgr
	if helicase_mgr == null:
		push_error("[Screenshot] helicase_mgr not found on simulation node.")
		return
	helicase_mgr.slot_reached.connect(_on_slot_reached)
	print("[Screenshot] Connected to helicase_mgr.slot_reached")

func _on_slot_reached(index: int) -> void:
	# Flag a capture for end of this frame — after _process has run
	pending_capture = true
	pending_slot = index

func _process(_delta: float) -> void:
	if not pending_capture:
		return
	pending_capture = false
	# Defer to after rendering so the frame is fully drawn
	RenderingServer.frame_post_draw.connect(_capture_frame, CONNECT_ONE_SHOT)

func _capture_frame() -> void:
	if sim == null:
		return

	var slot = pending_slot
	var queue_size = sim.loop_queue.size() if "loop_queue" in sim else 0
	var releasing = sim.loop_releasing if "loop_releasing" in sim else false

	var filename = "step_%04d_slot_%03d_queue_%02d_releasing_%s.png" % [
		step_count,
		slot,
		queue_size,
		"T" if releasing else "F"
	]

	var path = SCREENSHOT_DIR + filename
	var image = get_viewport().get_texture().get_image()
	var err = image.save_png(ProjectSettings.globalize_path(path))
	if err == OK:
		print("[Screenshot] Saved: %s" % filename)
	else:
		push_error("[Screenshot] Failed to save: %s (error %d)" % [filename, err])

	step_count += 1
