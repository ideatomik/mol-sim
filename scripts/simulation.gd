extends Node2D

# ==========================================
# v 70.3
# - Discrete helicase motion: helicase.gd owns slot stepping and phase
# - helicase_x is now a derived visual value (lerp between slots)
# - sweep_speed replaced by step_duration in helicase.gd
# - settle_blend driven by helicase.get_settling_blend()
# - simulation.gd reduced to template manager + visual coordinator
# ==========================================

# ---------- SIGNALS ----------
signal progress_changed(new_progress: float)  # 0.0 - 1.0
signal simulation_initialized(total_bases: int)

# ---------- EXPORTS ----------
@export var player_ui: Node  # Optional: drag your PlayerUI node here for direct access

const NewNitrogenBaseScene := preload("res://scenes/nitrogen_base.tscn")

@onready var background_rect: ColorRect = $CanvasLayer/ColorRect
@onready var rail_path: Path2D = $RailPath
@onready var template_strand_original_track: Line2D = $TemplateStrandOriginalTrack
@onready var new_strand_line: Line2D = $NewStrandLine
@onready var synthesis_circle: Node2D = $SynthesisCircle
@onready var synthesis_area: Area2D = $SynthesisCircle/SynthesisArea
@onready var template_strand_new_track: Line2D = $TemplateStrandNewTrack
@onready var backbone_line: Line2D = $BackboneLine
@onready var hydrogen_bonds_container: Node2D = $HydrogenBondsContainer
@onready var template_hydrogen_bonds_container: Node2D = $TemplateHydrogenBondsContainer
@onready var top_rail_path: Path2D = $TopRailPath
@onready var top_template_new_track: Line2D = $TopTemplateStrandNewTrack

# ---------- SUB-MANAGERS ----------
var helicase_mgr: Node = null  # helicase.gd instance, added as child in initialize_simulation

@export_group("Track Layout")
@export var nucleotide_slot_spacing: float = 54.0
@export var num_nucleotide_slots: int = 30  # Default length; can be overridden by sequence
@export var straight_y: float = 300.0
@export var nucleotide_slot_size: Vector2 = Vector2(24, 24)
var track_length: float = 0.0
@export var new_bottom_template_offset: float = 120.0
@export var dna_ribbons_gap: float = 90.0

@export_group("Loop Geometry")
@export var loop_floor_depth: float = 15.0
@export var max_loop_depth: float = 220.0
@export var gap_width: float = 168.0
@export var neck_depth_fraction: float = 0.15
@export var waist_flare_shallow: float = 0.45
@export var waist_flare_deep: float = 0.22
@export var armed_depth_fraction: float = 0.7

@export_group("Speeds & Timing")
@export var pulse_nucleotide_count: int = 6  # Slots per Okazaki fragment (boundary arithmetic only)
@export var fade_duration: float = 0.6
@export var settling_duration: float = 0.5
@export var settling_threshold: float = 2.0

@export_group("Wobble")
@export var wobble_amplitude: float = 2.0
@export var wobble_speed: float = 1.5
@export var wobble_phase_offset: float = 0.8

@export_group("Synthesis Circle")
@export var synthesis_circle_radius: float = 16.0
@export var synthesis_inside_threshold: float = 16.0
@export var synthesis_outside_threshold: float = 24.0

# ---------- STATE VARIABLES ----------
var new_bottom_template_y: float = 0.0
var new_top_template_y: float = 0.0
var new_synthesized_strand_y: float = 0.0
var new_strand_y: float = 0.0
var synthesis_circle_y: float = 0.0
var pulse_width: float = 0.0

var synthesis_circle_faded: bool = false
var top_polymerase: Node2D = null
var helicase_node: Node2D = null

var helicase_x: float = 0.0   # Derived each frame from helicase_mgr
var factory_x: float = 0.0   # Derived: helicase_x - gap_width

# Phase is now owned by helicase_mgr. Use helicase_mgr.get_phase() or
# helicase_mgr.Phase.* constants for phase checks.
# pulse_width is kept for Okazaki fragment boundary arithmetic.
var pulse_offset: float = 0.0  # Continuous loop animation value, driven visually

var population_left_edge: float = 0.0
var loop_depth: float = 0.0
var loop_length: float = 0.0
var settle_blend: float = 0.0

const LOOP_POPULATION_GROUP := "loop_population"
const UNZIPPED_POPULATION_GROUP := "unzipped_population"

# ---------- DYNAMIC ARRAYS (rebuilt on initialize) ----------
var template_strand_bottom: Array[PathFollow2D] = []
var nucleotide_bases: Array = []
var nucleotide_original_x: Array[float] = []

enum NucleotideTransferState { WAITING, ARMED, TRANSFERRED }
var nucleotide_transfer_state: Array[NucleotideTransferState] = []
var nucleotide_max_y_reached: Array[float] = []
var nucleotide_previous_y: Array[float] = []
var nucleotide_crossing_count: Array[int] = []
var nucleotide_previous_x: Array[float] = []
var nucleotide_entered_push_direction: Array[bool] = []

enum ProximityState { OUTSIDE, INSIDE }
var nucleotide_proximity_state: Array[ProximityState] = []

enum SynthesisCrossState { NONE, COMPLETED }
var nucleotide_synthesis_state: Array[SynthesisCrossState] = []

var nucleotide_backbone_delta: Array[float] = []

var baseline_switched: bool = false
var baseline_switch_nucleotide_index: int = -1
var settling_loop_depth_start: float = 0.0

var bond_marks: Array[Node2D] = []
var new_strand_backbone_line: Line2D
var new_strand_backbone_delta: Array[float] = []

var top_strand_slots: Array[PathFollow2D] = []
var top_strand_bases: Array = []
var top_strand_backbone_delta: Array[float] = []
var top_strand_bond_marks: Array[Node2D] = []
var top_strand_backbone_line: Line2D
var template_hydrogen_bonds: Array = []

var marker_template_5p: Node2D = null
var marker_template_3p: Node2D = null
var marker_new_5p: Node2D = null
var marker_new_3p: Node2D = null
var marker_top_5p: Node2D = null
var marker_top_3p: Node2D = null
var marker_leading_5p: Node2D = null
var marker_leading_3p: Node2D = null

# ---------- SINGLE SOURCE OF TRUTH ----------
var dna_sequence := DnaSequenceResource.new()

# ---------- SCRUBBER / PLAYBACK CONTROL ----------
var manual_override: bool = false  # When true, state doesn't auto-advance in _process

# ---------- SYNTHESIZED DATA (Lagging Strand) ----------
var synthesized_bases: Array = []
var hydrogen_bonds: Array = []

# ---------- SYNTHESIZED DATA (Leading Strand) ----------
var leading_synthesized_bases: Array = []   # Node2D references for leading strand bases
var leading_hydrogen_bonds: Array = []      # Node2D containers for leading H-bonds
var leading_backbone_line: Line2D           # Backbone for the leading strand
var leading_strand_bond_marks: Array[Node2D] = []  # Bond marks for leading backbone

# ---------- OKAZAKI FRAGMENTS (Lagging Strand) ----------
# Each entry: { slots: Array[int], backbone: Line2D, bond_marks: Array[Node2D],
#               marker_5p: Node2D, marker_3p: Node2D, complete: bool }
var okazaki_fragments: Array = []
var current_fragment_index: int = -1  # Index into okazaki_fragments of the active fragment
var last_synthesis_pulse_cycle: int = -1  # Pulse cycle number when last base was synthesized

# ==========================================
# LIFECYCLE
# ==========================================

func _ready():
	# Generate a random sequence as the default
	dna_sequence.randomize_sequence(num_nucleotide_slots)
	initialize_simulation(dna_sequence._to_string())

func initialize_simulation(sequence: String):
	# Validate and clean the sequence
	sequence = dna_sequence.clean_sequence(sequence)
	if sequence.length() > 57:
		sequence = sequence.substr(0, 57)
		print("[WARN] Sequence truncated to 57 bases")

	# 1. TEARDOWN old simulation
	teardown_simulation()

	# 2. LOAD the sequence into the resource
	dna_sequence.set_from_string(sequence)

	# 3. Update parameters from the resource
	num_nucleotide_slots = dna_sequence.get_length()
	track_length = (num_nucleotide_slots - 1) * nucleotide_slot_spacing + 2.0 * gap_width
	pulse_width = pulse_nucleotide_count * nucleotide_slot_spacing  # For Okazaki boundary arithmetic

	# 4. RESET all state variables
	helicase_x = gap_width
	factory_x = 0.0
	loop_depth = max_loop_depth
	pulse_offset = 0.0
	baseline_switched = false
	settle_blend = 0.0
	manual_override = true  # Start paused when a new sequence loads
	synthesis_circle_faded = false
	last_synthesis_pulse_cycle = -1

	# 4b. Create or re-initialize helicase manager
	if helicase_mgr != null:
		helicase_mgr.queue_free()
	var HelicastScript = load("res://scripts/helicase.gd")
	helicase_mgr = HelicastScript.new()
	add_child(helicase_mgr)
	helicase_mgr.initialize(num_nucleotide_slots, settling_duration)
	helicase_mgr.slot_reached.connect(_on_helicase_slot_reached)
	helicase_mgr.phase_changed.connect(_on_helicase_phase_changed)

	new_bottom_template_y = straight_y + new_bottom_template_offset
	new_top_template_y = straight_y - dna_ribbons_gap - new_bottom_template_offset
	new_synthesized_strand_y = new_bottom_template_y + new_bottom_template_offset
	new_strand_y = straight_y + max_loop_depth + nucleotide_slot_size.y
	synthesis_circle_y = straight_y + max_loop_depth

	# 5. REBUILD all visual elements
	_rebuild_rail()
	_spawn_nucleotide_slots()
	_setup_synthesis_circle()
	_setup_top_polymerase()
	_setup_helicase()

	# All enzymes start invisible; they fade in on first play.
	synthesis_circle.modulate.a = 0.0
	if top_polymerase:
		top_polymerase.modulate.a = 0.0
	if helicase_node:
		helicase_node.modulate.a = 0.0

	template_strand_original_track.visible = true
	template_strand_new_track.points = PackedVector2Array([
		Vector2(0, new_bottom_template_y),
		Vector2(track_length, new_bottom_template_y)
	])
	template_strand_new_track.visible = true

	backbone_line.default_color = %ThemeManager.backbone_color
	backbone_line.width = %ThemeManager.backbone_line_width
	backbone_line.z_index = -1
	backbone_line.joint_mode = Line2D.LINE_JOINT_ROUND
	backbone_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	backbone_line.end_cap_mode = Line2D.LINE_CAP_ROUND

	new_strand_backbone_line = Line2D.new()
	new_strand_backbone_line.default_color = %ThemeManager.backbone_color
	new_strand_backbone_line.width = %ThemeManager.backbone_line_width
	new_strand_backbone_line.z_index = -1
	new_strand_backbone_line.joint_mode = Line2D.LINE_JOINT_ROUND
	new_strand_backbone_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	new_strand_backbone_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(new_strand_backbone_line)

	top_strand_backbone_line = Line2D.new()
	top_strand_backbone_line.default_color = %ThemeManager.backbone_color
	top_strand_backbone_line.width = %ThemeManager.backbone_line_width
	top_strand_backbone_line.z_index = -1
	top_strand_backbone_line.joint_mode = Line2D.LINE_JOINT_ROUND
	top_strand_backbone_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	top_strand_backbone_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(top_strand_backbone_line)

	# ---- Leading strand backbone (above top template) ----
	leading_backbone_line = Line2D.new()
	leading_backbone_line.default_color = %ThemeManager.backbone_color
	leading_backbone_line.width = %ThemeManager.backbone_line_width
	leading_backbone_line.z_index = -1
	leading_backbone_line.joint_mode = Line2D.LINE_JOINT_ROUND
	leading_backbone_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	leading_backbone_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(leading_backbone_line)

	top_template_new_track.visible = false

	_spawn_top_strand()
	_rebuild_top_rail()
	for i in range(top_strand_slots.size()):
		top_strand_slots[i].progress = track_length - nucleotide_original_x[i]
	_spawn_leading_arrays()  # Initialize arrays for leading strand

	# Strand end markers
	var first_x = nucleotide_original_x[0]
	var last_x = nucleotide_original_x[num_nucleotide_slots - 1]
	marker_template_5p = _spawn_marker("5'", Vector2(last_x + %ThemeManager.marker_offset, straight_y))
	marker_template_3p = _spawn_marker("3'", Vector2(first_x - %ThemeManager.marker_offset, straight_y))
	marker_top_5p = _spawn_marker("5'", Vector2(first_x - %ThemeManager.marker_offset, straight_y - dna_ribbons_gap))
	marker_top_3p = _spawn_marker("3'", Vector2(last_x + %ThemeManager.marker_offset, straight_y - dna_ribbons_gap))
	marker_new_5p = null
	marker_new_3p = null

	# 6. Emit signal so UI can update its slider max_value and reset
	simulation_initialized.emit(num_nucleotide_slots)

	# Force an immediate visual update
	queue_redraw()
	print("[INIT] Simulation initialized with %d bases: %s" % [num_nucleotide_slots, dna_sequence._to_string()])

func teardown_simulation():
	# Clear all dynamic nodes
	var nodes_to_free: Array[Node] = []

	# Collect everything
	nodes_to_free.append_array(template_strand_bottom)
	nodes_to_free.append_array(nucleotide_bases)
	nodes_to_free.append_array(synthesized_bases)
	nodes_to_free.append_array(leading_synthesized_bases)
	nodes_to_free.append_array(top_strand_slots)
	nodes_to_free.append_array(top_strand_bases)
	nodes_to_free.append_array(hydrogen_bonds)
	nodes_to_free.append_array(leading_hydrogen_bonds)
	nodes_to_free.append_array(template_hydrogen_bonds)
	nodes_to_free.append_array(bond_marks)
	nodes_to_free.append_array(top_strand_bond_marks)
	nodes_to_free.append_array(leading_strand_bond_marks)

	if new_strand_backbone_line:
		nodes_to_free.append(new_strand_backbone_line)
	if top_strand_backbone_line:
		nodes_to_free.append(top_strand_backbone_line)
	if leading_backbone_line:
		nodes_to_free.append(leading_backbone_line)
	if marker_template_5p:
		nodes_to_free.append(marker_template_5p)
	if marker_template_3p:
		nodes_to_free.append(marker_template_3p)
	if marker_new_5p:
		nodes_to_free.append(marker_new_5p)
	if marker_new_3p:
		nodes_to_free.append(marker_new_3p)
	if marker_top_5p:
		nodes_to_free.append(marker_top_5p)
	if marker_top_3p:
		nodes_to_free.append(marker_top_3p)
	if top_polymerase:
		nodes_to_free.append(top_polymerase)
	if helicase_node:
		nodes_to_free.append(helicase_node)
	if marker_leading_5p:
		nodes_to_free.append(marker_leading_5p)
	if marker_leading_3p:
		nodes_to_free.append(marker_leading_3p)

	for node in nodes_to_free:
		if is_instance_valid(node) and node != null:
			node.queue_free()

	# Free Okazaki fragment nodes
	for frag in okazaki_fragments:
		if frag.has("backbone") and is_instance_valid(frag.backbone):
			frag.backbone.queue_free()
		for mark in frag.bond_marks:
			if is_instance_valid(mark): mark.queue_free()
		if frag.has("marker_5p") and frag.marker_5p and is_instance_valid(frag.marker_5p):
			frag.marker_5p.queue_free()
		if frag.has("marker_3p") and frag.marker_3p and is_instance_valid(frag.marker_3p):
			frag.marker_3p.queue_free()
	okazaki_fragments.clear()
	current_fragment_index = -1

	last_synthesis_pulse_cycle = -1
	# Clear arrays
	template_strand_bottom.clear()
	nucleotide_bases.clear()
	nucleotide_original_x.clear()
	nucleotide_transfer_state.clear()
	nucleotide_max_y_reached.clear()
	nucleotide_previous_y.clear()
	nucleotide_crossing_count.clear()
	nucleotide_previous_x.clear()
	nucleotide_entered_push_direction.clear()
	nucleotide_proximity_state.clear()
	nucleotide_synthesis_state.clear()
	nucleotide_backbone_delta.clear()
	synthesized_bases.clear()
	hydrogen_bonds.clear()
	leading_synthesized_bases.clear()
	leading_hydrogen_bonds.clear()
	new_strand_backbone_delta.clear()
	top_strand_slots.clear()
	top_strand_bases.clear()
	top_strand_backbone_delta.clear()
	top_strand_bond_marks.clear()
	template_hydrogen_bonds.clear()
	bond_marks.clear()
	leading_strand_bond_marks.clear()
	marker_leading_5p = null
	marker_leading_3p = null
	helicase_mgr = null  # Re-created in initialize_simulation

	# Reset line points so they don't linger
	if backbone_line:
		backbone_line.points = PackedVector2Array()
	if new_strand_backbone_line:
		new_strand_backbone_line.points = PackedVector2Array()
	if top_strand_backbone_line:
		top_strand_backbone_line.points = PackedVector2Array()
	if leading_backbone_line:
		leading_backbone_line.points = PackedVector2Array()

	# Clear the rail paths
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
	# ---------- 1. DERIVE VISUAL HELICASE POSITION ----------
	# helicase_x is computed from helicase_mgr's discrete slot index and eased step_t.
	# This is the only place helicase_x and factory_x are written.
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
		factory_x = helicase_x - gap_width
		settle_blend = helicase_mgr.get_settling_blend()

		# Trombone loop: pulse_offset animates continuously based on slot progress.
		# Each full slot step = one full pulse cycle.
		var slot_frac = fmod(float(idx) + eased, 2.0) / 2.0
		if slot_frac < 0.5:
			pulse_offset = slot_frac * 2.0 * nucleotide_slot_spacing
		else:
			pulse_offset = (1.0 - (slot_frac - 0.5) * 2.0) * nucleotide_slot_spacing
		var pulse_ratio = pulse_offset / nucleotide_slot_spacing

		var phase = helicase_mgr.get_phase()
		if phase == helicase_mgr.Phase.DONE:
			loop_depth = 0.0
			settle_blend = 1.0
		elif phase == helicase_mgr.Phase.SETTLING:
			loop_depth = lerp(settling_loop_depth_start, 0.0, settle_blend)
		else:
			loop_depth = lerp(loop_floor_depth, max_loop_depth, pulse_ratio)

		population_left_edge = factory_x - pulse_offset

	# ---------- 2. STATE UPDATE (only if not manually overridden) ----------
	if not manual_override and helicase_mgr != null:
		var phase = helicase_mgr.get_phase()

		# FINISHING_LAST_PULSE: sweep remaining lagging slots, then hand off to
		# helicase_mgr to step through remaining leading slots naturally.
		# Guard: extra_steps_total == 0 means start_finishing hasn't been called yet.
		if phase == helicase_mgr.Phase.FINISHING_LAST_PULSE and helicase_mgr.extra_steps_total == 0:
			# Catch any lagging slots still in the loop
			for j in range(num_nucleotide_slots):
				if nucleotide_synthesis_state[j] == SynthesisCrossState.NONE:
					nucleotide_synthesis_state[j] = SynthesisCrossState.COMPLETED
					synthesized_bases[j] = _spawn_complement_base(j)
					hydrogen_bonds[j] = _spawn_hydrogen_bonds(j)
					_assign_to_okazaki_fragment(j)
					print("[t=%s] nucleotide_slot[%d] COMPLETED via end-of-run sweep" % [Time.get_ticks_msec(), j])
			# Close the last open Okazaki fragment
			if current_fragment_index >= 0 and not okazaki_fragments[current_fragment_index].complete:
				_close_okazaki_fragment(current_fragment_index)
			settling_loop_depth_start = loop_depth
			# Count leading slots still ahead of factory_x — helicase steps through
			# exactly this many more times so they spawn one by one, not all at once
			var remaining_leading = 0
			for i in range(num_nucleotide_slots):
				if nucleotide_original_x[i] > factory_x:
					remaining_leading += 1
			helicase_mgr.start_finishing(remaining_leading)

		# DONE: fade enzymes, spawn final markers
		if phase == helicase_mgr.Phase.DONE and not synthesis_circle_faded:
			synthesis_circle_faded = true
			var fade_tween = create_tween()
			fade_tween.tween_property(synthesis_circle, "modulate:a", 0.0, fade_duration)
			if top_polymerase:
				fade_tween.parallel().tween_property(top_polymerase, "modulate:a", 0.0, fade_duration)
			if helicase_node:
				fade_tween.parallel().tween_property(helicase_node, "modulate:a", 0.0, fade_duration)
			var last = num_nucleotide_slots - 1
			var wobble_last = nucleotide_bases[last].position.y
			marker_new_3p = _spawn_marker("3'", Vector2(
				nucleotide_original_x[last] + %ThemeManager.marker_offset,
				new_bottom_template_y + dna_ribbons_gap + wobble_last + new_strand_backbone_delta[last]
			))
			marker_new_3p.modulate.a = 0.0  # Hidden until ligase joins fragments

		# ---- Enzyme positions ----
		synthesis_circle.position = Vector2(factory_x, new_bottom_template_y)
		if top_polymerase:
			top_polymerase.position = Vector2(factory_x, straight_y - dna_ribbons_gap - new_bottom_template_offset)
		if helicase_node:
			helicase_node.position = Vector2(helicase_x, straight_y - dna_ribbons_gap / 2.0)

		if phase != helicase_mgr.Phase.DONE:
			for i in range(template_strand_bottom.size()):
				template_strand_bottom[i].progress = track_length - nucleotide_original_x[i]

		# ---- Lagging strand: trombone + proximity synthesis ----
		# (Synthesis firing now also happens in _on_helicase_slot_reached,
		#  but proximity/transfer state tracking still runs here.)
		for i in range(template_strand_bottom.size()):
			var nucleotide_y = template_strand_bottom[i].position.y
			if nucleotide_y > nucleotide_max_y_reached[i]:
				nucleotide_max_y_reached[i] = nucleotide_y

			if not baseline_switched and nucleotide_y >= new_bottom_template_y:
				baseline_switched = true
				baseline_switch_nucleotide_index = i
				print(">>> BASELINE SWITCH TRIGGERED by nucleotide_slot[%d] at y=%.1f" % [i, nucleotide_y])

			match nucleotide_transfer_state[i]:
				NucleotideTransferState.WAITING:
					if nucleotide_max_y_reached[i] >= straight_y + max_loop_depth * armed_depth_fraction:
						nucleotide_transfer_state[i] = NucleotideTransferState.ARMED
				NucleotideTransferState.ARMED:
					if nucleotide_y < new_bottom_template_y:
						nucleotide_transfer_state[i] = NucleotideTransferState.TRANSFERRED
				NucleotideTransferState.TRANSFERRED:
					pass

			if nucleotide_synthesis_state[i] == SynthesisCrossState.COMPLETED:
				continue

			var current_x = template_strand_bottom[i].position.x
			var distance_to_polymerase = template_strand_bottom[i].position.distance_to(synthesis_circle.position)
			match nucleotide_proximity_state[i]:
				ProximityState.OUTSIDE:
					if distance_to_polymerase < synthesis_inside_threshold:
						nucleotide_proximity_state[i] = ProximityState.INSIDE
						var moving_left = current_x < nucleotide_previous_x[i]
						nucleotide_entered_push_direction[i] = moving_left
				ProximityState.INSIDE:
					if distance_to_polymerase > synthesis_outside_threshold:
						nucleotide_proximity_state[i] = ProximityState.OUTSIDE
						nucleotide_crossing_count[i] += 1
						if nucleotide_entered_push_direction[i] and nucleotide_synthesis_state[i] == SynthesisCrossState.NONE:
							nucleotide_synthesis_state[i] = SynthesisCrossState.COMPLETED
							synthesized_bases[i] = _spawn_complement_base(i)
							hydrogen_bonds[i] = _spawn_hydrogen_bonds(i)
							_assign_to_okazaki_fragment(i)

			nucleotide_previous_x[i] = current_x

		for i in range(template_strand_bottom.size()):
			var nucleotide_slot = template_strand_bottom[i]
			var x = nucleotide_original_x[i]
			var in_loop = (phase != helicase_mgr.Phase.DONE) and x >= population_left_edge and x <= helicase_x
			if in_loop and not nucleotide_slot.is_in_group(LOOP_POPULATION_GROUP):
				nucleotide_slot.add_to_group(LOOP_POPULATION_GROUP)
			elif not in_loop and nucleotide_slot.is_in_group(LOOP_POPULATION_GROUP):
				nucleotide_slot.remove_from_group(LOOP_POPULATION_GROUP)

		# ---- Leading strand synthesis ----
		var leading_synth_count = 0
		for i in range(num_nucleotide_slots):
			if nucleotide_original_x[i] <= factory_x:
				leading_synth_count += 1
			else:
				break
		for i in range(leading_synth_count):
			if leading_synthesized_bases[i] == null:
				var bottom_base = dna_sequence.get_complement(i)
				leading_synthesized_bases[i] = _spawn_leading_base(i, bottom_base)
				leading_hydrogen_bonds[i] = _spawn_leading_hydrogen_bonds(i)

		# Emit progress for the UI
		progress_changed.emit(get_total_progress())

	# ---------- 3. VISUAL RENDERING (Always runs, even when paused) ----------
	_rebuild_rail()
	_rebuild_top_rail()

	var is_done = helicase_mgr != null and helicase_mgr.get_phase() == helicase_mgr.Phase.DONE
	var wobble_t = helicase_x / nucleotide_slot_spacing  # Continuous wobble driver



	# ---- Backbone for bottom template (existing) ----
	var backbone_points = PackedVector2Array()
	for i in range(template_strand_bottom.size()):
		var nucleotide_slot = template_strand_bottom[i]
		var slot_y = nucleotide_slot.position.y
		var wobble_y = 0.0
		if wobble_amplitude > 0.0:
			var near_top = abs(slot_y - straight_y) < wobble_amplitude * 4.0
			var near_bottom = abs(slot_y - new_bottom_template_y) < wobble_amplitude * 4.0
			if near_top or near_bottom:
				wobble_y = sin(wobble_t * wobble_speed * TAU + i * wobble_phase_offset) * wobble_amplitude
		nucleotide_bases[i].position.y = wobble_y

		var on_rail_visual = abs(slot_y - straight_y) < 1.0
		var on_new_bottom = abs(slot_y - new_bottom_template_y) < 1.0
		var target_delta: float
		if on_rail_visual:
			target_delta = %ThemeManager.backbone_offset_distance
		elif on_new_bottom:
			target_delta = -%ThemeManager.backbone_offset_distance
		else:
			target_delta = %ThemeManager.backbone_offset_distance

		nucleotide_backbone_delta[i] = lerp(nucleotide_backbone_delta[i], target_delta, clamp(%ThemeManager.backbone_offset_smoothing_speed * delta, 0.0, 1.0))
		backbone_points.append(Vector2(nucleotide_slot.position.x, slot_y + nucleotide_backbone_delta[i] + wobble_y))

	backbone_line.points = backbone_points
	backbone_line.width = %ThemeManager.backbone_line_width

	# ---- Lagging strand: Okazaki fragments ----
	# new_strand_backbone_line is kept empty here; ligase will populate it later.
	new_strand_backbone_line.points = PackedVector2Array()

	var y_off = %ThemeManager.okazaki_marker_y_offset

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
				_update_hydrogen_bond_height(hydrogen_bonds[i], world_y - container_y)
			new_strand_backbone_delta[i] = lerp(
				new_strand_backbone_delta[i],
				%ThemeManager.backbone_offset_distance,
				clamp(%ThemeManager.backbone_offset_smoothing_speed * delta, 0.0, 1.0)
			)
			frag_points.append(Vector2(world_x, world_y + new_strand_backbone_delta[i]))

		frag.backbone.points = frag_points
		frag.backbone.width = %ThemeManager.backbone_line_width
		_update_bond_marks_fragment(frag, frag_points)

		# Spawn markers once fragment is complete and has at least 1 point.
		# Single-slot: combined "5'-3'" centered marker.
		# Multi-slot: 5' on left (origin/index 0), 3' on right (tip/last index).
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

		# Update marker positions every frame (trombone + scrub tracking).
		# For single-slot, marker_5p holds the combined "5'-3'" marker at tip_pt.
		# For multi-slot, marker_5p is at origin (left), marker_3p is at tip (right).
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

	_update_bond_marks(backbone_points)

	# ---- Top template strand ----
	var top_strand_points = PackedVector2Array()
	var top_curve = top_rail_path.curve
	for i in range(top_strand_slots.size()):
		var world_x = nucleotide_original_x[i]
		var slot_y: float
		if top_curve != null:
			var baked = top_curve.get_baked_points()
			slot_y = _sample_curve_y_at_x(baked, world_x, straight_y - dna_ribbons_gap)
		else:
			slot_y = straight_y - dna_ribbons_gap
		top_strand_slots[i].position = Vector2(world_x, slot_y)

		var wobble_y = sin(wobble_t * wobble_speed * TAU + i * wobble_phase_offset) * wobble_amplitude
		top_strand_bases[i].position = Vector2(0, wobble_y)

		var mid_y = new_top_template_y + (straight_y - dna_ribbons_gap - new_top_template_y) * 0.5
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
	top_strand_backbone_line.points = top_strand_points
	top_strand_backbone_line.width = %ThemeManager.backbone_line_width
	_update_bond_marks_top_strand(top_strand_points)

	# ---- Leading strand (new) ----
	var leading_points = PackedVector2Array()
	for i in range(leading_synthesized_bases.size()):
		if leading_synthesized_bases[i] != null:
			var wobble_y = sin(wobble_t * wobble_speed * TAU + i * wobble_phase_offset) * wobble_amplitude
			var world_x = top_strand_slots[i].position.x if top_strand_slots.size() > i else nucleotide_original_x[i]
			var leading_y = straight_y - dna_ribbons_gap - new_bottom_template_offset - dna_ribbons_gap + wobble_y
			leading_synthesized_bases[i].position = Vector2(world_x, leading_y)
			if leading_hydrogen_bonds[i] != null:
				var top_template_y = straight_y - dna_ribbons_gap - new_bottom_template_offset + wobble_y
				leading_hydrogen_bonds[i].position = Vector2(world_x, top_template_y)
				_update_hydrogen_bond_height(leading_hydrogen_bonds[i], leading_y - top_template_y)
			# Backbone offset: on the opposite side (above the base)
			leading_points.append(Vector2(world_x, leading_y - %ThemeManager.backbone_offset_distance))
	leading_backbone_line.points = leading_points
	leading_backbone_line.width = %ThemeManager.backbone_line_width
	_update_bond_marks_leading(leading_points)

	# ---- Marker positions (existing + leading markers) ----
	if marker_template_5p:
		var last = num_nucleotide_slots - 1
		var wobble_last = nucleotide_bases[last].position.y
		marker_template_5p.position = Vector2(
			template_strand_bottom[last].position.x + %ThemeManager.marker_offset,
			template_strand_bottom[last].position.y + nucleotide_backbone_delta[last] + wobble_last
		)
	if marker_template_3p:
		var wobble_first = nucleotide_bases[0].position.y
		marker_template_3p.position = Vector2(
			template_strand_bottom[0].position.x - %ThemeManager.marker_offset,
			template_strand_bottom[0].position.y + nucleotide_backbone_delta[0] + wobble_first
		)
	if marker_new_5p == null and synthesized_bases[0] != null:
		var wobble_first = nucleotide_bases[0].position.y
		marker_new_5p = _spawn_marker("5'", Vector2(
			template_strand_bottom[0].position.x - %ThemeManager.marker_offset,
			new_bottom_template_y + dna_ribbons_gap + wobble_first + new_strand_backbone_delta[0]
		))
		marker_new_5p.modulate.a = 0.0  # Hidden until ligase joins fragments
	if marker_new_5p:
		var wobble_first = nucleotide_bases[0].position.y
		marker_new_5p.position = Vector2(
			template_strand_bottom[0].position.x - %ThemeManager.marker_offset,
			new_bottom_template_y + dna_ribbons_gap + wobble_first + new_strand_backbone_delta[0]
		)
	if marker_new_3p:
		var last = num_nucleotide_slots - 1
		var wobble_last = nucleotide_bases[last].position.y
		marker_new_3p.position = Vector2(
			nucleotide_original_x[last] + %ThemeManager.marker_offset,
			new_bottom_template_y + dna_ribbons_gap + wobble_last + new_strand_backbone_delta[last]
		)
	if marker_top_5p:
		var wobble_first = sin(wobble_t * wobble_speed * TAU + 0 * wobble_phase_offset) * wobble_amplitude
		marker_top_5p.position = Vector2(
			top_strand_slots[0].position.x - %ThemeManager.marker_offset,
			top_strand_slots[0].position.y + top_strand_backbone_delta[0] + wobble_first
		)
	if marker_top_3p:
		var last = num_nucleotide_slots - 1
		var wobble_last = sin(wobble_t * wobble_speed * TAU + last * wobble_phase_offset) * wobble_amplitude
		marker_top_3p.position = Vector2(
			top_strand_slots[last].position.x + %ThemeManager.marker_offset,
			top_strand_slots[last].position.y + top_strand_backbone_delta[last] + wobble_last
		)
		# ---- Leading strand markers ----
	# 5' marker: appears when the first leading base is synthesized
	if marker_leading_5p == null and leading_synthesized_bases[0] != null:
		var wobble_first = sin(wobble_t * wobble_speed * TAU + 0 * wobble_phase_offset) * wobble_amplitude
		var leading_y = straight_y - dna_ribbons_gap - new_bottom_template_offset - dna_ribbons_gap + wobble_first
		marker_leading_5p = _spawn_marker("3'", Vector2(
			nucleotide_original_x[0] - %ThemeManager.marker_offset,
			leading_y - %ThemeManager.backbone_offset_distance
		))

	# Update 5' marker position (follows wobble)
	if marker_leading_5p:
		var wobble_first = sin(wobble_t * wobble_speed * TAU + 0 * wobble_phase_offset) * wobble_amplitude
		var leading_y = straight_y - dna_ribbons_gap - new_bottom_template_offset - dna_ribbons_gap + wobble_first
		marker_leading_5p.position = Vector2(
			nucleotide_original_x[0] - %ThemeManager.marker_offset,
			leading_y - %ThemeManager.backbone_offset_distance
		)

	# 3' marker: appears at the rightmost synthesized base
	# For the leading strand, the 3' end is at the growing tip (rightmost synthesized base)
	# We'll show it when at least one base is synthesized
	if marker_leading_3p == null and leading_synthesized_bases[0] != null:
		# Find the rightmost synthesized base
		var last_synth_index = -1
		for i in range(leading_synthesized_bases.size()):
			if leading_synthesized_bases[i] != null:
				last_synth_index = i
		if last_synth_index >= 0:
			var wobble_last = sin(wobble_t * wobble_speed * TAU + last_synth_index * wobble_phase_offset) * wobble_amplitude
			var leading_y = straight_y - dna_ribbons_gap - new_bottom_template_offset - dna_ribbons_gap + wobble_last
			marker_leading_3p = _spawn_marker("5'", Vector2(
				nucleotide_original_x[last_synth_index] + %ThemeManager.marker_offset,
				leading_y - %ThemeManager.backbone_offset_distance
			))

	# Update 3' marker position (follows the rightmost synthesized base)
	if marker_leading_3p:
		var last_synth_index = -1
		for i in range(leading_synthesized_bases.size()):
			if leading_synthesized_bases[i] != null:
				last_synth_index = i
		if last_synth_index >= 0:
			var wobble_last = sin(wobble_t * wobble_speed * TAU + last_synth_index * wobble_phase_offset) * wobble_amplitude
			var leading_y = straight_y - dna_ribbons_gap - new_bottom_template_offset - dna_ribbons_gap + wobble_last
			marker_leading_3p.position = Vector2(
				nucleotide_original_x[last_synth_index] + %ThemeManager.marker_offset,
				leading_y - %ThemeManager.backbone_offset_distance
			)

	background_rect.color = %ThemeManager.background_color

# ==========================================
# SCRUBBER API (Public Functions for UI)
# ==========================================

func toggle_play():
	manual_override = !manual_override
	if not manual_override and helicase_mgr != null:
		if helicase_mgr.is_done():
			scrub_to_nucleotide_index(0)
			helicase_mgr.start_intro()
		if helicase_mgr.get_phase() == helicase_mgr.Phase.INTRO:
			_run_intro()
		else:
			synthesis_circle.modulate.a = 1.0
			if top_polymerase:
				top_polymerase.modulate.a = 1.0
			if helicase_node:
				helicase_node.modulate.a = 1.0
			helicase_mgr.resume()
		synthesis_circle_faded = false
	elif helicase_mgr != null:
		helicase_mgr.pause()

func _run_intro():
	# Position enzymes left of the strand, then fade in and slide to start position.
	var intro_x = nucleotide_original_x[0] - gap_width * 0.5
	var fade_time = 0.4
	var slide_time = 0.5

	synthesis_circle.position = Vector2(intro_x - gap_width, new_bottom_template_y)
	if top_polymerase:
		top_polymerase.position = Vector2(intro_x - gap_width, straight_y - dna_ribbons_gap - new_bottom_template_offset)
	if helicase_node:
		helicase_node.position = Vector2(intro_x, straight_y - dna_ribbons_gap / 2.0)

	var tween = create_tween().set_parallel(true)
	tween.tween_property(synthesis_circle, "modulate:a", 1.0, fade_time)
	if top_polymerase:
		tween.tween_property(top_polymerase, "modulate:a", 1.0, fade_time)
	if helicase_node:
		tween.tween_property(helicase_node, "modulate:a", 1.0, fade_time)
	tween.tween_property(synthesis_circle, "position",
		Vector2(factory_x, new_bottom_template_y), slide_time).set_delay(fade_time)
	if top_polymerase:
		tween.tween_property(top_polymerase, "position",
			Vector2(factory_x, straight_y - dna_ribbons_gap - new_bottom_template_offset), slide_time).set_delay(fade_time)
	if helicase_node:
		tween.tween_property(helicase_node, "position",
			Vector2(helicase_x, straight_y - dna_ribbons_gap / 2.0), slide_time).set_delay(fade_time)
	# Notify helicase_mgr when intro tween completes → starts SWEEPING
	tween.chain().tween_callback(func():
		if helicase_mgr != null:
			helicase_mgr.finish_intro()
	)

func scrub_to(progress: float):
	progress = clamp(progress, 0.0, 1.0)

	# Map progress to a slot index
	var target_slot = int(progress * (num_nucleotide_slots - 1))
	target_slot = clamp(target_slot, 0, num_nucleotide_slots - 1)

	# Derive helicase_x and factory_x from target slot for this scrub
	var target_helicase_x = nucleotide_original_x[target_slot]
	var target_factory_x = target_helicase_x - gap_width

	# Update helicase_mgr discrete state
	if helicase_mgr != null:
		helicase_mgr.scrub_to_slot(target_slot)

	# Derive visual state
	helicase_x = target_helicase_x
	factory_x = target_factory_x

	# Compute pulse_offset from slot position for trombone visual
	var slot_frac = fmod(float(target_slot), 2.0) / 2.0
	if slot_frac < 0.5:
		pulse_offset = slot_frac * 2.0 * nucleotide_slot_spacing
	else:
		pulse_offset = (1.0 - (slot_frac - 0.5) * 2.0) * nucleotide_slot_spacing
	var pulse_ratio = pulse_offset / nucleotide_slot_spacing
	loop_depth = lerp(loop_floor_depth, max_loop_depth, pulse_ratio)
	population_left_edge = factory_x - pulse_offset

	baseline_switched = (target_factory_x >= nucleotide_original_x[0])

	# Set phase on helicase_mgr based on scrub position
	if helicase_mgr != null:
		if target_slot >= num_nucleotide_slots - 1:
			helicase_mgr.set_phase(helicase_mgr.Phase.DONE)
			loop_depth = 0.0
			settle_blend = 1.0
			synthesis_circle_faded = true
			synthesis_circle.modulate.a = 0.0
			if top_polymerase:
				top_polymerase.modulate.a = 0.0
			if helicase_node:
				helicase_node.modulate.a = 0.0
		elif target_factory_x > nucleotide_original_x[num_nucleotide_slots - 1]:
			helicase_mgr.set_phase(helicase_mgr.Phase.FINISHING_LAST_PULSE)
			settle_blend = 0.0
		else:
			helicase_mgr.set_phase(helicase_mgr.Phase.SWEEPING)
			settle_blend = 0.0

	# ---- Clear and rebuild lagging strand bases ----
	for base in synthesized_bases:
		if base != null and is_instance_valid(base):
			base.queue_free()
	for bond in hydrogen_bonds:
		if bond != null and is_instance_valid(bond):
			bond.queue_free()
	synthesized_bases.clear()
	hydrogen_bonds.clear()
	synthesized_bases.resize(num_nucleotide_slots)
	hydrogen_bonds.resize(num_nucleotide_slots)

	# ---- Clear Okazaki fragments ----
	for frag in okazaki_fragments:
		if frag.has("backbone") and is_instance_valid(frag.backbone):
			frag.backbone.queue_free()
		for mark in frag.bond_marks:
			if is_instance_valid(mark): mark.queue_free()
		if frag.marker_5p and is_instance_valid(frag.marker_5p): frag.marker_5p.queue_free()
		if frag.marker_3p and is_instance_valid(frag.marker_3p): frag.marker_3p.queue_free()
	okazaki_fragments.clear()
	current_fragment_index = -1
	last_synthesis_pulse_cycle = -1

	# Free new strand markers when scrubbing back before the first base
	if target_factory_x < nucleotide_original_x[0]:
		if marker_new_5p and is_instance_valid(marker_new_5p):
			marker_new_5p.queue_free()
			marker_new_5p = null
	# marker_new_3p is always freed on scrub; it respawns in Phase.DONE when appropriate
	if marker_new_3p and is_instance_valid(marker_new_3p):
		marker_new_3p.queue_free()
		marker_new_3p = null

	# ---- Clear leading markers when scrubbing back ----
	if target_factory_x < nucleotide_original_x[0]:
		if marker_leading_5p and is_instance_valid(marker_leading_5p):
			marker_leading_5p.queue_free()
			marker_leading_5p = null
		if marker_leading_3p and is_instance_valid(marker_leading_3p):
			marker_leading_3p.queue_free()
			marker_leading_3p = null

	var is_done_phase = helicase_mgr != null and helicase_mgr.get_phase() == helicase_mgr.Phase.DONE
	var lagging_synth_count = 0
	for i in range(num_nucleotide_slots):
		if is_done_phase:
			lagging_synth_count += 1  # All slots synthesized when done
		elif nucleotide_original_x[i] < population_left_edge:
			if nucleotide_original_x[i] <= target_factory_x:
				lagging_synth_count += 1
			else:
				break
		else:
			break

	for i in range(lagging_synth_count):
		if synthesized_bases[i] == null:
			synthesized_bases[i] = _spawn_complement_base(i)
			hydrogen_bonds[i] = _spawn_hydrogen_bonds(i)
		nucleotide_synthesis_state[i] = SynthesisCrossState.COMPLETED
		nucleotide_transfer_state[i] = NucleotideTransferState.TRANSFERRED
		nucleotide_proximity_state[i] = ProximityState.OUTSIDE

	# ---- Rebuild Okazaki fragments from synthesized slots ----
	# Use the same pulse cycle logic as normal synthesis.
	# pulse cycle = how many full pulse_widths fit between slot 0 and slot i.
	for i in range(lagging_synth_count):
		var scrub_pulse_cycle = int((nucleotide_original_x[i] - nucleotide_original_x[0]) / pulse_width)
		var needs_new_frag = (scrub_pulse_cycle != last_synthesis_pulse_cycle)
		if needs_new_frag:
			if current_fragment_index >= 0:
				_close_okazaki_fragment(current_fragment_index)
			current_fragment_index = _start_new_okazaki_fragment()
		okazaki_fragments[current_fragment_index].slots.append(i)
		last_synthesis_pulse_cycle = scrub_pulse_cycle
	# Close all fragments except the last (which may still be growing)
	for fi in range(okazaki_fragments.size() - 1):
		okazaki_fragments[fi].complete = true
	# Close last fragment too if we're past the last slot
	if current_fragment_index >= 0 and target_factory_x > nucleotide_original_x[num_nucleotide_slots - 1]:
		_close_okazaki_fragment(current_fragment_index)

	for i in range(lagging_synth_count, num_nucleotide_slots):
		nucleotide_synthesis_state[i] = SynthesisCrossState.NONE
		nucleotide_transfer_state[i] = NucleotideTransferState.WAITING
		nucleotide_proximity_state[i] = ProximityState.OUTSIDE
		nucleotide_crossing_count[i] = 0
		nucleotide_entered_push_direction[i] = false
		nucleotide_max_y_reached[i] = straight_y

	# ---- Clear and rebuild leading strand bases ----
	for base in leading_synthesized_bases:
		if base != null and is_instance_valid(base):
			base.queue_free()
	for bond in leading_hydrogen_bonds:
		if bond != null and is_instance_valid(bond):
			bond.queue_free()
	leading_synthesized_bases.clear()
	leading_hydrogen_bonds.clear()
	leading_synthesized_bases.resize(num_nucleotide_slots)
	leading_hydrogen_bonds.resize(num_nucleotide_slots)

	# ---- Update template hydrogen bond visibility based on helicase position ----
	for i in range(num_nucleotide_slots):
		if template_hydrogen_bonds[i] != null:
			template_hydrogen_bonds[i].visible = (nucleotide_original_x[i] >= helicase_x)

	# ---- Clear leading bond marks ----
	for mark in leading_strand_bond_marks:
		if mark != null and is_instance_valid(mark):
			mark.queue_free()
	leading_strand_bond_marks.clear()

	var leading_polymerase_x = target_factory_x  # same as factory_x
	var leading_synth_count = 0
	for i in range(num_nucleotide_slots):
		# When DONE, all leading bases are synthesized regardless of polymerase position
		if is_done_phase or nucleotide_original_x[i] <= leading_polymerase_x:
			leading_synth_count += 1
		else:
			break

	for i in range(leading_synth_count):
		if leading_synthesized_bases[i] == null:
			var leading_base = dna_sequence.get_complement(i)
			leading_synthesized_bases[i] = _spawn_leading_base(i, leading_base)
			leading_hydrogen_bonds[i] = _spawn_leading_hydrogen_bonds(i)

	# Force immediate rail rebuild
	_rebuild_rail()
	_rebuild_top_rail()
	for i in range(template_strand_bottom.size()):
		template_strand_bottom[i].progress = track_length - nucleotide_original_x[i]
	for i in range(top_strand_slots.size()):
		top_strand_slots[i].progress = track_length - nucleotide_original_x[i]

	synthesis_circle.modulate.a = 1.0
	if top_polymerase:
		top_polymerase.modulate.a = 1.0
	if helicase_node:
		helicase_node.modulate.a = 1.0

	synthesis_circle.position = Vector2(factory_x, new_bottom_template_y)
	if top_polymerase:
		top_polymerase.position = Vector2(factory_x, straight_y - dna_ribbons_gap - new_bottom_template_offset)
	if helicase_node:
		helicase_node.position = Vector2(helicase_x, straight_y - dna_ribbons_gap / 2.0)

	queue_redraw()

func scrub_to_nucleotide_index(index: int):
	index = clamp(index, 0, num_nucleotide_slots - 1)
	var progress = float(index) / float(num_nucleotide_slots - 1)
	scrub_to(progress)

func step_forward():
	var count = get_synthesized_count()
	if count < num_nucleotide_slots:
		scrub_to_nucleotide_index(count + 1)
	else:
		scrub_to_nucleotide_index(num_nucleotide_slots - 1)

func step_backward():
	var count = get_synthesized_count()
	if count > 0:
		scrub_to_nucleotide_index(count - 1)
	else:
		scrub_to_nucleotide_index(0)

# ==========================================
# UI HELPER FUNCTIONS
# ==========================================

func get_total_progress() -> float:
	if num_nucleotide_slots <= 1: return 0.0
	if helicase_mgr == null: return 0.0
	return clamp(float(helicase_mgr.get_slot_index()) / float(num_nucleotide_slots - 1), 0.0, 1.0)

func get_synthesized_count() -> int:
	var count = 0
	for base in synthesized_bases:
		if base != null and is_instance_valid(base):
			count += 1
	return count

func get_sequence_rich_text() -> String:
	var text = "5' "
	var seq_string = dna_sequence._to_string()
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
# HELICASE SIGNAL HANDLERS
# ==========================================

func _on_helicase_slot_reached(index: int) -> void:
	# Fired by helicase_mgr each time it steps to a new slot.
	# Leading strand synthesis is handled by position in _process;
	# this is a hook for future per-slot logic (e.g. primase, clamps).
	print("[HELICASE] slot_reached: %d" % index)

func _on_helicase_phase_changed(new_phase: int) -> void:
	print("[HELICASE] phase_changed: %d" % new_phase)

# ==========================================
# OKAZAKI FRAGMENT HELPERS
# ==========================================

func _assign_to_okazaki_fragment(slot_index: int) -> void:
	# Fragment boundary uses slot position arithmetic — same as scrub rebuild.
	# Slots within the same pulse_width window belong to the same fragment.
	var current_pulse_cycle = int((nucleotide_original_x[slot_index] - nucleotide_original_x[0]) / pulse_width)
	var needs_new_frag = (current_pulse_cycle != last_synthesis_pulse_cycle)
	if needs_new_frag:
		if current_fragment_index >= 0 and not okazaki_fragments[current_fragment_index].complete:
			_close_okazaki_fragment(current_fragment_index)
		current_fragment_index = _start_new_okazaki_fragment()
	okazaki_fragments[current_fragment_index].slots.append(slot_index)
	last_synthesis_pulse_cycle = current_pulse_cycle
	print("[OKAZAKI] Slot %d assigned to fragment #%d (pulse_cycle=%d, needs_new=%s)" % [slot_index, current_fragment_index, current_pulse_cycle, str(needs_new_frag)])

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
		nitrogen_base.set_colors(
			_get_base_fill(base_char),
			%ThemeManager.base_label_color
		)

		var x = row_start_x + i * nucleotide_slot_spacing
		nucleotide_original_x.append(x)
		nucleotide_slot.progress = track_length - x
		template_strand_bottom.append(nucleotide_slot)
		nucleotide_transfer_state.append(NucleotideTransferState.WAITING)
		nucleotide_max_y_reached.append(straight_y)
		nucleotide_previous_y.append(straight_y)
		nucleotide_crossing_count.append(0)
		nucleotide_proximity_state.append(ProximityState.OUTSIDE)
		nucleotide_previous_x.append(x)
		nucleotide_entered_push_direction.append(false)
		nucleotide_synthesis_state.append(SynthesisCrossState.NONE)
		nucleotide_backbone_delta.append(%ThemeManager.backbone_offset_distance)
		synthesized_bases.append(null)
		new_strand_backbone_delta.append(%ThemeManager.backbone_offset_distance)
		hydrogen_bonds.append(null)

func _spawn_leading_arrays():
	"""Initialize arrays for leading strand with null values."""
	leading_synthesized_bases.clear()
	leading_hydrogen_bonds.clear()
	leading_strand_bond_marks.clear()
	marker_leading_5p = null
	marker_leading_3p = null
	for i in range(num_nucleotide_slots):
		leading_synthesized_bases.append(null)
		leading_hydrogen_bonds.append(null)

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
		base.set_colors(_get_base_fill(base_char), %ThemeManager.base_label_color)

		top_strand_slots.append(slot)
		top_strand_bases.append(base)
		top_strand_backbone_delta.append(%ThemeManager.backbone_offset_distance)
		template_hydrogen_bonds.append(_spawn_template_hydrogen_bonds(i))

func _spawn_complement_base(template_index: int) -> Node2D:
	var base = NewNitrogenBaseScene.instantiate()
	var base_type = dna_sequence.get_base(template_index)
	base.position = Vector2(
		template_strand_bottom[template_index].position.x,
		0.0
	)
	base.z_index = 2
	add_child(base)
	base.set_base_type(base_type)
	base.set_colors(
		_get_base_fill(base_type),
		%ThemeManager.base_label_color
	)
	return base

func _spawn_leading_base(index: int, base_type: String) -> Node2D:
	"""Spawn a base on the leading strand (above the top template)."""
	var base = NewNitrogenBaseScene.instantiate()
	var world_x = nucleotide_original_x[index]
	# Leading strand sits above the top template: straight_y - dna_ribbons_gap - dna_ribbons_gap
	var leading_y = straight_y - dna_ribbons_gap - new_bottom_template_offset - dna_ribbons_gap
	base.position = Vector2(world_x, leading_y)
	base.z_index = 2
	add_child(base)
	base.set_base_type(base_type)
	base.set_colors(
		_get_base_fill(base_type),
		%ThemeManager.base_label_color
	)
	return base

func _start_new_okazaki_fragment() -> int:
	var backbone = Line2D.new()
	backbone.default_color = %ThemeManager.backbone_color
	backbone.width = %ThemeManager.backbone_line_width
	backbone.z_index = -1
	backbone.joint_mode = Line2D.LINE_JOINT_ROUND
	backbone.begin_cap_mode = Line2D.LINE_CAP_ROUND
	backbone.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(backbone)
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
	print("[OKAZAKI] Started fragment #%d" % (okazaki_fragments.size() - 1))

func _close_okazaki_fragment(frag_index: int) -> void:
	# Called when a fragment is complete. Markers are spawned in the rendering
	# loop on the next frame once backbone points are available.
	if frag_index < 0 or frag_index >= okazaki_fragments.size():
		return
	okazaki_fragments[frag_index].complete = true
	print("[OKAZAKI] Closed fragment #%d — slots: %s" % [frag_index, str(okazaki_fragments[frag_index].slots)])

func _spawn_hydrogen_bonds(template_index: int) -> Node2D:
	var base_type = dna_sequence.get_base(template_index)
	var bond_count = 3 if (base_type == "C" or base_type == "G") else 2
	var bond_color = %ThemeManager.cg_bond_color if (base_type == "C" or base_type == "G") else %ThemeManager.at_bond_color
	var container = Node2D.new()
	var total_width = (bond_count - 1) * %ThemeManager.hydrogen_bond_spacing
	var start_x = -total_width / 2.0
	var inset = 12.0  # matches nitrogen_base body_radius default
	for b in range(bond_count):
		var line = Line2D.new()
		var lx = start_x + b * %ThemeManager.hydrogen_bond_spacing
		line.add_point(Vector2(lx, inset))
		line.add_point(Vector2(lx, dna_ribbons_gap - inset))
		line.default_color = bond_color
		line.width = %ThemeManager.hydrogen_bond_width
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		container.add_child(line)
	hydrogen_bonds_container.add_child(container)
	return container

func _spawn_leading_hydrogen_bonds(index: int) -> Node2D:
	"""Spawn hydrogen bonds between top template and leading strand."""
	var template_base = dna_sequence.get_base(index)  # top template base
	# Determine bond count based on the template base (which is the top strand)
	var bond_count = 3 if (template_base == "C" or template_base == "G") else 2
	var bond_color = %ThemeManager.cg_bond_color if (template_base == "C" or template_base == "G") else %ThemeManager.at_bond_color
	var container = Node2D.new()
	var total_width = (bond_count - 1) * %ThemeManager.hydrogen_bond_spacing
	var start_x = -total_width / 2.0
	var inset = 12.0  # matches nitrogen_base body_radius
	for b in range(bond_count):
		var line = Line2D.new()
		var lx = start_x + b * %ThemeManager.hydrogen_bond_spacing
		# The container will be positioned at the top template y, and we draw upward
		line.add_point(Vector2(lx, -inset))
		line.add_point(Vector2(lx, -(dna_ribbons_gap - inset)))
		line.default_color = bond_color
		line.width = %ThemeManager.hydrogen_bond_width
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		container.add_child(line)
	hydrogen_bonds_container.add_child(container)
	return container

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
	marker.set_colors(%ThemeManager.marker_color, %ThemeManager.marker_font_color)
	return marker

func _get_base_fill(base_type: String) -> Color:
	match base_type:
		"A": return %ThemeManager.base_color_a
		"T": return %ThemeManager.base_color_t
		"C": return %ThemeManager.base_color_c
		"G": return %ThemeManager.base_color_g
		"5'", "3'": return %ThemeManager.marker_color
	return Color.GRAY

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
	var bonded_y = straight_y - dna_ribbons_gap
	var unzipped_y = new_top_template_y
	var first_slot_x = nucleotide_original_x[0] if nucleotide_original_x.size() > 0 else 0.0

	# When done, top template stays at its unzipped position — it's now paired with the leading strand
	var is_done = helicase_mgr != null and helicase_mgr.get_phase() == helicase_mgr.Phase.DONE
	if is_done:
		curve.add_point(Vector2(track_length, unzipped_y))
		curve.add_point(Vector2(0, unzipped_y))
		top_rail_path.curve = curve
		return

	if helicase_x <= first_slot_x:
		curve.add_point(Vector2(track_length, bonded_y))
		curve.add_point(Vector2(-gap_width, bonded_y))
		top_rail_path.curve = curve
		return

	var handle_x = (helicase_x - factory_x) * 0.4
	curve.add_point(Vector2(track_length, bonded_y))
	curve.add_point(Vector2(helicase_x, bonded_y))
	curve.add_point(Vector2(helicase_x, bonded_y), Vector2.ZERO, Vector2(-handle_x, 0))
	curve.add_point(Vector2(factory_x, unzipped_y), Vector2(handle_x, 0), Vector2.ZERO)
	curve.add_point(Vector2(-gap_width, unzipped_y))
	top_rail_path.curve = curve

func _rebuild_rail():
	var is_done = helicase_mgr != null and helicase_mgr.get_phase() == helicase_mgr.Phase.DONE
	if is_done:
		var flat_curve = Curve2D.new()
		var rest_y = new_bottom_template_y if baseline_switched else straight_y
		flat_curve.add_point(Vector2(track_length, rest_y))
		flat_curve.add_point(Vector2(0, rest_y))
		loop_length = 0.0
		rail_path.curve = flat_curve
		template_strand_original_track.points = flat_curve.get_baked_points()
		return

	var helicase_at_end = helicase_x >= track_length - 1.0
	var curve = Curve2D.new()
	var blended_straight_y = lerp(straight_y, new_bottom_template_y, settle_blend) if baseline_switched else straight_y

	if not helicase_at_end:
		curve.add_point(Vector2(track_length, blended_straight_y))
		curve.add_point(Vector2(helicase_x, blended_straight_y))

	var bulge_y = blended_straight_y + loop_depth
	var handle_x = max(40.0, loop_depth * 0.6)

	curve.add_point(
		Vector2(helicase_x, blended_straight_y),
		Vector2.ZERO,
		Vector2(-handle_x, loop_depth * 0.5)
	)
	var mid_x = (factory_x + helicase_x) / 2.0
	var anchor_rest_y = new_bottom_template_y if baseline_switched else blended_straight_y

	var depth_ratio = loop_depth / gap_width
	var max_depth_ratio = max_loop_depth / gap_width
	var flare_t = clamp(depth_ratio / max_depth_ratio, 0.0, 1.0) if max_depth_ratio > 0.0 else 0.0
	var omega_flare = lerp(waist_flare_shallow, waist_flare_deep, flare_t)
	var mid_handle_x = max(1.0, (helicase_x - factory_x) * omega_flare)

	curve.add_point(
		Vector2(mid_x, bulge_y),
		Vector2(mid_handle_x, 0),
		Vector2(-mid_handle_x, 0)
	)

	curve.add_point(
		Vector2(factory_x, anchor_rest_y),
		Vector2(handle_x, loop_depth * 0.5),
		Vector2.ZERO
	)

	var loop_only_curve = Curve2D.new()
	loop_only_curve.add_point(
		Vector2(helicase_x, blended_straight_y),
		Vector2.ZERO,
		Vector2(-handle_x, loop_depth * 0.5)
	)
	loop_only_curve.add_point(
		Vector2(mid_x, bulge_y),
		Vector2(mid_handle_x, 0),
		Vector2(-mid_handle_x, 0)
	)
	loop_only_curve.add_point(
		Vector2(factory_x, anchor_rest_y),
		Vector2(handle_x, loop_depth * 0.5),
		Vector2.ZERO)
	loop_length = loop_only_curve.get_baked_length()

	curve.add_point(Vector2(0, anchor_rest_y))

	rail_path.curve = curve
	template_strand_original_track.points = curve.get_baked_points()

func _setup_synthesis_circle():
	synthesis_circle.z_index = 2
	var poly = Polygon2D.new()
	var points = PackedVector2Array()
	const SEGMENTS = 32
	for i in range(SEGMENTS):
		var angle = (float(i) / SEGMENTS) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * synthesis_circle_radius)
	poly.polygon = points
	poly.color = %ThemeManager.synthesis_circle_color
	synthesis_circle.add_child(poly)

	var synthesis_collision_shape = synthesis_area.get_node("SynthesisCollisionShape")
	var circle_shape = CircleShape2D.new()
	circle_shape.radius = synthesis_circle_radius
	synthesis_collision_shape.shape = circle_shape
	synthesis_area.monitoring = true
	synthesis_area.monitorable = true
	synthesis_area.area_entered.connect(_on_synthesis_area_entered)

func _setup_helicase():
	helicase_node = Node2D.new()
	helicase_node.z_index = 3

	var backbone_reach = %ThemeManager.backbone_offset_distance + %ThemeManager.backbone_line_width * 0.5
	var half_h = dna_ribbons_gap / 2.0 + backbone_reach + %ThemeManager.helicase_height_margin
	var half_w = %ThemeManager.helicase_half_width
	var thickness = %ThemeManager.helicase_thickness
	var outer_color = %ThemeManager.helicase_color
	var inner_color = %ThemeManager.background_color

	for pass_idx in range(2):
		var poly = Polygon2D.new()
		var w = half_w if pass_idx == 0 else half_w - thickness
		var h = half_h if pass_idx == 0 else half_h - thickness
		var r = w  # Capsule radius = half_width
		var pts = PackedVector2Array()
		const SEGS = 24
		for i in range(SEGS + 1):
			var angle = PI + (PI * i / SEGS)
			pts.append(Vector2(cos(angle) * r, -h + r + sin(angle) * r))
		for i in range(SEGS + 1):
			var angle = (PI * i / SEGS)
			pts.append(Vector2(cos(angle) * r, h - r + sin(angle) * r))
		poly.polygon = pts
		poly.color = outer_color if pass_idx == 0 else inner_color
		helicase_node.add_child(poly)

	helicase_node.position = Vector2(helicase_x, straight_y - dna_ribbons_gap / 2.0)
	add_child(helicase_node)

func _setup_top_polymerase():
	top_polymerase = Node2D.new()
	top_polymerase.z_index = 2
	var poly = Polygon2D.new()
	var points = PackedVector2Array()
	const SEGMENTS = 32
	for i in range(SEGMENTS):
		var angle = (float(i) / SEGMENTS) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * synthesis_circle_radius)
	poly.polygon = points
	poly.color = Color(0.2, 0.4, 1.0, 1.0)
	top_polymerase.add_child(poly)
	top_polymerase.position = Vector2(factory_x, straight_y - dna_ribbons_gap - new_bottom_template_offset)
	add_child(top_polymerase)

func _on_synthesis_area_entered(area: Area2D):
	if not area.name.begins_with("NucleotideArea_"):
		return
	var nucleotide_index = int(area.name.substr("NucleotideArea_".length()))
	if nucleotide_index < 0 or nucleotide_index >= template_strand_bottom.size():
		return
	var nucleotide_slot = template_strand_bottom[nucleotide_index]
	if not nucleotide_slot.is_in_group(UNZIPPED_POPULATION_GROUP):
		nucleotide_slot.add_to_group(UNZIPPED_POPULATION_GROUP)

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

func _update_bond_marks_leading(points: PackedVector2Array):
	"""Update bond marks for the leading strand backbone."""
	var needed = max(0, points.size() - 1)
	while leading_strand_bond_marks.size() < needed:
		leading_strand_bond_marks.append(_create_bond_mark_sprite())  # ← Creates left-pointing diamonds
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
	var h = %ThemeManager.backbone_line_width / 2.0
	var w = %ThemeManager.bond_mark_width
	var black_diamond = Polygon2D.new()
	black_diamond.polygon = PackedVector2Array([
		Vector2(w / 2.0, 0),
		Vector2(0, -h),
		Vector2(-w / 2.0, 0),
		Vector2(0, h),
	])
	black_diamond.color = %ThemeManager.bond_mark_black_color
	holder.add_child(black_diamond)
	var back_inset = %ThemeManager.bond_mark_back_inset
	var magenta_diamond = Polygon2D.new()
	magenta_diamond.polygon = PackedVector2Array([
		Vector2(w / 2.0, 0),
		Vector2(0, -h),
		Vector2(-w / 2.0 + back_inset, 0),
		Vector2(0, h),
	])
	magenta_diamond.color = %ThemeManager.backbone_color
	holder.add_child(magenta_diamond)
	holder.z_index = 1
	add_child(holder)
	return holder

func _create_bond_mark_sprite_reversed() -> Node2D:
	var holder = Node2D.new()
	var h = %ThemeManager.backbone_line_width / 2.0
	var w = %ThemeManager.bond_mark_width
	var black_diamond = Polygon2D.new()
	black_diamond.polygon = PackedVector2Array([
		Vector2(w / 2.0, 0),
		Vector2(0, -h),
		Vector2(-w / 2.0, 0),
		Vector2(0, h),
	])
	black_diamond.color = %ThemeManager.bond_mark_black_color
	holder.add_child(black_diamond)
	var back_inset = %ThemeManager.bond_mark_back_inset
	var magenta_diamond = Polygon2D.new()
	magenta_diamond.polygon = PackedVector2Array([
		Vector2(w / 2.0 - back_inset, 0),
		Vector2(0, -h),
		Vector2(-w / 2.0, 0),
		Vector2(0, h),
	])
	magenta_diamond.color = %ThemeManager.backbone_color
	holder.add_child(magenta_diamond)
	holder.z_index = 1
	add_child(holder)
	return holder

# ==========================================
# SMOOTHSTEP HELPER
# ==========================================

func smoothstep(a: float, b: float, t: float) -> float:
	t = clamp((t - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
