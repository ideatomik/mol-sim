extends CharacterBody2D

@export var is_leading: bool = false
@export var nitrogen_base_scene: PackedScene
@export var binding_distance: float = 120.0

var template_strand: DnaStrand
var bases_bound_in_primer: int = 0
var is_waiting_for_binding: bool = true
var is_processing: bool = false
var is_detaching: bool = false
var current_target = null
var move_tween: Tween
var current_primer_target_index: int = -1

const LABEL_W: float = 90.0
const LABEL_H: float = 25.0
const RADIUS: float = 12.5
const FILL_COLOR: Color = Color(0.9, 0.4, 0.9)
const MOVE_SPEED: float = 150.0
const PRIMER_LENGTH: int = 5

func _ready():
	add_to_group("primases")

func _physics_process(delta):
	var rules = SimulationManager.current_rules
	if not rules or rules.mode != "DNA Repl":
		return
	if not rules.is_running or is_detaching:
		return

	var helicase = get_parent().get_node_or_null("Helicase")
	var helicase_x = helicase.position.x if helicase else 0.0
	var helicase_y = helicase.position.y if helicase else 0.0

	if is_processing:
		return

	if template_strand:
		var exposed = template_strand.get_exposed_bases(helicase_x)
		var target_base = _get_target_base(exposed)
				
		if target_base != null:
			is_waiting_for_binding = true
			if current_target != target_base:
				if current_target != null:
					current_target.is_target = false
				current_target = target_base
				current_target.is_target = true
				
				var mid_offset_y = -120.0 if is_leading else 120.0
				var target_pos = Vector2(target_base.original_pos.x, target_base.original_pos.y + mid_offset_y)
				
				if move_tween:
					move_tween.kill()
				move_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				move_tween.tween_property(self, "position", target_pos, 0.2)
		else:
			is_waiting_for_binding = false
			if current_target != null:
				current_target.is_target = false
				current_target = null
				
			if helicase:
				if is_leading and bases_bound_in_primer >= PRIMER_LENGTH:
					_trigger_detachment()
					return
				
				var follow_x = helicase_x - 60.0
				var follow_y = helicase_y + (-120.0 if is_leading else 120.0)
				position.x = move_toward(position.x, follow_x, MOVE_SPEED * 1.5 * delta)
				position.y = move_toward(position.y, follow_y, MOVE_SPEED * 1.5 * delta)

func _get_target_base(exposed: Array):
	if is_leading:
		if bases_bound_in_primer == 0 and exposed.size() > 0:
			if not exposed[0].is_bound:
				return exposed[0]
		return null # Job done for leading strand
	else:
		if current_primer_target_index == -1:
			for i in range(exposed.size() - 1, -1, -1):
				if not exposed[i].is_bound:
					current_primer_target_index = i
					return exposed[i]
		
		if current_primer_target_index >= 0 and current_primer_target_index < exposed.size():
			if not exposed[current_primer_target_index].is_bound:
				return exposed[current_primer_target_index]
			else:
				current_primer_target_index -= 1
				while current_primer_target_index >= 0:
					if not exposed[current_primer_target_index].is_bound:
						return exposed[current_primer_target_index]
					current_primer_target_index -= 1
				current_primer_target_index = -1
				return null
	return null

func request_binding(nucleotide):
	var rules = SimulationManager.current_rules
	if not is_waiting_for_binding or is_processing or is_detaching or not rules.is_running:
		return
	
	if not nucleotide.is_rna:
		nucleotide.reject()
		return
	
	var helicase = get_parent().get_node_or_null("Helicase")
	var helicase_x = helicase.position.x if helicase else 0.0
	var exposed = template_strand.get_exposed_bases(helicase_x)
	var target_base = _get_target_base(exposed)
			
	if target_base == null:
		return
		
	var needed_type = _get_complement(target_base.base_type)
	if nucleotide.base_type == needed_type:
		approve_binding(nucleotide, target_base)
	else:
		nucleotide.reject()

func approve_binding(nucleotide, target_base):
	is_waiting_for_binding = false
	is_processing = true
	if current_target != null:
		current_target.is_target = false
		current_target = null
		
	target_base.is_bound = true
	var offset_y = -160.0 if is_leading else 160.0
	var snap_pos = Vector2(target_base.original_pos.x, target_base.original_pos.y + offset_y)
	
	nucleotide.freeze = true
	nucleotide.linear_velocity = Vector2.ZERO
	nucleotide.angular_velocity = 0.0
	
	var tween = create_tween()
	tween.tween_property(nucleotide, "global_position", self.global_position, 0.05)
	tween.tween_property(nucleotide, "global_position", snap_pos, 0.1)
	tween.tween_callback(_on_binding_complete.bind(nucleotide, target_base, snap_pos))

func _on_binding_complete(nucleotide, target_base, snap_pos):
	target_base.partner_base = nucleotide
	nucleotide.partner_base = target_base
	nucleotide.finalize_bind(snap_pos)
	bases_bound_in_primer += 1
	
	if bases_bound_in_primer >= PRIMER_LENGTH:
		_trigger_detachment()
	else:
		is_processing = false
		is_waiting_for_binding = true

func _trigger_detachment():
	is_detaching = true
	is_waiting_for_binding = false
	var drift_direction = -1.0 if is_leading else 1.0
	var detach_pos = Vector2(position.x, position.y + (drift_direction * 60.0))
	var tween = create_tween().set_parallel(true)
	tween.tween_property(self, "position", detach_pos, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.8)

func _get_complement(base: String) -> String:
	match base:
		"A": return "U"
		"T": return "A"
		"C": return "G"
		"G": return "C"
		"U": return "A"
	return "A"

func _draw():
	draw_rect(Rect2(-LABEL_W/2, -LABEL_H/2, LABEL_W, LABEL_H), FILL_COLOR)
	draw_circle(Vector2(-LABEL_W/2, 0), RADIUS, FILL_COLOR)
	draw_circle(Vector2(LABEL_W/2, 0), RADIUS, FILL_COLOR)
