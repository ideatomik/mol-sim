extends Node2D

# The radius of the nitrogen bases. Used to offset the backbone line so it sits 
# on the edge of the bases, not through their centers.
const BASE_RADIUS: float = 15.0

# Tracks which gaps between Okazaki fragments have been welded by Ligase.
# When Ligase seals a gap, it adds the index of that gap to this array.
var sealed_gap_indices: Array[int] = []

func _ready():
	add_to_group("highlightable")
	# Listen for theme changes to redraw immediately
	if ThemeManager:
		ThemeManager.theme_changed.connect(queue_redraw)

func _process(delta):
	# Forces the node to redraw every frame. 
	# Note: We might want to optimize this later to only redraw when bases move, 
	# but for now, it ensures the backbone always follows the bases perfectly.
	queue_redraw()

func _draw():
	# 1. GATHER AND SORT BASES
	# We find all bound bases in the scene and separate them into top (leading) 
	# and bottom (lagging) strands based on their Y position relative to their template partner.
	var all_bases = get_tree().get_nodes_in_group("nitrogen_bases")
	
	var top_new_bases: Array[NitrogenBase] = []
	var bottom_new_bases: Array[NitrogenBase] = []
	
	for base in all_bases:
		if base.state == NitrogenBase.State.BOUND and base.partner_base != null:
			if base.position.y < base.partner_base.position.y:
				top_new_bases.append(base)
			else:
				bottom_new_bases.append(base)
				
	# Sort them by X position so we can draw lines from left to right.
	top_new_bases.sort_custom(func(a, b): return a.position.x < b.position.x)
	bottom_new_bases.sort_custom(func(a, b): return a.position.x < b.position.x)
	
	# 2. DRAW THE BACKBONES AND ARROWS
	# y_offset moves the line up (-BASE_RADIUS) or down (+BASE_RADIUS) to sit on the edge of the bases.
	# point_left determines the direction of the directional arrows (< or >).
	_draw_strand(top_new_bases, -BASE_RADIUS, false)  
	_draw_strand(bottom_new_bases, BASE_RADIUS, true) 

	# 3. DRAW ROUNDED TIPS
	# Adds a nice visual cap to the start and end of the newly synthesized strands.
	var width = ThemeManager.backbone_width if ThemeManager else 4.0
	var radius = width / 2.0
	var color = ThemeManager.backbone_color if ThemeManager else Color(0.6, 0.6, 0.6, 0.9)

	# Top strand tips
	if top_new_bases.size() > 0:
		var p_start = Vector2(top_new_bases[0].position.x, top_new_bases[0].position.y - BASE_RADIUS)
		var p_end = Vector2(top_new_bases[-1].position.x, top_new_bases[-1].position.y - BASE_RADIUS)
		draw_circle(p_start, radius, color)
		draw_circle(p_end, radius, color)

	# Bottom strand tips
	if bottom_new_bases.size() > 0:
		var p_start = Vector2(bottom_new_bases[0].position.x, bottom_new_bases[0].position.y + BASE_RADIUS)
		var p_end = Vector2(bottom_new_bases[-1].position.x, bottom_new_bases[-1].position.y + BASE_RADIUS)
		draw_circle(p_start, radius, color)
		draw_circle(p_end, radius, color)

# ==========================================
# CORE DRAWING LOGIC
# This is where the Trombone Loop will eventually live!
# ==========================================
func _draw_strand(bases: Array[NitrogenBase], y_offset: float, point_left: bool):
	if bases.size() < 2:
		return
		
	# Setup arrow shapes and colors from ThemeManager
	var s = ThemeManager.arrow_scale if ThemeManager else 1.0
	var arrow_right = PackedVector2Array([Vector2(-6*s, -5*s), Vector2(6*s, 0*s), Vector2(-6*s, 5*s)])
	var arrow_left = PackedVector2Array([Vector2(6*s, -5*s), Vector2(-6*s, 0*s), Vector2(6*s, 5*s)])
	var arrow_shape = arrow_left if point_left else arrow_right
	
	var arrow_color = ThemeManager.arrow_color if ThemeManager else Color(0.9, 0.9, 0.9, 0.8)
	var backbone_color = ThemeManager.backbone_color if ThemeManager else Color(0.6, 0.6, 0.6, 0.9)
	var nick_color = ThemeManager.nick_color if ThemeManager else Color(1.0, 0.3, 0.3, 0.9)
	var width = ThemeManager.backbone_width if ThemeManager else 4.0
		
	# Iterate through pairs of bases to draw the segments between them
	for i in range(bases.size() - 1):
		var b1 = bases[i]
		var b2 = bases[i+1]
		
		var p1 = Vector2(b1.position.x, b1.position.y + y_offset)
		var p2 = Vector2(b2.position.x, b2.position.y + y_offset)
		
		var angle = (p2 - p1).angle()
		var mid_point = (p1 + p2) / 2.0
		
		# CHECK: Are these bases close together (part of the same fragment)?
		if b1.position.distance_to(b2.position) < 50.0:
			# YES: Draw a continuous backbone line and an arrow.
			draw_line(p1, p2, backbone_color, width, true)
			
			var arrow_points = PackedVector2Array()
			for p in arrow_shape:
				arrow_points.append(mid_point + p.rotated(angle))
			draw_colored_polygon(arrow_points, arrow_color)
			
		else:
			# NO: There is a gap (nick) between Okazaki fragments.
			var nick_length = 10.0
			var is_sealed = sealed_gap_indices.has(i)
			
			if is_sealed:
				# If Ligase has welded it, draw it as a continuous line.
				draw_line(p1, p2, backbone_color, width, true)
				var arrow_points = PackedVector2Array()
				for p in arrow_shape:
					arrow_points.append(mid_point + p.rotated(angle))
				draw_colored_polygon(arrow_points, arrow_color)
			else:
				# If unsealed, draw a short red line to represent the nick.
				draw_line(mid_point - Vector2(nick_length, 0), mid_point + Vector2(nick_length, 0), nick_color, width * 0.75, true)

# Called by Ligase when it successfully welds a gap.
func seal_gap(gap_base_index: int):
	if not sealed_gap_indices.has(gap_base_index):
		sealed_gap_indices.append(gap_base_index)
		queue_redraw()

# Called by Ligase to find where it needs to work next.
func get_unsealed_gaps() -> Array[Dictionary]:
	var gaps: Array[Dictionary] = []
	var all_bases = get_tree().get_nodes_in_group("nitrogen_bases")
	var bottom_new_bases: Array[NitrogenBase] = []
	
	# Gather and sort bottom strand bases (Lagging strand)
	for base in all_bases:
		if base.state == NitrogenBase.State.BOUND and base.partner_base != null:
			if base.position.y > base.partner_base.position.y:
				bottom_new_bases.append(base)
				
	bottom_new_bases.sort_custom(func(a, b): return a.position.x < b.position.x)
	
	# Find gaps that are >= 50px apart and not yet sealed
	for i in range(bottom_new_bases.size() - 1):
		var b1 = bottom_new_bases[i]
		var b2 = bottom_new_bases[i+1]
		
		if b1.position.distance_to(b2.position) >= 50.0:
			if not sealed_gap_indices.has(i):
				var p1 = Vector2(b1.position.x, b1.position.y + BASE_RADIUS)
				var p2 = Vector2(b2.position.x, b2.position.y + BASE_RADIUS)
				var mid_point = (p1 + p2) / 2.0
				gaps.append({"position": mid_point, "index": i})
				
	return gaps
