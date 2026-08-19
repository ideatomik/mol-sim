extends Camera2D

# ==========================================
# ZOOM MANAGER  (v72 — renamed from camera_controller.gd)
# Per ZoomDesign.md. Level 1's original job (frame the whole strand to 90%
# of the along-axis viewport extent, centered on center_y) is UNCHANGED — see
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

# ---------- ORIENTATION (VerticalModeDesign.md) ----------
## Rotates the CAMERA -90 degrees so the track — which is ALWAYS world +x, in
## both modes — runs top->bottom on screen for 1080x1920 recording. Nothing in
## the simulation's own coordinate space changes; this file is the only place
## that knows which screen axis is which.
##
## Explicit toggle rather than aspect-derived: predictability while recording
## beats auto-detection.
##
## Set this BEFORE loading a sequence. Toggling it at runtime rotates the
## camera immediately, but glyph counter-rotation is PUSHED into bases at
## spawn time (nitrogen_base.gd is ThemeManager-free by contract), so text
## stays sideways until the next sequence reload rebuilds them.
@export var vertical_mode: bool = false:
	set(value):
		vertical_mode = value
		if is_inside_tree():
			_apply_orientation()

var pan_offset_x: float = 0.0  # WASD offset ALONG THE TRACK (world x in both
                                # modes — only the key binding swaps, see
                                # _pan_key_positive()). Added on top of whatever the
                                # current frame computes — reset on any target/level/sequence change

# Set by _compute_strand_fit() as a side effect each time it runs — true
# when level 1 is currently in windowed (cross-axis-fit) mode (long
# sequence). Auto-release below is scoped to this specifically, per
# LongSequenceDesign.md Part 3: levels 2/3 keep today's "sticky until
# deliberate change" pan behavior unchanged.
var _is_windowed_mode: bool = false
var _pan_idle_time: float = 0.0
var _pan_release_tween: Tween = null

var zoom_level: int = 1
var current_target_id: String = ""  # persists across levels once set — see reset_zoom()
var highlight_enabled: bool = false

# ---------- Free camera mode (mouse pan/zoom) ----------
# Orthogonal to the discrete zoom_level system above — while active, NEITHER
# _apply_live_frame() (target-driven) NOR _frame_strand()/_compute_strand_fit()
# (auto-fit) touch the camera at all; _process() below early-returns and the
# camera is driven entirely by _unhandled_input(). Entered by any background
# left-click-drag or any scroll-wheel input (both also clear current_target_id
# — "background" here just means the click/scroll wasn't already claimed by
# an enzyme's own drag-scrub, checked via is_input_handled() rather than any
# collision detection of our own). Exited only two ways, both explicit
# player actions: picking a target again (select_target()), or ResetZoomButton
# (reset_zoom()) — no automatic snap-back on its own.
var _free_camera_mode: bool = false
var _free_camera_zoom: float = 1.0
# Where scroll-zoom is EASING toward — _free_camera_zoom is the applied
# value _process() lerps toward this every frame (see _ease_free_camera_zoom()).
# Stepped from its own current value (not the eased one) so rapid successive
# ticks compound correctly mid-ease instead of restarting from wherever the
# ease happens to be that frame.
var _free_camera_target_zoom: float = 1.0
var _free_camera_zoom_anchor_screen: Vector2 = Vector2.ZERO
var _free_camera_position: Vector2 = Vector2.ZERO
var _free_camera_dragging: bool = false
var _free_camera_drag_last_mouse: Vector2 = Vector2.ZERO
var _free_camera_recenter_tween: Tween = null  # separate from _pan_release_tween — tweens a Vector2, not pan_offset_x

# ---------- Follow mode (double-click an enzyme) ----------
# A FOURTH mutually-exclusive camera state, alongside free camera and the
# level-based target system above — not a variant of either. Like target
# mode, position is auto-derived every frame from the target's own
# frame-provider (see _compute_follow_position()); like free camera, zoom is
# held independently in a local var and only ever changed by scroll, never
# by _process(). The frame provider's own zoom half is deliberately ignored —
# see FollowModeDesign's "manual zoom + auto position" framing.
#
# Entered/switched via request_follow(id) — double-click on an enzyme's own
# click region (helicase_ring.gd / polymerase_clamp.gd, same region
# drag-to-scrub already uses). A second double-click on the ALREADY-followed
# enzyme instead toggles highlight (request_follow()'s own branch) rather
# than re-entering. Exited via: double-click on empty background
# (routes through reset_zoom(), same as ResetZoomButton), or a quick
# press-release tap on empty background (see _follow_paused below).
var _follow_mode: bool = false
var _follow_target_id: String = ""
var _follow_zoom: float = 1.0
# Scroll-nudge target that _process() eases _follow_zoom toward each frame —
# same applied-vs-target split as free camera's _free_camera_target_zoom.
var _follow_target_zoom: float = 1.0

# A background press while following doesn't immediately decide what it is —
# it could resolve as a tap (drop follow, enter free camera), a hold (pause
# in place), or a hold-then-drag (pan), and the difference is only knowable
# at release (or once motion happens). So a press always freezes the camera
# in place first (_follow_paused = true, position/zoom held constant by
# _process() skipping its follow branch), then release/motion resolve which
# of the three outcomes actually happened.
var _follow_paused: bool = false
var _follow_pause_moved: bool = false
var _follow_pause_press_ticks: int = 0
var _follow_pause_position: Vector2 = Vector2.ZERO
var _follow_pause_drag_last_mouse: Vector2 = Vector2.ZERO
const FOLLOW_PAUSE_TAP_THRESHOLD_MSEC: int = 250  # below this + no movement = a tap, not a hold. NOT YET TUNED.

# Per ZoomDesign.md's own anticipated "critically-damped-spring clamp" note
# on follow speed: resuming from a pause/drag eases back toward the LIVE
# target position (recomputed every frame, not a frozen snapshot — the
# followed enzyme keeps moving during the ease) rather than snapping
# instantly. Bounded by a fixed duration rather than a distance epsilon,
# since a constant-velocity target never lets a pure distance check settle.
var _follow_resuming: bool = false
var _follow_resume_elapsed: float = 0.0
var _follow_resume_start_position: Vector2 = Vector2.ZERO

# id -> {frame_fns: Dictionary[int, Callable], entry_level: int, display_name: String, is_visible_fn: Callable}
var _targets: Dictionary = {}
var _target_order: Array[String] = []  # registration order, used for the dropdown + cycling

var _transition_tween: Tween = null

var tm: Node = null  # ThemeManager reference, cached in _ready() — all
                      # zoom-tuning floats + the shared legible_reference_length
                      # live there now (see "Zoom & Long-Sequence Display" group).

func _ready():
	tm = get_node("%ThemeManager")
	_apply_orientation()
	# Defer so simulation._ready() has time to call initialize_simulation()
	# and compute track_length before we try to frame the strand.
	_frame_strand.call_deferred()

## Camera2D.ignore_rotation defaults to TRUE in Godot 4 — without clearing it,
## `rotation` is silently ignored and vertical mode does nothing at all, with
## no error. Same class of silent-failure trap as the CSV localization
## registration and LocaleManager's unique-name flag. Set unconditionally
## rather than only in vertical mode, so there's no state where it's true.
func _apply_orientation() -> void:
	ignore_rotation = false
	rotation_degrees = -90.0 if vertical_mode else 0.0

## The viewport extent the track runs ALONG. Public because the frame
## providers in simulation.gd / replication_manager.gd compute their own zoom
## and must ASK rather than read get_viewport() themselves — this file stays
## the single source of truth for the axis mapping.
func get_along_extent() -> float:
	var vp: Vector2 = get_viewport_rect().size
	return vp.y if vertical_mode else vp.x

## The viewport extent ACROSS the track (strand thickness, replisome height).
## World y in both modes — perpendicular to the strand either way.
func get_cross_extent() -> float:
	var vp: Vector2 = get_viewport_rect().size
	return vp.x if vertical_mode else vp.y

## The local rotation a glyph must carry to render upright on screen. Content
## at world rotation psi appears at psi - rotation, so cancelling to zero means
## matching the camera's own rotation exactly.
##
## PUSHED to nodes rather than read by them: nitrogen_base.gd is
## ThemeManager-free by contract and cannot look this up, and helicase_ring.gd
## holds no external references at all. Both receive it like any other injected
## visual value (set_colors/set_font/set_style).
##
## NOTE for EnzymeLabel under the leading clamp: that node carries scale.y = -1,
## and reflection conjugates rotation (S * R(t) * S = R(-t)), so a mirrored
## parent renders a local t as world -t. Mirrored labels must therefore pass
## -get_label_counter_rotation(). Bases are unmirrored and pass it as-is.
func get_label_counter_rotation() -> float:
	return rotation

## WASD pans ALONG the track. pan_offset_x itself needs no change between
## modes — it's applied as a world-x offset and world x is along-track in
## both — so only which physical key means "forward" swaps. Raw keycodes,
## not Godot's ui_left/ui_right/ui_up/ui_down actions — those are used
## pervasively by every focusable Control for arrow-key focus navigation
## project-wide, so remapping them at the input-map level would change
## keyboard UI navigation everywhere, not just camera pan. Checking
## Input.is_key_pressed() directly (in _process() below) leaves those
## actions untouched — same approach player_ui.gd's own shortcut handler
## uses (event.keycode, not named actions). PlaybackShortcutsDesign.md's
## keyboard layer claims the arrow keys for base/fragment stepping now,
## which is what prompted this move off them.
func _pan_key_negative() -> Key:
	return KEY_W if vertical_mode else KEY_A

func _pan_key_positive() -> Key:
	return KEY_S if vertical_mode else KEY_D

## Screen-space pixel offset -> world-space offset. The ONLY screen->world
## conversion in this file; every other quantity here is world-native. In
## horizontal mode `rotation` is 0.0, so .rotated() is identity and this is
## bit-identical to the raw division it replaces.
func _screen_to_world_offset(screen_delta: Vector2, zoom_value: float) -> Vector2:
	if zoom_value <= 0.0:
		return Vector2.ZERO
	return (screen_delta / zoom_value).rotated(rotation)

## Background click-drag (pan) and scroll-wheel (zoom) — free camera mode,
## see the var block above. Runs as _unhandled_input specifically so any
## enzyme's own drag-scrub (helicase_ring.gd / polymerase_clamp.gd, both
## call set_input_as_handled() when THEY claim a click) gets first refusal —
## is_input_handled() is checked explicitly rather than relying on sibling
## node call-order alone.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if get_viewport().is_input_handled():
					return  # an enzyme already claimed this click
				if event.double_click:
					# The other half of "double-click an enzyme to follow
					# it": double-click on empty background exits follow (or
					# free camera, or a selected target) back to level 1.
					reset_zoom()
					get_viewport().set_input_as_handled()
					return
				if _follow_mode:
					_enter_follow_pause(event.position)
					get_viewport().set_input_as_handled()
					return
				_enter_free_camera_mode()
				if _free_camera_recenter_tween != null and _free_camera_recenter_tween.is_valid():
					_free_camera_recenter_tween.kill()
				_free_camera_dragging = true
				_free_camera_drag_last_mouse = event.position
				get_viewport().set_input_as_handled()
			elif _follow_paused:
				_exit_follow_pause()
				get_viewport().set_input_as_handled()
			elif _free_camera_dragging:
				_free_camera_dragging = false
				get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if get_viewport().is_input_handled():
				return
			if _follow_mode:
				_follow_nudge_zoom(1)
			else:
				_free_camera_scroll_zoom(event.position, 1)
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if get_viewport().is_input_handled():
				return
			if _follow_mode:
				_follow_nudge_zoom(-1)
			else:
				_free_camera_scroll_zoom(event.position, -1)
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
			# Single middle-click == ResetZoomButton, double == RecenterPanButton.
			# Godot's own event.double_click already debounces this the same
			# way MOUSE_BUTTON_LEFT's click/double-click split above does -
			# no separate timer needed. reset_zoom()/recenter_pan() are the
			# same public entry points those two PlayerUI buttons call.
			if get_viewport().is_input_handled():
				return
			if event.double_click:
				recenter_pan()
			else:
				reset_zoom()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if _follow_paused:
			_follow_pause_drag(event.position)
		elif _free_camera_dragging:
			# Standard "grab canvas" convention: content follows the mouse, so
			# the camera moves OPPOSITE the drag, converted from screen pixels
			# to world units via the current zoom.
			var delta_screen: Vector2 = event.position - _free_camera_drag_last_mouse
			_free_camera_drag_last_mouse = event.position
			if _free_camera_zoom > 0.0:
				_free_camera_position -= _screen_to_world_offset(delta_screen, _free_camera_zoom)
				zoom = Vector2(_free_camera_zoom, _free_camera_zoom)
				global_position = _free_camera_position

func _process(delta):
	# Keyboard pan is free like mouse pan: W/S (screen-vertical) previously had
	# NO binding outside vertical_mode, because _pan_key_negative()/
	# _pan_key_positive() only ever return ONE axis's keys at a time (A/D in
	# horizontal, W/S in vertical) — a single along-track scalar, not real 2D
	# pan. Pressing W/S in horizontal mode did nothing at all — the reported bug.
	#
	# Fix: any of the four screen-fixed keys can now ENTER free camera mode on
	# its own, exactly like a mouse drag/scroll already does — "free like mouse
	# pan" applies to entry, not just to motion once inside it. A/D's own
	# pre-existing cold-start behavior (the pan_offset_x branch further down,
	# untouched) still works exactly as before; this only adds the
	# previously-missing W/S case. Guarded against follow mode, matching how
	# A/D already has no effect there (the _follow_mode branch below returns
	# before reaching pan code).
	if not _free_camera_mode and not _follow_mode:
		var focus_is_text_field: bool = get_viewport().gui_get_focus_owner() is LineEdit
		if not focus_is_text_field and (Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_S)):
			_enter_free_camera_mode()

	if _free_camera_mode:
		# Position/drag are still fully owned by _unhandled_input() while this
		# is active, EXCEPT WASD - mouse-drag pan and the scroll-zoom ease
		# don't preclude also polling the same keys the level-based branch
		# below uses, so WASD keeps working after scroll-zoom enters free
		# camera mode instead of going dead. Unrotated Vector2(x, 0.0), same
		# as the level-based pan branch below and _apply_live_frame()/
		# _frame_strand()/scrub_snap(): world x is always along-track by
		# design, and _pan_key_negative()/_pan_key_positive() already pick
		# the orientation-correct physical key, so no further rotation
		# belongs here. (Previously wrongly .rotated(rotation) here, copying
		# _screen_to_world_offset()'s screen-to-world conversion for
		# mouse-drag - wrong precedent, since that one starts from a
		# screen-space delta rather than a world-space along-track one. The
		# mismatch sent vertical-mode W/S along the cross-track axis.)
				# TRUE 2D pan, screen-space fixed regardless of orientation — A/D is
		# always screen-horizontal, W/S is always screen-vertical. Replaces the
		# old single-axis _pan_key_negative()/_pan_key_positive() swap (which
		# picked ONE physical key pair depending on vertical_mode and could
		# only move along that one axis). Routed through
		# _screen_to_world_offset() — the same rotation-aware screen->world
		# conversion mouse-drag already uses — so no manual per-orientation
		# swap is needed here: in horizontal mode this reduces to plain
		# world-x/y; in vertical mode it correctly maps W/S to along-track and
		# A/D to cross-track, matching what the camera's own rotation already
		# does for the mouse.
		_ease_free_camera_zoom(delta)
		var screen_dir := Vector2.ZERO
		var focus_is_text_field: bool = get_viewport().gui_get_focus_owner() is LineEdit
		if not focus_is_text_field:
			if Input.is_key_pressed(KEY_A):
				screen_dir.x -= 1.0
			if Input.is_key_pressed(KEY_D):
				screen_dir.x += 1.0
			if Input.is_key_pressed(KEY_W):
				screen_dir.y -= 1.0
			if Input.is_key_pressed(KEY_S):
				screen_dir.y += 1.0
		if screen_dir != Vector2.ZERO and _free_camera_zoom > 0.0:
			# normalized() so a diagonal (e.g. W+D) isn't sqrt(2)x faster than
			# a single key — matches how mouse-drag speed doesn't depend on
			# drag angle either.
			var world_offset: Vector2 = _screen_to_world_offset(screen_dir.normalized() * tm.zoom_pan_screen_speed * delta, _free_camera_zoom)
			_free_camera_position += world_offset
			global_position = _free_camera_position
		return

	if _follow_mode:
		# Same fade-out safety net as the level-based target branch below —
		# if the followed enzyme fades out mid-session, drop back to level 1
		# rather than leaving the camera pointed at nothing.
		if not is_target_visible(_follow_target_id):
			exit_follow_mode()
			_transition_to_level(1)
			return
		if not _follow_paused:
			if _follow_resuming:
				_follow_resume_elapsed += delta
				var t: float = clamp(_follow_resume_elapsed / tm.zoom_follow_resume_duration, 0.0, 1.0)
				var eased_t: float = 1.0 - pow(1.0 - t, 3.0)  # cubic ease-out, matching this file's tween curves elsewhere
				global_position = _follow_resume_start_position.lerp(_compute_follow_position(), eased_t)
				if t >= 1.0:
					_follow_resuming = false
			else:
				global_position = _compute_follow_position()
				var ease_t: float = 1.0 - exp(-tm.zoom_scroll_ease_speed * delta)
				_follow_zoom = lerp(_follow_zoom, _follow_target_zoom, ease_t)
			zoom = Vector2(_follow_zoom, _follow_zoom)
		return  # position/zoom fully owned by follow mode while this is active —
		        # same "one writer" shape as free camera above; WASD pan and
		        # the level-based tracking below don't apply here.

	# Live tracking (_apply_live_frame / _frame_strand, in the branch below)
	# already recomputes from the current viewport size every frame, so no
	# separate resize hook is needed here anymore.

	# Constant SCREEN speed: dividing by the current zoom converts a fixed
	# px/sec-on-screen rate into the right amount of world-space movement,
	# so panning feels the same regardless of how zoomed in we are.
	# gui_get_focus_owner() guard: Input.is_key_pressed() polls raw key
	# state regardless of GUI focus, so without this, typing 'A' — a real,
	# common DNA/RNA base letter — into the Sequence Loader's LineEdit
	# would also pan the camera on every keystroke.
	var pan_dir: float = 0.0
	var _focus_is_text_field: bool = get_viewport().gui_get_focus_owner() is LineEdit
	if not _focus_is_text_field and Input.is_key_pressed(_pan_key_negative()):
		pan_dir -= 1.0
	if not _focus_is_text_field and Input.is_key_pressed(_pan_key_positive()):
		pan_dir += 1.0
	if pan_dir != 0.0 and zoom.x > 0.0:
		pan_offset_x += pan_dir * tm.zoom_pan_screen_speed * delta / zoom.x

	# Auto-release: level-1 windowed mode only (LongSequenceDesign.md Part 3
	# — confirmed scope, levels 2/3 unchanged). Two release triggers exist:
	# this inactivity timeout, and the explicit recenter_pan() a player can
	# call directly (wired to a button in PlayerUI.tscn).
	var in_level1_windowed = zoom_level == 1 and _is_windowed_mode
	if pan_dir != 0.0:
		_pan_idle_time = 0.0
		if _pan_release_tween != null and _pan_release_tween.is_valid():
			_pan_release_tween.kill()  # resuming manual pan cancels any in-flight release
	elif in_level1_windowed and pan_offset_x != 0.0:
		_pan_idle_time += delta
		if _pan_idle_time >= tm.zoom_pan_release_inactivity_seconds:
			_tween_pan_to_zero()
			_pan_idle_time = 0.0

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
	# Let an in-flight level/target transition tween finish uninterrupted —
	# live-tracking resumes once it completes, rather than racing it every
	# frame with a direct snap to the same properties it's animating.
	if _transition_tween != null and _transition_tween.is_valid():
		return
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
## new-strand targets' cross-axis-only "80%/70% of the cross-axis extent"
## framing, which a generic whichever-axis-is-more-constraining box fit
## can't express).
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
## `duration`/`trans_type`/`ease_type`: see _transition_to_level()'s own
## comment — optional, defaults reproduce prior behavior exactly.
func select_target(id: String, duration: float = -1.0, trans_type: Tween.TransitionType = Tween.TRANS_CUBIC, ease_type: Tween.EaseType = Tween.EASE_OUT) -> void:
	if not _targets.has(id):
		push_warning("ZoomManager: unknown target id '%s'" % id)
		return
	if not is_target_visible(id):
		push_warning("ZoomManager: target '%s' isn't visible on screen yet, refusing to zoom in" % id)
		return
	_free_camera_mode = false  # exits free camera — picking a target is one of its two explicit exits
	exit_follow_mode()  # a different input method (dropdown, cycle) picking a target should override follow too
	current_target_id = id
	_transition_to_level(_target_entry_level(id), duration, trans_type, ease_type)
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
	if _free_camera_mode:
		# Zoom In/Out buttons become continuous nudges here instead of
		# discrete level jumps — there's no target to frame against in this
		# mode. Direction is reliably encoded by level vs. the (otherwise
		# stale, unused-for-math) zoom_level, since both button handlers
		# always pass zoom_level ± 1.
		_free_camera_nudge_zoom(1 if level > zoom_level else -1)
		return
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

## =/- keyboard shortcut entry point for "no target selected" — the discrete
## 1-3 ladder above has nothing to frame against in that state (short of the
## level>=2 safety net silently picking a target the player never chose), so
## this routes straight to the same continuous free-camera zoom the mouse
## wheel uses, anchored at the viewport center like _free_camera_nudge_zoom()
## (Zoom In/Out buttons) already do. Deliberately NOT folded into
## set_zoom_level() itself — that function's callers (1/2/3 tier keys,
## trailer.gd) rely on its no-target safety net picking a target rather than
## silently diverting into free-camera mode.
func nudge_free_zoom(direction: int) -> void:
	_free_camera_nudge_zoom(direction)

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

## Whether level 1 is currently in windowed (cross-axis-fit) mode — lets
## PlayerUI disable the recenter button when it isn't relevant (short
## sequence, normal fit-to-track view).
func is_windowed_mode() -> bool:
	return _is_windowed_mode

## Explicit recenter action (LongSequenceDesign.md Part 3) — distinct from
## the full reset_zoom(), which also clears the target and returns to level
## 1. In level-1 windowed mode, this tweens pan_offset_x back to zero.
## In free-camera mode, it pulls double duty (per your ask): centers the
## whole track horizontally (and vertically, back to center_y) WITHOUT
## touching zoom — same position ResetZoomButton's level-1 snap would use,
## just without the zoom part.
func recenter_pan() -> void:
	if _free_camera_mode:
		_recenter_free_camera()
	else:
		_tween_pan_to_zero()

func _recenter_free_camera() -> void:
	var simulation = get_parent()
	var track_length: float = simulation.track_length if "track_length" in simulation else 0.0
	var mid_y: float = simulation.center_y if "center_y" in simulation else global_position.y
	var target_pos: Vector2 = Vector2(track_length * 0.5, mid_y)
	if _free_camera_recenter_tween != null and _free_camera_recenter_tween.is_valid():
		_free_camera_recenter_tween.kill()
	_free_camera_recenter_tween = create_tween()
	_free_camera_recenter_tween.tween_method(_set_free_camera_position, _free_camera_position, target_pos, tm.zoom_pan_release_tween_duration)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## tween_method callback rather than tweening global_position directly —
## keeps _free_camera_position (the authoritative state the drag/scroll
## handlers read and write) in sync throughout, so the next drag or scroll
## doesn't yank the view back to a stale pre-tween value. Same class of bug
## the missing lagging_polymerase_tween.kill() caused earlier this session.
func _set_free_camera_position(p: Vector2) -> void:
	_free_camera_position = p
	global_position = p

## Scripted equivalent of a player's own free-camera scroll/drag — for
## camera_regent.gd's recorded shots. Puts the camera into REAL free-camera
## mode (not a level/target framing), so anything gated on
## free_camera_mode() — molecule_structure_renderer.gd's atom-tier skeletal
## rendering is gated exactly this way, deliberately never activated by the
## level/target system (see that file's _compute_active() comment) —
## activates precisely as it would for a real player's own scroll-zoom,
## just driven by an explicit duration/easing instead of the fixed
## player-facing scroll-zoom ease. Reuses _free_camera_recenter_tween
## (already the "tween the free camera to a new position" tween — this is
## the same operation, now also animating zoom and driven by caller-
## supplied params) rather than adding a second tracked tween var. Keeps
## _free_camera_zoom/_free_camera_target_zoom/_free_camera_position in sync
## throughout via tween_method + setter (same pattern _recenter_free_
## camera()/_set_free_camera_position() already use for position alone) —
## so a player scrolling/dragging right after this shot ends resumes from
## consistent, non-stale free-camera state instead of jumping.
func enter_scripted_free_camera(target_zoom: float, target_position: Vector2, duration: float, trans_type: Tween.TransitionType, ease_type: Tween.EaseType) -> void:
	exit_follow_mode()
	set_pending_target("")
	# Seed from the camera's ACTUAL current zoom/position (same as
	# _enter_free_camera_mode() does) — NOT from whatever _free_camera_zoom/
	# _free_camera_position already happen to hold. Those private vars are
	# only kept live while ALREADY in free-camera mode; arriving here from
	# level-based mode (the normal case — this shot starts cold) leaves
	# them at stale/default values (zoom=1.0, position=(0,0), i.e. world
	# origin) that have nothing to do with where the camera is actually
	# showing right now. Tweening from THAT instead of the real current
	# state is what caused the reported "camera swings over to the first
	# residue, then back to the target" — the tween's own start point was
	# wrong, not the target.
	if not _free_camera_mode:
		_free_camera_zoom = zoom.x
		_free_camera_position = global_position
	_free_camera_mode = true
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	if _pan_release_tween != null and _pan_release_tween.is_valid():
		_pan_release_tween.kill()
	if _free_camera_recenter_tween != null and _free_camera_recenter_tween.is_valid():
		_free_camera_recenter_tween.kill()
	_free_camera_recenter_tween = create_tween()
	_free_camera_recenter_tween.set_parallel(true)
	_free_camera_recenter_tween.tween_method(_set_free_camera_zoom, _free_camera_zoom, target_zoom, duration)\
		.set_trans(trans_type).set_ease(ease_type)
	_free_camera_recenter_tween.tween_method(_set_free_camera_position, _free_camera_position, target_position, duration)\
		.set_trans(trans_type).set_ease(ease_type)

## tween_method callback, same reasoning as _set_free_camera_position()
## above — keeps _free_camera_zoom AND _free_camera_target_zoom equal to
## the tween's current value every step, which is what makes
## _ease_free_camera_zoom()'s is_equal_approx() early-return every frame
## while this tween is running (no competing per-frame ease fighting this
## scripted one).
func _set_free_camera_zoom(z: float) -> void:
	_free_camera_zoom = z
	_free_camera_target_zoom = z
	zoom = Vector2(z, z)

func _tween_pan_to_zero() -> void:
	if _pan_release_tween != null and _pan_release_tween.is_valid():
		_pan_release_tween.kill()
	_pan_release_tween = create_tween()
	_pan_release_tween.tween_property(self, "pan_offset_x", 0.0, tm.zoom_pan_release_tween_duration)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Full reset: clears the selected target AND returns to level 1, animated.
## Also the explicit exit from free-camera mode AND follow mode — per your
## call, a clean snap back to level 1 via ResetZoomButton or a double-click
## on empty background.
func reset_zoom() -> void:
	_free_camera_mode = false
	exit_follow_mode()
	current_target_id = ""
	_transition_to_level(1)

## Same as reset_zoom() but instant — for a fresh sequence load, where an
## animated pan across the old track would look wrong.
func reset_zoom_instant() -> void:
	_free_camera_mode = false
	exit_follow_mode()
	current_target_id = ""
	zoom_level = 1
	pan_offset_x = 0.0
	_pan_idle_time = 0.0
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	if _pan_release_tween != null and _pan_release_tween.is_valid():
		_pan_release_tween.kill()
	if _free_camera_recenter_tween != null and _free_camera_recenter_tween.is_valid():
		_free_camera_recenter_tween.kill()
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

## `duration`/`trans_type`/`ease_type` are optional per-call overrides —
## default (-1.0 sentinel, TRANS_CUBIC, EASE_OUT) reproduces the ORIGINAL
## hardcoded behavior exactly for every existing caller (reset_zoom(),
## set_zoom_level(), select_target()'s own default), so this is purely
## additive: nothing about normal level/target navigation changes unless a
## caller explicitly asks for something different. Added for
## camera_regent.gd's scripted shots, which need Inspector-tunable
## duration/easing per shot rather than sharing the one global
## tm.zoom_level_transition_duration every other transition uses.
func _transition_to_level(level: int, duration: float = -1.0, trans_type: Tween.TransitionType = Tween.TRANS_CUBIC, ease_type: Tween.EaseType = Tween.EASE_OUT) -> void:
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	if _pan_release_tween != null and _pan_release_tween.is_valid():
		_pan_release_tween.kill()
	if _free_camera_recenter_tween != null and _free_camera_recenter_tween.is_valid():
		_free_camera_recenter_tween.kill()
	pan_offset_x = 0.0  # any deliberate level/target change resets manual panning
	_pan_idle_time = 0.0

	var frame: Dictionary
	if current_target_id != "" and level >= _target_entry_level(current_target_id):
		frame = _compute_target_frame(level)
	else:
		frame = _compute_strand_fit()  # generic overworld fit — used below any target's entry level

	var actual_duration: float = duration if duration >= 0.0 else tm.zoom_level_transition_duration
	zoom_level = level
	_transition_tween = create_tween()
	_transition_tween.set_parallel(true)
	_transition_tween.tween_property(self, "zoom", Vector2(frame.zoom, frame.zoom), actual_duration)\
		.set_trans(trans_type).set_ease(ease_type)
	_transition_tween.tween_property(self, "global_position", frame.position, actual_duration)\
		.set_trans(trans_type).set_ease(ease_type)
	zoom_level_changed.emit(level)

## Called by simulation.gd's scrub functions so an in-flight level/target
## tween can't be caught mid-flight by a scrub — same pattern helicase.gd's
## set_phase() uses to force state during scrub rather than tweening
## through it. Scrub is always instant; this makes the camera match.
## pan_offset_x deliberately persists through scrub (only target/level/
## sequence changes reset it — scrubbing through time doesn't).
func scrub_snap() -> void:
	if _free_camera_mode:
		return  # scrubbing changes which base is synthesized, not where the
		        # player is looking — free camera stays exactly where it is
	if _follow_mode:
		# Bypass the resume-smoothing clamp entirely on scrub — jump straight
		# to the live target. Same "clamps are live-play-only, scrub always
		# snaps instantly" split every other scrub-driven value in this file
		# already follows (see the class of bug this exact omission caused
		# for lagging_polymerase_tween, noted below).
		_follow_resuming = false
		if not _follow_paused:
			global_position = _compute_follow_position()
			zoom = Vector2(_follow_zoom, _follow_zoom)
		return
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	if _pan_release_tween != null and _pan_release_tween.is_valid():
		_pan_release_tween.kill()
		pan_offset_x = 0.0  # the release tween's own end state — snap rather
		                    # than leave it frozen mid-interpolation
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
		# new-strand targets' cross-axis-only "80% of the cross-axis extent"
		# framing, which a generic bounding-box fit can't express since it
		# always picks whichever axis is more constraining).
		if result.is_empty():
			return _compute_strand_fit()
		return result
	# Otherwise treat as an Array of Vector2 points — the original
	# enzyme-target contract — and fit them generically.
	var points: Array = result
	if points.is_empty():
		return _compute_strand_fit()
	return _fit_points(points, tm.zoom_level34_padding)

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
	# size.x is always the world-x span and size.y always the world-y span; the
	# extent helpers supply whichever viewport dimension each currently maps to.
	# Because the rotation is exactly 90 degrees, a world-axis-aligned box stays
	# axis-aligned in camera space — no point transformation is needed.
	#
	# NOTE: currently unreached. Every registered target returns a Dictionary
	# {zoom, position}, so the Array/bounding-box contract has no live caller.
	# Kept axis-correct anyway so it isn't a trap for the next provider.
	var target_zoom := minf(get_along_extent() / size.x, get_cross_extent() / size.y)
	return {zoom = target_zoom, position = center}

func _frame_strand() -> void:
	var fit = _compute_strand_fit()
	zoom = Vector2(fit.zoom, fit.zoom)
	global_position = fit.position + Vector2(pan_offset_x, 0.0)

func _compute_strand_fit() -> Dictionary:
	var simulation = get_parent()
	if not "track_length" in simulation or simulation.track_length <= 0.0:
		_is_windowed_mode = false
		return {zoom = 1.0, position = global_position}
	var track_length: float = simulation.track_length
	var mid_y: float = simulation.center_y if "center_y" in simulation else 360.0
	var along_extent: float = get_along_extent()
	var track_zoom: float = _compute_track_fit_zoom(along_extent, track_length)

	# Threshold: would the whole track still fit legibly right now? Defined
	# live against viewport math (per your call), tied to the shared
	# legible_reference_length rather than an arbitrary standalone zoom
	# float — see _compute_reference_zoom().
	var min_readable_zoom = _compute_reference_zoom(simulation, along_extent)
	if min_readable_zoom <= 0.0 or track_zoom >= min_readable_zoom:
		_is_windowed_mode = false
		return {zoom = track_zoom, position = Vector2(track_length / 2.0, mid_y)}

	_is_windowed_mode = true
	return _compute_cross_axis_fit(simulation, mid_y)

## Shared by _compute_strand_fit() above (level 1, gated by the legibility
## threshold) and _compute_free_camera_min_zoom() below (free-camera mode's
## zoom-out floor, UNGATED — this doubles as "Level 0" with no separate fit
## formula needed: for short sequences it's identical to what level 1
## already shows, for long ones it's smaller than the windowed level-1 zoom,
## letting the player scroll out further to see the whole track).
func _compute_track_fit_zoom(along_extent: float, track_length: float) -> float:
	return (along_extent * tm.zoom_along_axis_percentage) / track_length

## The zoom _compute_strand_fit() would produce for a
## tm.legible_reference_length (57) base sequence at the current along-axis
## viewport extent — "the last known-good size." Used as the live windowed-
## mode threshold instead of a hardcoded nucleotide-count cutoff, so it stays
## correct if nucleotide_slot_spacing or viewport size ever change. Returns
## 0.0 (never triggers windowed mode) if simulation doesn't expose the
## geometry needed to compute it.
func _compute_reference_zoom(simulation, along_extent: float) -> float:
	if not ("nucleotide_slot_spacing" in simulation and "polymerase_x_offset_slots" in simulation):
		return 0.0
	var spacing: float = simulation.nucleotide_slot_spacing
	var offset: float = simulation.polymerase_x_offset_slots * spacing
	var reference_track_length: float = float(tm.legible_reference_length - 1) * spacing + 2.0 * offset
	if reference_track_length <= 0.0:
		return 0.0
	return _compute_track_fit_zoom(along_extent, reference_track_length)

## Level 1 for sequences long enough that fitting the track's whole along-axis
## extent would fall below the readable floor (LongSequenceDesign.md Part 3's
## "windowed" mode). Zoom is derived from a FIXED CROSS-AXIS content span
## instead of the (now arbitrarily long) track extent, so bases/enzymes stay a
## legible, constant size regardless of sequence length — the track simply runs
## past the viewport along-axis, and position.x below keeps the active
## synthesis point in view instead of centering the whole track.
##
## tm.zoom_cross_axis_content_span/tm.zoom_cross_axis_fit_percentage are NOT
## YET TUNED — placeholder values pending real numbers in-engine, per
## LongSequenceDesign.md. Now Inspector-editable via ThemeManager.
func _compute_cross_axis_fit(simulation, mid_y: float) -> Dictionary:
	var target_zoom: float = (get_cross_extent() * tm.zoom_cross_axis_fit_percentage) / tm.zoom_cross_axis_content_span

	# Follow anchor: midpoint of helicase_x/polymerase_x (leading), per
	# ZoomDesign.md's already-resolved decision — deliberately NOT the
	# lagging polymerase, whose per-fragment jump-back would make the anchor
	# itself jump. Falls back to keeping the camera's current x if simulation
	# doesn't expose these (rather than defaulting to some dimensionally
	# unrelated value).
	var follow_x: float = global_position.x
	if "helicase_x" in simulation and "polymerase_x" in simulation:
		follow_x = (simulation.helicase_x + simulation.polymerase_x) / 2.0
	elif "track_length" in simulation:
		follow_x = simulation.track_length / 2.0

	return {zoom = target_zoom, position = Vector2(follow_x, mid_y)}

# ==========================================
# FREE CAMERA MODE (mouse pan/zoom)
# ==========================================

## Entered by any background drag-start or scroll-wheel input. Seeds free-
## camera state from the camera's CURRENT zoom/position, so entry is
## seamless — whatever level/target framing was showing stays exactly where
## it was, just now under full manual control. Idempotent for the mode-entry
## part (a second call while already active doesn't re-seed), but still
## clears the target every time — "background drag/scroll always clears the
## target," even if it was already clear.
func _enter_free_camera_mode() -> void:
	if not _free_camera_mode:
		_free_camera_mode = true
		_free_camera_zoom = zoom.x
		_free_camera_target_zoom = zoom.x
		_free_camera_position = global_position
		if _transition_tween != null and _transition_tween.is_valid():
			_transition_tween.kill()
		if _pan_release_tween != null and _pan_release_tween.is_valid():
			_pan_release_tween.kill()
	set_pending_target("")

## Whether the camera is currently in free camera mode — lets PlayerUI adapt
## button behavior/disabled-state (Zoom In/Out become continuous nudges;
## RecenterPanButton doesn't apply here since pan_offset_x isn't in play).
func free_camera_mode() -> bool:
	return _free_camera_mode

## Zoom-toward-cursor (Illustrator/Photoshop convention): keeps the world
## point under mouse_screen fixed across the zoom change, rather than
## zooming toward the viewport center. Also used by _free_camera_nudge_zoom()
## below (Zoom In/Out buttons), passing the viewport center as mouse_screen
## since a button press has no cursor position of its own to anchor to.
func _free_camera_scroll_zoom(mouse_screen: Vector2, direction: int) -> void:
	_enter_free_camera_mode()
	if _free_camera_recenter_tween != null and _free_camera_recenter_tween.is_valid():
		_free_camera_recenter_tween.kill()
	var step: float = tm.zoom_free_camera_scroll_step
	_free_camera_target_zoom = _free_camera_target_zoom * step if direction > 0 else _free_camera_target_zoom / step
	_free_camera_target_zoom = clamp(_free_camera_target_zoom, _compute_free_camera_min_zoom(), tm.zoom_free_camera_max_zoom_in)
	# Held constant across the whole ease (not recomputed per-frame from the
	# CURRENT mouse position) — the point under the cursor AT SCROLL TIME
	# stays anchored as the eased zoom catches up, same convention the old
	# instant-apply math used.
	_free_camera_zoom_anchor_screen = mouse_screen

## Per-frame catch-up for _free_camera_target_zoom, called from _process()
## while free-camera mode is active. Reuses the same cursor-anchored
## compensation math the old instant-apply version of _free_camera_scroll_zoom()
## used, just applied incrementally (old_zoom -> this frame's eased zoom)
## instead of in one jump.
func _ease_free_camera_zoom(delta: float) -> void:
	if is_equal_approx(_free_camera_zoom, _free_camera_target_zoom):
		return
	var old_zoom: float = _free_camera_zoom
	var t: float = 1.0 - exp(-tm.zoom_scroll_ease_speed * delta)
	_free_camera_zoom = lerp(_free_camera_zoom, _free_camera_target_zoom, t)
	if abs(_free_camera_zoom - _free_camera_target_zoom) < 0.001:
		_free_camera_zoom = _free_camera_target_zoom

	# viewport_size * 0.5 is the SCREEN centre — a genuinely screen-space
	# quantity, so it is NOT axis-swapped. Only the screen->world conversion of
	# the resulting offset is orientation-aware.
	var viewport_size: Vector2 = get_viewport_rect().size
	var screen_offset: Vector2 = _free_camera_zoom_anchor_screen - viewport_size * 0.5
	var world_before: Vector2 = _free_camera_position + _screen_to_world_offset(screen_offset, old_zoom)
	var world_after: Vector2 = _free_camera_position + _screen_to_world_offset(screen_offset, _free_camera_zoom)
	_free_camera_position += world_before - world_after

	zoom = Vector2(_free_camera_zoom, _free_camera_zoom)
	global_position = _free_camera_position

## Zoom In/Out buttons while in free-camera mode — see set_zoom_level()'s
## free-camera branch. No cursor position associated with a button press, so
## this zooms toward the viewport center instead of reusing scroll-zoom's
## cursor-anchored math directly.
func _free_camera_nudge_zoom(direction: int) -> void:
	_free_camera_scroll_zoom(get_viewport_rect().size * 0.5, direction)

## The zoom-out FLOOR for free-camera mode — literally _compute_strand_fit()'s
## own ungated whole-track-fit value (see _compute_track_fit_zoom()'s doc
## comment for why this doubles as "Level 0" with no separate fit formula
## needed).
func _compute_free_camera_min_zoom() -> float:
	var simulation = get_parent()
	if not "track_length" in simulation or simulation.track_length <= 0.0:
		return 0.1
	return _compute_track_fit_zoom(get_along_extent(), simulation.track_length)

# ==========================================
# FOLLOW MODE (double-click an enzyme)
# ==========================================

## Single entry point for "double-click an enzyme" input — mirrors
## select_target()'s role as the convergence point input methods funnel
## through (helicase_ring.gd / polymerase_clamp.gd's own follow_requested
## signal, connected by their owning scripts). Two behaviors, matching your
## spec:
## - Not already following `id` -> enter/switch onto it. Same call covers
##   both "first double-click" and "double-click a DIFFERENT enzyme while
##   already following one" (switches directly, no need to route through
##   reset_zoom() first).
## - Already following `id` -> a second double-click on the SAME enzyme
##   toggles highlight instead — the second trigger for what HighlightButton
##   does, per your call.
func request_follow(id: String) -> void:
	if not _targets.has(id) or not is_target_visible(id):
		return
	if _follow_mode and _follow_target_id == id:
		set_highlight_enabled(not highlight_enabled)
		return
	_free_camera_mode = false
	_follow_paused = false
	_follow_resuming = false
	_follow_mode = true
	_follow_target_id = id
	current_target_id = id  # keeps get_enzyme_highlight_dim()/get_strand_highlight_dim() working unchanged
	# Seed from whatever zoom is already showing — "keep the wheel-set zoom
	# while following" — then clamp into the follow-specific (tighter) range,
	# same seed-then-clamp shape _enter_free_camera_mode()/_free_camera_scroll_zoom()
	# already use for their own zoom var.
	_follow_zoom = clamp(zoom.x, tm.zoom_follow_min_zoom, tm.zoom_free_camera_max_zoom_in)
	_follow_target_zoom = _follow_zoom
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	target_changed.emit(id)

## The only way follow mode ends without going through reset_zoom() (target
## fade-out in _process(), or select_target() picking something via a
## different input method). Doesn't touch current_target_id or zoom_level —
## callers that need those cleared too (reset_zoom(), the fade-out branch in
## _process()) do that themselves right after, same division of labor
## _free_camera_mode's own clearing already has.
func exit_follow_mode() -> void:
	_follow_mode = false
	_follow_target_id = ""
	_follow_paused = false
	_follow_resuming = false

func follow_mode() -> bool:
	return _follow_mode

## Position only — the followed target's own frame provider's zoom half is
## deliberately ignored (follow mode's zoom is independently held in
## _follow_zoom, never derived). Uses the target's entry_level framing
## ("regional context") rather than level 3 ("exclusively focused"): a
## continuously-moving follow shot wants the steadier, wider framing, not
## the tightest one. World-y is always pinned to center_y regardless of what
## the provider computed — "the strand stays centred and only scrolls
## vertically" (in vertical mode; the world-x/y meaning of "vertical" is
## still ZoomManager's own rotation, unchanged by follow mode).
func _compute_follow_position() -> Vector2:
	var frame = _compute_target_frame(_target_entry_level(_follow_target_id))
	var simulation = get_parent()
	var mid_y: float = simulation.center_y if "center_y" in simulation else global_position.y
	return Vector2(frame.position.x, mid_y)

## Scroll wheel while following — same cursor-independent nudge shape as
## _free_camera_nudge_zoom() (no cursor anchor point needed since position
## isn't player-controlled here), clamped into the follow-specific range.
func _follow_nudge_zoom(direction: int) -> void:
	var step: float = tm.zoom_free_camera_scroll_step
	_follow_target_zoom = _follow_target_zoom * step if direction > 0 else _follow_target_zoom / step
	_follow_target_zoom = clamp(_follow_target_zoom, tm.zoom_follow_min_zoom, tm.zoom_free_camera_max_zoom_in)

## A background press while following freezes the camera in place
## immediately — "click and hold: hold camera in current place" — rather
## than waiting to see whether it resolves into a tap, a hold, or a drag.
## _process()'s follow branch skips live-tracking whenever _follow_paused is
## true, so simply not writing position/zoom here IS the freeze.
func _enter_follow_pause(press_screen_position: Vector2) -> void:
	_follow_paused = true
	_follow_pause_moved = false
	_follow_pause_press_ticks = Time.get_ticks_msec()
	_follow_pause_position = global_position
	_follow_pause_drag_last_mouse = press_screen_position

## Any motion during a follow-pause is a drag — pan the camera exactly like
## free camera's own drag math, but writing _follow_pause_position (not
## _free_camera_position) and using the held _follow_zoom (not
## _free_camera_zoom) for the screen->world conversion, since we're not
## actually in free-camera mode.
func _follow_pause_drag(mouse_screen: Vector2) -> void:
	_follow_pause_moved = true
	var delta_screen: Vector2 = mouse_screen - _follow_pause_drag_last_mouse
	_follow_pause_drag_last_mouse = mouse_screen
	if _follow_zoom > 0.0:
		_follow_pause_position -= _screen_to_world_offset(delta_screen, _follow_zoom)
		global_position = _follow_pause_position
		zoom = Vector2(_follow_zoom, _follow_zoom)

## Release resolves the pause into one of two outcomes:
## - A quick tap (no movement, released inside the threshold) -> a genuine
##   "full click," per your spec: drop follow, enter free camera from
##   wherever the camera already is (unchanged, since a non-moved pause
##   never wrote position/zoom).
## - Anything else (held past the threshold, and/or dragged) -> resume
##   follow. _process() picks live-tracking back up next frame; if the
##   target moved during the pause, position.x will jump to catch up rather
##   than ease back — matches "return to follow state" as specified, easing
##   can be layered on later if the jump reads as jarring in practice.
func _exit_follow_pause() -> void:
	var held_msec: int = Time.get_ticks_msec() - _follow_pause_press_ticks
	var was_tap: bool = not _follow_pause_moved and held_msec < FOLLOW_PAUSE_TAP_THRESHOLD_MSEC
	_follow_paused = false
	if was_tap:
		exit_follow_mode()
		_enter_free_camera_mode()
	else:
		_follow_resuming = true
		_follow_resume_elapsed = 0.0
		_follow_resume_start_position = global_position

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