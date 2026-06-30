extends Node

# ==========================================
# replication_manager.gd
# v70.5.6: synthesis_circle -> lagging_polymerase, top_polymerase -> leading_polymerase
# (naming clarity pass). Polymerase y-positions now sit exactly on their
# template strand's bonded row (template_strand_y for lagging,
# template_strand_y - dna_ribbons_gap for leading) instead of the
# polymerase_y_lagging/polymerase_y_leading offsets, so each polymerase visually
# aligns with the row of bases it's synthesizing alongside.
#
# v70.5.5: Self-containment refactor (no behavior change). All leading-strand
# logic is grouped into clearly-named _leading_* functions
# (_leading_reset, _leading_setup_backbones, _leading_teardown, _leading_update,
# _leading_scrub_rebuild, _leading_render), called from the public lifecycle/
# update/render/scrub functions, which are thin dispatchers. This mirrors
# the structure the lagging strand will use, so future Okazaki-fragment work
# only touches _lagging_* functions without threading more conditionals into
# leading-strand code. Public API (initialize, reset, setup_backbones,
# teardown, update, render, scrub_rebuild, resume_enzymes, run_intro,
# get_sequence_rich_text, manual_override) is unchanged.
#
# Also removed in v70.5.5: a dead `lagging_synth_count` computation in the
# old scrub_rebuild() that was computed but never used (leftover from the
# pre-removal lagging strand).
#
# Phase 1 + Phase 2 complete: owns all synthesis state, spawning, synthesis
# rendering, and enzyme animation. simulation.gd calls update(delta, ctx) each
# frame and scrub_rebuild(ctx) on scrub. Nodes are added as children of sim
# (simulation.gd) so the scene tree shape is unchanged.
# v70.6: factory_x/factory_y renamed to polymerase_x/polymerase_y_lagging;
# new_bottom_template_offset renamed to polymerase_y_offset; gap_width replaced
# by polymerase_x_offset_slots * nucleotide_slot_spacing. Both polymerases are
# now positioned purely as offsets from helicase_node.position (single source
# of truth for replisome positioning), owned in simulation.gd.
# Lagging strand (Okazaki fragments, trombone loop) removed; clean slate for rebuild.
# ==========================================

# ---------- PARENT REFERENCE ----------
var sim: Node = null  # Set by initialize(). Used for add_child(), geometry, etc.
var tm: Node = null   # ThemeManager reference, cached in initialize()

# ---------- PER-SLOT STATE ARRAYS ----------
var nucleotide_backbone_delta: Array[float] = []

# ---------- SYNTHESIS STATE ----------
var manual_override: bool = true

# ---------- SYNTHESIZED DATA (Lagging Strand) ----------
var lagging_fragments: Array = []          # completed fragments
var lagging_current_fragment = null        # Dictionary or null — fragment in progress
var lagging_telomere_gap = null      # {start, end, length} of unsynthesized real slots at the strand's end, or null
var connected_helicase_mgr: Node = null  # cached for Phase enum access in the phase_changed handler

# ---------- CACHED CONTEXT (updated each frame in update()) ----------
var ctx_polymerase_x: float = 0.0
var ctx_helicase_x: float = 0.0
var ctx_center_y: float = 0.0
var ctx_template_strand_y: float = 0.0
var ctx_polymerase_y_lagging: float = 0.0
var ctx_polymerase_y_leading: float = 0.0
var ctx_dna_ribbons_gap: float = 0.0
var ctx_polymerase_y_offset: float = 0.0
var ctx_wobble_t: float = 0.0
var ctx_phase: int = 0
var ctx_num_slots: int = 0
var ctx_nucleotide_original_x: Array = []


# ---------- SYNTHESIZED DATA (Leading Strand) ----------
var leading_synthesized_bases: Array = []
var leading_hydrogen_bonds: Array = []
var leading_backbone_line: Line2D = null
var leading_strand_bond_marks: Array[Node2D] = []
var leading_polymerase: Node2D = null  # renamed from top_polymerase
var lagging_polymerase: Node2D = null  # renamed from synthesis_circle — reference to scene node, set in initialize()
var lagging_polymerase_faded: bool = false  # renamed from synthesis_circle_faded
const LEADING_POLYMERASE_RADIUS: float = 16.0  # renamed from TOP_POLYMERASE_RADIUS
# ---------- MARKERS ----------
var marker_leading_5p: Node2D = null
var marker_leading_3p: Node2D = null

# ==========================================
# LIFECYCLE — public dispatchers
# ==========================================

func initialize(p_sim: Node) -> void:
	# Called once when simulation.gd first creates this node.
	sim = p_sim
	tm = p_sim.get_node("%ThemeManager")
	lagging_polymerase = p_sim.synthesis_circle
	lagging_polymerase_faded = false
	lagging_polymerase.modulate.a = 0.0  # start invisible

	# ADD — build the visible circle, mirroring leading_polymerase's polygon
	var poly = Polygon2D.new()
	var points = PackedVector2Array()
	const SEGMENTS = 32
	for i in range(SEGMENTS):
		var angle = (float(i) / SEGMENTS) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * LEADING_POLYMERASE_RADIUS)
	poly.polygon = points
	poly.color = Color(1.0, 0.3, 0.3, 1.0)
	lagging_polymerase.add_child(poly)

func reset(num_slots: int) -> void:
	# Called by simulation.gd after teardown, before spawning new slots.
	manual_override = true
	_leading_reset(num_slots)
	_lagging_reset()

func setup_backbones() -> void:
	# Called after reset() during initialize_simulation().
	_leading_setup_backbones()

func teardown() -> void:
	# Free all owned nodes. Called by simulation.gd teardown_simulation().
	_leading_teardown()

# ==========================================
# UPDATE — called from simulation.gd _process
# ==========================================

func update(delta: float, ctx: Dictionary) -> void:
	# ctx keys provided by simulation.gd:
	#   helicase_x, polymerase_x, center_y, template_strand_y,
	#   polymerase_y_lagging, polymerase_y_leading, dna_ribbons_gap,
	#   polymerase_y_offset, wobble_t, phase, helicase_mgr, num_slots
	var phase = ctx.phase
	var helicase_mgr = ctx.helicase_mgr

	# Cache context for use in signal handlers
	ctx_polymerase_x = ctx.polymerase_x
	ctx_helicase_x = ctx.helicase_x
	ctx_center_y = ctx.center_y
	ctx_template_strand_y = ctx.template_strand_y
	ctx_polymerase_y_lagging = ctx.polymerase_y_lagging
	ctx_polymerase_y_leading = ctx.polymerase_y_leading
	ctx_dna_ribbons_gap = ctx.dna_ribbons_gap
	ctx_polymerase_y_offset = ctx.polymerase_y_offset
	ctx_wobble_t = ctx.wobble_t
	ctx_phase = ctx.phase
	ctx_num_slots = ctx.num_slots
	ctx_nucleotide_original_x = sim.nucleotide_original_x

	# ---- DONE: fade enzymes ----
	if phase == helicase_mgr.Phase.DONE and not lagging_polymerase_faded:
		lagging_polymerase_faded = true
		var fade_tween = sim.create_tween()
		fade_tween.tween_property(lagging_polymerase, "modulate:a", 0.0, sim.fade_duration)
		if leading_polymerase:
			fade_tween.parallel().tween_property(leading_polymerase, "modulate:a", 0.0, sim.fade_duration)
		if sim.helicase_node:
			fade_tween.parallel().tween_property(sim.helicase_node, "modulate:a", 0.0, sim.fade_duration)

	# ---- Enzyme positions: each polymerase sits on its own template strand's row ----
	if leading_polymerase and phase != helicase_mgr.Phase.DONE:
		leading_polymerase.position = Vector2(ctx.polymerase_x, ctx.new_top_template_y)
		#print("[DEBUG] leading_polymerase.position=", leading_polymerase.position, " template_strand_y=", ctx.template_strand_y, " dna_ribbons_gap=", ctx.dna_ribbons_gap, " global_pos=", leading_polymerase.global_position)
	if lagging_polymerase and phase != helicase_mgr.Phase.DONE:
		lagging_polymerase.position = Vector2(ctx.polymerase_x, ctx.new_bottom_template_y)

	# ---- Helicase finishing trigger (driven by leading strand's remaining slots) ----
	if phase == helicase_mgr.Phase.FINISHING_LAST_PULSE and helicase_mgr.extra_steps_total == 0:
		var remaining_leading = 0
		for i in range(ctx.num_slots):
			if sim.nucleotide_original_x[i] > ctx.polymerase_x:
				remaining_leading += 1
		helicase_mgr.start_finishing(remaining_leading)

	_leading_update(ctx.polymerase_x, ctx.num_slots, sim.nucleotide_original_x)

# ==========================================
# SCRUB REBUILD — called from simulation.gd scrub_to()
# ==========================================

func scrub_rebuild(ctx: Dictionary) -> void:
	# ctx keys: target_polymerase_x, helicase_x, is_done_phase, num_slots,
	#           nucleotide_original_x, template_strand_y, helicase_mgr
	var target_polymerase_x: float = ctx.target_polymerase_x
	var nucleotide_original_x = ctx.nucleotide_original_x
	_leading_scrub_rebuild(ctx)
	_lagging_scrub_rebuild(ctx)

	# ---- Enzyme visibility/position on scrub: each polymerase sits on its own template strand's row ----
	if leading_polymerase:
		leading_polymerase.modulate.a = 1.0 if not ctx.is_done_phase else 0.0
		leading_polymerase.position = Vector2(target_polymerase_x, ctx.new_top_template_y)
	if lagging_polymerase:
		lagging_polymerase_faded = ctx.is_done_phase
		lagging_polymerase.modulate.a = 0.0 if ctx.is_done_phase else 1.0
		lagging_polymerase.position = Vector2(target_polymerase_x, ctx.new_bottom_template_y)

	_leading_scrub_rebuild(ctx)

# ==========================================
# ENZYME ANIMATION — called from simulation.gd toggle_play() / _run_intro()
# ==========================================

func resume_enzymes() -> void:
	lagging_polymerase.modulate.a = 1.0
	lagging_polymerase_faded = false
	if leading_polymerase:
		leading_polymerase.modulate.a = 1.0

func run_intro(intro_x: float, fade_time: float, slide_time: float, tween: Tween) -> void:
	var polymerase_x_offset = sim.polymerase_x_offset_slots * sim.nucleotide_slot_spacing
	#lagging_polymerase.position = Vector2(intro_x - polymerase_x_offset, sim.template_strand_y)
	lagging_polymerase.position = Vector2(intro_x - polymerase_x_offset, sim.new_bottom_template_y)
	tween.tween_property(lagging_polymerase, "modulate:a", 1.0, fade_time)
	tween.tween_property(lagging_polymerase, "position",
		Vector2(sim.polymerase_x, sim.new_bottom_template_y), slide_time).set_delay(fade_time)

	if leading_polymerase:
		leading_polymerase.position = Vector2(intro_x - polymerase_x_offset, sim.new_top_template_y)
		tween.tween_property(leading_polymerase, "modulate:a", 1.0, fade_time)
		tween.tween_property(leading_polymerase, "position",
			Vector2(sim.polymerase_x, sim.new_top_template_y), slide_time).set_delay(fade_time)

# ==========================================
# RENDER — called from simulation.gd _process visual section
# ==========================================

func render(delta: float, ctx: Dictionary) -> void:
	# Updates positions and backbones for all synthesized nodes.
	# ctx keys: wobble_t, polymerase_y_lagging, dna_ribbons_gap,
	#           polymerase_y_offset, center_y, template_strand_y,
	#           new_top_template_y, num_slots,
	#           nucleotide_original_x, template_strand_bottom,
	#           nucleotide_bases, top_strand_slots
	_leading_render(ctx)

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
# LEADING STRAND — self-contained section
# ==========================================
# Owns: leading_synthesized_bases, leading_hydrogen_bonds, leading_backbone_line,
# leading_strand_bond_marks, leading_polymerase, marker_leading_5p/3p.
# Synthesis trigger: simple position check, nucleotide_original_x[i] <= polymerase_x.
# No queue, no fragment boundaries — continuous synthesis, same as a real leading strand.

func _leading_reset(num_slots: int) -> void:
	for i in range(num_slots):
		leading_synthesized_bases.append(null)
		leading_hydrogen_bonds.append(null)

func _leading_setup_backbones() -> void:
	leading_backbone_line = Line2D.new()
	leading_backbone_line.default_color = tm.backbone_color
	leading_backbone_line.width = tm.backbone_line_width
	leading_backbone_line.z_index = -1
	leading_backbone_line.joint_mode = Line2D.LINE_JOINT_ROUND
	leading_backbone_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	leading_backbone_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	sim.add_child(leading_backbone_line)

	# Leading polymerase visual
	if leading_polymerase and is_instance_valid(leading_polymerase):
		leading_polymerase.queue_free()
	leading_polymerase = Node2D.new()
	leading_polymerase.z_index = 2
	var poly = Polygon2D.new()
	var points = PackedVector2Array()
	const SEGMENTS = 32
	for i in range(SEGMENTS):
		var angle = (float(i) / SEGMENTS) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * LEADING_POLYMERASE_RADIUS)
	poly.polygon = points
	poly.color = Color(0.2, 0.4, 1.0, 1.0)
	leading_polymerase.add_child(poly)
	leading_polymerase.position = Vector2(sim.polymerase_x, sim.new_top_template_y)
	leading_polymerase.modulate.a = 0.0
	sim.add_child(leading_polymerase)

func _leading_teardown() -> void:
	for base in leading_synthesized_bases:
		if base != null and is_instance_valid(base): base.queue_free()
	for bond in leading_hydrogen_bonds:
		if bond != null and is_instance_valid(bond): bond.queue_free()
	for mark in leading_strand_bond_marks:
		if mark != null and is_instance_valid(mark): mark.queue_free()

	if leading_backbone_line and is_instance_valid(leading_backbone_line):
		leading_backbone_line.queue_free()
	if leading_polymerase and is_instance_valid(leading_polymerase):
		leading_polymerase.queue_free()
		leading_polymerase = null

	if marker_leading_5p and is_instance_valid(marker_leading_5p): marker_leading_5p.queue_free()
	if marker_leading_3p and is_instance_valid(marker_leading_3p): marker_leading_3p.queue_free()

	leading_backbone_line = null
	marker_leading_5p = null
	marker_leading_3p = null

func _leading_update(polymerase_x: float, num_slots: int, nucleotide_original_x: Array) -> void:
	var leading_synth_count = 0
	for i in range(num_slots):
		if nucleotide_original_x[i] <= polymerase_x:
			leading_synth_count += 1
		else:
			break
	for i in range(leading_synth_count):
		if leading_synthesized_bases[i] == null:
			leading_synthesized_bases[i] = _spawn_leading_base(i, sim.dna_sequence.get_complement(i))
			leading_hydrogen_bonds[i] = _spawn_leading_hydrogen_bonds(i)

func _leading_scrub_rebuild(ctx: Dictionary) -> void:
	var target_polymerase_x: float = ctx.target_polymerase_x
	var is_done_phase: bool = ctx.is_done_phase
	var num_slots: int = ctx.num_slots
	var nucleotide_original_x = ctx.nucleotide_original_x

	# ---- Free leading markers when before first base ----
	if target_polymerase_x < nucleotide_original_x[0]:
		if marker_leading_5p and is_instance_valid(marker_leading_5p):
			marker_leading_5p.queue_free()
			marker_leading_5p = null
		if marker_leading_3p and is_instance_valid(marker_leading_3p):
			marker_leading_3p.queue_free()
			marker_leading_3p = null

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
		if is_done_phase or nucleotide_original_x[i] <= target_polymerase_x:
			leading_synth_count += 1
		else:
			break

	for i in range(leading_synth_count):
		if leading_synthesized_bases[i] == null:
			leading_synthesized_bases[i] = _spawn_leading_base(i, sim.dna_sequence.get_complement(i))
			leading_hydrogen_bonds[i] = _spawn_leading_hydrogen_bonds(i)

func _leading_render(ctx: Dictionary) -> void:
	var wobble_t: float = ctx.wobble_t
	var dna_ribbons_gap: float = ctx.dna_ribbons_gap
	var new_top_template_y: float = ctx.new_top_template_y
	var nucleotide_original_x = ctx.nucleotide_original_x

	# ---- Leading strand backbone ----
	var leading_points = PackedVector2Array()
	for i in range(leading_synthesized_bases.size()):
		if leading_synthesized_bases[i] != null:
			var wobble_y = sin(wobble_t * sim.wobble_speed * TAU + i * sim.wobble_phase_offset) * sim.wobble_amplitude
			var world_x = nucleotide_original_x[i]
			var leading_y = new_top_template_y - dna_ribbons_gap + wobble_y
			leading_synthesized_bases[i].position = Vector2(world_x, leading_y)
			if leading_hydrogen_bonds[i] != null:
				var top_template_y = new_top_template_y + wobble_y
				leading_hydrogen_bonds[i].position = Vector2(world_x, top_template_y)
				sim._update_hydrogen_bond_height(leading_hydrogen_bonds[i], leading_y - top_template_y)
			leading_points.append(Vector2(world_x, leading_y - tm.backbone_offset_distance))
	leading_backbone_line.points = leading_points
	leading_backbone_line.width = tm.backbone_line_width
	_update_bond_marks_leading(leading_points)

	# ---- Leading strand markers ----
	if marker_leading_5p == null and leading_synthesized_bases[0] != null:
		var wobble_first = sin(wobble_t * sim.wobble_speed * TAU) * sim.wobble_amplitude
		var leading_y = new_top_template_y - dna_ribbons_gap + wobble_first
		marker_leading_5p = _spawn_marker("3'", Vector2(
			nucleotide_original_x[0] - tm.marker_offset,
			leading_y - tm.backbone_offset_distance
		))
	if marker_leading_5p:
		var wobble_first = sin(wobble_t * sim.wobble_speed * TAU) * sim.wobble_amplitude
		var leading_y = new_top_template_y - dna_ribbons_gap + wobble_first
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
			var leading_y = new_top_template_y - dna_ribbons_gap + wobble_last
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
			var leading_y = new_top_template_y - dna_ribbons_gap + wobble_last
			marker_leading_3p.position = Vector2(
				nucleotide_original_x[last_synth] + tm.marker_offset,
				leading_y - tm.backbone_offset_distance
			)

# ==========================================
# LAGGING STRAND — self-contained section
# ==========================================
# Owns: lagging_fragments, lagging_current_fragment.
# Synthesis trigger: helicase.slot_reached signal (not position-based, since
# fragments need discrete boundaries at okazaki_fragment_size).
# Slot mapping: when helicase reaches `index`, the lagging polymerase's
# trailing position corresponds to slot (index - polymerase_x_offset_slots),
# matching the polymerase_x formula in simulation.gd exactly.

func connect_helicase(helicase_mgr: Node) -> void:
	connected_helicase_mgr = helicase_mgr
	if not helicase_mgr.slot_reached.is_connected(_on_helicase_slot_reached):
		helicase_mgr.slot_reached.connect(_on_helicase_slot_reached)
	if not helicase_mgr.phase_changed.is_connected(_on_helicase_phase_changed):
		helicase_mgr.phase_changed.connect(_on_helicase_phase_changed)

func _lagging_reset() -> void:
	lagging_fragments.clear()
	lagging_current_fragment = null
	lagging_telomere_gap = null

func _on_helicase_slot_reached(index: int) -> void:
	var lagging_index = index - int(sim.polymerase_x_offset_slots)
	if lagging_index < 0:
		return  # not enough unzipped strand behind the helicase yet to start synthesis
	var max_synthesizable = sim.num_nucleotide_slots - 1 - sim.telomere_primer_footprint
	if lagging_index > max_synthesizable:
		return  # terminal footprint reserved for the not-yet-modeled end primer
	_lagging_advance_to_slot(lagging_index)

func _lagging_advance_to_slot(lagging_index: int) -> void:
	if lagging_current_fragment == null:
		_lagging_open_fragment()
	lagging_current_fragment.slots.append(lagging_index)
	print("[LAGGING] slot %d added — fragment size %d/%d" % [
		lagging_index, lagging_current_fragment.slots.size(), sim.okazaki_fragment_size
	])
	if lagging_current_fragment.slots.size() >= sim.okazaki_fragment_size:
		_lagging_close_fragment()

func _lagging_open_fragment() -> void:
	lagging_current_fragment = {
		slots = [],
		loop_queue = [],
		backbone = null,
		bond_marks = [],
		marker_5p = null,
		marker_3p = null,
		complete = false,
	}
	print("[LAGGING] fragment opened")

func _lagging_close_fragment() -> void:
	lagging_current_fragment.complete = true
	lagging_fragments.append(lagging_current_fragment)
	print("[LAGGING] fragment closed — slots=%s" % [str(lagging_current_fragment.slots)])
	lagging_current_fragment = null

func _lagging_scrub_rebuild(ctx: Dictionary) -> void:
	var target_polymerase_x: float = ctx.target_polymerase_x
	var is_done_phase: bool = ctx.is_done_phase
	var num_slots: int = ctx.num_slots
	var nucleotide_original_x = ctx.nucleotide_original_x

	var max_synthesizable = num_slots - 1 - sim.telomere_primer_footprint

	var lagging_synth_count = 0
	if is_done_phase:
		lagging_synth_count = max_synthesizable + 1
	else:
		for i in range(num_slots):
			if nucleotide_original_x[i] <= target_polymerase_x:
				lagging_synth_count += 1
			else:
				break
		lagging_synth_count = min(lagging_synth_count, max_synthesizable + 1)
	lagging_synth_count = max(lagging_synth_count, 0)

	# ---- Deterministic rebuild: chunk slots 0..lagging_synth_count-1 into fragments ----
	lagging_fragments.clear()
	lagging_current_fragment = null
	lagging_telomere_gap = null

	var frag_size = sim.okazaki_fragment_size
	var i = 0
	while i < lagging_synth_count:
		var chunk_end = min(i + frag_size, lagging_synth_count)
		var frag = {
			slots = range(i, chunk_end),
			loop_queue = [],
			backbone = null,
			bond_marks = [],
			marker_5p = null,
			marker_3p = null,
			complete = (chunk_end - i) >= frag_size,
		}
		if frag.complete:
			lagging_fragments.append(frag)
		else:
			lagging_current_fragment = frag
		i = chunk_end

	# ---- At DONE, force-close any trailing partial fragment and record the gap ----
	if is_done_phase:
		var last_slot = num_slots - 1
		var last_synthesized = -1
		if lagging_current_fragment != null and lagging_current_fragment.slots.size() > 0:
			last_synthesized = lagging_current_fragment.slots[-1]
		elif lagging_fragments.size() > 0:
			last_synthesized = lagging_fragments[-1].slots[-1]
		var gap_start = last_synthesized + 1
		if last_slot >= gap_start:
			lagging_telomere_gap = {
				start = gap_start,
				end = last_slot,
				length = last_slot - gap_start + 1,
			}
		if lagging_current_fragment != null:
			lagging_current_fragment.complete = true
			lagging_fragments.append(lagging_current_fragment)
			lagging_current_fragment = null

	print("[LAGGING] scrub rebuild — synth_count=%d fragments=%d current=%s gap=%s" % [
		lagging_synth_count, lagging_fragments.size(),
		str(lagging_current_fragment.slots) if lagging_current_fragment != null else "none",
		str(lagging_telomere_gap)
	])

func _on_helicase_phase_changed(new_phase: int) -> void:
	# Scrub-driven DONE transitions are handled entirely by _lagging_scrub_rebuild(),
	# which runs right after this signal and is the sole source of truth during scrub.
	# Only force-close here for a live-play DONE transition, where fragment state has
	# been kept accurate continuously via slot_reached and is safe to finalize now.
	if new_phase == connected_helicase_mgr.Phase.DONE and not sim.manual_override:
		_lagging_force_close_at_end()

func _lagging_force_close_at_end() -> void:
	var last_slot = sim.num_nucleotide_slots - 1
	var last_synthesized = -1
	if lagging_current_fragment != null and lagging_current_fragment.slots.size() > 0:
		last_synthesized = lagging_current_fragment.slots[-1]
	elif lagging_fragments.size() > 0:
		last_synthesized = lagging_fragments[-1].slots[-1]

	# Record the telomere gap: real slots that never got assigned to any fragment.
	var gap_start = last_synthesized + 1
	if last_slot >= gap_start:
		lagging_telomere_gap = {
			start = gap_start,
			end = last_slot,
			length = last_slot - gap_start + 1,
		}
		print("[LAGGING] telomere gap recorded: slots %d-%d (length %d)" % [
			gap_start, last_slot, lagging_telomere_gap.length
		])
	else:
		lagging_telomere_gap = null
		print("[LAGGING] no telomere gap — lagging strand reached the final slot")

	# Force-close whatever fragment was still open, even if short of okazaki_fragment_size.
	if lagging_current_fragment != null:
		lagging_current_fragment.complete = true
		lagging_fragments.append(lagging_current_fragment)
		print("[LAGGING] fragment force-closed at end — slots=%s (%d/%d)" % [
			str(lagging_current_fragment.slots), lagging_current_fragment.slots.size(), sim.okazaki_fragment_size
		])
		lagging_current_fragment = null

func _spawn_leading_base(index: int, base_type: String) -> Node2D:
	var base = sim.NewNitrogenBaseScene.instantiate()
	var world_x = sim.nucleotide_original_x[index]
	var leading_y = sim.new_top_template_y - sim.dna_ribbons_gap
	base.position = Vector2(world_x, leading_y)
	base.z_index = 2
	sim.add_child(base)
	base.set_base_type(base_type)
	base.set_colors(sim._get_base_fill(base_type), tm.base_label_color)
	base.set_font(tm.base_label_font_size, tm.base_label_font)
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

# ==========================================
# SHARED SPAWNING HELPERS
# ==========================================

func _spawn_marker(marker_type: String, world_pos: Vector2) -> Node2D:
	var marker = sim.NewNitrogenBaseScene.instantiate()
	marker.position = world_pos
	marker.z_index = 3
	sim.add_child(marker)
	marker.set_base_type(marker_type)
	marker.set_colors(tm.marker_color, tm.marker_font_color)
	marker.set_font(tm.marker_font_size, tm.marker_font)
	return marker

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
