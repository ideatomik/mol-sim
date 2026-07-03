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
var lagging_backbone_line: Line2D = null
var lagging_bond_marks: Array[Node2D] = []
var lagging_synthesized_bases: Array = []
var lagging_hydrogen_bonds: Array = []
var connected_helicase_mgr: Node = null  # cached for Phase enum access in the phase_changed handler

var lagging_total_fragments: int = 0     # floor(num_slots / okazaki_fragment_size) — hard safety cap, prevents ever firing an out-of-range slot
var lagging_firing_started: bool = false # true once the one-time startup delay has passed
var lagging_total_consumed: int = 0      # total slots actually fired so far
var lagging_batch_cursor: int = 0        # next slot index to fire within the currently-open fragment (counts down)
var lagging_polymerase_x: float = 0.0    # independent position of the lagging polymerase visual — no longer helicase-relative
var lagging_catchup_timer: Timer = null


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
const LEADING_POLYMERASE_RADIUS: float = 24.0  # renamed from TOP_POLYMERASE_RADIUS
# ---------- MARKERS ----------
var marker_leading_5p: Node2D = null
var marker_leading_3p: Node2D = null


var lagging_polymerase_tween: Tween = null
var leading_clamp: PolymeraseClamp = null
var lagging_clamp: PolymeraseClamp = null
var leading_halo: PolymeraseHalo = null
var lagging_halo: PolymeraseHalo = null
var lagging_pump_tween: Tween = null
# ==========================================
# LIFECYCLE — public dispatchers
# ==========================================

func initialize(p_sim: Node) -> void:
	# Called once when simulation.gd first creates this node.
	sim = p_sim
	tm = p_sim.get_node("%ThemeManager")
	lagging_polymerase = p_sim.synthesis_circle
	lagging_polymerase.z_index = 10
	lagging_polymerase_faded = false
	lagging_polymerase.modulate.a = 0.0  # start invisible

	# Build the 3-piece lagging clamp as a child of the SynthesisCircle node.
	# It self-offsets to the duplex centre and z-threads the strand between its
	# back pieces and front cap — no positioning code here changes.
	lagging_clamp = PolymeraseClamp.new()
	lagging_polymerase.add_child(lagging_clamp)
	lagging_clamp.setup(sim, false, Color(0.80, 0.32, 0.32), Color(0.95, 0.52, 0.52))
	lagging_halo = PolymeraseHalo.new()
	lagging_polymerase.add_child(lagging_halo)
	lagging_halo.setup(sim, false)

func reset(num_slots: int) -> void:
	# Called by simulation.gd after teardown, before spawning new slots.
	manual_override = true
	_leading_reset(num_slots)
	_lagging_reset(num_slots)

func setup_backbones() -> void:
	# Called after reset() during initialize_simulation().
	_leading_setup_backbones()
	_lagging_setup_backbones()

func teardown() -> void:
	# Free all owned nodes. Called by simulation.gd teardown_simulation().
	_leading_teardown()
	_lagging_teardown()

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



	# ---- Enzyme positions: each polymerase sits on its own template strand's row ----
	if leading_polymerase and phase != helicase_mgr.Phase.DONE:
		leading_polymerase.position = Vector2(ctx.polymerase_x, ctx.new_top_template_y)
		if leading_clamp != null:
			var reached_first_slot = ctx.num_slots > 0 and ctx.polymerase_x >= sim.nucleotide_original_x[0]
			leading_clamp.set_pump(sin(helicase_mgr.step_t * PI) if reached_first_slot else 0.0)
	elif leading_clamp != null:
		leading_clamp.set_pump(0.0)
		#print("[DEBUG] leading_polymerase.position=", leading_polymerase.position, " template_strand_y=", ctx.template_strand_y, " dna_ribbons_gap=", ctx.dna_ribbons_gap, " global_pos=", leading_polymerase.global_position)

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
		if leading_clamp != null: leading_clamp.set_pump(0.0)
	if lagging_polymerase:
		lagging_polymerase_faded = ctx.is_done_phase
		lagging_polymerase.modulate.a = 0.0 if ctx.is_done_phase else 1.0
		if lagging_pump_tween != null and lagging_pump_tween.is_valid():
			lagging_pump_tween.kill()
		if lagging_clamp != null:
			lagging_clamp.set_pump(0.0)
		
		lagging_polymerase.position = Vector2(lagging_polymerase_x, ctx.new_bottom_template_y)

	_leading_scrub_rebuild(ctx)

# ==========================================
# ENZYME ANIMATION — called from simulation.gd toggle_play() / _run_intro()
# ==========================================

func resume_enzymes() -> void:
	leading_polymerase.modulate.a = 1.0
	if lagging_firing_started:
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
	_lagging_render(ctx)

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
	leading_polymerase.z_index = 10
	leading_clamp = PolymeraseClamp.new()
	leading_polymerase.add_child(leading_clamp)
	leading_clamp.setup(sim, true, Color(0.22, 0.42, 1.0), Color(0.45, 0.60, 1.0))
	leading_halo = PolymeraseHalo.new()
	leading_polymerase.add_child(leading_halo)
	leading_halo.setup(sim, true)
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
			var wobble_y = sim.get_wobble_y(i, wobble_t)
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
		var wobble_first = sim.get_wobble_y(0, wobble_t)
		var leading_y = new_top_template_y - dna_ribbons_gap + wobble_first
		marker_leading_5p = _spawn_marker("3'", Vector2(
			nucleotide_original_x[0] - tm.marker_offset,
			leading_y - tm.backbone_offset_distance
		))
	if marker_leading_5p:
		var wobble_first = sim.get_wobble_y(0, wobble_t)
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
			var wobble_last = sim.get_wobble_y(last_synth, wobble_t)
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
			var wobble_last = sim.get_wobble_y(last_synth, wobble_t)
			var leading_y = new_top_template_y - dna_ribbons_gap + wobble_last
			marker_leading_3p.position = Vector2(
				nucleotide_original_x[last_synth] + tm.marker_offset,
				leading_y - tm.backbone_offset_distance
			)

func _spawn_leading_base(index: int, base_type: String) -> Node2D:
	var base = sim.NewNitrogenBaseScene.instantiate()
	var world_x = sim.nucleotide_original_x[index]
	var leading_y = sim.new_top_template_y - sim.dna_ribbons_gap
	base.position = Vector2(world_x, leading_y)
	base.z_index = 2
	sim.add_child(base)
	base.set_base_type(base_type)
	base.set_radius(tm.base_radius)
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
	var inset = tm.base_radius - 3.0
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

func _lagging_reset(num_slots: int) -> void:
	lagging_fragments.clear()
	lagging_current_fragment = null
	lagging_telomere_gap = null
	lagging_synthesized_bases.clear()
	lagging_hydrogen_bonds.clear()
	for i in range(num_slots):
		lagging_synthesized_bases.append(null)
		lagging_hydrogen_bonds.append(null)
	lagging_total_fragments = num_slots / sim.okazaki_fragment_size
	lagging_firing_started = false
	lagging_total_consumed = 0
	lagging_batch_cursor = 0
	lagging_polymerase_x = 0.0
	if lagging_catchup_timer != null:
		lagging_catchup_timer.stop()
	if lagging_polymerase_tween != null and lagging_polymerase_tween.is_valid():
		lagging_polymerase_tween.kill()

func _lagging_setup_backbones() -> void:
	if lagging_backbone_line != null and is_instance_valid(lagging_backbone_line):
		lagging_backbone_line.queue_free()
	lagging_backbone_line = Line2D.new()
	lagging_backbone_line.default_color = tm.backbone_color
	lagging_backbone_line.width = tm.backbone_line_width
	lagging_backbone_line.z_index = -1
	lagging_backbone_line.joint_mode = Line2D.LINE_JOINT_ROUND
	lagging_backbone_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	lagging_backbone_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	sim.add_child(lagging_backbone_line)

func _lagging_teardown() -> void:
	for base in lagging_synthesized_bases:
		if base != null and is_instance_valid(base): base.queue_free()
	for bond in lagging_hydrogen_bonds:
		if bond != null and is_instance_valid(bond): bond.queue_free()
	lagging_synthesized_bases.clear()
	lagging_hydrogen_bonds.clear()

	var all_fragments = lagging_fragments.duplicate()
	if lagging_current_fragment != null:
		all_fragments.append(lagging_current_fragment)
	for frag in all_fragments:
		if frag.backbone != null and is_instance_valid(frag.backbone):
			frag.backbone.queue_free()
		for mark in frag.bond_marks:
			if mark != null and is_instance_valid(mark): mark.queue_free()
		if frag.marker_5p != null and is_instance_valid(frag.marker_5p):
			frag.marker_5p.queue_free()
		if frag.marker_3p != null and is_instance_valid(frag.marker_3p):
			frag.marker_3p.queue_free()

	if lagging_backbone_line != null and is_instance_valid(lagging_backbone_line):
		lagging_backbone_line.queue_free()
	for mark in lagging_bond_marks:
		if mark != null and is_instance_valid(mark): mark.queue_free()
	lagging_bond_marks.clear()

	lagging_fragments.clear()
	lagging_current_fragment = null

func _on_helicase_slot_reached(index: int) -> void:
	if lagging_total_consumed >= sim.num_nucleotide_slots:
		return

	if not lagging_firing_started:
		if index < sim.okazaki_fragment_size + sim.pll_slot_count:
			return
		lagging_firing_started = true
		if lagging_polymerase != null:
			lagging_polymerase.modulate.a = 1.0

	if lagging_current_fragment == null:
		_lagging_open_next_fragment()

	_lagging_fire_step(sim.helicase_mgr.step_duration)

func _lagging_fire_step(duration: float) -> void:
	var slot_index = lagging_batch_cursor
	lagging_current_fragment.slots.push_front(slot_index)  # push_front: firing goes right-to-left, so this keeps the array ascending
	if lagging_synthesized_bases[slot_index] == null:
		lagging_synthesized_bases[slot_index] = _spawn_lagging_base(slot_index, sim.dna_sequence.get_base(slot_index))
		lagging_hydrogen_bonds[slot_index] = _spawn_lagging_hydrogen_bonds(slot_index)

	lagging_polymerase_x = sim.nucleotide_original_x[slot_index]
	if lagging_polymerase:
		if lagging_polymerase_tween != null and lagging_polymerase_tween.is_valid():
			lagging_polymerase_tween.kill()
		lagging_polymerase_tween = sim.create_tween()
		lagging_polymerase_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		lagging_polymerase_tween.tween_property(lagging_polymerase, "position", Vector2(lagging_polymerase_x, sim.new_bottom_template_y), duration)

	print("[LAGGING] slot %d fired — fragment size %d/%d" % [
		slot_index, lagging_current_fragment.slots.size(), sim.okazaki_fragment_size
	])

	# Pump the lagging clamp 0->1->0 over the same duration, matching the
	# leading strand's sin(step_t*PI) shape — opens mid-move, clamps on arrival.
	# Same call site for live and catch-up firing, so both are covered.
	if lagging_clamp != null:
		if lagging_pump_tween != null and lagging_pump_tween.is_valid():
			lagging_pump_tween.kill()
		lagging_pump_tween = sim.create_tween()
		lagging_pump_tween.tween_method(_set_lagging_pump_phase, 0.0, 1.0, duration)

	lagging_total_consumed += 1
	lagging_batch_cursor -= 1

	if lagging_current_fragment.slots.size() >= sim.okazaki_fragment_size or lagging_total_consumed >= sim.num_nucleotide_slots:
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

func _lagging_open_next_fragment() -> void:
	_lagging_open_fragment()
	var remaining = sim.num_nucleotide_slots - lagging_total_consumed
	var this_fragment_size = min(sim.okazaki_fragment_size, remaining)
	lagging_batch_cursor = lagging_total_consumed + this_fragment_size - 1

func _lagging_close_fragment() -> void:
	lagging_current_fragment.complete = true
	lagging_fragments.append(lagging_current_fragment)
	print("[LAGGING] fragment closed — slots=%s" % [str(lagging_current_fragment.slots)])
	lagging_current_fragment = null

func _lagging_scrub_rebuild(ctx: Dictionary) -> void:
	var is_done_phase: bool = ctx.is_done_phase
	var num_slots: int = ctx.num_slots
	var nucleotide_original_x = ctx.nucleotide_original_x
	var threshold = sim.okazaki_fragment_size + sim.pll_slot_count

	var attempted_consumed = 0
	if is_done_phase:
		attempted_consumed = _lagging_natural_done_consumed(num_slots, nucleotide_original_x)
	else:
		var exposed_count = max(0, ctx.target_slot)
		if exposed_count >= threshold:
			attempted_consumed = exposed_count - threshold + 1
		attempted_consumed = clamp(attempted_consumed, 0, num_slots)

	var total_consumed = attempted_consumed
	if is_done_phase and sim.lagging_gap_enabled:
		total_consumed = (attempted_consumed / sim.okazaki_fragment_size) * sim.okazaki_fragment_size  # reserved — telomerase tier
	elif is_done_phase:
		# DONE alone doesn't finish lagging — it reaches the natural tiling
		# point, same as live play. Further completion comes from explicit
		# catch-up steps, supplied via ctx.lagging_catchup_step by
		# scrub_to_lagging_catchup() for arrow-key stepping. Defaults to 0
		# (natural state) for ordinary scrub_to() calls — slider-drag or the
		# exact boundary arrow-key step.
		var catchup_step = ctx.get("lagging_catchup_step", 0)
		total_consumed = clamp(attempted_consumed + catchup_step, attempted_consumed, num_slots)
	if is_done_phase and sim.lagging_gap_enabled:
		var last_slot = num_slots - 1
		var gap_start = (total_consumed / sim.okazaki_fragment_size) * sim.okazaki_fragment_size
		if last_slot >= gap_start:
			lagging_telomere_gap = { start = gap_start, end = last_slot, length = last_slot - gap_start + 1 }
		else:
			lagging_telomere_gap = null
	else:
		lagging_telomere_gap = null

	print("[LAGGING] DEBUG rebuild — is_done_phase=%s ctx.num_slots=%s attempted_consumed=%d catchup_step=%s total_consumed=%d" % [
		is_done_phase, ctx.num_slots, attempted_consumed, ctx.get("lagging_catchup_step", "n/a"), total_consumed
	])

	# ---- Free old visuals, rebuild from scratch ----
	var old_fragments = lagging_fragments.duplicate()
	if lagging_current_fragment != null:
		old_fragments.append(lagging_current_fragment)
	for frag in old_fragments:
		if frag.backbone != null and is_instance_valid(frag.backbone): frag.backbone.queue_free()
		for mark in frag.bond_marks:
			if mark != null and is_instance_valid(mark): mark.queue_free()
		if frag.marker_5p != null and is_instance_valid(frag.marker_5p): frag.marker_5p.queue_free()
		if frag.marker_3p != null and is_instance_valid(frag.marker_3p): frag.marker_3p.queue_free()
	lagging_fragments.clear()
	lagging_current_fragment = null

	for base in lagging_synthesized_bases:
		if base != null and is_instance_valid(base): base.queue_free()
	for bond in lagging_hydrogen_bonds:
		if bond != null and is_instance_valid(bond): bond.queue_free()
	lagging_synthesized_bases.clear()
	lagging_hydrogen_bonds.clear()
	lagging_synthesized_bases.resize(num_slots)
	lagging_hydrogen_bonds.resize(num_slots)

	# ---- Tile [0, total_consumed) into fragments ----
	# Every full-size tile is complete. If total_consumed reaches num_slots and
	# the final tile is short, that short tile is ALSO complete — it's the
	# catch-up mechanism's genuinely-short final fragment (left-anchored), not
	# a partial fill. Only when total_consumed stops mid-tile *before* reaching
	# num_slots is the trailing portion still open — firing sweeps right-to-left
	# within a tile, so only its rightmost `remainder` slots have fired so far.
	var full_tiles = total_consumed / sim.okazaki_fragment_size
	var remainder = total_consumed - full_tiles * sim.okazaki_fragment_size

	for k in range(full_tiles):
		var frag = { slots = range(k * sim.okazaki_fragment_size, (k + 1) * sim.okazaki_fragment_size),
			loop_queue = [], backbone = null, bond_marks = [], marker_5p = null, marker_3p = null, complete = true }
		lagging_fragments.append(frag)

	if remainder > 0:
		var tile_start = full_tiles * sim.okazaki_fragment_size
		var true_tile_end = min(tile_start + sim.okazaki_fragment_size, num_slots)
		var frag_slots = range(true_tile_end - remainder, true_tile_end)
		if total_consumed >= num_slots:
			var frag = { slots = frag_slots,
				loop_queue = [], backbone = null, bond_marks = [], marker_5p = null, marker_3p = null, complete = true }
			lagging_fragments.append(frag)
		else:
			lagging_current_fragment = { slots = frag_slots,
				loop_queue = [], backbone = null, bond_marks = [], marker_5p = null, marker_3p = null, complete = false }

	var slots_to_spawn: Array = []
	for frag in lagging_fragments:
		slots_to_spawn.append_array(frag.slots)
	if lagging_current_fragment != null:
		slots_to_spawn.append_array(lagging_current_fragment.slots)

	for i in slots_to_spawn:
		lagging_synthesized_bases[i] = _spawn_lagging_base(i, sim.dna_sequence.get_base(i))
		lagging_hydrogen_bonds[i] = _spawn_lagging_hydrogen_bonds(i)

	# ---- Polymerase position + visibility ----
	lagging_total_consumed = total_consumed
	lagging_firing_started = total_consumed > 0
	if total_consumed > 0:
		if lagging_current_fragment != null:
			lagging_polymerase_x = sim.nucleotide_original_x[lagging_current_fragment.slots[0]]
			lagging_batch_cursor = lagging_current_fragment.slots[0] - 1
		elif lagging_fragments.size() > 0:
			lagging_polymerase_x = sim.nucleotide_original_x[lagging_fragments[-1].slots[0]]
	else:
		lagging_polymerase_x = sim.nucleotide_original_x[0] - sim.polymerase_x_offset_slots * sim.nucleotide_slot_spacing

	print("[LAGGING] scrub rebuild — consumed=%d fragments=%d current=%s gap=%s" % [
		total_consumed, lagging_fragments.size(),
		str(lagging_current_fragment.slots) if lagging_current_fragment != null else "none",
		str(lagging_telomere_gap)
	])

func _on_helicase_phase_changed(new_phase: int) -> void:
	if new_phase == connected_helicase_mgr.Phase.DONE and not sim.manual_override:
		if sim.lagging_gap_enabled:
			_lagging_discard_incomplete_at_end()  # reserved — telomerase tier
		else:
			_lagging_start_catchup()

func _lagging_start_catchup() -> void:
	if lagging_polymerase_faded:
		return
	if lagging_total_consumed >= sim.num_nucleotide_slots:
		lagging_polymerase_faded = true
		_lagging_fade_enzyme_scene()
		return
	if lagging_catchup_timer == null:
		lagging_catchup_timer = Timer.new()
		lagging_catchup_timer.one_shot = false
		sim.add_child(lagging_catchup_timer)
		lagging_catchup_timer.timeout.connect(_lagging_catchup_tick)
	lagging_catchup_timer.wait_time = sim.lagging_catchup_step_duration
	lagging_catchup_timer.start()
	print("[LAGGING] catch-up started — %d slots remaining" % (sim.num_nucleotide_slots - lagging_total_consumed))

func _lagging_catchup_tick() -> void:
	if lagging_current_fragment == null:
		_lagging_open_next_fragment()
	_lagging_fire_step(sim.lagging_catchup_step_duration)
	if lagging_total_consumed >= sim.num_nucleotide_slots:
		lagging_catchup_timer.stop()
		lagging_polymerase_faded = true
		print("[LAGGING] catch-up complete — strand fully synthesized")
		_lagging_fade_enzyme_scene()

func _lagging_discard_incomplete_at_end() -> void:
	var settle_tween: Tween = null

	if lagging_current_fragment != null:
		var discarded_slots = lagging_current_fragment.slots.duplicate()
		print("[FADE] t=%d discard sequence starting — fade_duration=%.3f slots=%s" % [Time.get_ticks_msec(), sim.fade_duration, str(discarded_slots)])
		settle_tween = sim.create_tween()
		for slot_index in discarded_slots:
			if lagging_synthesized_bases[slot_index] != null:
				settle_tween.parallel().tween_property(lagging_synthesized_bases[slot_index], "modulate:a", 0.0, sim.fade_duration)
			if lagging_hydrogen_bonds[slot_index] != null:
				settle_tween.parallel().tween_property(lagging_hydrogen_bonds[slot_index], "modulate:a", 0.0, sim.fade_duration)
		settle_tween.chain().tween_callback(func():
			print("[FADE] t=%d discard-fade finished, freeing bases" % Time.get_ticks_msec())
			for slot_index in discarded_slots:
				if lagging_synthesized_bases[slot_index] != null and is_instance_valid(lagging_synthesized_bases[slot_index]):
					lagging_synthesized_bases[slot_index].queue_free()
					lagging_synthesized_bases[slot_index] = null
				if lagging_hydrogen_bonds[slot_index] != null and is_instance_valid(lagging_hydrogen_bonds[slot_index]):
					lagging_hydrogen_bonds[slot_index].queue_free()
					lagging_hydrogen_bonds[slot_index] = null
		)
		print("[LAGGING] incomplete trailing fragment fading out — slots=%s" % [str(discarded_slots)])
		lagging_current_fragment = null
	else:
		print("[FADE] t=%d discard sequence skipped — no open fragment" % Time.get_ticks_msec())

	var last_slot = sim.num_nucleotide_slots - 1
	var gap_start = lagging_fragments.size() * sim.okazaki_fragment_size
	if last_slot >= gap_start:
		lagging_telomere_gap = { start = gap_start, end = last_slot, length = last_slot - gap_start + 1 }
		print("[LAGGING] telomere gap recorded: slots %d-%d (length %d)" % [gap_start, last_slot, lagging_telomere_gap.length])
	else:
		lagging_telomere_gap = null
		print("[LAGGING] no telomere gap — every completable fragment finished exactly at the strand's end")

	if not lagging_polymerase_faded:
		lagging_polymerase_faded = true
		print("[FADE] t=%d scene fade gate reached — settle_tween=%s" % [Time.get_ticks_msec(), "chained" if settle_tween != null else "immediate"])
		if settle_tween != null:
			settle_tween.chain().tween_callback(func(): _lagging_fade_enzyme_scene())
		else:
			_lagging_fade_enzyme_scene()

func _lagging_fade_enzyme_scene() -> void:
	var fade_tween = sim.create_tween()
	if lagging_polymerase != null:
		fade_tween.tween_property(lagging_polymerase, "modulate:a", 0.0, sim.fade_duration)
	if leading_polymerase:
		fade_tween.parallel().tween_property(leading_polymerase, "modulate:a", 0.0, sim.fade_duration)
	if sim.helicase_node:
		fade_tween.parallel().tween_property(sim.helicase_node, "modulate:a", 0.0, sim.fade_duration)

func _spawn_lagging_base(index: int, base_type: String) -> Node2D:
	var base = sim.NewNitrogenBaseScene.instantiate()
	var world_x = sim.nucleotide_original_x[index]
	var lagging_y = sim.new_bottom_template_y + sim.dna_ribbons_gap
	base.position = Vector2(world_x, lagging_y)
	base.z_index = 2
	sim.add_child(base)
	base.set_base_type(base_type)
	base.set_radius(tm.base_radius)
	base.set_colors(sim._get_base_fill(base_type), tm.base_label_color)
	base.set_font(tm.base_label_font_size, tm.base_label_font)
	return base

func _spawn_lagging_hydrogen_bonds(index: int) -> Node2D:
	var template_base = sim.dna_sequence.get_complement(index)
	var bond_count = 3 if (template_base == "C" or template_base == "G") else 2
	var bond_color = tm.cg_bond_color if (template_base == "C" or template_base == "G") else tm.at_bond_color
	var container = Node2D.new()
	container.position = Vector2(sim.nucleotide_original_x[index], sim.new_bottom_template_y)
	var total_width = (bond_count - 1) * tm.hydrogen_bond_spacing
	var start_x = -total_width / 2.0
	var inset = tm.base_radius - 3.0
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

func _lagging_render(ctx: Dictionary) -> void:
	var wobble_t: float = ctx.wobble_t
	var dna_ribbons_gap: float = ctx.dna_ribbons_gap
	var new_bottom_template_y: float = ctx.new_bottom_template_y
	var nucleotide_original_x = ctx.nucleotide_original_x

	for i in range(lagging_synthesized_bases.size()):
		if lagging_synthesized_bases[i] != null:
			var wobble_y = sim.get_wobble_y(i, wobble_t)
			var world_x = nucleotide_original_x[i]
			var lagging_y = new_bottom_template_y + dna_ribbons_gap + wobble_y
			lagging_synthesized_bases[i].position = Vector2(world_x, lagging_y)
			if lagging_hydrogen_bonds[i] != null:
				var bottom_template_y = new_bottom_template_y + wobble_y
				lagging_hydrogen_bonds[i].position = Vector2(world_x, bottom_template_y)
				sim._update_hydrogen_bond_height(lagging_hydrogen_bonds[i], lagging_y - bottom_template_y)

	var all_fragments = lagging_fragments.duplicate()
	if lagging_current_fragment != null:
		all_fragments.append(lagging_current_fragment)

	if sim.ligase_enabled:
		for frag in all_fragments:
			_lagging_render_fragment_backbone(frag, wobble_t, dna_ribbons_gap, new_bottom_template_y, nucleotide_original_x)
		for frag in all_fragments:
			_lagging_render_fragment_markers(frag, wobble_t, dna_ribbons_gap, new_bottom_template_y, nucleotide_original_x)
		return

	# ---- Continuous mode (no ligase modeled): backbone spans only COMPLETE
	# fragments, merged into one line. A fragment still being built keeps its
	# own separate backbone until it completes and joins the continuous line.
	var continuous_points = PackedVector2Array()
	for frag in lagging_fragments:
		if frag.backbone != null and is_instance_valid(frag.backbone):
			frag.backbone.queue_free()
			frag.backbone = null
		for slot_index in frag.slots:
			if lagging_synthesized_bases[slot_index] != null:
				var wobble_y = sim.get_wobble_y(slot_index, wobble_t)
				var lagging_y = new_bottom_template_y + dna_ribbons_gap + wobble_y
				continuous_points.append(Vector2(nucleotide_original_x[slot_index], lagging_y + tm.backbone_offset_distance))

	lagging_backbone_line.points = continuous_points
	lagging_backbone_line.width = tm.backbone_line_width
	_update_bond_marks_lagging(continuous_points)

	if lagging_current_fragment != null:
		_lagging_render_fragment_backbone(lagging_current_fragment, wobble_t, dna_ribbons_gap, new_bottom_template_y, nucleotide_original_x)

	# Only the very first fragment's 5' and the current last-complete
	# fragment's 3' survive — an internal boundary stops being meaningful
	# once the backbone actually connects through it.
	for idx in range(lagging_fragments.size()):
		var frag = lagging_fragments[idx]
		var want_5p = (idx == 0)
		var want_3p = (idx == lagging_fragments.size() - 1)
		_lagging_set_fragment_markers(frag, want_5p, want_3p, wobble_t, dna_ribbons_gap, new_bottom_template_y, nucleotide_original_x)

func _lagging_set_fragment_markers(frag: Dictionary, want_5p: bool, want_3p: bool, wobble_t: float, dna_ribbons_gap: float, new_bottom_template_y: float, nucleotide_original_x: Array) -> void:
	if frag.slots.size() == 0:
		return
	var first_slot = frag.slots[0]
	var last_slot = frag.slots[-1]
	var first_y = new_bottom_template_y + dna_ribbons_gap + sim.get_wobble_y(first_slot, wobble_t) + tm.backbone_offset_distance
	var last_y = new_bottom_template_y + dna_ribbons_gap + sim.get_wobble_y(last_slot, wobble_t) + tm.backbone_offset_distance

	if want_5p and want_3p and frag.slots.size() == 1:
		if frag.marker_5p == null:
			frag.marker_5p = _spawn_marker("5'-3'", Vector2(nucleotide_original_x[first_slot], first_y + tm.marker_offset))
		frag.marker_5p.position = Vector2(nucleotide_original_x[first_slot], first_y + tm.marker_offset)
		if frag.marker_3p != null:
			frag.marker_3p.queue_free()
			frag.marker_3p = null
		return

	if want_5p:
		if frag.marker_5p == null:
			frag.marker_5p = _spawn_marker("5'", Vector2(nucleotide_original_x[first_slot], first_y + tm.marker_offset))
		frag.marker_5p.position = Vector2(nucleotide_original_x[first_slot], first_y + tm.marker_offset)
	elif frag.marker_5p != null:
		frag.marker_5p.queue_free()
		frag.marker_5p = null

	if want_3p:
		if frag.marker_3p == null:
			frag.marker_3p = _spawn_marker("3'", Vector2(nucleotide_original_x[last_slot], last_y + tm.marker_offset))
		frag.marker_3p.position = Vector2(nucleotide_original_x[last_slot], last_y + tm.marker_offset)
	elif frag.marker_3p != null:
		frag.marker_3p.queue_free()
		frag.marker_3p = null

func _lagging_render_fragment_backbone(frag: Dictionary, wobble_t: float, dna_ribbons_gap: float, new_bottom_template_y: float, nucleotide_original_x: Array) -> void:
	if frag.slots.size() == 0:
		return

	if frag.backbone == null:
		var line = Line2D.new()
		line.default_color = tm.backbone_color
		line.width = tm.backbone_line_width
		line.z_index = -1
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		sim.add_child(line)
		frag.backbone = line

	var points = PackedVector2Array()
	for slot_index in frag.slots:
		if lagging_synthesized_bases[slot_index] != null:
			var wobble_y = sim.get_wobble_y(slot_index, wobble_t)
			var world_x = nucleotide_original_x[slot_index]
			var lagging_y = new_bottom_template_y + dna_ribbons_gap + wobble_y
			points.append(Vector2(world_x, lagging_y + tm.backbone_offset_distance))
	frag.backbone.points = points
	frag.backbone.width = tm.backbone_line_width

	_update_bond_marks_fragment(frag, points)

func _update_bond_marks_fragment(frag: Dictionary, points: PackedVector2Array) -> void:
	var needed = max(0, points.size() - 1)
	while frag.bond_marks.size() < needed:
		frag.bond_marks.append(sim._create_bond_mark_sprite_reversed())
	while frag.bond_marks.size() > needed:
		var extra = frag.bond_marks.pop_back()
		extra.queue_free()
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

func _lagging_natural_done_consumed(num_slots: int, nucleotide_original_x: Array) -> int:
	# How many lagging slots would be consumed by pure position-based tiling
	# the instant the helicase reaches its own final position — before any
	# catch-up steps are applied. Shared by _lagging_scrub_rebuild() and
	# get_lagging_catchup_steps_needed() so both use the identical formula.
	var last_slot_index = num_slots - 1
	var offset_px = sim.polymerase_x_offset_slots * sim.nucleotide_slot_spacing
	var polymerase_x_at_last_slot = nucleotide_original_x[last_slot_index] - offset_px
	var remaining_leading = 0
	for i in range(num_slots):
		if nucleotide_original_x[i] > polymerase_x_at_last_slot:
			remaining_leading += 1
	var effective_index = last_slot_index + max(1, remaining_leading)

	var threshold = sim.okazaki_fragment_size + sim.pll_slot_count
	var exposed_count = max(0, effective_index)
	var attempted = 0
	if exposed_count >= threshold:
		attempted = exposed_count - threshold + 1
	return clamp(attempted, 0, num_slots)

## Public: how many extra arrow-key steps past the helicase's own last slot
## are needed for the lagging strand to fully catch up, at base complexity
## (lagging_gap_enabled = false). Used by simulation.gd to extend the
## scrubbable range for scrub_to_nucleotide_index().
func get_lagging_catchup_steps_needed(num_slots: int, nucleotide_original_x: Array) -> int:
	return num_slots - _lagging_natural_done_consumed(num_slots, nucleotide_original_x)

func _lagging_render_fragment_markers(frag: Dictionary, wobble_t: float, dna_ribbons_gap: float, new_bottom_template_y: float, nucleotide_original_x: Array) -> void:
	if frag.slots.size() == 0 or not frag.complete:
		return

	var first_slot = frag.slots[0]
	var last_slot = frag.slots[-1]
	var first_y = new_bottom_template_y + dna_ribbons_gap + sim.get_wobble_y(first_slot, wobble_t) + tm.backbone_offset_distance
	var last_y = new_bottom_template_y + dna_ribbons_gap + sim.get_wobble_y(last_slot, wobble_t) + tm.backbone_offset_distance

	if frag.slots.size() == 1:
		if frag.marker_5p == null:
			frag.marker_5p = _spawn_marker("5'-3'", Vector2(nucleotide_original_x[first_slot], first_y + tm.marker_offset))
		frag.marker_5p.position = Vector2(nucleotide_original_x[first_slot], first_y + tm.marker_offset)
	else:
		if frag.marker_5p == null:
			frag.marker_5p = _spawn_marker("5'", Vector2(nucleotide_original_x[first_slot], first_y + tm.marker_offset))
		frag.marker_5p.position = Vector2(nucleotide_original_x[first_slot], first_y + tm.marker_offset)
		if frag.marker_3p == null:
			frag.marker_3p = _spawn_marker("3'", Vector2(nucleotide_original_x[last_slot], last_y + tm.marker_offset))
		frag.marker_3p.position = Vector2(nucleotide_original_x[last_slot], last_y + tm.marker_offset)

func _update_bond_marks_lagging(points: PackedVector2Array) -> void:
	var needed = max(0, points.size() - 1)
	while lagging_bond_marks.size() < needed:
		lagging_bond_marks.append(sim._create_bond_mark_sprite_reversed())
	while lagging_bond_marks.size() > needed:
		var extra = lagging_bond_marks.pop_back()
		extra.queue_free()
	for i in range(needed):
		var a = points[i]
		var b = points[i + 1]
		var mid = (a + b) / 2.0
		var segment = b - a
		var mark = lagging_bond_marks[i]
		mark.position = mid
		mark.visible = segment.length() > 0.0
		if mark.visible:
			mark.rotation = segment.angle()

func _set_lagging_pump_phase(phase: float) -> void:
	if lagging_clamp != null:
		lagging_clamp.set_pump(sin(phase * PI))

# ==========================================
# SHARED SPAWNING HELPERS
# ==========================================

func _spawn_marker(marker_type: String, world_pos: Vector2) -> Node2D:
	var marker = sim.NewNitrogenBaseScene.instantiate()
	marker.position = world_pos
	marker.z_index = 3
	sim.add_child(marker)
	marker.set_base_type(marker_type)
	marker.set_radius(tm.base_radius)
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
