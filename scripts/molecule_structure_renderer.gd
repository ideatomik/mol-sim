class_name MoleculeStructureRenderer
extends Node2D

# ==========================================
# MOLECULE STRUCTURE RENDERER
# Growth Session 1: ribose + phosphodiester bond, synthesized strand only.
# Growth Session 2 (docs/MolecularStructure_BasePairExpansion.md): full flat
# double ribbon — both strands (original template + synthesized), full
# nitrogenous bases, hydrogen bonds between paired bases. Still active ONLY
# at deep free-camera zoom.
#
# GROWTH-SESSION-2 CORRECTION (caught during implementation, not in the
# approved plan): EVERY rendered residue is folded (step_n = 0), including
# template-strand ones. A template strand is already mature, incorporated
# DNA — one phosphate per residue, not a free triphosphate — so there is no
# case in this milestone where the unfolded seed (full triphosphate) should
# ever be drawn. The plan's "template uses step_n = -1" was wrong; the
# fold-engine's "-1 returns the seed unmodified" feature stays supported for
# future use, just unused here.
#
# Persisted scene node, sibling of $NucleotideField under the root
# Simulation node. Fed by two independent, read-only sources:
# replication_manager.gd's get_synthesized_nucleotides() (leading/lagging)
# and simulation.gd's get_template_nucleotides() (template_bottom/
# template_top) — see set_replication_manager()/set_template_source().
#
# Immediate-mode (single _draw(), parallel arrays), NOT per-atom nodes —
# matches nucleotide_field.gd's pattern. See MolecularStructureDesign.md
# correction #7/#13 for the criterion.
# ==========================================

# ---------- REFERENCES (cached once in _ready(); VALUES read live every frame) ----------
var tm: Node = null
var zoom_mgr: Node = null
var replication_mgr: Node = null  # pushed in via set_replication_manager(), never looked up cross-tree
var template_sim: Node = null     # pushed in via set_template_source(), never looked up cross-tree

# ---------- STORED PER-ATOM/PER-BOND LAYOUT ----------
## Cheap insurance for a future atom-picking pass (Open Question 8,
## deferred but not blocked): {position: Vector2, element: String,
## atom_id: int, nucleotide_slot: int}. Written every frame by
## _rebuild_layout(), read by _draw() — never local-only, so a future hit
## test is "iterate this array," not a rebuild.
var _atom_layout: Array[Dictionary] = []
## {points: Array[Vector2]} — 2 points for a plain chord (the common case:
## every intra-residue bond, and most inter-residue ones), more for a
## curve-following polyline (Option C fix,
## docs/MolecularStructure_BasePairExpansion.md — only inter-residue bonds
## on template strands whose straight-chord length exceeds
## nucleotide_slot_spacing). One shape, one _draw() code path either way —
## see _build_bond_points().
var _bond_layout: Array[Dictionary] = []
## {anchor_a: Vector2, anchor_b: Vector2, count: int, color: Color} — one
## entry per rendered base pair, drawn as `count` parallel dashed lines.
var _h_bond_layout: Array[Dictionary] = []

## Last hysteresis decision. Gates ONLY the draw calls — layout below runs
## unconditionally every frame regardless of this, per the render-mode
## transition decision (Open Question 10): no first-crossing hitch.
var _active: bool = false

## Which "strand:slot" keys are actually rendered in skeletal mode THIS
## frame — backs is_slot_active(), polled live by replication_manager.gd/
## simulation.gd for bug-A occlusion suppression. Rebuilt every frame in
## _rebuild_layout(), never a separately-maintained cache.
var _active_slots: Dictionary = {}

## TEMPORARY diagnostic (docs/MolecularStructure_BasePairExpansion.md, Bug
## D follow-up) — press F9 while the scene is running (before or during
## play) to write a full geometry dump for template/leading/lagging, tied
## to real sequence position, bypassing culling, to
## user://geometry_dump.txt. A raw keypress, not a self-resetting @export
## bool toggled from the Remote/Inspector tab — the first version of this
## used the latter and crashed the debugger connection (remote_debugger_
## peer.cpp "Packet too large" / decode errors): the editor's live property
## sync can re-push a toggled-true value back down before a script's own
## one-shot reset lands, firing the dump every frame instead of once,
## flooding the SAME connection print() also uses. A keypress has no such
## feedback path, and writing to a file instead of print() keeps any output
## volume off the debugger transport entirely regardless. Remove once its
## diagnostic purpose is served, same convention as the earlier removed
## _report_if_bond_too_long().
var _debug_dump_key_was_down: bool = false

## Fold results are cacheable per (slot, strand) — this milestone has
## exactly one operator per residue, so the cache key is effectively "has
## this residue's phosphodiester bond formed yet" (spawned or not), not a
## real step counter. Flagged in the approved plan: if a second DNA-scope
## operator is ever added, this needs to become a real per-step cache.
var _fold_cache: Dictionary = {}  # "leading:12" -> MoleculeTopology

## Fold-cache staleness fix (docs/MolecularStructure_BasePairExpansion.md):
## `_fold_cache` is safe to keep forever WITHIN one simulation run — a
## given "strand:slot" key's base letter never changes mid-run — but
## `simulation.gd`'s `initialize_simulation()` (the single entry point for
## every sequence load, including "load a new sequence" from the popup)
## resets simulation state IN PLACE, never recreating this node, so the
## cache survives across a reload untouched. If a new sequence reuses the
## same slot numbers with a DIFFERENT base letter (different purine/
## pyrimidine class) at some slot, the stale cached topology gets reused —
## and since purines have n9/c8/n7 atoms pyrimidines don't (or vice
## versa), `NitrogenBaseDeriver.derive_base_layout()`'s role lookups fail
## silently and return an empty dict for that residue (confirmed via a
## live F9 dump: `base ring diameter = 0.0000`, `attachment atom
## local=(0,0)`, nonsense H-bond spans). Called from
## `simulation.gd`'s `teardown_simulation()` — the same place every other
## per-sequence dynamic state already gets cleared, so this stays
## consistent with the existing reset lifecycle rather than adding a new
## one.
func clear_fold_cache() -> void:
	_fold_cache.clear()

const OPERATOR_PATH: String = "res://resources/phosphodiester_bond_formation.tres"
var _phosphodiester_operator: ReactionOperator = null
var _operators: Array[ReactionOperator] = []  # [_phosphodiester_operator] — built once in _ready(), typed explicitly so fold()'s Array[ReactionOperator] parameter doesn't need to coerce an untyped literal every frame

## Which strand a given strand's bases hydrogen-bond to when a synthesized
## counterpart EXISTS at that slot. template_bottom/template_top pair with
## EACH OTHER instead, but only ahead of the helicase (see
## _pair_for_slot()'s own header for the corrected condition and why) —
## handled specially there, not in this table, since it's conditional
## rather than fixed.
const PARTNER_STRAND: Dictionary = {
	"leading": "template_top",
	"lagging": "template_bottom",
}

## Which screen-x direction each strand's 5'->3' reading runs, per
## SKILL.md's polarity marker convention ("Bottom template: 3' left, 5'
## right. Top template: 5' left, 3' right. Leading strand: 3' left, 5'
## right. Lagging strand: 5' left, 3' right."): -1 means 5'->3' runs
## right-to-left, +1 means left-to-right. Antiparallel PAIRS always land on
## opposite signs (leading/template_top, lagging/template_bottom,
## template_bottom/template_top) — confirmed consistent across all three
## pairings, not asserted per-pair. Drives apply_strand_direction()'s 180-
## degree rotation (docs/Handout_AntiparallelStrandOrientation.md) — strand
## identity is owned HERE (the renderer), never leaked into RiboseDeriver,
## which stays strand-agnostic (same separation pairing_direction already
## established).
const STRAND_DIRECTION_SIGN: Dictionary = {
	"leading": -1.0,
	"lagging": 1.0,
	"template_bottom": -1.0,
	"template_top": 1.0,
}

## Bug I decoupling (docs/MolecularStructure_BasePairExpansion.md): render-
## only vertical push, in units of tm.molecular_extra_ribbons_gap / 2,
## applied uniformly to every residue of a strand (never conditional on
## pairing state, so the backbone never kinks at a pairing/unpairing
## boundary) — added directly to world_pos before any geometry is derived,
## never to the real simulated position anything else reads. Each strand
## only ever has ONE fixed real neighbor it must clear (leading always
## pairs with template_top; lagging with template_bottom; the two
## templates pair with each other pre-fork/pre-synthesis — see
## PARTNER_STRAND and _pair_for_slot()), so a fixed per-strand push
## direction is enough even though the same strand can be involved in two
## different real pairings over its lifetime (never simultaneously, per
## _pair_for_slot()'s mutually-exclusive logic).
##
## The two templates push apart from EACH OTHER symmetrically (top: -1,
## bottom: +1, i.e. 1 unit of separation each = 1 total unit added between
## them). Leading/lagging push an ADDITIONAL unit further in the same
## direction their own template partner already moved (leading: -2,
## lagging: +2) — mirrors how simulation.gd's own row formulas are built
## (leading_y is defined relative to template_top's row, cascading), so
## the leading-vs-template_top separation grows by the same total amount
## as the template-vs-template separation, not half of it.
const MOLECULAR_ROW_PUSH: Dictionary = {
	"leading": -2.0,
	"template_top": -1.0,
	"template_bottom": 1.0,
	"lagging": 2.0,
}

## Chain-vs-slot-spacing collision fix (docs/MolecularStructure_
## BasePairExpansion.md, follow-up to the same-strand-neighbor direction
## fix — see theme_manager.gd's molecular_extra_slot_spacing doc comment
## for the full "why"). `cluster_center_x` is the CURRENT VIEWPORT's own
## world-space horizontal center (cull_rect's center in _rebuild_layout())
## — deliberately NOT a fixed per-residue value or a cumulative per-slot
## offset, both of which either pop visibly or diverge unboundedly across
## a 57-slot strand. Left at the INF sentinel (every diagnostic-path call
## site), the horizontal push is skipped entirely — there is no live
## camera/viewport in that context, and none of the diagnostic's existing
## clearance checks depend on a NEIGHBOR's pushed position, only the
## residue's own, so omitting it there changes nothing about what those
## checks measure.
##
## PROOF this cannot diverge and is camera-pan-invariant for RELATIVE
## spacing between any two adjacent same-strand residues (verify this
## algebra against real dump numbers before trusting it, same standard as
## everything else — see the doc entry for the live-dump check):
## extra_x(x) = molecular_extra_slot_spacing * (x - center_x) / slot_spacing
## extra_x(x2) - extra_x(x1) = molecular_extra_slot_spacing * (x2 - x1) / slot_spacing
## — center_x cancels out of the DIFFERENCE algebraically regardless of
## its value, so the relative push between two residues depends only on
## their own real spacing (x2 - x1), never on where the camera happens to
## be. This holds identically whether center_x moves because of a pan (x
## translation) or a zoom (cull_rect's size changing) — either way center_x
## is still just a single scalar that cancels in the subtraction.
func _molecular_render_pos(strand: String, world_pos: Vector2, cluster_center_x: float = INF) -> Vector2:
	var push: float = MOLECULAR_ROW_PUSH.get(strand, 0.0) * (tm.molecular_extra_ribbons_gap * 0.5)
	var result: Vector2 = world_pos + Vector2(0.0, push)
	if not is_inf(cluster_center_x):
		var slots_from_center: float = (result.x - cluster_center_x) / _slot_spacing()
		slots_from_center = clamp(slots_from_center, -5.0, 5.0)
		result.x += tm.molecular_extra_slot_spacing * slots_from_center
	return result

func _strand_direction_sign(strand: String) -> float:
	return STRAND_DIRECTION_SIGN.get(strand, 1.0)

## Atom-identity labels (user request, docs/MolecularStructure_
## BasePairExpansion.md, crossing-diagonal investigation follow-up):
## rendering used to label every atom with its bare element symbol only
## ("C", "N", "O", "P") — impossible to tell C3' from C1' from a base-ring
## carbon at a glance, or which oxygen is the 3'-OH vs the one that
## actually bonds the alpha-phosphate. Keyed by the atom's own role SUFFIX
## (topology.atoms' role strings are always "incoming.<suffix>" or
## "chain.<suffix>" — see molecule_topology.gd's add_atom()), so this stays
## a pure display lookup, never touching topology/layout data. Falls back
## to the bare element for anything not in this table (there is nothing
## currently unlisted, but new atoms added later shouldn't silently break
## rendering).
const ATOM_DISPLAY_LABELS: Dictionary = {
	# Ribose ring
	"c1_prime": "C1'", "c2_prime": "C2'", "c3_prime": "C3'", "c4_prime": "C4'", "o4_prime": "O4'",
	# Substituent chain — O3' is the 3'-OH (this residue's own outgoing
	# connection point to the NEXT residue's phosphate); O5' is the one
	# that actually bonds alpha-phosphate (the 5' side).
	"o3_prime": "O3'", "c5_prime": "C5'", "o5_prime": "O5'",
	# Triphosphate (alpha survives the phosphodiester fold; beta/gamma only
	# exist pre-fold, on template-strand/unfolded topologies)
	"alpha_phosphate": "Pα", "alpha_O1": "O1α", "alpha_O2": "O2α", "alpha_beta_bridge_O": "Oαβ",
	"beta_phosphate": "Pβ", "beta_O1": "O1β", "beta_O2": "O2β", "beta_gamma_bridge_O": "Oβγ",
	"gamma_phosphate": "Pγ", "gamma_O1": "O1γ", "gamma_O2": "O2γ", "gamma_O3": "O3γ",
	# Base ring atoms (purine/pyrimidine numbering; already unambiguous
	# without primes since they never collide with ring-atom suffixes)
	"n1": "N1", "c2": "C2", "n3": "N3", "c4": "C4", "c5": "C5", "c6": "C6",
	"n7": "N7", "c8": "C8", "n9": "N9",
	"n6": "N6", "o6": "O6", "n2": "N2", "o2": "O2", "o4": "O4", "c5_methyl": "C5-Me",
}

func _atom_display_label(role: String, element: String) -> String:
	var suffix: String = role
	var dot: int = role.rfind(".")
	if dot != -1:
		suffix = role.substr(dot + 1)
	return ATOM_DISPLAY_LABELS.get(suffix, element)


func _ready() -> void:
	tm = get_node("%ThemeManager")
	zoom_mgr = get_node_or_null("%ZoomManager")
	_phosphodiester_operator = load(OPERATOR_PATH)
	_operators = [_phosphodiester_operator]


func set_replication_manager(mgr: Node) -> void:
	replication_mgr = mgr

func set_template_source(sim: Node) -> void:
	template_sim = sim


## Polled live, every frame, by replication_manager.gd/simulation.gd for
## bug-A occlusion suppression — never cached by the caller, never touched
## by scrub_rebuild() on either side. Reflects exactly what _draw() will
## actually render this frame (both gated by the same _active flag).
func is_slot_active(strand: String, slot: int) -> bool:
	return _active and _active_slots.has("%s:%d" % [strand, slot])

## Whole-strand version of is_slot_active() — true if ANY slot of this
## strand is currently skeletal-active. Used for Line2D backbone
## suppression, which has no per-point alpha, so per-slot granularity
## isn't available there; at the deep zoom skeletal mode requires, this is
## visually equivalent to per-slot suppression since the rest of the line
## is off-screen regardless.
func is_strand_active(strand: String) -> bool:
	if not _active:
		return false
	for key in _active_slots.keys():
		if key.begins_with(strand + ":"):
			return true
	return false


func _process(_delta: float) -> void:
	if replication_mgr == null or zoom_mgr == null or tm == null:
		return
	_active = _compute_active()
	_rebuild_layout()
	queue_redraw()

	var key_down: bool = Input.is_key_pressed(KEY_F9)
	if key_down and not _debug_dump_key_was_down:
		_dump_geometry_diagnostic()
	_debug_dump_key_was_down = key_down


## Hysteresis: enter threshold (higher) crossed going up activates; exit
## threshold (lower) crossed going down deactivates. Gated on actually
## being in free-camera mode — level-based zoom (1-3) never activates
## skeletal rendering, per the CONFIRMED zoom_manager.gd convention: zoom.x
## increases when zooming in, decreases toward a floor when zooming out.
func _compute_active() -> bool:
	if not zoom_mgr.free_camera_mode():
		return false
	var z: float = zoom_mgr.zoom.x
	if _active:
		return z >= tm.molecular_zoom_exit_threshold
	return z >= tm.molecular_zoom_enter_threshold


func _rebuild_layout() -> void:
	_atom_layout.clear()
	_bond_layout.clear()
	_h_bond_layout.clear()
	_active_slots.clear()

	var bond_length: float = tm.molecular_ring_bond_length_ratio * _slot_spacing()
	var cull_rect: Rect2 = _current_viewport_world_rect()
	var cluster_center_x: float = cull_rect.position.x + cull_rect.size.x / 2.0
	var pair_span: float = tm.molecular_pair_span_padding if tm.molecular_pair_span_padding > 0.0 else _dna_ribbons_gap()

	var all_entries: Array[Dictionary] = []
	all_entries.append_array(replication_mgr.get_synthesized_nucleotides())
	if template_sim != null:
		all_entries.append_array(template_sim.get_template_nucleotides())

	# Cheap first pass: every residue's own raw anchor position, regardless
	# of culling — needed so a culled-in residue can still compute a
	# correct pairing_direction toward a partner that might itself be
	# culled out (or simply not looked at again), without a second full
	# fold+layout pass.
	var position_by_key: Dictionary = {}
	var base_type_by_key: Dictionary = {}
	for entry in all_entries:
		var key: String = "%s:%d" % [entry.strand, entry.slot]
		position_by_key[key] = _molecular_render_pos(entry.strand, entry.world_position, cluster_center_x)
		base_type_by_key[key] = entry.base_type

	# Per-residue backbone-link/pairing-anchor world positions, filled only
	# for residues actually rendered this frame — feeds the two
	# cross-residue passes (bug-B backbone bond, hydrogen bonds) below.
	var o3_by_key: Dictionary = {}
	var alpha_by_key: Dictionary = {}
	var anchor_by_key: Dictionary = {}

	for entry in all_entries:
		var world_pos: Vector2 = _molecular_render_pos(entry.strand, entry.world_position, cluster_center_x)
		var padding: float = tm.molecular_cull_bbox_padding + pair_span
		var bbox := Rect2(world_pos - Vector2.ONE * padding, Vector2.ONE * padding * 2.0)
		# CULLING: per-molecule (per-residue) bounding-box only, per
		# MolecularStructure_OpenQuestions_RenderClusterResolution.md
		# (question 9) — padding widened by pair_span in Growth Session 2
		# since a base pair's real extent now spans both strands, not just
		# one ribose ring. nucleotide_field.gd's own max_particles=200 cap
		# exists because this project measured a real FPS drop around
		# ~1,200 immediate-mode glyphs on target hardware — nowhere near
		# this pass's working set (~20-30 atoms x a handful of on-screen
		# residues at deep zoom, four strands). A per-ATOM cull tier is
		# explicitly deferred, not forgotten.
		if not cull_rect.intersects(bbox):
			continue

		var key: String = "%s:%d" % [entry.strand, entry.slot]
		_active_slots[key] = true

		var cache_key: String = key
		var topology: MoleculeTopology = _fold_cache.get(cache_key)
		if topology == null:
			var seed: MoleculeTopology = RiboseDeriver.build_incoming_nucleotide_seed("incoming.", entry.base_type)
			# Every residue is already-incorporated, mature DNA — template
			# strand included (see this file's header correction) — so
			# always fold, never the raw triphosphate seed.
			topology = MoleculeFoldEngine.fold(seed, _operators, 0)
			_fold_cache[cache_key] = topology

		var ring_positions: Dictionary = RiboseDeriver.derive_ring(topology, "incoming.", bond_length)

		# Antiparallel-strand orientation fix
		# (docs/Handout_AntiparallelStrandOrientation.md): the ring was
		# being derived with the SAME fixed local orientation regardless of
		# which way that strand's 5'->3' actually runs on screen — so
		# antiparallel-paired strands (leading/template_top,
		# lagging/template_bottom, and the two templates against each other
		# pre-fork) rendered with identical pucker direction instead of
		# nesting into each other's gaps. Fixed with a 180-degree ROTATION
		# around the C1' anchor (never a mirror — a mirror would silently
		# flip the ring's chirality while visually looking like a fix).
		# Applied here, immediately after deriving the ring and BEFORE
		# substituents are derived from it, so substituents inherit the
		# corrected orientation automatically (they're placed relative to
		# whatever ring shape they're given) rather than needing their own
		# separate rotation. C1' is the pivot, so it stays fixed under the
		# rotation — computed once, below, and valid whether or not the
		# rotation actually ran.
		var c1_id: int = topology.find_by_role("incoming.c1_prime")
		var c1_local: Vector2 = ring_positions.get(c1_id, Vector2.ZERO)
		ring_positions = RiboseDeriver.apply_strand_direction(ring_positions, c1_local, _strand_direction_sign(entry.strand))

		# Computed here, ahead of derive_substituents(), so the chain can use
		# it too (Bug J, below) — was previously computed after, purely for
		# base placement.
		var partner_key: String = _pair_for_slot(entry.strand, entry.slot, base_type_by_key, position_by_key)
		var pairing_direction: Vector2 = Vector2.ZERO
		if partner_key != "" and position_by_key.has(partner_key):
			pairing_direction = position_by_key[partner_key] - world_pos

		# Real same-strand-neighbor direction (supersedes Bug J/L — see
		# docs/MolecularStructureDesign.md's Layout rule + Open Question 10,
		# docs/MolecularStructure_BasePairExpansion.md). C5' bonds toward
		# the more-5' same-strand neighbor, O3' toward the more-3' one —
		# neither has anything to do with pairing_direction (the cross-
		# strand H-bond vector Bug J/L used, confirmed chemically wrong for
		# this purpose). Which physical slot (slot+1 vs slot-1) is more-3'
		# vs more-5' depends on STRAND_DIRECTION_SIGN, same rule
		# _build_backbone_bonds() already implements below — reused here,
		# not re-derived, so the two can't silently disagree.
		var neighbor_sign: float = _strand_direction_sign(entry.strand)
		var next_slot_key: String = "%s:%d" % [entry.strand, entry.slot + 1]
		var prev_slot_key: String = "%s:%d" % [entry.strand, entry.slot - 1]
		var more_3prime_key: String = next_slot_key if neighbor_sign >= 0.0 else prev_slot_key
		var more_5prime_key: String = prev_slot_key if neighbor_sign >= 0.0 else next_slot_key
		var toward_next: Vector2 = Vector2.ZERO
		if position_by_key.has(more_3prime_key):
			toward_next = position_by_key[more_3prime_key] - world_pos
		var toward_previous: Vector2 = Vector2.ZERO
		if position_by_key.has(more_5prime_key):
			toward_previous = position_by_key[more_5prime_key] - world_pos
		var substituent_positions: Dictionary = RiboseDeriver.derive_substituents(topology, "incoming.", ring_positions, bond_length, toward_next, toward_previous)

		var local_positions: Dictionary = {}
		for id in ring_positions:
			local_positions[id] = ring_positions[id]
		for id in substituent_positions:
			local_positions[id] = substituent_positions[id]

		# Bug-C fix: anchor at C1', not the ring's centroid. A point-like
		# bead circle centred at world_pos looked fine; a ring with real
		# spatial extent centred there oversails past wherever the
		# existing hydrogen-bond line geometry actually terminates.
		var anchor_offset: Vector2 = c1_local

		# NOTE: base placement is NOT subject to the ring rotation above —
		# pairing_direction is already derived from real world positions
		# (always points at the actual partner, whichever strand this is),
		# so it's correct regardless of strand identity on its own. Rotating
		# it again here would point the base AWAY from its real partner for
		# direction_sign < 0 strands — a double-transform bug, not a fix.
		#
		# avoid_points (docs/MolecularStructure_BasePairExpansion.md, Bug D
		# "ribose sits on its own base" follow-up): the ribose's own
		# substituent chain, already computed above (substituent_positions)
		# — passed through so derive_base_layout() can pick a rotation that
		# clears it, without this file duplicating any of that search logic.
		var base_positions: Dictionary = NitrogenBaseDeriver.derive_base_layout(topology, "incoming.", entry.base_type, c1_local, pairing_direction, bond_length, ring_positions.values() + substituent_positions.values())
		for id in base_positions:
			local_positions[id] = base_positions[id]

		for atom in topology.atoms:
			if not local_positions.has(atom.id):
				continue
			var world: Vector2 = world_pos + (local_positions[atom.id] - anchor_offset)
			_atom_layout.append({
				position = world,
				element = atom.element,
				label = _atom_display_label(atom.role, atom.element),
				atom_id = atom.id,
				nucleotide_slot = entry.slot,
			})

		for bond in topology.bonds:
			if not local_positions.has(bond.a) or not local_positions.has(bond.b):
				continue
			_bond_layout.append({
				points = [
					world_pos + (local_positions[bond.a] - anchor_offset),
					world_pos + (local_positions[bond.b] - anchor_offset),
				],
			})

		var o3_id: int = topology.find_by_role("incoming.o3_prime")
		var alpha_id: int = topology.find_by_role("incoming.alpha_phosphate")
		if local_positions.has(o3_id):
			o3_by_key[key] = world_pos + (local_positions[o3_id] - anchor_offset)
		if local_positions.has(alpha_id):
			alpha_by_key[key] = world_pos + (local_positions[alpha_id] - anchor_offset)
		var anchor_suffix: String = NitrogenBaseDeriver.pairing_anchor_suffix(entry.base_type)
		var anchor_id: int = topology.find_by_role("incoming." + anchor_suffix)
		if local_positions.has(anchor_id):
			anchor_by_key[key] = world_pos + (local_positions[anchor_id] - anchor_offset)

	_build_backbone_bonds(o3_by_key, alpha_by_key)
	_build_hydrogen_bonds(anchor_by_key, base_type_by_key, position_by_key)


## Bug-B fix: connects residue N's own already-positioned O3' to residue
## N+1's own already-positioned alpha-phosphate, WITHIN the same strand —
## real computed positions from each residue's independent fold+derive
## call, never the unpositioned chain.o3_prime stub (which stays in the
## topology only so bonds_formed resolves per-residue chemistry, never
## looked up for rendering). Only drawn when BOTH sides are rendered this
## frame — at the cull boundary, a momentarily-missing link bond is an
## accepted simplification of coarse per-molecule culling, not a
## correctness bug.
func _build_backbone_bonds(o3_by_key: Dictionary, alpha_by_key: Dictionary) -> void:
	# Direction fix (Claude Desktop chemistry review follow-up to
	# docs/Handout_AntiparallelStrandOrientation.md): connecting slot's O3'
	# to slot+1's alpha-phosphate silently assumed increasing slot index
	# always means the chemical 5'->3' direction. True for sign >= 0
	# strands (lagging/template_top, 5' at LOW slot index) but backwards
	# for sign < 0 strands (leading/template_bottom, 5' at HIGH slot
	# index, per SKILL.md's polarity table) — there, slot+1 is the more-5'
	# residue and slot is the more-3' one, so the roles swap. The rule
	# itself never changes: the more-5' residue's O3' always bonds to the
	# more-3' residue's alpha-phosphate (see
	# resources/phosphodiester_bond_formation.tres's own bonds_formed
	# direction) — only WHICH slot plays which role flips with strand
	# direction. Does not touch the ring/substituent rotation fix itself
	# (apply_strand_direction()), which is confirmed correct and untouched.
	#
	# Option C fix (docs/MolecularStructure_BasePairExpansion.md): the
	# temporary diagnostic print that used to live here (removed — its
	# purpose, finding the mechanism, is fulfilled) confirmed the "long
	# diagonal" was never a stale-position bug — it's a straight chord
	# crossing the template rail's steep bonded->unzipped transition. A
	# covalent phosphodiester bond does not stretch, so the fix is
	# _build_bond_points() below, not the connection logic here. The
	# threshold it used to just flag is now reused as the actual
	# straight-chord/curve-following mode switch.
	var mode_switch_threshold: float = _slot_spacing()

	for strand in ["leading", "lagging", "template_bottom", "template_top"]:
		var sign: float = _strand_direction_sign(strand)
		for key in o3_by_key.keys():
			if not key.begins_with(strand + ":"):
				continue
			var slot: int = int(key.split(":")[1])
			var next_key: String = "%s:%d" % [strand, slot + 1]
			if sign >= 0.0:
				if alpha_by_key.has(next_key):
					var from_pos: Vector2 = o3_by_key[key]
					var to_pos: Vector2 = alpha_by_key[next_key]
					_bond_layout.append({points = _build_bond_points(strand, from_pos, to_pos, mode_switch_threshold)})
			else:
				if o3_by_key.has(next_key) and alpha_by_key.has(key):
					var from_pos: Vector2 = o3_by_key[next_key]
					var to_pos: Vector2 = alpha_by_key[key]
					_bond_layout.append({points = _build_bond_points(strand, from_pos, to_pos, mode_switch_threshold)})

## Option C fix (docs/MolecularStructure_BasePairExpansion.md): a
## covalent phosphodiester backbone bond does not stretch — helicase
## unwinding breaks hydrogen bonds between strands, never backbone bonds
## within one. A straight chord that visibly elongates through the fork's
## steep bonded->unzipped transition teaches something false about what's
## actually flexing (the curve's bend, not the covalent backbone).
## Suppressing the bond past threshold is equally wrong the other way (a
## gap reads as "bond broken here"). Curve-following is the only option
## that doesn't teach something incorrect, and it isn't inventing new
## geometry — the curve being sampled already exists and is already
## correct (_rebuild_rail()'s control points, confirmed monotonic during
## the investigation); this only fixes the renderer's approximation.
##
## Below threshold: cheap straight chord — correct-enough for a near-flat
## span, and the common case for nearly every bond in the structure.
## Above threshold: only possible on template strands (the only ones with
## an actual rail curve to bend around — leading/lagging use flat
## algebraic Y and never trigger this), sample molecular_curve_sample_count
## points along the real curve. Each sample is curve_y(x) + an
## interpolated vertical offset (each real endpoint's own known offset
## from the raw curve — captures dna_ribbons_gap/ring-substituent/wobble
## without re-deriving the full atom-layout pipeline at every sample), then
## the first/last points are forced back to the exact real endpoints so the
## polyline stays continuous with the rest of the structure regardless of
## any interpolation rounding.
func _build_bond_points(strand: String, from_pos: Vector2, to_pos: Vector2, threshold: float) -> Array:
	if from_pos.distance_to(to_pos) <= threshold:
		return [from_pos, to_pos]
	if template_sim == null or (strand != "template_bottom" and strand != "template_top"):
		return [from_pos, to_pos]

	var sample_count: int = max(2, tm.molecular_curve_sample_count)
	var offset_from: float = from_pos.y - template_sim.sample_template_curve_y(strand, from_pos.x)
	var offset_to: float = to_pos.y - template_sim.sample_template_curve_y(strand, to_pos.x)

	var points: Array = []
	for i in range(sample_count):
		var t: float = float(i) / float(sample_count - 1)
		var x: float = lerp(from_pos.x, to_pos.x, t)
		var curve_y: float = template_sim.sample_template_curve_y(strand, x)
		var offset: float = lerp(offset_from, offset_to, t)
		points.append(Vector2(x, curve_y + offset))
	points[0] = from_pos
	points[points.size() - 1] = to_pos
	return points


## Which strand+slot key this residue's base pairs with THIS frame, or ""
## if no partner. leading/lagging always pair with their fixed template
## counterpart (PARTNER_STRAND). template_bottom/template_top pair with
## EACH OTHER, but only ahead of the helicase — matched against
## `template_sim.helicase_x` directly, the SAME value simulation.gd's own
## `template_hydrogen_bonds[i].visible = (world_x >= helicase_x)` already
## uses (see simulation.gd's per-frame template rendering).
##
## Correction (live screenshot at atom zoom, ghost cyan H-bond dashes
## visible on template residues already past the helicase, toggling
## on/off with a single camera-zoom tick): this used to check "does
## leading or lagging have a synthesized base at this slot yet" instead —
## NOT the same condition, since `polymerase_x_offset_slots` (simulation.gd,
## default 4) keeps both polymerases trailing several slots BEHIND the
## helicase. That left a real gap — already unwound by the helicase, not
## yet reached by either polymerase — where this function kept reporting
## the two templates as still paired, drawing an H-bond between two
## strands that are no longer actually in contact. The doc comment
## previously here claimed this "mirrors" simulation.gd's own rule; it
## didn't — it used a different, laxer proxy that happened to agree only
## once synthesis caught all the way up. The zoom-tick flicker was this
## gap-zone pair's cull-boundary sensitivity (only drawn when both
## residues' anchors survive this frame's cull rect), not a separate bug —
## fixed at the root by switching to the real, authoritative condition.
func _pair_for_slot(strand: String, slot: int, base_type_by_key: Dictionary, position_by_key: Dictionary) -> String:
	if PARTNER_STRAND.has(strand):
		var partner: String = "%s:%d" % [PARTNER_STRAND[strand], slot]
		return partner if base_type_by_key.has(partner) else ""
	if strand == "template_bottom" or strand == "template_top":
		# A template strand's real partner, once its complementary slot has
		# been synthesized, is that synthesized strand (leading for
		# template_top, lagging for template_bottom) — the biological
		# partner from that point forward, not the OTHER template strand,
		# which the helicase has already permanently unwound it from.
		# Mirrors the leading/lagging branch's own PARTNER_STRAND lookup
		# above, just in the reverse direction — checked FIRST, before the
		# other-template fallback below (only ever relevant pre-fork, when
		# nothing has synthesized yet).
		var synth_strand: String = "leading" if strand == "template_top" else "lagging"
		var synth_key: String = "%s:%d" % [synth_strand, slot]
		if base_type_by_key.has(synth_key):
			return synth_key
		var self_key: String = "%s:%d" % [strand, slot]
		if template_sim != null and position_by_key.has(self_key):
			var world_x: float = position_by_key[self_key].x
			if world_x < template_sim.helicase_x:
				return ""  # already past the helicase — no longer paired with the other template strand
		var other: String = "template_top:%d" % slot if strand == "template_bottom" else "template_bottom:%d" % slot
		return other if base_type_by_key.has(other) else ""
	return ""


## Builds one dashed-line group per rendered base pair, count sourced from
## NitrogenBaseDeriver.hydrogen_bond_count() (single source of truth, also
## used by replication_manager.gd's bead-glyph H-bond spawning — never
## recomputed independently). Only drawn when BOTH sides of a pair are
## rendered this frame, same accepted-simplification rule as the backbone
## bonds above.
func _build_hydrogen_bonds(anchor_by_key: Dictionary, base_type_by_key: Dictionary, position_by_key: Dictionary) -> void:
	var seen: Dictionary = {}
	for key in anchor_by_key.keys():
		if seen.has(key):
			continue
		var parts: PackedStringArray = key.split(":")
		var strand: String = parts[0]
		var slot: int = int(parts[1])
		var partner_key: String = _pair_for_slot(strand, slot, base_type_by_key, position_by_key)
		if partner_key == "" or not anchor_by_key.has(partner_key):
			continue
		seen[key] = true
		seen[partner_key] = true

		var base_type: String = base_type_by_key.get(key, "A")
		var count: int = NitrogenBaseDeriver.hydrogen_bond_count(base_type)
		var color: Color = tm.cg_bond_color if (base_type == "C" or base_type == "G") else tm.at_bond_color
		_h_bond_layout.append({
			anchor_a = anchor_by_key[key],
			anchor_b = anchor_by_key[partner_key],
			count = count,
			color = color,
		})


# ==========================================
# TEMPORARY DIAGNOSTIC DUMP (docs/MolecularStructure_BasePairExpansion.md,
# Bug D follow-up) — see _debug_dump_key_was_down's own comment above (F9
# trigger, writes to user://geometry_dump.txt). Builds geometry directly
# from RiboseDeriver/NitrogenBaseDeriver, independent of
# _rebuild_layout()'s cull_rect, so "first N pairs" means the same thing
# regardless of camera position at trigger time.
# ==========================================

const _DIAG_PAIR_COUNT: int = 10
const _DIAG_RING_ROLE_LABELS: Dictionary = {
	"c1_prime": "C1'", "c2_prime": "C2'", "c3_prime": "C3'",
	"c4_prime": "C4'", "o4_prime": "O4'",
}
## Ring-backbone suffixes plus every exocyclic substituent suffix
## _place_base_substituents() (nitrogen_base_deriver.gd) can place — o2/n4
## (C), o2/o4/c5_methyl (T), n6 (A), o6/n2 (G). Diagnostic-only: these
## atoms were already present in base_positions and already counted toward
## base_diameter (confirmed: thymine's printed diameter, 43.2, already
## reflects o4/c5_methyl even before this list named them) — this just
## makes them visible in the printed block. The existing per-suffix
## `if base_positions.has(id)` guard below already silently skips any
## suffix absent from a given base (same mechanism that already lets
## purine-only n7/c8/n9 coexist here with pyrimidine-only suffixes), so
## listing every base's substituents in one shared array is safe.
const _DIAG_BASE_ROLE_SUFFIXES: Array[String] = ["n1", "c2", "n3", "c4", "c5", "c6", "n7", "c8", "n9", "o2", "o4", "n4", "n6", "n2", "o6", "c5_methyl"]

const _DIAG_OUTPUT_PATH: String = "user://geometry_dump.txt"

## Writes (appends) to user://geometry_dump.txt instead of print() —
## deliberately NOT going through the remote debugger connection. Console
## only gets one short breadcrumb line per dump, never the full content.
func _dump_geometry_diagnostic() -> void:
	var out: Array = []
	var bond_length: float = tm.molecular_ring_bond_length_ratio * _slot_spacing()
	out.append("=== GEOMETRY DIAGNOSTIC DUMP (%s) ===" % Time.get_datetime_string_from_system())
	out.append("nucleotide_slot_spacing = %s" % _slot_spacing())
	out.append("dna_ribbons_gap = %s" % _dna_ribbons_gap())
	out.append("molecular_extra_ribbons_gap = %s  (render-only push, added per strand — see MOLECULAR_ROW_PUSH)" % tm.molecular_extra_ribbons_gap)
	out.append("molecular_ring_bond_length_ratio = %s" % tm.molecular_ring_bond_length_ratio)
	out.append("bond_length = %s" % bond_length)
	out.append("LIFECYCLE: fold TOPOLOGY (atoms/bonds, MoleculeFoldEngine.fold) is cached forever per \"strand:slot\" key in _fold_cache once first built, for every strand including template — never invalidated. Ring/base LOCAL GEOMETRY (RiboseDeriver.derive_ring/apply_strand_direction, NitrogenBaseDeriver.derive_base_layout) is recomputed FRESH every _process()/_rebuild_layout() call, every frame, for every strand including template — never cached. Any template-vs-leading/lagging difference found below is therefore numerical (real sequence/position data), not a staleness artifact.")

	var template_entries: Array[Dictionary] = template_sim.get_template_nucleotides() if template_sim != null else []
	var synth_entries: Array[Dictionary] = replication_mgr.get_synthesized_nucleotides() if replication_mgr != null else []

	# Same-strand-neighbor position lookup (real same-strand-neighbor
	# direction fix, docs/MolecularStructureDesign.md's Layout rule + Open
	# Question 10) — mirrors _rebuild_layout()'s own position_by_key, built
	# once here from every entry across every strand so _derive_full_residue()
	# can look up a real previous/next same-strand neighbor exactly like the
	# live renderer does, not a diagnostic-only approximation.
	var diag_position_by_key: Dictionary = {}
	for e in template_entries:
		diag_position_by_key["%s:%d" % [e.strand, e.slot]] = _molecular_render_pos(e.strand, e.world_position)
	for e in synth_entries:
		diag_position_by_key["%s:%d" % [e.strand, e.slot]] = _molecular_render_pos(e.strand, e.world_position)

	_dump_pairing(out, "template_top", "template_bottom", template_entries, template_entries, bond_length, diag_position_by_key, synth_entries)
	_dump_pairing(out, "leading", "template_top", synth_entries, template_entries, bond_length, diag_position_by_key)
	_dump_pairing(out, "lagging", "template_bottom", synth_entries, template_entries, bond_length, diag_position_by_key)

	# Full-sequence same-letter scan (docs/MolecularStructure_
	# BasePairExpansion.md, Bug E follow-up): the per-pairing dump above
	# only ever samples the first _DIAG_PAIR_COUNT slots. A same-letter
	# report at a slot outside that range would be invisible to it. This
	# scans EVERY slot present in each pairing and flags any where top and
	# bottom show the identical letter (never valid Watson-Crick), plus
	# prints the two full sequences so they can be eyeballed directly
	# against a screenshot.
	out.append("\n\n=== FULL-SEQUENCE SAME-LETTER SCAN (all slots, not just first 10) ===")
	_scan_pairing_for_same_letter(out, "template_top", "template_bottom", template_entries, template_entries)
	_scan_pairing_for_same_letter(out, "leading", "template_top", synth_entries, template_entries)
	_scan_pairing_for_same_letter(out, "lagging", "template_bottom", synth_entries, template_entries)

	out.append("=== END DUMP ===\n")

	var existing: String = ""
	if FileAccess.file_exists(_DIAG_OUTPUT_PATH):
		var read_f: FileAccess = FileAccess.open(_DIAG_OUTPUT_PATH, FileAccess.READ)
		if read_f != null:
			existing = read_f.get_as_text()
			read_f.close()
	var write_f: FileAccess = FileAccess.open(_DIAG_OUTPUT_PATH, FileAccess.WRITE)
	if write_f != null:
		write_f.store_string(existing + "\n".join(out) + "\n")
		write_f.close()
		print("[GEOMETRY DIAG] dump written to %s" % ProjectSettings.globalize_path(_DIAG_OUTPUT_PATH))
	else:
		print("[GEOMETRY DIAG] FAILED to open %s for writing" % _DIAG_OUTPUT_PATH)


## Scans EVERY slot present in this pairing (not just the first
## _DIAG_PAIR_COUNT) and reports any where top and bottom show the
## identical letter — never valid Watson-Crick, so any hit here is a real
## bug regardless of which slot range a screenshot happened to show.
## Also prints both full sequences (in slot order) so they can be
## eyeballed directly against a screenshot.
func _scan_pairing_for_same_letter(out: Array, top_strand: String, bottom_strand: String, top_source: Array[Dictionary], bottom_source: Array[Dictionary]) -> void:
	var top_by_slot: Dictionary = {}
	for e in top_source:
		if e.strand == top_strand:
			top_by_slot[e.slot] = e.base_type
	var bottom_by_slot: Dictionary = {}
	for e in bottom_source:
		if e.strand == bottom_strand:
			bottom_by_slot[e.slot] = e.base_type

	out.append("\n--- %s (top) / %s (bottom) — %d top slots, %d bottom slots ---" % [top_strand, bottom_strand, top_by_slot.size(), bottom_by_slot.size()])
	if top_by_slot.is_empty() or bottom_by_slot.is_empty():
		out.append("  (nothing to scan yet)")
		return

	var max_slot: int = 0
	for s in top_by_slot.keys():
		max_slot = max(max_slot, s)
	for s in bottom_by_slot.keys():
		max_slot = max(max_slot, s)

	var top_seq: String = ""
	var bottom_seq: String = ""
	var violations: Array = []
	for slot in range(max_slot + 1):
		var t: String = top_by_slot.get(slot, "-")
		var b: String = bottom_by_slot.get(slot, "-")
		top_seq += t
		bottom_seq += b
		if t != "-" and b != "-" and t == b:
			violations.append(slot)

	out.append("  top    sequence (slot 0..%d): %s" % [max_slot, top_seq])
	out.append("  bottom sequence (slot 0..%d): %s" % [max_slot, bottom_seq])
	if violations.is_empty():
		out.append("  SAME-LETTER VIOLATIONS: none — every paired slot has two different letters.")
	else:
		out.append("  SAME-LETTER VIOLATIONS at %d slot(s): %s" % [violations.size(), str(violations)])


## unzip_check_entries, if non-empty: replicates _pair_for_slot()'s real
## unzip logic (docs/MolecularStructure_BasePairExpansion.md, Bug F
## unpaired-residue follow-up) — a template_top/template_bottom slot is
## ONLY really paired with its opposite template if NEITHER leading NOR
## lagging has a base at that slot yet; once either exists, the real
## renderer treats that template residue as UNPAIRED (pairing_direction =
## ZERO, triggering the chain-aware fallback), regardless of whether the
## opposite template residue still physically exists. The old version of
## this function ignored that and force-paired every slot where BOTH
## template entries existed, silently computing geometry from a fake
## pairing_direction the real renderer never uses once replication has
## started — confirmed to give misleading "closest approach" numbers, not
## just a misleading H-bond span (the previously-known issue). Slots that
## are really unpaired are now dumped through the SAME unpaired code path
## as leading/lagging's own unpaired case, so the numbers here always
## match what actually renders.
func _dump_pairing(out: Array, top_strand: String, bottom_strand: String, top_source: Array[Dictionary], bottom_source: Array[Dictionary], bond_length: float, position_by_key: Dictionary, unzip_check_entries: Array[Dictionary] = []) -> void:
	var top_by_slot: Dictionary = {}
	for e in top_source:
		if e.strand == top_strand:
			top_by_slot[e.slot] = e
	var bottom_by_slot: Dictionary = {}
	for e in bottom_source:
		if e.strand == bottom_strand:
			bottom_by_slot[e.slot] = e

	# Matches _pair_for_slot()'s corrected real condition (docs/
	# MolecularStructure_BasePairExpansion.md, "ghost H-bond past helicase"
	# fix): a slot is unzipped once the helicase has physically passed it,
	# not merely once leading/lagging synthesis has caught up — those are
	# different positions (polymerase_x_offset_slots keeps synthesis
	# several slots behind the helicase), and the old leading/lagging-
	# existence-only check here would under-report unzipped slots in that
	# gap, same as the renderer bug it was written to catch.
	var unzipped_slots: Dictionary = {}
	if not unzip_check_entries.is_empty():
		for e in unzip_check_entries:
			if e.strand == "leading" or e.strand == "lagging":
				unzipped_slots[e.slot] = true
	# Helicase-position check only applies to the genuine template_top-vs-
	# template_bottom self-pairing (mirrors _pair_for_slot()'s real branch
	# order: PARTNER_STRAND.has(strand) — leading/lagging — returns
	# unconditionally BEFORE ever reaching the helicase check, so it must
	# never run for a leading/template_top or lagging/template_bottom call).
	# Applying it there too force-marks every slot "unzipped" once the
	# helicase has passed the whole strand (e.g. a finished simulation),
	# corrupting those sections into all-UNPAIRED even though they're real,
	# synthesized Watson-Crick pairs the live renderer draws correctly.
	var is_template_self_pairing: bool = (top_strand == "template_top" and bottom_strand == "template_bottom") or (top_strand == "template_bottom" and bottom_strand == "template_top")
	if template_sim != null and is_template_self_pairing:
		for e in top_by_slot.values():
			if e.world_position.x < template_sim.helicase_x:
				unzipped_slots[e.slot] = true
		for e in bottom_by_slot.values():
			if e.world_position.x < template_sim.helicase_x:
				unzipped_slots[e.slot] = true

	out.append("\n--- PAIRING: %s (top) / %s (bottom) ---" % [top_strand, bottom_strand])
	if top_by_slot.is_empty() or bottom_by_slot.is_empty():
		out.append("  (no paired residues yet — %s has %d entries, %s has %d entries)" % [top_strand, top_by_slot.size(), bottom_strand, bottom_by_slot.size()])
		return

	var printed: int = 0
	var slot: int = 0
	var max_slot_scan: int = 5000
	while printed < _DIAG_PAIR_COUNT and slot < max_slot_scan:
		if top_by_slot.has(slot) and bottom_by_slot.has(slot):
			var top_entry: Dictionary = top_by_slot[slot]
			var bottom_entry: Dictionary = bottom_by_slot[slot]
			var really_paired: bool = not unzipped_slots.has(slot)

			if not really_paired:
				# Real renderer treats BOTH sides as unpaired here — dump each
				# independently through the unpaired (ZERO pairing_direction)
				# path, no fake partner.
				printed += 1
				var top_r_u: Dictionary = _derive_full_residue(top_entry, _molecular_render_pos(top_entry.strand, top_entry.world_position), bond_length, position_by_key)
				var bottom_r_u: Dictionary = _derive_full_residue(bottom_entry, _molecular_render_pos(bottom_entry.strand, bottom_entry.world_position), bond_length, position_by_key)
				out.append("\n[PAIR %d | sequence: %s%s | UNPAIRED — unzipped, real renderer uses fallback direction, not shown as a real pair]" % [printed, top_entry.base_type, bottom_entry.base_type])
				_write_residue_block(out, "TOP (unpaired)", top_r_u)
				_write_residue_block(out, "BOTTOM (unpaired)", bottom_r_u)
				out.append("OVERLAP CHECK (own-base only, no real cross-strand pairing to check):")
				out.append("  top    substituent chain closest approach to OWN base = %.4f  (chain reaches %.4f from C1')" % [top_r_u.chain_closest_to_own_base, top_r_u.chain_far_from_c1])
				out.append("  bottom substituent chain closest approach to OWN base = %.4f  (chain reaches %.4f from C1')" % [bottom_r_u.chain_closest_to_own_base, bottom_r_u.chain_far_from_c1])
				slot += 1
				continue

			printed += 1
			var top_r: Dictionary = _derive_full_residue(top_entry, _molecular_render_pos(bottom_entry.strand, bottom_entry.world_position), bond_length, position_by_key)
			var bottom_r: Dictionary = _derive_full_residue(bottom_entry, _molecular_render_pos(top_entry.strand, top_entry.world_position), bond_length, position_by_key)

			out.append("\n[PAIR %d | sequence: %s%s]" % [printed, top_entry.base_type, bottom_entry.base_type])
			_write_residue_block(out, "TOP", top_r)
			var span: float = top_r.anchor_world.distance_to(bottom_r.anchor_world)
			out.append("H-BOND:")
			out.append("  anchor-to-anchor world distance = %.4f" % span)
			out.append("  dna_ribbons_gap for reference    = %s" % _dna_ribbons_gap())
			_write_residue_block(out, "BOTTOM", bottom_r)

			var top_closest_to_bottom_center: float = _closest_world_distance(top_r.base_world_positions.values(), bottom_r.world_pos)
			var bottom_closest_to_top_center: float = _closest_world_distance(bottom_r.base_world_positions.values(), top_r.world_pos)
			out.append("OVERLAP CHECK:")
			out.append("  top base ring closest-atom -> bottom strand center    = %.4f" % top_closest_to_bottom_center)
			out.append("  bottom base ring closest-atom -> top strand center    = %.4f" % bottom_closest_to_top_center)
			out.append("  top    ribose-to-own-base (attachment -> ring center) = %.4f  (base ring diameter = %.4f)" % [top_r.attachment_to_ring_center, top_r.base_diameter])
			out.append("  bottom ribose-to-own-base (attachment -> ring center) = %.4f  (base ring diameter = %.4f)" % [bottom_r.attachment_to_ring_center, bottom_r.base_diameter])
			out.append("  top    substituent chain closest approach to OWN base = %.4f  (chain reaches %.4f from C1')" % [top_r.chain_closest_to_own_base, top_r.chain_far_from_c1])
			out.append("  bottom substituent chain closest approach to OWN base = %.4f  (chain reaches %.4f from C1')" % [bottom_r.chain_closest_to_own_base, bottom_r.chain_far_from_c1])
		slot += 1


## Rebuilds one residue's full local+world geometry directly (same calls
## _rebuild_layout() makes), independent of culling. Returns everything the
## dump format needs, keyed for direct printing.
func _derive_full_residue(entry: Dictionary, partner_world_pos: Vector2, bond_length: float, position_by_key: Dictionary = {}) -> Dictionary:
	var strand: String = entry.strand
	var slot: int = entry.slot
	var base_type: String = entry.base_type
	var world_pos: Vector2 = _molecular_render_pos(strand, entry.world_position)

	var cache_key: String = "%s:%d" % [strand, slot]
	var topology: MoleculeTopology = _fold_cache.get(cache_key)
	if topology == null:
		var seed: MoleculeTopology = RiboseDeriver.build_incoming_nucleotide_seed("incoming.", base_type)
		topology = MoleculeFoldEngine.fold(seed, _operators, 0)
		_fold_cache[cache_key] = topology

	var ring_positions: Dictionary = RiboseDeriver.derive_ring(topology, "incoming.", bond_length)
	var c1_id: int = topology.find_by_role("incoming.c1_prime")
	var c1_local: Vector2 = ring_positions.get(c1_id, Vector2.ZERO)
	ring_positions = RiboseDeriver.apply_strand_direction(ring_positions, c1_local, _strand_direction_sign(strand))

	var pairing_direction: Vector2 = partner_world_pos - world_pos

	# Real same-strand-neighbor direction (supersedes Bug J/L — see
	# docs/MolecularStructureDesign.md's Layout rule + Open Question 10).
	# Mirrors _rebuild_layout()'s identical logic exactly, so the diagnostic
	# dump reports the same geometry the live renderer actually draws.
	var neighbor_sign: float = _strand_direction_sign(strand)
	var next_slot_key: String = "%s:%d" % [strand, slot + 1]
	var prev_slot_key: String = "%s:%d" % [strand, slot - 1]
	var more_3prime_key: String = next_slot_key if neighbor_sign >= 0.0 else prev_slot_key
	var more_5prime_key: String = prev_slot_key if neighbor_sign >= 0.0 else next_slot_key
	var toward_next: Vector2 = Vector2.ZERO
	if position_by_key.has(more_3prime_key):
		toward_next = position_by_key[more_3prime_key] - world_pos
	var toward_previous: Vector2 = Vector2.ZERO
	if position_by_key.has(more_5prime_key):
		toward_previous = position_by_key[more_5prime_key] - world_pos
	var substituent_positions: Dictionary = RiboseDeriver.derive_substituents(topology, "incoming.", ring_positions, bond_length, toward_next, toward_previous)

	var base_positions: Dictionary = NitrogenBaseDeriver.derive_base_layout(topology, "incoming.", base_type, c1_local, pairing_direction, bond_length, ring_positions.values() + substituent_positions.values())

	var ring_named: Dictionary = {}
	for suffix in _DIAG_RING_ROLE_LABELS:
		var id: int = topology.find_by_role("incoming." + suffix)
		if ring_positions.has(id):
			ring_named[_DIAG_RING_ROLE_LABELS[suffix]] = ring_positions[id]

	var base_named: Dictionary = {}
	for suffix in _DIAG_BASE_ROLE_SUFFIXES:
		var id: int = topology.find_by_role("incoming." + suffix)
		if base_positions.has(id):
			base_named[suffix.to_upper()] = base_positions[id]

	var is_purine: bool = base_type == "A" or base_type == "G"
	var attachment_suffix: String = "n9" if is_purine else "n1"
	var attachment_id: int = topology.find_by_role("incoming." + attachment_suffix)
	var attachment_local: Vector2 = base_positions.get(attachment_id, Vector2.ZERO)

	var anchor_suffix: String = NitrogenBaseDeriver.pairing_anchor_suffix(base_type)
	var anchor_id: int = topology.find_by_role("incoming." + anchor_suffix)
	var anchor_local: Vector2 = base_positions.get(anchor_id, Vector2.ZERO)
	var anchor_world: Vector2 = world_pos + (anchor_local - c1_local)

	var ring_centroid: Vector2 = _centroid(ring_positions.values())
	var base_world_positions: Dictionary = {}
	for id in base_positions:
		base_world_positions[id] = world_pos + (base_positions[id] - c1_local)

	# Substituent chain (docs/MolecularStructure_BasePairExpansion.md, Bug D
	# follow-up): O3'/C5'/O5'/alpha-phosphate — placed radially OUTWARD from
	# C4' by RiboseDeriver.derive_substituents(), chained (C5' = C4' +
	# outward*bond_length, O5' = C5' + outward*bond_length, alpha_phosphate
	# = O5' + outward*bond_length) — 3 full bond_lengths beyond the ring
	# itself, in the SAME "outward" direction every time. Not covered by
	# the earlier "ribose ring diameter" measurement (ring atoms only) —
	# this chain can reach much further than the bare ring, and its
	# direction is tied to ring rotation (sign) same as the ring itself,
	# independently of the base's own pairing-direction-based rotation.
	const CHAIN_ROLE_LABELS: Dictionary = {
		"o3_prime": "O3'", "c5_prime": "C5'", "o5_prime": "O5'", "alpha_phosphate": "alpha-P",
	}
	var chain_named: Dictionary = {}
	for suffix in CHAIN_ROLE_LABELS:
		var id: int = topology.find_by_role("incoming." + suffix)
		if substituent_positions.has(id):
			chain_named[CHAIN_ROLE_LABELS[suffix]] = substituent_positions[id]
	var chain_far_from_c1: float = 0.0
	for p in substituent_positions.values():
		chain_far_from_c1 = max(chain_far_from_c1, p.distance_to(c1_local))
	var chain_closest_to_own_base: float = INF
	for p in substituent_positions.values():
		for bp in base_positions.values():
			chain_closest_to_own_base = min(chain_closest_to_own_base, p.distance_to(bp))

	# World-space per-group coordinates (CQA follow-up — user asked whether
	# the dump discriminates which molecule/group an atom belongs to: yes,
	# ring_named/base_named/chain_named already do — but only LOCAL coords
	# were ever printed, forcing a manual local->world conversion by hand
	# to see what's actually overlapping on screen. Added directly here so
	# "is X too close to Y" is readable off the dump without doing that
	# conversion yourself.
	var ring_world_named: Dictionary = {}
	for role_label in ring_named:
		ring_world_named[role_label] = world_pos + (ring_named[role_label] - c1_local)
	var base_world_named: Dictionary = {}
	for role_label in base_named:
		base_world_named[role_label] = world_pos + (base_named[role_label] - c1_local)
	var chain_world_named: Dictionary = {}
	for role_label in chain_named:
		chain_world_named[role_label] = world_pos + (chain_named[role_label] - c1_local)

	# Direction check (CQA follow-up, docs/MolecularStructure_
	# BasePairExpansion.md, Bug F re-opened): the anchor-fixed clearance
	# search (Bug F correction) pins the ATTACHMENT atom toward
	# pairing_direction but rotates the rest of the ring FREELY to
	# maximize clearance from the ribose's own substituent chain — nothing
	# constrains the ANCHOR atom (the one actually used to aim the H-bond
	# at the real partner) to stay anywhere near that direction. This dot
	# product is strictly diagnostic: >0 means the anchor is at least on
	# the correct side of C1' (facing the partner); <0 means the search
	# picked a rotation that points the anchor AWAY from the real partner
	# entirely — the base's own chain and the partner happen to sit on the
	# same general side often enough that this is not a rare edge case.
	var anchor_dir: Vector2 = anchor_local - c1_local
	var anchor_alignment_dot: float = anchor_dir.normalized().dot(pairing_direction.normalized()) if anchor_dir.length() > 0.0 and pairing_direction.length() > 0.0 else 0.0

	return {
		strand = strand, slot = slot, sign = _strand_direction_sign(strand),
		base_type = base_type, world_pos = world_pos,
		ring_named = ring_named, ring_world_named = ring_world_named,
		ring_diameter = _max_pairwise_distance(ring_positions.values()),
		attachment_suffix = attachment_suffix.to_upper(), attachment_local = attachment_local,
		attachment_dist_from_c1 = attachment_local.distance_to(c1_local),
		attachment_to_ring_center = attachment_local.distance_to(ring_centroid),
		base_named = base_named, base_world_named = base_world_named,
		base_diameter = _max_pairwise_distance(base_positions.values()),
		anchor_suffix = anchor_suffix.to_upper(), anchor_world = anchor_world,
		base_world_positions = base_world_positions,
		chain_named = chain_named, chain_world_named = chain_world_named,
		chain_far_from_c1 = chain_far_from_c1,
		chain_closest_to_own_base = chain_closest_to_own_base,
		pairing_direction = pairing_direction,
		anchor_alignment_dot = anchor_alignment_dot,
	}


func _write_residue_block(out: Array, label: String, r: Dictionary) -> void:
	out.append("%s NUCLEOTIDE (strand=%s, slot=%d, sign=%s):" % [label, r.strand, r.slot, ("+1" if r.sign >= 0.0 else "-1")])
	out.append("  world_pos (residue anchor, = C1' world position) = (%.4f, %.4f)" % [r.world_pos.x, r.world_pos.y])
	out.append("  ribose ring [RIBOSE] — local / world coords:")
	for role_label in r.ring_named:
		var p: Vector2 = r.ring_named[role_label]
		var pw: Vector2 = r.ring_world_named[role_label]
		out.append("    %s: local=(%.4f, %.4f)  world=(%.4f, %.4f)" % [role_label, p.x, p.y, pw.x, pw.y])
	out.append("  ribose ring diameter (widest extent) = %.4f" % r.ring_diameter)
	out.append("  substituent chain [CHAIN: O3'/C5'/O5'/alpha-P] — local / world coords:")
	for role_label in r.chain_named:
		var pc: Vector2 = r.chain_named[role_label]
		var pcw: Vector2 = r.chain_world_named[role_label]
		out.append("    %s: local=(%.4f, %.4f)  world=(%.4f, %.4f)" % [role_label, pc.x, pc.y, pcw.x, pcw.y])
	out.append("  substituent chain farthest point from C1' = %.4f" % r.chain_far_from_c1)
	out.append("  DIRECTION CHECK: pairing_direction (toward real partner) = (%.4f, %.4f)  anchor_alignment_dot = %.4f  (%s)" % [
		r.pairing_direction.x, r.pairing_direction.y, r.anchor_alignment_dot,
		"anchor faces partner" if r.anchor_alignment_dot > 0.0 else "anchor faces AWAY from partner" if r.pairing_direction.length() > 0.0 else "n/a, unpaired"
	])
	out.append("  attachment atom (%s): local=(%.4f, %.4f), distance from C1' = %.4f" % [r.attachment_suffix, r.attachment_local.x, r.attachment_local.y, r.attachment_dist_from_c1])
	out.append("  base ring [BASE] — local / world coords:")
	for role_label in r.base_named:
		var p2: Vector2 = r.base_named[role_label]
		var p2w: Vector2 = r.base_world_named[role_label]
		out.append("    %s: local=(%.4f, %.4f)  world=(%.4f, %.4f)" % [role_label, p2.x, p2.y, p2w.x, p2w.y])
	out.append("  base ring diameter (widest extent) = %.4f" % r.base_diameter)
	out.append("  anchor atom (%s): world=(%.4f, %.4f)" % [r.anchor_suffix, r.anchor_world.x, r.anchor_world.y])


func _max_pairwise_distance(points) -> float:
	var pts: Array = Array(points)
	var best: float = 0.0
	for i in range(pts.size()):
		for j in range(i + 1, pts.size()):
			var d: float = pts[i].distance_to(pts[j])
			if d > best:
				best = d
	return best


func _centroid(points) -> Vector2:
	var pts: Array = Array(points)
	if pts.is_empty():
		return Vector2.ZERO
	var sum: Vector2 = Vector2.ZERO
	for p in pts:
		sum += p
	return sum / pts.size()


func _closest_world_distance(points, target: Vector2) -> float:
	var pts: Array = Array(points)
	var best: float = INF
	for p in pts:
		var d: float = p.distance_to(target)
		if d < best:
			best = d
	return best


func _slot_spacing() -> float:
	if replication_mgr != null and replication_mgr.sim != null and "nucleotide_slot_spacing" in replication_mgr.sim:
		return replication_mgr.sim.nucleotide_slot_spacing
	return 54.0

func _dna_ribbons_gap() -> float:
	if replication_mgr != null and replication_mgr.sim != null and "dna_ribbons_gap" in replication_mgr.sim:
		return replication_mgr.sim.dna_ribbons_gap
	return 60.0


## NOT nucleotide_field.gd's _visible_world_rect() — that function is
## deliberately zoom-INDEPENDENT (a fixed "overworld" extent, a different
## fix for a different bug). This renderer needs a genuine CURRENT-viewport
## visibility test, since at deep zoom only a couple of residues are ever
## on screen and the whole point is not issuing dead draw calls for the
## rest of a long strand.
func _current_viewport_world_rect() -> Rect2:
	var z: float = zoom_mgr.zoom.x
	if z <= 0.0:
		return Rect2()
	var world_size: Vector2 = get_viewport().get_visible_rect().size / z
	return Rect2(zoom_mgr.global_position - world_size * 0.5, world_size)


func _element_color(element: String) -> Color:
	match element:
		"C": return Color(0.75, 0.75, 0.78)
		"N": return tm.molecular_nitrogen_color
		"O": return Color(0.85, 0.25, 0.2)
		"P": return Color(0.95, 0.6, 0.15)
		_: return tm.molecular_bond_color


## Draws fixed-size dots along a->b rather than dash segments — see
## molecular_h_bond_dot_radius's comment (theme_manager.gd) for why: a
## dashed line degrades to a solid blur once the span shrinks toward one
## dash+gap cycle, but a dot is a fixed mark regardless of how few fit
## along the line.
func _draw_dotted_line(a: Vector2, b: Vector2, color: Color, radius: float, gap: float) -> void:
	var diff: Vector2 = b - a
	var length: float = diff.length()
	if length <= 0.0:
		draw_circle(a, radius, color, true, -1.0, false)
		return
	var dir: Vector2 = diff / length
	var step: float = max(radius * 2.0 + gap, 0.01)
	var t: float = 0.0
	while t <= length:
		draw_circle(a + dir * t, radius, color, true, -1.0, false)
		t += step


func _draw() -> void:
	if not _active:
		return

	# Bonds: ProceduralShapeUtils.inset_segment() shortens the bond's TRUE
	# endpoints (the first/last points — real atom centres) to run
	# edge-to-edge rather than centre-to-centre (avoids showing through an
	# atom's own circle/label — the exact failure mode it was built to fix
	# for the ATP cofactor beads; see MolecularStructureDesign.md
	# correction #8). draw_line() has no round-cap option the way a Line2D
	# node does, so a round-joint draw_circle() is added at EVERY point in
	# the polyline (half line-width radius), not just the two ends —
	# interior points (Option C's curve-sample waypoints,
	# docs/MolecularStructure_BasePairExpansion.md) are never inset, since
	# they're pure curve geometry, not atom centres — only the true
	# first/last points get the inset treatment.
	var half_width: float = tm.molecular_bond_width * 0.5
	for b in _bond_layout:
		var points: Array = b.points
		if points.size() < 2:
			continue
		var drawn_points: Array = points.duplicate()
		var inset_first: PackedVector2Array = ProceduralShapeUtils.inset_segment(
			points[0], points[1], tm.molecular_atom_radius, 0.0
		)
		if inset_first.size() >= 1:
			drawn_points[0] = inset_first[0]
		var last_i: int = points.size() - 1
		var inset_last: PackedVector2Array = ProceduralShapeUtils.inset_segment(
			points[last_i - 1], points[last_i], 0.0, tm.molecular_atom_radius
		)
		if inset_last.size() >= 2:
			drawn_points[last_i] = inset_last[1]
		for i in range(drawn_points.size() - 1):
			draw_line(drawn_points[i], drawn_points[i + 1], tm.molecular_bond_color, tm.molecular_bond_width, false)
		for p in drawn_points:
			draw_circle(p, half_width, tm.molecular_bond_color, true, -1.0, false)

	# Hydrogen bonds: dotted parallel lines between each rendered pair's
	# named pairing-anchor atoms (Tier 2, see the addendum doc) — count and
	# color reused verbatim from the existing bead-glyph AT/CG convention,
	# never recomputed independently.
	for h in _h_bond_layout:
		var dir: Vector2 = h.anchor_b - h.anchor_a
		if dir.length() <= 0.0:
			continue
		dir = dir.normalized()
		var perp: Vector2 = dir.orthogonal()
		var total_width: float = float(h.count - 1) * tm.hydrogen_bond_spacing
		var start_offset: float = -total_width / 2.0
		for i in range(h.count):
			var offset: Vector2 = perp * (start_offset + float(i) * tm.hydrogen_bond_spacing)
			_draw_dotted_line(h.anchor_a + offset, h.anchor_b + offset, h.color, tm.molecular_h_bond_dot_radius, tm.molecular_h_bond_dot_gap)

	# Atoms: element-colored circle + counter-rotated label, mirroring
	# nucleotide_field.gd's exact per-glyph transform pattern (cache the
	# ZoomManager REFERENCE, read rotation LIVE here) — including the
	# MANDATORY draw_set_transform reset after each label, since the loop
	# continues and the next atom's draw_circle() uses absolute coords.
	var label_rotation: float = zoom_mgr.get_label_counter_rotation() if zoom_mgr != null else 0.0
	var font: Font = tm.base_label_font if tm.base_label_font != null else ThemeDB.fallback_font
	# Dedicated field, NOT tm.base_label_font_size — that value is
	# proportioned for the bead-glyph mode's base_radius (15 world units);
	# reused directly against molecular_atom_radius (6.0) it was ~2.5x too
	# large relative to its own atom circle. See the field's own doc
	# comment in theme_manager.gd.
	var font_size: int = tm.molecular_atom_label_font_size
	for a in _atom_layout:
		draw_circle(a.position, tm.molecular_atom_radius, _element_color(a.element), true, -1.0, false)
		if font != null:
			var ssize: Vector2 = font.get_string_size(a.label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var ascent: float = font.get_ascent(font_size)
			var draw_pos: Vector2 = Vector2(-ssize.x / 2.0, ascent - ssize.y / 2.0)
			draw_set_transform(a.position, label_rotation, Vector2.ONE)
			draw_string(font, draw_pos, a.label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tm.base_label_color)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
