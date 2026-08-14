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
## {c5: Vector2, c3: Vector2} — one entry per rendered residue, the two
## world-space endpoints of that residue's OWN intra-residue C5'->C3'
## segment (MolecularIdentityHierarchy_Design.md's "directional highlight"
## investigation). No longer drawn directly — camera_regent.gd's scripted
## capsule shot is the sole consumer now, via get_residue_capsule_positions()
## / get_residue_capsule_positions_when_centered() below, which read from
## _last_capsule_by_key (built from this array). Populated unconditionally
## alongside _bond_layout/_atom_layout every rebuild.
var _capsule_layout: Array[Dictionary] = []

## Last rebuild's o3_by_key/alpha_by_key (see _build_backbone_bonds()) —
## cached across the frame boundary so replication_manager.gd can query the
## atom-tier position of a specific lagging-strand fragment gap (for the
## ligase atom-tier position swap) without _build_backbone_bonds() itself
## needing to know ligase exists. Cleared alongside the other per-frame
## layout arrays whenever _rebuild_layout() early-returns
## (_transition_fraction <= 0.0) — stale positions are worse than no
## positions, so has_lagging_gap_atom_position() must go false then, never
## keep returning last-bead-mode data.
var _last_o3_by_key: Dictionary = {}
var _last_alpha_by_key: Dictionary = {}
## {c5: Vector2, c3: Vector2} per "strand:slot" key — the SAME per-residue
## capsule positions _capsule_layout holds (see that array's own comment),
## just also indexed by residue identity for external lookup. Cached across
## the frame boundary exactly like _last_o3_by_key/_last_alpha_by_key above
## (same reasoning: stale positions are worse than no positions), backing
## get_residue_capsule_positions() below — the shared dependency
## CapsuleArrowOverlay's c5_position/c3_position fields and the upcoming
## camera-choreography target both need, so neither has to re-derive
## topology/layout math of its own or invent a second indexing scheme.
var _last_capsule_by_key: Dictionary = {}

## {world_pos: Vector2, radius: float, key: String} — one entry per
## residue currently rendered via RiboseDeriver.reflect_about_backbone_axis()
## (the fork-flip mirror) this frame. Populated in _rebuild_layout() by a
## registration branch guarded by the identical condition
## (is_self_paired_template and neighbor_sign < 0.0) as the mirror
## branch above it — keep the two conditions in sync if either changes.
## Read by _process() to compute _hovered_mirrored_key, and indirectly by
## _draw() through that. Inherits the _active zoom-tier gate for free:
## _rebuild_layout() early-returns before this is ever touched while
## inactive.
var _mirrored_residue_layout: Array[Dictionary] = []

## Key ("strand:slot") of the mirrored residue currently under the mouse,
## or "" if none. Recomputed once per frame in _process(), read by _draw()
## to decide whether to draw the fork-flip disclaimer tooltip.
var _hovered_mirrored_key: String = ""

## Last hysteresis decision. Gates ONLY the draw calls — layout below runs
## unconditionally every frame regardless of this, per the render-mode
## transition decision (Open Question 10): no first-crossing hitch.
var _active: bool = false
## Continuous 0..1 position within the SAME molecular_zoom_enter/exit_
## threshold band _compute_active() hystereses over — 0 at or below
## molecular_zoom_exit_threshold, 1 at or above molecular_zoom_enter_
## threshold, ramping linearly between. Unlike _active, this is a pure
## function of the live zoom scalar with no stored prior-state comparison,
## so it needs no hysteresis of its own — a continuous ramp has nothing to
## flicker. Drives the bead<->molecular crossfade (Open Question 10's
## deferred transition treatment): both tiers draw concurrently anywhere
## inside the band, alpha-blended by this value. _active is left
## completely alone for its own existing consumers (is_molecular_mode_
## active()'s external callers) — this is an ADDITION, not a replacement.
var _transition_fraction: float = 0.0
## Second-tier hysteresis nested inside skeletal mode (Part 1,
## docs/atomtier/AtomTier_VisualDesign.md): true = closer band, full
## geometry labels (C3', Pα, ...); false = wider band, element-only
## labels (C, O, P, N). Meaningless while _active is false — reset to
## false alongside it so re-entering skeletal mode always starts in the
## wider band rather than resuming stale state. Mirrors
## _compute_active()'s own enter/exit hysteresis exactly, against its
## own ThemeManager pair (molecular_label_zoom_enter_threshold /
## _exit_threshold) — independent of the skeletal on/off pair.
var _label_full_geometry_active: bool = false

## Which "strand:slot" keys are actually rendered in skeletal mode THIS
## frame — backs is_slot_active(), polled live by replication_manager.gd/
## simulation.gd for bug-A occlusion suppression. Rebuilt every frame in
## _rebuild_layout(), never a separately-maintained cache.
var _active_slots: Dictionary = {}

## Superset of _active_slots — also includes, for every active residue, its
## one immediate OUTWARD same-strand neighbor (the slot on the far side from
## cluster_center_x). Backs get_bead_fade_amount(), polled by the same
## callers as is_slot_active() but specifically for bead-GLYPH occlusion.
##
## Why this exists (screenshot bug, 2026-08-07): _molecular_render_pos()'s
## outward spread push (tm.molecular_extra_slot_spacing) is scaled by
## distance from cluster_center_x so ADJACENT ACTIVE residues clear each
## other's ring geometry — provably a constant +extra_slot_spacing added to
## every active-active gap (see that function's own PROOF comment). But the
## same push moves the OUTERMOST active residue TOWARD its next, INACTIVE
## neighbor (which never moves — bead-tier positions are plain
## nucleotide_original_x, computed in simulation.gd/replication_manager.gd
## with zero knowledge of this push), shrinking that one gap by the same
## amount instead of growing it. Verified live (headless repro, real
## project constants: slot_spacing=54, molecular_extra_slot_spacing=30,
## viewport=1280px): the normal 54-unit gap shrinks to 24 exactly at the
## atom/bead boundary, while active-active gaps correctly grow to 84 — the
## bead-tier letter glyph ends up overlapping the atom cluster next to it.
##
## Fix is occlusion, not a geometry rewrite: suppressing the one bead-glyph
## that would otherwise sit in the crowded gap is the same pattern this file
## already uses for is_slot_active() itself (Bug A) and nucleotide_field.gd's
## atom-tier auto-block — hide what atom-tier rendering makes redundant or
## incompatible, rather than reworking the invariant-proven push math and
## risking the ring-collision behavior it was built to prevent.
var _bead_suppressed_slots: Dictionary = {}

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
## STAGE 4 (docs/superpowers/plans, self-paired pentose reconstruction):
## template_top/template_bottom's push halved from the original ∓1.0.
## Measured live via F9 dump before this change: self-paired template-
## to-template gap = 160 world units (raw 60 + push-contributed 100),
## while leading-to-its-template-partner gap = 110 (raw 60 + push-
## contributed 50) — self-paired was rendering 50 units WIDER than
## leading/lagging's own spacing, not matching it as originally
## intended (the prior comment here claimed the two should grow by
## "the same total amount," which the measured numbers contradicted).
## Halving template_top/template_bottom's multiplier (∓1.0 -> ∓0.5)
## brings self-paired's push-contributed share down to 50, matching
## leading/lagging's spacing exactly (60 + 50 = 110 both). leading/
## lagging's own ∓2.0 are unchanged -- they still push one additional
## step beyond wherever their template partner now sits.
const MOLECULAR_ROW_PUSH: Dictionary = {
	"leading": -2.0,
	"template_top": -0.5,
	"template_bottom": 0.5,
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
	# c5_methyl displays as "C7" — 2007 PDB remediation nomenclature for
	# thymine's methyl carbon (supersedes the older "C5M"/"C5-Me" naming),
	# and short enough to fit inside the atom circle at the full-label tier
	# where "C5-Me" overflowed it. Internal role key stays c5_methyl
	# (nitrogen_base_deriver.gd, molecule_geometry_diagnostics.gd) — display
	# text only.
	"n6": "N6", "o6": "O6", "n2": "N2", "o2": "O2", "o4": "O4", "c5_methyl": "C7",
	# n4 was missing entirely (fell back to bare element "N") — cytosine's
	# exocyclic amino group, built at nitrogen_base_deriver.gd's
	# build_cytosine_seed_into() (role_prefix + "n4").
	"n4": "N4",
}

func _atom_display_label(role: String, element: String, full_geometry: bool) -> String:
	if not full_geometry:
		return element
	var suffix: String = _role_suffix(role)
	return ATOM_DISPLAY_LABELS.get(suffix, element)

## Shared by _atom_display_label() above and _bond_is_carbonyl() below —
## topology.atoms' role strings are always "incoming.<suffix>" or
## "chain.<suffix>" (see molecule_topology.gd's add_atom()).
func _role_suffix(role: String) -> String:
	var dot: int = role.rfind(".")
	if dot != -1:
		return role.substr(dot + 1)
	return role

## Carbonyl oxygens (C=O, always double regardless of label zoom tier —
## bond-thickness design pass): the exocyclic ring substituent oxygens,
## never the ribose/phosphate oxygens (o4_prime, alpha_O1, etc. — full
## suffixes, not matched by this short-suffix set).
const CARBONYL_OXYGEN_SUFFIXES: Array[String] = ["o2", "o4", "o6"]

## Whether a bond is a carbonyl C=O — shows double even at the wider,
## element-only label band (see _draw()'s draw_double decision), unlike
## other order==2 bonds (aromatic ring, phosphate P=O) which only show
## double once _label_full_geometry_active. Checked by role suffix, not a
## new authoring-time flag — carbonyls are already order==2 in the
## topology (see nitrogen_base_deriver.gd), this just identifies WHICH
## order==2 bonds those are.
func _bond_is_carbonyl(topology: MoleculeTopology, bond: Dictionary) -> bool:
	var atom_a: Dictionary = topology.get_atom(bond.a)
	var atom_b: Dictionary = topology.get_atom(bond.b)
	return CARBONYL_OXYGEN_SUFFIXES.has(_role_suffix(atom_a.get("role", ""))) \
		or CARBONYL_OXYGEN_SUFFIXES.has(_role_suffix(atom_b.get("role", "")))


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

## Bead-tier-visual occlusion — true for every truly-active atom-tier slot
## PLUS the one boundary slot just outside the cluster on each side. Use
## this (not is_slot_active()) for anything positioned the same raw,
## un-pushed way the letter-glyph circles are — the letter glyphs
## themselves (nucleotide_bases/top_strand_bases/leading_synthesized_bases/
## lagging_synthesized_bases) AND the per-slot hydrogen-bond dash lines
## (template_hydrogen_bonds/leading_hydrogen_bonds/lagging_hydrogen_bonds)
## — both sit at fixed bead-tier coordinates with no knowledge of this
## file's outward spread push, so both crowd the same boundary residue the
## same way. See _bead_suppressed_slots' doc comment for why the plain
## is_slot_active() boundary is not enough.
##
## Stays on is_slot_active() instead: the backbone Line2D nodes
## (leading_backbone_line, lagging_backbone_line, top/bottom template
## backbone lines) — those are suppressed whole-strand via
## get_strand_fade_amount() (Line2D has no per-point alpha), so they were
## never subject to this per-residue boundary artifact in the first place.
##
## Continuous replacement for the old is_slot_bead_suppressed() bool
## (bead<->molecular crossfade, Open Question 10) — same membership test as
## before, 0.0 = fully bead-glyph, up to _transition_fraction = fully
## molecular-occluded. No longer gated on _active (which flips later/
## earlier than the band's own edges — see _transition_fraction's doc
## comment); nonzero as soon as the crossfade band is entered in either
## direction.
func get_bead_fade_amount(strand: String, slot: int) -> float:
	return _transition_fraction if _bead_suppressed_slots.has("%s:%d" % [strand, slot]) else 0.0

## Continuous replacement for the old is_strand_active() bool. Whole-strand
## version of get_bead_fade_amount() — true if ANY slot of this strand is
## currently skeletal-active, for Line2D backbone suppression (no per-point
## alpha available there); at the deep zoom skeletal mode requires, this is
## visually equivalent to per-slot suppression since the rest of the line
## is off-screen regardless.
func get_strand_fade_amount(strand: String) -> float:
	if _transition_fraction <= 0.0:
		return 0.0
	for key in _active_slots.keys():
		if key.begins_with(strand + ":"):
			return _transition_fraction
	return 0.0

## Public accessor for _active — simulation.gd polls this to auto-block
## nucleotide_field.gd's ambient dNTP cloud while atom-tier skeletal
## rendering is active (the ambient cloud is visually/conceptually
## incompatible with atom-level rendering — see nucleotide_field.gd's
## set_atom_tier_blocked()).
func is_molecular_mode_active() -> bool:
	return _active


func _process(_delta: float) -> void:
	if replication_mgr == null or zoom_mgr == null or tm == null:
		return
	_active = _compute_active()
	_label_full_geometry_active = _compute_label_full_geometry_active()
	_transition_fraction = _compute_transition_fraction()
	_rebuild_layout()
	_hovered_mirrored_key = _compute_hovered_mirrored_key()
	queue_redraw()


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


## Pure function of the live zoom scalar, no hysteresis (see _transition_
## fraction's own doc comment for why none is needed here). Reuses the SAME
## molecular_zoom_enter/exit_threshold pair _compute_active() hystereses
## over, per the render-mode transition decision (Open Question 10): never
## a separate transition-specific tunable.
func _compute_transition_fraction() -> float:
	if not zoom_mgr.free_camera_mode():
		return 0.0
	var z: float = zoom_mgr.zoom.x
	var band: float = tm.molecular_zoom_enter_threshold - tm.molecular_zoom_exit_threshold
	if band <= 0.0:
		return 1.0 if z >= tm.molecular_zoom_enter_threshold else 0.0
	return clamp((z - tm.molecular_zoom_exit_threshold) / band, 0.0, 1.0)


## Public accessor for _transition_fraction — how far into the bead<->
## molecular crossfade band the live zoom scalar currently sits. 0.0 =
## fully bead-glyph, 1.0 = fully molecular. Polled by replication_manager.gd/
## simulation.gd to alpha-blend both tiers concurrently.
func get_transition_fraction() -> float:
	return _transition_fraction


## Generic O3'/alpha-phosphate atom position accessors, keyed by strand+slot
## — single source of truth for "where is this residue's backbone atom
## right now," backing get_lagging_gap_atom_position() below and the
## leading/lagging polymerase atom-tier position swap alike, so multiple
## callers can't silently derive different answers to the same underlying
## question. _last_o3_by_key/_last_alpha_by_key are strand-generic already
## (_build_backbone_bonds() populates all four strands into them), so no
## rebuild-side change was needed to support strands other than "lagging."
func has_slot_o3_position(strand: String, slot: int) -> bool:
	return _last_o3_by_key.has("%s:%d" % [strand, slot])

func get_slot_o3_position(strand: String, slot: int) -> Vector2:
	return _last_o3_by_key.get("%s:%d" % [strand, slot], Vector2.ZERO)

func has_slot_alpha_position(strand: String, slot: int) -> bool:
	return _last_alpha_by_key.has("%s:%d" % [strand, slot])

func get_slot_alpha_position(strand: String, slot: int) -> Vector2:
	return _last_alpha_by_key.get("%s:%d" % [strand, slot], Vector2.ZERO)

## Residue-position lookup — the shared dependency behind CapsuleArrowOverlay's
## c5_position/c3_position fields (currently set manually) and the upcoming
## camera-choreography target's per-frame midpoint. Same has_/get_ pair shape
## as has_slot_o3_position()/get_slot_o3_position() above, keyed the same way
## ("strand:slot") — matches this file's own established convention rather
## than inventing a new residue-indexing scheme. Strand-generic for free: the
## per-residue loop in _rebuild_layout() that populates _last_capsule_by_key
## runs identically for leading/lagging/template_top/template_bottom (see
## has_slot_o3_position()'s own comment on why the O3'/alpha accessors are
## already strand-generic — same mechanism, same reason, here too). The
## PRIMARY case this needs to be correct for is the self-paired template
## state (both template strands, no fork/enzymes active) — that's just the
## template_top/template_bottom rows of the same generic loop, no special
## casing required. For any strand/slot not currently rendered (off-screen,
## below the full-label... actually below the atom tier entirely, wrong
## strand name, or the crossfade band not yet entered), has_ returns false —
## callers MUST check that first; get_ returns {} (empty Dictionary, a
## documented non-answer) rather than a zero-filled Vector2 pair that could
## be mistaken for a real position at world origin.
func has_residue_capsule_positions(strand: String, slot: int) -> bool:
	return _last_capsule_by_key.has("%s:%d" % [strand, slot])

func get_residue_capsule_positions(strand: String, slot: int) -> Dictionary:
	return _last_capsule_by_key.get("%s:%d" % [strand, slot], {})

## On-demand sibling of get_residue_capsule_positions() above: computes a
## residue's capsule endpoints from scratch, for ANY residue, at ANY zoom —
## including while the atom tier isn't rendering at all. Reads none of the
## per-frame layout state, so it answers before the camera has moved, which
## is the whole point: a Tween needs its end value up front, and the
## rendered position only exists once the camera is already there.
##
## "WHEN CENTERED" is load-bearing, not decoration. A residue has no single
## capsule position — _molecular_render_pos() spreads x outward by
## molecular_extra_slot_spacing * clamp((x - cluster_center_x) /
## slot_spacing, -5, 5), and cluster_center_x is the LIVE camera centre, so
## the answer moves with the camera (up to ~150 world units). What a camera
## shot actually wants is the fixed point: where the capsule sits once the
## camera is centred on it. That's what this returns. Only x is affected —
## the y push (MOLECULAR_ROW_PUSH) has no cluster_center_x term.
##
## Returns {} for a residue not present in the current entry lists (the same
## documented non-answer convention get_residue_capsule_positions() uses) —
## which, for a template strand, doubles as the "is the self-paired template
## state still active" check, since get_template_nucleotides() drops a slot
## once its bead is gone.
func get_residue_capsule_positions_when_centered(strand: String, slot: int) -> Dictionary:
	if replication_mgr == null or tm == null:
		return {}
	var all_entries: Array[Dictionary] = []
	all_entries.append_array(replication_mgr.get_synthesized_nucleotides())
	if template_sim != null:
		all_entries.append_array(template_sim.get_template_nucleotides())

	var target_entry: Dictionary = {}
	for entry in all_entries:
		if entry.strand == strand and entry.slot == slot:
			target_entry = entry
			break
	if target_entry.is_empty():
		return {}

	var bond_length: float = tm.molecular_ring_bond_length_ratio * _slot_spacing()
	# Seeded at the residue's own raw x — already ~the centred configuration,
	# so its neighbours land well inside _molecular_render_pos()'s unclamped
	# +/-5-slot band, which is what makes the single derivation below valid.
	var cluster_center_x: float = target_entry.world_position.x
	var position_by_key: Dictionary = {}
	var base_type_by_key: Dictionary = {}
	for entry in all_entries:
		var key: String = "%s:%d" % [entry.strand, entry.slot]
		position_by_key[key] = _molecular_render_pos(entry.strand, entry.world_position, cluster_center_x)
		base_type_by_key[key] = entry.base_type

	# Derived ONCE, not per fixed-point iteration: the c5/c3 offsets relative
	# to world_pos are camera-independent. _derive_residue_geometry() consumes
	# position_by_key only as DIFFERENCES (pairing_direction, toward_next/
	# toward_previous), and _molecular_render_pos()'s x-spread term cancels in
	# a subtraction — see that function's own extra_x(x2) - extra_x(x1) note.
	# So the expensive part (fold, ring, substituents, derive_base_layout()'s
	# rotation search) stays a one-time cost here.
	var seed_world_pos: Vector2 = _molecular_render_pos(strand, target_entry.world_position, cluster_center_x)
	var geo: Dictionary = _derive_residue_geometry(target_entry, seed_world_pos, bond_length, position_by_key, base_type_by_key)
	var topology: MoleculeTopology = geo.topology
	var local_positions: Dictionary = geo.local_positions
	var c5_id: int = topology.find_by_role("incoming.c5_prime")
	var c3_id: int = topology.find_by_role("incoming.c3_prime")
	if not local_positions.has(c5_id) or not local_positions.has(c3_id):
		return {}
	var c5_offset: Vector2 = local_positions[c5_id] - geo.anchor_offset
	var c3_offset: Vector2 = local_positions[c3_id] - geo.anchor_offset
	var midpoint_offset: Vector2 = (c5_offset + c3_offset) / 2.0

	# Fixed point: the camera centre we're solving for is itself an input to
	# where the capsule lands. Iterating the REAL _molecular_render_pos()
	# (rather than inverting its formula) keeps the +/-5-slot clamp handled
	# exactly. Converges fast — the shift's slope is only
	# molecular_extra_slot_spacing / slot_spacing (~0.56), so error shrinks
	# ~44% per pass; the cap is a guard, not the expected exit.
	for _i in range(16):
		var next_cx: float = _molecular_render_pos(strand, target_entry.world_position, cluster_center_x).x + midpoint_offset.x
		var moved: float = absf(next_cx - cluster_center_x)
		cluster_center_x = next_cx
		if moved < 0.01:
			break

	var world_pos: Vector2 = _molecular_render_pos(strand, target_entry.world_position, cluster_center_x)
	return {c5 = world_pos + c5_offset, c3 = world_pos + c3_offset}

## Atom-tier equivalent of _ligase_gap_bead_position()'s bead-space gap
## target: the midpoint between lagging slot `slot`'s O3' (a completed-but-
## unsealed fragment's last slot) and slot+1's alpha-phosphate (the next
## fragment's, or lagging_current_fragment's, first slot) — the exact two
## positions _build_backbone_bonds() omits a bond between while unsealed.
## Only meaningful when has_lagging_gap_atom_position(slot) is true; callers
## MUST check that first — this returns Vector2.ZERO otherwise, a
## documented non-answer, never a real position.
func get_lagging_gap_atom_position(slot: int) -> Vector2:
	if has_slot_o3_position("lagging", slot) and has_slot_alpha_position("lagging", slot + 1):
		return (get_slot_o3_position("lagging", slot) + get_slot_alpha_position("lagging", slot + 1)) / 2.0
	return Vector2.ZERO

## True if get_lagging_gap_atom_position(slot) has a real answer THIS
## rebuild — both slot's O3' and slot+1's alpha-phosphate were folded and
## on-screen (inside cull_rect) this frame. False whenever either residue is
## off-screen (atom zoom's narrow cull window has scrolled the gap out of
## view) or the crossfade band isn't even entered
## (_transition_fraction <= 0.0). Caller (replication_manager.gd) must treat
## false as "atom-tier position unavailable this frame" and fall back to a
## freshly recomputed bead-tier position — never trust a stale
## ligase.position left over from a previous frame's tier. Also correctly
## false for slot = -1 (the very first Okazaki fragment's own seal, no
## real predecessor slot) with no special-casing needed — "lagging:-1" is
## never a real key.
func has_lagging_gap_atom_position(slot: int) -> bool:
	return has_slot_o3_position("lagging", slot) and has_slot_alpha_position("lagging", slot + 1)


## Desaturation-dip amount for the bead-glyph tier, peaking at the exact
## midpoint of the transition band (parabola, not a triangle, so the dip
## fades in/out with a continuous slope rather than a visible kink at the
## midpoint). Scaled by the ThemeManager-tunable peak magnitude so the
## bead's base-letter color coding is dipped, never fully erased.
func get_transition_desaturation_amount() -> float:
	var shape: float = 4.0 * _transition_fraction * (1.0 - _transition_fraction)
	return shape * tm.molecular_bead_desaturation_peak_amount


## Nested inside skeletal mode: only meaningful while _active is true.
## Same enter/exit hysteresis shape as _compute_active(), against the
## label-band-specific threshold pair.
func _compute_label_full_geometry_active() -> bool:
	if not _active:
		return false
	var z: float = zoom_mgr.zoom.x
	if _label_full_geometry_active:
		return z >= tm.molecular_label_zoom_exit_threshold
	return z >= tm.molecular_label_zoom_enter_threshold


## Nearest mirrored residue whose radius contains the mouse, or "" if none
## qualify. _mirrored_residue_layout is already empty whenever _active is
## false (Task 1) or no residue is currently fork-flip-mirrored, so no
## extra gating is needed here.
func _compute_hovered_mirrored_key() -> String:
	var mouse_pos: Vector2 = get_global_mouse_position()
	var best_key: String = ""
	var best_dist: float = INF
	for m in _mirrored_residue_layout:
		var dist: float = mouse_pos.distance_to(m.world_pos)
		if dist <= m.radius and dist < best_dist:
			best_dist = dist
			best_key = m.key
	return best_key


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
	# strand was visible. Safe to skip entirely below the crossfade band:
	# _draw() guards on the same _transition_fraction condition before
	# reading _atom_layout/_bond_layout/_h_bond_layout, and get_bead_fade_
	# amount()/get_strand_fade_amount() short-circuit before ever
	# consulting _active_slots — nothing downstream depends on these being
	# freshly rebuilt while fully bead-glyph. Gate widened from `not
	# _active` to `_transition_fraction <= 0.0` (bead<->molecular
	# crossfade, Open Question 10): layout must exist throughout the WHOLE
	# band in both scroll directions, not just once _active's own,
	# later-flipping hysteresis has fully committed — otherwise there'd be
	# nothing to fade in from partway through a zoom-in gesture.
	_atom_layout.clear()
	_bond_layout.clear()
	_h_bond_layout.clear()
	_capsule_layout.clear()
	_active_slots.clear()
	_bead_suppressed_slots.clear()
	_mirrored_residue_layout.clear()
	_last_o3_by_key.clear()
	_last_alpha_by_key.clear()
	_last_capsule_by_key.clear()
	if _transition_fraction <= 0.0:
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
	# {c5: Vector2, c3: Vector2} per "strand:slot" — local build, assigned to
	# _last_capsule_by_key only once complete (same two-step "build local,
	# commit at the end" shape as o3_by_key/alpha_by_key below, so a caller
	# querying mid-rebuild never sees a partially-populated frame's worth of
	# residues).
	var capsule_by_key: Dictionary = {}
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

		# Geometry derivation lives in _derive_residue_geometry() (see its own
		# comment) -- everything below consumes what it returns. _active_slots
		# is set above, NOT in there, on purpose.
		var geo: Dictionary = _derive_residue_geometry(entry, world_pos, bond_length, position_by_key, base_type_by_key)
		var topology: MoleculeTopology = geo.topology
		var local_positions: Dictionary = geo.local_positions
		var anchor_offset: Vector2 = geo.anchor_offset
		var is_self_paired_template: bool = geo.is_self_paired_template
		var neighbor_sign: float = geo.neighbor_sign

		var residue_max_extent: float = 0.0
		for atom in topology.atoms:
			if not local_positions.has(atom.id):
				continue
			var local_offset: Vector2 = local_positions[atom.id] - anchor_offset
			residue_max_extent = max(residue_max_extent, local_offset.length())
			var world: Vector2 = world_pos + local_offset
			var full_for_this_atom: bool = _label_full_geometry_active
			_atom_layout.append({
				position = world,
				element = atom.element,
				label = _atom_display_label(atom.role, atom.element, full_for_this_atom),
				atom_id = atom.id,
				nucleotide_slot = entry.slot,
			})

		# Provisional/debug — intra-residue C5'->C3' capsule (see
		# _capsule_layout's own comment above). Both atoms belong to THIS
		# residue's own topology (unlike O3'/alpha-phosphate below, which
		# link neighbor residues), so BUILDING these two positions never
		# needed a cross-residue pass of its own — same in-loop pattern as
		# _atom_layout/_bond_layout above. capsule_by_key below is a
		# different thing: not needed to construct c5/c3 (already have both
		# from local_positions right here), but populated anyway so external
		# callers can LOOK UP a specific residue's positions by strand+slot
		# after the fact — see _last_capsule_by_key's own comment.
		var c5_id: int = topology.find_by_role("incoming.c5_prime")
		var c3_id: int = topology.find_by_role("incoming.c3_prime")
		if local_positions.has(c5_id) and local_positions.has(c3_id):
			var capsule_c5: Vector2 = world_pos + (local_positions[c5_id] - anchor_offset)
			var capsule_c3: Vector2 = world_pos + (local_positions[c3_id] - anchor_offset)
			_capsule_layout.append({c5 = capsule_c5, c3 = capsule_c3})
			capsule_by_key["%s:%d" % [entry.strand, entry.slot]] = {c5 = capsule_c5, c3 = capsule_c3}

		# STAGE 1: bypassed alongside the mirror call above -- nothing is
		# actually mirrored this stage, so nothing should be hoverable
		# either (this is a SEPARATE condition check from the bypassed
		# derivation above, not structurally tied to it -- see that
		# block's own comment -- so it needed its own bypass here).
		if false and is_self_paired_template and neighbor_sign < 0.0:
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
				is_backbone = false,
				order = bond.order,
				always_double = _bond_is_carbonyl(topology, bond),
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

	# Bead-glyph boundary buffer (see _bead_suppressed_slots' doc comment):
	# run only after _active_slots is FULLY populated above, since this
	# needs to know each active residue's own pushed x to decide which side
	# of cluster_center_x it's on — not attemptable inside the main loop,
	# where later entries in `all_entries` haven't been visited yet.
	for key in _active_slots.keys():
		_bead_suppressed_slots[key] = true
		var sep: int = key.rfind(":")
		var strand: String = key.substr(0, sep)
		var slot: int = int(key.substr(sep + 1))
		var x: float = position_by_key[key].x
		var outward_slot: int = slot + 1 if x > cluster_center_x else slot - 1
		_bead_suppressed_slots["%s:%d" % [strand, outward_slot]] = true

	_build_backbone_bonds(o3_by_key, alpha_by_key)
	_last_o3_by_key = o3_by_key
	_last_alpha_by_key = alpha_by_key
	_last_capsule_by_key = capsule_by_key
	_build_hydrogen_bonds(base_bond_atoms_by_key, base_type_by_key)


## Per-residue geometry derivation, lifted verbatim out of
## _rebuild_layout()'s own loop (Step 1 of the on-demand-position
## refactor -- a pure extraction, no behavior change). This is the
## expensive half of that loop: everything its later consumers need
## (_atom_layout, _bond_layout, the C5'/C3' capsule, o3_by_key/
## alpha_by_key, base_bond_atoms_by_key) derives from the returned
## topology/local_positions/anchor_offset triple, so it runs ONCE per
## residue and is deliberately not re-run per consumer -- see
## _rebuild_layout()'s own perf-fix comment for why that matters here.
##
## Reads/writes _fold_cache (persistent for a whole simulation run,
## cleared only by clear_fold_cache()), so a repeat call for the same
## residue skips the fold entirely.
##
## Deliberately does NOT touch _active_slots -- marking a slot active is
## a rendering side effect belonging to the caller, and a future
## on-demand caller must not trigger it for a residue it is merely
## querying. is_self_paired_template/neighbor_sign are returned only
## because the caller's currently-dead _mirrored_residue_layout branch
## still references them.
func _derive_residue_geometry(entry: Dictionary, world_pos: Vector2, bond_length: float, position_by_key: Dictionary, base_type_by_key: Dictionary) -> Dictionary:
	var cache_key: String = "%s:%d" % [entry.strand, entry.slot]
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
	var partner_key: String = _pair_for_slot(entry.strand, entry.slot, base_type_by_key)
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
	# STAGE 1 (docs/superpowers/plans -- reconstruction of the self-
	# paired pentose/phosphate geometry, staged deliberately after the
	# fork-flip mirror and the bake were both found to have real
	# geometry bugs -- see the F9 dump: mirror path produced an exact
	# O3'=C4'/C5'=C3' overlap, bake path produced a C1'-farther-than-
	# C4'-from-base "cross-twist"). Both bake_self_paired_geometry()
	# and reflect_about_backbone_axis() are DELIBERATELY bypassed here,
	# not deleted -- self-paired residues now fall through to the exact
	# same plain formula leading/lagging already use below, matching
	# the fake leading/lagging residues in the test chamber, to
	# establish a known-clean ring/chain baseline before layering
	# orientation-correctness back on top in a later stage. Expected to
	# look orientation-wrong (no antiparallel/self-paired correction)
	# -- that is intentional for this stage, not a regression.
	ring_positions = RiboseDeriver.apply_strand_direction(ring_positions, c1_local, _strand_direction_sign(entry.strand))
	substituent_positions = RiboseDeriver.derive_substituents(topology, "incoming.", ring_positions, bond_length, toward_next, toward_previous)

	# STAGE 2, bottom strand only: reflect C1'/C2'/O4' across the
	# C3'-C4' line (C3'/C4' sit ON that axis so they -- and the
	# substituent chain derived from them above -- are unaffected).
	# Unlike the old, buggy mirror branch, axis_y is read from THIS
	# ring's own post-apply_strand_direction C4' (not the pre-rotation
	# natural ring's), which is what caused the old O3'=C4'/C5'=C3'
	# overlap. Reassigning c1_local to the reflected C1' (rather than
	# leaving it at the natural pivot used above) is deliberate: both
	# anchor_offset and the derive_base_layout() call below read this
	# same variable, so the base re-derives correctly bonded to
	# wherever C1' now sits, with no separate parameter to thread.
	# c1_local's EARLIER use above (apply_strand_direction()'s pivot)
	# already happened, so it's unaffected by this reassignment.
	if is_self_paired_template and neighbor_sign < 0.0:
		var c4_id: int = topology.find_by_role("incoming.c4_prime")
		var axis_y: float = ring_positions[c4_id].y
		ring_positions = RiboseDeriver.reflect_about_backbone_axis(ring_positions, axis_y)
		c1_local = ring_positions[c1_id]

	# STAGE 3, top strand: same transform as Stage 2 immediately above,
	# same reasoning (see that block's comment), the complementary
	# sign. For template_top, apply_strand_direction() above was
	# identity (sign >= 0), so axis_y here is the natural,
	# never-rotated ring's own C4' -- reflect_about_backbone_axis()
	# doesn't care either way, it just mirrors whatever ring it's
	# given about that ring's own current C3'-C4' line.
	if is_self_paired_template and neighbor_sign >= 0.0:
		var c4_id: int = topology.find_by_role("incoming.c4_prime")
		var axis_y: float = ring_positions[c4_id].y
		ring_positions = RiboseDeriver.reflect_about_backbone_axis(ring_positions, axis_y)
		c1_local = ring_positions[c1_id]

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

	return {
		topology = topology,
		local_positions = local_positions,
		anchor_offset = anchor_offset,
		is_self_paired_template = is_self_paired_template,
		neighbor_sign = neighbor_sign,
	}


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
					# Real, sealable Okazaki-fragment nick (helicase+Pol III+
					# ligase complexity) — template_top shares this sign>=0.0
					# branch with lagging (STRAND_DIRECTION_SIGN above), so the
					# gate is on strand == "lagging" specifically, not on which
					# branch got taken. replication_mgr.is_lagging_bond_sealed()
					# reads lagging_fragments live every call, so a mid-session
					# seal (camera parked at atom zoom) shows up on the very
					# next rebuild with no zoom change needed.
					if strand == "lagging" and replication_mgr != null and not replication_mgr.is_lagging_bond_sealed(slot):
						continue
					var from_pos: Vector2 = o3_by_key[key]
					var to_pos: Vector2 = alpha_by_key[next_key]
					_bond_layout.append({points = _build_bond_points(strand, from_pos, to_pos, mode_switch_threshold), is_backbone = true, order = 1, always_double = false})
			else:
				if o3_by_key.has(next_key) and alpha_by_key.has(key):
					var from_pos: Vector2 = o3_by_key[next_key]
					var to_pos: Vector2 = alpha_by_key[key]
					_bond_layout.append({points = _build_bond_points(strand, from_pos, to_pos, mode_switch_threshold), is_backbone = true, order = 1, always_double = false})

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
func _pair_for_slot(strand: String, slot: int, base_type_by_key: Dictionary) -> String:
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
		# First-pair boundary bug fix (screenshot, 2026-08-07): this used to
		# compare position_by_key[self_key].x — a camera-relative RENDER
		# position (_molecular_render_pos()'s outward spread push, up to
		# ~150 world units) — against template_sim.helicase_x, a raw
		# simulation coordinate. Slot 0 is the leftmost residue in the whole
		# molecule, so any camera framing that doesn't center exactly on it
		# (the natural way to view "the first pair," since nothing exists
		# further left to balance the view) pushed its compared x further
		# left, often enough to dip below the raw helicase_x and wrongly
		# report slot 0 as already-unzipped — even paused, helicase never
		# having moved. Fixed by comparing raw-to-raw:
		# nucleotide_original_x lives in the exact same unpushed coordinate
		# space helicase_x does (simulation.gd, built once per sequence load
		# from row_start_x + i * nucleotide_slot_spacing). This also brings
		# the real renderer in line with molecule_geometry_diagnostics.gd's
		# own (already raw-vs-raw) unzipped-slot check, which is why the F9
		# dump could never have caught this on its own.
		if template_sim != null and slot >= 0 and slot < template_sim.nucleotide_original_x.size():
			var world_x: float = template_sim.nucleotide_original_x[slot]
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
func _build_hydrogen_bonds(base_bond_atoms_by_key: Dictionary, base_type_by_key: Dictionary) -> void:
	var seen: Dictionary = {}
	for key in base_bond_atoms_by_key.keys():
		if seen.has(key):
			continue
		var parts: PackedStringArray = key.split(":")
		var strand: String = parts[0]
		var slot: int = int(parts[1])
		var partner_key: String = _pair_for_slot(strand, slot, base_type_by_key)
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
		"C": return tm.molecular_carbon_color
		"N": return tm.molecular_nitrogen_color
		"O": return tm.molecular_oxygen_color
		"P": return tm.molecular_phosphorus_color
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


## Draws a small filled triangle centered (by arc length) on `points`,
## pointing from the polyline's start toward its end — the caller is
## responsible for `points` already being ordered in the direction the
## arrow should point. Works for both the straight-chord (2-point) and
## curve-following (Option C, multi-point) backbone polyline shapes, since
## it walks arc length rather than assuming a fixed point count.
func _draw_backbone_arrowhead(points: Array, color: Color) -> void:
	if points.size() < 2:
		return
	var seg_lengths: Array = []
	var total_length: float = 0.0
	for i in range(points.size() - 1):
		var seg_len: float = (points[i + 1] - points[i]).length()
		seg_lengths.append(seg_len)
		total_length += seg_len
	if total_length <= 0.0:
		return
	var target: float = total_length * 0.5
	var accumulated: float = 0.0
	var mid_pos: Vector2 = points[0]
	var mid_dir: Vector2 = Vector2.RIGHT
	for i in range(seg_lengths.size()):
		var seg_len: float = seg_lengths[i]
		if seg_len <= 0.0:
			continue
		if accumulated + seg_len >= target or i == seg_lengths.size() - 1:
			var local_t: float = clamp((target - accumulated) / seg_len, 0.0, 1.0)
			mid_pos = points[i].lerp(points[i + 1], local_t)
			mid_dir = (points[i + 1] - points[i]) / seg_len
			break
		accumulated += seg_len
	var perp: Vector2 = mid_dir.rotated(PI / 2.0)
	var arrow_len: float = tm.molecular_backbone_arrow_length
	var arrow_half_w: float = tm.molecular_backbone_arrow_half_width
	var tip: Vector2 = mid_pos + mid_dir * (arrow_len * 0.5)
	var base_center: Vector2 = mid_pos - mid_dir * (arrow_len * 0.5)
	var base_a: Vector2 = base_center + perp * arrow_half_w
	var base_b: Vector2 = base_center - perp * arrow_half_w
	draw_polygon(PackedVector2Array([tip, base_a, base_b]), PackedColorArray([color]))


func _draw() -> void:
	if _transition_fraction <= 0.0:
		return
	# Bead<->molecular crossfade (Open Question 10): every color drawn below
	# gets its alpha scaled by this same live fraction, so the whole
	# skeletal tier fades in/out in lockstep with the bead-glyph tier's own
	# fade (get_bead_fade_amount()/get_strand_fade_amount()) rather than
	# either tier popping in first.
	var t: float = _transition_fraction

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
	for b in _bond_layout:
		var points: Array = b.points
		if points.size() < 2:
			continue
		var bond_color: Color = tm.molecular_backbone_bond_color if b.is_backbone else tm.molecular_bond_color
		bond_color.a *= t
		var bond_width: float = tm.molecular_backbone_bond_width if b.is_backbone else tm.molecular_bond_width
		# Double-bond parallel trace (bond-thickness design pass): only ever
		# order==2 intra-residue bonds (carbonyl/aromatic/phosphate P=O) —
		# backbone bonds are always order 1 (a phosphodiester linkage never
		# doubles), so this never has to contend with curve-following
		# multi-point polylines (Option C), only plain 2-point chords.
		# Coarse (element-only) label band shows ONLY carbonyls double
		# (b.always_double); the full-geometry band shows every real
		# double bond.
		var draw_double: bool = b.order == 2 and (_label_full_geometry_active or b.always_double)
		# Each trace of a double bond is drawn at half the regular width —
		# two full-width lines side by side would read as "twice as thick,"
		# not "one double bond."
		if draw_double:
			bond_width *= 0.5
		var bond_half_width: float = bond_width * 0.5
		var segments: Array = [points]
		if draw_double and points.size() == 2:
			var direction: Vector2 = (points[1] - points[0]).normalized()
			var perp: Vector2 = direction.rotated(PI / 2.0) * (tm.molecular_double_bond_offset * 0.5)
			segments = [
				[points[0] + perp, points[1] + perp],
				[points[0] - perp, points[1] - perp],
			]
		for seg_points in segments:
			var drawn_points: Array = seg_points.duplicate()
			var inset_first: PackedVector2Array = ProceduralShapeUtils.inset_segment(
				seg_points[0], seg_points[1], tm.molecular_atom_radius, 0.0
			)
			if inset_first.size() >= 1:
				drawn_points[0] = inset_first[0]
			var last_i: int = seg_points.size() - 1
			var inset_last: PackedVector2Array = ProceduralShapeUtils.inset_segment(
				seg_points[last_i - 1], seg_points[last_i], 0.0, tm.molecular_atom_radius
			)
			if inset_last.size() >= 2:
				drawn_points[last_i] = inset_last[1]
			for i in range(drawn_points.size() - 1):
				draw_line(drawn_points[i], drawn_points[i + 1], bond_color, bond_width, false)
			for p in drawn_points:
				draw_circle(p, bond_half_width, bond_color, true, -1.0, false)

		# 5'->3' direction arrowhead, full-label zoom tier only (design
		# decision doc: directional arrows on phosphodiester bonds). `points`
		# is already ordered O3'-end (more-5' residue) -> alpha-phosphate-end
		# (more-3' residue) — see _build_backbone_bonds()'s own doc comment
		# and molecular_backbone_bond_color's "5'->3' thread" comment above
		# — so pointing toward the LAST point is the correct 5'->3' direction,
		# not the first (O3') one.
		if b.is_backbone and _label_full_geometry_active:
			var arrow_color: Color = tm.molecular_backbone_arrow_color
			arrow_color.a *= t
			_draw_backbone_arrowhead(points, arrow_color)

	# Hydrogen bonds: one dotted line per REAL atom pair
	# (docs/MolecularStructure_BasePairExpansion.md — supersedes the old
	# parallel-offset-from-one-anchor approximation). Each segment already
	# carries its own real world endpoints (HBOND_OWN_TO_PARTNER_ROLES,
	# _build_hydrogen_bonds()) — no perp/offset math, no dash spacing of
	# any kind involved here anymore.
	for h in _h_bond_layout:
		var h_color: Color = h.color
		h_color.a *= t
		for seg in h.segments:
			_draw_dotted_line(seg.a, seg.b, h_color, tm.molecular_h_bond_dot_radius, tm.molecular_h_bond_dot_gap)

	# Atoms: element-colored circle + counter-rotated label, mirroring
	# nucleotide_field.gd's exact per-glyph transform pattern (cache the
	# ZoomManager REFERENCE, read rotation LIVE here) — including the
	# MANDATORY draw_set_transform reset after each label, since the loop
	# continues and the next atom's draw_circle() uses absolute coords.
	var label_rotation: float = zoom_mgr.get_label_counter_rotation() if zoom_mgr != null else 0.0
	var font: Font = tm.molecular_atom_label_font
	if font == null:
		font = tm.base_label_font if tm.base_label_font != null else ThemeDB.fallback_font
	# Dedicated fields, NOT tm.base_label_font_size — that value is
	# proportioned for the bead-glyph mode's base_radius (15 world units);
	# reused directly against molecular_atom_radius (6.0) it was ~2.5x too
	# large relative to its own atom circle. See the fields' own doc
	# comments in theme_manager.gd. Selects between the closer band's
	# full-geometry size and the wider band's element-only size (Part 1,
	# docs/atomtier/AtomTier_VisualDesign.md), per _label_full_geometry_active.
	var font_size: int = tm.molecular_atom_label_font_size if _label_full_geometry_active else tm.molecular_atom_label_font_size_element_only
	var atom_label_color: Color = tm.base_label_color
	atom_label_color.a *= t
	for a in _atom_layout:
		var atom_color: Color = _element_color(a.element)
		atom_color.a *= t
		draw_circle(a.position, tm.molecular_atom_radius, atom_color, true, -1.0, false)
		if font != null:
			var ssize: Vector2 = font.get_string_size(a.label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var ascent: float = font.get_ascent(font_size)
			var draw_pos: Vector2 = Vector2(-ssize.x / 2.0, ascent - ssize.y / 2.0)
			draw_set_transform(a.position, label_rotation, Vector2.ONE)
			draw_string(font, draw_pos, a.label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, atom_label_color)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Fork-flip hover disclaimer (docs/superpowers/specs/
	# 2026-08-04-fork-flip-disclaimer-design.md): drawn last so it renders
	# on top of atoms/bonds/labels. Hardcoded background/text colors —
	# no established draw_rect() convention or theme fields exist in this
	# file to reuse, and this is a small, self-contained overlay, not
	# something worth a new theme_manager.gd surface for.
	if _hovered_mirrored_key != "":
		var hovered_world_pos: Vector2 = Vector2.ZERO
		var hovered_radius: float = 0.0
		for m in _mirrored_residue_layout:
			if m.key == _hovered_mirrored_key:
				hovered_world_pos = m.world_pos
				hovered_radius = m.radius
				break
		var tooltip_font: Font = tm.base_label_font if tm.base_label_font != null else ThemeDB.fallback_font
		if tooltip_font != null:
			var tooltip_font_size: int = tm.molecular_atom_label_font_size
			var text_size: Vector2 = tooltip_font.get_string_size(MIRRORED_RESIDUE_TOOLTIP_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, tooltip_font_size)
			var padding: Vector2 = Vector2(6.0, 4.0)
			var tooltip_offset: Vector2 = Vector2(-text_size.x / 2.0, -hovered_radius)
			var box_pos: Vector2 = tooltip_offset - padding
			var box_size: Vector2 = text_size + padding * 2.0
			draw_set_transform(hovered_world_pos, label_rotation, Vector2.ONE)
			draw_rect(Rect2(box_pos, box_size), Color(0.0, 0.0, 0.0, 0.75 * t), true)
			var text_pos: Vector2 = tooltip_offset + Vector2(0.0, tooltip_font.get_ascent(tooltip_font_size))
			draw_string(tooltip_font, text_pos, MIRRORED_RESIDUE_TOOLTIP_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, tooltip_font_size, atom_label_color)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
