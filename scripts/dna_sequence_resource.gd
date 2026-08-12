class_name DnaSequenceResource
extends Resource

# ==========================================
# DNA SEQUENCE RESOURCE
# Single source of truth for all sequence data.
# Owns presets, random generation, and complement logic.
# ==========================================

# ---------- CONSTANTS ----------
const VALID_BASES: Array[String] = ["A", "T", "C", "G", "U"]
## Bases used for random DNA generation -- U excluded until RNA/transcription is implemented.
const DNA_BASES: Array[String] = ["A", "T", "C", "G"]

const COMPLEMENTS: Dictionary = {
	"A": "T",
	"T": "A",
	"C": "G",
	"G": "C",
	"U": "A"   # RNA complement
}

const MIN_LENGTH: int = 18
const MAX_LENGTH: int = 300

# ---------- PRESETS ----------
# Stable keys (never shown to the user directly) — display text lives in
# presets.csv, mirroring the enzyme-label pattern (EnzymeLabelsDesign.md).
# Random content, pinned length, re-rolled fresh every selection.
const RANDOM_LENGTH_PRESETS: Dictionary = {
	"PRESET_CURTA": 34,
	"PRESET_MEDIA": 57,
	"PRESET_LONGA": 90,
}

# Explicit dropdown order.
const PRESET_ORDER: Array[String] = [
	"PRESET_CURTA", "PRESET_MEDIA", "PRESET_LONGA",
]

# ---------- DATA ----------
@export var sequence: Array[String] = []

# ==========================================
# PUBLIC METHODS
# ==========================================

func randomize_sequence(length: int = -1) -> void:
	"""Generate a random sequence. If length is -1, pick random length between MIN and MAX."""
	if length < 0:
		length = randi_range(MIN_LENGTH, MAX_LENGTH)
	sequence.clear()
	for i in range(length):
		sequence.append(DNA_BASES[randi() % DNA_BASES.size()])

func set_from_string(s: String, target_length: int = -1) -> void:
	"""Parse a string into the sequence array, filtering invalid characters."""
	sequence.clear()
	for c in s.to_upper():
		if c in VALID_BASES:
			sequence.append(c)
	if target_length > 0:
		while sequence.size() > target_length:
			sequence.pop_back()
		while sequence.size() < target_length:
			sequence.append(DNA_BASES[randi() % DNA_BASES.size()])

func get_complement(index: int) -> String:
	"""Return the Watson-Crick complement of the base at the given index."""
	if index < 0 or index >= sequence.size():
		push_warning("DnaSequenceResource.get_complement: index %d out of range (size=%d)" % [index, sequence.size()])
		return ""
	return COMPLEMENTS.get(sequence[index], "")

func get_base(index: int) -> String:
	"""Return the base at the given index, or empty string if out of range."""
	if index >= 0 and index < sequence.size():
		return sequence[index]
	return ""

func get_length() -> int:
	return sequence.size()

func is_empty() -> bool:
	return sequence.is_empty()

# FIXED: Use _to_string() to override Godot's built-in string representation
func _to_string() -> String:
	return "".join(sequence)

# ---------- PRESET METHODS ----------

func load_preset(preset_name: String) -> String:
	"""Load a preset by name. Returns the preset string (or empty if not found)."""
	if not RANDOM_LENGTH_PRESETS.has(preset_name):
		return ""
	randomize_sequence(RANDOM_LENGTH_PRESETS[preset_name])
	return _to_string()

func get_preset_names() -> Array[String]:
	"""Return the stable preset keys, in dropdown display order. Display
	translation happens at the call site (tr()), not here — these are
	lookup keys, not display text."""
	return PRESET_ORDER.duplicate()

func get_preset_string(preset_name: String) -> String:
	"""Get the raw string for a preset (without loading it into the sequence)."""
	if not RANDOM_LENGTH_PRESETS.has(preset_name):
		return ""
	# Generate on a temporary instance so previewing a random-length
	# preset doesn't disturb this resource's own live state.
	var temp_seq = DnaSequenceResource.new()
	temp_seq.randomize_sequence(RANDOM_LENGTH_PRESETS[preset_name])
	return temp_seq._to_string()

# ---------- VALIDATION ----------

func is_valid_sequence(s: String) -> bool:
	"""Check if a string is a valid sequence (length and characters)."""
	var cleaned = s.to_upper().replace(" ", "")
	var len = cleaned.length()
	if len < MIN_LENGTH or len > MAX_LENGTH:
		return false
	for char in cleaned:
		if char not in VALID_BASES:
			return false
	return true

func clean_sequence(s: String) -> String:
	"""Strip whitespace, convert to uppercase, and filter invalid characters."""
	var result = ""
	for c in s.to_upper():
		if c in VALID_BASES:
			result += c
	return result