class_name ReactionOperator
extends Resource

# ==========================================
# REACTION OPERATOR
# Per MolecularStructureDesign.md Open Question 5's resolution
# (MolecularStructure_OpenQuestions_Q3Q5Resolution.md): a reaction operator
# is a diff of exactly four arrays, plus a teaching-text gloss. Atom
# references inside every array MUST be role-tag Strings ("chain.o3_prime",
# "incoming.alpha_phosphate") — NEVER raw indices or ids — because topology
# is derived fresh every fold (Model B, nothing cached across steps) and an
# index-based reference would silently break the moment this same operator
# is applied against a different nucleotide's topology than the one it was
# authored against.
#
# Option A (this file + authored .tres data): static Resource data,
# Inspector-editable, no code — the correct fit for an operator with no
# conditional logic (this milestone's one operator, phosphodiester bond
# formation). Precedented by dna_sequence_resource.gd, the only other
# Resource subclass in scripts/.
#
# Option B (procedural variant, NOT built): a per-operator GDScript function
# producing the same four-array shape, held in reserve for when aconitase
# (MolecularStructureDesign.md Open Question 1, parked) forces an operator
# to choose between two topologically-identical atoms — something static
# data can't express. Not needed before that; do not build it speculatively.
#
# Consumed exclusively by MoleculeFoldEngine.apply_operator() — this file
# holds no logic of its own beyond the data shape.
# ==========================================

## Each entry: [role_tag_a: String, role_tag_b: String]. The bond between
## these two atoms is removed.
@export var bonds_broken: Array[Array] = []
## Each entry: [role_tag_a: String, role_tag_b: String]. A new bond is
## formed between these two atoms.
@export var bonds_formed: Array[Array] = []
## Role tags of whole atoms that vanish from the topology this fold (e.g.
## the leaving group's atoms).
@export var atoms_leaving: Array[String] = []
## Role tags of whole atoms that appear in the topology this fold. Empty is
## valid — this milestone's phosphodiester operator only removes atoms and
## forms one bond between two atoms already present in the seed topology.
@export var atoms_arriving: Array[String] = []
## Plain-English gloss — literally the reaction equation's teaching text,
## per the design doc's "the operator IS the pedagogy" claim.
@export_multiline var teaching_text: String = ""
