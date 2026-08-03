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
## as BASE_ROTATION_SEARCH_STEPS's own comment (a handful of residues
## rendered per frame at deep zoom).
const SELF_PAIRED_ROTATION_SEARCH_STEPS: int = 72
## Small negative margin, not exactly 0.0: keeps the winning angle off the
## constraint's exact boundary, where floating-point noise (different
## residues, different frames) could flip bulge_vs_pairing_dot's sign.
## Kept small deliberately — it only needs to clear floating-point noise,
## not carve out a large exclusion that would shrink the search's freedom
## to find good chain clearance.
const SELF_PAIRED_BULGE_DOT_MARGIN: float = 0.05

## Net-side constraint fix (docs/MolecularStructure_BasePairExpansion.md):
## resolve_self_paired_ring_rotation()'s search originally constrained
## bulge_vs_pairing_dot and self-clearance only — nothing stopped it from
## picking an angle where O3'/C5' net out on the WRONG side of the pivot
## relative to the real toward_next/toward_previous neighbor, even though
## each individual hop's DIRECTION was mathematically correct (confirmed
## via real dump coordinates: template_top slot 2's O3' landed at world
## x=318.09, LESS than its own C1' at x=324, despite the real next
## residue sitting at x=378 — C3' itself started far enough on the wrong
## side that one correct-direction bond_length hop wasn't enough to net
## positive). This margin is in WORLD UNITS (a projection distance, not a
## normalized cosine like SELF_PAIRED_BULGE_DOT_MARGIN), expressed as a
## ratio of bond_length rather than a flat constant specifically so it
## stays proportionally correct if bond_length itself is ever scaled
## (e.g. a future self-paired-specific size adjustment) — a flat
## constant would silently drift out of proportion in that case.
const SELF_PAIRED_NET_SIDE_MARGIN_RATIO: float = 0.1

## Deterministic tie-break (docs/MolecularStructure_BasePairExpansion.md,
## frame-to-frame ring-rotation flicker): CONFIRMED via two real F9 dumps
## 3 seconds apart that the winning angle for a boundary residue (exact
## toward_next/toward_previous antiparallel fallback firing) flips between
## an exact mirror pair (e.g. 165/195 degrees) frame to frame — real
## observed gaps of 0.04-0.21 (world units) between winner and runner-up.
## Root cause is NOT float noise in the search math — it's the real
## toward_next vector itself changing slightly frame to frame (observed
## y-component swinging from +0.53 to -0.10), which is enough to flip
## which of two near-mirror-symmetric candidates truly scores higher.
## "First-encountered wins" (the loop's plain `>` comparison) does NOT
## fix this, since the two candidates are NOT exactly tied — they're
## just close enough that legitimate sub-degree input jitter flips which
## is truly larger. The fix has to make the WINNER SELECTION itself
## insensitive to differences below this epsilon: among every valid
## candidate within epsilon of the best clearance found, always pick the
## one earliest in the fixed iteration order (smallest angle) — never
## whichever the frame's exact numbers happen to favor. Expressed as a
## ratio of bond_length, same convention as the other self-paired
## margins, and picked comfortably above the observed max gap (0.21)
## while staying well below the gap to the THIRD-place candidate
## (observed ~0.9 in the same real dumps) so it only merges the genuinely
## near-tied pair, not the wider field.
const SELF_PAIRED_TIE_BREAK_EPSILON_RATIO: float = 0.05

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

## Self-paired-template ring orientation (Bug W, docs/MolecularStructure_
## BasePairExpansion.md — supersedes Bug V's binary identity/180-degree
## choice for this one case). Bug V's real requirement was always
## DIRECTIONAL (bulge faces away from the partner, i.e.
## bulge_vs_pairing_dot < 0) — the diagnostic's own descriptive text
## already phrased it that way; -1.0 was never load-bearing anywhere
## downstream, just what the old binary rotation happened to produce.
## That binary choice left zero freedom to ALSO satisfy chain-vs-own-ring
## clearance for residues where the flip fired (confirmed via live dump:
## O3' landing 0.04-0.21 units from a ring atom). Two earlier approaches
## were tried and rejected: negating toward_next/toward_previous (broke
## the real-neighbor connection — the chain must always reach the real
## adjacent residue, not a computed direction) and reflecting the ring
## across pairing_direction (chirality-unsafe — ANY single-axis reflection
## has determinant -1, silently turning the rendered ring into its wrong
## enantiomer, the exact defect apply_strand_direction()'s own doc comment
## and derive_ring()'s HARDCODED HANDEDNESS note rule out).
##
## This replaces the binary choice with a bounded SEARCH over the one
## legitimately free parameter — rotation angle around the fixed C1' pivot
## — same "maximize real clearance via search, not a closed-form guess"
## idiom NitrogenBaseDeriver.derive_base_layout() already uses for its own
## rotation search, aimed here at the CHAIN (built fresh per candidate from
## the real, unmodified toward_next/toward_previous) instead of that
## function's avoid_points. Chirality-safe BY CONSTRUCTION: every candidate
## is a proper rotation (Vector2.rotated(), determinant +1) around a fixed
## pivot, never a reflection — so the enantiomer concern that ruled out the
## reflection approach cannot apply to any candidate, not just the winner.
##
## `natural_ring_positions` is the ring BEFORE any rotation (derive_ring()'s
## raw output). `pivot` is C1' (stays fixed under every candidate, same as
## apply_strand_direction()). Falls back to the old binary choice (never to
## an unrotated/unfiltered ring) in the — expected never to occur in
## practice, since the constraint region is roughly half the circle — case
## where no candidate in the sweep satisfies the margin.
static func resolve_self_paired_ring_rotation(topology: MoleculeTopology, role_prefix: String, natural_ring_positions: Dictionary, pivot: Vector2, pairing_direction: Vector2, bond_length: float, toward_next: Vector2, toward_previous: Vector2) -> Dictionary:
	if pairing_direction.length() <= 0.0:
		return natural_ring_positions
	var bulge_ids: Array = [
		topology.find_by_role(role_prefix + "c2_prime"), topology.find_by_role(role_prefix + "c3_prime"),
		topology.find_by_role(role_prefix + "c4_prime"), topology.find_by_role(role_prefix + "o4_prime"),
	]
	var pairing_hat: Vector2 = pairing_direction.normalized()

	# Net-side constraint (docs/MolecularStructure_BasePairExpansion.md):
	# same mutual-fallback derive_substituents() applies internally,
	# duplicated here so boundary residues (one real neighbor missing) are
	# checked against the effective (fallback-resolved) direction rather
	# than skipped outright.
	var effective_toward_next: Vector2 = toward_next
	var effective_toward_previous: Vector2 = toward_previous
	if effective_toward_next.length() <= 0.0 and effective_toward_previous.length() > 0.0:
		effective_toward_next = -effective_toward_previous
	elif effective_toward_previous.length() <= 0.0 and effective_toward_next.length() > 0.0:
		effective_toward_previous = -effective_toward_next
	var net_side_margin: float = bond_length * SELF_PAIRED_NET_SIDE_MARGIN_RATIO
	var o3_id: int = topology.find_by_role(role_prefix + "o3_prime")
	var c5_id: int = topology.find_by_role(role_prefix + "c5_prime")

	# Deterministic tie-break (docs/MolecularStructure_BasePairExpansion.md):
	# every valid candidate is collected, in fixed increasing-angle order,
	# rather than tracking only a running best — a real frame-to-frame
	# flicker was confirmed where the true winner among two near-mirror
	# candidates flips due to real (not floating-point-noise) sub-degree
	# input jitter. Picking the single running-max candidate is exactly
	# what produced that flicker; the fix (below, after the loop) needs
	# the full list to find every candidate within epsilon of the best.
	var valid_candidates: Array = []
	for i in range(SELF_PAIRED_ROTATION_SEARCH_STEPS):
		var angle: float = TAU * float(i) / float(SELF_PAIRED_ROTATION_SEARCH_STEPS)
		var candidate: Dictionary = {}
		for id in natural_ring_positions:
			candidate[id] = pivot + (natural_ring_positions[id] - pivot).rotated(angle)

		var bulge_sum: Vector2 = Vector2.ZERO
		var bulge_count: int = 0
		for bulge_id in bulge_ids:
			if candidate.has(bulge_id):
				bulge_sum += candidate[bulge_id]
				bulge_count += 1
		if bulge_count == 0:
			continue
		var bulge: Vector2 = bulge_sum / float(bulge_count) - pivot
		if bulge.length() <= 0.0:
			continue
		var bulge_dot: float = bulge.normalized().dot(pairing_hat)
		if bulge_dot > -SELF_PAIRED_BULGE_DOT_MARGIN:
			continue  # constraint not satisfied (or too close to the boundary)

		var candidate_substituents: Dictionary = derive_substituents(topology, role_prefix, candidate, bond_length, toward_next, toward_previous)

		# Net-side constraint: O3'/C5' must net out on the side of the
		# pivot the real neighbor actually is on — not just be pulled
		# toward it from wherever C3'/C4' happened to land. Checking only
		# the first hop of each sub-chain is sufficient: O5'/alpha-P
		# continue in the exact same direction, so their projection is
		# strictly more positive once O3'/C5' already clear the margin.
		if effective_toward_next.length() > 0.0 and candidate_substituents.has(o3_id):
			var o3_side: float = (candidate_substituents[o3_id] - pivot).dot(effective_toward_next.normalized())
			if o3_side <= net_side_margin:
				continue
		if effective_toward_previous.length() > 0.0 and candidate_substituents.has(c5_id):
			var c5_side: float = (candidate_substituents[c5_id] - pivot).dot(effective_toward_previous.normalized())
			if c5_side <= net_side_margin:
				continue

		var clearance: float = INF
		for sp in candidate_substituents.values():
			for rp in candidate.values():
				clearance = min(clearance, sp.distance_to(rp))
		valid_candidates.append({positions = candidate, clearance = clearance})

	if not valid_candidates.is_empty():
		var best_clearance: float = -INF
		for vc in valid_candidates:
			if vc.clearance > best_clearance:
				best_clearance = vc.clearance
		var tie_break_epsilon: float = bond_length * SELF_PAIRED_TIE_BREAK_EPSILON_RATIO
		# valid_candidates is already in fixed increasing-angle order (the
		# loop above appends in that order), so the first one found here
		# within epsilon of the best is deterministically the
		# smallest-angle member of the near-tied set — never whichever
		# the frame's exact numbers happen to favor.
		for vc in valid_candidates:
			if vc.clearance >= best_clearance - tie_break_epsilon:
				return vc.positions

	var natural_bulge: Vector2 = Vector2.ZERO
	var natural_bulge_count: int = 0
	for bulge_id in bulge_ids:
		if natural_ring_positions.has(bulge_id):
			natural_bulge += natural_ring_positions[bulge_id]
			natural_bulge_count += 1
	if natural_bulge_count > 0:
		natural_bulge = natural_bulge / float(natural_bulge_count) - pivot
		if natural_bulge.length() > 0.0:
			var natural_dot: float = natural_bulge.normalized().dot(pairing_hat)
			var fallback_sign: float = -1.0 if natural_dot > 0.0 else 1.0
			return apply_strand_direction(natural_ring_positions, pivot, fallback_sign)
	return natural_ring_positions

## TEMPORARY diagnostic (docs/MolecularStructure_BasePairExpansion.md,
## frame-to-frame ring-rotation flicker investigation) — a full-trace
## twin of resolve_self_paired_ring_rotation() above: same per-candidate
## math, kept in sync BY HAND (same "explicit duplicate, cross-referenced
## by comment" convention this file already uses for
## molecule_structure_renderer.gd's _rebuild_layout()/_derive_full_residue()
## pair), returning every candidate's data instead of only the winner, so
## a caller can inspect whether the winning score is a clear maximum or a
## near/exact tie with a runner-up — invisible from the real function's
## return value alone. Remove once the flicker investigation is served,
## same convention as this file's other removed temporary diagnostics.
## Each entry: {angle_deg, bulge_dot, bulge_valid, o3_side, o3_valid,
## c5_side, c5_valid, valid (all three), clearance (INF if invalid)}.
static func debug_self_paired_candidates(topology: MoleculeTopology, role_prefix: String, natural_ring_positions: Dictionary, pivot: Vector2, pairing_direction: Vector2, bond_length: float, toward_next: Vector2, toward_previous: Vector2) -> Array:
	var trace: Array = []
	if pairing_direction.length() <= 0.0:
		return trace
	var bulge_ids: Array = [
		topology.find_by_role(role_prefix + "c2_prime"), topology.find_by_role(role_prefix + "c3_prime"),
		topology.find_by_role(role_prefix + "c4_prime"), topology.find_by_role(role_prefix + "o4_prime"),
	]
	var pairing_hat: Vector2 = pairing_direction.normalized()

	var effective_toward_next: Vector2 = toward_next
	var effective_toward_previous: Vector2 = toward_previous
	if effective_toward_next.length() <= 0.0 and effective_toward_previous.length() > 0.0:
		effective_toward_next = -effective_toward_previous
	elif effective_toward_previous.length() <= 0.0 and effective_toward_next.length() > 0.0:
		effective_toward_previous = -effective_toward_next
	var net_side_margin: float = bond_length * SELF_PAIRED_NET_SIDE_MARGIN_RATIO
	var o3_id: int = topology.find_by_role(role_prefix + "o3_prime")
	var c5_id: int = topology.find_by_role(role_prefix + "c5_prime")

	for i in range(SELF_PAIRED_ROTATION_SEARCH_STEPS):
		var angle: float = TAU * float(i) / float(SELF_PAIRED_ROTATION_SEARCH_STEPS)
		var candidate: Dictionary = {}
		for id in natural_ring_positions:
			candidate[id] = pivot + (natural_ring_positions[id] - pivot).rotated(angle)

		var entry: Dictionary = {
			angle_deg = rad_to_deg(angle), bulge_dot = 0.0, bulge_valid = false,
			o3_side = 0.0, o3_valid = true, c5_side = 0.0, c5_valid = true,
			valid = false, clearance = INF,
		}

		var bulge_sum: Vector2 = Vector2.ZERO
		var bulge_count: int = 0
		for bulge_id in bulge_ids:
			if candidate.has(bulge_id):
				bulge_sum += candidate[bulge_id]
				bulge_count += 1
		if bulge_count == 0:
			trace.append(entry)
			continue
		var bulge: Vector2 = bulge_sum / float(bulge_count) - pivot
		if bulge.length() <= 0.0:
			trace.append(entry)
			continue
		entry.bulge_dot = bulge.normalized().dot(pairing_hat)
		entry.bulge_valid = entry.bulge_dot <= -SELF_PAIRED_BULGE_DOT_MARGIN
		if not entry.bulge_valid:
			trace.append(entry)
			continue

		var candidate_substituents: Dictionary = derive_substituents(topology, role_prefix, candidate, bond_length, toward_next, toward_previous)

		if effective_toward_next.length() > 0.0 and candidate_substituents.has(o3_id):
			entry.o3_side = (candidate_substituents[o3_id] - pivot).dot(effective_toward_next.normalized())
			entry.o3_valid = entry.o3_side > net_side_margin
		if effective_toward_previous.length() > 0.0 and candidate_substituents.has(c5_id):
			entry.c5_side = (candidate_substituents[c5_id] - pivot).dot(effective_toward_previous.normalized())
			entry.c5_valid = entry.c5_side > net_side_margin
		if not (entry.o3_valid and entry.c5_valid):
			trace.append(entry)
			continue

		var clearance: float = INF
		for sp in candidate_substituents.values():
			for rp in candidate.values():
				clearance = min(clearance, sp.distance_to(rp))
		entry.valid = true
		entry.clearance = clearance
		trace.append(entry)

	return trace

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
