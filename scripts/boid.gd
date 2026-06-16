extends RigidBody2D

@export var speed: float = 150.0
var screen_size: Vector2

func _ready():
	screen_size = get_viewport_rect().size
	position = Vector2(randf() * screen_size.x, randf() * screen_size.y)
	
	# Ensure it's in the boids group for flocking calculations
	add_to_group("boids")
	
	# Read initial speed from rules so the slider affects spawn speed
	var rules = SimulationManager.current_rules
	var current_speed = rules.speed if rules else speed
	linear_velocity = Vector2.RIGHT.rotated(randf() * TAU) * current_speed

func _integrate_forces(state):
	var rules = SimulationManager.current_rules
	if not rules:
		return
		
	var current_speed = rules.speed
	
	if rules.mode == "Cardume":
		# --- FLOCKING BEHAVIOR (CARDUME) ---
		var flocking_force = Vector2.ZERO
		var boids = get_tree().get_nodes_in_group("boids")
		
		var separation = Vector2.ZERO
		var alignment = Vector2.ZERO
		var cohesion = Vector2.ZERO
		var total = 0
		
		for other in boids:
			if other == self:
				continue
				
			var dist = position.distance_to(other.position)
			if dist < rules.perception_radius and dist > 0:
				total += 1
				
				# 1. Separation: steer to avoid crowding
				var diff = position - other.position
				separation += diff.normalized() / dist
				
				# 2. Alignment: steer towards average heading
				if other is RigidBody2D:
					alignment += other.linear_velocity.normalized()
				
				# 3. Cohesion: steer towards average position
				cohesion += other.position
		
		if total > 0:
			separation = (separation / total) * rules.separation_weight
			alignment = (alignment / total) * rules.alignment_weight
			cohesion = ((cohesion / total) - position).normalized() * rules.cohesion_weight
			
			flocking_force = separation + alignment + cohesion
			
			# Apply the calculated flocking force to the velocity
			var desired_velocity = (linear_velocity.normalized() + flocking_force).normalized() * current_speed
			state.linear_velocity = desired_velocity
	else:
		# --- BOUNCING BEHAVIOR (LIVRE) ---
		# Just maintain constant speed, physics engine handles wall bounces
		var current_vel = state.linear_velocity
		if current_vel.length() > 0:
			state.linear_velocity = current_vel.normalized() * current_speed

func _draw():
	# Read size from rules so the UI slider affects it in real-time
	var rules = SimulationManager.current_rules
	var current_size = rules.size if rules else 1.0
	var radius = 10.0 * current_size
	
	# 1. Draw filled circle (Cyan)
	draw_circle(Vector2.ZERO, radius, Color.CYAN)
	
	# 2. Draw white border (matches NitrogenBase exactly: 2.0 thickness)
	draw_arc(Vector2.ZERO, radius, 0, TAU, 32, Color.WHITE, 2.0, true)
