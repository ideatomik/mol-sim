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
static func derive_ring(topology: MoleculeTopology, role_prefix: String, bond_length: float) -> Dictionary:
	return NitrogenBaseDeriver.derive_regular_ring(topology, RING_ROLE_SUFFIXES, role_prefix, bond_length)

## Substituent positions (5'-CH2-phosphate chain's first atom, 3'-OH),
## merged into the same local frame as derive_ring()'s output — the
## backbone (ring) stays anchored; substituents hang off it at derived
## angles, per the Layout section's stability rule. Placed radially outward
## from the ring centroid at each anchor vertex, which is the simplest
## idealized choice consistent with "the backbone must not visibly shift
## when something attached to it changes."
##
## `pairing_direction` (Bug J fix, docs/MolecularStructure_
## BasePairExpansion.md): real, world-space, points TOWARD the partner —
## same convention molecule_structure_renderer.gd already computes for base
## placement. Without it, "outward" was purely a function of the ring's own
## antiparallel-pucker rotation sign (apply_strand_direction, owned by the
## caller) — correct for leading/lagging only by coincidence, backwards for
## template_top/template_bottom, confirmed via a live screenshot: their
## chain reached TOWARD the real partner instead of away. Left at the
## default zero vector (unpaired, or a caller that hasn't been updated),
## behaves exactly as before — there's no real partner to be wrong
## relative to, so nothing needs correcting.
static func derive_substituents(topology: MoleculeTopology, role_prefix: String, ring_positions: Dictionary, bond_length: float, pairing_direction: Vector2 = Vector2.ZERO) -> Dictionary:
	var positions: Dictionary = {}

	# Decided ONCE from C4' and applied to both substituent groups (O3' via
	# C3', and the C5'/O5'/alpha-phosphate chain via C4') so they flip
	# together rather than independently — C3' and C4' always agree on
	# which way is "toward the partner" in this ring's construction (same Y
	# sign, only X differs), so a single decision keeps the existing
	# left/right branching shape intact and just mirrors it vertically.
	# Negating the WHOLE outward vector (both components), not just one
	# axis, is a proper 180-degree ROTATION of the substituent group around
	# its own fixed attachment point on the ring — never a mirror, per the
	# same rule apply_strand_direction() already documents (a mirror would
	# silently flip the chain's own chirality while looking like a fix).
	var flip: bool = false
	if pairing_direction.length() > 0.0:
		var c4_id_probe: int = topology.find_by_role(role_prefix + "c4_prime")
		if c4_id_probe != -1 and ring_positions.has(c4_id_probe):
			var natural_outward: Vector2 = ring_positions[c4_id_probe].normalized()
			flip = natural_outward.dot(pairing_direction.normalized()) > 0.0

	var c3_id: int = topology.find_by_role(role_prefix + "c3_prime")
	var o3_id: int = topology.find_by_role(role_prefix + "o3_prime")
	if c3_id != -1 and o3_id != -1 and ring_positions.has(c3_id):
		var c3_pos: Vector2 = ring_positions[c3_id]
		var outward: Vector2 = -c3_pos.normalized() if flip else c3_pos.normalized()
		positions[o3_id] = c3_pos + outward * bond_length

	var c4_id: int = topology.find_by_role(role_prefix + "c4_prime")
	var c5_id: int = topology.find_by_role(role_prefix + "c5_prime")
	if c4_id != -1 and c5_id != -1 and ring_positions.has(c4_id):
		var c4_pos: Vector2 = ring_positions[c4_id]
		var outward: Vector2 = -c4_pos.normalized() if flip else c4_pos.normalized()
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

## Bug L fix (docs/MolecularStructure_BasePairExpansion.md): apply_strand_
## direction()'s rotation is a FIXED per-strand convention (real 5'->3'
## reading direction, confirmed against SKILL.md's polarity table) — it
## must NOT vary per residue based on live pairing state, or consecutive
## residues along the same strand would visibly zigzag. derive_substituents()'s
## chain-flip (Bug J), however, IS driven by live pairing_direction. Before
## Bug J both used the ring's own as-derived local frame and so always
## agreed (even though the chain pointed at the partner — Bug J's original
## problem). Bug J fixed the chain alone, leaving the ring's fixed-sign
## orientation unchanged — for leading/lagging this is invisible (their
## chain's needed flip is always false, so nothing diverges), but for
## template_top/template_bottom the ring now bulges one way while the
## chain reaches the opposite way within the SAME residue — confirmed via
## the F9 dump: ring-bulge-direction dot chain-reach-direction is strongly
## POSITIVE (aligned) for leading (+555) and lagging (+492), strongly
## NEGATIVE (opposed) for template_top (-110) and template_bottom (-173).
##
## Fixed by moving the SAME flip decision Bug J already computes (does the
## ring's natural C4' direction, in its OWN local frame, face toward the
## real partner?) onto the RING itself, applied as an ADDITIONAL rotation
## on top of the fixed-sign one — then reverting derive_substituents() to
## always use natural/unflipped outward again (the caller now passes
## Vector2.ZERO for its pairing_direction argument), since the chain
## naturally follows wherever the ring ends up. Two 180-degree rotations
## around the same pivot (C1') compose correctly either way: a strand
## whose fixed-sign rotation already applied gets it CANCELLED (net
## identity) when this test also fires, a strand whose fixed-sign
## rotation didn't apply gets this one ADDED — verified by hand against
## the dump for both template_top (0+1=1, bulge flips to match chain) and
## template_bottom (1+1=2=identity, bulge flips back to match chain).
## Easy revert: delete the call site in molecule_structure_renderer.gd and
## restore its derive_substituents() call to pass real pairing_direction
## again — this function is additive, nothing else changes.
static func apply_partner_flip(local_positions: Dictionary, pivot: Vector2, probe_id: int, pairing_direction: Vector2) -> Dictionary:
	if pairing_direction.length() <= 0.0 or not local_positions.has(probe_id):
		return local_positions
	var natural_outward: Vector2 = local_positions[probe_id].normalized()
	if natural_outward.dot(pairing_direction.normalized()) <= 0.0:
		return local_positions
	return _rotate_180(local_positions, pivot)
