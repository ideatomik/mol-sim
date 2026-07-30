class_name MoleculeStructureRenderer
extends Node2D

# ==========================================
# MOLECULE STRUCTURE RENDERER
# Growth-phase implementation of the DNA-first milestone
# (MolecularStructureDesign.md, ClaudeCode_Handout_MolecularStructure.md).
# Skeletal (line-angle) rendering of each synthesized nucleotide's ribose
# ring + surviving alpha-phosphate, active ONLY at deep free-camera zoom.
#
# Persisted scene node, sibling of $NucleotideField under the root
# Simulation node — matches nucleotide_field.gd's Inspector-editable,
# not-code-instantiated convention. No sequence-load lifecycle of its own;
# it just needs a live data feed (see set_replication_manager()).
#
# Immediate-mode (single _draw(), parallel arrays), NOT per-atom nodes —
# large-count-over-time case, matching nucleotide_field.gd's pattern rather
# than polymerase_halo.gd's small-fixed-pool one. See
# MolecularStructureDesign.md correction #7/#13 for the criterion.
# ==========================================

# ---------- REFERENCES (cached once in _ready(); VALUES read live every frame) ----------
var tm: Node = null
var zoom_mgr: Node = null
var replication_mgr: Node = null  # pushed in via set_replication_manager(), never looked up cross-tree

# ---------- STORED PER-ATOM/PER-BOND LAYOUT ----------
## Cheap insurance for a future atom-picking pass (Open Question 8,
## deferred but not blocked): {position: Vector2, element: String,
## atom_id: int, nucleotide_slot: int}. Written every frame by
## _rebuild_layout(), read by _draw() — never local-only, so a future hit
## test is "iterate this array," not a rebuild.
var _atom_layout: Array[Dictionary] = []
## {from: Vector2, to: Vector2}
var _bond_layout: Array[Dictionary] = []

## Last hysteresis decision. Gates ONLY the draw calls — layout below runs
## unconditionally every frame regardless of this, per the render-mode
## transition decision (Open Question 10): no first-crossing hitch.
var _active: bool = false

## Fold results are cacheable per (slot, strand) — this milestone has
## exactly one operator, so the cache key is effectively "has this slot's
## phosphodiester bond formed yet" (spawned or not), not a real step
## counter. Flagged in the approved plan: if a second DNA-scope operator is
## ever added, this needs to become a real per-step cache, not a bool.
var _fold_cache: Dictionary = {}  # "leading:12" -> MoleculeTopology

const OPERATOR_PATH: String = "res://resources/phosphodiester_bond_formation.tres"
var _phosphodiester_operator: ReactionOperator = null
var _operators: Array[ReactionOperator] = []  # [_phosphodiester_operator] — built once in _ready(), typed explicitly so fold()'s Array[ReactionOperator] parameter doesn't need to coerce an untyped literal every frame


func _ready() -> void:
	tm = get_node("%ThemeManager")
	zoom_mgr = get_node_or_null("%ZoomManager")
	_phosphodiester_operator = load(OPERATOR_PATH)
	_operators = [_phosphodiester_operator]


func set_replication_manager(mgr: Node) -> void:
	replication_mgr = mgr


func _process(_delta: float) -> void:
	if replication_mgr == null or zoom_mgr == null or tm == null:
		return
	_active = _compute_active()
	_rebuild_layout()
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


func _rebuild_layout() -> void:
	_atom_layout.clear()
	_bond_layout.clear()

	var bond_length: float = tm.molecular_ring_bond_length_ratio * _slot_spacing()
	var cull_rect: Rect2 = _current_viewport_world_rect()

	for entry in replication_mgr.get_synthesized_nucleotides():
		var world_pos: Vector2 = entry.world_position
		var padding: float = tm.molecular_cull_bbox_padding
		var bbox := Rect2(world_pos - Vector2.ONE * padding, Vector2.ONE * padding * 2.0)
		# CULLING: per-molecule (per-nucleotide) bounding-box only, per this
		# milestone's decision (MolecularStructure_OpenQuestions_
		# RenderClusterResolution.md, question 9). nucleotide_field.gd's own
		# max_particles=200 cap exists because this project measured a real
		# FPS drop around ~1,200 immediate-mode glyphs on target hardware —
		# nowhere near this pass's working set (~20 atoms x a handful of
		# on-screen nucleotides at deep zoom). A per-ATOM cull tier is
		# explicitly deferred, not forgotten, should a future pass (Krebs,
		# more atoms per molecule) approach that ceiling.
		if not cull_rect.intersects(bbox):
			continue

		var cache_key: String = "%s:%d" % [entry.strand, entry.slot]
		var topology: MoleculeTopology = _fold_cache.get(cache_key)
		if topology == null:
			var seed: MoleculeTopology = RiboseDeriver.build_incoming_nucleotide_seed()
			topology = MoleculeFoldEngine.fold(seed, _operators, 0)
			_fold_cache[cache_key] = topology

		var ring_positions: Dictionary = RiboseDeriver.derive_ring(topology, "incoming.", bond_length)
		var substituent_positions: Dictionary = RiboseDeriver.derive_substituents(topology, "incoming.", ring_positions, bond_length)

		var local_positions: Dictionary = {}
		for id in ring_positions:
			local_positions[id] = ring_positions[id]
		for id in substituent_positions:
			local_positions[id] = substituent_positions[id]

		for atom in topology.atoms:
			if not local_positions.has(atom.id):
				continue
			var world: Vector2 = world_pos + local_positions[atom.id]
			_atom_layout.append({
				position = world,
				element = atom.element,
				atom_id = atom.id,
				nucleotide_slot = entry.slot,
			})

		for bond in topology.bonds:
			if not local_positions.has(bond.a) or not local_positions.has(bond.b):
				continue
			_bond_layout.append({
				from = world_pos + local_positions[bond.a],
				to = world_pos + local_positions[bond.b],
			})


func _slot_spacing() -> float:
	if replication_mgr != null and replication_mgr.sim != null and "nucleotide_slot_spacing" in replication_mgr.sim:
		return replication_mgr.sim.nucleotide_slot_spacing
	return 54.0


## NOT nucleotide_field.gd's _visible_world_rect() — that function is
## deliberately zoom-INDEPENDENT (a fixed "overworld" extent, a different
## fix for a different bug). This renderer needs a genuine CURRENT-viewport
## visibility test, since at deep zoom only a couple of nucleotides are
## ever on screen and the whole point is not issuing dead draw calls for
## the rest of a long strand.
func _current_viewport_world_rect() -> Rect2:
	var z: float = zoom_mgr.zoom.x
	if z <= 0.0:
		return Rect2()
	var world_size: Vector2 = get_viewport().get_visible_rect().size / z
	return Rect2(zoom_mgr.global_position - world_size * 0.5, world_size)


func _element_color(element: String) -> Color:
	match element:
		"C": return Color(0.75, 0.75, 0.78)
		"O": return Color(0.85, 0.25, 0.2)
		"P": return Color(0.95, 0.6, 0.15)
		_: return tm.molecular_bond_color


func _draw() -> void:
	if not _active:
		return

	# Bonds: ProceduralShapeUtils.inset_segment() shortens each bond to run
	# edge-to-edge rather than centre-to-centre (avoids showing through an
	# atom's own circle/label — the exact failure mode it was built to fix
	# for the ATP cofactor beads; see MolecularStructureDesign.md
	# correction #8). draw_line() has no round-cap option the way a Line2D
	# node does, so each bond is drawn as a straight segment PLUS a
	# draw_circle() at both endpoints (half line-width radius) — three
	# calls per bond instead of one. At this milestone's atom counts
	# (~10-15 visible bonds max) this is free, and squared ends would
	# visibly clip at every ring-vertex junction, which is exactly the one
	# place this renderer needs a clean joint.
	var half_width: float = tm.molecular_bond_width * 0.5
	for b in _bond_layout:
		var endpoints: PackedVector2Array = ProceduralShapeUtils.inset_segment(
			b.from, b.to, tm.molecular_atom_radius, tm.molecular_atom_radius
		)
		if endpoints.size() < 2:
			continue
		draw_line(endpoints[0], endpoints[1], tm.molecular_bond_color, tm.molecular_bond_width, true)
		draw_circle(endpoints[0], half_width, tm.molecular_bond_color, true, -1.0, true)
		draw_circle(endpoints[1], half_width, tm.molecular_bond_color, true, -1.0, true)

	# Atoms: element-colored circle + counter-rotated label, mirroring
	# nucleotide_field.gd's exact per-glyph transform pattern (cache the
	# ZoomManager REFERENCE, read rotation LIVE here) — including the
	# MANDATORY draw_set_transform reset after each label, since the loop
	# continues and the next atom's draw_circle() uses absolute coords.
	var label_rotation: float = zoom_mgr.get_label_counter_rotation() if zoom_mgr != null else 0.0
	var font: Font = tm.base_label_font if tm.base_label_font != null else ThemeDB.fallback_font
	var font_size: int = tm.base_label_font_size
	for a in _atom_layout:
		draw_circle(a.position, tm.molecular_atom_radius, _element_color(a.element), true, -1.0, true)
		if font != null:
			var ssize: Vector2 = font.get_string_size(a.element, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var ascent: float = font.get_ascent(font_size)
			var draw_pos: Vector2 = Vector2(-ssize.x / 2.0, ascent - ssize.y / 2.0)
			draw_set_transform(a.position, label_rotation, Vector2.ONE)
			draw_string(font, draw_pos, a.element, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tm.base_label_color)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
