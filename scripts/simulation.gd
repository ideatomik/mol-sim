extends Node2D

# ==========================================
# v 69.3 - Fix leading strand marker orientation (3' left, 5' right)
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
@export var sweep_speed: float = 90.0
@export var pulse_nucleotide_count: int = 6
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

var helicase_x: float = 0.0
var factory_x: float = 0.0

enum Phase { INTRO, SWEEPING, FINISHING_LAST_PULSE, SETTLING, DONE }
var phase: Phase = Phase.SWEEPING

var pulse_time_budget: float = 0.0
var pulse_speed: float = 0.0

enum PulseState { GROWING, SHRINKING, DONE }
var pulse_state: PulseState = PulseState.GROWING
var pulse_offset: float = 0.0

var population_left_edge: float = 0.0
var loop_depth: float = 0.0
var loop_length: float = 0.0

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

var settling_t: float = 0.0
var settling_loop_depth_start: float = 0.0
var settle_blend: float = 0.0

var bond_marks: Array[Node2D] = []
var new_strand_bond_marks: Array[Node2D] = []
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
	pulse_width = pulse_nucleotide_count * nucleotide_slot_spacing
	pulse_time_budget = pulse_width / sweep_speed
	pulse_speed = (2.0 * pulse_width) / pulse_time_budget

	# 4. RESET all state variables
	helicase_x = gap_width
	factory_x = 0.0
	loop_depth = max_loop_depth
	pulse_offset = 0.0
	pulse_state = PulseState.GROWING
	phase = Phase.INTRO
	baseline_switched = false
	settle_blend = 0.0
	settling_t = 0.0
	manual_override = true  # Start paused when a new sequence loads
	synthesis_circle_faded = false

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
	nodes_to_free.append_array(new_strand_bond_marks)
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
	new_strand_bond_marks.clear()
	leading_strand_bond_marks.clear()
	marker_leading_5p = null
	marker_leading_3p = null

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
	# ---------- 1. STATE UPDATE (only if not manually overridden) ----------
	if not manual_override:
		match phase:
			Phase.INTRO:
				pass  # Handled by _run_intro tween; simulation doesn't advance.
			Phase.SWEEPING:
				helicase_x += sweep_speed * delta
				factory_x = helicase_x - gap_width
				match pulse_state:
					PulseState.GROWING:
						pulse_offset = min(pulse_offset + pulse_speed * delta, pulse_width)
						if pulse_offset >= pulse_width:
							pulse_state = PulseState.SHRINKING
					PulseState.SHRINKING:
						pulse_offset = max(pulse_offset - pulse_speed * delta, 0.0)
						if pulse_offset <= 0.0:
							pulse_state = PulseState.GROWING
					PulseState.DONE:
						pulse_offset = 0.0
				var pulse_ratio = pulse_offset / pulse_width
				loop_depth = lerp(loop_floor_depth, max_loop_depth, pulse_ratio)
				population_left_edge = factory_x - pulse_offset
				var last_nucleotide_x = nucleotide_original_x[nucleotide_original_x.size() - 1]
				if factory_x > last_nucleotide_x:
					phase = Phase.FINISHING_LAST_PULSE

			Phase.FINISHING_LAST_PULSE:
				match pulse_state:
					PulseState.GROWING:
						pulse_offset = min(pulse_offset + pulse_speed * delta, pulse_width)
						if pulse_offset >= pulse_width:
							pulse_state = PulseState.SHRINKING
					PulseState.SHRINKING:
						pulse_offset = max(pulse_offset - pulse_speed * delta, 0.0)
						if pulse_offset <= 0.0:
							pulse_state = PulseState.GROWING
					PulseState.DONE:
						pulse_offset = 0.0
				var pulse_ratio2 = pulse_offset / pulse_width
				loop_depth = lerp(loop_floor_depth, max_loop_depth, pulse_ratio2)
				population_left_edge = factory_x - pulse_offset
				var all_settled = baseline_switched
				if all_settled:
					for i in range(template_strand_bottom.size()):
						if abs(template_strand_bottom[i].position.y - new_bottom_template_y) > settling_threshold:
							all_settled = false
							break
				if all_settled:
					settling_t = 0.0
					settling_loop_depth_start = loop_depth
					phase = Phase.SETTLING

			Phase.SETTLING:
				settling_t += delta
				var t = clamp(settling_t / settling_duration, 0.0, 1.0)
				var eased_t = smoothstep(0.0, 1.0, t)
				loop_depth = lerp(settling_loop_depth_start, 0.0, eased_t)
				settle_blend = eased_t
				if t >= 1.0:
					loop_depth = 0.0
					settle_blend = 1.0
					phase = Phase.DONE
					for j in range(template_strand_bottom.size()):
						if nucleotide_proximity_state[j] == ProximityState.INSIDE \
						and nucleotide_entered_push_direction[j] \
						and nucleotide_synthesis_state[j] == SynthesisCrossState.NONE:
							nucleotide_synthesis_state[j] = SynthesisCrossState.COMPLETED
							synthesized_bases[j] = _spawn_complement_base(j)
							hydrogen_bonds[j] = _spawn_hydrogen_bonds(j)
							print("[t=%s] nucleotide_slot[%d] COMPLETED via end-of-run sweep" % [
								Time.get_ticks_msec(), j
							])

			Phase.DONE:
				settle_blend = 1.0
				if not synthesis_circle_faded:
					synthesis_circle_faded = true
					var fade_tween = create_tween()
					fade_tween.tween_property(synthesis_circle, "modulate:a", 0.0, fade_duration)
					if top_polymerase:
						fade_tween.parallel().tween_property(top_polymerase, "modulate:a", 0.0, fade_duration)
					var last = num_nucleotide_slots - 1
					var wobble_last = nucleotide_bases[last].position.y
					marker_new_3p = _spawn_marker("3'", Vector2(
						nucleotide_original_x[last] + %ThemeManager.marker_offset,
						new_bottom_template_y + dna_ribbons_gap + wobble_last + new_strand_backbone_delta[last]
					))
					# Sweep: catch any leading bases not yet spawned.
					for i in range(num_nucleotide_slots):
						if leading_synthesized_bases[i] == null:
							leading_synthesized_bases[i] = _spawn_leading_base(i, dna_sequence.get_complement(i))
							leading_hydrogen_bonds[i] = _spawn_leading_hydrogen_bonds(i)

		# ---- State logic that runs every frame (even if not playing, but we keep it here for clarity) ----
		synthesis_circle.position = Vector2(factory_x, new_bottom_template_y)
		if top_polymerase:
			top_polymerase.position = Vector2(factory_x, straight_y - dna_ribbons_gap - new_bottom_template_offset)
		if helicase_node:
			helicase_node.position = Vector2(helicase_x, straight_y - dna_ribbons_gap / 2.0)

		if phase != Phase.DONE:
			for i in range(template_strand_bottom.size()):
				template_strand_bottom[i].progress = track_length - nucleotide_original_x[i]

		# ---- Lagging strand synthesis logic (existing) ----
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

			nucleotide_previous_x[i] = current_x

		for i in range(template_strand_bottom.size()):
			var nucleotide_slot = template_strand_bottom[i]
			var x = nucleotide_original_x[i]
			var in_loop = (phase != Phase.DONE) and x >= population_left_edge and x <= helicase_x
			if in_loop and not nucleotide_slot.is_in_group(LOOP_POPULATION_GROUP):
				nucleotide_slot.add_to_group(LOOP_POPULATION_GROUP)
			elif not in_loop and nucleotide_slot.is_in_group(LOOP_POPULATION_GROUP):
				nucleotide_slot.remove_from_group(LOOP_POPULATION_GROUP)

		# ---- Leading strand synthesis (Option B: Position-Based) ----
		# The leading polymerase position is factory_x (since top_polymerase follows factory_x)
		var leading_polymerase_x = factory_x

		# Determine how many top-strand bases have been passed by the leading polymerase
		var leading_synth_count = 0
		for i in range(num_nucleotide_slots):
			if nucleotide_original_x[i] <= leading_polymerase_x:
				leading_synth_count += 1
			else:
				break

		# Spawn leading bases as needed (only if not already synthesized)
		for i in range(leading_synth_count):
			if leading_synthesized_bases[i] == null:
				# The leading strand base is the complement of the top template.
				# Since top template is complement of bottom, leading base = bottom base.
				var bottom_base = dna_sequence.get_complement(i)
				leading_synthesized_bases[i] = _spawn_leading_base(i, bottom_base)
				leading_hydrogen_bonds[i] = _spawn_leading_hydrogen_bonds(i)

		# Emit progress for the UI
		progress_changed.emit(get_total_progress())

	# ---------- 2. VISUAL RENDERING (Always runs, even when paused) ----------
	# Rail rebuilds here so they always reflect current state, even when paused
	# or after scrubbing/stopping.
	_rebuild_rail()
	_rebuild_top_rail()

	var virtual_time = (helicase_x - gap_width) / sweep_speed if sweep_speed > 0 else 0.0
	var wobble_t = virtual_time

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

	# ---- Lagging strand new strand (existing) ----
	var new_strand_points = PackedVector2Array()
	for i in range(synthesized_bases.size()):
		if synthesized_bases[i] != null:
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
			new_strand_points.append(Vector2(world_x, world_y + new_strand_backbone_delta[i]))
	new_strand_backbone_line.points = new_strand_points
	new_strand_backbone_line.width = %ThemeManager.backbone_line_width
	_update_bond_marks_new_strand(new_strand_points)

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
			template_hydrogen_bonds[i].visible = (world_x >= helicase_x)
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

	# 5' marker: at the growing tip (rightmost synthesized base)
	if marker_leading_5p == null and leading_synthesized_bases[0] != null:
		var last_synth_index = -1
		for i in range(leading_synthesized_bases.size()):
			if leading_synthesized_bases[i] != null:
				last_synth_index = i
		if last_synth_index >= 0:
			var wobble_last = sin(wobble_t * wobble_speed * TAU + last_synth_index * wobble_phase_offset) * wobble_amplitude
			var leading_y = straight_y - dna_ribbons_gap - new_bottom_template_offset - dna_ribbons_gap + wobble_last
			marker_leading_5p = _spawn_marker("5'", Vector2(
				nucleotide_original_x[last_synth_index] + %ThemeManager.marker_offset,
				leading_y - %ThemeManager.backbone_offset_distance
			))

	# Update 5' marker position (follows the rightmost synthesized base)
	if marker_leading_5p:
		var last_synth_index = -1
		for i in range(leading_synthesized_bases.size()):
			if leading_synthesized_bases[i] != null:
				last_synth_index = i
		if last_synth_index >= 0:
			var wobble_last = sin(wobble_t * wobble_speed * TAU + last_synth_index * wobble_phase_offset) * wobble_amplitude
			var leading_y = straight_y - dna_ribbons_gap - new_bottom_template_offset - dna_ribbons_gap + wobble_last
			marker_leading_5p.position = Vector2(
				nucleotide_original_x[last_synth_index] + %ThemeManager.marker_offset,
				leading_y - %ThemeManager.backbone_offset_distance
			)

	# 3' marker: fixed at the left end (index 0, the origin of the leading strand)
	if marker_leading_3p == null and leading_synthesized_bases[0] != null:
		var wobble_first = sin(wobble_t * wobble_speed * TAU + 0 * wobble_phase_offset) * wobble_amplitude
		var leading_y = straight_y - dna_ribbons_gap - new_bottom_template_offset - dna_ribbons_gap + wobble_first
		marker_leading_3p = _spawn_marker("3'", Vector2(
			nucleotide_original_x[0] - %ThemeManager.marker_offset,
			leading_y - %ThemeManager.backbone_offset_distance
		))

	# Update 3' marker position (follows wobble at index 0)
	if marker_leading_3p:
		var wobble_first = sin(wobble_t * wobble_speed * TAU + 0 * wobble_phase_offset) * wobble_amplitude
		var leading_y = straight_y - dna_ribbons_gap - new_bottom_template_offset - dna_ribbons_gap + wobble_first
		marker_leading_3p.position = Vector2(
			nucleotide_original_x[0] - %ThemeManager.marker_offset,
			leading_y - %ThemeManager.backbone_offset_distance
		)

	background_rect.color = %ThemeManager.background_color

# ==========================================
# SCRUBBER API (Public Functions for UI)
# ==========================================

func toggle_play():
	manual_override = !manual_override
	if not manual_override:
		if phase == Phase.DONE:
			scrub_to_nucleotide_index(0)
			phase = Phase.INTRO
		if phase == Phase.INTRO:
			_run_intro()
		else:
			synthesis_circle.modulate.a = 1.0
			if top_polymerase:
				top_polymerase.modulate.a = 1.0
			if helicase_node:
				helicase_node.modulate.a = 1.0
		synthesis_circle_faded = false

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
	# Fade in
	tween.tween_property(synthesis_circle, "modulate:a", 1.0, fade_time)
	if top_polymerase:
		tween.tween_property(top_polymerase, "modulate:a", 1.0, fade_time)
	if helicase_node:
		tween.tween_property(helicase_node, "modulate:a", 1.0, fade_time)
	# Slide to starting position after fade
	tween.tween_property(synthesis_circle, "position",
		Vector2(factory_x, new_bottom_template_y), slide_time).set_delay(fade_time)
	if top_polymerase:
		tween.tween_property(top_polymerase, "position",
			Vector2(factory_x, straight_y - dna_ribbons_gap - new_bottom_template_offset), slide_time).set_delay(fade_time)
	if helicase_node:
		tween.tween_property(helicase_node, "position",
			Vector2(helicase_x, straight_y - dna_ribbons_gap / 2.0), slide_time).set_delay(fade_time)
	# Start simulation after intro completes
	tween.chain().tween_callback(func():
		phase = Phase.SWEEPING
	)

func scrub_to(progress: float):
	progress = clamp(progress, 0.0, 1.0)

	var start_helicase_x = gap_width
	var last_nucleotide_x = nucleotide_original_x[num_nucleotide_slots - 1]
	var end_helicase_x = last_nucleotide_x + gap_width + pulse_width
	var total_distance = end_helicase_x - start_helicase_x

	var target_helicase_x = lerp(start_helicase_x, end_helicase_x, progress)
	var target_factory_x = target_helicase_x - gap_width

	# Calculate pulse offset for this exact time
	var virtual_time = (target_helicase_x - gap_width) / sweep_speed
	var cycle_duration = 2.0 * pulse_time_budget
	var t_mod = fmod(virtual_time, cycle_duration)

	var target_pulse_offset: float
	if t_mod < pulse_time_budget:
		target_pulse_offset = (t_mod / pulse_time_budget) * pulse_width
	else:
		var shrinking_t = t_mod - pulse_time_budget
		target_pulse_offset = (1.0 - (shrinking_t / pulse_time_budget)) * pulse_width

	# Apply state
	helicase_x = target_helicase_x
	factory_x = target_factory_x
	pulse_offset = target_pulse_offset
	var pulse_ratio = pulse_offset / pulse_width
	loop_depth = lerp(loop_floor_depth, max_loop_depth, pulse_ratio)
	population_left_edge = factory_x - pulse_offset

	baseline_switched = (target_factory_x >= nucleotide_original_x[0])

	# Handle phase
	if target_helicase_x >= end_helicase_x - pulse_width:
		phase = Phase.DONE
		loop_depth = 0.0
		settle_blend = 1.0
		synthesis_circle_faded = true
		synthesis_circle.modulate.a = 0.0
		if top_polymerase:
			top_polymerase.modulate.a = 0.0
	elif target_factory_x > nucleotide_original_x[num_nucleotide_slots - 1]:
		phase = Phase.FINISHING_LAST_PULSE
		settle_blend = 0.0
	else:
		phase = Phase.SWEEPING
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

	# Free new strand markers when scrubbing back before the first base
	if target_factory_x < nucleotide_original_x[0]:
		if marker_new_5p and is_instance_valid(marker_new_5p):
			marker_new_5p.queue_free()
			marker_new_5p = null
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

	var lagging_synth_count = 0
	for i in range(num_nucleotide_slots):
		if nucleotide_original_x[i] <= target_factory_x:
			lagging_synth_count += 1
		else:
			break

	for i in range(lagging_synth_count):
		if synthesized_bases[i] == null:
			synthesized_bases[i] = _spawn_complement_base(i)
			hydrogen_bonds[i] = _spawn_hydrogen_bonds(i)
		nucleotide_synthesis_state[i] = SynthesisCrossState.COMPLETED
		nucleotide_transfer_state[i] = NucleotideTransferState.TRANSFERRED
		nucleotide_proximity_state[i] = ProximityState.OUTSIDE

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
		if nucleotide_original_x[i] <= leading_polymerase_x:
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
	index = clamp(index, 0, num_nucleotide_slots)
	var start_x = gap_width
	var total_distance = (nucleotide_original_x[num_nucleotide_slots - 1] + gap_width + pulse_width) - start_x

	var target_helicase_x: float
	if index == 0:
		target_helicase_x = gap_width
	elif index == num_nucleotide_slots:
		var last_x = nucleotide_original_x[num_nucleotide_slots - 1]
		target_helicase_x = last_x + gap_width + pulse_width
	else:
		target_helicase_x = nucleotide_original_x[index] + gap_width

	var progress = clamp((target_helicase_x - start_x) / total_distance, 0.0, 1.0)
	scrub_to(progress)

func step_forward():
	var count = get_synthesized_count()
	if count < num_nucleotide_slots:
		scrub_to_nucleotide_index(count + 1)
	else:
		scrub_to_nucleotide_index(num_nucleotide_slots)

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
	var start_x = gap_width
	var last_x = nucleotide_original_x[num_nucleotide_slots - 1]
	var end_helicase_x = last_x + gap_width + pulse_width
	var total_distance = end_helicase_x - start_x
	if total_distance <= 0: return 0.0
	return clamp((helicase_x - start_x) / total_distance, 0.0, 1.0)

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
		if i < synthesized_bases.size() and synthesized_bases[i] != null and is_instance_valid(synthesized_bases[i]):
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
		nitrogen_base.set_font(%ThemeManager.base_label_font_size, %ThemeManager.base_label_font)

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
		base.set_font(%ThemeManager.base_label_font_size, %ThemeManager.base_label_font)

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
	base.set_font(%ThemeManager.base_label_font_size, %ThemeManager.base_label_font)
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
	base.set_font(%ThemeManager.base_label_font_size, %ThemeManager.base_label_font)
	return base

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
	marker.set_font(%ThemeManager.base_label_font_size, %ThemeManager.base_label_font)
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
	if phase == Phase.DONE:
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

func _update_bond_marks_new_strand(points: PackedVector2Array):
	var needed = max(0, points.size() - 1)
	while new_strand_bond_marks.size() < needed:
		new_strand_bond_marks.append(_create_bond_mark_sprite_reversed())
	while new_strand_bond_marks.size() > needed:
		var extra = new_strand_bond_marks.pop_back()
		extra.queue_free()
	for i in range(needed):
		var a = points[i]
		var b = points[i + 1]
		var mid = (a + b) / 2.0
		var segment = b - a
		var mark = new_strand_bond_marks[i]
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