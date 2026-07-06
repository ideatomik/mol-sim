extends Camera2D

# ==========================================
# ZOOM MANAGER  (v72 — renamed from camera_controller.gd)
# Per ZoomDesign.md. Level 1's original job (frame the whole strand to 90%
# of viewport width, centered on center_y) is UNCHANGED — see
# _compute_strand_fit(). This file adds levels 2-3 on top of it. Level 4 was
# removed entirely (design decision: two zoom-in steps plus level 1 is
# enough; no target needs a fourth level).
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
# Per-target entry level: all targets now register real content at both
# levels 2 and 3 — {2: fn2, 3: fn3} — so entry_level is 2 across the board;
# select_target() always jumps straight to level 2 for every target now.
# (Earlier, enzymes registered {3: fn} only, with level 2 falling back to
# the generic overworld placeholder — that's been superseded now that
# helicase/leading/lagging polymerase all have real "regional context"
# framing at level 2, matching the new-strand targets' pattern.)
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
const PAN_SCREEN_SPEED: float = 400.0  # px/sec on SCREEN — divided by zoom each
                                        # frame so panning feels the same speed
                                        # regardless of how zoomed in the camera is

var pan_offset_x: float = 0.0  # left/right arrow offset, added on top of whatever the
                                # current frame computes — reset on any target/level/sequence change

var zoom_level: int = 1
var current_target_id: String = ""  # persists across levels once set — see reset_zoom()
var highlight_enabled: bool = false

# id -> {frame_fns: Dictionary[int, Callable], entry_level: int, display_name: String, is_visible_fn: Callable}
var _targets: Dictionary = {}
var _target_order: Array[String] = []  # registration order, used for the dropdown + cycling

var _transition_tween: Tween = null

func _ready():
	# Defer so simulation._ready() has time to call initialize_simulation()
	# and compute track_length before we try to frame the strand.
	_frame_strand.call_deferred()

## Node._input() fires BEFORE GUI input is distributed to focused Controls
## (PlayerUI's Scrubber HSlider included), so consuming ui_left/ui_right here
## reliably stops the slider from ever seeing them — regardless of whether it
## currently has focus. The actual panning movement itself happens in
## _process() below (polling, not per-keypress), so this is purely "claim the
## keys before anything else can."
func _input(event: InputEvent) -> void:
	if event.is_action("ui_left") or event.is_action("ui_right"):
		get_viewport().set_input_as_handled()

func _process(delta):
	# Live tracking (_apply_live_frame / _frame_strand, in the branch below)
	# already recomputes from the current viewport size every frame, so no
	# separate resize hook is needed here anymore.

	# Constant SCREEN speed: dividing by the current zoom converts a fixed
	# px/sec-on-screen rate into the right amount of world-space movement,
	# so panning feels the same regardless of how zoomed in we are.
	var pan_dir: float = 0.0
	if Input.is_action_pressed("ui_left"):
		pan_dir -= 1.0
	if Input.is_action_pressed("ui_right"):
		pan_dir += 1.0
	if pan_dir != 0.0 and zoom.x > 0.0:
		pan_offset_x += pan_dir * PAN_SCREEN_SPEED * delta / zoom.x

	# If the enzyme we're focused on fades out mid-session (proximity fade
	# ending, is_done_phase, etc.) while we're zoomed into it, drop back to
	# level 1 rather than leaving the camera pointed at an enzyme that's no
	# longer there. current_target_id is deliberately NOT cleared here —
	# only reset_zoom() (the full Reset button) does that — so pressing +
	# again resumes trying to focus the SAME enzyme: it succeeds once the
	# enzyme fades back in, or refuses again via the same visibility guard
	# select_target()/set_zoom_level() already use. Clearing it here instead
	# would leave PlayerUI's dropdown still showing the old enzyme selected
	# while + silently fell back to a different default target — a
	# mismatch between what's displayed and what actually happens.
	if current_target_id != "" and zoom_level >= _target_entry_level(current_target_id) and not is_target_visible(current_target_id):
		_transition_to_level(1)
		return

	# Live tracking WITHIN the current level/target — recomputed fresh every
	# frame from whatever the frame-provider returns right now. Never
	# tweened, so this is scrub-safe by construction (same principle as
	# helicase_x being derived fresh each frame rather than cached).
	if current_target_id != "" and zoom_level >= _target_entry_level(current_target_id) and _targets.has(current_target_id):
		_apply_live_frame()
	else:
		_frame_strand()

# ==========================================
# REGISTRATION
# ==========================================

## frame_fns maps zoom level (int) -> Callable. Each Callable may return
## either an Array of Vector2 points (generically fitted via _fit_points(),
## the original enzyme-target contract) or a Dictionary {zoom, position}
## computed directly by the owning script (needed when framing must be
## driven by a single dimension rather than a bounding box — e.g. the
## new-strand targets' height-only "80%/70% of screen height" framing, which
## a generic width-or-height-whichever-is-smaller box fit can't express).
## entry_level is derived as the LOWEST key in frame_fns — this is the level
## select_target() jumps to, and the level below which this target's framing
## doesn't apply at all (falls back to _compute_strand_fit()). All targets
## now register {2: fn2, 3: fn3} (entry_level 2 across the board), so every
## target's dropdown selection lands on level 2 ("regional context") first,
## with + advancing to level 3 ("exclusively focused").
func register_target(id: String, frame_fns: Dictionary, display_name: String, is_visible_fn: Callable = Callable()) -> void:
	var entry_level: int = 3
	for lvl in frame_fns.keys():
		entry_level = min(entry_level, lvl)
	_targets[id] = {
		frame_fns = frame_fns,
		entry_level = entry_level,
		display_name = display_name,
		is_visible_fn = is_visible_fn,  # optional — invalid Callable means "always visible"
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

## display_name is expected to be a translation key (e.g. "ENZYME_HELICASE"),
## not a literal string — this keeps the zoom system's target list wired
## into the same locale system as everything else (LocaleManager /
## enzyme_labels.csv), so it re-translates automatically on locale switch.
func get_target_display_name(id: String) -> String:
	if _targets.has(id):
		return tr(_targets[id].display_name)
	return id

## Whether a target's enzyme is actually on screen right now (faded in,
## not mid-teardown, etc.) — checked live against whatever the owning
## script's is_visible_fn reports (typically its own modulate.a, since that's
## already the single source of truth those scripts use for their proximity
## fade-in logic). A target with no is_visible_fn registered is always
## considered visible (backward compatible).
func is_target_visible(id: String) -> bool:
	var entry = _targets.get(id)
	if entry == null:
		return false
	var fn: Callable = entry.is_visible_fn
	if not fn.is_valid():
		return true
	return fn.call()

## The lowest level at which this target's own framing applies — 3 for
## enzymes, 2 for the new-strand targets. Below this, framing falls back to
## _compute_strand_fit() regardless of current_target_id.
func _target_entry_level(id: String) -> int:
	if _targets.has(id):
		return _targets[id].entry_level
	return 3

# ==========================================
# PLAYER INPUT ENTRY POINTS
# Every input method (UI buttons today; keyboard/click/voice later) is meant
# to converge on these calls — no input method should compute camera math
# itself.
# ==========================================

## Jumps to the target's own entry level (3 for enzymes, 2 for new-strand
## targets — see register_target()). Refuses if the target isn't currently
## visible on screen (e.g. hasn't faded in yet before play starts) — see
## is_target_visible().
func select_target(id: String) -> void:
	if not _targets.has(id):
		push_warning("ZoomManager: unknown target id '%s'" % id)
		return
	if not is_target_visible(id):
		push_warning("ZoomManager: target '%s' isn't visible on screen yet, refusing to zoom in" % id)
		return
	current_target_id = id
	_transition_to_level(_target_entry_level(id))
	target_changed.emit(id)

## Sets current_target_id WITHOUT transitioning levels. Used to sync a
## default or restored dropdown selection (e.g. right after registration,
## or after the target list changes) so state matches what's displayed
## without treating population as a player action. select_target() above is
## still the only thing that jumps to level 3.
func set_pending_target(id: String) -> void:
	if id != "" and not _targets.has(id):
		return
	current_target_id = id
	target_changed.emit(id)

## Walks the 1-3 ladder. Does NOT clear current_target_id when dropping below
## a target's entry level — so going back up later resumes the same enzyme
## (this resolves ZoomDesign.md's "level 2 -> level 3 target memory" open
## question: it remembers). Only reset_zoom() fully clears the target.
## Refuses to enter a level that needs the current target if it isn't
## visible yet (same guard as select_target()) — this is what PlayerUI's +
## button relies on.
func set_zoom_level(level: int) -> void:
	level = clamp(level, 1, 3)
	if current_target_id == "" and _target_order.size() > 0 and level >= 2:
		# Safety net if something calls this directly without a target ever
		# having been picked. PlayerUI is expected to keep + disabled in
		# that state instead of relying on this.
		current_target_id = _target_order[0]
	if current_target_id != "" and level >= _target_entry_level(current_target_id):
		if not is_target_visible(current_target_id):
			push_warning("ZoomManager: cannot enter level %d — '%s' isn't visible on screen yet" % [level, current_target_id])
			return
	_transition_to_level(level)

## Cycles to the next/previous VISIBLE target, skipping any that aren't
## currently on screen. No-ops if nothing is visible to cycle to.
func cycle_target(direction: int) -> void:
	if _target_order.is_empty():
		return
	var start_idx = _target_order.find(current_target_id)
	start_idx = 0 if start_idx == -1 else start_idx
	var n = _target_order.size()
	for step in range(1, n + 1):
		var idx = ((start_idx + direction * step) % n + n) % n
		var candidate = _target_order[idx]
		if is_target_visible(candidate):
			select_target(candidate)
			return

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
	pan_offset_x = 0.0
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
	pan_offset_x = 0.0  # any deliberate level/target change resets manual panning

	var frame: Dictionary
	if current_target_id != "" and level >= _target_entry_level(current_target_id):
		frame = _compute_target_frame(level)
	else:
		frame = _compute_strand_fit()  # generic overworld fit — used below any target's entry level

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
## pan_offset_x deliberately persists through scrub (only target/level/
## sequence changes reset it — scrubbing through time doesn't).
func scrub_snap() -> void:
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	if current_target_id != "" and zoom_level >= _target_entry_level(current_target_id):
		_apply_live_frame()
	else:
		var fit = _compute_strand_fit()
		zoom = Vector2(fit.zoom, fit.zoom)
		global_position = fit.position + Vector2(pan_offset_x, 0.0)

# ==========================================
# FRAMING MATH
# ==========================================

func _apply_live_frame() -> void:
	var frame = _compute_target_frame(zoom_level)
	zoom = Vector2(frame.zoom, frame.zoom)
	global_position = frame.position + Vector2(pan_offset_x, 0.0)

func _compute_target_frame(level: int) -> Dictionary:
	var entry = _targets.get(current_target_id)
	if entry == null:
		return _compute_strand_fit()
	var frame_fn: Callable = entry.frame_fns.get(level)
	if frame_fn == null or not frame_fn.is_valid():
		return _compute_strand_fit()
	var result = frame_fn.call()
	if result is Dictionary:
		# Bespoke framing computed directly by the owning script (e.g. the
		# new-strand targets' height-only "80% of screen height" framing,
		# which a generic bounding-box fit can't express since it always
		# picks whichever of width/height is more constraining).
		if result.is_empty():
			return _compute_strand_fit()
		return result
	# Otherwise treat as an Array of Vector2 points — the original
	# enzyme-target contract — and fit them generically.
	var points: Array = result
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
	global_position = fit.position + Vector2(pan_offset_x, 0.0)

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