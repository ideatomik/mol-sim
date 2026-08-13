extends Node

# ==========================================
# camera_regent.gd
# Scripted camera-and-scene-state driver for recording promo/highlight
# footage — separate from trailer.gd, which stays scoped to live in-app
# demonstration sequences (following enzymes through a real synthesis
# pass). This is meant to grow into a general recording tool over time,
# not a one-shot hack — but for now it drives exactly ONE shot: a close-up
# on the intra-residue directional capsule + arrow at the self-paired
# template state's middle residue.
#
# PLACEMENT: same convention as trailer.gd — add as a child node anywhere
# inside simulation.tscn's tree (e.g. directly under "root", as a sibling
# of ZoomManager). Resolves %ZoomManager the same unique-name way
# trailer.gd/replication_manager.gd/zoom_manager.gd itself do, and the
# simulation root via `simulation_path` (defaults to "..", same default
# trailer.gd uses). MoleculeStructureRenderer has no scene-unique name
# (confirmed — only ZoomManager/ThemeManager/LocaleManager/
# ComplexityManager carry unique_name_in_owner in simulation.tscn), so it's
# reached via a relative path off the resolved simulation root instead,
# matching simulation.gd's own "UI/PlayerUI" relative-lookup convention.
#
# EXTENSION POINT for a second shot: this file currently hardcodes ONE
# trigger key -> ONE shot pair directly in _unhandled_input(). The natural
# generalization, once a second shot actually exists, is a
# Dictionary[Key, {start: Callable, end: Callable}] (trigger key -> shot
# start/end methods) checked in _unhandled_input() instead of the direct
# keycode compare below — deliberately NOT built now, since one entry
# doesn't justify the indirection; build it when shot #2 actually arrives.
# ==========================================

@export var shot_trigger_key: Key = KEY_F4
@export var simulation_path: NodePath = NodePath("..")
@export_group("Capsule Direction Shot")
## Absolute Camera2D zoom to land on — direct/explicit rather than derived
## from tm.molecular_label_zoom_enter_threshold (an earlier version
## computed it as threshold + margin; a live-tunable absolute number is
## simpler to dial in against whatever this scene's thresholds actually
## are right now than getting a margin formula exactly right). MUST exceed
## both tm.molecular_zoom_enter_threshold and tm.molecular_label_zoom_
## enter_threshold for the atom tier + capsule to actually render — if the
## shot still lands at bead-tier zoom, raise this. NOT YET TUNED.
@export var capsule_shot_target_zoom: float = 8.0
## How long the camera takes to move onto the target — this shot's OWN
## duration, not the shared tm.zoom_level_transition_duration every other
## zoom_manager.gd transition uses (every other transition is unaffected).
## NOT YET TUNED.
@export var capsule_shot_transition_seconds: float = 1.5
## Short corrective settle applied AFTER the main zoom-in, onto the EXACT
## atom-tier capsule midpoint — the main transition's own target is only the
## bead's approximate position (see _start_capsule_direction_shot()'s own
## comment on why), close enough to reach the atom tier but not precise
## enough to land centered at this zoom level. NOT YET TUNED.
@export var capsule_shot_correction_seconds: float = 0.2
## Renders as an Inspector dropdown (Godot enums always do). NOT YET TUNED.
@export var capsule_shot_transition_type: Tween.TransitionType = Tween.TRANS_CUBIC
## Renders as an Inspector dropdown. NOT YET TUNED.
@export var capsule_shot_ease_type: Tween.EaseType = Tween.EASE_OUT

const _CAPSULE_SHOT_STRAND: String = "template_top"

enum _ShotState { IDLE, ACTIVE }
var _state: _ShotState = _ShotState.IDLE

var _sim: Node = null
var _zoom_mgr: Node = null
var _capsule_overlay: CapsuleArrowOverlay = null
var _capsule_shot_slot: int = -1
var _prev_ui_visible: bool = true
var _prev_enzyme_labels_enabled: bool = true

func _ready() -> void:
	_sim = get_node_or_null(simulation_path)
	if _sim == null or not ("num_nucleotide_slots" in _sim):
		push_error("camera_regent.gd: simulation_path (%s) doesn't point at simulation.gd — check node placement." % simulation_path)
		return
	_zoom_mgr = get_node_or_null("%ZoomManager")
	if _zoom_mgr == null:
		push_error("camera_regent.gd: %ZoomManager not found in this scene.")

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	if event.keycode != shot_trigger_key:
		return
	match _state:
		_ShotState.IDLE:
			_start_capsule_direction_shot()
		_ShotState.ACTIVE:
			_end_capsule_direction_shot()

## Fresh every call (never cached — same scrub-safe convention
## get_residue_capsule_positions() itself follows), scanning
## simulation.gd's get_template_nucleotides(). Deliberately NOT
## MoleculeStructureRenderer's get_residue_capsule_positions(): that
## accessor only has data for residues the atom-tier renderer is CURRENTLY
## drawing, which requires the camera to already be zoomed in there —
## unusable both as a precondition (checked before any camera movement)
## and as this target's own is_visible_fn (checked every frame starting
## the instant the transition begins, long before it settles). Bead-tier
## positions exist regardless of current zoom, which is what makes them
## usable to DRIVE the zoom-in in the first place; a bead entry existing
## at all IS the self-paired-template-state check (get_template_nucleotides()
## only includes a slot while its bead is still valid/unsuperseded by
## synthesis — see simulation.gd's own `base != null and is_instance_valid`
## guard there).
func _find_template_world_position(strand: String, slot: int) -> Variant:
	if _sim == null:
		return null
	for entry in _sim.get_template_nucleotides():
		if entry.strand == strand and entry.slot == slot:
			return entry.world_position
	return null

## Setup per the shot spec: hide player UI + enzyme labels (reusing
## simulation.gd's own setters, not reimplementing the toggle logic),
## verify an odd-length sequence and a real middle residue, then drive the
## camera toward that residue's bead-tier position via zoom_manager.gd's
## enter_scripted_free_camera() — REAL free-camera mode, not the level/
## target system (molecule_structure_renderer.gd's atom-tier rendering is
## gated on free_camera_mode() specifically and NEVER activates under the
## level/target system, confirmed live — an earlier version of this shot
## used register_target()/select_target() and could reach any zoom value
## without ever triggering the atom tier). Once settled, read the
## NOW-available precise atom-tier capsule position to spawn the arrow
## overlay on it.
func _start_capsule_direction_shot() -> void:
	if _sim == null or _zoom_mgr == null:
		push_error("camera_regent.gd: cannot start shot — simulation/ZoomManager not resolved (see _ready() errors).")
		return
	var renderer: Node = _sim.get_node_or_null("MoleculeStructureRenderer")
	if renderer == null:
		push_error("camera_regent.gd: MoleculeStructureRenderer not found under the simulation root — cannot start capsule-direction shot.")
		return

	var sequence_length: int = _sim.num_nucleotide_slots
	if sequence_length <= 0 or sequence_length % 2 == 0:
		push_error("camera_regent.gd: capsule-direction shot requires an ODD-length loaded sequence (a well-defined single middle residue) — got length=%d. Load an odd-length sequence before pressing %s." % [sequence_length, OS.get_keycode_string(shot_trigger_key)])
		return
	var middle_slot: int = (sequence_length - 1) / 2

	var bead_position = _find_template_world_position(_CAPSULE_SHOT_STRAND, middle_slot)
	if bead_position == null:
		push_error("camera_regent.gd: %s:%d isn't in the self-paired template state right now (no bead-tier residue found at that slot — the replication fork may already have passed it, or replication is already underway). This shot requires the self-paired template state (both template strands, no fork/enzymes active) — confirm that before pressing %s." % [_CAPSULE_SHOT_STRAND, middle_slot, OS.get_keycode_string(shot_trigger_key)])
		return

	_capsule_shot_slot = middle_slot
	_prev_ui_visible = _sim.set_player_ui_visible(false)
	_prev_enzyme_labels_enabled = _sim.set_enzyme_labels_enabled(false)

	# Y is simulation.gd's own center_y (its documented "vertical
	# screen-center anchor; all strand/enzyme y positions derive from
	# this" — the same convention zoom_manager.gd's own
	# _compute_cross_axis_fit() uses for vertical framing elsewhere), NOT
	# the bead's own raw world Y — template_top's bead sits above that
	# centerline by the strand's own vertical spacing, so centering on the
	# bead's exact Y left the capsule (which renders nearer the
	# centerline, between both template strands) vertically off-center.
	var camera_target: Vector2 = bead_position
	if "center_y" in _sim:
		camera_target.y = _sim.center_y
	_zoom_mgr.enter_scripted_free_camera(capsule_shot_target_zoom, camera_target, capsule_shot_transition_seconds, capsule_shot_transition_type, capsule_shot_ease_type)
	_state = _ShotState.ACTIVE

	# "Once the camera has reached and settled" — same reasoning as before:
	# we own the exact duration driving the tween, so awaiting that value is
	# exact, not a guess.
	await get_tree().create_timer(capsule_shot_transition_seconds).timeout
	# The shot may have been cancelled (trigger key pressed again) DURING
	# the await above — don't spawn the overlay for a shot already torn
	# down (_end_capsule_direction_shot() already reset the camera and
	# restored visibility; spawning now would leak an overlay node nothing
	# will ever queue_free()).
	if _state != _ShotState.ACTIVE:
		return

	# NOW get_residue_capsule_positions() is meaningful — the camera has
	# actually arrived, in REAL free-camera mode, at the atom tier.
	var positions: Dictionary = renderer.get_residue_capsule_positions(_CAPSULE_SHOT_STRAND, _capsule_shot_slot)
	if positions.is_empty():
		push_error("camera_regent.gd: %s:%d still isn't available at the atom tier after the camera settled — aborting overlay spawn. Raise capsule_shot_target_zoom until it clears both tm.molecular_zoom_enter_threshold and tm.molecular_label_zoom_enter_threshold." % [_CAPSULE_SHOT_STRAND, _capsule_shot_slot])
		return

	# The bead-tier position that drove the initial zoom-in was only ever
	# an APPROXIMATION of the capsule's real center — the bead anchor and
	# the actual C5'/C3' midpoint don't coincide, and at this zoom level
	# the gap reads as visibly off-center (both the earlier center_y
	# attempt and the raw bead position missed it for the same underlying
	# reason). Now that the real atom-tier position is known, do a short
	# corrective settle onto the EXACT midpoint. enter_scripted_free_
	# camera() is reused rather than a new snap primitive — already in
	# free-camera mode by this point, so its seed-from-current-state guard
	# is a no-op, making this just a short, small tween from wherever the
	# first tween landed to the precise target.
	var precise_target: Vector2 = (positions.c5 + positions.c3) / 2.0
	_zoom_mgr.enter_scripted_free_camera(capsule_shot_target_zoom, precise_target, capsule_shot_correction_seconds, capsule_shot_transition_type, capsule_shot_ease_type)
	await get_tree().create_timer(capsule_shot_correction_seconds).timeout
	if _state != _ShotState.ACTIVE:
		return

	_capsule_overlay = CapsuleArrowOverlay.new()
	_capsule_overlay.tm = _zoom_mgr.tm
	_capsule_overlay.c5_position = positions.c5
	_capsule_overlay.c3_position = positions.c3
	add_child(_capsule_overlay)
	# The overlay now runs its own loop (lerp/fade/repeat) unattended — no
	# further per-frame driving needed from here.

## Teardown per the shot spec: free the overlay, exit free-camera mode
## back to the normal level-1 whole-strand view (reset_zoom() — the same
## public exit every other free-camera session uses, e.g. ResetZoomButton
## or a double-click on empty background), then restore whatever player-UI/
## enzyme-label visibility was actually in effect before this shot started
## (not necessarily "visible" — F2/F3 may already have been toggled a
## specific way beforehand).
func _end_capsule_direction_shot() -> void:
	_state = _ShotState.IDLE
	if _capsule_overlay != null:
		_capsule_overlay.queue_free()
		_capsule_overlay = null
	if _zoom_mgr != null:
		_zoom_mgr.reset_zoom()
	if _sim != null:
		_sim.set_player_ui_visible(_prev_ui_visible)
		_sim.set_enzyme_labels_enabled(_prev_enzyme_labels_enabled)
