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

## {world_pos: Vector2, radius: float, key: String} — one entry per
## residue currently rendered via RiboseDeriver.reflect_about_backbone_axis()
## (the fork-flip mirror) this frame. Populated inline at the exact call
## site of that mirror in _rebuild_layout() — never a separate opt-in step
## — so a residue cannot be mirrored without becoming hoverable, closing
## the disclaimer requirement in reflect_about_backbone_axis()'s own doc
## comment. Read by _process() to compute _hovered_mirrored_key, and
## indirectly by _draw() through that. Inherits the _active zoom-tier gate
## for free: _rebuild_layout() early-returns before this is ever touched
## while inactive.
var _mirrored_residue_layout: Array[Dictionary] = []

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

## "strand:slot" -> {ring_positions: Dictionary, substituent_positions: Dictionary}
## (RiboseDeriver.bake_self_paired_geometry()'s return shape). Computed
## once per residue, on first encounter while self-paired, never
## recomputed after -- same convention as _fold_cache, now extended to
## LOCAL GEOMETRY for this one render state (docs/MolecularStructureDesign.md,
## "Self-paired geometry is baked once per residue, not recomputed live").
var _self_paired_geometry_cache: Dictionary = {}

## Named, callable invalidation seam for future work this cache does not
## yet need to know about (an unbound/exposed phosphate at a ligase site,
## distinct polymerase-interaction geometry) -- decided at Nucleation,
## docs/MolecularStructureDesign.md's same entry. Nothing calls this yet;
## it exists so that future work has an obvious attachment point instead
## of forcing a redesign of this cache.
func invalidate_self_paired_geometry(strand: String, slot: int) -> void:
	_self_paired_geometry_cache.erase("%s:%d" % [strand, slot])

const OPERATOR_PATH: String = "res://resources/phosphodiester_bond_formation.tres"

## Verbatim project framing (docs/MolecularStructureDesign.md, "Self-paired
## fork-flip as a deliberate, labeled 2D mirror") for the hover disclaimer
## shown while a residue is rendered via RiboseDeriver.
## reflect_about_backbone_axis(). Never paraphrase this string — it's the
## project's own already-agreed wording.
const MIRRORED_RESIDUE_TOOLTIP_TEXT: String = "in 2D molecular representations this rotation doesn't really exist, but for didactic reasons, we're showing you this way."

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

## Every base-atom role suffix that can be one end of a real Watson-Crick
## hydrogen bond, across all four base letters — used to build
## base_bond_atoms_by_key (_rebuild_layout()) via a single flat try-lookup
## loop (find_by_role, skip if absent) rather than branching per letter.
const HBOND_ROLE_SUFFIXES: Array[String] = ["n1", "n3", "n2", "o2", "o6", "n4", "n6", "o4"]

## Real per-base-letter hydrogen-bond atom pairs (own role -> partner's
## role), replacing the old "N parallel offset lines from one shared
## anchor axis" approximation (docs/MolecularStructure_BasePairExpansion.md).
## G-C: N1-N3 (existing anchor pair), N2-O2, O6-N4. A-T: N1-N3, N6-O4.
## Real chemistry, not a rendering convenience — every pair here is an
## actual WC donor/acceptor atom pair, confirmed against standard base-
## pairing geometry, not this project's own invention.
const HBOND_OWN_TO_PARTNER_ROLES: Dictionary = {
	"A": [["n1", "n3"], ["n6", "o4"]],
	"T": [["n3", "n1"], ["o4", "n6"]],
	"G": [["n1", "n3"], ["n2", "o2"], ["o6", "n4"]],
	"C": [["n3", "n1"], ["o2", "n2"], ["n4", "o6"]],
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
		MoleculeGeometryDiagnostics.dump(self, replication_mgr, template_sim, _fold_cache, _operators)
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
	# Perf fix (docs/MolecularStructure_BasePairExpansion.md): this used to
	# run its full per-residue cost — fold lookup, ring/base derivation,
	# NitrogenBaseDeriver.derive_base_layout()'s 72-step clearance-search
	# rotation, none of it cached (recomputed fresh every call, by design,
	# per this file's own dump header) — EVERY FRAME regardless of
	# whether the molecular renderer was even active, for every residue
	# inside cull_rect. cull_rect (_current_viewport_world_rect()) is
	# LARGER exactly when zoomed OUT (world_size = viewport_pixels / z,
	# smaller z -> bigger world_size), so ordinary bead-glyph play at
	# normal zoom — nowhere near molecular mode — paid the full cost for
	# every residue on screen, scaling directly with how much of the
	# strand was visible. Safe to skip entirely while inactive: _draw()
	# already independently guards on _active before reading
	# _atom_layout/_bond_layout/_h_bond_layout, and is_slot_active()/
	# is_strand_active() already short-circuit on `not _active` before
	# ever consulting _active_slots — nothing downstream depends on these
	# being freshly rebuilt while inactive.
	_atom_layout.clear()
	_bond_layout.clear()
	_h_bond_layout.clear()
	_active_slots.clear()
	_mirrored_residue_layout.clear()
	if not _active:
		return

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
	# Real per-atom world positions for every role Watson-Crick H-bonding
	# can involve (base-letter-dependent — see HBOND_OWN_TO_PARTNER_ROLES),
	# not just one named anchor atom. Supersedes the old single-anchor
	# anchor_by_key (docs/MolecularStructure_BasePairExpansion.md): the
	# anchor-pair-only rendering was chemically wrong at atom-level zoom —
	# real G:C/A:T H-bonds connect specific, different atom pairs (N1-N3,
	# N2-O2, O6-N4 for G:C; N1-N3, N6-O4 for A:T), not N parallel offset
	# lines fanned out from one shared axis.
	var base_bond_atoms_by_key: Dictionary = {}

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
		var c1_id: int = topology.find_by_role("incoming.c1_prime")
		var c1_local: Vector2 = ring_positions.get(c1_id, Vector2.ZERO)

		# Computed here, ahead of the ring-direction decision below (moved up
		# from its old post-rotation position — the self-paired template
		# case, below, needs the real partner direction BEFORE choosing
		# which way to rotate the ring, not after). Also still feeds
		# derive_substituents()/derive_base_layout() exactly as before.
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
		# not re-derived, so the two can't silently disagree. Computed here,
		# ahead of the ring-rotation decision below (Bug W needs these real
		# vectors to run its own clearance search) — this file's own
		# geometry is not affected by rotation state, only by real
		# same-strand neighbor positions, so the reordering changes nothing
		# about what these vectors mean.
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
		# rotation.
		#
		# Self-paired-template correction (docs/MolecularStructure_
		# BasePairExpansion.md, Bug V/Bug W): the fixed STRAND_DIRECTION_SIGN
		# convention above was verified only against "do the rings stop
		# overlapping" (Handout_AntiparallelStrandOrientation.md's own
		# criterion) — never against the ring's bulge direction relative to
		# the real partner. Bug V fixed the bulge direction with a binary
		# identity/180-degree choice; Bug W found that binary choice left no
		# freedom to also avoid the substituent chain colliding with the
		# ring's own atoms, and replaced it with
		# RiboseDeriver.resolve_self_paired_ring_rotation() — a bounded
		# search over the ring's rotation angle that satisfies the same
		# bulge-away-from-partner requirement (any negative dot product, not
		# specifically -1.0 — see that function's own doc comment) while
		# maximizing clearance against the real chain (toward_next/
		# toward_previous, computed above, never modified). This branch
		# ONLY changes that specific case — leading, lagging, and any
		# template residue with a real synthesized partner (post-
		# _pair_for_slot()-fix, already confirmed clean this session) keep
		# the exact original fixed sign, byte-identical to before.
		var is_self_paired_template: bool = (entry.strand == "template_top" or entry.strand == "template_bottom") and partner_key.begins_with("template_")
		var substituent_positions: Dictionary = {}
		# Fork-flip build (docs/MolecularStructureDesign.md, "Self-paired
		# fork-flip as a deliberate, labeled 2D mirror"): direction_sign < 0
		# self-paired residues (template_bottom) no longer go through
		# bake_self_paired_geometry()'s collision-search rotation -- they
		# get the pedagogical mirror instead, derived from their own
		# natural (direction_sign >= 0) ring/substituent placement.
		# template_top (direction_sign >= 0) is untouched, still the bake
		# path, same as leading/lagging's own `else` branch below is
		# untouched.
		var self_paired_sign: float = _strand_direction_sign(entry.strand)
		if is_self_paired_template and self_paired_sign < 0.0:
			var natural_substituents: Dictionary = RiboseDeriver.derive_substituents(topology, "incoming.", ring_positions, bond_length, toward_next, toward_previous)
			var c4_id: int = topology.find_by_role("incoming.c4_prime")
			var axis_y: float = ring_positions[c4_id].y
			ring_positions = RiboseDeriver.reflect_about_backbone_axis(ring_positions, axis_y)
			substituent_positions = RiboseDeriver.reflect_about_backbone_axis(natural_substituents, axis_y)
		elif is_self_paired_template:
			var self_paired_cache_key: String = "%s:%d" % [entry.strand, entry.slot]
			if not _self_paired_geometry_cache.has(self_paired_cache_key):
				_self_paired_geometry_cache[self_paired_cache_key] = RiboseDeriver.bake_self_paired_geometry(topology, "incoming.", bond_length, pairing_direction, toward_next, toward_previous, tm.molecular_atom_radius)
			var baked: Dictionary = _self_paired_geometry_cache[self_paired_cache_key]
			ring_positions = baked.ring_positions
			substituent_positions = baked.substituent_positions
		else:
			ring_positions = RiboseDeriver.apply_strand_direction(ring_positions, c1_local, _strand_direction_sign(entry.strand))

		if not is_self_paired_template:
			substituent_positions = RiboseDeriver.derive_substituents(topology, "incoming.", ring_positions, bond_length, toward_next, toward_previous)

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

		var residue_max_extent: float = 0.0
		for atom in topology.atoms:
			if not local_positions.has(atom.id):
				continue
			var local_offset: Vector2 = local_positions[atom.id] - anchor_offset
			residue_max_extent = max(residue_max_extent, local_offset.length())
			var world: Vector2 = world_pos + local_offset
			_atom_layout.append({
				position = world,
				element = atom.element,
				label = _atom_display_label(atom.role, atom.element),
				atom_id = atom.id,
				nucleotide_slot = entry.slot,
			})

		if is_self_paired_template and self_paired_sign < 0.0:
			_mirrored_residue_layout.append({
				world_pos = world_pos,
				radius = residue_max_extent + tm.molecular_atom_radius,
				key = key,
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
		var bond_atoms: Dictionary = {}
		for suffix in HBOND_ROLE_SUFFIXES:
			var role_id: int = topology.find_by_role("incoming." + suffix)
			if local_positions.has(role_id):
				bond_atoms[suffix] = world_pos + (local_positions[role_id] - anchor_offset)
		if not bond_atoms.is_empty():
			base_bond_atoms_by_key[key] = bond_atoms

	_build_backbone_bonds(o3_by_key, alpha_by_key)
	_build_hydrogen_bonds(base_bond_atoms_by_key, base_type_by_key, position_by_key)


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


## Builds one real-atom-pair segment group per rendered base pair
## (docs/MolecularStructure_BasePairExpansion.md — supersedes the old
## single-anchor-pair-plus-parallel-offset approximation). Segment count
## is naturally 2 for A:T, 3 for G:C — no longer read from
## NitrogenBaseDeriver.hydrogen_bond_count() here (that stays the single
## source of truth for replication_manager.gd's bead-glyph dash COUNT,
## an intentionally different, coarser Tier-1 rendering this file doesn't
## touch). Only drawn when BOTH sides of a pair are rendered this frame,
## same accepted-simplification rule as the backbone bonds above.
func _build_hydrogen_bonds(base_bond_atoms_by_key: Dictionary, base_type_by_key: Dictionary, position_by_key: Dictionary) -> void:
	var seen: Dictionary = {}
	for key in base_bond_atoms_by_key.keys():
		if seen.has(key):
			continue
		var parts: PackedStringArray = key.split(":")
		var strand: String = parts[0]
		var slot: int = int(parts[1])
		var partner_key: String = _pair_for_slot(strand, slot, base_type_by_key, position_by_key)
		if partner_key == "" or not base_bond_atoms_by_key.has(partner_key):
			continue
		seen[key] = true
		seen[partner_key] = true

		var base_type: String = base_type_by_key.get(key, "A")
		var own_atoms: Dictionary = base_bond_atoms_by_key[key]
		var partner_atoms: Dictionary = base_bond_atoms_by_key[partner_key]
		var role_pairs: Array = HBOND_OWN_TO_PARTNER_ROLES.get(base_type, [])
		var segments: Array = []
		for pair in role_pairs:
			var own_suffix: String = pair[0]
			var partner_suffix: String = pair[1]
			if own_atoms.has(own_suffix) and partner_atoms.has(partner_suffix):
				segments.append({a = own_atoms[own_suffix], b = partner_atoms[partner_suffix]})
		if segments.is_empty():
			continue

		var color: Color = tm.cg_bond_color if (base_type == "C" or base_type == "G") else tm.at_bond_color
		_h_bond_layout.append({
			segments = segments,
			color = color,
		})



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

	# Hydrogen bonds: one dotted line per REAL atom pair
	# (docs/MolecularStructure_BasePairExpansion.md — supersedes the old
	# parallel-offset-from-one-anchor approximation). Each segment already
	# carries its own real world endpoints (HBOND_OWN_TO_PARTNER_ROLES,
	# _build_hydrogen_bonds()) — no perp/offset math, no dash spacing of
	# any kind involved here anymore.
	for h in _h_bond_layout:
		for seg in h.segments:
			_draw_dotted_line(seg.a, seg.b, h.color, tm.molecular_h_bond_dot_radius, tm.molecular_h_bond_dot_gap)

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
