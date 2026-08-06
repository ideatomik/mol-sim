class_name RiboseDeriver
extends RefCounted

# ==========================================
# RIBOSE DERIVER
# Per MolecularStructureDesign.md Open Question 2's resolution: canonical
# ring vertex positions are DERIVED from idealized bond geometry, never
# hand-authored. This file is both the Topology-layer seed builder (a
# single incorporated-nucleotide's atoms/bonds — ribose + triphosphate) AND
# the Layout-layer deriver (ring/substituent 2D positions) for that same
# molecule. Kept in one file because both are intrinsically about ribose's
# own structure, not generic infrastructure — MoleculeTopology/
# MoleculeFoldEngine stay molecule-agnostic; this file is the one place
# that actually knows what a nucleotide's sugar-phosphate backbone is made
# of.
#
# GROWTH-PHASE NOTE (divergence from the worked example in
# MolecularStructure_OpenQuestions_Q3Q5Resolution.md, recorded rather than
# silently corrected): the design doc's worked example's atoms_leaving used
# `[...]` shorthand for "pyrophosphate." Real inorganic pyrophosphate
# (P2O7) is 2 phosphorus + 7 oxygen atoms — beta-phosphate, gamma-phosphate,
# beta's 2 non-bridging oxygens, the alpha<->beta AND beta<->gamma bridging
# oxygens, and gamma's 3 terminal oxygens. The seed topology and the
# authored operator (resources/phosphodiester_bond_formation.tres) are
# built to that full 9-atom count, not the shorthand's implied smaller set.
# See molecule_fold_engine.gd's CQA note on verifying this directly.
# ==========================================

const TETRAHEDRAL_ANGLE_DEG: float = 109.5
const RING_ATOM_COUNT: int = 5
## Fixed chemical walk order — see derive_ring()'s handedness note below.
const RING_ROLE_SUFFIXES: Array[String] = ["c1_prime", "c2_prime", "c3_prime", "c4_prime", "o4_prime"]

## Keeps bulge_vs_pairing_dot comfortably negative (~-0.087) instead of
## landing exactly on the 0.0 floating-point knife-edge -- confirmed live
## that all three sampled fixtures saturate this clamp exactly, so this
## margin is load-bearing, not a rare-case safeguard. Mirrors
## diagnosis/diag_chain_ring_clearance_fix.py's BULGE_DOT_MARGIN_DEG.
const BULGE_DOT_MARGIN_DEG: float = 5.0

## No overlap between two full-radius atom circles -- the real invariant
## behind the collision-clearance target. The actual threshold is derived
## from the real molecular_atom_radius (passed through from the caller's
## `tm`, the same pattern bond_length already uses) rather than hardcoded,
## after live testing found the old flat 12.0 was silently based on
## theme_manager.gd's SCRIPT DEFAULT molecular_atom_radius (6.0) while the
## real scene (scenes/simulation.tscn) overrides it to 4.0 -- a real
## mismatch that made Tier 2 target 50% more clearance than actually
## needed.
const COLLISION_CLEARANCE_RATIO: float = 2.0

## Bug W (docs/MolecularStructure_BasePairExpansion.md) —
## resolve_self_paired_ring_rotation()'s search. Unlike NitrogenBaseDeriver's
## BASE_ROTATION_SEARCH_WINDOW_DEG (a NARROW window bounding how far an
## already-good angle is allowed to drift, to cap real bond stretch), this
## search has no "already good" starting angle to stay near — the set of
## angles satisfying the bulge_vs_pairing_dot < 0 constraint forms an arc
## roughly 180 degrees wide, roughly centered on the angle directly
## OPPOSITE wherever the ring naturally starts. A narrow window copied from
## the base search would frequently never reach negative territory at all.
## Sweeps the FULL 360 degrees instead — cheap regardless, same reasoning
## Builds the seed topology for ONE nucleotide being incorporated into the
## strand: a minimal single-atom "chain.o3_prime" stub (the growing chain's
## existing terminal 3'-oxygen — the previous residue's own ring is
## rendered as its own independent unit elsewhere, so only the one atom it
## contributes to THIS reaction needs to exist here) plus the full
## "incoming."-prefixed ribose + triphosphate + base topology.
## `base_letter` (A/T/C/G) selects the nitrogenous base attached at C1' —
## see NitrogenBaseDeriver.build_base_seed_into(). No ReactionOperator
## models base attachment (see docs/MolecularStructure_BasePairExpansion.md's
## decision record): the base is always present, not a simulated reaction
## step, so it's built directly into the seed rather than via a fold.
## Fold this seed with the phosphodiester operator (step_n = 0) to get the
## post-bond-formation topology actually rendered for a synthesized base;
## template-strand residues use step_n = -1 (the seed itself, unfolded —
## template nucleotides are never a party to that reaction).
static func build_incoming_nucleotide_seed(role_prefix: String = "incoming.", base_letter: String = "A") -> MoleculeTopology:
	var t := MoleculeTopology.new()

	var chain_o3 := t.add_atom("O", "chain.o3_prime")

	var c1 := t.add_atom("C", role_prefix + "c1_prime")
	var c2 := t.add_atom("C", role_prefix + "c2_prime")
	var c3 := t.add_atom("C", role_prefix + "c3_prime")
	var c4 := t.add_atom("C", role_prefix + "c4_prime")
	var o4 := t.add_atom("O", role_prefix + "o4_prime")
	t.add_bond(c1, c2)
	t.add_bond(c2, c3)
	t.add_bond(c3, c4)
	t.add_bond(c4, o4)
	t.add_bond(o4, c1)

	NitrogenBaseDeriver.build_base_seed_into(t, role_prefix, base_letter)

	var o3 := t.add_atom("O", role_prefix + "o3_prime")
	t.add_bond(c3, o3)
	var c5 := t.add_atom("C", role_prefix + "c5_prime")
	t.add_bond(c4, c5)
	var o5 := t.add_atom("O", role_prefix + "o5_prime")
	t.add_bond(c5, o5)

	var alpha_p := t.add_atom("P", role_prefix + "alpha_phosphate")
	t.add_bond(o5, alpha_p)
	var alpha_o1 := t.add_atom("O", role_prefix + "alpha_O1")
	var alpha_o2 := t.add_atom("O", role_prefix + "alpha_O2")
	# One P=O double bond per phosphate (bond-thickness design pass) —
	# alpha_O1/alpha_O2 are chemically equivalent non-bridging oxygens
	# (resonance-delocalized in reality); picking alpha_O1 is standard
	# skeletal-diagram convention, not an approximation of something more
	# "correct" than picking alpha_O2 instead.
	t.add_bond(alpha_p, alpha_o1, 2)
	t.add_bond(alpha_p, alpha_o2)
	var alpha_beta_bridge := t.add_atom("O", role_prefix + "alpha_beta_bridge_O")
	t.add_bond(alpha_p, alpha_beta_bridge)

	var beta_p := t.add_atom("P", role_prefix + "beta_phosphate")
	t.add_bond(alpha_beta_bridge, beta_p)
	var beta_o1 := t.add_atom("O", role_prefix + "beta_O1")
	var beta_o2 := t.add_atom("O", role_prefix + "beta_O2")
	t.add_bond(beta_p, beta_o1)
	t.add_bond(beta_p, beta_o2)
	var beta_gamma_bridge := t.add_atom("O", role_prefix + "beta_gamma_bridge_O")
	t.add_bond(beta_p, beta_gamma_bridge)

	var gamma_p := t.add_atom("P", role_prefix + "gamma_phosphate")
	t.add_bond(beta_gamma_bridge, gamma_p)
	var gamma_o1 := t.add_atom("O", role_prefix + "gamma_O1")
	var gamma_o2 := t.add_atom("O", role_prefix + "gamma_O2")
	var gamma_o3 := t.add_atom("O", role_prefix + "gamma_O3")
	t.add_bond(gamma_p, gamma_o1)
	t.add_bond(gamma_p, gamma_o2)
	t.add_bond(gamma_p, gamma_o3)

	return t

## Ring vertex positions in a local, unrotated, unscaled frame (ring
## centroid at origin) — the Layout layer. Thin wrapper over
## NitrogenBaseDeriver.derive_regular_ring() (extracted as a shared pure
## utility in Growth Session 2 — see docs/MolecularStructure_BasePairExpansion.md):
## placed as a regular pentagon (circumradius derived from bond_length)
## rather than walked edge-by-edge with a fixed turn angle, since an
## edge-walk over 5 vertices does not close exactly — undermining the
## "stability, not just determinism" requirement (MolecularStructureDesign.md's
## Layout section). A regular pentagon closes by construction.
## TETRAHEDRAL_ANGLE_DEG is kept as a named constant for documentation/
## future reference even though the pentagon placement itself doesn't
## consume it directly.
##
## HARDCODED HANDEDNESS (MolecularStructureDesign.md Open Question 3's
## milestone-slice decision): walking RING_ROLE_SUFFIXES in INCREASING
## angle (derive_regular_ring()'s default start_angle/direction) is the one
## fixed convention that produces D-ribose. Not a parameter, deliberately —
## see this file's header and the design doc's Open Questions section.
## Reversing the walk direction would produce L-ribose instead; do not add
## a flag here to "support" that without promoting handedness to real
## topology data first, per the design doc's explicit caution.
##
## `reverse` (default false) is the one exception, and only in the sense
## of a DEMO, not "support" — see derive_regular_ring()'s own comment and
## docs/MolecularStructure_BasePairExpansion.md's Bug W entry for the
## one-time L-ribose visual confirmation this exists for. Defaults false,
## so this wrapper is a provable no-op for every call site that doesn't
## pass it explicitly. Confirm no shipped call site passes true.
static func derive_ring(topology: MoleculeTopology, role_prefix: String, bond_length: float, reverse: bool = false) -> Dictionary:
	return NitrogenBaseDeriver.derive_regular_ring(topology, RING_ROLE_SUFFIXES, role_prefix, bond_length, -PI / 2.0, reverse)

## Substituent positions (5'-CH2-phosphate chain's first atom, 3'-OH),
## merged into the same local frame as derive_ring()'s output — the
## backbone (ring) stays anchored; substituents hang off it at derived
## angles, per the Layout section's stability rule.
##
## Real same-strand-neighbor direction (supersedes Bug J/L,
## docs/MolecularStructureDesign.md's Layout rule + Open Question 10,
## docs/MolecularStructure_BasePairExpansion.md): C5' (via O5'/alpha-
## phosphate) and O3' are governed by two INDEPENDENT real bond angles in
## actual deoxyribose (Gelbin et al. 1996 — C5'-C4'-C3' averages 114.7°,
## C4'-C3'-O3' averages 110.3°, two separately measured quantities) and
## point at DIFFERENT real neighbors: C5' bonds toward the previous
## residue on the SAME strand (this residue's own alpha-phosphate bonds
## the more-5' neighbor's O3'); O3' bonds toward the next residue on the
## SAME strand. Neither has anything to do with which base is paired
## across the helix. `toward_previous`/`toward_next` are real, world-space
## vectors the caller computes from actual neighbor positions (same
## established pattern as the old `pairing_direction` parameter — this
## file stays strand-agnostic, the renderer owns strand/slot identity).
## Left at the default zero vector for either (no such neighbor — e.g. a
## terminal residue, or an unpaired/uninitialized caller): if the OTHER
## side has a real neighbor, falls back to its negation (continue in a
## straight line along the strand's own real local direction) rather than
## the ring's own raw vertex direction — a strand boundary residue (the
## newest nucleotide next to the polymerase, or the oldest next to the
## primer) still has ONE real same-strand neighbor, and consecutive
## nucleotides run essentially straight, so this is a real, grounded
## direction, not an invented one (same "derive from whatever real data
## IS available" principle as the Bug F unpaired-residue fallback).
## Confirmed via two live screenshots (docs/MolecularStructure_
## BasePairExpansion.md) that the OLD single-neighbor-missing behavior —
## falling straight to c3_pos.normalized()/c4_pos.normalized(), the ring's
## own local-frame vertex direction — reproduces exactly the same
## "reaches mostly vertically instead of along the strand" problem the
## original same-strand-neighbor-direction fix (this file's header
## comment above) was written to eliminate for the non-terminal case; it
## was simply never carried through to the boundary-residue fallback.
## Only when BOTH sides are missing (a fully isolated residue — should not
## occur in practice) does this still fall back to the ring's own raw
## vertex direction, the original fallback shape.
static func derive_substituents(topology: MoleculeTopology, role_prefix: String, ring_positions: Dictionary, bond_length: float, toward_next: Vector2 = Vector2.ZERO, toward_previous: Vector2 = Vector2.ZERO) -> Dictionary:
	var positions: Dictionary = {}

	if toward_next.length() <= 0.0 and toward_previous.length() > 0.0:
		toward_next = -toward_previous
	elif toward_previous.length() <= 0.0 and toward_next.length() > 0.0:
		toward_previous = -toward_next

	var c3_id: int = topology.find_by_role(role_prefix + "c3_prime")
	var o3_id: int = topology.find_by_role(role_prefix + "o3_prime")
	if c3_id != -1 and o3_id != -1 and ring_positions.has(c3_id):
		var c3_pos: Vector2 = ring_positions[c3_id]
		var outward: Vector2 = toward_next.normalized() if toward_next.length() > 0.0 else c3_pos.normalized()
		positions[o3_id] = c3_pos + outward * bond_length

	var c4_id: int = topology.find_by_role(role_prefix + "c4_prime")
	var c5_id: int = topology.find_by_role(role_prefix + "c5_prime")
	if c4_id != -1 and c5_id != -1 and ring_positions.has(c4_id):
		var c4_pos: Vector2 = ring_positions[c4_id]
		var outward: Vector2 = toward_previous.normalized() if toward_previous.length() > 0.0 else c4_pos.normalized()
		var c5_pos: Vector2 = c4_pos + outward * bond_length
		positions[c5_id] = c5_pos

		var o5_id: int = topology.find_by_role(role_prefix + "o5_prime")
		if o5_id != -1:
			var o5_pos: Vector2 = c5_pos + outward * bond_length
			positions[o5_id] = o5_pos

			# Alpha-phosphate is the one phosphate group that SURVIVES the
			# phosphodiester operator's fold (beta/gamma leave as
			# pyrophosphate — see build_incoming_nucleotide_seed()'s
			# header). Placed here unconditionally rather than only when
			# absent-after-fold, since a pre-fold topology harmlessly gets
			# extra position entries for atoms that are about to be
			# removed anyway — the renderer only ever draws what
			# find_by_role() can still resolve.
			var alpha_id: int = topology.find_by_role(role_prefix + "alpha_phosphate")
			if alpha_id != -1:
				var alpha_pos: Vector2 = o5_pos + outward * bond_length
				positions[alpha_id] = alpha_pos
				var alpha_o1_id: int = topology.find_by_role(role_prefix + "alpha_O1")
				var alpha_o2_id: int = topology.find_by_role(role_prefix + "alpha_O2")
				var perp: Vector2 = outward.orthogonal()
				if alpha_o1_id != -1:
					positions[alpha_o1_id] = alpha_pos + (outward + perp).normalized() * bond_length
				if alpha_o2_id != -1:
					positions[alpha_o2_id] = alpha_pos + (outward - perp).normalized() * bond_length

	return positions

## Rotates every position in `local_positions` by 180 degrees around `pivot`
## when `direction_sign` is negative — identity otherwise. This is a PROPER
## ROTATION (`new = 2*pivot - old`, negating both components relative to
## the pivot), never a mirror/reflection. A rotation preserves chirality in
## 2D; a mirror would invert it — silently flipping the ring to the wrong
## enantiomer on screen while visually "fixing" the overlap, a correctness
## bug masquerading as a layout fix. See
## docs/Handout_AntiparallelStrandOrientation.md.
##
## Strand-agnostic by design — this file has no concept of "leading" vs.
## "template_top," only a caller-supplied sign, matching the same
## separation pairing_direction already established (the renderer owns
## strand identity; this file owns geometry). `pivot` is expected to be the
## same anchor point (C1') the renderer already translates the whole
## residue by, so C1' itself stays fixed under the rotation — only the
## ring/substituents/base rotate around it.
static func apply_strand_direction(local_positions: Dictionary, pivot: Vector2, direction_sign: float) -> Dictionary:
	if direction_sign >= 0.0:
		return local_positions
	return _rotate_180(local_positions, pivot)

static func _rotate_180(local_positions: Dictionary, pivot: Vector2) -> Dictionary:
	var rotated: Dictionary = {}
	for id in local_positions:
		rotated[id] = 2.0 * pivot - local_positions[id]
	return rotated

## Pedagogical fork-flip (docs/MolecularStructureDesign.md, "Self-paired
## fork-flip as a deliberate, labeled 2D mirror"): reflects every atom
## about the horizontal line y = axis_y, i.e. (x, y) -> (x, 2*axis_y - y).
## This is the flat-plane projection of a real 180-degree rotation about an
## in-plane axis (here, the residue's own C4'-C5' bond, which sits exactly
## horizontal in the natural, unrotated local frame). Unlike
## apply_strand_direction()'s point-reflection (det +1 in 2D, winding-order
## safe), this is a 2D mirror (det -1) by construction: the whole point is
## to visually show the residue turning around its own backbone bond, which
## this flat renderer cannot represent as a true rotation. Deliberately
## separate from apply_strand_direction() rather than folded into it -- the
## two answer different questions (which way is 5'->3' running vs. which
## face of the residue is toward the viewer) and callers choose one or the
## other, never both, for a given residue. Callers MUST pair this with the
## on-screen didactic disclaimer the design doc requires -- this function
## does not and cannot enforce that itself.
static func reflect_about_backbone_axis(local_positions: Dictionary, axis_y: float) -> Dictionary:
	var reflected: Dictionary = {}
	for id in local_positions:
		var p: Vector2 = local_positions[id]
		reflected[id] = Vector2(p.x, 2.0 * axis_y - p.y)
	return reflected

## Self-paired geometry bake, Stage 1: ring construction (docs/
## MolecularStructureDesign.md, "Self-paired geometry is baked once per
## residue, not recomputed live", 2026-08-04). Reuses the proven Tier 1
## rotation unchanged, then sweeps an elbow-flex angle (the revived
## abandoned "1b" idea) around the natural joint angle, widening Gelbin
## tolerance only as far as diagnosis/diag_self_paired_bake.py's real run
## found necessary. Bake-time only -- called at most once per residue,
## never per frame, so a real search budget is available here that was
## never available to the retired live formula.
const ELBOW_SEARCH_HALF_WINDOW_DEG: float = 40.0
const ELBOW_SEARCH_STEP_DEG: float = 1.0
const GELBIN_RING_INTERNAL_SIGMA_DEG: Dictionary = {"c3_prime": 1.0, "c4_prime": 1.0, "o4_prime": 1.4}
const REGULAR_PENTAGON_INTERIOR_DEG: float = 108.0
## Sigma multiples tried in order until one yields a valid candidate --
## confirmed against diagnosis/diag_self_paired_bake.py's real run before
## this port; update this list if that harness found different widths
## necessary.
const TOLERANCE_WIDEN_STEPS: Array[float] = [2.0, 3.0, 4.0, 6.0, 8.0]

static func _angle_at(prev_pt: Vector2, vertex_pt: Vector2, next_pt: Vector2) -> float:
	var v1: Vector2 = (prev_pt - vertex_pt).normalized()
	var v2: Vector2 = (next_pt - vertex_pt).normalized()
	return rad_to_deg(acos(clamp(v1.dot(v2), -1.0, 1.0)))

static func _within_gelbin_delta(vertex_suffix: String, measured_deg: float, sigma_multiple: float) -> bool:
	var sigma: float = GELBIN_RING_INTERNAL_SIGMA_DEG[vertex_suffix]
	return abs(measured_deg - REGULAR_PENTAGON_INTERIOR_DEG) <= sigma_multiple * sigma

static func _signed_area(points_in_order: Array) -> float:
	var s: float = 0.0
	var n: int = points_in_order.size()
	for i in range(n):
		var p1: Vector2 = points_in_order[i]
		var p2: Vector2 = points_in_order[(i + 1) % n]
		s += p1.x * p2.y - p2.x * p1.y
	return 0.5 * s

static func _elbow_candidate(a_fixed: Vector2, b_fixed: Vector2, link_len: float, alpha: float, prefer_near: Vector2) -> Array:
	var d_ab: float = a_fixed.distance_to(b_fixed)
	if d_ab <= 0.0 or d_ab > 3.0 * link_len:
		return []
	var u: Vector2 = (b_fixed - a_fixed).normalized()
	var v: Vector2 = u.orthogonal()
	var c3: Vector2 = a_fixed + u * (link_len * cos(alpha)) + v * (link_len * sin(alpha))
	var d: float = c3.distance_to(b_fixed)
	if d > 2.0 * link_len or d <= 0.0:
		return []
	var a_dist: float = d / 2.0
	var h_sq: float = link_len * link_len - a_dist * a_dist
	if h_sq < 0.0:
		return []
	var h: float = sqrt(h_sq)
	var mid: Vector2 = (c3 + b_fixed) * 0.5
	var perp: Vector2 = (b_fixed - c3).normalized().orthogonal()
	var cand1: Vector2 = mid + perp * h
	var cand2: Vector2 = mid - perp * h
	var c4: Vector2 = cand1 if cand1.distance_to(prefer_near) <= cand2.distance_to(prefer_near) else cand2
	return [c3, c4]

## Returns a flat Dictionary (atom id -> Vector2), the same shape
## derive_ring()/derive_self_paired_ring_rotation_only() return -- not a
## wrapper with separate "ring"/"theta" keys. Returns {} (empty) if no
## candidate was found at any tolerance width tried -- the caller (Stage 2
## / the bake orchestrator) must handle this as the documented
## stop-condition case, not assume a result.
static func _search_self_paired_ring(topology: MoleculeTopology, role_prefix: String, natural_ring_positions: Dictionary, pivot: Vector2, pairing_direction: Vector2, bond_length: float, toward_next: Vector2, toward_previous: Vector2) -> Dictionary:
	var rotated_ring: Dictionary = derive_self_paired_ring_rotation_only(topology, role_prefix, natural_ring_positions, pivot, pairing_direction, bond_length, toward_next, toward_previous)
	var c2_id: int = topology.find_by_role(role_prefix + "c2_prime")
	var c3_id: int = topology.find_by_role(role_prefix + "c3_prime")
	var c4_id: int = topology.find_by_role(role_prefix + "c4_prime")
	var o4_id: int = topology.find_by_role(role_prefix + "o4_prime")
	var c1: Vector2 = rotated_ring[topology.find_by_role(role_prefix + "c1_prime")]
	var c2: Vector2 = rotated_ring[c2_id]
	var o4: Vector2 = rotated_ring[o4_id]
	var natural_c3: Vector2 = rotated_ring[c3_id]
	var natural_c4: Vector2 = rotated_ring[c4_id]
	## alpha0 must be expressed RELATIVE to the local (u, v) basis
	## _elbow_candidate() builds internally (u = (b_fixed - a_fixed)
	## .normalized(), v = u.orthogonal()), not as Vector2.angle()'s
	## absolute world/local angle -- confirmed in
	## diagnosis/diag_self_paired_bake.py (commit 2135685): the naive
	## absolute-angle version put alpha0 off by ~36 degrees against the
	## +/-40 degree elbow search window, failing the Gelbin tolerance
	## check for every candidate across all three real fixtures.
	var u0: Vector2 = (o4 - c2).normalized()
	var v0: Vector2 = u0.orthogonal()
	var rel_c3: Vector2 = natural_c3 - c2
	var alpha0: float = atan2(rel_c3.dot(v0), rel_c3.dot(u0))

	var canonical_order: Array = [natural_ring_positions[topology.find_by_role(role_prefix + "c1_prime")], natural_ring_positions[c2_id], natural_ring_positions[c3_id], natural_ring_positions[c4_id], natural_ring_positions[o4_id]]
	var canonical_sign_positive: bool = _signed_area(canonical_order) > 0.0

	for sigma_mult in TOLERANCE_WIDEN_STEPS:
		var best: Dictionary = {}
		var best_spread: float = -INF
		var steps: int = int(ELBOW_SEARCH_HALF_WINDOW_DEG / ELBOW_SEARCH_STEP_DEG)
		for i in range(-steps, steps + 1):
			var alpha: float = alpha0 + deg_to_rad(i * ELBOW_SEARCH_STEP_DEG)
			var candidate: Array = _elbow_candidate(c2, o4, bond_length, alpha, natural_c4)
			if candidate.is_empty():
				continue
			var c3: Vector2 = candidate[0]
			var c4: Vector2 = candidate[1]
			if not _within_gelbin_delta("c3_prime", _angle_at(c2, c3, c4), sigma_mult):
				continue
			if not _within_gelbin_delta("c4_prime", _angle_at(c3, c4, o4), sigma_mult):
				continue
			if not _within_gelbin_delta("o4_prime", _angle_at(c4, o4, c1), sigma_mult):
				continue
			var ring_now: Dictionary = {topology.find_by_role(role_prefix + "c1_prime"): c1, c2_id: c2, c3_id: c3, c4_id: c4, o4_id: o4}
			var order_now: Array = [c1, c2, c3, c4, o4]
			if (_signed_area(order_now) > 0.0) != canonical_sign_positive:
				continue
			var bulge_dot: float = _bulge_vs_pairing_dot(ring_now, c1, c2_id, c3_id, c4_id, o4_id, pairing_direction)
			if bulge_dot > -0.05:
				continue
			var spread: float = c3.distance_to(c1) + c4.distance_to(c1)
			if spread > best_spread:
				best_spread = spread
				best = ring_now
		if not best.is_empty():
			return best
	return {}

static func _bulge_vs_pairing_dot(ring: Dictionary, c1: Vector2, c2_id: int, c3_id: int, c4_id: int, o4_id: int, pairing_direction: Vector2) -> float:
	var bulge: Vector2 = (ring[c2_id] + ring[c3_id] + ring[c4_id] + ring[o4_id]) * 0.25
	var bulge_vec: Vector2 = bulge - c1
	if bulge_vec.length() <= 0.0 or pairing_direction.length() <= 0.0:
		return 0.0
	return bulge_vec.normalized().dot(pairing_direction.normalized())

## Self-paired ring construction, Tier 1 (docs/superpowers/plans/
## 2026-08-03-self-paired-chain-collision-fix.md, Task 3) -- replaces the
## binary 0/180-degree choice (Branch B / 1a) with a closed-form continuous
## rotation angle. Still a RIGID rotation of the whole natural ring (never
## flexes C3'/C4' individually), so it is chirality-safe by construction,
## same proof as the version it replaces -- no new tolerance/signed-area
## check needed. Verified against real fixture data in
## diagnosis/diag_chain_ring_clearance_fix.py before this port.
## Kept as a small private helper -- Stage 1 (_search_self_paired_ring()
## above) calls this to get the rigid-rotated starting point before
## flexing C3'/C4' individually. No longer called directly from outside
## this file; bake_self_paired_geometry() is the public entry point now.
##
## Two real constraints, both derived from the SAME rotation angle:
## 1. Bulge-away-from-partner (existing goal, unchanged): the ring's own
##    bulge (a fixed direction in its unrotated frame) must face away from
##    the real partner (pairing_direction) -- a ~180-degree-wide feasible
##    arc, centered on theta_center below.
## 2. Chain-clearance (new): the ring's own C3'-C4' bond should point away
##    from the strand's real forward direction (blended from toward_next
##    and -toward_previous -- these agree in the common straight-strand
##    case, so a single angle can satisfy both O3' and C5' at once there).
## If the ideal chain-clearance angle falls inside the bulge-away arc, use
## it exactly. If not, clamp to the nearest arc edge -- continuous in the
## real inputs, so this does not reproduce the discrete-candidate-jump
## flicker that got the old 72-step search reverted.
static func derive_self_paired_ring_rotation_only(topology: MoleculeTopology, role_prefix: String, natural_ring_positions: Dictionary, pivot: Vector2, pairing_direction: Vector2, bond_length: float, toward_next: Vector2, toward_previous: Vector2) -> Dictionary:
	if pairing_direction.length() <= 0.0:
		return natural_ring_positions

	var c2_id: int = topology.find_by_role(role_prefix + "c2_prime")
	var c3_id: int = topology.find_by_role(role_prefix + "c3_prime")
	var c4_id: int = topology.find_by_role(role_prefix + "c4_prime")
	var o4_id: int = topology.find_by_role(role_prefix + "o4_prime")

	var bulge: Vector2 = (natural_ring_positions[c2_id] + natural_ring_positions[c3_id] + natural_ring_positions[c4_id] + natural_ring_positions[o4_id]) * 0.25
	var bulge_vec: Vector2 = bulge - pivot
	var pairing_hat: Vector2 = pairing_direction.normalized()
	var arc_target: Vector2 = -pairing_hat
	var theta_center: float = bulge_vec.angle_to(arc_target)

	var ring_bond_dir0: Vector2 = (natural_ring_positions[c4_id] - natural_ring_positions[c3_id]).normalized()

	## Fixed, deterministic tie-break for which arc edge to clamp to when
	## theta_ideal falls outside the feasible arc (docs/superpowers/plans/
	## 2026-08-03-self-paired-chain-collision-fix.md -- critical fix found
	## during Task 4 live verification). theta_center and theta_ideal are
	## structurally ~180 degrees apart for this project's geometry (always,
	## not occasionally), which puts the OLD sign-based tie-break exactly on
	## the +/-PI wraparound boundary -- any sub-floating-point jitter in the
	## real toward_next/toward_previous/pairing_direction inputs flipped
	## which side got chosen every single frame, causing a game-freezing
	## visible oscillation (confirmed live). This tiebreak depends ONLY on
	## the fixed, unrotated natural ring shape (bulge_vec, ring_bond_dir0)
	## -- never on live data -- so it is a hardcoded constant in practice
	## and cannot jitter. Both clamp sides are functionally equivalent for
	## both real constraints (bulge safety is identical via cosine symmetry;
	## chain-clearance is comparable either way since theta_ideal is always
	## near-antipodal to theta_center), so fixing this deterministically
	## loses nothing.
	var fixed_tiebreak_sign: float = 1.0 if (bulge_vec.x * ring_bond_dir0.y - bulge_vec.y * ring_bond_dir0.x) >= 0.0 else -1.0

	var tn: Vector2 = toward_next
	var tp: Vector2 = toward_previous
	if tn.length() <= 0.0 and tp.length() > 0.0:
		tn = -tp
	elif tp.length() <= 0.0 and tn.length() > 0.0:
		tp = -tn

	var theta: float = theta_center
	if tn.length() > 0.0 or tp.length() > 0.0:
		var tn_hat: Vector2 = tn.normalized() if tn.length() > 0.0 else Vector2.ZERO
		var tp_hat: Vector2 = tp.normalized() if tp.length() > 0.0 else Vector2.ZERO
		var forward: Vector2 = tn_hat - tp_hat
		if forward.length() > 0.0:
			var target_ring_bond_dir: Vector2 = -forward.normalized()
			var theta_ideal: float = ring_bond_dir0.angle_to(target_ring_bond_dir)
			var half: float = PI / 2.0 - deg_to_rad(BULGE_DOT_MARGIN_DEG)
			var delta: float = wrapf(theta_ideal - theta_center, -PI, PI)
			theta = theta_ideal if abs(delta) <= half else theta_center + fixed_tiebreak_sign * half

	var result: Dictionary = {}
	for id in natural_ring_positions:
		result[id] = pivot + (natural_ring_positions[id] - pivot).rotated(theta)
	return result

## Self-paired geometry bake, Stage 2 (docs/MolecularStructureDesign.md,
## same entry as Stage 1 above): O3'/C5' direction AND distance searched
## jointly, centered on and bounded around the real toward_next/
## toward_previous direction -- never able to point at the wrong
## neighbor, per this project's hard-won constraint from four
## independently-failed prior attempts (docs/MolecularStructure_
## BasePairExpansion.md, Bug V/W). Bake-time only, same as Stage 1.
const SUBSTITUENT_SEARCH_HALF_WINDOW_DEG: float = 90.0
const SUBSTITUENT_SEARCH_ANGLE_STEP_DEG: float = 3.0
const SUBSTITUENT_SEARCH_DIST_STEPS: int = 6

static func _min_clearance_to_ring(point: Vector2, ring_positions: Dictionary) -> float:
	var best: float = INF
	for p in ring_positions.values():
		best = min(best, point.distance_to(p))
	return best

## Objective (revised after live testing found the original max-clearance
## objective produces visually chaotic, flung-out chains): among all
## candidates that CLEAR the collision threshold, prefer the one with
## the SMALLEST deviation from the natural (real) direction and distance
## -- a minimal, chemically-plausible-looking placement, not the most
## extreme one the search window allows. Falls back to the old max-
## clearance candidate only when nothing in the window clears the
## threshold at all (the genuinely-hard case this project already
## documents as an accepted open residual, not silently degraded
## further). Deviation is an unweighted sum of angular offset (degrees)
## and radial overshoot beyond bond_length -- both real, comparable
## "how far from natural" measures, left unweighted deliberately (no
## tuned relative-importance constant to justify without more data than
## this project currently has). Matches diagnosis/diag_self_paired_bake.py's
## search_substituent(), ported after live testing (not part of the
## original brief).
static func _search_substituent(start_pos: Vector2, natural_dir: Vector2, ring_positions: Dictionary, bond_length: float, real_neighbor_distance: float, collision_clearance_threshold: float) -> Dictionary:
	if natural_dir.length() <= 0.0:
		return {}
	var natural_angle: float = natural_dir.angle()
	var max_safe_reach: float = max(bond_length, real_neighbor_distance * 0.5 - collision_clearance_threshold)
	var best_clearing: Dictionary = {}
	var best_clearing_deviation: float = INF
	var best_overall: Dictionary = {}
	var best_overall_clearance: float = -INF
	var steps: int = int(SUBSTITUENT_SEARCH_HALF_WINDOW_DEG / SUBSTITUENT_SEARCH_ANGLE_STEP_DEG)
	for i in range(-steps, steps + 1):
		var angle: float = natural_angle + deg_to_rad(i * SUBSTITUENT_SEARCH_ANGLE_STEP_DEG)
		var direction: Vector2 = Vector2(cos(angle), sin(angle))
		for j in range(SUBSTITUENT_SEARCH_DIST_STEPS + 1):
			var dist: float = bond_length + (max_safe_reach - bond_length) * (float(j) / float(SUBSTITUENT_SEARCH_DIST_STEPS))
			var point: Vector2 = start_pos + direction * dist
			var clearance: float = _min_clearance_to_ring(point, ring_positions)
			var candidate: Dictionary = {point = point, direction = direction, dist = dist, clearance = clearance}
			var deviation: float = abs(i * SUBSTITUENT_SEARCH_ANGLE_STEP_DEG) + abs(dist - bond_length)
			if clearance >= collision_clearance_threshold:
				if deviation < best_clearing_deviation:
					best_clearing_deviation = deviation
					best_clearing = candidate
			if clearance > best_overall_clearance:
				best_overall_clearance = clearance
				best_overall = candidate
	return best_clearing if not best_clearing.is_empty() else best_overall

## The single public entry point for this whole bake (docs/
## MolecularStructureDesign.md, "Self-paired geometry is baked once per
## residue, not recomputed live"). Returns {} (empty) if Stage 1 found no
## ring candidate at any tolerance width -- the caller (the renderer's
## cache-or-bake lookup, Task 4) must handle this as the documented
## stop-condition case: fall back to the rigid rotation-only construction
## (derive_self_paired_ring_rotation_only) rather than crash or render
## nothing.
static func bake_self_paired_geometry(topology: MoleculeTopology, role_prefix: String, bond_length: float, pairing_direction: Vector2, toward_next: Vector2, toward_previous: Vector2, molecular_atom_radius: float) -> Dictionary:
	var natural_ring: Dictionary = derive_ring(topology, role_prefix, bond_length)
	var pivot: Vector2 = natural_ring[topology.find_by_role(role_prefix + "c1_prime")]
	var ring_positions: Dictionary = _search_self_paired_ring(topology, role_prefix, natural_ring, pivot, pairing_direction, bond_length, toward_next, toward_previous)
	if ring_positions.is_empty():
		ring_positions = derive_self_paired_ring_rotation_only(topology, role_prefix, natural_ring, pivot, pairing_direction, bond_length, toward_next, toward_previous)

	var collision_clearance_threshold: float = COLLISION_CLEARANCE_RATIO * molecular_atom_radius

	var c3_id: int = topology.find_by_role(role_prefix + "c3_prime")
	var c4_id: int = topology.find_by_role(role_prefix + "c4_prime")
	var tn: Vector2 = toward_next
	var tp: Vector2 = toward_previous
	if tn.length() <= 0.0 and tp.length() > 0.0:
		tn = -tp
	elif tp.length() <= 0.0 and tn.length() > 0.0:
		tp = -tn

	var substituent_positions: Dictionary = derive_substituents(topology, role_prefix, ring_positions, bond_length, toward_next, toward_previous)
	if ring_positions.has(c3_id) and tn.length() > 0.0:
		var o3_id: int = topology.find_by_role(role_prefix + "o3_prime")
		var o3_result: Dictionary = _search_substituent(ring_positions[c3_id], tn, ring_positions, bond_length, tn.length(), collision_clearance_threshold)
		if not o3_result.is_empty():
			substituent_positions[o3_id] = o3_result.point
	if ring_positions.has(c4_id) and tp.length() > 0.0:
		var c5_id: int = topology.find_by_role(role_prefix + "c5_prime")
		var c5_result: Dictionary = _search_substituent(ring_positions[c4_id], tp, ring_positions, bond_length, tp.length(), collision_clearance_threshold)
		if not c5_result.is_empty():
			# O5'/alpha-phosphate continue chained from the searched C5' in
			# its own found direction, same bond_length increments as
			# derive_substituents() already applies -- recomputed here since
			# C5' itself moved.
			var o5_id: int = topology.find_by_role(role_prefix + "o5_prime")
			var alpha_id: int = topology.find_by_role(role_prefix + "alpha_phosphate")
			substituent_positions[c5_id] = c5_result.point
			if o5_id != -1:
				var o5_pos: Vector2 = c5_result.point + c5_result.direction * bond_length
				substituent_positions[o5_id] = o5_pos
				if alpha_id != -1:
					var alpha_pos: Vector2 = o5_pos + c5_result.direction * bond_length
					substituent_positions[alpha_id] = alpha_pos
					# O1a/O2a must move WITH the phosphate they're attached
					# to -- mirrors derive_substituents()'s own formula
					# (this file, lines ~242-248) exactly, just using the
					# NEW alpha_pos/direction from this search instead of
					# the old unmodified outward. Found via live testing:
					# without this, O1a/O2a stayed at their position from
					# the initial (pre-search) derive_substituents() call
					# while Pa itself moved, visually detaching them from
					# their own phosphate.
					var alpha_o1_id: int = topology.find_by_role(role_prefix + "alpha_O1")
					var alpha_o2_id: int = topology.find_by_role(role_prefix + "alpha_O2")
					var perp: Vector2 = c5_result.direction.orthogonal()
					if alpha_o1_id != -1:
						substituent_positions[alpha_o1_id] = alpha_pos + (c5_result.direction + perp).normalized() * bond_length
					if alpha_o2_id != -1:
						substituent_positions[alpha_o2_id] = alpha_pos + (c5_result.direction - perp).normalized() * bond_length

	return {ring_positions = ring_positions, substituent_positions = substituent_positions}

