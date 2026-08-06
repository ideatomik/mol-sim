class_name MoleculeTopology
extends RefCounted

# ==========================================
# MOLECULE TOPOLOGY
# Per MolecularStructureDesign.md's three-layer model: this is the Topology
# layer only. Atoms + bonds + identity. NO coordinates, ever — that's the
# Layout layer's job (ribose_deriver.gd), kept deliberately separate.
#
# Instances are produced by MoleculeFoldEngine.fold() and never mutated
# after construction — see that file's header for why (scrub-safety: a
# topology must be safely re-derivable from scratch on every fold call).
# ==========================================

var _next_id: int = 0

## {id: int, element: String, formal_charge: int, role: String}
var atoms: Array[Dictionary] = []
## {a: int, b: int, order: int} — atom ids, never coordinates
var bonds: Array[Dictionary] = []

func add_atom(element: String, role: String, formal_charge: int = 0) -> int:
	var id: int = _next_id
	_next_id += 1
	atoms.append({id = id, element = element, formal_charge = formal_charge, role = role})
	return id

func add_bond(a: int, b: int, order: int = 1) -> void:
	bonds.append({a = a, b = b, order = order})

## Overrides an existing bond's order after construction — needed when a
## shared ring-building helper (e.g. nitrogen_base_deriver.gd's
## _build_pyrimidine_ring()/_build_purine_rings(), reused across multiple
## bases with different Kekulé double-bond placements) can't hardcode a
## single order for a bond it adds generically. Still a construction-time
## primitive alongside add_bond()/add_atom() — called only while a
## *_seed_into() function is still building its own topology, never on a
## topology already handed off by MoleculeFoldEngine.fold() (see this
## file's header on the never-mutated-after-construction contract).
func set_bond_order(a: int, b: int, order: int) -> void:
	for bond in bonds:
		if (bond.a == a and bond.b == b) or (bond.a == b and bond.b == a):
			bond.order = order
			return

## Role tags are the ONLY way operators reference atoms (never raw ids/
## indices — see reaction_operator.gd's header for why). Linear scan is
## fine at this scale (~30 atoms per molecule, per the design doc's own
## cast-size estimate).
func find_by_role(role: String) -> int:
	for atom in atoms:
		if atom.role == role:
			return atom.id
	return -1

func atoms_with_role_prefix(prefix: String) -> Array[int]:
	var result: Array[int] = []
	for atom in atoms:
		if atom.role.begins_with(prefix):
			result.append(atom.id)
	return result

func get_atom(id: int) -> Dictionary:
	for atom in atoms:
		if atom.id == id:
			return atom
	return {}

## Deep-ish copy — atoms/bonds are Dictionaries, duplicated per-entry so the
## copy shares no mutable state with the original. Used by
## MoleculeFoldEngine.apply_operator() so folding never mutates its input.
func duplicate_topology() -> MoleculeTopology:
	var copy := MoleculeTopology.new()
	copy._next_id = _next_id
	for atom in atoms:
		copy.atoms.append(atom.duplicate())
	for bond in bonds:
		copy.bonds.append(bond.duplicate())
	return copy
