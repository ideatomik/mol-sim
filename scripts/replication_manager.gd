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

# ---------- ENUMS ----------
enum SynthesisCrossState { NONE, COMPLETED }

# ---------- PER-SLOT STATE ARRAYS ----------
var nucleotide_synthesis_state: Array = []
var nucleotide_backbone_delta: Array[float] = []

# ---------- DEBUG ----------
var last_logged_extra_steps: int = -1  # For [SWEEP] debug print — remove when sweep is confirmed stable

# ---------- SYNTHESIS STATE ----------
var baseline_switched: bool = false
var baseline_switch_nucleotide_index: int = -1
var settling_loop_depth_start: float = 0.0
var manual_override: bool = true

# ---------- SYNTHESIZED DATA (Lagging Strand) ----------
var synthesized_bases: Array = []
var hydrogen_bonds: Array = []
var new_strand_backbone_line: Line2D = null
var new_strand_backbone_delta: Array[float] = []

# ---------- SYNTHESIZED DATA (Leading Strand) ----------
var leading_synthesized_bases: Array = []
var leading_hydrogen_bonds: Array = []
var leading_backbone_line: Line2D = null
var leading_strand_bond_marks: Array[Node2D] = []

# ---------- OKAZAKI FRAGMENTS ----------
# Each entry: { slots: Array[int], backbone: Line2D, bond_marks: Array[Node2D],
#               marker_5p: Node2D, marker_3p: Node2D, complete: bool }
var okazaki_fragments: Array = []
var current_fragment_index: int = -1
var last_synthesis_pulse_cycle: int = -1

# ---------- MARKERS ----------
var marker_new_5p: Node2D = null
var marker_new_3p: Node2D = null
var marker_leading_5p: Node2D = null
var marker_leading_3p: Node2D = null

# ==========================================
# LIFECYCLE
# ==========================================

func initialize(p_sim: Node) -> void:
	# Called once when simulation.gd first creates this node.
	sim = p_sim
	tm = p_sim.get_node("%ThemeManager")

func reset(num_slots: int) -> void:
	# Called by simulation.gd after teardown, before spawning new slots.
	# Resets all per-slot arrays to match the new sequence length.
	baseline_switched = false
	baseline_switch_nucleotide_index = -1
	settling_loop_depth_start = 0.0
	manual_override = true
	last_synthesis_pulse_cycle = -1
	current_fragment_index = -1
	last_logged_extra_steps = -1

	nucleotide_synthesis_state.clear()
	nucleotide_backbone_delta.clear()
	synthesized_bases.clear()
	hydrogen_bonds.clear()
	new_strand_backbone_delta.clear()
	leading_synthesized_bases.clear()
	leading_hydrogen_bonds.clear()
	leading_strand_bond_marks.clear()
	okazaki_fragments.clear()

	for i in range(num_slots):
		nucleotide_synthesis_state.append(SynthesisCrossState.NONE)
		nucleotide_backbone_delta.append(tm.backbone_offset_distance)
		synthesized_bases.append(null)
		hydrogen_bonds.append(null)
		new_strand_backbone_delta.append(tm.backbone_offset_distance)
		leading_synthesized_bases.append(null)
		leading_hydrogen_bonds.append(null)

func setup_backbones() -> void:
	# Creates the Line2D backbone nodes owned by replication_manager.
	# Called after reset() during initialize_simulation().
	new_strand_backbone_line = Line2D.new()
	new_strand_backbone_line.default_color = tm.backbone_color
	new_strand_backbone_line.width = tm.backbone_line_width
	new_strand_backbone_line.z_index = -1
	new_strand_backbone_line.joint_mode = Line2D.LINE_JOINT_ROUND
	new_strand_backbone_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	new_strand_backbone_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	sim.add_child(new_strand_backbone_line)

	leading_backbone_line = Line2D.new()
	leading_backbone_line.default_color = tm.backbone_color
	leading_backbone_line.width = tm.backbone_line_width
	leading_backbone_line.z_index = -1
	leading_backbone_line.joint_mode = Line2D.LINE_JOINT_ROUND
	leading_backbone_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	leading_backbone_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	sim.add_child(leading_backbone_line)

func teardown() -> void:
	# Free all owned nodes. Called by simulation.gd teardown_simulation().
	for base in synthesized_bases:
		if base != null and is_instance_valid(base): base.queue_free()
	for bond in hydrogen_bonds:
		if bond != null and is_instance_valid(bond): bond.queue_free()
	for base in leading_synthesized_bases:
		if base != null and is_instance_valid(base): base.queue_free()
	for bond in leading_hydrogen_bonds:
		if bond != null and is_instance_valid(bond): bond.queue_free()
	for mark in leading_strand_bond_marks:
		if mark != null and is_instance_valid(mark): mark.queue_free()

	for frag in okazaki_fragments:
		if frag.has("backbone") and is_instance_valid(frag.backbone):
			frag.backbone.queue_free()
		for mark in frag.bond_marks:
			if is_instance_valid(mark): mark.queue_free()
		if frag.has("marker_5p") and frag.marker_5p and is_instance_valid(frag.marker_5p):
			frag.marker_5p.queue_free()
		if frag.has("marker_3p") and frag.marker_3p and is_instance_valid(frag.marker_3p):
			frag.marker_3p.queue_free()

	if new_strand_backbone_line and is_instance_valid(new_strand_backbone_line):
		new_strand_backbone_line.queue_free()
	if leading_backbone_line and is_instance_valid(leading_backbone_line):
		leading_backbone_line.queue_free()
	if marker_new_5p and is_instance_valid(marker_new_5p): marker_new_5p.queue_free()
	if marker_new_3p and is_instance_valid(marker_new_3p): marker_new_3p.queue_free()
	if marker_leading_5p and is_instance_valid(marker_leading_5p): marker_leading_5p.queue_free()
	if marker_leading_3p and is_instance_valid(marker_leading_3p): marker_leading_3p.queue_free()

	# Reset refs — reset() will repopulate arrays next initialize_simulation()
	new_strand_backbone_line = null
	leading_backbone_line = null
	marker_new_5p = null
	marker_new_3p = null
	marker_leading_5p = null
	marker_leading_3p = null
	okazaki_fragments.clear()
	current_fragment_index = -1

# ==========================================
# UPDATE — called from simulation.gd _process
# ==========================================

func update(delta: float, ctx: Dictionary) -> void:
	# ctx keys provided by simulation.gd:
	#   helicase_x, factory_x, loop_depth, straight_y, new_bottom_template_y,
	#   dna_ribbons_gap, new_bottom_template_offset, wobble_t, phase,
	#   helicase_mgr, num_slots, pulse_width
	var helicase_x: float = ctx.helicase_x
	var factory_x: float = ctx.factory_x
	var straight_y: float = ctx.straight_y
	var new_bottom_template_y: float = ctx.new_bottom_template_y
	var phase = ctx.phase
	var helicase_mgr = ctx.helicase_mgr
	var num_slots: int = ctx.num_slots
	var pulse_width: float = ctx.pulse_width

	var template_strand_bottom = sim.template_strand_bottom
	var nucleotide_original_x = sim.nucleotide_original_x

	# ---- FINISHING_LAST_PULSE: end-of-run lagging sweep ----
	# Guard: extra_steps_total == 0 means start_finishing() hasn't been called yet.
	if phase == helicase_mgr.Phase.FINISHING_LAST_PULSE and helicase_mgr.extra_steps_total != last_logged_extra_steps:
		last_logged_extra_steps = helicase_mgr.extra_steps_total
		print("[SWEEP] FINISHING_LAST_PULSE — extra_steps_total=%d" % helicase_mgr.extra_steps_total)
	if phase == helicase_mgr.Phase.FINISHING_LAST_PULSE and helicase_mgr.extra_steps_total == 0:
		for j in range(num_slots):
			if nucleotide_synthesis_state[j] == SynthesisCrossState.NONE:
				nucleotide_synthesis_state[j] = SynthesisCrossState.COMPLETED
				synthesized_bases[j] = _spawn_complement_base(j)
				hydrogen_bonds[j] = _spawn_hydrogen_bonds(j)
				_assign_to_okazaki_fragment(j, nucleotide_original_x, pulse_width)
				print("[t=%s] nucleotide_slot[%d] COMPLETED via end-of-run sweep" % [Time.get_ticks_msec(), j])
		if current_fragment_index >= 0 and not okazaki_fragments[current_fragment_index].complete:
			_close_okazaki_fragment(current_fragment_index)
		settling_loop_depth_start = ctx.loop_depth
		var remaining_leading = 0
		for i in range(num_slots):
			if nucleotide_original_x[i] > factory_x:
				remaining_leading += 1
		helicase_mgr.start_finishing(remaining_leading)

	# ---- DONE: fade enzymes, spawn final markers ----
	if phase == helicase_mgr.Phase.DONE and not sim.synthesis_circle_faded:
		sim.synthesis_circle_faded = true
		var fade_tween = sim.create_tween()
		fade_tween.tween_property(sim.synthesis_circle, "modulate:a", 0.0, sim.fade_duration)
		if sim.top_polymerase:
			fade_tween.parallel().tween_property(sim.top_polymerase, "modulate:a", 0.0, sim.fade_duration)
		if sim.helicase_node:
			fade_tween.parallel().tween_property(sim.helicase_node, "modulate:a", 0.0, sim.fade_duration)
		var last = num_slots - 1
		var wobble_last = sim.nucleotide_bases[last].position.y
		marker_new_3p = _spawn_marker("3'", Vector2(
			nucleotide_original_x[last] + tm.marker_offset,
			new_bottom_template_y + sim.dna_ribbons_gap + wobble_last + new_strand_backbone_delta[last]
		))
		marker_new_3p.modulate.a = 0.0  # Hidden until ligase joins fragments

	# ---- Lagging strand: baseline switch detection ----
	# Proximity synthesis removed — lagging synthesis is now triggered
	# deterministically by synthesize_lagging_slot() via loop release animation.
	if not baseline_switched:
		for i in range(sim.template_strand_bottom.size()):
			if sim.template_strand_bottom[i].position.y >= new_bottom_template_y:
				baseline_switched = true
				baseline_switch_nucleotide_index = i
				print(">>> BASELINE SWITCH by slot[%d]" % i)
				break

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

func synthesize_lagging_slot(slot_index: int, ctx: Dictionary) -> void:
	# Called by simulation.gd release animation when a slot exits through factory_x.
	var pulse_width: float = ctx.pulse_width
	var nucleotide_original_x = sim.nucleotide_original_x
	var num_slots = nucleotide_synthesis_state.size()
	if slot_index < 0 or slot_index >= num_slots:
		return
	if nucleotide_synthesis_state[slot_index] == SynthesisCrossState.COMPLETED:
		return
	nucleotide_synthesis_state[slot_index] = SynthesisCrossState.COMPLETED
	synthesized_bases[slot_index] = _spawn_complement_base(slot_index)
	hydrogen_bonds[slot_index] = _spawn_hydrogen_bonds(slot_index)
	_assign_to_okazaki_fragment(slot_index, nucleotide_original_x, pulse_width)
	print("[LAGGING] synthesized slot %d via loop release" % slot_index)

# ==========================================
# SCRUB REBUILD — called from simulation.gd scrub_to()
# ==========================================

func scrub_rebuild(ctx: Dictionary) -> void:
	# ctx keys: target_factory_x, helicase_x,
	#           is_done_phase, num_slots, pulse_width,
	#           nucleotide_original_x, straight_y, helicase_mgr
	var target_factory_x: float = ctx.target_factory_x
	var helicase_x: float = ctx.helicase_x
	var is_done_phase: bool = ctx.is_done_phase
	var num_slots: int = ctx.num_slots
	var pulse_width: float = ctx.pulse_width
	var nucleotide_original_x = ctx.nucleotide_original_x
	var straight_y: float = ctx.straight_y

	# ---- Free synthesized bases ----
	for base in synthesized_bases:
		if base != null and is_instance_valid(base): base.queue_free()
	for bond in hydrogen_bonds:
		if bond != null and is_instance_valid(bond): bond.queue_free()
	synthesized_bases.clear()
	hydrogen_bonds.clear()
	synthesized_bases.resize(num_slots)
	hydrogen_bonds.resize(num_slots)

	# ---- Free Okazaki fragments ----
	for frag in okazaki_fragments:
		if frag.has("backbone") and is_instance_valid(frag.backbone): frag.backbone.queue_free()
		for mark in frag.bond_marks:
			if is_instance_valid(mark): mark.queue_free()
		if frag.marker_5p and is_instance_valid(frag.marker_5p): frag.marker_5p.queue_free()
		if frag.marker_3p and is_instance_valid(frag.marker_3p): frag.marker_3p.queue_free()
	okazaki_fragments.clear()
	current_fragment_index = -1
	last_synthesis_pulse_cycle = -1

	# ---- Free whole-strand lagging markers when before first base ----
	if target_factory_x < nucleotide_original_x[0]:
		if marker_new_5p and is_instance_valid(marker_new_5p):
			marker_new_5p.queue_free()
			marker_new_5p = null
	# marker_new_3p always freed on scrub
	if marker_new_3p and is_instance_valid(marker_new_3p):
		marker_new_3p.queue_free()
		marker_new_3p = null

	# ---- Free leading markers when before first base ----
	if target_factory_x < nucleotide_original_x[0]:
		if marker_leading_5p and is_instance_valid(marker_leading_5p):
			marker_leading_5p.queue_free()
			marker_leading_5p = null
		if marker_leading_3p and is_instance_valid(marker_leading_3p):
			marker_leading_3p.queue_free()
			marker_leading_3p = null

	# ---- Rebuild lagging synthesis state ----
	var lagging_synth_count = 0
	for i in range(num_slots):
		if is_done_phase or nucleotide_original_x[i] <= target_factory_x:
			lagging_synth_count += 1
		else:
			break

	for i in range(lagging_synth_count):
		if synthesized_bases[i] == null:
			synthesized_bases[i] = _spawn_complement_base(i)
			hydrogen_bonds[i] = _spawn_hydrogen_bonds(i)
		nucleotide_synthesis_state[i] = SynthesisCrossState.COMPLETED

	# ---- Rebuild Okazaki fragments ----
	for i in range(lagging_synth_count):
		var scrub_pulse_cycle = int((nucleotide_original_x[i] - nucleotide_original_x[0]) / pulse_width)
		var needs_new_frag = (scrub_pulse_cycle != last_synthesis_pulse_cycle)
		if needs_new_frag:
			if current_fragment_index >= 0:
				_close_okazaki_fragment(current_fragment_index)
			current_fragment_index = _start_new_okazaki_fragment()
		okazaki_fragments[current_fragment_index].slots.append(i)
		last_synthesis_pulse_cycle = scrub_pulse_cycle
	for fi in range(okazaki_fragments.size() - 1):
		okazaki_fragments[fi].complete = true
	if current_fragment_index >= 0 and target_factory_x > nucleotide_original_x[num_slots - 1]:
		_close_okazaki_fragment(current_fragment_index)

	for i in range(lagging_synth_count, num_slots):
		nucleotide_synthesis_state[i] = SynthesisCrossState.NONE

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

	# ---- Lagging strand: Okazaki fragments ----
	new_strand_backbone_line.points = PackedVector2Array()
	var y_off = tm.okazaki_marker_y_offset

	for frag_idx in range(okazaki_fragments.size()):
		var frag = okazaki_fragments[frag_idx]
		var frag_points = PackedVector2Array()

		for si in range(frag.slots.size()):
			var i = frag.slots[si]
			if synthesized_bases[i] == null:
				continue
			var template_slot = template_strand_bottom[i]
			var wobble_y = nucleotide_bases[i].position.y
			var world_x = template_slot.position.x
			var world_y = new_bottom_template_y + dna_ribbons_gap + wobble_y
			synthesized_bases[i].position = Vector2(world_x, world_y)
			if hydrogen_bonds[i] != null:
				var container_y = new_bottom_template_y + wobble_y
				hydrogen_bonds[i].position = Vector2(world_x, container_y)
				sim._update_hydrogen_bond_height(hydrogen_bonds[i], world_y - container_y)
			new_strand_backbone_delta[i] = lerp(
				new_strand_backbone_delta[i],
				tm.backbone_offset_distance,
				clamp(tm.backbone_offset_smoothing_speed * delta, 0.0, 1.0)
			)
			frag_points.append(Vector2(world_x, world_y + new_strand_backbone_delta[i]))

		frag.backbone.points = frag_points
		frag.backbone.width = tm.backbone_line_width
		sim._update_bond_marks_fragment(frag, frag_points)

		if frag.complete and frag_points.size() >= 1:
			var tip_pt = frag_points[frag_points.size() - 1]
			var origin_pt = frag_points[0]
			if frag_points.size() == 1:
				if frag.marker_5p == null:
					frag.marker_5p = _spawn_marker("5'-3'", Vector2(tip_pt.x, tip_pt.y + y_off))
			else:
				if frag.marker_5p == null:
					frag.marker_5p = _spawn_marker("5'", Vector2(origin_pt.x, origin_pt.y + y_off))
				if frag.marker_3p == null:
					frag.marker_3p = _spawn_marker("3'", Vector2(tip_pt.x, tip_pt.y + y_off))

		if frag_points.size() >= 1:
			var tip_pt = frag_points[frag_points.size() - 1]
			var origin_pt = frag_points[0]
			if frag_points.size() == 1:
				if frag.marker_5p:
					frag.marker_5p.position = Vector2(tip_pt.x, tip_pt.y + y_off)
			else:
				if frag.marker_5p:
					frag.marker_5p.position = Vector2(origin_pt.x, origin_pt.y + y_off)
				if frag.marker_3p:
					frag.marker_3p.position = Vector2(tip_pt.x, tip_pt.y + y_off)

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
	sim._update_bond_marks_leading(leading_points)

	# ---- Lagging whole-strand markers ----
	if marker_new_5p == null and synthesized_bases[0] != null:
		var wobble_first = nucleotide_bases[0].position.y
		marker_new_5p = _spawn_marker("5'", Vector2(
			template_strand_bottom[0].position.x - tm.marker_offset,
			new_bottom_template_y + dna_ribbons_gap + wobble_first + new_strand_backbone_delta[0]
		))
		marker_new_5p.modulate.a = 0.0  # Hidden until ligase joins fragments
	if marker_new_5p:
		var wobble_first = nucleotide_bases[0].position.y
		marker_new_5p.position = Vector2(
			template_strand_bottom[0].position.x - tm.marker_offset,
			new_bottom_template_y + dna_ribbons_gap + wobble_first + new_strand_backbone_delta[0]
		)
	if marker_new_3p:
		var last = num_slots - 1
		var wobble_last = nucleotide_bases[last].position.y
		marker_new_3p.position = Vector2(
			nucleotide_original_x[last] + tm.marker_offset,
			new_bottom_template_y + dna_ribbons_gap + wobble_last + new_strand_backbone_delta[last]
		)

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

func get_synthesized_count() -> int:
	var count = 0
	for base in synthesized_bases:
		if base != null and is_instance_valid(base): count += 1
	return count

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

func _spawn_complement_base(template_index: int) -> Node2D:
	var base = sim.NewNitrogenBaseScene.instantiate()
	var base_type = sim.dna_sequence.get_base(template_index)
	base.position = Vector2(sim.template_strand_bottom[template_index].position.x, 0.0)
	base.z_index = 2
	sim.add_child(base)
	base.set_base_type(base_type)
	base.set_colors(sim._get_base_fill(base_type), tm.base_label_color)
	return base

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

func _spawn_hydrogen_bonds(template_index: int) -> Node2D:
	var base_type = sim.dna_sequence.get_base(template_index)
	var bond_count = 3 if (base_type == "C" or base_type == "G") else 2
	var bond_color = tm.cg_bond_color if (base_type == "C" or base_type == "G") else tm.at_bond_color
	var container = Node2D.new()
	var total_width = (bond_count - 1) * tm.hydrogen_bond_spacing
	var start_x = -total_width / 2.0
	var inset = 12.0
	for b in range(bond_count):
		var line = Line2D.new()
		var lx = start_x + b * tm.hydrogen_bond_spacing
		line.add_point(Vector2(lx, inset))
		line.add_point(Vector2(lx, sim.dna_ribbons_gap - inset))
		line.default_color = bond_color
		line.width = tm.hydrogen_bond_width
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		container.add_child(line)
	sim.hydrogen_bonds_container.add_child(container)
	return container

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

func _start_new_okazaki_fragment() -> int:
	var backbone = Line2D.new()
	backbone.default_color = tm.backbone_color
	backbone.width = tm.backbone_line_width
	backbone.z_index = -1
	backbone.joint_mode = Line2D.LINE_JOINT_ROUND
	backbone.begin_cap_mode = Line2D.LINE_CAP_ROUND
	backbone.end_cap_mode = Line2D.LINE_CAP_ROUND
	sim.add_child(backbone)
	var frag = {
		slots = [],
		backbone = backbone,
		bond_marks = [],
		marker_5p = null,
		marker_3p = null,
		complete = false
	}
	okazaki_fragments.append(frag)
	return okazaki_fragments.size() - 1

func _close_okazaki_fragment(frag_index: int) -> void:
	if frag_index < 0 or frag_index >= okazaki_fragments.size():
		return
	if okazaki_fragments[frag_index].complete:
		return  # Already closed — guard against scrub_rebuild re-closing
	okazaki_fragments[frag_index].complete = true
	print("[OKAZAKI] Closed fragment #%d — slots: %s" % [frag_index, str(okazaki_fragments[frag_index].slots)])

func _assign_to_okazaki_fragment(slot_index: int, nucleotide_original_x: Array, pulse_width: float) -> void:
	var current_pulse_cycle = int((nucleotide_original_x[slot_index] - nucleotide_original_x[0]) / pulse_width)
	var needs_new_frag = (current_pulse_cycle != last_synthesis_pulse_cycle)
	if needs_new_frag:
		if current_fragment_index >= 0 and not okazaki_fragments[current_fragment_index].complete:
			_close_okazaki_fragment(current_fragment_index)
		current_fragment_index = _start_new_okazaki_fragment()
	okazaki_fragments[current_fragment_index].slots.append(slot_index)
	last_synthesis_pulse_cycle = current_pulse_cycle
	print("[OKAZAKI] Slot %d assigned to fragment #%d (pulse_cycle=%d, needs_new=%s)" % [slot_index, current_fragment_index, current_pulse_cycle, str(needs_new_frag)])
