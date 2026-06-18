extends Camera2D

# References to the DNA strands (will be set from Main.gd or SimulationManager)
var top_strand: DnaStrand
var bottom_strand: DnaStrand

var current_zoom_level: int = 0
var shake_strength: float = 0.0
var shake_decay: float = 10.0
var is_shake_enabled: bool = true

# ==========================================
# LEVEL 0: OVERWORLD
# ==========================================
const LEVEL_0_WIDTH_PERCENTAGE: float = 0.80 # DNA width takes up 80% of screen
const LEVEL_0_MIN_HEIGHT_PERCENTAGE: float = 0.15 # DNA height must be at least 15% of screen

# ==========================================
# LEVEL 1: CONTEXT & TRACKING
# ==========================================
var target_node: Node2D = null # The enzyme we are following

const LEVEL_1_HEIGHT_PERCENTAGE: float = 0.90 # Target height takes up 90% of screen

func _ready():
	# Enable Godot's built-in smooth camera tracking!
	position_smoothing_enabled = true
	position_smoothing_speed = 5.0 # Adjust this (1.0 = slow/lazy, 10.0 = snappy)

# Call this function when the DNA is fully built and ready to be framed
func setup_and_frame_level_0(top: DnaStrand, bottom: DnaStrand):
	top_strand = top
	bottom_strand = bottom
	
	# 1. Calculate the physical bounds of the DNA
	var bounds = _calculate_bounds()
	var dna_width = bounds.x2 - bounds.x1
	var dna_height = bounds.y2 - bounds.y1
	
	# 2. Calculate the Zoom based on the 80% Width Rule
	var screen_width = get_viewport_rect().size.x
	var screen_height = get_viewport_rect().size.y
	
	# How wide does the viewport need to be to make the DNA 80% of it?
	var required_viewport_width = dna_width / LEVEL_0_WIDTH_PERCENTAGE
	
	# Calculate the zoom multiplier
	var zoom_x = screen_width / required_viewport_width
	
	# 3. Apply the "Minimum Height" Safety Valve
	# If the DNA is super long (e.g., 512 bases), the width rule might zoom out too far,
	# making the DNA vertically too thin.
	var min_zoom_for_height = (dna_height / screen_height) / LEVEL_0_MIN_HEIGHT_PERCENTAGE
	
	# If our calculated zoom is smaller (more zoomed out) than the safety valve allows, clamp it.
	if zoom_x < min_zoom_for_height:
		zoom_x = min_zoom_for_height
		print("Camera: Safety valve triggered! Clamping zoom to maintain readable height.")
	else:
		print("Camera: Framing DNA at 80% width.")

	# Apply the zoom (keep X and Y uniform)
	zoom = Vector2(zoom_x, zoom_x)
	
	# 4. Center the Camera on the DNA
	var center_x = (bounds.x1 + bounds.x2) / 2.0
	var center_y = (bounds.y1 + bounds.y2) / 2.0
	global_position = Vector2(center_x, center_y)
	
	print("[%s] CAM: Level 0 Framed. Zoom: %s | Pos: %s" % [Time.get_ticks_msec(), zoom, global_position])

# Call this to enter Level 1 and start following an enzyme
func setup_level_1(target: Node2D, target_height: float, level: int = 1):
	# 'level' is declared right here in the parentheses above!
	current_zoom_level = level 
	target_node = target
	
	var screen_height = get_viewport_rect().size.y
	
	var required_viewport_height = target_height / LEVEL_1_HEIGHT_PERCENTAGE
	var zoom_y = screen_height / required_viewport_height
	
	zoom = Vector2(zoom_y, zoom_y)
	
	# Snap the camera's Y position to the target (Helicase) so it's perfectly centered
	global_position.y = target.global_position.y 
	
	print("[%s] CAM: Entered Level %d. Zoom: %s | Target: %s | CamPos: %s" % [Time.get_ticks_msec(), level, zoom, target.name, global_position])

func _calculate_bounds() -> Dictionary:
	var bounds = {}
	
	# Horizontal bounds [x1, x2] based on markers' GLOBAL positions
	if top_strand and top_strand.left_marker:
		bounds.x1 = top_strand.left_marker.global_position.x - 15.0 
	else:
		bounds.x1 = 0.0
		
	if top_strand and top_strand.right_marker:
		bounds.x2 = top_strand.right_marker.global_position.x + 15.0
	else:
		bounds.x2 = 100.0
		
	# Vertical bounds [y1, y2] based on the FIRST BASES' GLOBAL positions
	# This ensures we frame the actual DNA, not the (0,0) parent node!
	if top_strand and top_strand.bases.size() > 0:
		bounds.y1 = top_strand.bases[0].global_position.y - 15.0
	else:
		bounds.y1 = 0.0
		
	if bottom_strand and bottom_strand.bases.size() > 0:
		bounds.y2 = bottom_strand.bases[0].global_position.y + 15.0
	else:
		bounds.y2 = 100.0
		
	return bounds

# Calculates the total vertical height needed to see the original strands AND the new polymerase lanes
func calculate_helicase_level_1_height(top: DnaStrand, bottom: DnaStrand) -> float:
	if not top or not bottom or top.bases.size() == 0:
		return 300.0 # Fallback
		
	# Get the global Y position of the first base of both original strands
	var top_y = top.bases[0].global_position.y
	var bottom_y = bottom.bases[0].global_position.y
	
	# The polymerases are spawned 120px above the top strand and 120px below the bottom strand
	var polymerase_offset = 120.0 
	
	# Total height = Distance between original strands + space for top and bottom polymerases
	var total_height = (bottom_y - top_y) + (polymerase_offset * 2.0)
	
	return total_height

# Calculates the height needed to see ONLY the separated original strands
func calculate_helicase_level_2_height(top: DnaStrand, bottom: DnaStrand) -> float:
	if not top or not bottom or top.bases.size() == 0:
		return 200.0 # Fallback

	# 1. Original distance between strand centers
	var original_distance = bottom.bases[0].original_pos.y - top.bases[0].original_pos.y

	# 2. Distance they move apart (MAX_SEPARATION * 2 because they move in opposite directions)
	var total_separation = DnaStrand.MAX_SEPARATION * 2.0

	# 3. Height of the bases themselves (Top radius + Bottom radius)
	var base_height = DnaStrand.BASE_RADIUS * 2.0

	return original_distance + total_separation + base_height

# Called every frame to update the camera position
func _process(delta):
	# ==========================================
	# DYNAMIC TARGET SWITCHING
	# ==========================================
	if current_zoom_level > 0:
		var new_target = _get_highlighted_enzyme()
		
		if new_target != target_node:
			target_node = new_target
			
			# FIX: If user unselected the enzyme, zoom back out to Level 0!
			if not target_node:
				print("Camera: No enzyme highlighted. Returning to Level 0.")
				if top_strand and bottom_strand:
					setup_and_frame_level_0(top_strand, bottom_strand)
				return # Stop tracking logic for this frame
				
			print("Camera: Switched target to ", target_node.name)
	# ==========================================

	if target_node:
		# 1. Lock the camera's Y position to the SELECTED ENZYME
		global_position.y = lerp(global_position.y, target_node.global_position.y, 5.0 * delta)

		# 2. Handle X tracking based on the zoom level
		if current_zoom_level == 1:
			# LEVEL 1: Context Tracking
			var target_x = target_node.global_position.x
			var polymerases = get_tree().get_nodes_in_group("polymerases")
			
			var min_x = target_x
			var max_x = target_x
			
			for pol in polymerases:
				if pol.global_position.x < min_x:
					min_x = pol.global_position.x
				if pol.global_position.x > max_x:
					max_x = pol.global_position.x
					
			var center_x = (min_x + max_x) / 2.0
			global_position.x = lerp(global_position.x, center_x, 5.0 * delta)
			
		else:
			# LEVELS 2 & 3: Tight Tracking
			global_position.x = lerp(global_position.x, target_node.global_position.x, 5.0 * delta)

	# Handle Screen Shake
	if is_shake_enabled and shake_strength > 0.0:
		offset = Vector2(randf_range(-shake_strength, shake_strength), randf_range(-shake_strength, shake_strength))
		shake_strength = move_toward(shake_strength, 0.0, shake_decay * delta)
	else:
		offset = Vector2.ZERO

# Call this from enzymes when they do something impactful
func trigger_shake(base_strength: float, decay: float = 10.0):
	if not is_shake_enabled:
		return
		
	# Multiply the base strength by a factor depending on the zoom level
	var zoom_multiplier = 1.0
	match current_zoom_level:
		0: zoom_multiplier = 0.2  # Very subtle shake in overview
		1: zoom_multiplier = 0.5  # Moderate shake in context view
		2: zoom_multiplier = 1.0  # Strong shake in action zone
		3: zoom_multiplier = 2.0  # Violent shake in microscope view
		
	var final_strength = base_strength * zoom_multiplier
	shake_strength = max(shake_strength, final_strength)
	shake_decay = decay

# ==========================================
# SCROLL WHEEL ZOOM CONTROLS
# ==========================================

func _unhandled_input(event):
	# Listen for scroll wheel clicks
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_step_zoom(1)  # Zoom In
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_step_zoom(-1) # Zoom Out

func _step_zoom(direction: int):
	var target = _get_highlighted_enzyme()
	
	#Prevent crash if no enzyme is selected
	if not target:
		return 
	
	if direction > 0: # Zooming IN
		if current_zoom_level < 3:
			var next_level = current_zoom_level + 1
			var height = 300.0 # Default fallback
			
			# HELICASE MATH
			if target.is_in_group("helicases"):
				if next_level == 1 and has_method("calculate_helicase_level_1_height"):
					height = calculate_helicase_level_1_height(top_strand, bottom_strand)
				elif next_level == 2 and has_method("calculate_helicase_level_2_height"):
					height = calculate_helicase_level_2_height(top_strand, bottom_strand)
				elif next_level == 3 and has_method("calculate_both_strands_height"):
					height = calculate_both_strands_height() # <-- UPDATED
					
			# POLYMERASE MATH
			elif target.is_in_group("polymerases"):
				if next_level == 1 and has_method("calculate_polymerase_level_1_height"):
					height = calculate_polymerase_level_1_height(target)
				elif next_level == 2 and has_method("calculate_polymerase_level_2_height"):
					height = calculate_polymerase_level_2_height(target)
				elif next_level == 3 and has_method("calculate_both_strands_height"):
					height = calculate_both_strands_height() # <-- UPDATED
					
			# Apply the new level
			setup_level_1(target, height, next_level)
				
	else: # Zooming OUT
		if current_zoom_level > 0:
			var prev_level = current_zoom_level - 1
			if prev_level == 0:
				# Return to Overview
				if top_strand and bottom_strand:
					setup_and_frame_level_0(top_strand, bottom_strand)
			else:
				# Step down to previous level (using placeholder height for now)
				setup_level_1(target, 300.0, prev_level) 

# Finds which enzyme is currently highlighted in the UI
func _get_highlighted_enzyme() -> Node2D:
	if not HighlightManager: 
		return null
		
	var active_groups = HighlightManager.current_active_groups
	
	# Priority 1: Helicase
	if active_groups.has("helicase_highlight"):
		return get_tree().get_first_node_in_group("helicases")
		
	# Priority 2: Polymerases
	var polys = get_tree().get_nodes_in_group("polymerases")
	for pol in polys:
		if active_groups.has("leading_poly_highlight") and pol.is_leading:
			return pol
		if active_groups.has("lagging_poly_highlight") and not pol.is_leading:
			return pol
			
	# Priority 3: Ligase (Assuming the group name is "ligase_highlight")
	var ligases = get_tree().get_nodes_in_group("ligases")
	for lig in ligases:
		if active_groups.has("ligase_highlight"):
			return lig
			
	return null

# ==========================================
# POLYMERASE ZOOM PROFILES
# ==========================================

# Level 1: Context (Polymerase + Template Strand)
func calculate_polymerase_level_1_height(target: Node2D) -> float:
	if not target or not target.template_strand:
		return 250.0 # Fallback
		
	# Distance from the polymerase lane to the template strand (usually 120px)
	var distance_to_strand = abs(target.position.y - target.template_strand.bases[0].position.y)
	
	# Add the thickness of the strand and bases (approx 40px)
	return distance_to_strand + 40.0

# Level 2: Action Zone (Polymerase + Target Base)
func calculate_polymerase_level_2_height(target: Node2D) -> float:
	if not target or not target.template_strand:
		return 120.0 # Fallback
		
	# We want to see the polymerase and the immediate base it's hovering over.
	# This is roughly the distance from the polymerase center to the strand center.
	var distance_to_strand = abs(target.position.y - target.template_strand.bases[0].position.y)
	
	# Tighter frame, just the enzyme and the immediate binding site
	return distance_to_strand + 20.0

# Level 3: Microscope (The Base Pairing)
func calculate_polymerase_level_3_height(target: Node2D) -> float:
	# Extreme close-up. We just want to see two bases pairing up.
	# Two bases are roughly 30px tall each, plus a little padding.
	return 60.0 

# Calculates the height needed to see BOTH the top and bottom DNA strands
# Uses original_pos to ignore the dynamic "peeling" animation
func calculate_both_strands_height() -> float:
	if not top_strand or not bottom_strand or top_strand.bases.size() == 0:
		return 150.0 # Fallback
		
	# FIX: Use original_pos.y instead of global_position.y
	var top_y = top_strand.bases[0].original_pos.y
	var bottom_y = bottom_strand.bases[0].original_pos.y
	
	# Distance between the original strand centers + 40px of padding
	return (bottom_y - top_y) + 40.0
