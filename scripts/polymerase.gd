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

# FACTORY MODEL: Lagging polymerase stays tethered to the replisome and only
# advances in discrete steps when an Okazaki fragment completes, rather than
# continuously chasing the helicase (which is what the leading polymerase does).
var factory_anchor_x: float = 0.0
var factory_anchor_initialized: bool = false
var anchor_tween: Tween
var _last_supply_check_frame: int = -1

# LOOP LEFT EDGE: distinct from factory_anchor_x (which is where the
# polymerase SPRITE sits, jumping forward only every 6 bases). This tracks
# where the loop's actual geometric left boundary is -- it advances by one
# BASE_SPACING step on EVERY individual successful bind, since synthesis
# (and thus "how much template has been consumed into the loop") happens
# continuously, not just at fragment boundaries. The curve math in
# dna_strand.gd anchors to this instead of factory_anchor_x.
var loop_left_edge_x: float = 0.0
var loop_left_edge_initialized: bool = false

const LABEL_W: float = 110.0
const LABEL_H: float = 30.0
const RADIUS: float = 15.0
const MOVE_SPEED: float = 120.0
const FACTORY_OFFSET: float = 150.0 # Distance the anchor trails behind the helicase
const FRAGMENT_ADVANCE: float = 6 * 35.0 # Okazaki fragment length (6 bases * spacing), matches bases_bound_in_fragment threshold

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

	# FACTORY MODEL: Set the lagging polymerase's initial anchor once we have a
	# real helicase position to anchor relative to.
	if not is_leading and not factory_anchor_initialized and helicase:
		factory_anchor_x = helicase_x - FACTORY_OFFSET
		factory_anchor_initialized = true
		# Loop's left edge starts at the same place the polymerase does --
		# nothing's been synthesized yet, so there's no "consumed" template.
		loop_left_edge_x = factory_anchor_x
		loop_left_edge_initialized = true

	if is_processing or is_detaching:
		return

	if template_strand:
		var exposed = template_strand.get_exposed_bases(helicase_x)
		var target_base = _get_target_base(exposed)
				
		if target_base != null:
			is_waiting_for_binding = true

			# REDIRECT MECHANIC: we know exactly which base type is needed
			# right now -- check if one is already organically nearby; if
			# not, redirect (or as a rare fallback, spawn) one instead of
			# leaving the polymerase to wait on pure Brownian luck.
			var needed_type = _get_complement(target_base.base_type)
			_ensure_nucleotide_supply(needed_type)

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
				
				# POST-DETACH Y FIX: once the helicase starts detaching, it
				# tweens its own position.y upward (drift-away animation) --
				# but this code was still reading helicase.position.y live
				# every frame to compute follow_y, so the polymerase kept
				# chasing the helicase's y as it drifted off, instead of
				# detaching itself promptly. Freeze follow_y at the last
				# good value once the helicase is no longer a valid
				# reference point. (helicase.position.x >= end_x above
				# already triggers our own detachment in the common case,
				# but this branch only runs when target_base == null --
				# this check covers the gap for whichever frame order
				# leaves us here with a still-valid target_base.)
				if helicase.is_detaching:
					_trigger_detachment()
					return

				var follow_y = helicase_y + (-120.0 if template_strand.is_top_strand else 120.0)

				if is_leading:
					# LEADING STRAND: continuously chases the helicase, no looping needed.
					var follow_x = helicase_x - 40.0
					position.x = move_toward(position.x, follow_x, MOVE_SPEED * 1.5 * delta)
					position.y = move_toward(position.y, follow_y, MOVE_SPEED * 1.5 * delta)
				else:
					# LAGGING STRAND (Factory/Trombone model): stays tethered near
					# factory_anchor_x instead of tracking the helicase every frame.
					# The anchor itself only advances in discrete steps (see
					# _advance_factory_anchor), so the template loops out between
					# this position and the helicase as the fork progresses.
					# JOLT FIX: while the anchor tween is running, let it own
					# position.x exclusively -- move_toward and the tween writing
					# to the same property on the same frame was causing the jolt.
					var anchor_tween_running = anchor_tween != null and anchor_tween.is_running()
					if not anchor_tween_running:
						var clamped_anchor_x = min(factory_anchor_x, helicase_x - 20.0)
						position.x = move_toward(position.x, clamped_anchor_x, MOVE_SPEED * delta)
					position.y = move_toward(position.y, follow_y, MOVE_SPEED * delta)

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
		if target_base == template_strand.bases[0]: _spawn_marker("5'", snap_pos.x - 35.0, snap_pos.y, target_base)
		if target_base == template_strand.bases[-1]: _spawn_marker("3'", snap_pos.x + 35.0, snap_pos.y, target_base)
	else:
		if target_base == template_strand.bases[-1]: _spawn_marker("5'", snap_pos.x + 35.0, snap_pos.y, target_base)
		if target_base == template_strand.bases[0]: _spawn_marker("3'", snap_pos.x - 35.0, snap_pos.y, target_base)

	# LOOP LEFT EDGE: advance by one BASE_SPACING on every individual bind
	# (continuous), not just every 6th base. This is what makes the loop's
	# near end actually get pulled in by synthesis, rather than staying
	# pinned at a fixed point between the rarer fragment-jump events.
	if not is_leading:
		loop_left_edge_x += DnaStrand.BASE_SPACING
		# Never let the tracked edge run ahead of the polymerase's own
		# physical anchor -- it should trail behind/at factory_anchor_x,
		# not overtake it (that would mean "more consumed than exists").
		loop_left_edge_x = min(loop_left_edge_x, factory_anchor_x + FRAGMENT_ADVANCE)
		
	bases_bound_in_fragment += 1
	if not is_leading and bases_bound_in_fragment >= 6:
		bases_bound_in_fragment = 0
		current_fragment_target_index = -1
		# POST-HELICASE FIX: only advance the anchor if the helicase is still
		# active -- if it's faded/detached, the replisome no longer exists so
		# there's no biological reason to keep synthesizing or moving forward.
		var helicase = get_tree().get_first_node_in_group("helicases")
		if helicase and not is_detaching:
			_advance_factory_anchor()
		
	is_processing = false
	is_waiting_for_binding = true

func _advance_factory_anchor():
	# FACTORY MODEL: Called when an Okazaki fragment completes. The anchor
	# steps forward by one fragment length, and the polymerase visually
	# slides to the new position rather than snapping instantly -- this
	# reads as the discrete "fragment finished, loop releasing" event.
	factory_anchor_x += FRAGMENT_ADVANCE
	
	if anchor_tween:
		anchor_tween.kill()
	
	var follow_y = position.y
	var target_pos = Vector2(factory_anchor_x, follow_y)
	
	anchor_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	anchor_tween.tween_property(self, "position", target_pos, 0.4)

func _get_target_base(exposed: Array):
	if is_leading:
		for base in exposed:
			if not base.is_bound and base.state == NitrogenBase.State.TEMPLATE:
				return base
		return null
	else:
		if current_fragment_target_index == -1:
			# FRAGMENT-START FIX: previously this scanned from the absolute
			# rightmost exposed base (closest to the helicase), which could be
			# far ahead of where the polymerase is actually anchored -- causing
			# it to tween far forward to grab a base near the fork, then drift
			# back. Instead, start the new fragment from the base nearest to
			# factory_anchor_x (the polymerase's actual position), since that's
			# biologically where the next Okazaki fragment begins -- right where
			# the previous one just finished, not wherever has newly unzipped.
			var best_index = -1
			var best_dist = INF
			for i in range(exposed.size()):
				if not exposed[i].is_bound and exposed[i].state == NitrogenBase.State.TEMPLATE:
					var dist = abs(exposed[i].original_pos.x - factory_anchor_x)
					if dist < best_dist:
						best_dist = dist
						best_index = i
			current_fragment_target_index = best_index
		
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
				# Same anchor-relative fix as above: when a fragment is fully
				# exhausted and we need to find the start of the NEXT one,
				# search from factory_anchor_x outward rather than jumping to
				# the absolute rightmost exposed base near the helicase.
				var best_index = -1
				var best_dist = INF
				for i in range(exposed.size()):
					if not exposed[i].is_bound and exposed[i].state == NitrogenBase.State.TEMPLATE:
						var dist = abs(exposed[i].original_pos.x - factory_anchor_x)
						if dist < best_dist:
							best_dist = dist
							best_index = i
				if best_index != -1:
					current_fragment_target_index = best_index
					return exposed[best_index]
	return null

func _ensure_nucleotide_supply(needed_type: String):
	# THROTTLE: this does a group scan, which is cheap but not free -- no
	# need to run it more than ~10x/sec per polymerase, since "is a base
	# nearby" doesn't meaningfully change frame-to-frame. Lowered from 12 to
	# 6 frames (was ~5x/sec) for faster response after a stall.
	var frame = Engine.get_physics_frames()
	if frame - _last_supply_check_frame < 6:
		return
	_last_supply_check_frame = frame

	var free_bases = get_tree().get_nodes_in_group("free_nucleotides")
	var rules = SimulationManager.current_rules
	var radius = rules.binding_distance if rules else 80.0

	# 1. Is a correct-type base already organically within binding range?
	# If so, do nothing -- let natural Brownian motion handle it.
	for base in free_bases:
		if base.base_type == needed_type and not base.is_target:
			if global_position.distance_to(base.global_position) < radius:
				return

	# 2. REDIRECT: find the nearest correct-type base anywhere in the pool
	# and nudge it toward us instead of waiting on luck.
	var nearest: NitrogenBase = null
	var nearest_dist: float = INF
	for base in free_bases:
		if base.base_type == needed_type and not base.is_redirecting:
			var d = global_position.distance_to(base.global_position)
			if d < nearest_dist:
				nearest_dist = d
				nearest = base

	if nearest:
		nearest.start_redirect(global_position)
		return

	# 3. FALLBACK (rare): no correct-type base exists anywhere in the pool
	# right now. Spawn one, hidden behind an existing wrong-type base so it
	# doesn't visibly pop into existence.
	_spawn_hidden_nucleotide(needed_type, free_bases)

func _spawn_hidden_nucleotide(needed_type: String, free_bases: Array):
	if not nitrogen_base_scene:
		return

	# Find a decoy: any existing free base (any type) to spawn behind.
	# Prefer one reasonably close to us so the new base's approach reads
	# naturally once it separates from the decoy.
	var decoy_pos = global_position + Vector2(randf_range(-150, 150), randf_range(-150, 150))
	var nearest_dist: float = INF
	for base in free_bases:
		var d = global_position.distance_to(base.global_position)
		if d < nearest_dist:
			nearest_dist = d
			decoy_pos = base.global_position

	var new_base = nitrogen_base_scene.instantiate()
	new_base.base_type = needed_type
	new_base.state = NitrogenBase.State.FREE
	new_base.position = decoy_pos
	new_base.add_to_group("sim_objects")
	get_parent().add_child(new_base)
	new_base.start_redirect(global_position)

func _spawn_marker(marker_type: String, pos_x: float, pos_y: float, partner: NitrogenBase = null):
	var marker = nitrogen_base_scene.instantiate()
	marker.base_type = marker_type
	marker.position = Vector2(pos_x, pos_y)
	marker.original_pos = marker.position

	if partner:
		# LIVE TRACKING FIX: previously this marker was state=TEMPLATE,
		# frozen, with a position set once at spawn time and never updated
		# again -- so as the template base (and its loop) moved through the
		# trombone motion afterward, the marker stayed behind at its
		# original flat-strand position. Setting state=BOUND with
		# partner_base wired up means this marker flows through the exact
		# same live position-tracking already built for every other
		# new-strand base in new_strand_backbone.gd's
		# _update_active_fragment_positions() (derives position from
		# partner.position + curve-normal offset when on the loop) -- no
		# new tracking logic needed, just correct state/partner wiring.
		marker.state = NitrogenBase.State.BOUND
		marker.partner_base = partner
		marker.make_bound()
	else:
		# Fallback (shouldn't normally happen): no partner given, behave
		# like the old static marker.
		marker.state = NitrogenBase.State.TEMPLATE
		marker.make_template()
		marker.freeze = true
		marker.linear_velocity = Vector2.ZERO
		marker.angular_velocity = 0.0

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
