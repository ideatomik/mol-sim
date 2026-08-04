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
	t.add_bond(alpha_p, alpha_o1)
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

## Tier 2 (docs/superpowers/plans/2026-08-03-self-paired-chain-collision-fix.md,
## Task 3, revised after a critical live-testing finding): smallest
## distance >= bond_length along the UNCHANGED real direction `dir_hat`
## that clears every atom in `ring_positions` by
## `collision_clearance_threshold`, capped so it can never reach past
## roughly the halfway point to the real same-strand neighbor
## (real_neighbor_distance = length of the real, UNnormalized
## toward_next/toward_previous vector) minus a
## `collision_clearance_threshold`-sized safety margin -- grounded in the
## real live neighbor distance, not an arbitrary bond-length multiplier,
## so this scales correctly regardless of what slot spacing/bond_length
## ratio a given scene uses. Found via live testing: the old flat
## bond_length-ratio cap let the chain reach 55.1 units when the real
## neighbor was only 54.0 units away -- a real, visible inter-residue
## collision (confirmed: one residue's alpha-phosphate landed 6.46 units
## from the NEXT residue's own O4' atom, well under threshold) that the
## old same-residue-only cap had no way to prevent. Trade-off: may leave
## some same-ring collision unresolved in tight cases (accepted, per this
## project's established "document the limit, don't chase it further"
## pattern) in exchange for guaranteeing zero inter-residue collision.
## `collision_clearance_threshold` is passed in by the caller (derived
## from the real molecular_atom_radius via COLLISION_CLEARANCE_RATIO,
## same pattern as bond_length) rather than read from a module constant,
## after live testing found a stale hardcoded threshold silently drifted
## out of sync with the real scene's theme override (see
## COLLISION_CLEARANCE_RATIO's doc comment). Never changes direction --
## only how far along the already-correct real direction the substituent
## sits, so this cannot desync from the real inter-residue backbone bond
## the way every previously-attempted fix for the original collision did.
static func _required_chain_reach(start_pos: Vector2, dir_hat: Vector2, ring_positions: Dictionary, bond_length: float, real_neighbor_distance: float, collision_clearance_threshold: float) -> float:
	var best: float = bond_length
	var threshold_sq: float = collision_clearance_threshold * collision_clearance_threshold
	for p in ring_positions.values():
		var rel: Vector2 = p - start_pos
		var a: float = rel.dot(dir_hat)
		var h_sq: float = max(0.0, rel.length_squared() - a * a)
		if h_sq >= threshold_sq:
			continue
		var current_dist_sq: float = (bond_length - a) * (bond_length - a) + h_sq
		if current_dist_sq >= threshold_sq:
			continue
		var reach: float = sqrt(threshold_sq - h_sq)
		best = max(best, a + reach)
	var max_safe_reach: float = max(bond_length, real_neighbor_distance * 0.5 - collision_clearance_threshold)
	return min(best, max_safe_reach)

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
static func derive_substituents(topology: MoleculeTopology, role_prefix: String, ring_positions: Dictionary, bond_length: float, toward_next: Vector2 = Vector2.ZERO, toward_previous: Vector2 = Vector2.ZERO, is_self_paired_template: bool = false, molecular_atom_radius: float = 6.0) -> Dictionary:
	var positions: Dictionary = {}
	var collision_clearance_threshold: float = COLLISION_CLEARANCE_RATIO * molecular_atom_radius

	if toward_next.length() <= 0.0 and toward_previous.length() > 0.0:
		toward_next = -toward_previous
	elif toward_previous.length() <= 0.0 and toward_next.length() > 0.0:
		toward_previous = -toward_next

	var c3_id: int = topology.find_by_role(role_prefix + "c3_prime")
	var o3_id: int = topology.find_by_role(role_prefix + "o3_prime")
	if c3_id != -1 and o3_id != -1 and ring_positions.has(c3_id):
		var c3_pos: Vector2 = ring_positions[c3_id]
		var outward: Vector2 = toward_next.normalized() if toward_next.length() > 0.0 else c3_pos.normalized()
		var reach: float = bond_length
		if is_self_paired_template and toward_next.length() > 0.0:
			reach = _required_chain_reach(c3_pos, outward, ring_positions, bond_length, toward_next.length(), collision_clearance_threshold)
		positions[o3_id] = c3_pos + outward * reach

	var c4_id: int = topology.find_by_role(role_prefix + "c4_prime")
	var c5_id: int = topology.find_by_role(role_prefix + "c5_prime")
	if c4_id != -1 and c5_id != -1 and ring_positions.has(c4_id):
		var c4_pos: Vector2 = ring_positions[c4_id]
		var outward: Vector2 = toward_previous.normalized() if toward_previous.length() > 0.0 else c4_pos.normalized()
		var reach: float = bond_length
		if is_self_paired_template and toward_previous.length() > 0.0:
			reach = _required_chain_reach(c4_pos, outward, ring_positions, bond_length, toward_previous.length(), collision_clearance_threshold)
		var c5_pos: Vector2 = c4_pos + outward * reach
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

## Self-paired ring construction, Tier 1 (docs/superpowers/plans/
## 2026-08-03-self-paired-chain-collision-fix.md, Task 3) -- replaces the
## binary 0/180-degree choice (Branch B / 1a) with a closed-form continuous
## rotation angle. Still a RIGID rotation of the whole natural ring (never
## flexes C3'/C4' individually), so it is chirality-safe by construction,
## same proof as the version it replaces -- no new tolerance/signed-area
## check needed. Verified against real fixture data in
## diagnosis/diag_chain_ring_clearance_fix.py before this port.
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
static func derive_self_paired_ring(topology: MoleculeTopology, role_prefix: String, natural_ring_positions: Dictionary, pivot: Vector2, pairing_direction: Vector2, bond_length: float, toward_next: Vector2, toward_previous: Vector2) -> Dictionary:
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

