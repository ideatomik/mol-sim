extends Node2D

var top_strand: DnaStrand
var bottom_strand: DnaStrand

const MAX_BOND_DISTANCE: float = 100.0 

func _ready():
	# Listen for theme changes to redraw immediately
	if ThemeManager:
		ThemeManager.theme_changed.connect(queue_redraw)

func _process(delta):
	queue_redraw()

func _draw():
	# 1. Draw bonds for the ORIGINAL template strands
	if top_strand and bottom_strand:
		for i in range(top_strand.bases.size()):
			var b1 = top_strand.bases[i]
			var b2 = bottom_strand.bases[i]
			_draw_bond_between(b1, b2)

	# 2. Draw bonds for NEWLY SYNTHESIZED strands
	var all_bases = get_tree().get_nodes_in_group("nitrogen_bases")
	for base in all_bases:
		if base.state == NitrogenBase.State.BOUND and base.partner_base != null:
			_draw_bond_between(base, base.partner_base)

func _draw_bond_between(b1: NitrogenBase, b2: NitrogenBase):
	# Only draw if they are close enough (not unzipped)
	if b1.position.distance_to(b2.position) > MAX_BOND_DISTANCE:
		return

	# Determine the color based on Highlighting
	var color = _get_bond_color(b1, b2)

	# Determine number of bonds: A-T = 2, C-G = 3
	var num_bonds = 2
	if (b1.base_type == "C" and b2.base_type == "G") or (b1.base_type == "G" and b2.base_type == "C"):
		num_bonds = 3

	# Calculate the direction and perpendicular vectors for offset drawing
	var dir = (b2.position - b1.position).normalized()
	var perp = Vector2(-dir.y, dir.x)
	
	var spacing = 4.0 # Distance between the parallel bond lines

	# Get thickness from ThemeManager
	var thickness = ThemeManager.bond_thickness if ThemeManager else 1.5

	if num_bonds == 2:
		# Draw 2 lines offset to the sides (DOUBLE BOND for A-T)
		var offset1 = perp * spacing
		var offset2 = perp * -spacing
		draw_line(b1.position + offset1, b2.position + offset1, color, thickness, true)
		draw_line(b1.position + offset2, b2.position + offset2, color, thickness, true)
	elif num_bonds == 3:
		# Draw 3 lines: one in the middle, two on the sides (TRIPLE BOND for C-G)
		var offset1 = perp * spacing
		var offset2 = perp * -spacing
		draw_line(b1.position, b2.position, color, thickness, true) # Middle
		draw_line(b1.position + offset1, b2.position + offset1, color, thickness, true) # Side 1
		draw_line(b1.position + offset2, b2.position + offset2, color, thickness, true) # Side 2

func _get_bond_color(b1: NitrogenBase, b2: NitrogenBase) -> Color:
	if not ThemeManager:
		return Color(1.0, 1.0, 1.0, 0.5) # Fallback color
		
	var active_groups = HighlightManager.current_active_groups
	var is_highlighting_pairs = active_groups.has("pair_AT") or active_groups.has("pair_CG")

	# If the user is highlighting specific pairs, evaluate this bond
	if is_highlighting_pairs:
		var is_AT = (b1.base_type == "A" and b2.base_type == "T") or (b1.base_type == "T" and b2.base_type == "A")
		var is_CG = (b1.base_type == "C" and b2.base_type == "G") or (b1.base_type == "G" and b2.base_type == "C")
		
		if active_groups.has("pair_AT") and is_AT:
			return ThemeManager.bond_highlight_color
		elif active_groups.has("pair_CG") and is_CG:
			return ThemeManager.bond_highlight_color
		else:
			return ThemeManager.bond_dimmed_color
	else:
		# If no pairs are highlighted, but something else is (like an enzyme), dim the bonds
		if active_groups.size() > 0:
			return ThemeManager.bond_dimmed_color
			
	return ThemeManager.bond_normal_color
