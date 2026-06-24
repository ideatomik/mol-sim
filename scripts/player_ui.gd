extends CanvasLayer

# ==========================================
# PLAYER UI
# Transport controls for the DNA simulation.
# ==========================================

@export var simulation: Node2D  # Drag the root Simulation node here

# UI Node References
@onready var sequence_label: RichTextLabel = $Panel/MarginContainer/VBoxContainer/SequenceLabel
@onready var scrubber: HSlider = $Panel/MarginContainer/VBoxContainer/Scrubber
@onready var transport_buttons: HBoxContainer = $Panel/MarginContainer/VBoxContainer/TransportButtons

# Transport Buttons
@onready var menu_button: Button = $Panel/MarginContainer/VBoxContainer/TransportButtons/Menu
@onready var fast_backward: Button = $Panel/MarginContainer/VBoxContainer/TransportButtons/FastBackward
@onready var backward: Button = $Panel/MarginContainer/VBoxContainer/TransportButtons/Backward
@onready var play_pause_button: Button = $Panel/MarginContainer/VBoxContainer/TransportButtons/PlayPauseButton
@onready var stop_button: Button = $Panel/MarginContainer/VBoxContainer/TransportButtons/StopButton
@onready var forward: Button = $Panel/MarginContainer/VBoxContainer/TransportButtons/Forward
@onready var fast_forward: Button = $Panel/MarginContainer/VBoxContainer/TransportButtons/FastForward
@onready var eject_button: Button = $Panel/MarginContainer/VBoxContainer/TransportButtons/Eject

var _is_dragging: bool = false

# ==========================================
# LIFECYCLE
# ==========================================

func _ready():
	# Configure the scrubber
	scrubber.min_value = 0
	scrubber.step = 1.0
	scrubber.value_changed.connect(_on_scrubber_dragged)

	# Connect simulation signals
	if simulation:
		simulation.progress_changed.connect(_on_simulation_progress_changed)
		simulation.simulation_initialized.connect(_on_simulation_initialized)

		# Connect all transport buttons
		menu_button.pressed.connect(_on_menu_pressed)
		fast_backward.pressed.connect(_on_fast_backward)
		backward.pressed.connect(_on_backward)
		play_pause_button.pressed.connect(_on_play_pause)
		stop_button.pressed.connect(_on_stop_pressed)
		forward.pressed.connect(_on_forward)
		fast_forward.pressed.connect(_on_fast_forward)
		eject_button.pressed.connect(_on_eject_pressed)

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

func _on_scrubber_dragged(value: float):
	_is_dragging = true
	var index = int(round(value))
	index = clamp(index, 0, simulation.num_nucleotide_slots)

	# Pause the simulation when the user drags
	if not simulation.manual_override:
		simulation.toggle_play()
		play_pause_button.text = "▶"

	simulation.scrub_to_nucleotide_index(index)
	_update_ui()

	await get_tree().process_frame
	_is_dragging = false

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
	var target = min(simulation.num_nucleotide_slots, current + 1)
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
	var target = min(simulation.num_nucleotide_slots, current + 5)
	simulation.scrub_to_nucleotide_index(target)
	scrubber.set_value_no_signal(target)
	_update_ui()

func _on_fast_backward():
	var current = simulation.get_synthesized_count()
	var target = max(0, current - 5)
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
	"""Open the main menu (placeholder for now)."""
	print("[PlayerUI] Menu button pressed - TODO: Open main menu")
	# Later we'll add a proper menu system here

# ==========================================
# SIMULATION SIGNAL CALLBACKS
# ==========================================

func _on_simulation_initialized(total_bases: int):
	"""Called when a new sequence is loaded."""
	scrubber.max_value = float(total_bases)
	scrubber.value = 0.0
	play_pause_button.text = "▶"
	_update_ui()
	_update_button_states()

func _on_simulation_progress_changed(new_progress: float):
	"""Called every frame by the simulation."""
	if not _is_dragging:
		var total = float(simulation.num_nucleotide_slots)
		var current_index = int(round(new_progress * total))
		current_index = clamp(current_index, 0, simulation.num_nucleotide_slots)
		scrubber.set_value_no_signal(current_index)
		_update_ui()

func _on_sequence_loaded(new_sequence: String):
	"""Called when the user loads a new sequence from the popup."""
	print("[PlayerUI] New sequence loaded: %s" % new_sequence)

	# Initialize the simulation with the new sequence
	simulation.initialize_simulation(new_sequence)

	# Reframe the camera to fit the new strand length.
	var camera = get_viewport().get_camera_2d()
	if camera and camera.has_method("_frame_strand"):
		camera._frame_strand()

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

	# Update sequence label with rich text
	sequence_label.bbcode_text = simulation.get_sequence_rich_text()

	_update_button_states()

func _update_button_states():
	var count = simulation.get_synthesized_count()
	var total = simulation.num_nucleotide_slots

	backward.disabled = (count <= 0)
	forward.disabled = (count >= total)
	fast_backward.disabled = (count <= 0)
	fast_forward.disabled = (count >= total)

	# Stop button is always enabled
	# Eject button is always enabled
	# Menu button is always enabled
