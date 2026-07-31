class_name NitrogenBaseDeriver
extends RefCounted

# ==========================================
# NITROGEN BASE DERIVER
# Growth Session 2 (docs/MolecularStructure_BasePairExpansion.md). Builds
# purine (adenine, guanine — fused bicyclic 6-ring+5-ring) and pyrimidine
# (cytosine, thymine — single 6-ring) topology + layout, mirroring
# ribose_deriver.gd's shape for a different molecule family.
#
# No ReactionOperator models base attachment — a base is always present,
# never modeled as attaching mid-simulation. See the addendum doc's
# decision record for the full reasoning.
#
# derive_regular_ring() is a PURE UTILITY (no tuned/behavioral value —
# straight trigonometry) extracted here rather than left duplicated in
# ribose_deriver.gd, per SKILL.md's pure-utility-vs-behavioral-constant
# extraction rule. ribose_deriver.gd's derive_ring() is now a thin wrapper
# around it.
# ==========================================

const PYRIMIDINE_RING_SUFFIXES: Array[String] = ["n1", "c2", "n3", "c4", "c5", "c6"]
const PURINE_SIX_RING_SUFFIXES: Array[String] = ["n1", "c2", "n3", "c4", "c5", "c6"]
## Walked in bond order starting adjacent to c4 and ending adjacent to c5 —
## c4/c5 themselves are the shared edge, already placed by the 6-ring.
const PURINE_FIVE_RING_REMAINING_SUFFIXES: Array[String] = ["n9", "c8", "n7"]


static func _is_purine(base_letter: String) -> bool:
	return base_letter == "A" or base_letter == "G"


# ==========================================
# TOPOLOGY — atoms + bonds, no coordinates
# ==========================================

static func build_base_seed_into(topology: MoleculeTopology, role_prefix: String, base_letter: String) -> void:
	match base_letter:
		"A": build_adenine_seed_into(topology, role_prefix)
		"G": build_guanine_seed_into(topology, role_prefix)
		"C": build_cytosine_seed_into(topology, role_prefix)
		"T": build_thymine_seed_into(topology, role_prefix)
		_:
			push_warning("NitrogenBaseDeriver.build_base_seed_into: unknown base letter '%s', defaulting to adenine" % base_letter)
			build_adenine_seed_into(topology, role_prefix)

## Glycosidic bond: purine N9 / pyrimidine N1 to the ribose's C1' — real
## Watson-Crick numbering. Must be called AFTER both the base ring atoms
## and the ribose ring atoms already exist on `topology`.
static func _attach_glycosidic_bond(topology: MoleculeTopology, role_prefix: String, attachment_suffix: String) -> void:
	var base_n_id: int = topology.find_by_role(role_prefix + attachment_suffix)
	var c1_id: int = topology.find_by_role(role_prefix + "c1_prime")
	if base_n_id != -1 and c1_id != -1:
		topology.add_bond(c1_id, base_n_id)

static func _build_pyrimidine_ring(topology: MoleculeTopology, role_prefix: String) -> Dictionary:
	var ids := {}
	ids.n1 = topology.add_atom("N", role_prefix + "n1")
	ids.c2 = topology.add_atom("C", role_prefix + "c2")
	ids.n3 = topology.add_atom("N", role_prefix + "n3")
	ids.c4 = topology.add_atom("C", role_prefix + "c4")
	ids.c5 = topology.add_atom("C", role_prefix + "c5")
	ids.c6 = topology.add_atom("C", role_prefix + "c6")
	topology.add_bond(ids.n1, ids.c2)
	topology.add_bond(ids.c2, ids.n3)
	topology.add_bond(ids.n3, ids.c4)
	topology.add_bond(ids.c4, ids.c5)
	topology.add_bond(ids.c5, ids.c6)
	topology.add_bond(ids.c6, ids.n1)
	return ids

static func build_cytosine_seed_into(topology: MoleculeTopology, role_prefix: String) -> void:
	var ring := _build_pyrimidine_ring(topology, role_prefix)
	var o2 := topology.add_atom("O", role_prefix + "o2")
	topology.add_bond(ring.c2, o2)
	var n4 := topology.add_atom("N", role_prefix + "n4")
	topology.add_bond(ring.c4, n4)
	_attach_glycosidic_bond(topology, role_prefix, "n1")

static func build_thymine_seed_into(topology: MoleculeTopology, role_prefix: String) -> void:
	var ring := _build_pyrimidine_ring(topology, role_prefix)
	var o2 := topology.add_atom("O", role_prefix + "o2")
	topology.add_bond(ring.c2, o2)
	var o4 := topology.add_atom("O", role_prefix + "o4")
	topology.add_bond(ring.c4, o4)
	var c5_methyl := topology.add_atom("C", role_prefix + "c5_methyl")
	topology.add_bond(ring.c5, c5_methyl)
	_attach_glycosidic_bond(topology, role_prefix, "n1")

static func _build_purine_rings(topology: MoleculeTopology, role_prefix: String) -> Dictionary:
	var ids := {}
	ids.n1 = topology.add_atom("N", role_prefix + "n1")
	ids.c2 = topology.add_atom("C", role_prefix + "c2")
	ids.n3 = topology.add_atom("N", role_prefix + "n3")
	ids.c4 = topology.add_atom("C", role_prefix + "c4")
	ids.c5 = topology.add_atom("C", role_prefix + "c5")
	ids.c6 = topology.add_atom("C", role_prefix + "c6")
	topology.add_bond(ids.n1, ids.c2)
	topology.add_bond(ids.c2, ids.n3)
	topology.add_bond(ids.n3, ids.c4)
	topology.add_bond(ids.c4, ids.c5)
	topology.add_bond(ids.c5, ids.c6)
	topology.add_bond(ids.c6, ids.n1)
	# Imidazole 5-ring, sharing the c4-c5 edge already placed above.
	ids.n9 = topology.add_atom("N", role_prefix + "n9")
	ids.c8 = topology.add_atom("C", role_prefix + "c8")
	ids.n7 = topology.add_atom("N", role_prefix + "n7")
	topology.add_bond(ids.c4, ids.n9)
	topology.add_bond(ids.n9, ids.c8)
	topology.add_bond(ids.c8, ids.n7)
	topology.add_bond(ids.n7, ids.c5)
	return ids

static func build_adenine_seed_into(topology: MoleculeTopology, role_prefix: String) -> void:
	var ring := _build_purine_rings(topology, role_prefix)
	var n6 := topology.add_atom("N", role_prefix + "n6")
	topology.add_bond(ring.c6, n6)
	_attach_glycosidic_bond(topology, role_prefix, "n9")

static func build_guanine_seed_into(topology: MoleculeTopology, role_prefix: String) -> void:
	var ring := _build_purine_rings(topology, role_prefix)
	var o6 := topology.add_atom("O", role_prefix + "o6")
	topology.add_bond(ring.c6, o6)
	var n2 := topology.add_atom("N", role_prefix + "n2")
	topology.add_bond(ring.c2, n2)
	_attach_glycosidic_bond(topology, role_prefix, "n9")


# ==========================================
# LAYOUT — 2D positions, local unrotated frame
# ==========================================

## Generic regular-N-gon vertex placement, centered at local origin. Pure
## utility — no tuned/behavioral value, straight trigonometry. Used for
## ribose (N=5, via ribose_deriver.gd's wrapper), pyrimidines (N=6), and
## the purine 6-ring half.
static func derive_regular_ring(topology: MoleculeTopology, role_suffixes: Array[String], role_prefix: String, bond_length: float, start_angle: float = -PI / 2.0) -> Dictionary:
	var positions: Dictionary = {}
	var n: int = role_suffixes.size()
	if n < 3:
		return positions
	var circumradius: float = bond_length / (2.0 * sin(PI / n))
	var angle_step: float = TAU / n
	for i in range(n):
		var atom_id: int = topology.find_by_role(role_prefix + role_suffixes[i])
		if atom_id == -1:
			push_warning("NitrogenBaseDeriver.derive_regular_ring: role not found (%s)" % [role_prefix + role_suffixes[i]])
			continue
		var angle: float = start_angle + i * angle_step
		positions[atom_id] = Vector2(cos(angle), sin(angle)) * circumradius
	return positions

## A second ring fused to an ALREADY-PLACED shared edge (shared_edge_a ->
## shared_edge_b), folded to the side AWAY from fold_away_from (e.g. the
## first ring's own centroid) — a shared edge alone is ambiguous about fold
## direction, and this must be deterministic per the Layout section's
## stability rule. remaining_role_suffixes must be given in bond-walk order
## starting adjacent to shared_edge_a and ending adjacent to shared_edge_b.
static func derive_fused_ring(shared_edge_a: Vector2, shared_edge_b: Vector2, remaining_role_suffixes: Array[String], topology: MoleculeTopology, role_prefix: String, fold_away_from: Vector2) -> Dictionary:
	var positions: Dictionary = {}
	var edge_vec: Vector2 = shared_edge_b - shared_edge_a
	var edge_len: float = edge_vec.length()
	if edge_len <= 0.0:
		return positions
	var n: int = remaining_role_suffixes.size() + 2
	var circumradius: float = edge_len / (2.0 * sin(PI / n))
	var apothem: float = circumradius * cos(PI / n)
	var edge_mid: Vector2 = (shared_edge_a + shared_edge_b) * 0.5
	var edge_normal: Vector2 = edge_vec.orthogonal().normalized()
	# Fold away from fold_away_from: the new ring's centre must land on the
	# OPPOSITE side of the shared edge from fold_away_from.
	if edge_normal.dot(edge_mid - fold_away_from) < 0.0:
		edge_normal = -edge_normal
	var center: Vector2 = edge_mid + edge_normal * apothem

	var start_angle: float = (shared_edge_a - center).angle()
	var target_angle: float = (shared_edge_b - center).angle()
	var step: float = TAU / n
	# shared_edge_a (e.g. c4) has exactly TWO ring-neighbors, one step away in
	# EACH rotational sense: shared_edge_b (e.g. c5, reached directly via the
	# already-existing shared-edge bond) and the first remaining atom (e.g.
	# n9, reached via the new bond being placed here). Both are legitimately
	# "one step from start_angle" — so whichever signed step lands closest to
	# target_angle is the direction that reaches shared_edge_b, and walking
	# the remaining atoms must go the OPPOSITE way (fix: was previously
	# walking the same way, which put the first remaining atom exactly on
	# top of shared_edge_b — verified via diagnosis/diag.py's coordinate
	# dump, local[n9] == local[c5] to machine precision).
	var direction: float = -1.0
	if abs(wrapf(start_angle - step - target_angle, -PI, PI)) < abs(wrapf(start_angle + step - target_angle, -PI, PI)):
		direction = 1.0

	var angle: float = start_angle
	for i in range(remaining_role_suffixes.size()):
		angle += direction * step
		var atom_id: int = topology.find_by_role(role_prefix + remaining_role_suffixes[i])
		if atom_id == -1:
			push_warning("NitrogenBaseDeriver.derive_fused_ring: role not found (%s)" % [role_prefix + remaining_role_suffixes[i]])
			continue
		positions[atom_id] = center + Vector2(cos(angle), sin(angle)) * circumradius
	return positions

## Places the base's full ring system (same local frame the ribose ring
## occupies, so a single later translation carries both into world space
## together, per the C1'-anchor fix) — rotated to face `pairing_direction`
## AND translated so its glycosidic attachment atom (N9/N1) lands exactly
## `bond_length` from `c1_position` along that direction. pairing_direction
## is caller-supplied (the renderer's job, not this file's — it's the one
## place that knows which way a given strand's residues face their pairing
## partner; this file stays strand-agnostic, matching the three-layer
## separation).
static func derive_base_layout(topology: MoleculeTopology, role_prefix: String, base_letter: String, c1_position: Vector2, pairing_direction: Vector2, bond_length: float) -> Dictionary:
	var positions: Dictionary = {}
	var is_purine: bool = _is_purine(base_letter)
	var attachment_suffix: String = "n9" if is_purine else "n1"
	var attachment_id: int = topology.find_by_role(role_prefix + attachment_suffix)
	if attachment_id == -1:
		return positions

	var local_positions: Dictionary
	if is_purine:
		local_positions = derive_regular_ring(topology, PURINE_SIX_RING_SUFFIXES, role_prefix, bond_length)
		var c4_id: int = topology.find_by_role(role_prefix + "c4")
		var c5_id: int = topology.find_by_role(role_prefix + "c5")
		if local_positions.has(c4_id) and local_positions.has(c5_id):
			var five_ring: Dictionary = derive_fused_ring(local_positions[c4_id], local_positions[c5_id], PURINE_FIVE_RING_REMAINING_SUFFIXES, topology, role_prefix, Vector2.ZERO)
			for id in five_ring:
				local_positions[id] = five_ring[id]
	else:
		local_positions = derive_regular_ring(topology, PYRIMIDINE_RING_SUFFIXES, role_prefix, bond_length)

	if not local_positions.has(attachment_id):
		return positions

	var anchor_suffix: String = pairing_anchor_suffix(base_letter)
	var anchor_id: int = topology.find_by_role(role_prefix + anchor_suffix)
	if anchor_id == -1 or not local_positions.has(anchor_id):
		return positions

	var dir: Vector2 = pairing_direction.normalized() if pairing_direction.length() > 0.0 else Vector2.DOWN

	# Rotation fix (docs/MolecularStructure_BasePairExpansion.md): this used
	# to only TRANSLATE the ring so the attachment atom (N9/N1) landed at the
	# right spot, leaving the rest of the ring — including the H-BOND ANCHOR
	# atom (N1/N3, a DIFFERENT atom than the attachment atom) — at whatever
	# position its fixed local orientation (derive_regular_ring's constant
	# start_angle = -90°) happened to produce, regardless of which way
	# pairing_direction actually points. Confirmed via diagnosis/diag.py: a
	# G/C pair's H-bond span differed ~24x (108.90 vs 4.50) purely from which
	# strand each base sat on, with identical ribose-ring math both times —
	# the ring itself was never wrong, only never rotated into place.
	#
	# Rotation-target retarget (follow-up, docs/MolecularStructure_
	# BasePairExpansion.md): aligning the C1'->attachment direction with
	# pairing_direction (the first version of this fix) made the span
	# symmetric, but a bond_length sweep (diagnosis/diag_span_breakdown.py)
	# proved no bond_length could bring the anchor pair together — because
	# the anchor (N1/N3) sits roughly 180 degrees across the ring from the
	# attachment atom (N9/N1), so pointing the attachment at the partner
	# necessarily points the anchor AWAY from it. Fixed by aligning the
	# LOCAL attachment->anchor vector with pairing_direction instead — the
	# attachment atom still lands at c1_position + dir*bond_length (its own
	# distance from C1' is unchanged), but the ring's rotation around that
	# point now carries the anchor further along pairing_direction, toward
	# the partner, rather than behind the attachment atom. Still a PROPER
	# ROTATION (Vector2.rotated(), same no-mirroring constraint as every
	# other fix this session — a reflection would silently produce the
	# wrong-handed ring).
	var local_attachment: Vector2 = local_positions[attachment_id]
	var local_anchor: Vector2 = local_positions[anchor_id]
	var local_reach: Vector2 = local_anchor - local_attachment
	var local_dir: Vector2 = local_reach.normalized() if local_reach.length() > 0.0 else Vector2.DOWN
	var rotation_angle: float = dir.angle() - local_dir.angle()
	var rotated_positions: Dictionary = {}
	for id in local_positions:
		rotated_positions[id] = local_positions[id].rotated(rotation_angle)

	var attachment_target: Vector2 = c1_position + dir * bond_length
	var translation: Vector2 = attachment_target - rotated_positions[attachment_id]
	for id in rotated_positions:
		positions[id] = rotated_positions[id] + translation

	_place_base_substituents(topology, role_prefix, base_letter, positions, bond_length)
	return positions

static func _substituent_anchor_map(base_letter: String) -> Dictionary:
	match base_letter:
		"A": return {"n6": "c6"}
		"G": return {"o6": "c6", "n2": "c2"}
		"C": return {"o2": "c2", "n4": "c4"}
		"T": return {"o2": "c2", "o4": "c4", "c5_methyl": "c5"}
	return {}

## Radially outward from the RING SYSTEM's own centroid (post-translation)
## — same "substituent hangs off the anchored ring" convention
## ribose_deriver.gd's derive_substituents() already uses.
static func _place_base_substituents(topology: MoleculeTopology, role_prefix: String, base_letter: String, positions: Dictionary, bond_length: float) -> void:
	var centroid: Vector2 = Vector2.ZERO
	var count: int = 0
	for id in positions:
		centroid += positions[id]
		count += 1
	if count > 0:
		centroid /= count

	var substituent_map: Dictionary = _substituent_anchor_map(base_letter)
	for sub_suffix in substituent_map:
		var anchor_suffix: String = substituent_map[sub_suffix]
		var sub_id: int = topology.find_by_role(role_prefix + sub_suffix)
		var anchor_id: int = topology.find_by_role(role_prefix + anchor_suffix)
		if sub_id == -1 or anchor_id == -1 or not positions.has(anchor_id):
			continue
		var outward: Vector2 = (positions[anchor_id] - centroid)
		outward = outward.normalized() if outward.length() > 0.0 else Vector2.RIGHT
		positions[sub_id] = positions[anchor_id] + outward * bond_length


# ==========================================
# HYDROGEN-BOND PAIRING ANCHOR
# ==========================================

## One named anchor atom per base for hydrogen-bond line placement (Tier 2
## per the addendum doc's decision — not atom-exact donor/acceptor pairs).
static func pairing_anchor_suffix(base_letter: String) -> String:
	match base_letter:
		"A": return "n1"
		"T": return "n3"
		"G": return "n1"
		"C": return "n3"
	return "n1"

## Single source of truth for the AT=2/CG=3 hydrogen-bond count — was
## previously duplicated as an inline literal in
## replication_manager.gd's _spawn_leading_hydrogen_bonds()/
## _spawn_lagging_hydrogen_bonds(); both now call this instead, and
## molecule_structure_renderer.gd reads it here too, so the bead-glyph and
## skeletal renderings can never silently disagree about bond count
## (the "never let two independently-tuned numbers coincidentally agree"
## trap this project has been bitten by before).
static func hydrogen_bond_count(base_type: String) -> int:
	return 3 if (base_type == "C" or base_type == "G") else 2
