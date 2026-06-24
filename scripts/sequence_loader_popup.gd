extends ColorRect

# ==========================================
# SEQUENCE LOADER POPUP
# UI-only dialog for loading custom DNA/RNA sequences.
# Uses DnaSequenceResource for all sequence data.
# ==========================================

signal sequence_loaded(sequence: String)

# --- DEBUG: Set to true to auto-show when running this scene alone (F6) ---
const DEBUG_AUTO_SHOW: bool = false

# UI Node References
@onready var sequence_input: LineEdit = $CenterContainer/DialogPanel/MarginContainer/MainLayout/SequenceInput
@onready var char_count_label: Label = $CenterContainer/DialogPanel/MarginContainer/MainLayout/CharCountLabel
@onready var option_button: OptionButton = $CenterContainer/DialogPanel/MarginContainer/MainLayout/PresetsRow/OptionButton
@onready var cancel_button: Button = $CenterContainer/DialogPanel/MarginContainer/MainLayout/ActionsRow/CancelButton
@onready var ok_button: Button = $CenterContainer/DialogPanel/MarginContainer/MainLayout/ActionsRow/OKButton

# Reference to the sequence resource (local copy for UI operations)
var dna_sequence: DnaSequenceResource

func _ready():
	# Create a local resource for UI operations
	dna_sequence = DnaSequenceResource.new()
	
	# Connect UI signals
	sequence_input.text_changed.connect(_on_sequence_text_changed)
	sequence_input.text_submitted.connect(_on_sequence_submitted)
	option_button.item_selected.connect(_on_preset_selected)
	cancel_button.pressed.connect(_on_cancel_pressed)
	ok_button.pressed.connect(_on_ok_pressed)
	
	# Populate the preset dropdown
	_populate_presets()
	
	visible = false
	
	if DEBUG_AUTO_SHOW:
		show_dialog()

func show_dialog():
	"""Show the dialog and focus the input field."""
	visible = true
	
	# Generate a random sequence using the resource
	var random_seq = dna_sequence.get_preset_string("Aleatória")
	sequence_input.text = random_seq
	sequence_input.select_all()
	sequence_input.grab_focus()
	_update_char_count()

func hide_dialog():
	visible = false

# ----- PRIVATE HELPERS -----

func _populate_presets():
	"""Populate the dropdown with preset names from the resource."""
	option_button.clear()
	var preset_names = dna_sequence.get_preset_names()
	for name in preset_names:
		option_button.add_item(name)
	option_button.selected = 0

func _update_char_count():
	var current_len = sequence_input.text.length()
	char_count_label.text = "%d / %d caracteres" % [current_len, dna_sequence.MAX_LENGTH]
	ok_button.disabled = not dna_sequence.is_valid_sequence(sequence_input.text)

func _load_preset(preset_name: String):
	"""Load a preset from the resource and display it."""
	var preset_string = dna_sequence.get_preset_string(preset_name)
	sequence_input.text = preset_string
	_update_char_count()
	sequence_input.select_all()
	sequence_input.grab_focus()

# ----- SIGNAL HANDLERS -----

func _on_sequence_text_changed(new_text: String):
	# Filter: only allow valid bases, automatically uppercase
	var filtered = dna_sequence.clean_sequence(new_text)
	if filtered != new_text:
		sequence_input.text = filtered
		sequence_input.caret_column = filtered.length()
	_update_char_count()

func _on_sequence_submitted(entered_text: String):
	if dna_sequence.is_valid_sequence(entered_text):
		_on_ok_pressed()
	else:
		sequence_input.add_theme_color_override("font_color", Color(1, 0, 0))
		await get_tree().create_timer(0.3).timeout
		sequence_input.remove_theme_color_override("font_color")

func _on_preset_selected(index: int):
	var preset_name = option_button.get_item_text(index)
	_load_preset(preset_name)

func _on_cancel_pressed():
	hide_dialog()

func _on_ok_pressed():
	var raw_text = sequence_input.text
	var cleaned = dna_sequence.clean_sequence(raw_text)
	
	if not dna_sequence.is_valid_sequence(cleaned):
		sequence_input.add_theme_color_override("font_color", Color(1, 0, 0))
		return
	
	sequence_input.remove_theme_color_override("font_color")
	
	# Emit the cleaned sequence string
	sequence_loaded.emit(cleaned)
	hide_dialog()