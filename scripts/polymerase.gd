extends CharacterBody2D

@export var is_leading: bool = true
@export var nitrogen_base_scene: PackedScene

var template_strand: DnaStrand
var bases_bound_in_fragment: int = 0
var is_waiting_for_binding: bool = true
var is_processing: bool = false
var is_detaching: bool = false
var current_target = null
var move_tween: Tween
var current_fragment_target_index: int = -1

const LABEL_W: float = 110.0
const LABEL_H: float = 30.0
const RADIUS: float = 15.0
const MOVE_SPEED: float = 120.0

func _ready():
	add_to_group("polymerases")
	add_to_group("highlightable") # Allows it to be dimmed
	
	# Join the specific highlight group based on its type
	if is_leading:
		add_to_group("leading_poly_highlight")
	else:
		add_to_group("lagging_poly_highlight")
	
	# Set the initial color
	_update_enzyme_color()	
	# Listen for theme changes
	if ThemeManager:
		ThemeManager.theme_changed.connect(_update_enzyme_color)

func _update_enzyme_color():
	var new_color = ThemeManager.enzyme_polymerase_color

func _physics_process(delta):
	# DEBUG: Print once every 2 seconds (120 physics frames at 60fps)
	if Engine.get_physics_frames() % 120 == 0:
		var cam = get_viewport().get_camera_2d()
		var cam_level = cam.current_zoom_level if cam else -1
		print("[%s] POLY DEBUG | CamLevel: %d | MyPos: %s" % [Time.get_ticks_msec(), cam_level, global_position])

	var rules = SimulationManager.current_rules
	if not rules or rules.mode != "DNA Repl":
		return
		
	# CASCADE EFFECT 1: If this specific polymerase is disabled, detach
	if is_leading and not rules.enable_leading_polymerase and not is_detaching:
		_trigger_detachment()
		return
	if not is_leading and not rules.enable_lagging_polymerase and not is_detaching:
		_trigger_detachment()
		return
		
	# CASCADE EFFECT 2: If Helicase is disabled, polymerases cannot function (no unzipped template)
	if not rules.enable_helicase and not is_detaching:
		_trigger_detachment()
		return

	if not rules.is_running:
		return

	#Use group lookup instead of hardcoded node name to avoid Godot auto-renaming issues
	var helicase = get_tree().get_first_node_in_group("helicases")
	var helicase_x = helicase.position.x if helicase else 99999.0 
	var helicase_y = helicase.position.y if helicase else 0.0

	if is_processing or is_detaching:
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
				
				var mid_offset_y = -120.0 if template_strand.is_top_strand else 120.0
				var target_pos = Vector2(target_base.original_pos.x, target_base.original_pos.y + mid_offset_y)
				
				if move_tween:
					move_tween.kill()
				move_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				move_tween.tween_property(self, "position", target_pos, 0.3)
		else:
			is_waiting_for_binding = false
			if current_target != null:
				current_target.is_target = false
				current_target = null
				
			if helicase:
				if helicase.position.x >= helicase.end_x:
					_trigger_detachment()
					return 
				
				var follow_x = helicase_x - 40.0
				var follow_y = helicase_y + (-120.0 if template_strand.is_top_strand else 120.0)
				position.x = move_toward(position.x, follow_x, MOVE_SPEED * 1.5 * delta)
				position.y = move_toward(position.y, follow_y, MOVE_SPEED * 1.5 * delta)

func _trigger_detachment():
	if is_detaching:
		return
	is_detaching = true
	is_waiting_for_binding = false
	current_fragment_target_index = -1
	
	var drift_direction = -1.0 if template_strand.is_top_strand else 1.0
	var detach_pos = Vector2(position.x, position.y + (drift_direction * 80.0))
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(self, "position", detach_pos, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 1.2)

func request_binding(nucleotide):
	var rules = SimulationManager.current_rules
	if not is_waiting_for_binding or is_processing or is_detaching or not rules.is_running:
		return
	
	var helicase = get_tree().get_first_node_in_group("helicases")
	var helicase_x = helicase.position.x if helicase else 99999.0
	var exposed = template_strand.get_exposed_bases(helicase_x)
	var target_base = _get_target_base(exposed)
			
	if target_base == null:
		return
		
	var needed_type = _get_complement(target_base.base_type)
	if nucleotide.base_type == needed_type:
		approve_binding(nucleotide, target_base)
	else:
		nucleotide.reject()
		# SHAKE: Impact feedback for rejecting a wrong base!
		_trigger_camera_shake(rules.shake_reject_strength if rules else 0.5, rules.shake_reject_decay if rules else 15.0)

func approve_binding(nucleotide, target_base):
	is_waiting_for_binding = false
	is_processing = true
	if current_target != null:
		current_target.is_target = false
		current_target = null
		
	target_base.is_bound = true
	var offset_y = -160.0 if template_strand.is_top_strand else 160.0
	var snap_pos = Vector2(target_base.original_pos.x, target_base.original_pos.y + offset_y)
	
	nucleotide.freeze = true
	nucleotide.linear_velocity = Vector2.ZERO
	nucleotide.angular_velocity = 0.0
	
	var tween = create_tween()
	tween.tween_property(nucleotide, "global_position", self.global_position, 0.1)
	tween.tween_property(nucleotide, "global_position", snap_pos, 0.15)
	tween.tween_callback(_on_binding_complete.bind(nucleotide, target_base, snap_pos))

func _on_binding_complete(nucleotide, target_base, snap_pos):
	target_base.partner_base = nucleotide
	nucleotide.partner_base = target_base
	nucleotide.finalize_bind(snap_pos)
	
	# SHAKE: Impact feedback for successfully building the strand!
	var rules = SimulationManager.current_rules
	_trigger_camera_shake(rules.shake_approve_strength if rules else 0.25, rules.shake_approve_decay if rules else 10.0)
	
	if template_strand.is_top_strand:
		if target_base == template_strand.bases[0]: _spawn_marker("5'", snap_pos.x - 35.0, snap_pos.y)
		if target_base == template_strand.bases[-1]: _spawn_marker("3'", snap_pos.x + 35.0, snap_pos.y)
	else:
		if target_base == template_strand.bases[-1]: _spawn_marker("5'", snap_pos.x + 35.0, snap_pos.y)
		if target_base == template_strand.bases[0]: _spawn_marker("3'", snap_pos.x - 35.0, snap_pos.y)
		
	bases_bound_in_fragment += 1
	if not is_leading and bases_bound_in_fragment >= 6:
		bases_bound_in_fragment = 0
		current_fragment_target_index = -1
		
	is_processing = false
	is_waiting_for_binding = true

func _get_target_base(exposed: Array):
	if is_leading:
		for base in exposed:
			if not base.is_bound and base.state == NitrogenBase.State.TEMPLATE:
				return base
		return null
	else:
		if current_fragment_target_index == -1:
			for i in range(exposed.size() - 1, -1, -1):
				if not exposed[i].is_bound and exposed[i].state == NitrogenBase.State.TEMPLATE:
					current_fragment_target_index = i
					break
		
		if current_fragment_target_index != -1 and current_fragment_target_index < exposed.size():
			if not exposed[current_fragment_target_index].is_bound:
				return exposed[current_fragment_target_index]
			else:
				current_fragment_target_index -= 1
				while current_fragment_target_index >= 0:
					if not exposed[current_fragment_target_index].is_bound and exposed[current_fragment_target_index].state == NitrogenBase.State.TEMPLATE:
						return exposed[current_fragment_target_index]
					current_fragment_target_index -= 1
				
				current_fragment_target_index = -1
				for i in range(exposed.size() - 1, -1, -1):
					if not exposed[i].is_bound and exposed[i].state == NitrogenBase.State.TEMPLATE:
						current_fragment_target_index = i
						return exposed[i]
	return null

func _spawn_marker(marker_type: String, pos_x: float, pos_y: float):
	var marker = nitrogen_base_scene.instantiate()
	marker.base_type = marker_type
	marker.state = NitrogenBase.State.TEMPLATE
	marker.make_template()
	marker.freeze = true
	marker.linear_velocity = Vector2.ZERO
	marker.angular_velocity = 0.0
	marker.position = Vector2(pos_x, pos_y)
	marker.original_pos = marker.position
	marker._apply_appearance()
	marker.queue_redraw()
	
	# CRITICAL FIX: Add dynamically spawned markers to the cleanup group!
	marker.add_to_group("sim_objects")
	
	get_parent().add_child(marker)

func _get_complement(base: String) -> String:
	match base:
		"A": return "T"
		"T": return "A"
		"C": return "G"
		"G": return "C"
	return "A"

func _draw():
	var current_separation = DnaStrand.MAX_SEPARATION
	var clamp_h = current_separation * 0.3 
	var clamp_w = 30.0
	var label_w = 110.0
	var label_h = 30.0
	var radius = 15.0
	
	draw_rect(Rect2(-clamp_w/2, -clamp_h/2, clamp_w, clamp_h), ThemeManager.enzyme_polymerase_color)
	draw_circle(Vector2(0, -clamp_h/2), radius, ThemeManager.enzyme_polymerase_color)
	draw_circle(Vector2(0, clamp_h/2), radius, ThemeManager.enzyme_polymerase_color)
	draw_rect(Rect2(-label_w/2, -label_h/2, label_w, label_h), ThemeManager.enzyme_polymerase_color)
	draw_circle(Vector2(-label_w/2, 0), radius, ThemeManager.enzyme_polymerase_color)
	draw_circle(Vector2(label_w/2, 0), radius, ThemeManager.enzyme_polymerase_color)

func _trigger_camera_shake(base_strength: float, decay: float = 10.0):
	var cam = get_viewport().get_camera_2d()
	if cam and cam.has_method("trigger_shake"):
		cam.trigger_shake(base_strength, decay)
