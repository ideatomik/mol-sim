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
		# DEBUG: Print camera state every 2 seconds to avoid spam
	if Engine.get_physics_frames() % 120 == 0:
		print("[%s] CAM PROCESS | Level: %d | Zoom: %s | CamPos: %s | TargetPos: %s" % [
			Time.get_ticks_msec(), 
			current_zoom_level, 
			zoom, 
			global_position, 
			target_node.global_position if target_node else "None"
		])
	if target_node:
		# 1. ALWAYS lock the camera's Y position to the center of the DNA strands
		if top_strand and bottom_strand and top_strand.bases.size() > 0:
			var dna_center_y = (top_strand.bases[0].global_position.y + bottom_strand.bases[0].global_position.y) / 2.0
			global_position.y = lerp(global_position.y, dna_center_y, 5.0 * delta)

		# 2. Handle X tracking based on the zoom level
		if current_zoom_level == 1:
			# LEVEL 1: Context Tracking (Keep Polymerases in frame)
			var helicase_x = target_node.global_position.x
			var polymerases = get_tree().get_nodes_in_group("polymerases")
			
			var min_x = helicase_x
			var max_x = helicase_x
			
			# Find the leftmost and rightmost enzymes in the complex
			for pol in polymerases:
				if pol.global_position.x < min_x:
					min_x = pol.global_position.x
				if pol.global_position.x > max_x:
					max_x = pol.global_position.x
					
			# Calculate the center of the replication complex
			var center_x = (min_x + max_x) / 2.0
			
			# Smoothly glide the camera to that center
			global_position.x = lerp(global_position.x, center_x, 5.0 * delta)
			
		else:
			# LEVELS 2 & 3: Tight Tracking (Focus only on the Helicase)
			# We use lerp here too so the camera smoothly glides over to the Helicase
			# instead of snapping rigidly when you switch zoom levels.
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
