extends CanvasLayer

# ==========================================
# PLAYER UI
# Transport controls for the DNA simulation.
# ==========================================

# OPTIONAL NODES (VerticalModeDesign.md step 7): the vertical layout omits
# SequenceLabel and the whole ZoomControls row — 1080px can't hold 21 controls
# in one line, and the video these vertical builds exist to record never shows
# the UI at all. Those eight use get_node_or_null() and every consumer guards
# them, so ONE script drives both layouts. Nothing is deleted: the dropdown's
# code stays whole for the planned voice-command interface, it simply has no
# widget in the vertical scene. ResetZoomButton is deliberately KEPT (moved
# into the transport row) — without it, and with no pinch gesture on mobile,
# zooming in would be a one-way trip.
@export var simulation: Node2D  # Drag the root Simulation node here

# UI Node References
@onready var sequence_label: RichTextLabel = get_node_or_null("%SequenceLabel")
@onready var scrubber: HSlider = %Scrubber
@onready var transport_buttons: HBoxContainer = %TransportButtons

# Transport Buttons
@onready var menu_button: Button = %Menu
@onready var fast_backward: Button = %FastBackward
@onready var backward: Button = %Backward
@onready var play_pause_button: Button = %PlayPauseButton
@onready var stop_button: Button = %StopButton
@onready var forward: Button = %Forward
@onready var fast_forward: Button = %FastForward
@onready var eject_button: Button = %Eject

# Speed Controls
@onready var speed_controls: HBoxContainer = %SpeedControls
@onready var speed_label: Label = %SpeedLabel
@onready var speed_decrease_button: Button = %SpeedDecreaseButton
@onready var speed_value_label: Label = %SpeedValueLabel
@onready var speed_increase_button: Button = %SpeedIncreaseButton
@onready var wobble_toggle: Button = %WobbleToggle

# Zoom Controls
@onready var zoom_controls: HBoxContainer = get_node_or_null("%ZoomControls")
@onready var highlight_button: Button = get_node_or_null("%HighlightButton")
@onready var zoom_out_button: Button = get_node_or_null("%ZoomOutButton")
@onready var enzyme_dropdown: OptionButton = get_node_or_null("%EnzymeDropdown")
@onready var zoom_in_button: Button = get_node_or_null("%ZoomInButton")
@onready var reset_zoom_button: Button = %ResetZoomButton
@onready var recenter_pan_button: Button = get_node_or_null("%RecenterPanButton")
@onready var ncloud_toggle: Button = get_node_or_null("%NCloudToggle")

var zoom_mgr: Camera2D = null  # %ZoomManager — self-resolved in _ready() for the
                                # horizontal layout; injected by simulation.gd's
                                # _swap_in_vertical_player_ui() for the vertical
                                # layout, whose runtime-instantiated scene can't
                                # reach a sibling's unique name across the
                                # ownership boundary.

var _is_dragging: bool = false

# LongSequenceDesign.md Part 4 — SequenceLabel click/drag-to-scrub state.
# _hover_index (-1 = none) is the absolute slot index currently under the
# mouse, threaded into get_sequence_rich_text() each rebuild so the rebuild
# function itself applies the hover highlight. _is_label_dragging is
# synthesized from raw mouse-button state (RichTextLabel has no built-in
# drag concept the way HSlider does) — while true, meta_hover_started's own
# span-transition firing doubles as "which letter is the cursor over during
# the drag," continuously scrubbing exactly like dragging the slider does.
var _hover_index: int = -1
var _is_label_dragging: bool = false

var _stop_icon_default: String = ""

# ==========================================
# SPEED CONTROLS
# Ladder maps 1:1 onto helicase_mgr.speed_multiplier via set_speed(). "0x" is
# NOT a ladder entry — helicase.gd derives step_duration = base_step_duration
# / speed_multiplier, so a real 0 would divide by zero. Instead 0x is a
# display-only state shown whenever the sim is paused or done; the selected
# ladder index is remembered underneath and reapplied the moment play
# resumes. helicase_mgr is destroyed and recreated on every sequence load
# (see simulation.gd's initialize_simulation()), always starting back at
# 1.0x, so the selected index must be explicitly reapplied after
# simulation_initialized fires — otherwise a speed choice would silently
# reset on every new sequence.
# ==========================================
const SPEED_VALUES: Array[float] = [1.0 / 16.0, 1.0 / 8.0, 1.0 / 4.0, 0.5, 1.0, 1.5, 2.0, 4.0, 8.0, 16.0]
const SPEED_DISPLAY: Array[String] = ["1/16x", "1/8x", "1/4x", "1/2x", "1x", "1.5x", "2x", "4x", "8x", "16x"]
const DEFAULT_SPEED_INDEX: int = 4  # 1.0x

var _speed_index: int = DEFAULT_SPEED_INDEX

func _is_simulation_done() -> bool:
	return simulation.helicase_mgr != null and simulation.helicase_mgr.get_phase() == simulation.helicase_mgr.Phase.DONE

# ==========================================
# LIFECYCLE
# ==========================================

func _ready():
	# Configure the scrubber
	scrubber.min_value = 0
	scrubber.step = 1.0
	scrubber.value_changed.connect(_on_scrubber_dragged)

	# LongSequenceDesign.md Part 4 — click/drag-to-scrub on SequenceLabel.
	# meta_hover_started/ended fire regardless of button state (hover
	# tracking is motion-based, not click-based), which is what lets the
	# same hover signal double as "which letter during an active drag."
	# gui_input is the only way to observe raw mouse-button state on a
	# RichTextLabel, since it has no built-in Range-style drag handling.
	if sequence_label != null:
		sequence_label.meta_clicked.connect(_on_sequence_label_meta_clicked)
		sequence_label.meta_hover_started.connect(_on_sequence_label_meta_hover_started)
		sequence_label.meta_hover_ended.connect(_on_sequence_label_meta_hover_ended)
		sequence_label.gui_input.connect(_on_sequence_label_gui_input)

	# Connect simulation signals
	if simulation:
		simulation.progress_changed.connect(_on_simulation_progress_changed)
		simulation.simulation_initialized.connect(_on_simulation_initialized)
		# LongSequenceDesign.md follow-up — helicase_ring.gd's and both
		# polymerase clamps' drag-to-scrub gestures all funnel through this
		# one signal (see simulation.gd's request_drag_scrub()).
		simulation.drag_scrub_requested.connect(_on_drag_scrub_requested)

		# Connect all transport buttons
		menu_button.pressed.connect(_on_menu_pressed)
		fast_backward.pressed.connect(_on_fast_backward)
		backward.pressed.connect(_on_backward)
		play_pause_button.pressed.connect(_on_play_pause)
		stop_button.pressed.connect(_on_stop_pressed)
		forward.pressed.connect(_on_forward)
		fast_forward.pressed.connect(_on_fast_forward)
		eject_button.pressed.connect(_on_eject_pressed)

		_stop_icon_default = stop_button.text

		# Connect speed controls.
		# SpeedLabel's text is set to the raw translation key exactly once, at
		# spawn time — never touched again — same auto-translate mechanism
		# EnzymeLabelsDesign.md documents for RichTextLabel: plain Label.text
		# is also a Control text property, so it auto-refreshes on
		# TranslationServer.set_locale() with zero extra plumbing.
		speed_label.text = "UI_SPEED_LABEL"
		speed_decrease_button.pressed.connect(_on_speed_decrease)
		speed_increase_button.pressed.connect(_on_speed_increase)
		# NOT _apply_speed_to_helicase() here — PlayerUI is a child of
		# Simulation, so this _ready() runs BEFORE Simulation's own _ready()
		# (children before parents), meaning helicase_mgr doesn't exist yet.
		# The initial application happens in _on_simulation_initialized(),
		# same as everywhere else in this file that depends on simulation
		# state being live (e.g. the scrubber's max_value setup below).
		_update_speed_button_states()

		# WobbleToggle controls ThemeManager's own wobble_enabled export —
		# a cross-cutting visual dial, not something scoped to zoom_mgr.
		wobble_toggle.toggled.connect(_on_wobble_toggled)
		var tm = get_node_or_null("%ThemeManager")
		if tm:
			wobble_toggle.button_pressed = tm.wobble_enabled

		# Connect zoom controls
		# Connect zoom controls
		if zoom_mgr == null:  # already injected for vertical — see var declaration above
			zoom_mgr = get_node_or_null("%ZoomManager")		
		if zoom_mgr:
			# reset_zoom_button is NOT optional — it exists in both layouts.
			reset_zoom_button.pressed.connect(_on_reset_zoom_pressed)
			if highlight_button != null:
				highlight_button.toggled.connect(_on_highlight_toggled)
			if zoom_out_button != null:
				zoom_out_button.pressed.connect(_on_zoom_out_pressed)
			if zoom_in_button != null:
				zoom_in_button.pressed.connect(_on_zoom_in_pressed)
			if recenter_pan_button != null:
				recenter_pan_button.pressed.connect(_on_recenter_pan_pressed)
			if enzyme_dropdown != null:
				enzyme_dropdown.item_selected.connect(_on_enzyme_selected)
			zoom_mgr.zoom_level_changed.connect(_on_zoom_level_changed)
			zoom_mgr.target_changed.connect(_on_zoom_target_changed)
			# NOT populated here — PlayerUI is a child of Simulation, and
			# Godot calls _ready() bottom-up (children before parents), so
			# this fires BEFORE Simulation's own _ready() has registered any
			# targets (helicase/leading/lagging). targets_changed fires
			# whenever the target set actually changes — on initial
			# registration today, and later whenever a complexity toggle
			# registers/unregisters an enzyme — so the dropdown stays in
			# sync without needing to guess when registration is "done".
			zoom_mgr.targets_changed.connect(_populate_enzyme_dropdown)
			_update_zoom_button_states()

			# OptionButton item text isn't auto-translated the way
			# RichTextLabel.text is (per EnzymeLabelsDesign.md) — it needs an
			# explicit refresh, so hook the dropdown into the same
			# LocaleManager the rest of the enzyme-label system already uses.
			var locale_mgr = get_node_or_null("%LocaleManager")
			if locale_mgr:
				locale_mgr.locale_changed.connect(func(_new_locale): _populate_enzyme_dropdown())
		else:
			push_error("PlayerUI: %ZoomManager not found!")
			if zoom_controls != null:
				zoom_controls.visible = false

		# NCloudToggle controls nucleotide_field.gd's own "enabled" export —
		# a separate decorative system, unrelated to zoom_mgr's presence, so
		# this is wired independently of the block above.
		if ncloud_toggle != null:
			ncloud_toggle.toggled.connect(_on_ncloud_toggled)
			if simulation and simulation.nucleotide_field:
				ncloud_toggle.button_pressed = simulation.nucleotide_field.enabled

		# Connect the sequence loader popup (sibling under UI)
		var popup = get_node("../SequenceLoaderPopup")
		if popup:
			popup.sequence_loaded.connect(_on_sequence_loaded)
		else:
			push_error("PlayerUI: SequenceLoaderPopup not found as sibling!")

		# Initial UI state
		_on_simulation_initialized(simulation.num_nucleotide_slots)
	else:
		push_error("PlayerUI: simulation node not assigned!")

# ==========================================
# SLIDER / SCRUBBER
# ==========================================

## Shared by the scrubber drag and SequenceLabel's click/drag-to-scrub
## (LongSequenceDesign.md Part 4) — pause if not already manually stepping,
## scrub, and refresh the UI. One code path instead of two copies of the
## same pause/scrub/update sequence.
func _scrub_to_index(index: int) -> void:
	index = clamp(index, 0, simulation.get_max_scrub_index())
	if not simulation.manual_override:
		simulation.toggle_play()
		play_pause_button.text = "▶"
	simulation.scrub_to_nucleotide_index(index)
	_update_ui()

func _on_scrubber_dragged(value: float):
	_is_dragging = true
	_scrub_to_index(int(round(value)))

	await get_tree().process_frame
	_is_dragging = false

## LongSequenceDesign.md follow-up — helicase_ring.gd / polymerase_clamp.gd
## drag gestures arrive here already converted to a target index (see
## simulation.gd's request_drag_scrub()); this just reuses the same shared
## helper as the scrubber and SequenceLabel, so pause-on-drag and the UI
## refresh stay one code path instead of a fourth copy of it.
func _on_drag_scrub_requested(index: int) -> void:
	_scrub_to_index(index)

# ==========================================
# SEQUENCE LABEL — click/drag-to-scrub (LongSequenceDesign.md Part 4)
# Every visible character is wrapped in [url=ABSOLUTE_INDEX] by
# get_sequence_rich_text(); these handlers convert that meta back into a
# scrub action, reusing _scrub_to_index() above rather than duplicating it.
# ==========================================

func _on_sequence_label_meta_clicked(meta):
	_scrub_to_index(int(meta))

## Fires on every span transition regardless of button state (hover
## tracking is motion-based, not click-based) — this is what lets the same
## signal serve two purposes: plain hover highlighting, and (when
## _is_label_dragging is true) continuous scrub-while-dragging, mirroring
## how dragging the slider itself works.
func _on_sequence_label_meta_hover_started(meta):
	_hover_index = int(meta)
	sequence_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if _is_label_dragging:
		_scrub_to_index(_hover_index)
	else:
		_update_ui()  # refresh immediately rather than waiting for the next progress tick

func _on_sequence_label_meta_hover_ended(meta):
	if int(meta) == _hover_index:
		_hover_index = -1
		sequence_label.mouse_default_cursor_shape = Control.CURSOR_ARROW
		_update_ui()

## The only way to observe raw mouse-button state on a RichTextLabel —
## unlike HSlider, it has no built-in drag concept, so drag-to-scrub is
## synthesized from this plus meta_hover_started's span transitions above.
func _on_sequence_label_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_is_label_dragging = event.pressed

# ==========================================
# TRANSPORT CONTROLS
# ==========================================

func _on_play_pause():
	simulation.toggle_play()
	play_pause_button.text = "⏸" if not simulation.manual_override else "▶"
	_update_ui()

func _on_stop_pressed():
	"""Stop the simulation and reset to the beginning."""
	# Pause the simulation
	if not simulation.manual_override:
		simulation.toggle_play()
		play_pause_button.text = "▶"

	# Jump to the start
	simulation.scrub_to_nucleotide_index(0)
	scrubber.set_value_no_signal(0)
	_update_ui()

func _on_forward():
	var current = simulation.get_synthesized_count()
	var target = min(simulation.get_max_scrub_index(), current + 1)
	simulation.scrub_to_nucleotide_index(target)
	scrubber.set_value_no_signal(target)
	_update_ui()

func _on_backward():
	var current = simulation.get_synthesized_count()
	var target = max(0, current - 1)
	simulation.scrub_to_nucleotide_index(target)
	scrubber.set_value_no_signal(target)
	_update_ui()

func _on_fast_forward():
	var current = simulation.get_synthesized_count()
	var target = min(simulation.get_max_scrub_index(), current + simulation.okazaki_fragment_size)
	simulation.scrub_to_nucleotide_index(target)
	scrubber.set_value_no_signal(target)
	_update_ui()

func _on_fast_backward():
	var current = simulation.get_synthesized_count()
	var target = max(0, current - simulation.okazaki_fragment_size)
	simulation.scrub_to_nucleotide_index(target)
	scrubber.set_value_no_signal(target)
	_update_ui()


func _on_eject_pressed():
	"""Open the sequence loader popup."""
	var popup = get_node("../SequenceLoaderPopup")
	if not popup:
		push_error("PlayerUI: SequenceLoaderPopup not found!")
		return

	# Pause the simulation
	if not simulation.manual_override:
		simulation.toggle_play()
		play_pause_button.text = "▶"

	popup.show_dialog()

func _on_menu_pressed():
	"""Reopen the complexity setup popup (Pol I / Ligase / Primase toggles)."""
	var popup = get_node_or_null("../ComplexitySetupPopup")
	if not popup:
		push_error("PlayerUI: ComplexitySetupPopup not found!")
		return

	# Pause the simulation while reconfiguring — same pattern as
	# _on_eject_pressed()'s SequenceLoaderPopup handling below.
	if not simulation.manual_override:
		simulation.toggle_play()
		play_pause_button.text = "▶"

	popup.show_dialog()

# ==========================================
# SPEED CONTROLS
# Converge on helicase_mgr.set_speed(), same narrow-API discipline the zoom
# controls use with ZoomManager — this file never computes speed math itself,
# just walks the SPEED_VALUES ladder and forwards the result.
# ==========================================

func _on_speed_decrease():
	_speed_index = max(0, _speed_index - 1)
	_apply_speed_to_helicase()
	_update_speed_display()

func _on_speed_increase():
	_speed_index = min(SPEED_VALUES.size() - 1, _speed_index + 1)
	_apply_speed_to_helicase()
	_update_speed_display()

func _apply_speed_to_helicase():
	if simulation and simulation.helicase_mgr != null:
		simulation.helicase_mgr.set_speed(SPEED_VALUES[_speed_index])

func _update_speed_display():
	# "0x" is display-only (see the SPEED CONTROLS state comment near the top
	# of this file) — it never gets passed to set_speed(). The underlying
	# ladder selection is untouched while paused/done, so play/resume picks
	# the real speed back up with no extra bookkeeping.
	#
	# Deliberately NOT _is_simulation_done() here: that checks only
	# helicase_mgr.get_phase() == Phase.DONE, but the lagging strand keeps
	# synthesizing on its own independent catch-up timer for a while after
	# the helicase itself reaches DONE (see replication_manager.gd's
	# _lagging_start_catchup()). is_fully_complete() is true only once the
	# whole replisome has actually faded out.
	var truly_done = simulation and simulation.replication_mgr != null and simulation.replication_mgr.is_fully_complete()
	if truly_done or (simulation and simulation.manual_override):
		speed_value_label.text = "0x"
	else:
		speed_value_label.text = SPEED_DISPLAY[_speed_index]
	_update_speed_button_states()

func _update_speed_button_states():
	speed_decrease_button.disabled = (_speed_index <= 0)
	speed_increase_button.disabled = (_speed_index >= SPEED_VALUES.size() - 1)

# ==========================================
# ZOOM CONTROLS
# All four controls converge on ZoomManager's narrow player-input API
# (select_target / set_zoom_level / reset_zoom / set_highlight_enabled) —
# see ZoomDesign.md. This file never computes camera math itself.
# ==========================================

func _on_highlight_toggled(pressed: bool):
	zoom_mgr.set_highlight_enabled(pressed)

func _on_ncloud_toggled(pressed: bool):
	if simulation and simulation.nucleotide_field:
		simulation.nucleotide_field.enabled = pressed

func _on_wobble_toggled(pressed: bool):
	var tm = get_node_or_null("%ThemeManager")
	if tm:
		tm.wobble_enabled = pressed

func _on_zoom_out_pressed():
	zoom_mgr.set_zoom_level(zoom_mgr.zoom_level - 1)

func _on_zoom_in_pressed():
	# Guard mirrors the disabled state set in _update_zoom_button_states():
	# + should be a no-op at level 1 with nothing ever selected yet — but
	# free-camera mode is a separate state where current_target_id is always
	# "" by construction, so this guard doesn't apply there.
	if not zoom_mgr.free_camera_mode() and zoom_mgr.zoom_level == 1 and zoom_mgr.current_target_id == "":
		return
	zoom_mgr.set_zoom_level(zoom_mgr.zoom_level + 1)

func _on_reset_zoom_pressed():
	print("[RESETZOOM] button pressed")
	zoom_mgr.reset_zoom()

## LongSequenceDesign.md Part 3 — explicit recenter action, distinct from
## the full reset_zoom() above (which also clears target and returns to
## level 1). Only meaningful in level-1 fit-to-height mode; disabled
## otherwise (see _update_zoom_button_states()).
func _on_recenter_pan_pressed():
	zoom_mgr.recenter_pan()

func _on_enzyme_selected(index: int):
	var id = enzyme_dropdown.get_item_metadata(index)
	if id != null:
		zoom_mgr.select_target(id)

func _on_zoom_level_changed(_new_level: int):
	_update_zoom_button_states()

func _on_zoom_target_changed(new_target_id: String):
	# Keep the dropdown in sync if the target changed via some other input
	# method (keyboard/click/voice, later) rather than the dropdown itself.
	# Driven by zoom_mgr's signal, not by the dropdown — so this still fires in
	# the vertical layout, where there is no dropdown to sync.
	if enzyme_dropdown != null:
		if new_target_id == "":
			enzyme_dropdown.select(0)  # placeholder
		else:
			for i in range(enzyme_dropdown.item_count):
				if enzyme_dropdown.get_item_metadata(i) == new_target_id:
					enzyme_dropdown.select(i)
					break
	_update_zoom_button_states()

func _populate_enzyme_dropdown():
	# Connected to zoom_mgr.targets_changed and LocaleManager.locale_changed —
	# both still fire in the vertical layout, which has no dropdown.
	if enzyme_dropdown == null:
		return
	var previous_id = zoom_mgr.current_target_id
	enzyme_dropdown.clear()

	# Placeholder — shown until the player actually picks an enzyme, rather
	# than defaulting to whichever one happens to be registered first
	# (previously always "Helicase"). Disabled so it can't be re-selected
	# once a real choice is made; metadata stays null, already guarded in
	# _on_enzyme_selected().
	enzyme_dropdown.add_item(tr("UI_ENZYME_DROPDOWN_PLACEHOLDER"))
	enzyme_dropdown.set_item_disabled(0, true)

	var ids = zoom_mgr.get_target_ids()
	for id in ids:
		var display_name = zoom_mgr.get_target_display_name(id)
		enzyme_dropdown.add_item(display_name)
		enzyme_dropdown.set_item_metadata(enzyme_dropdown.item_count - 1, id)

	if ids.is_empty() or previous_id == "" or not ids.has(previous_id):
		# Nothing valid was previously selected — show the placeholder
		# rather than auto-picking the first registered enzyme. Still a UI
		# sync, so explicitly clears current_target_id (rather than leaving
		# a stale/now-invalid id behind) instead of just skipping the call.
		enzyme_dropdown.select(0)
		zoom_mgr.set_pending_target("")
		_update_zoom_button_states()
		return

	# Restore whichever target was already current (e.g. after a future
	# complexity toggle re-registers targets) — a UI sync, not a player
	# action, so it uses set_pending_target() rather than select_target()
	# — no jump to level 3.
	enzyme_dropdown.select(ids.find(previous_id) + 1)  # +1 for the placeholder at index 0
	zoom_mgr.set_pending_target(previous_id)
	_update_zoom_button_states()

func _update_zoom_button_states():
	if not zoom_mgr:
		return
	# Every button below is omitted from the vertical layout (ResetZoom, which
	# both layouts keep, is stateless and isn't touched here) — so one guard
	# covers the function.
	if zoom_out_button == null or zoom_in_button == null or recenter_pan_button == null:
		return
	if zoom_mgr.free_camera_mode():
		# Continuous zoom in this mode — always available, no discrete
		# ladder to reach the top/bottom of.
		zoom_out_button.disabled = false
		zoom_in_button.disabled = false
	else:
		zoom_out_button.disabled = (zoom_mgr.zoom_level <= 1)
		var no_target_yet = zoom_mgr.current_target_id == ""
		var target_unavailable = no_target_yet or not zoom_mgr.is_target_visible(zoom_mgr.current_target_id)
		zoom_in_button.disabled = (zoom_mgr.zoom_level >= 3) or target_unavailable
	# Free-camera mode: always available now (centers the track, see
	# recenter_pan()'s free-camera branch). Otherwise: only meaningful in
	# level-1 fit-to-height windowed mode.
	recenter_pan_button.disabled = not zoom_mgr.free_camera_mode() and not zoom_mgr.is_windowed_mode()

## Called every frame (see _process below) since enzyme visibility changes
## continuously during play (proximity fade-in/out), not just on discrete
## events like zoom_level_changed/target_changed — a dropdown item that's
## disabled because its enzyme isn't on screen yet needs to re-enable itself
## the moment that enzyme fades in, without waiting for some other action.
func _update_enzyme_dropdown_availability():
	if enzyme_dropdown == null:
		_update_zoom_button_states()
		return
	for i in range(enzyme_dropdown.item_count):
		var id = enzyme_dropdown.get_item_metadata(i)
		if id != null:
			enzyme_dropdown.set_item_disabled(i, not zoom_mgr.is_target_visible(id))
	_update_zoom_button_states()

func _process(_delta: float) -> void:
	if zoom_mgr:
		_update_enzyme_dropdown_availability()

# ==========================================
# SIMULATION SIGNAL CALLBACKS
# ==========================================

func _on_simulation_initialized(total_bases: int):
	"""Called when a new sequence is loaded."""
	scrubber.max_value = float(simulation.get_max_scrub_index())
	scrubber.value = 0.0
	play_pause_button.text = "▶"
	# helicase_mgr was just destroyed and recreated (see simulation.gd's
	# initialize_simulation()) and always starts back at speed_multiplier =
	# 1.0 — reapply whatever speed was already selected so it survives a
	# sequence reload instead of silently resetting to 1x.
	_apply_speed_to_helicase()
	_update_ui()
	_update_button_states()

func _on_simulation_progress_changed(new_progress: float):
	"""Called every frame by the simulation."""
	if not _is_dragging:
		var total = float(simulation.get_max_scrub_index())
		var current_index = int(round(new_progress * total))
		current_index = clamp(current_index, 0, simulation.get_max_scrub_index())
		scrubber.set_value_no_signal(current_index)
		_update_ui()

	if _is_simulation_done():
		play_pause_button.text = "▶"

func _on_sequence_loaded(new_sequence: String):
	"""Called when the user loads a new sequence from the popup."""
	print("[PlayerUI] New sequence loaded: %s" % new_sequence)

	# Initialize the simulation with the new sequence
	simulation.initialize_simulation(new_sequence)

	# Reset zoom to the overworld and reframe for the new strand length —
	# instant, not animated, since panning from the old track's framing
	# would look wrong on a fresh load.
	if zoom_mgr and zoom_mgr.has_method("reset_zoom_instant"):
		zoom_mgr.reset_zoom_instant()

	# Reset the scrubber
	scrubber.value = 0.0

	# Reset the play button
	play_pause_button.text = "▶"

	# Update UI
	_update_ui()

# ==========================================
# UI UPDATE HELPERS
# ==========================================

func _update_ui():
	if not simulation:
		return

	# Match scrubber width to the label's content width, so a scrub position
	# lines up with the glyph under it. The vertical layout drops SequenceLabel,
	# so it also drops this rule — the Scrubber sizes itself by container fill
	# there instead (size_flags_horizontal on the node), which is why that isn't
	# just an omission but a deliberate second rule.
	#
	# Note the await below is inside the guard: without SequenceLabel this
	# function no longer yields. Harmless — every caller is fire-and-forget —
	# but it does mean _update_ui() is a coroutine in one layout and not the
	# other.
	if sequence_label != null:
		sequence_label.queue_redraw()
		await get_tree().process_frame
		var label_width = sequence_label.get_content_width()
		scrubber.custom_minimum_size.x = max(label_width, 100)  # Minimum 100px for usability
		sequence_label.bbcode_text = simulation.get_sequence_rich_text(_hover_index)

	_update_speed_display()
	_update_button_states()

func _update_button_states():
	var count = simulation.get_synthesized_count()
	var total = simulation.get_max_scrub_index()

	backward.disabled = (count <= 0)
	forward.disabled = (count >= total)
	fast_backward.disabled = (count <= 0)
	fast_forward.disabled = (count >= total)

	stop_button.text = "" if _is_simulation_done() else _stop_icon_default

