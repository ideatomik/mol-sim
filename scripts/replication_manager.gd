extends Node

# ==========================================
# replication_manager.gd
# Phase 1 migration: owns all synthesis state, spawning, and synthesis rendering.
# simulation.gd calls update(delta, ctx) each frame and scrub_rebuild(ctx) on scrub.
# Nodes are added as children of sim (simulation.gd) so scene tree is unchanged.
# Phase 2 will introduce signals and extract okazaki_manager.gd.
# ==========================================

# ---------- PARENT REFERENCE ----------
var sim: Node = null  # Set by initialize(). Used for add_child(), geometry, etc.
var tm: Node = null   # ThemeManager reference, cached in initialize()

# ---------- PER-SLOT STATE ARRAYS ----------
var nucleotide_backbone_delta: Array[float] = []

# ---------- SYNTHESIS STATE ----------
var manual_override: bool = true

# ---------- CACHED CONTEXT (updated each frame in update()) ----------
var ctx_factory_x: float = 0.0
var ctx_helicase_x: float = 0.0
var ctx_straight_y: float = 0.0
var ctx_new_bottom_template_y: float = 0.0
var ctx_dna_ribbons_gap: float = 0.0
var ctx_new_bottom_template_offset: float = 0.0
var ctx_wobble_t: float = 0.0
var ctx_phase: int = 0
var ctx_num_slots: int = 0
#var ctx_pulse_width: float = 0.0
var ctx_nucleotide_original_x: Array = []


# ---------- SYNTHESIZED DATA (Leading Strand) ----------
var leading_synthesized_bases: Array = []
var leading_hydrogen_bonds: Array = []
var leading_backbone_line: Line2D = null
var leading_strand_bond_marks: Array[Node2D] = []
var top_polymerase: Node2D = null  # ADD
var synthesis_circle: Node2D = null  # ADD — reference to scene node, set in initialize()
var synthesis_circle_faded: bool = false  # ADD
const TOP_POLYMERASE_RADIUS: float = 16.0  # ADD — was sim.synthesis_circle_radius
# ---------- MARKERS ----------
var marker_leading_5p: Node2D = null
var marker_leading_3p: Node2D = null

# ==========================================
# LIFECYCLE
# ==========================================

func initialize(p_sim: Node) -> void:
	# Called once when simulation.gd first creates this node.
	sim = p_sim
	tm = p_sim.get_node("%ThemeManager")
	synthesis_circle = p_sim.synthesis_circle
	synthesis_circle_faded = false  # ADD
	synthesis_circle.modulate.a = 0.0  # ADD — start invisible

func reset(num_slots: int) -> void:
	# Called by simulation.gd after teardown, before spawning new slots.
	# Resets all per-slot arrays to match the new sequence length.
	manual_override = true

	for i in range(num_slots):
		leading_synthesized_bases.append(null)
		leading_hydrogen_bonds.append(null)

func setup_backbones() -> void:
	# Creates the Line2D backbone nodes owned by replication_manager.
	# Called after reset() during initialize_simulation().

	leading_backbone_line = Line2D.new()
	leading_backbone_line.default_color = tm.backbone_color
	leading_backbone_line.width = tm.backbone_line_width
	leading_backbone_line.z_index = -1
	leading_backbone_line.joint_mode = Line2D.LINE_JOINT_ROUND
	leading_backbone_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	leading_backbone_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	sim.add_child(leading_backbone_line)

	#Top polymerase visual
	if top_polymerase and is_instance_valid(top_polymerase):
		top_polymerase.queue_free()
	top_polymerase = Node2D.new()
	top_polymerase.z_index = 2
	var poly = Polygon2D.new()
	var points = PackedVector2Array()
	const SEGMENTS = 32
	for i in range(SEGMENTS):
		var angle = (float(i) / SEGMENTS) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * TOP_POLYMERASE_RADIUS)
	poly.polygon = points
	poly.color = Color(0.2, 0.4, 1.0, 1.0)
	top_polymerase.add_child(poly)
	top_polymerase.position = Vector2(sim.factory_x, sim.straight_y - sim.dna_ribbons_gap - sim.new_bottom_template_offset)
	top_polymerase.modulate.a = 0.0
	sim.add_child(top_polymerase)

func teardown() -> void:
	# Free all owned nodes. Called by simulation.gd teardown_simulation().

	for base in leading_synthesized_bases:
		if base != null and is_instance_valid(base): base.queue_free()
	for bond in leading_hydrogen_bonds:
		if bond != null and is_instance_valid(bond): bond.queue_free()
	for mark in leading_strand_bond_marks:
		if mark != null and is_instance_valid(mark): mark.queue_free()


	if leading_backbone_line and is_instance_valid(leading_backbone_line):
		leading_backbone_line.queue_free()
	if top_polymerase and is_instance_valid(top_polymerase):  # ADD
		top_polymerase.queue_free()
		top_polymerase = null

	if marker_leading_5p and is_instance_valid(marker_leading_5p): marker_leading_5p.queue_free()
	if marker_leading_3p and is_instance_valid(marker_leading_3p): marker_leading_3p.queue_free()

	# Reset refs — reset() will repopulate arrays next initialize_simulation()

	leading_backbone_line = null

	marker_leading_5p = null
	marker_leading_3p = null


# ==========================================
# UPDATE — called from simulation.gd _process
# ==========================================

func update(delta: float, ctx: Dictionary) -> void:
	var helicase_x: float = ctx.helicase_x
	var factory_x: float = ctx.factory_x
	var straight_y: float = ctx.straight_y
	var new_bottom_template_y: float = ctx.new_bottom_template_y
	var phase = ctx.phase
	var helicase_mgr = ctx.helicase_mgr
	var num_slots: int = ctx.num_slots

	var template_strand_bottom = sim.template_strand_bottom
	var nucleotide_original_x = sim.nucleotide_original_x

	# Cache context for use in signal handlers
	ctx_factory_x = ctx.factory_x
	ctx_helicase_x = ctx.helicase_x
	ctx_straight_y = ctx.straight_y
	ctx_new_bottom_template_y = ctx.new_bottom_template_y
	ctx_dna_ribbons_gap = ctx.dna_ribbons_gap
	ctx_new_bottom_template_offset = ctx.new_bottom_template_offset
	ctx_wobble_t = ctx.wobble_t
	ctx_phase = ctx.phase
	ctx_num_slots = ctx.num_slots
	ctx_nucleotide_original_x = sim.nucleotide_original_x



	# ---- DONE: fade enzymes, spawn final markers ----
	if phase == helicase_mgr.Phase.DONE and not synthesis_circle_faded:
		synthesis_circle_faded = true
		var fade_tween = sim.create_tween()
		fade_tween.tween_property(synthesis_circle, "modulate:a", 0.0, sim.fade_duration)
		if top_polymerase:
			fade_tween.parallel().tween_property(top_polymerase, "modulate:a", 0.0, sim.fade_duration)
		if sim.helicase_node:
			fade_tween.parallel().tween_property(sim.helicase_node, "modulate:a", 0.0, sim.fade_duration)

	# ADD — top polymerase position
	if top_polymerase and phase != helicase_mgr.Phase.DONE:
		top_polymerase.position = Vector2(factory_x, sim.straight_y - sim.dna_ribbons_gap - sim.new_bottom_template_offset)

	# ADD — synthesis circle position
	if synthesis_circle and phase != helicase_mgr.Phase.DONE:
		synthesis_circle.position = Vector2(factory_x, sim.new_bottom_template_y)

	if phase == helicase_mgr.Phase.FINISHING_LAST_PULSE and helicase_mgr.extra_steps_total == 0:
		var remaining_leading = 0
		for i in range(num_slots):
			if nucleotide_original_x[i] > factory_x:
				remaining_leading += 1
		helicase_mgr.start_finishing(remaining_leading)

	# ---- Leading strand synthesis ----
	var leading_synth_count = 0
	for i in range(num_slots):
		if nucleotide_original_x[i] <= factory_x:
			leading_synth_count += 1
		else:
			break
	for i in range(leading_synth_count):
		if leading_synthesized_bases[i] == null:
			leading_synthesized_bases[i] = _spawn_leading_base(i, sim.dna_sequence.get_complement(i))
			leading_hydrogen_bonds[i] = _spawn_leading_hydrogen_bonds(i)

# ==========================================
# SCRUB REBUILD — called from simulation.gd scrub_to()
# ==========================================

func scrub_rebuild(ctx: Dictionary) -> void:
	# ctx keys: target_factory_x, helicase_x, is_done_phase, num_slots,
	#           nucleotide_original_x, straight_y, helicase_mgr
	var target_factory_x: float = ctx.target_factory_x
	var helicase_x: float = ctx.helicase_x
	var is_done_phase: bool = ctx.is_done_phase
	var num_slots: int = ctx.num_slots
	var nucleotide_original_x = ctx.nucleotide_original_x
	var straight_y: float = ctx.straight_y
	# ADD — reset top polymerase visibility on scrub
	if top_polymerase:
		top_polymerase.modulate.a = 1.0 if not ctx.is_done_phase else 0.0
		top_polymerase.position = Vector2(ctx.target_factory_x, sim.straight_y - sim.dna_ribbons_gap - sim.new_bottom_template_offset)


	# ---- Free leading markers when before first base ----
	if target_factory_x < nucleotide_original_x[0]:
		if marker_leading_5p and is_instance_valid(marker_leading_5p):
			marker_leading_5p.queue_free()
			marker_leading_5p = null
		if marker_leading_3p and is_instance_valid(marker_leading_3p):
			marker_leading_3p.queue_free()
			marker_leading_3p = null

	# ADD — synthesis circle scrub
	if synthesis_circle:
		synthesis_circle_faded = ctx.is_done_phase
		synthesis_circle.modulate.a = 0.0 if ctx.is_done_phase else 1.0
		synthesis_circle.position = Vector2(ctx.target_factory_x, sim.new_bottom_template_y)

	# ---- Rebuild lagging synthesis state ----
	var lagging_synth_count = 0
	for i in range(num_slots):
		if is_done_phase:
			lagging_synth_count += 1
		elif nucleotide_original_x[i] <= target_factory_x:
			lagging_synth_count += 1
		else:
			break

	# ---- Rebuild leading strand ----
	for base in leading_synthesized_bases:
		if base != null and is_instance_valid(base): base.queue_free()
	for bond in leading_hydrogen_bonds:
		if bond != null and is_instance_valid(bond): bond.queue_free()
	leading_synthesized_bases.clear()
	leading_hydrogen_bonds.clear()
	leading_synthesized_bases.resize(num_slots)
	leading_hydrogen_bonds.resize(num_slots)

	for mark in leading_strand_bond_marks:
		if mark != null and is_instance_valid(mark): mark.queue_free()
	leading_strand_bond_marks.clear()

	var leading_synth_count = 0
	for i in range(num_slots):
		if is_done_phase or nucleotide_original_x[i] <= target_factory_x:
			leading_synth_count += 1
		else:
			break

	for i in range(leading_synth_count):
		if leading_synthesized_bases[i] == null:
			leading_synthesized_bases[i] = _spawn_leading_base(i, sim.dna_sequence.get_complement(i))
			leading_hydrogen_bonds[i] = _spawn_leading_hydrogen_bonds(i)

# ==========================================
# ENZYME ANIMATION — called from simulation.gd toggle_play() / _run_intro()
# ==========================================

func resume_enzymes() -> void:
	synthesis_circle.modulate.a = 1.0
	synthesis_circle_faded = false
	if top_polymerase:
		top_polymerase.modulate.a = 1.0

func run_intro(intro_x: float, fade_time: float, slide_time: float, tween: Tween) -> void:
	synthesis_circle.position = Vector2(intro_x - sim.gap_width, sim.new_bottom_template_y)
	tween.tween_property(synthesis_circle, "modulate:a", 1.0, fade_time)
	tween.tween_property(synthesis_circle, "position",
		Vector2(sim.factory_x, sim.new_bottom_template_y), slide_time).set_delay(fade_time)

	if top_polymerase:
		top_polymerase.position = Vector2(intro_x - sim.gap_width, sim.straight_y - sim.dna_ribbons_gap - sim.new_bottom_template_offset)
		tween.tween_property(top_polymerase, "modulate:a", 1.0, fade_time)
		tween.tween_property(top_polymerase, "position",
			Vector2(sim.factory_x, sim.straight_y - sim.dna_ribbons_gap - sim.new_bottom_template_offset), slide_time).set_delay(fade_time)

# ==========================================
# RENDER — called from simulation.gd _process visual section
# ==========================================

func render(delta: float, ctx: Dictionary) -> void:
	# Updates positions and backbones for all synthesized nodes.
	# ctx keys: wobble_t, new_bottom_template_y, dna_ribbons_gap,
	#           new_bottom_template_offset, straight_y, num_slots,
	#           nucleotide_original_x, template_strand_bottom,
	#           nucleotide_bases, top_strand_slots
	var wobble_t: float = ctx.wobble_t
	var new_bottom_template_y: float = ctx.new_bottom_template_y
	var dna_ribbons_gap: float = ctx.dna_ribbons_gap
	var new_bottom_template_offset: float = ctx.new_bottom_template_offset
	var straight_y: float = ctx.straight_y
	var num_slots: int = ctx.num_slots
	var nucleotide_original_x = ctx.nucleotide_original_x
	var template_strand_bottom = ctx.template_strand_bottom
	var nucleotide_bases = ctx.nucleotide_bases
	var top_strand_slots = ctx.top_strand_slots


	# ---- Leading strand ----
	var leading_points = PackedVector2Array()
	for i in range(leading_synthesized_bases.size()):
		if leading_synthesized_bases[i] != null:
			var wobble_y = sin(wobble_t * sim.wobble_speed * TAU + i * sim.wobble_phase_offset) * sim.wobble_amplitude
			var world_x = nucleotide_original_x[i]
			var leading_y = straight_y - dna_ribbons_gap - new_bottom_template_offset - dna_ribbons_gap + wobble_y
			leading_synthesized_bases[i].position = Vector2(world_x, leading_y)
			if leading_hydrogen_bonds[i] != null:
				var top_template_y = straight_y - dna_ribbons_gap - new_bottom_template_offset + wobble_y
				leading_hydrogen_bonds[i].position = Vector2(world_x, top_template_y)
				sim._update_hydrogen_bond_height(leading_hydrogen_bonds[i], leading_y - top_template_y)
			leading_points.append(Vector2(world_x, leading_y - tm.backbone_offset_distance))
	leading_backbone_line.points = leading_points
	leading_backbone_line.width = tm.backbone_line_width
	_update_bond_marks_leading(leading_points)


	# ---- Leading strand markers ----
	if marker_leading_5p == null and leading_synthesized_bases[0] != null:
		var wobble_first = sin(wobble_t * sim.wobble_speed * TAU) * sim.wobble_amplitude
		var leading_y = straight_y - dna_ribbons_gap - new_bottom_template_offset - dna_ribbons_gap + wobble_first
		marker_leading_5p = _spawn_marker("3'", Vector2(
			nucleotide_original_x[0] - tm.marker_offset,
			leading_y - tm.backbone_offset_distance
		))
	if marker_leading_5p:
		var wobble_first = sin(wobble_t * sim.wobble_speed * TAU) * sim.wobble_amplitude
		var leading_y = straight_y - dna_ribbons_gap - new_bottom_template_offset - dna_ribbons_gap + wobble_first
		marker_leading_5p.position = Vector2(
			nucleotide_original_x[0] - tm.marker_offset,
			leading_y - tm.backbone_offset_distance
		)
	if marker_leading_3p == null and leading_synthesized_bases[0] != null:
		var last_synth = -1
		for i in range(leading_synthesized_bases.size()):
			if leading_synthesized_bases[i] != null: last_synth = i
		if last_synth >= 0:
			var wobble_last = sin(wobble_t * sim.wobble_speed * TAU + last_synth * sim.wobble_phase_offset) * sim.wobble_amplitude
			var leading_y = straight_y - dna_ribbons_gap - new_bottom_template_offset - dna_ribbons_gap + wobble_last
			marker_leading_3p = _spawn_marker("5'", Vector2(
				nucleotide_original_x[last_synth] + tm.marker_offset,
				leading_y - tm.backbone_offset_distance
			))
	if marker_leading_3p:
		var last_synth = -1
		for i in range(leading_synthesized_bases.size()):
			if leading_synthesized_bases[i] != null: last_synth = i
		if last_synth >= 0:
			var wobble_last = sin(wobble_t * sim.wobble_speed * TAU + last_synth * sim.wobble_phase_offset) * sim.wobble_amplitude
			var leading_y = straight_y - dna_ribbons_gap - new_bottom_template_offset - dna_ribbons_gap + wobble_last
			marker_leading_3p.position = Vector2(
				nucleotide_original_x[last_synth] + tm.marker_offset,
				leading_y - tm.backbone_offset_distance
			)

# ==========================================
# QUERY FUNCTIONS
# ==========================================

func get_sequence_rich_text(helicase_x: float, nucleotide_original_x: Array) -> String:
	var text = "5' "
	var seq_string = sim.dna_sequence._to_string()
	if seq_string.is_empty():
		return "5' [empty] 3'"
	for i in range(seq_string.length()):
		var base = seq_string[i]
		if i < nucleotide_original_x.size() and nucleotide_original_x[i] <= helicase_x:
			text += "[color=#4CAF50]" + base + "[/color] "
		else:
			text += "[color=#FFFFFF]" + base + "[/color] "
		if (i + 1) % 10 == 0:
			text += " "
	text += "3'"
	return text

# ==========================================
# SPAWNING FUNCTIONS
# ==========================================

func _spawn_leading_base(index: int, base_type: String) -> Node2D:
	var base = sim.NewNitrogenBaseScene.instantiate()
	var world_x = sim.nucleotide_original_x[index]
	var leading_y = sim.straight_y - sim.dna_ribbons_gap - sim.new_bottom_template_offset - sim.dna_ribbons_gap
	base.position = Vector2(world_x, leading_y)
	base.z_index = 2
	sim.add_child(base)
	base.set_base_type(base_type)
	base.set_colors(sim._get_base_fill(base_type), tm.base_label_color)
	return base

func _spawn_leading_hydrogen_bonds(index: int) -> Node2D:
	var template_base = sim.dna_sequence.get_base(index)
	var bond_count = 3 if (template_base == "C" or template_base == "G") else 2
	var bond_color = tm.cg_bond_color if (template_base == "C" or template_base == "G") else tm.at_bond_color
	var container = Node2D.new()
	var total_width = (bond_count - 1) * tm.hydrogen_bond_spacing
	var start_x = -total_width / 2.0
	var inset = 12.0
	for b in range(bond_count):
		var line = Line2D.new()
		var lx = start_x + b * tm.hydrogen_bond_spacing
		line.add_point(Vector2(lx, -inset))
		line.add_point(Vector2(lx, -(sim.dna_ribbons_gap - inset)))
		line.default_color = bond_color
		line.width = tm.hydrogen_bond_width
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		container.add_child(line)
	sim.hydrogen_bonds_container.add_child(container)
	return container

func _spawn_marker(marker_type: String, world_pos: Vector2) -> Node2D:
	var marker = sim.NewNitrogenBaseScene.instantiate()
	marker.position = world_pos
	marker.z_index = 3
	sim.add_child(marker)
	marker.set_base_type(marker_type)
	marker.set_colors(tm.marker_color, tm.marker_font_color)
	return marker

func _update_bond_marks_leading(points: PackedVector2Array) -> void:
	var needed = max(0, points.size() - 1)
	while leading_strand_bond_marks.size() < needed:
		leading_strand_bond_marks.append(_create_bond_mark_sprite())
	while leading_strand_bond_marks.size() > needed:
		var extra = leading_strand_bond_marks.pop_back()
		extra.queue_free()
	for i in range(needed):
		var a = points[i]
		var b = points[i + 1]
		var mid = (a + b) / 2.0
		var segment = b - a
		var mark = leading_strand_bond_marks[i]
		mark.position = mid
		mark.visible = segment.length() > 0.0
		if mark.visible:
			mark.rotation = segment.angle()

func _create_bond_mark_sprite() -> Node2D:
	var holder = Node2D.new()
	var h = tm.backbone_line_width / 2.0
	var w = tm.bond_mark_width
	var black_diamond = Polygon2D.new()
	black_diamond.polygon = PackedVector2Array([
		Vector2(w / 2.0, 0),
		Vector2(0, -h),
		Vector2(-w / 2.0, 0),
		Vector2(0, h),
	])
	black_diamond.color = tm.bond_mark_black_color
	holder.add_child(black_diamond)
	var back_inset = tm.bond_mark_back_inset
	var magenta_diamond = Polygon2D.new()
	magenta_diamond.polygon = PackedVector2Array([
		Vector2(w / 2.0, 0),
		Vector2(0, -h),
		Vector2(-w / 2.0 + back_inset, 0),
		Vector2(0, h),
	])
	magenta_diamond.color = tm.backbone_color
	holder.add_child(magenta_diamond)
	holder.z_index = 1
	sim.add_child(holder)
	return holder
