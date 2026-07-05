extends Camera2D

# ==========================================
# ZOOM MANAGER  (v72 — renamed from camera_controller.gd)
# Per ZoomDesign.md. Level 1's original job (frame the whole strand to 90%
# of viewport width, centered on center_y) is UNCHANGED — see
# _compute_strand_fit(). This file adds levels 2-4 on top of it.
#
# Ownership contract (see ZoomDesign.md "core design problem" section):
# targets register a frame-provider Callable, not a static point list or a
# cached Node2D — leading_polymerase and helicase_node are both freed and
# recreated on every sequence load (confirmed in replication_manager.gd /
# simulation.gd), so anything cached here would go stale on reload. The
# Callables close over the persistent owning manager (replication_mgr /
# simulation.gd itself) and look up the live node each call.
#
# Highlight: this script only ever QUERIES dim factors
# (get_enzyme_highlight_dim / get_strand_highlight_dim). It never writes
# modulate/self_modulate on nodes it doesn't own — the owning scripts
# (replication_manager.gd, simulation.gd) apply those factors themselves,
# so there's exactly one writer per property (no fights with the existing
# proximity fade-in tweens).
#
# v72 scope note: levels 2 and 4 are placeholders this pass — level 2 reuses
# level 1's whole-track fit, level 4 reuses level 3's framing. Real framing
# for both is deferred until their own design lands (see ZoomDesign.md open
# questions).
# ==========================================

signal zoom_level_changed(new_level: int)
signal target_changed(new_target_id: String)
signal highlight_changed(enabled: bool)
signal targets_changed()  # fires on register_target()/unregister_target() — lets any UI
                          # (PlayerUI's dropdown today; complexity-toggle-driven
                          # re-registration later) stay in sync without polling.

const STRAND_WIDTH_PERCENTAGE: float = 0.90
const LEVEL34_PADDING: float = 160.0  # world-space padding around framed points
const LEVEL_TRANSITION_DURATION: float = 0.5

var _last_viewport_size: Vector2 = Vector2.ZERO

var zoom_level: int = 1
var current_target_id: String = ""  # persists across levels once set — see reset_zoom()
var highlight_enabled: bool = false

# id -> {level3_frame_fn: Callable, level4_frame_fn: Callable, display_name: String}
var _targets: Dictionary = {}
var _target_order: Array[String] = []  # registration order, used for the dropdown + cycling

var _transition_tween: Tween = null

func _ready():
	# Defer so simulation._ready() has time to call initialize_simulation()
	# and compute track_length before we try to frame the strand.
	_frame_strand.call_deferred()

func _process(_delta):
	var current_size = get_viewport_rect().size
	if current_size != _last_viewport_size:
		_last_viewport_size = current_size
		# Levels 3/4 recompute zoom from the live viewport size every frame
		# anyway (see _apply_live_frame), so only 1/2 need an explicit
		# resize hook.
		if zoom_level <= 2:
			_frame_strand()

	# Live tracking WITHIN the current level/target — recomputed fresh every
	# frame from whatever the frame-provider returns right now. Never
	# tweened, so this is scrub-safe by construction (same principle as
	# helicase_x being derived fresh each frame rather than cached).
	if zoom_level >= 3 and current_target_id != "" and _targets.has(current_target_id):
		_apply_live_frame()

# ==========================================
# REGISTRATION
# ==========================================

func register_target(id: String, level3_frame_fn: Callable, level4_frame_fn: Callable, display_name: String) -> void:
	_targets[id] = {
		level3_frame_fn = level3_frame_fn,
		level4_frame_fn = level4_frame_fn,
		display_name = display_name,
	}
	if not _target_order.has(id):
		_target_order.append(id)
	targets_changed.emit()

func unregister_target(id: String) -> void:
	_targets.erase(id)
	_target_order.erase(id)
	if current_target_id == id:
		reset_zoom()
	targets_changed.emit()

func get_target_ids() -> Array[String]:
	return _target_order.duplicate()

func get_target_display_name(id: String) -> String:
	if _targets.has(id):
		return _targets[id].display_name
	return id

# ==========================================
# PLAYER INPUT ENTRY POINTS
# Every input method (UI buttons today; keyboard/click/voice later) is meant
# to converge on these calls — no input method should compute camera math
# itself.
# ==========================================

## Always jumps to level 3 for the given target (per design decision).
func select_target(id: String) -> void:
	if not _targets.has(id):
		push_warning("ZoomManager: unknown target id '%s'" % id)
		return
	current_target_id = id
	_transition_to_level(3)
	target_changed.emit(id)

## Walks the 1-4 ladder. Does NOT clear current_target_id when dropping below
## level 3 — so going back up to 3/4 later resumes the same enzyme (this
## resolves ZoomDesign.md's "level 2 -> level 3 target memory" open question:
## it remembers). Only reset_zoom() fully clears the target.
func set_zoom_level(level: int) -> void:
	level = clamp(level, 1, 4)
	if level >= 3 and current_target_id == "" and _target_order.size() > 0:
		# Safety net if something calls this directly without a target ever
		# having been picked. PlayerUI is expected to keep + disabled in
		# that state instead of relying on this.
		current_target_id = _target_order[0]
	_transition_to_level(level)

func cycle_target(direction: int) -> void:
	if _target_order.is_empty():
		return
	var idx = _target_order.find(current_target_id)
	idx = 0 if idx == -1 else (idx + direction + _target_order.size()) % _target_order.size()
	select_target(_target_order[idx])

func set_highlight_enabled(enabled: bool) -> void:
	highlight_enabled = enabled
	highlight_changed.emit(enabled)

## Full reset: clears the selected target AND returns to level 1, animated.
func reset_zoom() -> void:
	current_target_id = ""
	_transition_to_level(1)

## Same as reset_zoom() but instant — for a fresh sequence load, where an
## animated pan across the old track would look wrong.
func reset_zoom_instant() -> void:
	current_target_id = ""
	zoom_level = 1
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	var fit = _compute_strand_fit()
	zoom = Vector2(fit.zoom, fit.zoom)
	global_position = fit.position
	zoom_level_changed.emit(1)

# ==========================================
# LEVEL / TARGET TRANSITIONS
# Discrete, player-triggered, animated during live play. Live tracking
# WITHIN a level (in _process above) is never tweened — only the
# level/target CHANGE itself is. See ZoomDesign.md's scrub-safety split.
# ==========================================

func _transition_to_level(level: int) -> void:
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()

	var frame: Dictionary
	match level:
		3, 4:
			frame = _compute_target_frame(level)
		_:
			frame = _compute_strand_fit()  # levels 1 and 2 (placeholder) both fit-to-whole-track

	zoom_level = level
	_transition_tween = create_tween()
	_transition_tween.set_parallel(true)
	_transition_tween.tween_property(self, "zoom", Vector2(frame.zoom, frame.zoom), LEVEL_TRANSITION_DURATION)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_transition_tween.tween_property(self, "global_position", frame.position, LEVEL_TRANSITION_DURATION)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	zoom_level_changed.emit(level)

## Called by simulation.gd's scrub functions so an in-flight level/target
## tween can't be caught mid-flight by a scrub — same pattern helicase.gd's
## set_phase() uses to force state during scrub rather than tweening
## through it. Scrub is always instant; this makes the camera match.
func scrub_snap() -> void:
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	if zoom_level >= 3 and current_target_id != "":
		_apply_live_frame()
	else:
		var fit = _compute_strand_fit()
		zoom = Vector2(fit.zoom, fit.zoom)
		global_position = fit.position

# ==========================================
# FRAMING MATH
# ==========================================

func _apply_live_frame() -> void:
	var frame = _compute_target_frame(zoom_level)
	zoom = Vector2(frame.zoom, frame.zoom)
	global_position = frame.position

func _compute_target_frame(level: int) -> Dictionary:
	var entry = _targets.get(current_target_id)
	if entry == null:
		return _compute_strand_fit()
	var frame_fn: Callable = entry.level3_frame_fn if level == 3 else entry.level4_frame_fn
	var points: Array = frame_fn.call()
	if points.is_empty():
		return _compute_strand_fit()
	return _fit_points(points, LEVEL34_PADDING)

func _fit_points(points: Array, padding: float) -> Dictionary:
	var min_pos: Vector2 = points[0]
	var max_pos: Vector2 = points[0]
	for p in points:
		min_pos.x = min(min_pos.x, p.x)
		min_pos.y = min(min_pos.y, p.y)
		max_pos.x = max(max_pos.x, p.x)
		max_pos.y = max(max_pos.y, p.y)
	var center = (min_pos + max_pos) / 2.0
	var size = (max_pos - min_pos) + Vector2(padding, padding) * 2.0
	size.x = max(size.x, 1.0)
	size.y = max(size.y, 1.0)
	var viewport_size = get_viewport_rect().size
	var target_zoom = min(viewport_size.x / size.x, viewport_size.y / size.y)
	return {zoom = target_zoom, position = center}

func _frame_strand() -> void:
	var fit = _compute_strand_fit()
	zoom = Vector2(fit.zoom, fit.zoom)
	global_position = fit.position
	print("[ZOOM] Framed strand: zoom=%.4f pos=%s" % [fit.zoom, str(fit.position)])

func _compute_strand_fit() -> Dictionary:
	var simulation = get_parent()
	if not "track_length" in simulation or simulation.track_length <= 0.0:
		return {zoom = 1.0, position = global_position}
	var track_length: float = simulation.track_length
	var mid_y: float = simulation.center_y if "center_y" in simulation else 360.0
	var viewport_width: float = get_viewport_rect().size.x
	var target_zoom: float = (viewport_width * STRAND_WIDTH_PERCENTAGE) / track_length
	return {zoom = target_zoom, position = Vector2(track_length / 2.0, mid_y)}

# ==========================================
# HIGHLIGHT — queried by owning scripts, never written here (see file banner).
# ==========================================

func get_enzyme_highlight_dim(id: String) -> float:
	if not highlight_enabled or current_target_id == "":
		return 1.0
	return 1.0 if id == current_target_id else 0.10

func get_strand_highlight_dim() -> float:
	if not highlight_enabled or current_target_id == "":
		return 1.0
	return 0.50
