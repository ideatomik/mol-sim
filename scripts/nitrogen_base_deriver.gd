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
##
## DEMO-ONLY parameter (docs/MolecularStructure_BasePairExpansion.md,
## Bug W): `reverse`, defaulting false. When true, walks vertices with
## `angle = start_angle - i * angle_step` instead of `+` — mathematically
## a mirror reflection of the vertex walk, not a rotation (this is exactly
## the reversal `derive_ring()`'s own HARDCODED HANDEDNESS comment warns
## produces L-ribose instead of D-ribose). Defaults false everywhere, so
## every existing call site (leading, lagging, every non-demo path) is a
## provable no-op — `false` reduces to the original `angle = start_angle
## + i * angle_step` exactly, byte-identical. NOT a shipped mechanism —
## see the Bug W doc entry for the one-time visual confirmation this was
## added for, and confirm before trusting this comment that no call site
## still passes `true`.
static func derive_regular_ring(topology: MoleculeTopology, role_suffixes: Array[String], role_prefix: String, bond_length: float, start_angle: float = -PI / 2.0, reverse: bool = false) -> Dictionary:
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
		var angle: float = start_angle - i * angle_step if reverse else start_angle + i * angle_step
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

## Number of candidate rotation angles tried by the clearance-maximizing
## search in derive_base_layout() (below), across the FULL search window
## (BASE_ROTATION_SEARCH_WINDOW_DEG below) — 5-degree resolution at the
## window's original 360-degree span. Cheap: skeletal mode only ever
## renders a handful of residues at once (deep-zoom cull window, confirmed
## ~3-4 nucleotides — see molecule_structure_renderer.gd's culling note),
## so a few thousand distance checks per residue per frame is negligible.
const BASE_ROTATION_SEARCH_STEPS: int = 72

## Half-width of the rotation search window, centered on the angle that
## points the H-BOND ANCHOR atom exactly at pairing_direction (or the
## unpaired fallback direction) — NOT a full 360-degree sweep.
##
## History: the FIRST version of this search pinned the ANCHOR atom at its
## exact target and rotated the whole ring FREELY (360 degrees) to
## maximize clearance from the ribose's own substituent chain — this
## stretched the ATTACHMENT atom's real covalent bond to C1' (Bug F
## correction, see derive_base_layout()'s comments). The FIX for that —
## pinning the ATTACHMENT instead and letting the ANCHOR float freely —
## introduced a WORSE regression: with nothing pinning the anchor to a
## consistent position, a paired residue's own search (which only knows
## about ITS OWN chain, not its partner's) could land the anchor anywhere
## in a full circle, independently of where the PARTNER residue's own
## search left ITS anchor. Confirmed via a live screenshot AND a live F9
## dump: the H-bond anchor-to-anchor span, previously a stable 81-84,
## collapsed to 6.4-11.25 — both strands' entire base rings landing almost
## on top of each other, non-monotonically unstable across window sizes
## (one sweep example: 12.5 -> 16.6 -> 7.5 -> 6.3; another: 12.5 -> 13.2 ->
## 19.5 -> 19.5 -> 1.1). Reverted to pinning the ANCHOR (restores the
## exactly-correct, provably-stable H-bond span at every window size, by
## construction — translation is always solved so the anchor lands exactly
## on anchor_target regardless of which angle within the window wins) and
## moved the window constraint onto the ATTACHMENT's stretch instead: it's
## now BOUNDED rather than eliminated, a smaller but real regression
## accepted deliberately since a wrong/unstable H-bond span is far more
## visible than a somewhat-stretched invisible glycosidic bond length.
## Swept clearance-vs-stretch (diagnosis/) at increasing window sizes: 0
## degrees reproduces the original Bug D overlap (worst-case clearance
## 0.56, zero stretch); 15 degrees already escapes the worst overlap
## (0.56 -> 3.31+) for a modest, bounded stretch (+1.6 to +3.7, i.e.
## bond_length effectively 10.8 -> ~12.4-14.5); stretch grows much faster
## than clearance improves past that, especially for purines (+19.7 at 45
## degrees, +43.0 at 90). 15 chosen as the point that clears the worst
## overlap for the smallest acceptable stretch.
const BASE_ROTATION_SEARCH_WINDOW_DEG: float = 15.0

## Places the base's full ring system (same local frame the ribose ring
## occupies, so a single later translation carries both into world space
## together, per the C1'-anchor fix). The H-bond ANCHOR atom (N1/N3) lands
## at a fixed target derived from `pairing_direction`/`bond_length` (see
## below) — everything else (attachment atom, rest of the ring) rotates
## freely around that fixed anchor point to maximize clearance from
## `avoid_points` (the ribose's own substituent chain, in the same local
## frame — caller-supplied, since this file stays strand/ribose-agnostic).
## pairing_direction is caller-supplied (the renderer's job, not this
## file's — it's the one place that knows which way a given strand's
## residues face their pairing partner; this file stays strand-agnostic,
## matching the three-layer separation).
static func derive_base_layout(topology: MoleculeTopology, role_prefix: String, base_letter: String, c1_position: Vector2, pairing_direction: Vector2, bond_length: float, avoid_points: Array = []) -> Dictionary:
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

	# Fallback-direction fix (docs/MolecularStructure_BasePairExpansion.md,
	# Bug F follow-up): an UNPAIRED residue (no real partner yet — e.g. a
	# template residue freshly split off the helicase, still waiting for
	# the other strand's polymerase to catch up) has no H-bond constraint
	# at all, so a fixed Vector2.DOWN fallback here was completely
	# arbitrary. For sign=+1 strands that arbitrary choice happened to
	# leave the clearance search plenty of room (worst case 46.4 —
	# comfortably clear); for sign=-1 it didn't (worst case 4.8 for T/C —
	# a real, visible ribose-through-base crossing, confirmed via a live
	# screenshot of an unpaired template_bottom residue just past the
	# helicase). Since there's no real constraint to violate when unpaired,
	# the fallback direction can just as easily point AWAY from the
	# ribose's own substituent chain instead — verified via diagnosis/
	# diag_unpaired_case.py to raise the sign=-1 worst case from 4.8 to
	# 45.9, comfortably clear, before the rotation search even runs.
	var dir: Vector2
	if pairing_direction.length() > 0.0:
		dir = pairing_direction.normalized()
	elif not avoid_points.is_empty():
		var chain_centroid: Vector2 = Vector2.ZERO
		for p in avoid_points:
			chain_centroid += p
		chain_centroid /= avoid_points.size()
		dir = (-chain_centroid).normalized() if chain_centroid.length() > 0.0 else Vector2.DOWN
	else:
		dir = Vector2.DOWN

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
	# LOCAL attachment->anchor vector with pairing_direction instead.
	#
	# Anchor-fixed clearance search (follow-up, docs/MolecularStructure_
	# BasePairExpansion.md, Bug D "ribose sits on its own base" follow-up):
	# the H-bond span (12.5484, verified consistent across all 3 real
	# pairing relationships once Bug E's sequence fix landed) is exactly
	# right and must not move again. But the ribose ring's own substituent
	# chain (O3'/C5'/O5'/alpha-phosphate — RiboseDeriver.derive_
	# substituents(), 3 bond_lengths long) was found, via the F9 geometry
	# diagnostic, to nearly touch the base in template-template pairing
	# (as close as 0.56 units) — a real visible overlap the old
	# attachment->anchor-aligned rotation had no way to avoid, since it had
	# no free parameter left once pairing_direction fixed the rotation.
	# Both RiboseDeriver's ring rotation (confirmed-correct antiparallel
	# fix) and its substituent chain (Bug B's inter-residue backbone bonds
	# depend on its exact placement) are protected — neither can move to
	# fix this — so the fix reformulates this function to fix the ANCHOR's
	# target position directly (algebraically identical to what the old
	# formula already produced — verified bit-for-bit via diagnosis/
	# diag_anchor_preserving.py before shipping, not assumed), freeing up
	# the rotation angle as a genuine free parameter, then picks whichever
	# angle maximizes the ring's minimum distance from avoid_points. A
	# single-vector heuristic (rotate so attachment->anchor points opposite
	# avoid_points' own direction) was tried first and recovered most of
	# the gap for one strand sign but far from it for the other (purine
	# fused-ring bulk isn't captured by one vector) — so this is a genuine
	# search, not a disguised heuristic. Still real derived geometry (a
	# maximization over the one legitimately free rotation DOF), not a
	# tuned constant — same "derive, don't hardcode" principle as every
	# other fix this session, expressed as a search instead of closed-form
	# trig because the shape genuinely doesn't reduce to one.
	# Anchor-pinned, window-bounded search (re-correction, docs/
	# MolecularStructure_BasePairExpansion.md — see
	# BASE_ROTATION_SEARCH_WINDOW_DEG's own comment above for the full
	# history of why this went attachment-pinned-unbounded then back to
	# anchor-pinned-bounded). Pinning the ANCHOR means `translation` is
	# always solved so the anchor lands exactly on `anchor_target`
	# regardless of which angle the search picks — the H-bond span this
	# produces is therefore exactly as stable/correct as it was before any
	# search existed at all, for every window size, every base letter,
	# every strand sign. The window only bounds how far the ATTACHMENT
	# atom (and therefore the real covalent glycosidic bond to C1') is
	# allowed to drift from `bond_length` while the search looks for
	# clearance from the ribose's own substituent chain.
	var local_attachment: Vector2 = local_positions[attachment_id]
	var local_anchor: Vector2 = local_positions[anchor_id]
	var local_reach: Vector2 = local_anchor - local_attachment
	var reach_length: float = local_reach.length()
	var anchor_target: Vector2 = c1_position + dir * (bond_length + reach_length)

	# The angle that points the anchor exactly at `dir` — also the CENTER
	# of the clearance search's window (see BASE_ROTATION_SEARCH_WINDOW_DEG),
	# not just the one candidate it used to be.
	var local_dir: Vector2 = local_reach.normalized() if reach_length > 0.0 else Vector2.DOWN
	var aligned_angle: float = dir.angle() - local_dir.angle()

	var best_angle: float
	if avoid_points.is_empty():
		# No chain data supplied (e.g. a caller that hasn't been updated) —
		# fall back to the previous behavior (align attachment->anchor with
		# pairing_direction) rather than searching over nothing.
		best_angle = aligned_angle
	else:
		var window: float = deg_to_rad(BASE_ROTATION_SEARCH_WINDOW_DEG)
		var best_clearance: float = -INF
		for i in range(BASE_ROTATION_SEARCH_STEPS + 1):
			var angle: float = aligned_angle - window + (2.0 * window) * float(i) / float(BASE_ROTATION_SEARCH_STEPS)
			var candidate_anchor: Vector2 = local_anchor.rotated(angle)
			var candidate_translation: Vector2 = anchor_target - candidate_anchor
			var clearance: float = INF
			for id in local_positions:
				var world: Vector2 = local_positions[id].rotated(angle) + candidate_translation
				for avoid in avoid_points:
					clearance = min(clearance, world.distance_to(avoid))
			if clearance > best_clearance:
				best_clearance = clearance
				best_angle = angle

	var rotated_positions: Dictionary = {}
	for id in local_positions:
		rotated_positions[id] = local_positions[id].rotated(best_angle)
	var translation: Vector2 = anchor_target - rotated_positions[anchor_id]
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
