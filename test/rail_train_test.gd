extends Node2D

# ==========================================
# RAIL/TRAIN TEST v59
# Hydrogen bonds between template and new strand bases.
# A-T pairs: 2 lines. C-G pairs: 3 lines.
# Each bond group is a Node2D container child of HydrogenBondsContainer
# (a dedicated scene node), holding the individual Line2D segments in
# local space (y: 0 to dna_ribbons_gap). The container's world position
# is updated every frame to follow the template slot x and wobble y,
# so the bonds track both strands without recomputing each line.
# Spawned progressively on synthesis completion, same trigger as the
# complement base. Color and thickness are @export vars.
# ==========================================

const NewNitrogenBaseScene := preload("res://test/new_nitrogen_base.tscn")

@onready var rail_path: Path2D = $RailPath
@onready var template_strand_original_track: Line2D = $TemplateStrandOriginalTrack
@onready var new_strand_line: Line2D = $NewStrandLine
@onready var synthesis_circle: Node2D = $SynthesisCircle
@onready var synthesis_area: Area2D = $SynthesisCircle/SynthesisArea
@onready var template_strand_new_track: Line2D = $TemplateStrandNewTrack
@onready var new_synthesized_strand_position: Line2D = $NewSynthesizedStrandPosition
@onready var backbone_line: Line2D = $BackboneLine
@onready var hydrogen_bonds_container: Node2D = $HydrogenBondsContainer

@export_group("Track Layout")
@export var nucleotide_slot_spacing: float = 60.0
@export var num_nucleotide_slots: int = 24
@export var straight_y: float = 300.0
## Computed in _ready() from (num_nucleotide_slots - 1) * nucleotide_slot_spacing + 2 * gap_width.
## Not an export -- change num_nucleotide_slots or nucleotide_slot_spacing instead.
var track_length: float = 0.0
@export var new_bottom_template_offset: float = 90.0
## Y offset from new_bottom_template_y to the synthesized strand.
## Defaults to new_bottom_template_offset (the same gap used between
## TemplateStrandOriginalTrack and TemplateStrandNewTrack) but can be
## tweaked freely in the Inspector.
@export var dna_ribbons_gap: float = 90.0

@export_group("Loop Geometry")
@export var loop_floor_depth: float = 15.0
@export var max_loop_depth: float = 194.0
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
## Threshold in pixels within which all nucleotide slots must be to
## new_bottom_template_y before FINISHING_LAST_PULSE transitions to
## SETTLING. Increase if larger new_bottom_template_offset values cause
## the simulation to stall at the end.
@export var settling_threshold: float = 2.0

@export_group("Wobble")
## Maximum pixel offset of the per-slot sine wobble (up and down).
## Set to 0 to disable wobble entirely.
@export var wobble_amplitude: float = 2.0
## Speed of the wobble in cycles per second.
@export var wobble_speed: float = 1.5
## Phase offset between adjacent slots in radians -- higher values make
## neighbors more out of sync, lower values make the whole strand move
## more in unison. TAU/num_slots gives one full wave across the strand.
@export var wobble_phase_offset: float = 0.8

@export_group("Nucleotide Slot Visuals (DEPRECATED -- will be replaced by nitrogen_base child)")
@export var nucleotide_slot_size: Vector2 = Vector2(24, 24)
@export var nucleotide_color_even: Color = Color(0.2, 0.6, 0.9)
@export var nucleotide_color_odd: Color = Color(0.9, 0.6, 0.2)
@export var nucleotide_color_unzipped: Color = Color(0.0, 1.0, 1.0, 1.0)
@export var nucleotide_color_sequence_complete: Color = Color(1.0, 0.0, 1.0, 1.0)

@export_group("Backbone")
@export var backbone_color: Color = Color(1.0, 0.0, 1.0, 1.0)
@export var backbone_line_width: float = 8.0
@export var backbone_offset_distance: float = 12.0
@export var backbone_offset_smoothing_speed: float = 10.0

@export_group("Bond Marks")
@export var bond_mark_width: float = 14.0
@export var bond_mark_black_color: Color = Color(0.0, 0.0, 0.0, 1.0)
@export var bond_mark_back_inset: float = 6.3

@export_group("Hydrogen Bonds")
## Color of the two hydrogen bonds in A-T pairs.
@export var at_bond_color: Color = Color(1.0, 0.85, 0.3, 1.0)
## Color of the three hydrogen bonds in C-G pairs.
@export var cg_bond_color: Color = Color(0.3, 0.85, 1.0, 1.0)
## Width of each individual hydrogen bond line in pixels.
@export var hydrogen_bond_width: float = 1.5
## Horizontal spacing between parallel bond lines in pixels.
@export var hydrogen_bond_spacing: float = 4.0

@export_group("Synthesis Circle")
@export var synthesis_circle_color: Color = Color(1.0, 0.85, 0.1)
@export var synthesis_circle_radius: float = 16.0
@export var synthesis_inside_threshold: float = 16.0
@export var synthesis_outside_threshold: float = 24.0

var new_bottom_template_y: float = 0.0
var new_synthesized_strand_y: float = 0.0
var new_strand_y: float = 0.0
var synthesis_circle_y: float = 0.0
var pulse_width: float = 0.0

var synthesis_circle_faded: bool = false

var helicase_x: float = 0.0
var factory_x: float = 0.0

enum Phase { SWEEPING, FINISHING_LAST_PULSE, SETTLING, DONE }
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
## Bond marks for the new synthesized strand backbone -- separate array
## so template and new strand marks are managed independently.
var new_strand_bond_marks: Array[Node2D] = []
## Created in _ready() -- not a scene node so it doesn't need an @onready.
var new_strand_backbone_line: Line2D
## Per-slot backbone offset delta for the new strand, lerped each frame
## same as nucleotide_backbone_delta for the template strand.
var new_strand_backbone_delta: Array[float] = []

## Single source of truth for the template strand's base sequence.
## Populated with a random sequence in _ready(); can be overridden
## before the simulation starts via dna_sequence.set_from_string().
var dna_sequence := DnaSequenceResource.new()

var synthesized_bases: Array = []
## Parallel to template_strand_bottom: null until synthesis completes,
## then holds the Node2D container (child of HydrogenBondsContainer)
## with the individual Line2D bond segments inside.
var hydrogen_bonds: Array = []

func _ready():
	track_length = (num_nucleotide_slots - 1) * nucleotide_slot_spacing + 2.0 * gap_width
	print("[SETUP] track_length computed: %.1f (%d slots x %.1fpx + 2x gap_width %.1fpx)" % [
		track_length, num_nucleotide_slots, nucleotide_slot_spacing, gap_width
	])

	dna_sequence.randomize_sequence(num_nucleotide_slots)
	print("[SETUP] sequence: %s" % dna_sequence.to_string())

	new_bottom_template_y = straight_y + new_bottom_template_offset
	new_synthesized_strand_y = new_bottom_template_y + new_bottom_template_offset
	new_strand_y = straight_y + max_loop_depth + nucleotide_slot_size.y
	synthesis_circle_y = straight_y + max_loop_depth
	pulse_width = pulse_nucleotide_count * nucleotide_slot_spacing

	helicase_x = gap_width
	factory_x = 0.0
	loop_depth = max_loop_depth

	pulse_time_budget = pulse_width / sweep_speed
	pulse_speed = (2.0 * pulse_width) / pulse_time_budget

	_rebuild_rail()
	_spawn_nucleotide_slots()
	_setup_synthesis_circle()

	template_strand_original_track.visible = true

	template_strand_new_track.points = PackedVector2Array([
		Vector2(0, new_bottom_template_y),
		Vector2(track_length, new_bottom_template_y)
	])
	template_strand_new_track.visible = true

	new_synthesized_strand_position.points = PackedVector2Array([
		Vector2(0, new_synthesized_strand_y),
		Vector2((factory_x + helicase_x) / 2.0, new_synthesized_strand_y)
	])
	new_synthesized_strand_position.visible = true

	backbone_line.default_color = backbone_color
	backbone_line.width = backbone_line_width
	backbone_line.z_index = -1
	backbone_line.joint_mode = Line2D.LINE_JOINT_ROUND
	backbone_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	backbone_line.end_cap_mode = Line2D.LINE_CAP_ROUND

	# New strand backbone -- created in code, same style as template backbone.
	new_strand_backbone_line = Line2D.new()
	new_strand_backbone_line.default_color = backbone_color
	new_strand_backbone_line.width = backbone_line_width
	new_strand_backbone_line.z_index = -1
	new_strand_backbone_line.joint_mode = Line2D.LINE_JOINT_ROUND
	new_strand_backbone_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	new_strand_backbone_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(new_strand_backbone_line)

	print("=== RUN START === baseline_switched:%s pulse_nucleotide_count:%d" % [baseline_switched, pulse_nucleotide_count])

func _process(delta):
	match phase:
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
						print("[t=%s] nucleotide_slot[%d] COMPLETED via end-of-run sweep (was mid-push at DONE)" % [
							Time.get_ticks_msec(), j
						])
		Phase.DONE:
			settle_blend = 1.0
			if not synthesis_circle_faded:
				synthesis_circle_faded = true
				var fade_tween = create_tween()
				fade_tween.tween_property(synthesis_circle, "modulate:a", 0.0, fade_duration)

	_rebuild_rail()

	synthesis_circle.position = Vector2(factory_x, new_bottom_template_y)

	var new_strand_tracking_x = (factory_x + helicase_x) / 2.0
	new_synthesized_strand_position.points = PackedVector2Array([
		Vector2(0, new_synthesized_strand_y),
		Vector2(new_strand_tracking_x, new_synthesized_strand_y)
	])

	# Progress only needs updating while the simulation is running --
	# at Phase.DONE the curve is flat and slots don't move, so the
	# constant progress reassignment would fight the wobble by forcing
	# Godot to recalculate child transforms every frame.
	if phase != Phase.DONE:
		for i in range(template_strand_bottom.size()):
			template_strand_bottom[i].progress = track_length - nucleotide_original_x[i]

	for i in range(template_strand_bottom.size()):
		var nucleotide_y = template_strand_bottom[i].position.y

		if nucleotide_y > nucleotide_max_y_reached[i]:
			nucleotide_max_y_reached[i] = nucleotide_y

		if not baseline_switched and nucleotide_y >= new_bottom_template_y:
			baseline_switched = true
			baseline_switch_nucleotide_index = i
			print(">>> BASELINE SWITCH TRIGGERED by nucleotide_slot[%d] at y=%.1f (t=%s) <<<" % [i, nucleotide_y, Time.get_ticks_msec()])

		match nucleotide_transfer_state[i]:
			NucleotideTransferState.WAITING:
				if nucleotide_max_y_reached[i] >= straight_y + max_loop_depth * armed_depth_fraction:
					nucleotide_transfer_state[i] = NucleotideTransferState.ARMED
					print("[t=%s] nucleotide_slot[%d] ARMED (max_y_reached=%.1f)" % [Time.get_ticks_msec(), i, nucleotide_max_y_reached[i]])
			NucleotideTransferState.ARMED:
				if nucleotide_y < new_bottom_template_y:
					nucleotide_transfer_state[i] = NucleotideTransferState.TRANSFERRED
					print("[t=%s] nucleotide_slot[%d] TRANSFERRED (y=%.1f)" % [Time.get_ticks_msec(), i, nucleotide_y])
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
					print("[t=%s] nucleotide_slot[%d] ENTERED polymerase zone (moving_left=%s x=%.1f prev_x=%.1f)" % [
						Time.get_ticks_msec(), i, moving_left, current_x, nucleotide_previous_x[i]
					])
			ProximityState.INSIDE:
				if distance_to_polymerase > synthesis_outside_threshold:
					nucleotide_proximity_state[i] = ProximityState.OUTSIDE
					nucleotide_crossing_count[i] += 1
					print("[t=%s] nucleotide_slot[%d] GENUINE PASS #%d push=%s (distance=%.1f)" % [
						Time.get_ticks_msec(), i, nucleotide_crossing_count[i],
						nucleotide_entered_push_direction[i], distance_to_polymerase
					])
					if nucleotide_entered_push_direction[i] and nucleotide_synthesis_state[i] == SynthesisCrossState.NONE:
						nucleotide_synthesis_state[i] = SynthesisCrossState.COMPLETED
						synthesized_bases[i] = _spawn_complement_base(i)
						hydrogen_bonds[i] = _spawn_hydrogen_bonds(i)
						print("[t=%s] nucleotide_slot[%d] COMPLETED on pass #%d PUSH" % [
							Time.get_ticks_msec(), i, nucleotide_crossing_count[i]
						])

		nucleotide_previous_x[i] = current_x

	for i in range(template_strand_bottom.size()):
		var nucleotide_slot = template_strand_bottom[i]
		var x = nucleotide_original_x[i]
		var in_loop = (phase != Phase.DONE) and x >= population_left_edge and x <= helicase_x

		if in_loop and not nucleotide_slot.is_in_group(LOOP_POPULATION_GROUP):
			nucleotide_slot.add_to_group(LOOP_POPULATION_GROUP)
		elif not in_loop and nucleotide_slot.is_in_group(LOOP_POPULATION_GROUP):
			nucleotide_slot.remove_from_group(LOOP_POPULATION_GROUP)

	# Wobble + backbone in one pass.
	# Compute the sine offset for each slot, apply it to the nitrogen_base
	# local y, and include it directly in the backbone point -- one loop,
	# no intermediate array needed.
	var wobble_t = Time.get_ticks_msec() * 0.001
	var backbone_points = PackedVector2Array()
	for i in range(template_strand_bottom.size()):
		var nucleotide_slot = template_strand_bottom[i]
		var slot_y = nucleotide_slot.position.y

		# Wobble: only on flat sections, off in the loop and at DONE.
		var wobble_y = 0.0
		if wobble_amplitude > 0.0:
			var near_top = abs(slot_y - straight_y) < wobble_amplitude * 4.0
			var near_bottom = abs(slot_y - new_bottom_template_y) < wobble_amplitude * 4.0
			if near_top or near_bottom:
				wobble_y = sin(wobble_t * wobble_speed * TAU + i * wobble_phase_offset) * wobble_amplitude
		nucleotide_bases[i].position.y = wobble_y

		# Backbone delta (which side of the strand the line runs along).
		var on_rail_visual = abs(slot_y - straight_y) < 1.0
		var on_new_bottom = abs(slot_y - new_bottom_template_y) < 1.0
		var target_delta: float
		if on_rail_visual:
			target_delta = backbone_offset_distance
		elif on_new_bottom:
			target_delta = -backbone_offset_distance
		else:
			target_delta = backbone_offset_distance

		nucleotide_backbone_delta[i] = lerp(nucleotide_backbone_delta[i], target_delta, clamp(backbone_offset_smoothing_speed * delta, 0.0, 1.0))
		backbone_points.append(Vector2(nucleotide_slot.position.x, slot_y + nucleotide_backbone_delta[i] + wobble_y))

	backbone_line.points = backbone_points
	backbone_line.width = backbone_line_width

	# Track synthesized complement bases: mirror the template nucleotide's
	# x position and wobble every frame. y is fixed at
	# new_bottom_template_y + dna_ribbons_gap, plus the template's wobble.
	# Backbone points include a lerped offset (below the base center)
	# matching the template backbone pattern.
	var new_strand_points = PackedVector2Array()
	for i in range(synthesized_bases.size()):
		if synthesized_bases[i] != null:
			var template_slot = template_strand_bottom[i]
			# wobble_y is the local y offset already applied to the template base.
			var wobble_y = nucleotide_bases[i].position.y
			# World position: template x, fixed strand y + gap + wobble.
			var world_x = template_slot.position.x
			var world_y = new_bottom_template_y + dna_ribbons_gap + wobble_y
			synthesized_bases[i].position = Vector2(world_x, world_y)
			# Hydrogen bond container follows the same x and wobble y,
			# anchored at the template strand y so bonds span downward
			# to the complement base in local space.
			if hydrogen_bonds[i] != null:
				hydrogen_bonds[i].position = Vector2(world_x, new_bottom_template_y + wobble_y)
			# Backbone offset below the base center.
			new_strand_backbone_delta[i] = lerp(
				new_strand_backbone_delta[i],
				backbone_offset_distance,
				clamp(backbone_offset_smoothing_speed * delta, 0.0, 1.0)
			)
			new_strand_points.append(Vector2(world_x, world_y + new_strand_backbone_delta[i]))
	new_strand_backbone_line.points = new_strand_points
	new_strand_backbone_line.width = backbone_line_width
	_update_bond_marks_new_strand(new_strand_points)

	_update_bond_marks(backbone_points)

func _spawn_hydrogen_bonds(template_index: int) -> Node2D:
	# Determine bond count and color from the template base type.
	# A and T form 2 hydrogen bonds; C and G form 3.
	var base_type = dna_sequence.sequence[template_index]
	var bond_count = 3 if (base_type == "C" or base_type == "G") else 2
	var bond_color = cg_bond_color if (base_type == "C" or base_type == "G") else at_bond_color

	# Container node: position is updated every frame in _process() to
	# follow the template slot x and wobble y. The individual Line2D
	# children are static in local space -- they span from y=0 (template
	# strand) to y=dna_ribbons_gap (complement strand).
	var container = Node2D.new()

	# Space the lines evenly, centered on x=0 in local space.
	var total_width = (bond_count - 1) * hydrogen_bond_spacing
	var start_x = -total_width / 2.0

	for b in range(bond_count):
		var line = Line2D.new()
		var lx = start_x + b * hydrogen_bond_spacing
		line.add_point(Vector2(lx, 0.0))
		line.add_point(Vector2(lx, dna_ribbons_gap))
		line.default_color = bond_color
		line.width = hydrogen_bond_width
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		container.add_child(line)

	hydrogen_bonds_container.add_child(container)
	return container

func _spawn_complement_base(template_index: int) -> Node2D:
	# Instantiate a full NewNitrogenBaseScene so the complement base
	# gets the correct base type, color, and label automatically.
	# Position is set here for the first frame only; the tracking loop
	# in _process() owns position every subsequent frame.
	var base = NewNitrogenBaseScene.instantiate()
	base.set_base_type(dna_sequence.get_complement(template_index))
	base.position = Vector2(
		template_strand_bottom[template_index].position.x,
		0.0  # tracking loop sets y every frame relative to new_bottom_template_y + dna_ribbons_gap
	)
	base.z_index = 2
	add_child(base)
	return base

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
		if segment.length() > 0.0:
			mark.rotation = segment.angle()
			mark.visible = true
		else:
			mark.visible = false

func _update_bond_marks_new_strand(points: PackedVector2Array):
	# Identical logic to _update_bond_marks but uses new_strand_bond_marks
	# and _create_bond_mark_sprite_reversed() so diamonds point right (→)
	# for the antiparallel new strand.
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
		if segment.length() > 0.0:
			mark.rotation = segment.angle()
			mark.visible = true
		else:
			mark.visible = false

func _create_bond_mark_sprite_reversed() -> Node2D:
	# Mirror of _create_bond_mark_sprite(): the magenta inset is on the
	# RIGHT side instead of the left, so the ">" shape becomes "<" in
	# local space -- but since these marks are rotated to follow rightward
	# segments, they render as ">" on screen, correct for the antiparallel
	# new strand pointing right (→).
	var holder = Node2D.new()
	var h = backbone_line_width / 2.0
	var w = bond_mark_width

	var black_diamond = Polygon2D.new()
	black_diamond.polygon = PackedVector2Array([
		Vector2(w / 2.0, 0),
		Vector2(0, -h),
		Vector2(-w / 2.0, 0),
		Vector2(0, h),
	])
	black_diamond.color = bond_mark_black_color
	holder.add_child(black_diamond)

	var back_inset = bond_mark_back_inset
	var magenta_diamond = Polygon2D.new()
	magenta_diamond.polygon = PackedVector2Array([
		Vector2(w / 2.0 - back_inset, 0),
		Vector2(0, -h),
		Vector2(-w / 2.0, 0),
		Vector2(0, h),
	])
	magenta_diamond.color = backbone_color
	holder.add_child(magenta_diamond)

	holder.z_index = 1
	add_child(holder)
	return holder

func _create_bond_mark_sprite() -> Node2D:
	var holder = Node2D.new()
	var h = backbone_line_width / 2.0
	var w = bond_mark_width

	var black_diamond = Polygon2D.new()
	black_diamond.polygon = PackedVector2Array([
		Vector2(w / 2.0, 0),
		Vector2(0, -h),
		Vector2(-w / 2.0, 0),
		Vector2(0, h),
	])
	black_diamond.color = bond_mark_black_color
	holder.add_child(black_diamond)

	var back_inset = bond_mark_back_inset
	var magenta_diamond = Polygon2D.new()
	magenta_diamond.polygon = PackedVector2Array([
		Vector2(w / 2.0, 0),
		Vector2(0, -h),
		Vector2(-w / 2.0 + back_inset, 0),
		Vector2(0, h),
	])
	magenta_diamond.color = backbone_color
	holder.add_child(magenta_diamond)

	holder.z_index = 1
	add_child(holder)
	return holder

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
		Vector2.ZERO
	)
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
	poly.color = synthesis_circle_color
	synthesis_circle.add_child(poly)

	var synthesis_collision_shape = synthesis_area.get_node("SynthesisCollisionShape")
	var circle_shape = CircleShape2D.new()
	circle_shape.radius = synthesis_circle_radius
	synthesis_collision_shape.shape = circle_shape
	synthesis_area.monitoring = true
	synthesis_area.monitorable = true
	synthesis_area.area_entered.connect(_on_synthesis_area_entered)
	print("[SETUP] synthesis_area ready: monitoring=%s monitorable=%s shape_radius=%.1f collision_layer=%d collision_mask=%d" % [
		synthesis_area.monitoring, synthesis_area.monitorable, circle_shape.radius,
		synthesis_area.collision_layer, synthesis_area.collision_mask
	])

func _on_synthesis_area_entered(area: Area2D):
	print("[t=%s] SYNTHESIS AREA ENTERED by: %s" % [Time.get_ticks_msec(), area.name])

	if not area.name.begins_with("NucleotideArea_"):
		return
	var nucleotide_index = int(area.name.substr("NucleotideArea_".length()))
	if nucleotide_index < 0 or nucleotide_index >= template_strand_bottom.size():
		return

	var nucleotide_slot = template_strand_bottom[nucleotide_index]
	if not nucleotide_slot.is_in_group(UNZIPPED_POPULATION_GROUP):
		nucleotide_slot.add_to_group(UNZIPPED_POPULATION_GROUP)

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
		nitrogen_base.set_base_type(dna_sequence.sequence[i])

		rail_path.add_child(nucleotide_slot)

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
		nucleotide_backbone_delta.append(backbone_offset_distance)
		synthesized_bases.append(null)
		new_strand_backbone_delta.append(backbone_offset_distance)
		hydrogen_bonds.append(null)
