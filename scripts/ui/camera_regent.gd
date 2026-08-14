extends Node

# ==========================================
# camera_regent.gd
# Scripted camera-and-scene-state driver for recording promo/highlight
# footage — separate from trailer.gd, which stays scoped to live in-app
# demonstration sequences (following enzymes through a real synthesis
# pass). Drives multiple independent, trigger-key-activated shots.
#
# PLACEMENT: same convention as trailer.gd — add as a child node anywhere
# inside simulation.tscn's tree (e.g. directly under "root", as a sibling
# of ZoomManager). Resolves %ZoomManager the same unique-name way
# trailer.gd/replication_manager.gd/zoom_manager.gd itself do, and the
# simulation root via `simulation_path` (defaults to "..", same default
# trailer.gd uses). MoleculeStructureRenderer/PlayerUI have no scene-unique
# name (confirmed — only ZoomManager/ThemeManager/LocaleManager/
# ComplexityManager/DnaUnwindIntro carry unique_name_in_owner in
# simulation.tscn), so they're reached via a relative path off the resolved
# simulation root instead, matching simulation.gd's own "UI/PlayerUI"
# relative-lookup convention.
#
# MULTI-SHOT DISPATCH: each shot is a {state, start, end} entry in _shots,
# keyed by its own trigger Key — this is the generalization the file's own
# comment originally deferred "until shot #2 actually arrives" (it has).
# Dictionaries are reference types in GDScript, so a shot's own dict entry
# — passed into its start/end Callables — stays a live handle: mutating
# `shot.state` from _unhandled_input() is visible inside a shot's own
# `await`-suspended coroutine, which is how each shot detects being
# cancelled mid-flight without a separate per-shot bookkeeping var.
#
# ADDING SHOT #3: register a new entry in _shots (a new trigger key +
# start/end Callable pair) and export whatever tunables it needs — no
# changes to the dispatch mechanism itself.
# ==========================================

@export var simulation_path: NodePath = NodePath("..")

@export_group("Capsule Direction Shot")
@export var capsule_shot_trigger_key: Key = KEY_F4
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
## Renders as an Inspector dropdown (Godot enums always do). NOT YET TUNED.
@export var capsule_shot_transition_type: Tween.TransitionType = Tween.TRANS_CUBIC
## Renders as an Inspector dropdown. NOT YET TUNED.
@export var capsule_shot_ease_type: Tween.EaseType = Tween.EASE_OUT

@export_group("Recording Shot")
## Single trigger for the whole merged take: intro -> play -> helicase
## framing -> pause -> A-T pair -> C-G pair -> resume -> leading
## polymerase hold. Was two separately-triggered shots (F5 establishing +
## F7 helicase highlight); merged into one continuous take, so there's
## only one trigger now.
@export var recording_shot_trigger_key: Key = KEY_F5
## How long normal playback holds (helicase + polymerases visibly copying
## in one direction) before cutting to the helicase close-up. Renamed from
## shot1_hold_seconds — simulation.tscn's CameraRegent override was
## updated to match (kept at its tuned 2.0, not reverted to this default).
@export var shot_intro_hold_seconds: float = 3.0
## Manual two-press cue, not a timer: once the camera settles on helicase
## level 2, playback halves to 0.5x (giving room for the narration to
## identify the helicase before its label appears) and holds there until
## this key's FIRST press — which reveals the helicase label and restores
## 1x speed. The shot then waits again, this time for a SECOND press,
## before moving on into the base-pair highlight beat (pause + A-T
## capsule) — the operator controls exactly when the scene advances, not
## a guessed duration. Replaces the old fixed shot2_pre_highlight_seconds
## wait (was NOT YET TUNED). Not a toggle/shot-state entry like the
## trigger keys above — a plain one-shot flag, only meaningful while the
## Recording Shot's own wait loops are polling for it.
@export var helicase_label_reveal_key: Key = KEY_F10
## Hold time for the C-G pair capsule beat, same narration-timing basis.
## NOT YET TUNED.
@export var shot2_cg_pair_seconds: float = 5.3
## Crossfade duration between the A-T and C-G capsules.
@export var shot2_capsule_crossfade_seconds: float = 0.35

@export_group("Lagging Hold Shot")
## Standalone shot ("fita atrasada, fragmentos") — fresh sequence, straight
## into play, camera settles on the lagging polymerase and just holds
## there through the whole duplication run. No intro, no highlight
## overlay, no complexity-tier changes. Deliberately recorded longer than
## the final edit needs — trimmed afterward, not timed by this script.
@export var lagging_hold_shot_trigger_key: Key = KEY_F7

@export_group("Primer Highlight Shot")
## Shot C (Rilare 17's line, RNA primer). Fresh sequence, Complex tier
## (primase+Pol I+ligase) flipped on at play start, reuses
## lagging_polymerase level 2 framing (same as the Lagging Hold Shot —
## no dedicated primer target exists, and this reads clearly enough
## without one), spawns a capsule around the current primer's span, holds
## for shot_c_hold_seconds. Enzyme labels stay ON throughout (Complex
## tier, all five enzymes accepted as labeled for this shot).
## F8 was tried first and rejected — it's Godot's own editor shortcut for
## "Stop Running Project", which intercepts the keypress and kills the
## debug session before the running game ever sees it (looked exactly
## like a crash: no script error, no stack trace, execution just trailing
## off mid-frame — confirmed via the editor's own toolbar tooltip, not a
## bug in this shot's code). F9 avoids the game's own F1-F7 bindings and
## isn't a global Godot editor shortcut for the running-game window.
@export var primer_shot_trigger_key: Key = KEY_F9
## Hold time — matches Rilare_17's real trimmed narration length.
@export var shot_c_hold_seconds: float = 18.7

const _CAPSULE_SHOT_STRAND: String = "template_top"

enum _ShotState { IDLE, ACTIVE }

# trigger Key -> {state: _ShotState, start: Callable, end: Callable}
var _shots: Dictionary = {}

var _sim: Node = null
var _zoom_mgr: Node = null
var _capsule_overlay: CapsuleArrowOverlay = null
var _capsule_shot_slot: int = -1
var _capsule_prev_ui_visible: bool = true
var _capsule_prev_enzyme_labels_enabled: bool = true
var _highlight_overlay: PairCapsuleOverlay = null
var _recording_prev_ui_visible: bool = true
var _recording_prev_enzyme_labels_enabled: bool = true
var _helicase_label_reveal_requested: bool = false
var _lagging_prev_ui_visible: bool = true
var _primer_overlays: Array[PrimerCapsuleOverlay] = []
var _primer_highlighted_tile_ends: Dictionary = {}  # Set-style: tile_end -> true, for dedupe against get_current_primer_capsule_positions()'s tile_end
var _primer_prev_ui_visible: bool = true
var _primer_prev_enzyme_labels_enabled: bool = true

func _ready() -> void:
	_sim = get_node_or_null(simulation_path)
	if _sim == null or not ("num_nucleotide_slots" in _sim):
		push_error("camera_regent.gd: simulation_path (%s) doesn't point at simulation.gd — check node placement." % simulation_path)
		return
	_zoom_mgr = get_node_or_null("%ZoomManager")
	if _zoom_mgr == null:
		push_error("camera_regent.gd: %ZoomManager not found in this scene.")

	_shots = {
		capsule_shot_trigger_key: {state = _ShotState.IDLE, start = _start_capsule_direction_shot, end = _end_capsule_direction_shot},
		recording_shot_trigger_key: {state = _ShotState.IDLE, start = _start_recording_shot, end = _end_recording_shot},
		lagging_hold_shot_trigger_key: {state = _ShotState.IDLE, start = _start_lagging_hold_shot, end = _end_lagging_hold_shot},
		primer_shot_trigger_key: {state = _ShotState.IDLE, start = _start_primer_shot, end = _end_primer_shot},
	}

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	if event.keycode == helicase_label_reveal_key:
		# Plain one-shot cue, not a _shots toggle entry — only meaningful
		# while the Recording Shot's own wait loop is polling for it; a
		# press at any other time just sets a flag nothing is watching.
		_helicase_label_reveal_requested = true
		return
	var shot: Dictionary = _shots.get(event.keycode, {})
	if shot.is_empty():
		return
	if shot.state == _ShotState.IDLE:
		shot.state = _ShotState.ACTIVE
		shot.start.call(shot)
	else:
		shot.state = _ShotState.IDLE
		shot.end.call(shot)

# ==========================================
# CAPSULE DIRECTION SHOT
# ==========================================

## Setup per the shot spec: hide player UI + enzyme labels (reusing
## simulation.gd's own setters, not reimplementing the toggle logic),
## verify an odd-length sequence, solve the middle residue's exact capsule
## midpoint up front (get_residue_capsule_positions_when_centered(), which
## works before the camera has moved), then run ONE tween onto it via
## zoom_manager.gd's enter_scripted_free_camera() — REAL free-camera mode,
## not the level/target system (molecule_structure_renderer.gd's atom-tier
## rendering is gated on free_camera_mode() specifically and NEVER
## activates under the level/target system, confirmed live — an earlier
## version of this shot used register_target()/select_target() and could
## reach any zoom value without ever triggering the atom tier). Once
## settled, spawn the arrow overlay on the live rendered capsule.
func _start_capsule_direction_shot(shot: Dictionary) -> void:
	if _sim == null or _zoom_mgr == null:
		push_error("camera_regent.gd: cannot start shot — simulation/ZoomManager not resolved (see _ready() errors).")
		return
	var renderer: Node = _sim.get_node_or_null("MoleculeStructureRenderer")
	if renderer == null:
		push_error("camera_regent.gd: MoleculeStructureRenderer not found under the simulation root — cannot start capsule-direction shot.")
		return

	var sequence_length: int = _sim.num_nucleotide_slots
	if sequence_length <= 0 or sequence_length % 2 == 0:
		push_error("camera_regent.gd: capsule-direction shot requires an ODD-length loaded sequence (a well-defined single middle residue) — got length=%d. Load an odd-length sequence before pressing %s." % [sequence_length, OS.get_keycode_string(capsule_shot_trigger_key)])
		return
	var middle_slot: int = (sequence_length - 1) / 2

	# The EXACT capsule midpoint, solved before the camera moves — see
	# get_residue_capsule_positions_when_centered()'s own comment. This is
	# what lets the whole shot be a single tween: earlier versions aimed at
	# the bead position (plus a center_y guess for the vertical), which is a
	# different point from the capsule's real centre, and had to paper over
	# the gap with a second corrective tween once the camera had arrived and
	# the rendered position finally existed.
	var predicted: Dictionary = renderer.get_residue_capsule_positions_when_centered(_CAPSULE_SHOT_STRAND, middle_slot)
	if predicted.is_empty():
		push_error("camera_regent.gd: %s:%d isn't in the self-paired template state right now (no residue found at that slot — the replication fork may already have passed it, or replication is already underway). This shot requires the self-paired template state (both template strands, no fork/enzymes active) — confirm that before pressing %s." % [_CAPSULE_SHOT_STRAND, middle_slot, OS.get_keycode_string(capsule_shot_trigger_key)])
		return
	var camera_target: Vector2 = (predicted.c5 + predicted.c3) / 2.0

	_capsule_shot_slot = middle_slot
	_capsule_prev_ui_visible = _sim.set_player_ui_visible(false)
	_capsule_prev_enzyme_labels_enabled = _sim.set_enzyme_labels_enabled(false)

	_zoom_mgr.enter_scripted_free_camera(capsule_shot_target_zoom, camera_target, capsule_shot_transition_seconds, capsule_shot_transition_type, capsule_shot_ease_type)

	# "Once the camera has reached and settled" — same reasoning as before:
	# we own the exact duration driving the tween, so awaiting that value is
	# exact, not a guess.
	await get_tree().create_timer(capsule_shot_transition_seconds).timeout
	# The shot may have been cancelled (trigger key pressed again) DURING
	# the await above — don't spawn the overlay for a shot already torn
	# down (_end_capsule_direction_shot() already reset the camera and
	# restored visibility; spawning now would leak an overlay node nothing
	# will ever queue_free()).
	if shot.state != _ShotState.ACTIVE:
		return

	# The overlay is positioned from the LIVE rendered capsule, not the
	# prediction that aimed the camera — same value if the fixed-point solve
	# is right, but this is the ground truth of what's actually on screen,
	# so the arrow can't drift from the shape it's annotating.
	var positions: Dictionary = renderer.get_residue_capsule_positions(_CAPSULE_SHOT_STRAND, _capsule_shot_slot)
	if positions.is_empty():
		push_error("camera_regent.gd: %s:%d still isn't available at the atom tier after the camera settled — aborting overlay spawn. Raise capsule_shot_target_zoom until it clears both tm.molecular_zoom_enter_threshold and tm.molecular_label_zoom_enter_threshold." % [_CAPSULE_SHOT_STRAND, _capsule_shot_slot])
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
func _end_capsule_direction_shot(_shot: Dictionary) -> void:
	if _capsule_overlay != null:
		_capsule_overlay.queue_free()
		_capsule_overlay = null
	if _zoom_mgr != null:
		_zoom_mgr.reset_zoom()
	if _sim != null:
		_sim.set_player_ui_visible(_capsule_prev_ui_visible)
		_sim.set_enzyme_labels_enabled(_capsule_prev_enzyme_labels_enabled)

# ==========================================
# RECORDING SHOT (intro -> play -> helicase+polymerases frame -> pause ->
# A-T pair -> C-G pair -> resume -> leading polymerase hold)
#
# Formerly two independently-triggered shots (establishing shot on F5,
# helicase highlight shot on F7) — merged into one continuous take on a
# single trigger, since they were always meant to be recorded as one
# unbroken clip, not edited together afterward. Merging also removes the
# need for the standalone highlight shot's old precondition check
# ("replication must already be running before pressing this key"): this
# take fully owns every toggle_play() call in one linear sequence —
# unpaused (intro -> play) -> paused (highlight beats) -> unpaused
# (resume) — so each call's starting-state assumption is guaranteed by
# the step directly before it in the same coroutine, not by whatever
# state the operator happened to leave the sim in beforehand.
# ==========================================

## Setup: hide player UI + enzyme labels (same reused setters as the
## capsule shot), play the DNA unwind intro NON-DISMISSIBLY on the
## already-running simulation (player_ui.gd's trigger_dna_intro(false) —
## confirmed by reading _play_dna_intro() that it gathers every value
## fresh from current simulation state each call, so no fresh sequence
## load is needed or wanted here — the operator loads a fresh sequence via
## the popup before pressing this shot's trigger, same precondition as
## before), wait for its natural finish via intro_finished (not a guessed
## delay), start normal playback (toggle_play() — safe unconditional here:
## the intro only ever runs from the paused post-load state, so this is
## the shot's own first flip, guaranteed to be a "start"), hold for
## shot_intro_hold_seconds, cut to the "helicase" target (level-2 frame
## already confirmed to keep both polymerases in view, no framing changes
## needed), wait out its transition duration (tm.zoom_level_transition_
## duration — the same value select_target() itself falls back to when
## called without an explicit duration), pause (toggle_play() again — also
## safe unconditional, since we just started play above and nothing else
## in this take can have re-paused it; wobble keeps animating through the
## pause per simulation.gd's STATE UPDATE/VISUAL RENDERING split), then run
## the two-beat pair-capsule highlight via find_nearest_matching_pair()
## (simulation.gd) — never a hardcoded/assumed slot. Resumes play (third
## toggle_play(), mirroring the pause) and cuts to leading_polymerase
## (already registered, simulation.gd:248) once both beats have held.
func _start_recording_shot(shot: Dictionary) -> void:
	if _sim == null or _zoom_mgr == null:
		push_error("camera_regent.gd: cannot start shot — simulation/ZoomManager not resolved (see _ready() errors).")
		return
	var player_ui: Node = _sim.get_node_or_null("UI/PlayerUI")
	if player_ui == null:
		push_error("camera_regent.gd: UI/PlayerUI not found under the simulation root — cannot start recording shot.")
		return

	_recording_prev_ui_visible = _sim.set_player_ui_visible(false)
	_recording_prev_enzyme_labels_enabled = _sim.set_enzyme_labels_enabled(false)

	if not player_ui.trigger_dna_intro(false):  # false = non-dismissible
		push_error("camera_regent.gd: DNA intro didn't start (trigger_dna_intro() returned false) — is a sequence currently loaded?")
		_sim.set_player_ui_visible(_recording_prev_ui_visible)
		_sim.set_enzyme_labels_enabled(_recording_prev_enzyme_labels_enabled)
		return

	var dna_intro: Node = get_node_or_null("%DnaUnwindIntro")
	await dna_intro.intro_finished
	# intro_finished fires at the START of the crossfade fade-out, not its
	# end (confirmed in dna_unwind_intro.gd's _finish()) — matching
	# player_ui.gd's OWN existing normal-flow callback
	# (_on_sequence_loaded_intro_done()), which proceeds at this exact same
	# point rather than waiting out crossfade_duration_seconds too.
	if shot.state != _ShotState.ACTIVE:
		return

	_sim.toggle_play()  # start play

	await get_tree().create_timer(shot_intro_hold_seconds).timeout
	if shot.state != _ShotState.ACTIVE:
		return

	_zoom_mgr.select_target("helicase")
	await get_tree().create_timer(_zoom_mgr.tm.zoom_level_transition_duration).timeout
	if shot.state != _ShotState.ACTIVE:
		return

	# Manual cue, replacing the old fixed shot2_pre_highlight_seconds wait:
	# playback halves to 0.5x right as the camera settles here — giving
	# room for the narration to identify the helicase before its label
	# appears — and holds at that speed until helicase_label_reveal_key
	# (F10) is pressed. On press: reveal the label (independent of the
	# shared tm.enzyme_labels_enabled flag — helicase_ring.gd is
	# deliberately ThemeManager-agnostic, see set_label_enabled()'s own
	# comment, so this doesn't reveal polymerase/ligase/pol1/primase_blip
	# labels early) and restore 1x speed. If the shot is cancelled while
	# still waiting, speed is restored here too — it must never be left
	# stuck at 0.5x past this beat.
	_helicase_label_reveal_requested = false
	if _sim.helicase_mgr != null:
		_sim.helicase_mgr.set_speed(0.5)
	while not _helicase_label_reveal_requested:
		await get_tree().process_frame
		if shot.state != _ShotState.ACTIVE:
			if _sim.helicase_mgr != null:
				_sim.helicase_mgr.set_speed(1.0)
			return
	_helicase_label_reveal_requested = false
	if _sim.helicase_ring != null:
		_sim.helicase_ring.set_label_enabled(true)
	if _sim.helicase_mgr != null:
		_sim.helicase_mgr.set_speed(1.0)

	# Second F10 press: cue to move on into the base-pair highlight beat
	# (pause + A-T capsule). First press only revealed the label/restored
	# speed above — this shot now waits for an explicit second cue rather
	# than proceeding automatically, so the operator controls exactly when
	# the scene advances.
	while not _helicase_label_reveal_requested:
		await get_tree().process_frame
		if shot.state != _ShotState.ACTIVE:
			return
	_helicase_label_reveal_requested = false

	_sim.toggle_play()  # pause — wobble keeps running (see header comment)

	var at_pair: Dictionary = _sim.find_nearest_matching_pair("AT")
	if at_pair.is_empty():
		push_error("camera_regent.gd: no pre-fork A-T pair found ahead of the helicase — aborting base-pair highlight beat.")
		_sim.toggle_play()  # resume — don't leave playback paused on a failed beat
		_sim.set_player_ui_visible(_recording_prev_ui_visible)
		_sim.set_enzyme_labels_enabled(_recording_prev_enzyme_labels_enabled)
		return

	_highlight_overlay = PairCapsuleOverlay.new()
	_highlight_overlay.tm = _zoom_mgr.tm
	_highlight_overlay.bead_a_position = at_pair.template_top_position
	_highlight_overlay.bead_b_position = at_pair.template_bottom_position
	add_child(_highlight_overlay)

	# Third F10 press: cue to move on from the A-T capsule into the C-G
	# crossfade. Same manual-cue pattern as the first two presses —
	# replaces the old fixed shot2_at_pair_seconds wait.
	while not _helicase_label_reveal_requested:
		await get_tree().process_frame
		if shot.state != _ShotState.ACTIVE:
			return
	_helicase_label_reveal_requested = false

	var cg_pair: Dictionary = _sim.find_nearest_matching_pair("CG")
	if cg_pair.is_empty():
		push_error("camera_regent.gd: no pre-fork C-G pair found ahead of the helicase — ending recording shot after the A-T beat.")
		_highlight_overlay.queue_free()
		_highlight_overlay = null
		_sim.toggle_play()  # resume
		_sim.set_player_ui_visible(_recording_prev_ui_visible)
		_sim.set_enzyme_labels_enabled(_recording_prev_enzyme_labels_enabled)
		return

	# Crossfade: fade the A-T capsule out while a second overlay (the C-G
	# pair) fades in, then drop the first — two overlays cross-tweened via
	# their own built-in Node2D.modulate (no changes needed to
	# pair_capsule_overlay.gd itself; modulate already applies to its
	# _draw()'s draw_polyline() output).
	var old_overlay: PairCapsuleOverlay = _highlight_overlay
	var new_overlay := PairCapsuleOverlay.new()
	new_overlay.tm = _zoom_mgr.tm
	new_overlay.bead_a_position = cg_pair.template_top_position
	new_overlay.bead_b_position = cg_pair.template_bottom_position
	new_overlay.modulate.a = 0.0
	add_child(new_overlay)
	_highlight_overlay = new_overlay

	var crossfade_tween := create_tween().set_parallel(true)
	crossfade_tween.tween_property(old_overlay, "modulate:a", 0.0, shot2_capsule_crossfade_seconds)
	crossfade_tween.tween_property(new_overlay, "modulate:a", 1.0, shot2_capsule_crossfade_seconds)
	await crossfade_tween.finished
	old_overlay.queue_free()
	if shot.state != _ShotState.ACTIVE:
		return

	await get_tree().create_timer(shot2_cg_pair_seconds).timeout
	if shot.state != _ShotState.ACTIVE:
		return

	if _highlight_overlay != null:
		_highlight_overlay.queue_free()
		_highlight_overlay = null

	_sim.toggle_play()  # resume
	# Shared flag, deliberately — confirmed safe for this shot specifically:
	# base complexity tier only, so ligase/pol1/primase_blip aren't present
	# on screen and this only visibly affects the two polymerase labels
	# here. Uses set_enzyme_labels_enabled() (not a direct tm write) so
	# leading_clamp/lagging_clamp's refresh_label_visibility() fires
	# immediately, rather than waiting for their next pulse/pump tween.
	_sim.set_enzyme_labels_enabled(true)
	_zoom_mgr.select_target("leading_polymerase")

## Teardown: force-finish the intro if it's still playing (non-dismissible,
## so nothing else can end it), free any spawned overlay, resume playback
## if this shot left it paused (only if still paused — pressing the
## trigger key again after the shot already resumed on its own must not
## re-pause it), restore UI/label visibility, and return to the level-1
## whole-strand view (reset_zoom() — same exit every other shot uses).
func _end_recording_shot(_shot: Dictionary) -> void:
	var dna_intro: Node = get_node_or_null("%DnaUnwindIntro")
	if dna_intro != null and dna_intro.has_method("skip"):
		dna_intro.skip()
	if _highlight_overlay != null:
		_highlight_overlay.queue_free()
		_highlight_overlay = null
	if _sim != null and _sim.manual_override:
		_sim.toggle_play()
	if _sim != null:
		_sim.set_player_ui_visible(_recording_prev_ui_visible)
		_sim.set_enzyme_labels_enabled(_recording_prev_enzyme_labels_enabled)
	if _zoom_mgr != null:
		_zoom_mgr.reset_zoom()

# ==========================================
# LAGGING HOLD SHOT ("fita atrasada, fragmentos" — lagging polymerase's
# stop-start fragment behavior). Standalone, not merged with any other
# cue — a photo interlude separates it from the next Zymulador cue in the
# script, so this has to stand alone as its own take.
# ==========================================

## Setup: hide player UI + enzyme labels (same reused setters as the other
## shots), start play directly (toggle_play(), not through the hidden UI —
## no intro here, this isn't the start of a video segment), wait for
## lagging_polymerase to actually START MOVING toward its first target,
## then cut to it at its registered entry level (already registered,
## simulation.gd:249).
##
## Two separate, unsynchronized things gate lagging_polymerase's fade-in
## and position, and only the SECOND one is what this shot needs to wait
## for:
##  1. An early, purely cosmetic proximity pre-fade in the per-frame render
##     loop (replication_manager.gd:424-429) tweens modulate.a toward 1.0
##     once the helicase is within 3 slot-spacings of the first fragment —
##     but lagging_polymerase_x is still 0.0 at that point (reset in
##     initialize(), replication_manager.gd:1425) because nothing has fired
##     yet, and the per-frame render loop unconditionally writes
##     lagging_polymerase.position from that stale 0.0 every frame
##     (replication_manager.gd:489) — even though a much earlier run_intro()
##     tween already tried to slide it into the visible strand, this
##     later per-frame write stomps that and parks it at world x=0, well
##     outside the strand. Waiting on is_target_visible() alone (an
##     earlier version of this shot did) cuts the camera onto that
##     off-strand position.
##  2. The REAL start-of-motion, replication_manager.gd:1484-1507's
##     _on_helicase_slot_reached(): once index >= okazaki_fragment_size +
##     pll_slot_count, lagging_firing_started flips true, modulate.a is
##     force-set to 1.0 directly (no tween), and _lagging_fire_step() runs
##     in the SAME call, finally setting lagging_polymerase_x to a real
##     slot position. This is the moment the polymerase is both visible
##     AND positioned correctly — reused here via
##     replication_mgr.lagging_firing_started rather than reimplementing
##     the index math, since that's the exact flag this logic already
##     flips at the moment we need.
## No highlight overlay, no complexity-tier calls (base tier only for this
## shot). Once framed, nothing else to await — the shot just holds there
## through the whole duplication run at whatever pace playback is already
## running, and stays ACTIVE until the trigger key is pressed again
## (there's no fixed hold duration to time against; this is deliberately
## recorded longer than the final edit needs and trimmed afterward, not in
## this script).
func _start_lagging_hold_shot(shot: Dictionary) -> void:
	if _sim == null or _zoom_mgr == null:
		push_error("camera_regent.gd: cannot start shot — simulation/ZoomManager not resolved (see _ready() errors).")
		return
	if _sim.replication_mgr == null:
		push_error("camera_regent.gd: simulation.replication_mgr not resolved — cannot start lagging hold shot.")
		return

	_lagging_prev_ui_visible = _sim.set_player_ui_visible(false)
	# Enzyme labels stay on for this shot, unlike the other shots —
	# deliberately not calling set_enzyme_labels_enabled(false) here.

	_sim.toggle_play()  # start play directly

	while not _sim.replication_mgr.lagging_firing_started:
		await get_tree().process_frame
		if shot.state != _ShotState.ACTIVE:
			return

	_zoom_mgr.select_target("lagging_polymerase")

## Teardown: restore UI/label visibility and return to the level-1
## whole-strand view (reset_zoom() — same exit every other shot uses).
## Deliberately does NOT touch play state — this shot never pauses
## anything, so there's nothing to resume, and forcing a pause here would
## be new, unrequested behavior; playback is left exactly as it was
## (running, or already finished on its own) when the shot ends.
func _end_lagging_hold_shot(_shot: Dictionary) -> void:
	if _sim != null:
		_sim.set_player_ui_visible(_lagging_prev_ui_visible)
	if _zoom_mgr != null:
		_zoom_mgr.reset_zoom()

# ==========================================
# PRIMER HIGHLIGHT SHOT (shot C — Rilare 17's line, RNA primer). Complex
# tier (primase+Pol I+ligase) on at play start, reuses the Lagging Hold
# Shot's framing (no dedicated primer target exists — flagged, not built,
# given time pressure), capsule around the current primer's span, hold,
# teardown. Labels stay ON throughout — not hidden like other shots.
# ==========================================

## Setup: hide player UI, force enzyme labels ON (Complex tier means all
## five enzymes are accepted as labeled for this shot). Flip Complex tier
## on FIRST, before play starts — set_pol1_enabled() cascades
## primase+ligase (complexity_manager.gd), and per the known constraint a
## fragment already closed before the toggle doesn't retroactively apply,
## so this has to happen before the helicase reaches the region being
## filmed. Reuses lagging_polymerase's level 2 framing — same
## lagging_firing_started gate as the Lagging Hold Shot (that shot's own
## header comment explains why: the polymerase isn't at a legible position
## until it actually fires its first slot). Once framed, polls
## replication_mgr.get_current_primer_capsule_positions() (thin wrapper
## reusing primase/Pol I's own existing tiling math and the already-spawned
## lagging_synthesized_bases array — no new geometry) every frame for the
## rest of the hold, spawning a NEW capsule each time a not-yet-seen
## tile_end appears — every primer built during the shot gets its own
## capsule, not just the first. Earlier capsules stay on screen (freed
## only at full teardown), matching how the placed primer bases themselves
## persist visually. Holds for shot_c_hold_seconds, then returns (stays
## ACTIVE — same "no self-teardown on natural completion" behavior every
## other multi-beat shot already has; full teardown happens on next
## trigger press).
func _start_primer_shot(shot: Dictionary) -> void:
	if _sim == null or _zoom_mgr == null:
		push_error("camera_regent.gd: cannot start shot — simulation/ZoomManager not resolved (see _ready() errors).")
		return
	if _sim.replication_mgr == null:
		push_error("camera_regent.gd: simulation.replication_mgr not resolved — cannot start primer highlight shot.")
		return
	var complexity_mgr: Node = get_node_or_null("%ComplexityManager")
	if complexity_mgr == null:
		push_error("camera_regent.gd: %ComplexityManager not found in this scene — cannot start primer highlight shot.")
		return

	_primer_prev_ui_visible = _sim.set_player_ui_visible(false)
	_primer_prev_enzyme_labels_enabled = _sim.set_enzyme_labels_enabled(true)

	complexity_mgr.set_pol1_enabled(true)  # cascades primase+ligase, before play starts
	_sim.toggle_play()  # start play directly — no intro

	while not _sim.replication_mgr.lagging_firing_started:
		await get_tree().process_frame
		if shot.state != _ShotState.ACTIVE:
			return

	_zoom_mgr.select_target("lagging_polymerase")

	# Every primer, not just the current one: poll every frame for the rest
	# of the hold, and whenever get_current_primer_capsule_positions()
	# reports a tile_end we haven't seen yet, spawn a NEW capsule for it —
	# never reused/repositioned. Earlier capsules are left in place
	# (queue_free()'d only at full teardown), matching how the placed
	# primer bases themselves persist visually until Pol I removes them
	# (see replication_manager.gd's OkazakiMaturationDesign.md banner:
	# "The PLACED BASES never fade — real persisted state").
	var hold_deadline: float = Time.get_ticks_msec() / 1000.0 + shot_c_hold_seconds
	while Time.get_ticks_msec() / 1000.0 < hold_deadline:
		var primer_positions: Dictionary = _sim.replication_mgr.get_current_primer_capsule_positions()
		if not primer_positions.is_empty() and not _primer_highlighted_tile_ends.has(primer_positions.tile_end):
			_primer_highlighted_tile_ends[primer_positions.tile_end] = true
			var overlay := PrimerCapsuleOverlay.new()
			overlay.tm = _zoom_mgr.tm
			overlay.start_position = primer_positions.start_position
			overlay.end_position = primer_positions.end_position
			add_child(overlay)
			_primer_overlays.append(overlay)
		await get_tree().process_frame
		if shot.state != _ShotState.ACTIVE:
			return

## Teardown: free every spawned overlay, restore UI/label visibility,
## return to the level-1 whole-strand view. Does NOT touch play state and
## does NOT revert the Complex-tier toggle (not requested —
## complexity_manager.gd's own toggles are meant to persist as an
## operator/scene setting, not something a shot silently undoes).
func _end_primer_shot(_shot: Dictionary) -> void:
	for overlay in _primer_overlays:
		if overlay != null:
			overlay.queue_free()
	_primer_overlays.clear()
	_primer_highlighted_tile_ends.clear()
	if _sim != null:
		_sim.set_player_ui_visible(_primer_prev_ui_visible)
		_sim.set_enzyme_labels_enabled(_primer_prev_enzyme_labels_enabled)
	if _zoom_mgr != null:
		_zoom_mgr.reset_zoom()
