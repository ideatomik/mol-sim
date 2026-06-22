class_name DnaSequenceResource
extends Resource

# ==========================================
# DNA SEQUENCE RESOURCE
# Single source of truth for the template strand's base sequence.
# Decoupled from any simulation script so the UI, template strand,
# new strand, and any future system can all read from the same object.
#
# Usage:
#   var dna_sequence := DnaSequenceResource.new()
#   dna_sequence.randomize_sequence(num_nucleotide_slots)
#   var base = dna_sequence.sequence[i]          # "A", "T", "C", or "G"
#   var comp = dna_sequence.get_complement(i)    # paired base on new strand
#   dna_sequence.set_from_string("ATCGATCG")    # UI/manual assignment
# ==========================================

const VALID_BASES: Array[String] = ["A", "T", "C", "G"]

const COMPLEMENTS: Dictionary = {
	"A": "T",
	"T": "A",
	"C": "G",
	"G": "C"
}

## The template strand sequence. Each entry is one of "A", "T", "C", "G".
## Index 0 = leftmost nucleotide slot (slot 0 in rail_train_test.gd).
@export var sequence: Array[String] = []

## Fill the sequence with random bases of the given length.
## Called during simulation setup when no explicit sequence is provided.
func randomize_sequence(length: int) -> void:
	sequence.clear()
	for i in range(length):
		sequence.append(VALID_BASES[randi() % VALID_BASES.size()])

## Return the Watson-Crick complement of the base at the given index.
## Used by the new synthesized strand to determine its base type.
func get_complement(index: int) -> String:
	if index < 0 or index >= sequence.size():
		push_warning("DnaSequenceResource.get_complement: index %d out of range (size=%d)" % [index, sequence.size()])
		return ""
	return COMPLEMENTS.get(sequence[index], "")

## Parse a plain string into the sequence array, ignoring any character
## that isn't a valid base. Case-insensitive. Extra characters are skipped
## silently so a user can paste a sequence with spaces or numbers and it
## still works. The resulting sequence is truncated or padded with random
## bases to match target_length if provided (pass -1 to skip padding).
func set_from_string(s: String, target_length: int = -1) -> void:
	sequence.clear()
	for c in s.to_upper():
		if c in VALID_BASES:
			sequence.append(c)
	if target_length > 0:
		# Truncate if too long.
		while sequence.size() > target_length:
			sequence.pop_back()
		# Pad with random bases if too short.
		while sequence.size() < target_length:
			sequence.append(VALID_BASES[randi() % VALID_BASES.size()])

## Return the sequence as a plain string, e.g. "ATCGATCG".
## Useful for displaying in a UI text field or saving to disk.
func to_string() -> String:
	return "".join(sequence)
