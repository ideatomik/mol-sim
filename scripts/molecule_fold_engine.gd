class_name MoleculeFoldEngine
extends RefCounted

# ==========================================
# MOLECULE FOLD ENGINE
# The regent pattern applied to chemistry (MolecularStructureDesign.md's
# "derived, not stored" / Model B decision):
#
#   molecule_at(step_n) = fold(reactions[0..n], seed)
#
# fold() replays operators[0..step_n] over a fresh duplicate of `seed` EVERY
# call — never patches an existing topology incrementally, never caches
# across steps internally. Callers (molecule_structure_renderer.gd) may
# cache the RESULT keyed off live synthesis state, but this engine itself
# has no memory. This is what makes an arbitrary scrub target reproducible
# with no replay-order dependency, the same invariant every other
# scrub-driven system in this project already holds.
#
# One shared function, not per-operator code — any operator's four-array
# diff is consumed identically here, regardless of which molecule/reaction
# it belongs to.
# ==========================================

## Applies one operator's four-array diff to `topology`, resolving every
## role tag against the atoms actually present. Never mutates `topology` —
## returns a new MoleculeTopology built from a duplicate.
static func apply_operator(topology: MoleculeTopology, op: ReactionOperator) -> MoleculeTopology:
	var result: MoleculeTopology = topology.duplicate_topology()

	for pair in op.bonds_broken:
		var a: int = result.find_by_role(pair[0])
		var b: int = result.find_by_role(pair[1])
		if a == -1 or b == -1:
			push_warning("MoleculeFoldEngine: bonds_broken role tag not found (%s, %s)" % [pair[0], pair[1]])
			continue
		for i in range(result.bonds.size() - 1, -1, -1):
			var bond: Dictionary = result.bonds[i]
			if (bond.a == a and bond.b == b) or (bond.a == b and bond.b == a):
				result.bonds.remove_at(i)

	var leaving_ids: Array[int] = []
	for role in op.atoms_leaving:
		var id: int = result.find_by_role(role)
		if id == -1:
			push_warning("MoleculeFoldEngine: atoms_leaving role tag not found (%s)" % role)
			continue
		leaving_ids.append(id)
	if not leaving_ids.is_empty():
		for i in range(result.atoms.size() - 1, -1, -1):
			if result.atoms[i].id in leaving_ids:
				result.atoms.remove_at(i)
		for i in range(result.bonds.size() - 1, -1, -1):
			var bond: Dictionary = result.bonds[i]
			if bond.a in leaving_ids or bond.b in leaving_ids:
				result.bonds.remove_at(i)

	# atoms_arriving intentionally has no handling here beyond the role-tag
	# lookup contract implying the atom must already exist by the time
	# bonds_formed resolves it — this milestone's one operator never
	# populates atoms_arriving (nothing new is created, only removed), so
	# there is no real "spawn a new atom" case to exercise yet. A future
	# operator that needs to introduce a genuinely new atom (e.g. a
	# transferred hydride in Krebs) will need this engine extended with an
	# explicit atom-creation step — flagged here rather than silently
	# assumed to already work.
	if not op.atoms_arriving.is_empty():
		push_warning("MoleculeFoldEngine: atoms_arriving is non-empty but this engine has no atom-creation path yet — extend before using an operator that populates it")

	for pair in op.bonds_formed:
		var a: int = result.find_by_role(pair[0])
		var b: int = result.find_by_role(pair[1])
		if a == -1 or b == -1:
			push_warning("MoleculeFoldEngine: bonds_formed role tag not found (%s, %s)" % [pair[0], pair[1]])
			continue
		result.add_bond(a, b)

	return result

## Replays operators[0..step_n] (inclusive) over a fresh duplicate of `seed`.
## step_n = -1 returns the seed itself, unmodified.
static func fold(seed: MoleculeTopology, operators: Array[ReactionOperator], step_n: int) -> MoleculeTopology:
	var current: MoleculeTopology = seed.duplicate_topology()
	var last_step: int = min(step_n, operators.size() - 1)
	for i in range(last_step + 1):
		current = apply_operator(current, operators[i])
	return current
