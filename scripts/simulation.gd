extends Node2D

# ==========================================
# v 81 — NAD+ pass (bacterial ligase gets its cofactor)
# - is_enabled("ligase_cofactor") stopped being a topology GATE and became a
#   plain proxy for cofactor_activation_enabled — ligase has a cofactor in
#   BOTH modes now. WHICH one is a separate question, answered by the new
#   ComplexityManager.ligase_uses_nad() (true in Circular/bacterial mode),
#   deliberately kept out of is_enabled() itself: mixing a mode PARAMETER
#   into that boolean would make "false" ambiguous between "lens off" and
#   "wrong donor for this mode."
# - ligase_cofactor.gd: _ppi_group -> _leaving_group. New donor_is_nad flag,
#   set by replication_manager.gd from ligase_uses_nad() before every
#   begin_carry() (topology can change between one seal and the next). New
#   _apply_donor(): ATP -> second bead "P" + thick fused link (PPi, must not
#   read as two loose Pi); NAD+ -> second bead "N" + ordinary link (NMN's two
#   beads are already visually distinct by colour, so the fused treatment
#   would falsely claim a "rigid unit" NMN doesn't have). The AMP half is
#   entirely untouched — adenylylation is chemically identical for both
#   donors, so nothing there needed to change.
# - New ThemeManager field: cofactor_nicotinamide_color.
# - complexity_setup_popup.gd: _update_cofactor_mode_note() REMOVED — it
#   explained an absence ("ligase has no cofactor here"), and the absence is
#   filled. Left as a comment rather than silently deleted.
# - ui_strings.csv: UI_ATP_TOGGLE_LABEL / UI_ATP_BYPRODUCTS_TOGGLE_LABEL /
#   UI_ATP_BYPRODUCTS_REQUIRES_ATP_TOOLTIP -> UI_COFACTOR_* (copy updated:
#   byproducts list now includes NMN). UI_ATP_BACTERIAL_LIGASE_NAD_TOOLTIP
#   deleted outright, not carried forward.
# - Zero helicase changes. Its bonds and byproducts are still pure ATP
#   (helicase runs on ATP in every domain — see v80's header on why atp_*
#   stayed atp_* there).
#
# CURRENT VERSION ONLY. Prior versions live in CHANGELOG.md — when
# delivering a new version, move this block there first, then write the new
# one here. This header never accumulates more than one version.
# ==========================================

# ---------- SIGNALS ----------
signal progress_changed(new_progress: float)  # 0.0 - 1.0
signal simulation_initialized(total_bases: int)
## LongSequenceDesign.md follow-up: emitted by request_drag_scrub() below,
## the one funnel point for helicase_ring.gd's and both polymerase clamps'
## drag-to-scrub gestures — player_ui.gd connects to this the same way it
## already connects to the two signals above.
signal drag_scrub_requested(index: int)

# ---------- EXPORTS ----------
const VERTICAL_PLAYER_UI_SCENE: PackedScene = preload("res://scenes/VerticalPlayerUI.tscn")
const NewNitrogenBaseScene := preload("res://scenes/nitrogen_base.tscn")

@onready var background_rect: ColorRect = $CanvasLayer/ColorRect
@onready var rail_path: Path2D = $RailPath
@onready var template_strand_original_track: Line2D = $TemplateStrandOriginalTrack

@onready var synthesis_circle: Node2D = $SynthesisCircle

@onready var backbone_line: Line2D = $BackboneLine
@onready var hydrogen_bonds_container: Node2D = $HydrogenBondsContainer
@onready var template_hydrogen_bonds_container: Node2D = $TemplateHydrogenBondsContainer
@onready var top_rail_path: Path2D = $TopRailPath
@onready var top_template_new_track: Line2D = $TopTemplateStrandNewTrack
@onready var nucleotide_field: Node = $NucleotideField  # decorative free-nucleotide layer; scene node, not code-instantiated — see nucleotide_field.gd
@onready var molecule_renderer: Node = $MoleculeStructureRenderer  # deep-zoom skeletal ribose renderer; scene node, not code-instantiated — see molecule_structure_renderer.gd

# ---------- SUB-MANAGERS ----------
var helicase_mgr: Node = null   # helicase.gd instance, added as child in initialize_simulation
var replication_mgr: Node = null  # replication_manager.gd instance, persists across sequences

@export_group("Track Layout")
@export var nucleotide_slot_spacing: float = 54.0
@export var num_nucleotide_slots: int = 30  # Default length; can be overridden by sequence
@export var center_y: float = 360.0  # Vertical screen-center anchor; all strand/enzyme y positions derive from this
@export var nucleotide_slot_size: Vector2 = Vector2(24, 24)
var track_length: float = 0.0
@export var polymerase_y_offset: float = 120.0  # Renamed from new_bottom_template_offset: vertical distance each polymerase sits from center_y
@export var dna_ribbons_gap: float = 90.0


@export var polymerase_x_offset_slots: float = 4.0  # Multiplied by nucleotide_slot_spacing for polymerase_x distance from helicase_x
@export var pll_slot_count: int = 4

@export_group("Speeds & Timing")
@export var okazaki_fragment_size: int = 12  # Slots per Okazaki fragment (boundary arithmetic only). Raised from 6 so a 3-slot primer (primer_length_ratio = 0.25, see OkazakiMaturationDesign.md) is a sensible fraction of the fragment rather than half of it.
@export var telomere_primer_footprint: int = 2  # Slots at the strand's terminal end the lagging polymerase can never synthesize — end-replication-problem stand-in; primer/primase not modeled yet  # Slots per Okazaki fragment (boundary arithmetic only)
@export var fade_duration: float = 0.6
@export var settling_duration: float = 0.5
@export var settling_threshold: float = 2.0
@export var lagging_gap_enabled: bool = false  # false: base complexity — lagging polymerase catches up, closing the strand fully. true: reserved for the telomerase tier, where the trailing gap is left standing.
@export var ligase_enabled: bool = false  # false: base complexity — continuous lagging backbone (no ligase modeled). true: reserved for the ligase tier — per-fragment backbone with visible nicks until ligase joins them.
@export var lagging_catchup_step_duration: float = 0.3  # pace of post-DONE catch-up firing — independent of helicase timing, since there's no fork driving it anymore


@export_group("Wobble")
@export var wobble_amplitude: float = 2.0
@export var wobble_speed: float = 1.5
@export var wobble_phase_offset: float = 0.8


# ---------- STATE VARIABLES ----------
var template_strand_y: float = 0.0  # Derived: center_y + dna_ribbons_gap / 2.0 — bottom template strand's resting y
var new_top_template_y: float = 0.0
var new_bottom_template_y: float = 0.0  # ADD — bottom template's unzipped row, mirrors new_top_template_y

var helicase_node: Node2D = null
var helicase_ring: HelicaseRing = null   # child of helicase_node; rides its position/modulate for free
var helicase_atp_cycle: HelicaseAtpCycle = null           # sibling of helicase_ring under helicase_node; same free ride
var _ring_drag_start_index: int = 0      # scrub index when the ring's current drag gesture began

var wobble_time: float = 0.0

var helicase_x: float = 0.0   # Derived each frame from helicase_mgr
var polymerase_x: float = 0.0   # Derived: helicase_x - polymerase_x_offset_slots * nucleotide_slot_spacing
var polymerase_y_lagging: float = 0.0   # Derived: center_y + polymerase_y_offset (lagging polymerase y)
var polymerase_y_leading: float = 0.0   # Derived: center_y - polymerase_y_offset (leading polymerase y)


# Phase is now owned by helicase_mgr. Use helicase_mgr.get_phase() or
# helicase_mgr.Phase.* constants for phase checks.
# pulse_width is kept for Okazaki fragment boundary arithmetic.


var settle_blend: float = 0.0



# ---------- DYNAMIC ARRAYS (rebuilt on initialize) ----------
var template_strand_bottom: Array[PathFollow2D] = []
var nucleotide_bases: Array = []
var nucleotide_original_x: Array[float] = []

var nucleotide_backbone_delta: Array[float] = []

var bond_marks: Array[Node2D] = []
var new_strand_backbone_line: Line2D  # kept for ligase; managed by replication_mgr

var top_strand_slots: Array[PathFollow2D] = []
var top_strand_bases: Array = []
var top_strand_backbone_delta: Array[float] = []
var top_strand_bond_marks: Array[Node2D] = []
var top_strand_backbone_line: Line2D
var template_hydrogen_bonds: Array = []

var marker_template_5p: Node2D = null
var marker_template_3p: Node2D = null
var marker_top_5p: Node2D = null
var marker_top_3p: Node2D = null

# ---------- SINGLE SOURCE OF TRUTH ----------
var dna_sequence := DnaSequenceResource.new()

# ---------- SCRUBBER / PLAYBACK CONTROL ----------
var manual_override: bool = false  # Mirrored on replication_mgr; kept here for toggle_play logic
var lagging_last_catchup_step: int = 0

# ==========================================
# LIFECYCLE
# ==========================================

## Swap PlayerUI for its vertical sibling when vertical_mode is on
## (VerticalModeDesign.md step 7). Both scenes share ONE script — player_ui.gd —
## and satisfy the same unique-name contract; the vertical one simply omits
## SequenceLabel and the whole ZoomControls row, which that script treats as
## optional via get_node_or_null().
##
## Deliberately asymmetric: the horizontal path is left completely untouched, so
## the working PC build carries zero risk from this. Only the vertical branch is
## new code.
##
## The one thing this has to do by hand is `simulation` — PlayerUI.tscn's
## instance in simulation.tscn has that @export wired in the editor
## (node_paths=PackedStringArray("simulation")), which a runtime instantiation
## can't inherit. Assign it BEFORE add_child(), since player_ui.gd's _ready()
## reads it.
func _swap_in_vertical_player_ui(zoom_mgr) -> void:
	if not zoom_mgr.vertical_mode:
		return
	var ui_root := get_node_or_null("UI")
	var old_ui := get_node_or_null("UI/PlayerUI")
	if ui_root == null or old_ui == null:
		push_error("simulation.gd: vertical_mode on, but UI/PlayerUI not found — keeping horizontal UI.")
		return
	# Children _ready() before parents, so the horizontal PlayerUI has already
	# fully initialised and connected by the time we get here. Freeing it drops
	# those connections with it (Godot disconnects on free), so the two never
	# both respond to a signal.
	old_ui.queue_free()
	var vertical = VERTICAL_PLAYER_UI_SCENE.instantiate()
	vertical.name = "PlayerUI"   # keep the node path stable
	vertical.simulation = self   # the editor-wired @export, by hand
	ui_root.add_child(vertical)
	print("[VERTICAL] PlayerUI -> VerticalPlayerUI")

func _ready():
	# Register the helicase zoom target once. The frame-providers close over
	# `self` and look up helicase_node/replication_mgr fresh each call — must
	# NOT cache the node directly, since helicase_node is freed and recreated
	# on every sequence load (see teardown_simulation() / _setup_helicase()).
	# NOTE: entry_level is now 2 (was 3) — now that level 2 has real content
	# (see below), selecting "Helicase" from the dropdown jumps straight to
	# level 2, same as the new-strand targets, rather than skipping to 3.
	var zoom_mgr = get_node_or_null("%ZoomManager")
	if zoom_mgr != null:
		zoom_mgr.register_target("helicase", {2: _zoom_frame_helicase_level2, 3: _zoom_frame_helicase_level3}, "ENZYME_HELICASE", _zoom_helicase_visible)
		_swap_in_vertical_player_ui(zoom_mgr)

	# Molecular Structure (Growth Session 2, base-pair expansion): the
	# renderer needs a read-only feed of the ORIGINAL template strand's own
	# nucleotides — simulation.gd is the only script that owns those (see
	# get_template_nucleotides()). molecule_renderer is a persisted scene
	# node (always present, unlike replication_mgr which is lazily
	# .new()'d on first sequence load), and Godot calls child _ready()
	# before parent _ready(), so molecule_renderer.tm/zoom_mgr are already
	# set by the time this runs — safe to wire here rather than in
	# initialize_simulation().
	if molecule_renderer != null:
		molecule_renderer.set_template_source(self)

	# Startup gate (v76): complexity toggles first, then sequence selection —
	# replaces the old auto-random-sequence boot. See OkazakiMaturationDesign.md
	# for the toggle set this screen exposes.
	var complexity_popup = get_node_or_null("UI/ComplexitySetupPopup")
	if complexity_popup != null:
		complexity_popup.setup_confirmed.connect(_on_startup_complexity_confirmed, CONNECT_ONE_SHOT)
		complexity_popup.show_dialog()
	else:
		push_error("Simulation: ComplexitySetupPopup not found — falling back to default boot")
		_boot_with_random_sequence()

func _on_startup_complexity_confirmed() -> void:
	# Hands off to the existing SequenceLoaderPopup. Its sequence_loaded
	# signal is already connected in player_ui.gd's _ready() to
	# simulation.initialize_simulation() — this just decides WHEN it first
	# opens, it does not add a second listener on that signal.
	var seq_popup = get_node_or_null("UI/SequenceLoaderPopup")
	if seq_popup != null:
		seq_popup.show_dialog()
	else:
		push_error("Simulation: SequenceLoaderPopup not found — falling back to default boot")
		_boot_with_random_sequence()

func _boot_with_random_sequence() -> void:
	dna_sequence.randomize_sequence(num_nucleotide_slots)
	initialize_simulation(dna_sequence._to_string())

# ==========================================
# ZOOM / HIGHLIGHT
# Frame-providers for the helicase zoom target, and per-frame highlight-dim
# application for the strand visuals this file owns directly. See
# ZoomDesign.md. ZoomManager only ever queries dim factors — it never writes
# modulate/self_modulate on nodes it doesn't own, so there's exactly one
# writer per property.
# ==========================================

## Fit percentages, same tunable-by-eye pattern that worked for the
## new-strand targets — nudge these directly if the framing needs
## adjustment once tested in-engine.

## Level 2 — "regional context": camera CENTERS ON the helicase itself
## (the highlighted object), sized just wide/tall enough that LEADING
## polymerase also fits in frame. Lagging is deliberately EXCLUDED from
## this sizing calculation — same fix as _zoom_frame_lagging_level2()'s own
## Level 2, applied here for the same reason: lagging periodically swings
## far from the helicase (Okazaki fragment jump-back), and including it
## here would force the zoom to double outward to keep it in frame every
## cycle, the same runaway-zoom problem already fixed for lagging's own
## view. Leading stays close at all times, so sizing around it alone keeps
## this view's zoom stable. Lagging is free to wander in and out of frame
## as it does its own thing — its disappearing/reappearing is itself part
## of the "leading is steady, lagging chases" contrast this view exists to
## teach, not something to compensate for.
## Frame providers compute their own zoom, so they need the viewport extent
## that currently corresponds to a given WORLD axis. ZoomManager owns that
## mapping (VerticalModeDesign.md) — ask it rather than reading get_viewport()
## here, so exactly one file knows which way is up. Fallbacks match the
## previous inline defaults for the no-viewport case.
## The glyph counter-rotation, asked of ZoomManager rather than derived here —
## same single-source-of-truth reason as _zoom_along_extent() above. 0.0 in
## horizontal mode, so every set_label_rotation() call below is a no-op there.
func _zoom_label_rotation() -> float:
	var zm = get_node_or_null("%ZoomManager")
	return zm.get_label_counter_rotation() if zm != null else 0.0

func _zoom_along_extent() -> float:
	var zm = get_node_or_null("%ZoomManager")
	return zm.get_along_extent() if zm != null else 1152.0

func _zoom_cross_extent() -> float:
	var zm = get_node_or_null("%ZoomManager")
	return zm.get_cross_extent() if zm != null else 648.0

func _zoom_frame_helicase_level2() -> Dictionary:
	if helicase_node == null or not is_instance_valid(helicase_node):
		return {}
	var context: Array = []
	if replication_mgr != null and replication_mgr.leading_polymerase != null and is_instance_valid(replication_mgr.leading_polymerase):
		context.append(replication_mgr.leading_polymerase.global_position)

	if context.is_empty():
		return _helicase_footprint_frame(%ThemeManager.zoom_helicase_level2_fit)

	return _anchor_centered_frame(helicase_node.global_position, context, %ThemeManager.zoom_helicase_level2_fit)

## Centers the camera ON `anchor` (the highlighted object) — NOT on the
## bounding-box midpoint of anchor+context, which is what a naive box-fit
## would do and is exactly the bug this replaced: it pulled the camera
## toward whatever's between the helicase and its polymerases instead of
## keeping the helicase itself as the visual center. Sizes the frame
## symmetrically around the anchor just far enough to include every context
## point, so the anchor is guaranteed to land dead-center on screen.
func _anchor_centered_frame(anchor: Vector2, context: Array, fit_pct: float) -> Dictionary:
	var max_dx: float = 0.0
	var max_dy: float = 0.0
	for p in context:
		max_dx = max(max_dx, abs(p.x - anchor.x))
		max_dy = max(max_dy, abs(p.y - anchor.y))
	var size: Vector2 = Vector2(max(max_dx * 2.0, 1.0), max(max_dy * 2.0, 1.0))
	# size.x is a world-x span, size.y a world-y span. The extent helpers supply
	# whichever viewport dimension each currently maps to — the rotation is
	# exactly 90 degrees, so the box stays axis-aligned and needs no transform.
	var target_zoom: float = minf((_zoom_along_extent() * fit_pct) / size.x, (_zoom_cross_extent() * fit_pct) / size.y)
	return {zoom = target_zoom, position = anchor}

func _zoom_frame_helicase_level3() -> Dictionary:
	return _helicase_footprint_frame(%ThemeManager.zoom_helicase_level3_fit)

## Geometrically-derived footprint, reusing the EXACT formula
## helicase_ring.gd already uses for its own label placement
## (ring_radius + max_blob_height * 0.5 = "the ring's tallest reach", per
## its own comment) — doubled for full height. Grounded in real geometry
## rather than a guessed constant, and automatically stays correct if
## ring_radius/max_blob_height are ever retuned in the Inspector.
func _helicase_footprint_frame(fit_pct: float) -> Dictionary:
	if helicase_node == null or not is_instance_valid(helicase_node) or helicase_ring == null:
		return {}
	var footprint_height: float = 2.0 * helicase_ring.ring_radius + helicase_ring.max_blob_height
	if footprint_height <= 0.0:
		return {}
	# footprint_height is a world-y span — i.e. ACROSS the track — so it fits
	# against the cross-axis viewport extent in both orientations.
	var target_zoom: float = (_zoom_cross_extent() * fit_pct) / footprint_height
	return {zoom = target_zoom, position = helicase_node.global_position}

## Reuses helicase_node's own modulate.a — the exact signal it already sets
## to 0.0 before the first play and 1.0 once faded in — rather than
## introducing a second, possibly-out-of-sync notion of "visible."
func _zoom_helicase_visible() -> bool:
	return helicase_node != null and is_instance_valid(helicase_node) and helicase_node.modulate.a > 0.01

func _apply_zoom_highlight() -> void:
	var zoom_mgr = get_node_or_null("%ZoomManager")
	if zoom_mgr == null:
		return

	# Helicase: writes helicase_ring's own `modulate` — NOT self_modulate.
	# self_modulate was a real bug (confirmed via screenshots): helicase_ring
	# is itself just a Node2D container with no drawing of its own — the
	# actual barrel-roll blobs are its own children (_blobs), so
	# self_modulate on the ring had no visible effect. Regular `modulate`
	# propagates to children and is still conflict-free here: helicase_node
	# (the parent) is what the play/pause fade and intro tween write to,
	# never helicase_ring's own modulate — still exactly one writer per
	# property, one level down from where this used to sit. Also fixes the
	# helicase's label not dimming (a child too, unreached by self_modulate).
	if helicase_ring != null:
		helicase_ring.modulate.a = zoom_mgr.get_enzyme_highlight_dim("helicase")

	# Template-strand visuals: plain modulate.a is safe here — nothing else
	# writes it, EXCEPT molecular-structure occlusion (bug A,
	# MolecularStructure_BasePairExpansion.md), folded in directly below
	# rather than living as a second writer in the render loop — this
	# function is called mid-_process(), and a write placed before this
	# call (as the bottom-template one originally was) got silently
	# clobbered back to strand_dim right here every frame. Molecular
	# suppression always wins over strand_dim (0.0, not multiplied).
	var strand_dim = zoom_mgr.get_strand_highlight_dim()
	var template_bottom_active: bool = molecule_renderer != null and molecule_renderer.is_strand_active("template_bottom")
	var template_top_active: bool = molecule_renderer != null and molecule_renderer.is_strand_active("template_top")
	if backbone_line != null: backbone_line.modulate.a = 0.0 if template_bottom_active else strand_dim
	if top_strand_backbone_line != null: top_strand_backbone_line.modulate.a = 0.0 if template_top_active else strand_dim
	if hydrogen_bonds_container != null: hydrogen_bonds_container.modulate.a = strand_dim
	if template_hydrogen_bonds_container != null: template_hydrogen_bonds_container.modulate.a = strand_dim
	if template_strand_original_track != null: template_strand_original_track.modulate.a = strand_dim
	if top_template_new_track != null: top_template_new_track.modulate.a = strand_dim
	if marker_template_5p != null: marker_template_5p.modulate.a = strand_dim
	if marker_template_3p != null: marker_template_3p.modulate.a = strand_dim
	if marker_top_5p != null: marker_top_5p.modulate.a = strand_dim
	if marker_top_3p != null: marker_top_3p.modulate.a = strand_dim

func _notify_zoom_scrub() -> void:
	# Cancels any in-flight zoom level/target tween and snaps the camera
	# straight to the correct position — scrub is always instant, and the
	# camera must match (see ZoomDesign.md's scrub-safety split).
	var zoom_mgr = get_node_or_null("%ZoomManager")
	if zoom_mgr != null and zoom_mgr.has_method("scrub_snap"):
		zoom_mgr.scrub_snap()

func initialize_simulation(sequence: String):
	# Validate and clean the sequence
	sequence = dna_sequence.clean_sequence(sequence)
	var min_sequence_length = int(polymerase_x_offset_slots) + okazaki_fragment_size + telomere_primer_footprint + 1
	if sequence.length() > DnaSequenceResource.MAX_LENGTH:
		sequence = sequence.substr(0, DnaSequenceResource.MAX_LENGTH)
		print("[WARN] Sequence truncated to %d bases" % DnaSequenceResource.MAX_LENGTH)
	elif sequence.length() < min_sequence_length:
		var pad_chars = "ATCG"
		while sequence.length() < min_sequence_length:
			sequence += pad_chars[randi() % pad_chars.length()]
		print("[WARN] Sequence padded to minimum %d bases" % min_sequence_length)

	# 1. TEARDOWN old simulation
	teardown_simulation()

	# 2. LOAD the sequence into the resource
	dna_sequence.set_from_string(sequence)

	# 3. Update parameters from the resource
	num_nucleotide_slots = dna_sequence.get_length()
	var polymerase_x_offset = polymerase_x_offset_slots * nucleotide_slot_spacing
	track_length = (num_nucleotide_slots - 1) * nucleotide_slot_spacing + 2.0 * polymerase_x_offset
	
	# Environmental free-nucleotide field — count scales with sequence length;
	# runs on every load, including the first.
	if nucleotide_field != null:
		nucleotide_field.on_sequence_changed(num_nucleotide_slots)

	# 4. RESET all state variables
	helicase_x = polymerase_x_offset
	polymerase_x = 0.0
	settle_blend = 0.0
	manual_override = true  # Start paused when a new sequence loads

	# 4b. Create or re-initialize helicase manager
	if helicase_mgr != null:
		helicase_mgr.queue_free()
	var HelicastScript = load("res://scripts/helicase.gd")
	helicase_mgr = HelicastScript.new()
	add_child(helicase_mgr)
	helicase_mgr.initialize(num_nucleotide_slots, settling_duration)
	helicase_mgr.slot_reached.connect(_on_helicase_slot_reached)
	helicase_mgr.phase_changed.connect(_on_helicase_phase_changed)

	# 4c. Create replication manager once; reset it for each new sequence
	if replication_mgr == null:
		var RepScript = load("res://scripts/replication_manager.gd")
		replication_mgr = RepScript.new()
		add_child(replication_mgr)
		replication_mgr.initialize(self)
		molecule_renderer.set_replication_manager(replication_mgr)
		replication_mgr.set_molecule_renderer(molecule_renderer)

	replication_mgr.connect_helicase(helicase_mgr)

	template_strand_y = center_y + dna_ribbons_gap / 2.0
	new_top_template_y = center_y - dna_ribbons_gap / 2.0 - polymerase_y_offset
	new_bottom_template_y = center_y + dna_ribbons_gap / 2.0 + polymerase_y_offset  # ADD
	polymerase_y_lagging = center_y + polymerase_y_offset
	polymerase_y_leading = center_y - polymerase_y_offset

	# 5. REBUILD all visual elements
	_rebuild_rail()
	_spawn_nucleotide_slots()
	_setup_helicase()

	# All enzymes start invisible; they fade in on first play.
	if helicase_node:
		helicase_node.modulate.a = 0.0

	backbone_line.default_color = %ThemeManager.template_backbone_color
	backbone_line.width = %ThemeManager.backbone_line_width
	backbone_line.z_index = -1
	backbone_line.joint_mode = Line2D.LINE_JOINT_ROUND
	backbone_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	backbone_line.end_cap_mode = Line2D.LINE_CAP_ROUND

	top_strand_backbone_line = Line2D.new()
	top_strand_backbone_line.default_color = %ThemeManager.template_backbone_color
	top_strand_backbone_line.width = %ThemeManager.backbone_line_width
	top_strand_backbone_line.z_index = -1
	top_strand_backbone_line.joint_mode = Line2D.LINE_JOINT_ROUND
	top_strand_backbone_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	top_strand_backbone_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(top_strand_backbone_line)

	_spawn_top_strand()
	_rebuild_top_rail()
	for i in range(top_strand_slots.size()):
		top_strand_slots[i].progress = track_length - nucleotide_original_x[i]

	# Initialize replication manager for this sequence
	replication_mgr.reset(num_nucleotide_slots)
	replication_mgr.setup_backbones()
	#new_strand_backbone_line = replication_mgr.new_strand_backbone_line

	# Strand end markers
	var first_x = nucleotide_original_x[0]
	var last_x = nucleotide_original_x[num_nucleotide_slots - 1]
	marker_template_5p = _spawn_marker("5'", Vector2(last_x + %ThemeManager.marker_offset, template_strand_y))
	marker_template_3p = _spawn_marker("3'", Vector2(first_x - %ThemeManager.marker_offset, template_strand_y))
	marker_top_5p = _spawn_marker("5'", Vector2(first_x - %ThemeManager.marker_offset, template_strand_y - dna_ribbons_gap))
	marker_top_3p = _spawn_marker("3'", Vector2(last_x + %ThemeManager.marker_offset, template_strand_y - dna_ribbons_gap))

	# 6. Emit signal so UI can update its slider max_value and reset
	simulation_initialized.emit(num_nucleotide_slots)

	# Force an immediate visual update
	queue_redraw()
	print("[INIT] Simulation initialized with %d bases: %s" % [num_nucleotide_slots, dna_sequence._to_string()])

func teardown_simulation():
	# Clear all dynamic nodes
	# Delegate synthesis node cleanup to replication_mgr
	if replication_mgr != null:
		replication_mgr.teardown()

	var nodes_to_free: Array[Node] = []

	# Collect template-owned nodes only
	nodes_to_free.append_array(template_strand_bottom)
	nodes_to_free.append_array(nucleotide_bases)
	nodes_to_free.append_array(top_strand_slots)
	nodes_to_free.append_array(top_strand_bases)
	nodes_to_free.append_array(template_hydrogen_bonds)
	nodes_to_free.append_array(bond_marks)
	nodes_to_free.append_array(top_strand_bond_marks)

	if top_strand_backbone_line:
		nodes_to_free.append(top_strand_backbone_line)
	if marker_template_5p:
		nodes_to_free.append(marker_template_5p)
	if marker_template_3p:
		nodes_to_free.append(marker_template_3p)
	if marker_top_5p:
		nodes_to_free.append(marker_top_5p)
	if marker_top_3p:
		nodes_to_free.append(marker_top_3p)

	if helicase_node:
		nodes_to_free.append(helicase_node)

	for node in nodes_to_free:
		if is_instance_valid(node) and node != null:
			node.queue_free()

	# Clear template arrays
	template_strand_bottom.clear()
	nucleotide_bases.clear()
	nucleotide_original_x.clear()
	nucleotide_backbone_delta.clear()
	top_strand_slots.clear()
	top_strand_bases.clear()
	top_strand_backbone_delta.clear()
	top_strand_bond_marks.clear()
	template_hydrogen_bonds.clear()
	bond_marks.clear()
	helicase_mgr = null  # Re-created in initialize_simulation
	# replication_mgr persists — only teardown()+reset() called, not queue_free()

	# Reset line points
	if backbone_line:
		backbone_line.points = PackedVector2Array()
	if top_strand_backbone_line:
		top_strand_backbone_line.points = PackedVector2Array()

	# Clear rail paths
	if rail_path:
		var old_curve = rail_path.curve
		if old_curve:
			old_curve.clear_points()
	if top_rail_path:
		var top_curve = top_rail_path.curve
		if top_curve:
			top_curve.clear_points()

# ==========================================
# CORE UPDATE LOOP
# ==========================================


func _process(delta):
	# v76 startup-gate fix: the complexity/sequence popups delay
	# initialize_simulation() past the first several frames (previously it
	# ran synchronously in _ready(), before _process() ever fired). Section 3
	# below ("Always runs, even when paused") touches nodes — e.g.
	# top_strand_backbone_line — that only exist after the first
	# initialize_simulation() call, so bail out entirely until that's
	# happened at least once. helicase_mgr is null only in that pre-init
	# window; every reload after that recreates it synchronously inside
	# initialize_simulation() itself, so this never skips a real frame once
	# a sequence has loaded.
	if helicase_mgr == null:
		return

	# ---------- 1. DERIVE VISUAL HELICASE POSITION ----------
	# helicase_x is computed from helicase_mgr's discrete slot index and eased step_t.
	# This is the only place helicase_x and polymerase_x are written.
	if helicase_mgr != null:
		var idx = helicase_mgr.get_slot_index()
		var eased = helicase_mgr.get_eased_step_t()
		var last_valid = num_nucleotide_slots - 1
		if idx >= last_valid:
			# Helicase is past the last slot (finishing phase) — extrapolate using slot spacing
			var overshoot = (idx - last_valid + eased) * nucleotide_slot_spacing
			helicase_x = nucleotide_original_x[last_valid] + overshoot
		else:
			helicase_x = lerp(nucleotide_original_x[idx], nucleotide_original_x[idx + 1], eased)
		polymerase_x = helicase_x - polymerase_x_offset_slots * nucleotide_slot_spacing
		settle_blend = helicase_mgr.get_settling_blend()

		if helicase_ring != null:
			# Frozen (static symmetric pose, no roll dependency) whenever paused/
			# scrubbed — mirrors the polymerase clamp always showing its DOWN
			# state on scrub — or whenever the theme disables ring rotation
			# (future low-info preset, same relationship wobble_enabled has).
			helicase_ring.rotation_frozen = manual_override or not %ThemeManager.helicase_ring_rotation_enabled
			helicase_ring.set_roll(float(idx) + eased)

		var phase = helicase_mgr.get_phase()
		if phase == helicase_mgr.Phase.DONE:
			settle_blend = 1.0

		if helicase_atp_cycle != null:
			# ---- ATP cycle: BOTH progress values resolved HERE, not there ----
			# get_eased_step_t() is a cubic ease-out, so raw 0.7 maps to eased
			# 0.973. Handing helicase_atp_cycle a single step_t and letting it decide
			# what to ease would fire the approach at effectively 97% of the
			# step, leaving nothing visible — the same "two similar values are
			# not interchangeable" trap as the wobble-gating mismatch and the
			# stale straight_y read. Resolving both at this boundary and naming
			# the parameters for their space leaves helicase_atp_cycle.gd with no easing
			# logic at all and therefore nothing to get wrong. This file is
			# already the single funnel that does exactly this for
			# helicase_ring's whole config, label_counter_rotation and
			# rotation_frozen.
			#
			# The cleave happened at the slot the helicase is currently AT, so
			# the origin uses the SAME last_valid branch helicase_x itself uses
			# just above — evaluated at step start rather than mid-step.
			# Clamping with min(idx, last_valid) instead would be wrong: during
			# FINISHING_LAST_PULSE every cleave would report the same origin
			# and ADP would pile up at the last slot while the helicase walks
			# away from it. Extrapolate, exactly as helicase_x does.
			var discard_origin_x: float
			if idx >= last_valid:
				discard_origin_x = nucleotide_original_x[last_valid] + (idx - last_valid) * nucleotide_slot_spacing
			else:
				discard_origin_x = nucleotide_original_x[idx]
			# Subtracting helicase_x once, here, is what lets helicase_atp_cycle.gd stay
			# in pure local space — see its header for why that diverges from
			# the design doc's global_position instruction.
			var discard_origin_local := Vector2(discard_origin_x - helicase_x, 0.0)

			# Gated to the two phases where the helicase is actually stepping.
			# INTRO is the load-bearing exclusion: step_t is 0 there, which
			# sits inside the spark window and would fire a cleave at scene
			# load, before replication has begun. FINISHING_LAST_PULSE stays
			# ON — the cycle lives in step_t space, so finishing_acceleration
			# compresses it proportionally exactly as it already does the
			# barrel roll, and switching the lens off while the helicase
			# visibly keeps translocating would read as fuel-free motion.
			var cofactor_stepping: bool = phase == helicase_mgr.Phase.SWEEPING or phase == helicase_mgr.Phase.FINISHING_LAST_PULSE
			helicase_atp_cycle.byproducts_visible = %ComplexityManager.is_enabled("cofactor_byproducts")
			helicase_atp_cycle.update(
				helicase_mgr.get_step_t(),        # spawn_progress_raw
				eased,                            # drift_progress_eased
				discard_origin_local,
				cofactor_stepping and %ComplexityManager.is_enabled("cofactor")
			)

	# wobble_t computed once here — used by both state update and rendering sections
	wobble_time += delta
	var wobble_t = wobble_time

	# ---------- 2. STATE UPDATE (only if not manually overridden) ----------
	if not manual_override and helicase_mgr != null and replication_mgr != null:
		var phase = helicase_mgr.get_phase()

		# ---- Enzyme positions ----
		if helicase_node:
			helicase_node.position = Vector2(helicase_x, center_y)

		if phase != helicase_mgr.Phase.DONE:
			for i in range(template_strand_bottom.size()):
				template_strand_bottom[i].progress = track_length - nucleotide_original_x[i]

		# ---- Delegate synthesis logic to replication_mgr ----
		replication_mgr.update(delta, {
			helicase_x = helicase_x,
			polymerase_x = polymerase_x,
			center_y = center_y,
			template_strand_y = template_strand_y,
			polymerase_y_lagging = polymerase_y_lagging,
			polymerase_y_leading = polymerase_y_leading,
			new_top_template_y = new_top_template_y,
			new_bottom_template_y = new_bottom_template_y,
			dna_ribbons_gap = dna_ribbons_gap,
			polymerase_y_offset = polymerase_y_offset,
			wobble_t = wobble_t,
			phase = phase,
			helicase_mgr = helicase_mgr,
			num_slots = num_nucleotide_slots,
		})
		manual_override = replication_mgr.manual_override


		# Emit progress for the UI
		progress_changed.emit(get_total_progress())

	# ---------- 3. VISUAL RENDERING (Always runs, even when paused) ----------
	_rebuild_rail()
	_rebuild_top_rail()

	var is_done = helicase_mgr != null and helicase_mgr.get_phase() == helicase_mgr.Phase.DONE



	# ---- Backbone for bottom template (existing) ----
	var backbone_points = PackedVector2Array()
	var bottom_curve = rail_path.curve
	for i in range(template_strand_bottom.size()):
		var nucleotide_slot = template_strand_bottom[i]
		var world_x = nucleotide_original_x[i]
		var slot_y: float
		if bottom_curve != null:
			var baked = bottom_curve.get_baked_points()
			slot_y = _sample_curve_y_at_x(baked, world_x, template_strand_y)
		else:
			slot_y = template_strand_y
		nucleotide_slot.position = Vector2(world_x, slot_y)

		var wobble_y = 0.0
		var near_top = abs(slot_y - template_strand_y) < wobble_amplitude * 4.0
		var near_bottom = abs(slot_y - new_bottom_template_y) < wobble_amplitude * 4.0
		if near_top or near_bottom:
			wobble_y = get_wobble_y(i, wobble_t)
		nucleotide_bases[i].position.y = wobble_y
		# Bug A fix (MolecularStructure_BasePairExpansion.md): suppress the
		# bead-glyph circle per-slot, live, whenever the molecule renderer
		# is actually drawing this residue in skeletal mode — never cached,
		# polled fresh every frame via a public accessor rather than a
		# second independent hysteresis check. Backbone Line2D suppression
		# (whole-strand, since Line2D has no per-point alpha) is applied
		# further down, once backbone_points/bond_marks are finalized —
		# see the reversed decision noted there.
		if molecule_renderer != null:
			nucleotide_bases[i].modulate.a = 0.0 if molecule_renderer.is_slot_active("template_bottom", i) else 1.0

		var mid_y = template_strand_y + (new_bottom_template_y - template_strand_y) * 0.5
		var on_bonded = slot_y < mid_y
		var target_delta: float
		if on_bonded:
			target_delta = %ThemeManager.backbone_offset_distance
		else:
			target_delta = -%ThemeManager.backbone_offset_distance

		nucleotide_backbone_delta[i] = lerp(nucleotide_backbone_delta[i], target_delta, clamp(%ThemeManager.backbone_offset_smoothing_speed * delta, 0.0, 1.0))
		backbone_points.append(Vector2(world_x, slot_y + nucleotide_backbone_delta[i] + wobble_y))


	backbone_line.points = backbone_points
	backbone_line.width = %ThemeManager.backbone_line_width
	# Bug A suppression now lives in _apply_zoom_highlight() (single-writer
	# fix) — a write here was silently clobbered by that function's own
	# strand_dim write later in the same _process() call. bond_marks
	# suppression below is unaffected by this (that function never touches
	# bond_marks), so it stays where it is.

	# ---- Lagging + leading synthesis rendering ----
	if replication_mgr != null:
		replication_mgr.render(delta, {
			wobble_t = wobble_t,
			polymerase_y_lagging = polymerase_y_lagging,
			dna_ribbons_gap = dna_ribbons_gap,
			polymerase_y_offset = polymerase_y_offset,
			center_y = center_y,
			template_strand_y = template_strand_y,
			new_top_template_y = new_top_template_y,
			new_bottom_template_y = new_bottom_template_y,
			num_slots = num_nucleotide_slots,
			nucleotide_original_x = nucleotide_original_x,
			template_strand_bottom = template_strand_bottom,
			nucleotide_bases = nucleotide_bases,
			top_strand_slots = top_strand_slots,
		})

	_apply_zoom_highlight()

	_update_bond_marks(backbone_points)
	if molecule_renderer != null:
		var template_bottom_active: float = 0.0 if molecule_renderer.is_strand_active("template_bottom") else 1.0
		for mark in bond_marks:
			if mark != null and is_instance_valid(mark): mark.modulate.a = template_bottom_active

	# ---- Top template strand ----
	var top_strand_points = PackedVector2Array()
	var top_curve = top_rail_path.curve
	for i in range(top_strand_slots.size()):
		var world_x = nucleotide_original_x[i]
		var slot_y: float
		if top_curve != null:
			var baked = top_curve.get_baked_points()
			slot_y = _sample_curve_y_at_x(baked, world_x, template_strand_y - dna_ribbons_gap)
		else:
			slot_y = template_strand_y - dna_ribbons_gap
		top_strand_slots[i].position = Vector2(world_x, slot_y)

		var wobble_y = get_wobble_y(i, wobble_t)
		top_strand_bases[i].position = Vector2(0, wobble_y)
		# Bug A fix (bead circle) — see the matching comment on the bottom
		# template loop above. Backbone line suppression is below, once
		# top_strand_points/its bond marks are finalized.
		if molecule_renderer != null:
			top_strand_bases[i].modulate.a = 0.0 if molecule_renderer.is_slot_active("template_top", i) else 1.0

		var mid_y = new_top_template_y + (template_strand_y - dna_ribbons_gap - new_top_template_y) * 0.5
		var on_bonded = slot_y > mid_y
		var target_backbone_delta = -%ThemeManager.backbone_offset_distance if on_bonded else %ThemeManager.backbone_offset_distance
		top_strand_backbone_delta[i] = lerp(
			top_strand_backbone_delta[i],
			target_backbone_delta,
			clamp(%ThemeManager.backbone_offset_smoothing_speed * delta, 0.0, 1.0)
		)
		top_strand_points.append(Vector2(world_x, slot_y + top_strand_backbone_delta[i] + wobble_y))

		if template_hydrogen_bonds[i] != null:
			# Container anchors at bottom template slot y; lines draw upward to top template slot.
			var bottom_slot_y = template_strand_bottom[i].position.y
			var bottom_wobble_y = nucleotide_bases[i].position.y
			var container_y = bottom_slot_y + bottom_wobble_y
			template_hydrogen_bonds[i].position = Vector2(world_x, container_y)
			# Height is negative: top template slot is above bottom template slot.
			var bond_height = (slot_y + wobble_y) - container_y
			_update_hydrogen_bond_height(template_hydrogen_bonds[i], bond_height)
			template_hydrogen_bonds[i].visible = (world_x >= helicase_x) and not is_done
			# Bug A fix — modulate.a, not .visible, so this composes with
			# the helicase-progress visibility above rather than fighting
			# it (two writers on the same property would be a real bug;
			# modulate.a is untouched elsewhere on this node).
			if molecule_renderer != null:
				template_hydrogen_bonds[i].modulate.a = 0.0 if (molecule_renderer.is_slot_active("template_bottom", i) or molecule_renderer.is_slot_active("template_top", i)) else 1.0
	top_strand_backbone_line.points = top_strand_points
	top_strand_backbone_line.width = %ThemeManager.backbone_line_width
	_update_bond_marks_top_strand(top_strand_points)
	# Backbone-line suppression now lives in _apply_zoom_highlight()
	# (single-writer fix) — bond_marks suppression stays here since that
	# function never touches bond_marks (no conflict).
	if molecule_renderer != null:
		var template_top_active: float = 0.0 if molecule_renderer.is_strand_active("template_top") else 1.0
		for mark in top_strand_bond_marks:
			if mark != null and is_instance_valid(mark): mark.modulate.a = template_top_active

	# ---- Marker positions: template strands (owned by simulation.gd) ----
	if marker_template_5p:
		var last = num_nucleotide_slots - 1
		var wobble_last = get_wobble_y(last, wobble_t)
		marker_template_5p.position = Vector2(
			template_strand_bottom[last].position.x + %ThemeManager.marker_offset,
			template_strand_bottom[last].position.y + nucleotide_backbone_delta[last] + wobble_last
		)
	if marker_template_3p:
		var wobble_first = get_wobble_y(0, wobble_t)
		marker_template_3p.position = Vector2(
			template_strand_bottom[0].position.x - %ThemeManager.marker_offset,
			template_strand_bottom[0].position.y + nucleotide_backbone_delta[0] + wobble_first
		)
	if marker_top_5p:
		var wobble_first = get_wobble_y(0, wobble_t)
		marker_top_5p.position = Vector2(
			top_strand_slots[0].position.x - %ThemeManager.marker_offset,
			top_strand_slots[0].position.y + top_strand_backbone_delta[0] + wobble_first
		)
	if marker_top_3p:
		var last = num_nucleotide_slots - 1
		var wobble_last = get_wobble_y(last, wobble_t)
		marker_top_3p.position = Vector2(
			top_strand_slots[last].position.x + %ThemeManager.marker_offset,
			top_strand_slots[last].position.y + top_strand_backbone_delta[last] + wobble_last
		)
	background_rect.color = %ThemeManager.background_color

# ==========================================
# SCRUBBER API (Public Functions for UI)
# ==========================================

func toggle_play():
	manual_override = !manual_override
	if replication_mgr != null:
		replication_mgr.manual_override = manual_override
	if not manual_override and helicase_mgr != null:
		if helicase_mgr.is_done():
			scrub_to_nucleotide_index(0)
			helicase_mgr.start_intro()
		if helicase_mgr.get_phase() == helicase_mgr.Phase.INTRO:
			_run_intro()
		else:
			replication_mgr.resume_enzymes()
			if helicase_node:
				helicase_node.modulate.a = 1.0
			helicase_mgr.resume()
	elif helicase_mgr != null:
		helicase_mgr.pause()

func _run_intro():
	# Position enzymes left of the strand, then fade in and slide to start position.
	var intro_x = nucleotide_original_x[0] - polymerase_x_offset_slots * nucleotide_slot_spacing * 0.5
	var fade_time = 0.4
	var slide_time = 0.5

	if helicase_node:
		helicase_node.position = Vector2(intro_x, center_y)

	var tween = create_tween().set_parallel(true)
	replication_mgr.run_intro(intro_x, fade_time, slide_time, tween)

	if helicase_node:
		tween.tween_property(helicase_node, "modulate:a", 1.0, fade_time)
		tween.tween_property(helicase_node, "position",
			Vector2(helicase_x, center_y), slide_time).set_delay(fade_time)
	# Notify helicase_mgr when intro tween completes → starts SWEEPING
	tween.chain().tween_callback(func():
		if helicase_mgr != null:
			helicase_mgr.finish_intro()
	)

func scrub_to(progress: float):
	progress = clamp(progress, 0.0, 1.0)
	lagging_last_catchup_step = 0

	# Map progress to a slot index
	var target_slot = int(progress * (num_nucleotide_slots - 1))
	target_slot = clamp(target_slot, 0, num_nucleotide_slots - 1)

	# Derive helicase_x and polymerase_x from target slot for this scrub
	var target_helicase_x = nucleotide_original_x[target_slot]
	var target_polymerase_x = target_helicase_x - polymerase_x_offset_slots * nucleotide_slot_spacing

	# Update helicase_mgr discrete state
	if helicase_mgr != null:
		helicase_mgr.scrub_to_slot(target_slot)

	# Derive visual state
	helicase_x = target_helicase_x
	polymerase_x = target_polymerase_x

	# Set phase on helicase_mgr based on scrub position
	if helicase_mgr != null:
		if target_slot >= num_nucleotide_slots - 1:
			helicase_mgr.set_phase(helicase_mgr.Phase.DONE)
			# Push helicase past the last slot so enzymes exit visually off the right edge
			var last_x = nucleotide_original_x[num_nucleotide_slots - 1]
			helicase_x = last_x + polymerase_x_offset_slots * nucleotide_slot_spacing
			polymerase_x = last_x
			settle_blend = 1.0
			if helicase_node:
				helicase_node.modulate.a = 0.0
		elif target_polymerase_x > nucleotide_original_x[num_nucleotide_slots - 1]:
			helicase_mgr.set_phase(helicase_mgr.Phase.FINISHING_LAST_PULSE)
			settle_blend = 0.0
		else:
			helicase_mgr.set_phase(helicase_mgr.Phase.SWEEPING)
			settle_blend = 0.0

	var is_done_phase = helicase_mgr != null and helicase_mgr.get_phase() == helicase_mgr.Phase.DONE

	# ---- Delegate synthesis rebuild to replication_mgr ----
	if replication_mgr != null:
		replication_mgr.scrub_rebuild({
			target_slot = target_slot,
			target_polymerase_x = target_polymerase_x,
			helicase_x = helicase_x,
			is_done_phase = is_done_phase,
			num_slots = num_nucleotide_slots,
			nucleotide_original_x = nucleotide_original_x,
			template_strand_y = template_strand_y,
			new_top_template_y = new_top_template_y,
			new_bottom_template_y = new_bottom_template_y,
			helicase_mgr = helicase_mgr,
		})

	# ---- Update template hydrogen bond visibility ----
	for i in range(num_nucleotide_slots):
		if template_hydrogen_bonds[i] != null:
			template_hydrogen_bonds[i].visible = (nucleotide_original_x[i] >= helicase_x)

	# Force immediate rail rebuild
	_rebuild_rail()
	_rebuild_top_rail()
	for i in range(template_strand_bottom.size()):
		template_strand_bottom[i].progress = track_length - nucleotide_original_x[i]
	for i in range(top_strand_slots.size()):
		top_strand_slots[i].progress = track_length - nucleotide_original_x[i]


	if helicase_node:
		helicase_node.modulate.a = 1.0

	if helicase_node:
		helicase_node.position = Vector2(helicase_x, center_y)

	_notify_zoom_scrub()
	queue_redraw()

func scrub_to_nucleotide_index(index: int):
	var max_index = get_max_scrub_index()
	index = clamp(index, 0, max_index)
	var catchup_needed = 0
	if replication_mgr != null and not lagging_gap_enabled:
		catchup_needed = replication_mgr.get_lagging_catchup_steps_needed(num_nucleotide_slots, nucleotide_original_x)
	
	if index <= num_nucleotide_slots - 1:
		var progress = float(index) / float(num_nucleotide_slots - 1)
		scrub_to(progress)
	else:
		var catchup_step = index - (num_nucleotide_slots - 1)
		scrub_to_lagging_catchup(catchup_step)

func scrub_to_lagging_catchup(catchup_step: int) -> void:
	lagging_last_catchup_step = catchup_step
	var target_slot = num_nucleotide_slots - 1

	if helicase_mgr != null:
		helicase_mgr.scrub_to_slot(target_slot)
		helicase_mgr.set_phase(helicase_mgr.Phase.DONE)

	var last_x = nucleotide_original_x[num_nucleotide_slots - 1]
	helicase_x = last_x + polymerase_x_offset_slots * nucleotide_slot_spacing
	polymerase_x = last_x
	settle_blend = 1.0

	if replication_mgr != null:
		replication_mgr.scrub_rebuild({
			target_slot = target_slot,
			target_polymerase_x = polymerase_x,
			helicase_x = helicase_x,
			is_done_phase = true,
			lagging_catchup_step = catchup_step,
			num_slots = num_nucleotide_slots,
			nucleotide_original_x = nucleotide_original_x,
			template_strand_y = template_strand_y,
			new_top_template_y = new_top_template_y,
			new_bottom_template_y = new_bottom_template_y,
			helicase_mgr = helicase_mgr,
		})

	for i in range(num_nucleotide_slots):
		if template_hydrogen_bonds[i] != null:
			template_hydrogen_bonds[i].visible = (nucleotide_original_x[i] >= helicase_x)

	_rebuild_rail()
	_rebuild_top_rail()
	for i in range(template_strand_bottom.size()):
		template_strand_bottom[i].progress = track_length - nucleotide_original_x[i]
	for i in range(top_strand_slots.size()):
		top_strand_slots[i].progress = track_length - nucleotide_original_x[i]

	_notify_zoom_scrub()
	queue_redraw()


# ==========================================
# UI HELPER FUNCTIONS
# ==========================================

func get_total_progress() -> float:
	if num_nucleotide_slots <= 1: return 0.0
	if helicase_mgr == null: return 0.0
	return clamp(float(helicase_mgr.get_slot_index()) / float(num_nucleotide_slots - 1), 0.0, 1.0)

func get_synthesized_count() -> int:
	if helicase_mgr != null and helicase_mgr.get_phase() == helicase_mgr.Phase.DONE:
		return num_nucleotide_slots - 1 + lagging_last_catchup_step
	elif helicase_mgr != null:
		return helicase_mgr.get_slot_index()
	return 0

func get_sequence_rich_text(hover_index: int = -1) -> String:
	if replication_mgr != null:
		return replication_mgr.get_sequence_rich_text(helicase_x, nucleotide_original_x, hover_index)
	return "5' [empty] 3'"

## Read-only view over nucleotide_bases / top_strand_bases for
## molecule_structure_renderer.gd — the ORIGINAL template strand's own
## counterpart to replication_manager.gd's get_synthesized_nucleotides().
## world_position uses global_position, NOT position: these nodes are
## children of PathFollow2D slots riding rail_path/top_rail_path (see
## _spawn_nucleotide_slots()/_spawn_top_strand()), so .position is local to
## a moving parent, not a world position.
func get_template_nucleotides() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in range(nucleotide_bases.size()):
		var base = nucleotide_bases[i]
		if base != null and is_instance_valid(base):
			result.append({
				slot = i,
				strand = "template_bottom",
				base_type = dna_sequence.get_base(i),
				world_position = base.global_position,
			})
	for i in range(top_strand_bases.size()):
		var base = top_strand_bases[i]
		if base != null and is_instance_valid(base):
			result.append({
				slot = i,
				strand = "template_top",
				base_type = dna_sequence.get_complement(i),
				world_position = base.global_position,
			})
	return result

func get_max_scrub_index() -> int:
	var catchup_needed = 0
	if replication_mgr != null and not lagging_gap_enabled:
		catchup_needed = replication_mgr.get_lagging_catchup_steps_needed(num_nucleotide_slots, nucleotide_original_x)
	return num_nucleotide_slots - 1 + catchup_needed

## LongSequenceDesign.md follow-up — the one funnel point for drag-to-scrub
## gestures from helicase_ring.gd (connected below) and both polymerase
## clamps (connected in replication_manager.gd, which owns them directly).
## Clamping lives here once rather than duplicated at each call site.
## player_ui.gd connects to drag_scrub_requested and calls its existing
## _scrub_to_index() — pause-on-drag and the UI refresh stay the one shared
## code path that already handles the scrubber and SequenceLabel.
func request_drag_scrub(target_index: int) -> void:
	drag_scrub_requested.emit(clamp(target_index, 0, get_max_scrub_index()))

func _on_helicase_ring_drag_started() -> void:
	_ring_drag_start_index = get_synthesized_count()

## Converts screen-space cumulative drag pixels into a slot delta relative
## to _ring_drag_start_index — NOT the ring's own current position. Same
## conversion replication_manager.gd uses for both polymerase clamps, so
## drag feel is identical across all three enzymes regardless of which one
## was grabbed.
func _on_helicase_ring_drag_delta(cumulative_px: Vector2) -> void:
	var zoom_mgr = get_node_or_null("%ZoomManager")
	if zoom_mgr == null or nucleotide_slot_spacing <= 0.0:
		return
	var zoom_x: float = zoom_mgr.zoom.x
	if zoom_x <= 0.0:
		return
	# The enzyme reports both axes; picking the along-track one is decided here,
	# where zoom_mgr is already in hand. Needs no sign flip: horizontally, drag
	# right (+screen x) is world +x is forward; vertically, world +x maps to
	# screen +y, which is DOWN — so drag down is forward. Positive is forward in
	# both. zoom is uniform (Vector2(z, z)), so px_per_slot is axis-independent.
	var along_px: float = cumulative_px.y if zoom_mgr.vertical_mode else cumulative_px.x
	var px_per_slot: float = nucleotide_slot_spacing * zoom_x
	var slot_delta: int = int(round(along_px / px_per_slot))
	request_drag_scrub(_ring_drag_start_index + slot_delta)

func _on_helicase_ring_follow_requested() -> void:
	var zoom_mgr = get_node_or_null("%ZoomManager")
	if zoom_mgr != null:
		zoom_mgr.request_follow("helicase")

# ==========================================
# HELICASE SIGNAL HANDLERS
# ==========================================

func _on_helicase_slot_reached(index: int) -> void:
	# Fired by helicase_mgr each time it steps to a new slot.
	# Leading strand synthesis is handled by position in _process;
	# this is a hook for future per-slot logic (e.g. primase, clamps).
	pass

func _on_helicase_phase_changed(new_phase: int) -> void:
	pass

# ==========================================
# SPAWNING FUNCTIONS
# ==========================================

func _spawn_nucleotide_slots():
	var row_span = (num_nucleotide_slots - 1) * nucleotide_slot_spacing
	var row_start_x = (track_length - row_span) / 2.0

	for i in range(num_nucleotide_slots):
		var nucleotide_slot = PathFollow2D.new()
		nucleotide_slot.rotates = false
		nucleotide_slot.loop = false

		var nucleotide_area = Area2D.new()
		nucleotide_area.name = "NucleotideArea_%d" % i
		nucleotide_area.monitoring = true
		nucleotide_area.monitorable = true
		var nucleotide_collision_shape = CollisionShape2D.new()
		var nucleotide_shape = RectangleShape2D.new()
		nucleotide_shape.size = nucleotide_slot_size
		nucleotide_collision_shape.shape = nucleotide_shape
		nucleotide_area.add_child(nucleotide_collision_shape)
		nucleotide_slot.add_child(nucleotide_area)

		var nitrogen_base = NewNitrogenBaseScene.instantiate()
		nucleotide_slot.add_child(nitrogen_base)
		nucleotide_bases.append(nitrogen_base)

		rail_path.add_child(nucleotide_slot)

		var base_char = dna_sequence.get_complement(i)
		nitrogen_base.set_base_type(base_char)
		nitrogen_base.set_radius(%ThemeManager.base_radius)
		nitrogen_base.set_colors(
			_get_base_fill(base_char),
			%ThemeManager.base_label_color
		)
		nitrogen_base.set_font(%ThemeManager.base_label_font_size, %ThemeManager.base_label_font)
		nitrogen_base.set_label_rotation(_zoom_label_rotation())

		var x = row_start_x + i * nucleotide_slot_spacing
		nucleotide_original_x.append(x)
		nucleotide_slot.progress = track_length - x
		template_strand_bottom.append(nucleotide_slot)
		nucleotide_backbone_delta.append(%ThemeManager.backbone_offset_distance)

func _spawn_top_strand():
	for i in range(num_nucleotide_slots):
		var slot = PathFollow2D.new()
		slot.rotates = false
		slot.loop = false
		top_rail_path.add_child(slot)

		var base = NewNitrogenBaseScene.instantiate()
		slot.add_child(base)
		var base_char = dna_sequence.get_base(i)
		base.set_base_type(base_char)
		base.set_radius(%ThemeManager.base_radius)
		base.set_colors(_get_base_fill(base_char), %ThemeManager.base_label_color)
		base.set_font(%ThemeManager.base_label_font_size, %ThemeManager.base_label_font)
		base.set_label_rotation(_zoom_label_rotation())

		top_strand_slots.append(slot)
		top_strand_bases.append(base)
		top_strand_backbone_delta.append(%ThemeManager.backbone_offset_distance)
		template_hydrogen_bonds.append(_spawn_template_hydrogen_bonds(i))

func _spawn_template_hydrogen_bonds(index: int) -> Node2D:
	var base_type = dna_sequence.get_complement(index)
	var bond_count = 3 if (base_type == "C" or base_type == "G") else 2
	var bond_color = %ThemeManager.cg_bond_color if (base_type == "C" or base_type == "G") else %ThemeManager.at_bond_color
	var container = Node2D.new()
	var total_width = (bond_count - 1) * %ThemeManager.hydrogen_bond_spacing
	var start_x = -total_width / 2.0
	var inset = 12.0
	for b in range(bond_count):
		var line = Line2D.new()
		var lx = start_x + b * %ThemeManager.hydrogen_bond_spacing
		line.add_point(Vector2(lx, -inset))
		line.add_point(Vector2(lx, -(dna_ribbons_gap - inset)))
		line.default_color = bond_color
		line.width = %ThemeManager.hydrogen_bond_width
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		container.add_child(line)
	template_hydrogen_bonds_container.add_child(container)
	return container

func _spawn_marker(marker_type: String, world_pos: Vector2) -> Node2D:
	var marker = NewNitrogenBaseScene.instantiate()
	marker.position = world_pos
	marker.z_index = 3
	add_child(marker)
	marker.set_base_type(marker_type)
	marker.set_radius(%ThemeManager.base_radius)
	marker.set_colors(%ThemeManager.marker_color, %ThemeManager.marker_font_color)
	marker.set_font(%ThemeManager.marker_font_size, %ThemeManager.marker_font)
	marker.set_label_rotation(_zoom_label_rotation())
	return marker

func _get_base_fill(base_type: String) -> Color:
	match base_type:
		"A": return %ThemeManager.base_color_a
		"T": return %ThemeManager.base_color_t
		"C": return %ThemeManager.base_color_c
		"G": return %ThemeManager.base_color_g
		"5'", "3'": return %ThemeManager.marker_color
	return Color.GRAY

## Deterministic pseudo-random [0,1) value from a seed — same input always
## gives the same output (no per-frame flicker), used to give each slot its
## own stable "personality" instead of a linear traveling-wave phase.
func _wobble_hash01(seed: float) -> float:
	var x = sin(seed) * 43758.5453
	return x - floor(x)

## Returns this frame's wobble y-offset for a given slot index. Blends two
## independently-hashed sine waves per index so bases jitter with their own
## semi-random phase/frequency rather than rippling in sync like a flag.
## Shared by all four wobbling strands (bottom/top template, leading/lagging)
## so the "chaotic" feel and the accessibility toggle live in exactly one place.
func get_wobble_y(index: int, wobble_t: float) -> float:
	if not %ThemeManager.wobble_enabled or wobble_amplitude <= 0.0:
		return 0.0
	var phase_a = _wobble_hash01(float(index) * 12.9898) * TAU
	var freq_a = 0.85 + _wobble_hash01(float(index) * 78.233) * 0.5
	var phase_b = _wobble_hash01(float(index) * 39.425) * TAU
	var freq_b = 1.1 + _wobble_hash01(float(index) * 91.731) * 0.6

	var wave_a = sin(wobble_t * wobble_speed * freq_a * TAU + phase_a)
	var wave_b = sin(wobble_t * wobble_speed * freq_b * TAU + phase_b)
	return (wave_a * 0.7 + wave_b * 0.3) * wobble_amplitude

func _update_hydrogen_bond_height(container: Node2D, height: float) -> void:
	# Rescale bond lines to match the actual distance between paired bases.
	# Preserves the inset ratio from the original spawn so lines don't
	# touch the base circles regardless of current bond height.
	var inset = 12.0
	for child in container.get_children():
		if child is Line2D and child.get_point_count() >= 2:
			var p1 = child.get_point_position(0)
			# Determine direction: bonds may draw upward (negative) or downward (positive).
			var sign = -1.0 if height < 0.0 else 1.0
			var abs_h = abs(height)
			var p0_y = sign * inset
			var p1_y = sign * max(inset, abs_h - inset)
			child.set_point_position(0, Vector2(p1.x, p0_y))
			child.set_point_position(1, Vector2(p1.x, p1_y))

## Curve Y only (not a full atom position) at a given world-x, for
## molecule_structure_renderer.gd's curve-following polyline mode — see
## docs/MolecularStructure_BasePairExpansion.md's Option C decision. The
## caller combines this with each endpoint's own known vertical offset
## from the curve, so the resulting polyline stays exactly continuous with
## the real atom positions it already computed — this returns only the
## template rail's own shape, not a claim about where any atom sits.
## Reuses _sample_curve_y_at_x() (single source of truth for curve
## sampling — the same function the bead-glyph template rendering already
## depends on) rather than duplicating the lookup.
func sample_template_curve_y(strand: String, world_x: float) -> float:
	var curve: Curve2D = rail_path.curve if strand == "template_bottom" else top_rail_path.curve
	var fallback_y: float = template_strand_y if strand == "template_bottom" else (template_strand_y - dna_ribbons_gap)
	if curve == null:
		return fallback_y
	return _sample_curve_y_at_x(curve.get_baked_points(), world_x, fallback_y)

func _sample_curve_y_at_x(baked: PackedVector2Array, x: float, fallback_y: float) -> float:
	if baked.size() < 2:
		return fallback_y
	if x >= baked[0].x:
		return baked[0].y
	if x <= baked[baked.size() - 1].x:
		return baked[baked.size() - 1].y
	var lo = 0
	var hi = baked.size() - 1
	while hi - lo > 1:
		var mid = (lo + hi) / 2
		if baked[mid].x > x:
			lo = mid
		else:
			hi = mid
	var seg_x = baked[lo].x - baked[hi].x
	if seg_x == 0.0:
		return baked[lo].y
	var t = (baked[lo].x - x) / seg_x
	return lerp(baked[lo].y, baked[hi].y, t)

func _rebuild_top_rail():
	var curve = Curve2D.new()
	var bonded_y = template_strand_y - dna_ribbons_gap
	var unzipped_y = new_top_template_y
	var first_slot_x = nucleotide_original_x[0] if nucleotide_original_x.size() > 0 else 0.0

	# When done, top template stays at its unzipped position — it's now paired with the leading strand
	var is_done = helicase_mgr != null and helicase_mgr.get_phase() == helicase_mgr.Phase.DONE
	var polymerase_x_offset = polymerase_x_offset_slots * nucleotide_slot_spacing
	if is_done:
		curve.add_point(Vector2(track_length, unzipped_y))
		curve.add_point(Vector2(0, unzipped_y))
		top_rail_path.curve = curve
		return

	if helicase_x <= first_slot_x:
		curve.add_point(Vector2(track_length, bonded_y))
		curve.add_point(Vector2(-polymerase_x_offset, bonded_y))
		top_rail_path.curve = curve
		return

	var handle_x = (helicase_x - polymerase_x) * 0.4
	curve.add_point(Vector2(track_length, bonded_y))
	curve.add_point(Vector2(helicase_x, bonded_y))
	curve.add_point(Vector2(helicase_x, bonded_y), Vector2.ZERO, Vector2(-handle_x, 0))
	curve.add_point(Vector2(polymerase_x, unzipped_y), Vector2(handle_x, 0), Vector2.ZERO)
	curve.add_point(Vector2(-polymerase_x_offset, unzipped_y))
	top_rail_path.curve = curve

#func _rebuild_rail():
#	var is_done = helicase_mgr != null and helicase_mgr.get_phase() == helicase_mgr.Phase.DONE
#	var curve = Curve2D.new()
#	#var rest_y = polymerase_y_lagging if is_done else template_strand_y
#	var rest_y = template_strand_y
#	curve.add_point(Vector2(track_length, rest_y))
#	curve.add_point(Vector2(0, rest_y))
#	rail_path.curve = curve
#	template_strand_original_track.points = curve.get_baked_points()

func _rebuild_rail():
	var curve = Curve2D.new()
	var bonded_y = template_strand_y
	var unzipped_y = new_bottom_template_y
	var first_slot_x = nucleotide_original_x[0] if nucleotide_original_x.size() > 0 else 0.0

	# When done, bottom template stays at its unzipped position — it's now paired with the lagging strand
	var is_done = helicase_mgr != null and helicase_mgr.get_phase() == helicase_mgr.Phase.DONE
	var polymerase_x_offset = polymerase_x_offset_slots * nucleotide_slot_spacing
	if is_done:
		curve.add_point(Vector2(track_length, unzipped_y))
		curve.add_point(Vector2(0, unzipped_y))
		rail_path.curve = curve
		template_strand_original_track.points = curve.get_baked_points()
		return

	if helicase_x <= first_slot_x:
		curve.add_point(Vector2(track_length, bonded_y))
		curve.add_point(Vector2(-polymerase_x_offset, bonded_y))
		rail_path.curve = curve
		template_strand_original_track.points = curve.get_baked_points()
		return

	var handle_x = (helicase_x - polymerase_x) * 0.4
	curve.add_point(Vector2(track_length, bonded_y))
	curve.add_point(Vector2(helicase_x, bonded_y))
	curve.add_point(Vector2(helicase_x, bonded_y), Vector2.ZERO, Vector2(-handle_x, 0))
	curve.add_point(Vector2(polymerase_x, unzipped_y), Vector2(handle_x, 0), Vector2.ZERO)
	curve.add_point(Vector2(-polymerase_x_offset, unzipped_y))
	rail_path.curve = curve
	template_strand_original_track.points = curve.get_baked_points()

func _setup_helicase():
	helicase_node = Node2D.new()
	helicase_node.z_index = 3

	helicase_ring = HelicaseRing.new()
	helicase_ring.blob_count = %ThemeManager.helicase_ring_blob_count
	helicase_ring.ring_radius = %ThemeManager.helicase_ring_ring_radius
	helicase_ring.max_blob_height = %ThemeManager.helicase_ring_max_blob_height
	helicase_ring.max_blob_width = %ThemeManager.helicase_ring_max_blob_width
	helicase_ring.min_width_ratio = %ThemeManager.helicase_ring_min_width_ratio
	helicase_ring.chamfer_ratio = %ThemeManager.helicase_ring_chamfer_ratio
	helicase_ring.corner_radius_ratio = %ThemeManager.helicase_ring_corner_radius_ratio
	helicase_ring.corner_segments = %ThemeManager.helicase_ring_corner_segments
	helicase_ring.step_angle_deg = %ThemeManager.helicase_ring_step_angle_deg
	helicase_ring.front_color = %ThemeManager.helicase_ring_front_color
	helicase_ring.back_color = %ThemeManager.helicase_ring_back_color
	helicase_ring.front_z = %ThemeManager.helicase_ring_front_z
	helicase_ring.back_z = %ThemeManager.helicase_ring_back_z
	helicase_ring.ring_skew_deg = %ThemeManager.helicase_ring_skew_deg
	# helicase_ring.gd holds no external references by design, so this is
	# pushed like every other param above rather than looked up there.
	helicase_ring.label_counter_rotation = _zoom_label_rotation()
	helicase_node.add_child(helicase_ring)
	helicase_ring.scrub_drag_started.connect(_on_helicase_ring_drag_started)
	helicase_ring.scrub_drag_delta.connect(_on_helicase_ring_drag_delta)
	helicase_ring.follow_requested.connect(_on_helicase_ring_follow_requested)

	# ATP cycle — a SIBLING of the ring, not a child of it. helicase_ring.gd
	# deliberately holds no ThemeManager reference (its own header insists on
	# being a pure function of one float), so an ATP visual parented inside it
	# would either break that contract or need every field forwarded twice.
	# Parenting under helicase_node instead also inherits helicase_node.modulate
	# for free, which matters at end-of-run: _lagging_fade_enzyme_scene() fades
	# the whole enzyme scene, and a cycle parented at the scene root would be
	# the one object left behind.
	helicase_atp_cycle = HelicaseAtpCycle.new()
	helicase_atp_cycle.z_as_relative = false
	helicase_atp_cycle.z_index = %ThemeManager.cofactor_z
	helicase_atp_cycle.bead_radius = %ThemeManager.cofactor_bead_size
	helicase_atp_cycle.adenine_radius = %ThemeManager.base_radius * %ThemeManager.cofactor_head_scale
	helicase_atp_cycle.bead_spacing = %ThemeManager.cofactor_bead_spacing
	helicase_atp_cycle.bead_color = %ThemeManager.cofactor_bead_color
	# base_color_a pushed VERBATIM, with no ATP-side field of its own: the
	# adenine in ATP is the adenine in DNA, and that identity is the point.
	# Two independently-tuned colors that are only supposed to agree would be
	# exactly the coincidence this project's rule forbids.
	helicase_atp_cycle.adenine_color = %ThemeManager.base_color_a
	helicase_atp_cycle.link_color = %ThemeManager.cofactor_link_color
	helicase_atp_cycle.link_width = %ThemeManager.cofactor_link_width
	helicase_atp_cycle.label_color = %ThemeManager.cofactor_label_color
	helicase_atp_cycle.label_font_size = %ThemeManager.cofactor_label_font_size
	helicase_atp_cycle.label_font = %ThemeManager.cofactor_label_font
	helicase_atp_cycle.spark_color = %ThemeManager.cofactor_spark_color
	helicase_atp_cycle.spark_radius = %ThemeManager.cofactor_spark_radius
	helicase_atp_cycle.spark_width = %ThemeManager.cofactor_spark_width
	helicase_atp_cycle.spawn_lead_ratio = %ThemeManager.atp_spawn_lead_ratio
	helicase_atp_cycle.spark_window = %ThemeManager.atp_spark_window
	helicase_atp_cycle.byproduct_fade_end_eased = %ThemeManager.atp_byproduct_fade_end_eased
	helicase_atp_cycle.pi_x_ratio = %ThemeManager.atp_pi_x_ratio
	helicase_atp_cycle.pi_rise_distance = %ThemeManager.atp_pi_rise_distance
	helicase_atp_cycle.approach_offset = %ThemeManager.atp_approach_offset
	helicase_atp_cycle.nucleotide_slot_spacing = nucleotide_slot_spacing
	# Same push as helicase_ring's above — the "A"/"P" bead glyphs are drawn
	# text and would ship sideways in vertical mode without this. This file
	# stays the single place that asks ZoomManager.
	helicase_atp_cycle.label_counter_rotation = _zoom_label_rotation()
	helicase_node.add_child(helicase_atp_cycle)

	helicase_node.position = Vector2(helicase_x, center_y)
	add_child(helicase_node)

func _update_bond_marks_fragment(frag: Dictionary, points: PackedVector2Array) -> void:
	var needed = max(0, points.size() - 1)
	while frag.bond_marks.size() < needed:
		frag.bond_marks.append(_create_bond_mark_sprite_reversed())
	while frag.bond_marks.size() > needed:
		var extra = frag.bond_marks.pop_back()
		if is_instance_valid(extra): extra.queue_free()
	for i in range(needed):
		var a = points[i]
		var b = points[i + 1]
		var mid = (a + b) / 2.0
		var segment = b - a
		var mark = frag.bond_marks[i]
		mark.position = mid
		mark.visible = segment.length() > 0.0
		if mark.visible:
			mark.rotation = segment.angle()

func _update_bond_marks(points: PackedVector2Array):
	var needed = max(0, points.size() - 1)
	while bond_marks.size() < needed:
		bond_marks.append(_create_bond_mark_sprite())
	while bond_marks.size() > needed:
		var extra = bond_marks.pop_back()
		extra.queue_free()
	for i in range(needed):
		var a = points[i]
		var b = points[i + 1]
		var mid = (a + b) / 2.0
		var segment = b - a
		var mark = bond_marks[i]
		mark.position = mid
		mark.visible = segment.length() > 0.0
		if mark.visible:
			mark.rotation = segment.angle()

func _update_bond_marks_top_strand(points: PackedVector2Array):
	var needed = max(0, points.size() - 1)
	while top_strand_bond_marks.size() < needed:
		top_strand_bond_marks.append(_create_bond_mark_sprite_reversed())
	while top_strand_bond_marks.size() > needed:
		var extra = top_strand_bond_marks.pop_back()
		extra.queue_free()
	for i in range(needed):
		var a = points[i]
		var b = points[i + 1]
		var mid = (a + b) / 2.0
		var segment = b - a
		var mark = top_strand_bond_marks[i]
		mark.position = mid
		mark.visible = segment.length() > 0.0
		if mark.visible:
			mark.rotation = segment.angle()

func _create_bond_mark_sprite() -> Node2D:
	# Single triangle, tip pointing LEFT — replaces the old two-diamond
	# masking trick (a full black diamond with a second, background-colored
	# diamond overlaid to "erase" part of it). That trick broke visibly
	# during alpha fades: fading the holder faded BOTH diamonds together,
	# so the masking diamond's own transparency let the covered part of the
	# black diamond show back through, revealing two overlapping triangles
	# instead of one clean shape. This triangle is geometrically the LEFT
	# HALF of the old black diamond (tip at the diamond's original left
	# vertex, flat back edge spanning the full height at center) — exactly
	# what the masking trick was already visually approximating, just as an
	# actual single shape instead of an illusion built from two.
	var holder = Node2D.new()
	var h = %ThemeManager.backbone_line_width / 2.0
	var w = %ThemeManager.bond_mark_width
	var triangle = Polygon2D.new()
	triangle.polygon = PackedVector2Array([
		Vector2(-w / 2.0, 0),
		Vector2(0, -h),
		Vector2(0, h),
	])
	triangle.color = %ThemeManager.bond_mark_color
	holder.add_child(triangle)
	holder.z_index = 1
	add_child(holder)
	return holder

func _create_bond_mark_sprite_reversed() -> Node2D:
	# Mirror of _create_bond_mark_sprite() above — tip points RIGHT instead
	# of left. Same single-triangle replacement for the same two-diamond
	# masking trick; see that function's comment for the full rationale.
	var holder = Node2D.new()
	var h = %ThemeManager.backbone_line_width / 2.0
	var w = %ThemeManager.bond_mark_width
	var triangle = Polygon2D.new()
	triangle.polygon = PackedVector2Array([
		Vector2(w / 2.0, 0),
		Vector2(0, -h),
		Vector2(0, h),
	])
	triangle.color = %ThemeManager.bond_mark_color
	holder.add_child(triangle)
	holder.z_index = 1
	add_child(holder)
	return holder

func _create_bond_mark_sprite_rna_reversed() -> Node2D:
	# Same corner geometry as _create_bond_mark_sprite_reversed() (tip
	# pointing right), but as an OPEN 3-point Line2D instead of a filled
	# Polygon2D — the "back" edge is simply never drawn, which is exactly
	# what turns a solid triangle into an open ">" chevron ("an equilateral
	# triangle without one of its sides"). Accessibility: RNA backbone must
	# be distinguishable by shape, not color alone, per the same rule the
	# rounded-square base shape follows. Sized off rna_backbone_line_width
	# and its own rna_bond_mark_width — NOT bond_mark_width, which is the
	# DNA triangle's — a filled-vs-open distinction at the SAME size proved
	# too subtle to read even paused and zoomed in; this needs to be
	# noticeably WIDER, not just a stylistic variant of the same geometry.
	var holder = Node2D.new()
	var h = %ThemeManager.rna_backbone_line_width / 2.0
	var w = %ThemeManager.rna_bond_mark_width
	var chevron = Line2D.new()
	chevron.points = PackedVector2Array([
		Vector2(0, -h),
		Vector2(w / 2.0, 0),
		Vector2(0, h),
	])
	chevron.default_color = %ThemeManager.rna_bond_mark_color
	chevron.width = %ThemeManager.rna_bond_mark_line_width
	chevron.joint_mode = Line2D.LINE_JOINT_ROUND
	chevron.begin_cap_mode = Line2D.LINE_CAP_ROUND
	chevron.end_cap_mode = Line2D.LINE_CAP_ROUND
	holder.add_child(chevron)
	holder.z_index = 1
	add_child(holder)
	return holder

# ==========================================
# SMOOTHSTEP HELPER
# ==========================================

func smoothstep(a: float, b: float, t: float) -> float:
	t = clamp((t - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)