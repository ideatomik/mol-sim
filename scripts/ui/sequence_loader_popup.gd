extends ColorRect

# ==========================================
# SEQUENCE LOADER POPUP
# UI-only dialog for loading custom DNA/RNA sequences.
# Uses DnaSequenceResource for all sequence data.
# ==========================================

signal sequence_loaded(sequence: String, okazaki_fragment_size: int)

# --- DEBUG: Set to true to auto-show when running this scene alone (F6) ---
const DEBUG_AUTO_SHOW: bool = false

# UI Node References
@onready var sequence_input: LineEdit = $CenterContainer/DialogPanel/MarginContainer/MainLayout/SequenceInput
@onready var char_count_label: Label = $CenterContainer/DialogPanel/MarginContainer/MainLayout/CharCountLabel
@onready var option_button: OptionButton = $CenterContainer/DialogPanel/MarginContainer/MainLayout/PresetsRow/OptionButton
@onready var fragment_size_slider: HSlider = %FragmentSizeSlider
@onready var fragment_size_value_label: Label = %FragmentSizeValueLabel
@onready var cancel_button: Button = $CenterContainer/DialogPanel/MarginContainer/MainLayout/ActionsRow/CancelButton
@onready var ok_button: Button = $CenterContainer/DialogPanel/MarginContainer/MainLayout/ActionsRow/OKButton

# Reference to the sequence resource (local copy for UI operations)
var dna_sequence: DnaSequenceResource

func _ready():
	# Create a local resource for UI operations
	dna_sequence = DnaSequenceResource.new()

	# Sync the LineEdit's own hard character limit to the resource's ceiling
	# — otherwise this is a fourth place the length limit could silently
	# drift out of sync with MAX_LENGTH.
	sequence_input.max_length = dna_sequence.MAX_LENGTH
	
	# Connect UI signals
	sequence_input.text_changed.connect(_on_sequence_text_changed)
	sequence_input.text_submitted.connect(_on_sequence_submitted)
	option_button.item_selected.connect(_on_preset_selected)
	fragment_size_slider.value_changed.connect(_on_fragment_size_slider_changed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	ok_button.pressed.connect(_on_ok_pressed)
	
	# Populate the preset dropdown
	_populate_presets()

	# OptionButton item text isn't auto-translated the way RichTextLabel.text
	# is (per EnzymeLabelsDesign.md) — needs an explicit refresh on locale
	# switch, same pattern player_ui.gd already uses for the enzyme dropdown.
	var locale_mgr = get_node_or_null("%LocaleManager")
	if locale_mgr:
		locale_mgr.locale_changed.connect(func(_new_locale): _populate_presets())

	visible = false
	
	if DEBUG_AUTO_SHOW:
		show_dialog()

func show_dialog(is_startup: bool = false) -> void:
	"""Show the dialog and focus the input field. is_startup hides Cancel —
	at first boot there's no already-loaded sequence to cancel back to, and
	closing the dialog with nothing loaded just leaves the game in a blank
	state. Mid-session reopens (PlayerUI's Eject button) always have a prior
	sequence, so they keep the default false and Cancel stays visible."""
	visible = true
	cancel_button.visible = not is_startup

	# Generate a random sequence using the resource. "Aleatória" no longer
	# exists as a preset — PRESET_MEDIA (57 bases) is the replacement default
	# for the dialog's initial fill.
	var random_seq = dna_sequence.get_preset_string("PRESET_MEDIA")
	sequence_input.text = random_seq
	sequence_input.select_all()
	sequence_input.grab_focus()
	_update_char_count()
	_update_fragment_size_bounds()

	# The dropdown doesn't actually reflect PRESET_MEDIA (the fill above is
	# a fresh random draw, not that preset's fixed string) — select() alone
	# doesn't emit item_selected, so this is silent, matching what's
	# actually in the text field.
	option_button.select(0)

func hide_dialog():
	visible = false

# ----- PRIVATE HELPERS -----

func _populate_presets():
	"""Populate the dropdown with preset names from the resource. Item text
	is the translated display string; the stable lookup key is stored as
	metadata — same split EnzymeLabelsDesign.md established for enzyme
	labels, and the same pattern player_ui.gd already uses for the enzyme
	dropdown, since OptionButton items don't auto-translate on their own.

	Item 0 is a blank placeholder (metadata null) representing "no preset
	selected" — show_dialog() selects it under the random fill-text, so
	picking the preset that already happens to be item 0 (e.g. Short) still
	changes the selection and fires item_selected, instead of silently
	no-opping because it was already the selected index."""
	var previous_key = option_button.get_item_metadata(option_button.selected) if option_button.item_count > 0 else null
	option_button.clear()
	option_button.add_item("")
	var preset_keys = dna_sequence.get_preset_names()
	for key in preset_keys:
		option_button.add_item(tr(key))
		option_button.set_item_metadata(option_button.item_count - 1, key)

	var restore_index = 0
	if previous_key != null:
		for i in range(preset_keys.size()):
			if preset_keys[i] == previous_key:
				restore_index = i + 1
				break
	option_button.selected = restore_index

func _update_char_count():
	var current_len = sequence_input.text.length()
	char_count_label.text = tr("UI_CHAR_COUNT") % [current_len, dna_sequence.MAX_LENGTH]
	ok_button.disabled = not dna_sequence.is_valid_sequence(sequence_input.text)

## Derives the valid okazaki_fragment_size range from sequence length —
## short sequences shouldn't be given a nonsensically large fragment size
## (or vice versa). Formula tuned by hand against known-good values (30
## bases -> min 5, max 12): max keeps fragments a sensible fraction of the
## strand, min keeps them from degenerating to near-single-slot fragments.
func _fragment_size_bounds(length: int) -> Vector2i:
	var lo := int(max(1, ceil(length / 6.0)))
	var hi := int(max(1, round(length / 2.5)))
	if lo > hi:
		lo = hi  # pathologically short sequences — degenerate to a single value
	return Vector2i(lo, hi)

## Recomputes the slider's live range from the current SequenceInput text,
## clamps an out-of-range value into the new bounds, and refreshes the
## value label. Called from every code path that changes SequenceInput's
## text, same as _update_char_count() above.
func _update_fragment_size_bounds():
	var bounds := _fragment_size_bounds(sequence_input.text.length())
	fragment_size_slider.min_value = bounds.x
	fragment_size_slider.max_value = bounds.y
	if fragment_size_slider.value < bounds.x or fragment_size_slider.value > bounds.y:
		fragment_size_slider.value = clamp(12, bounds.x, bounds.y)
	_update_fragment_size_label()

func _update_fragment_size_label():
	fragment_size_value_label.text = "%d (%d-%d)" % [
		int(fragment_size_slider.value), int(fragment_size_slider.min_value), int(fragment_size_slider.max_value)
	]

func _load_preset(preset_name: String):
	"""Load a preset from the resource and display it."""
	var preset_string = dna_sequence.get_preset_string(preset_name)
	sequence_input.text = preset_string
	_update_char_count()
	_update_fragment_size_bounds()
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
	_update_fragment_size_bounds()

func _on_fragment_size_slider_changed(_value: float) -> void:
	_update_fragment_size_label()

func _on_sequence_submitted(entered_text: String):
	if dna_sequence.is_valid_sequence(entered_text):
		_on_ok_pressed()
	else:
		sequence_input.add_theme_color_override("font_color", Color(1, 0, 0))
		await get_tree().create_timer(0.3).timeout
		sequence_input.remove_theme_color_override("font_color")

func _on_preset_selected(index: int):
	var preset_key = option_button.get_item_metadata(index)
	if preset_key != null:
		_load_preset(preset_key)

func _on_cancel_pressed():
	hide_dialog()

func _on_ok_pressed():
	var raw_text = sequence_input.text
	var cleaned = dna_sequence.clean_sequence(raw_text)
	
	if not dna_sequence.is_valid_sequence(cleaned):
		sequence_input.add_theme_color_override("font_color", Color(1, 0, 0))
		return
	
	sequence_input.remove_theme_color_override("font_color")
	
	# Emit the cleaned sequence string, plus the chosen fragment size
	sequence_loaded.emit(cleaned, int(fragment_size_slider.value))
	hide_dialog()