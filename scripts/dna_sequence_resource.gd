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
const MAX_LENGTH: int = 57

# ---------- PRESETS ----------
const PRESETS: Dictionary = {
	"Aleatória": "",  # Special case: generates random sequence
	"Telômeros": "TTAGGGTTAGGGTTAGGGTTAGGG",
	"Promotores": "TATAAAATATAAAATATAAA",
	"Rica em C-G": "GCGCCGCCGCCGCCGCCGCCGCCGC",
	"Rica em A-T": "ATATATATATATATATATATATATAT"
}

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

func to_string() -> String:
	return "".join(sequence)

# ---------- PRESET METHODS ----------

func load_preset(preset_name: String) -> String:
	"""Load a preset by name. Returns the preset string (or empty if not found)."""
	if preset_name == "Aleatória":
		randomize_sequence()
		return to_string()

	var preset_string = PRESETS.get(preset_name, "")
	if preset_string.is_empty():
		return ""

	# Load the preset into the sequence
	set_from_string(preset_string)
	return to_string()

func get_preset_names() -> Array[String]:
	"""Return a list of all preset names (for the UI dropdown)."""
	var names: Array[String] = []
	for key in PRESETS.keys():
		names.append(key)
	return names

func get_preset_string(preset_name: String) -> String:
	"""Get the raw string for a preset (without loading it into the sequence)."""
	if preset_name == "Aleatória":
		var temp_seq = DnaSequenceResource.new()
		temp_seq.randomize_sequence()
		return temp_seq.to_string()
	return PRESETS.get(preset_name, "")

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
