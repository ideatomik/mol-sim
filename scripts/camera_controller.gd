extends Camera2D

# References to the DNA strands (will be set from Main.gd or SimulationManager)
var top_strand: DnaStrand
var bottom_strand: DnaStrand

# Framing Rules
const LEVEL_0_WIDTH_PERCENTAGE: float = 0.80 # DNA width takes up 80% of screen
const LEVEL_0_MIN_HEIGHT_PERCENTAGE: float = 0.15 # DNA height must be at least 15% of screen

func _ready():
	# Optional: If your strands are ready immediately, you can call this here.
	# Otherwise, we will call it from your main simulation script once DNA is built.
	pass

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
