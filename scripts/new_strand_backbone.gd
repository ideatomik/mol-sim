extends Node2D

const BASE_RADIUS: float = 15.0

var sealed_gap_indices: Array[int] = []

func _ready():
	add_to_group("highlightable")
	# Listen for theme changes to redraw immediately
	if ThemeManager:
		ThemeManager.theme_changed.connect(queue_redraw)

func _process(delta):
	queue_redraw()

func _draw():
	var all_bases = get_tree().get_nodes_in_group("nitrogen_bases")
	
	var top_new_bases: Array[NitrogenBase] = []
	var bottom_new_bases: Array[NitrogenBase] = []
	
	for base in all_bases:
		if base.state == NitrogenBase.State.BOUND and base.partner_base != null:
			if base.position.y < base.partner_base.position.y:
				top_new_bases.append(base)
			else:
				bottom_new_bases.append(base)
				
	top_new_bases.sort_custom(func(a, b): return a.position.x < b.position.x)
	bottom_new_bases.sort_custom(func(a, b): return a.position.x < b.position.x)
	
	# Draw the main backbone lines and arrows
	_draw_strand(top_new_bases, -BASE_RADIUS, false)  
	_draw_strand(bottom_new_bases, BASE_RADIUS, true) 

	# ==========================================
	# DRAW ROUNDED TIPS FOR NEW STRANDS
	# ==========================================
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

func _draw_strand(bases: Array[NitrogenBase], y_offset: float, point_left: bool):
	if bases.size() < 2:
		return
		
	# Scale arrow points dynamically
	var s = ThemeManager.arrow_scale if ThemeManager else 1.0
	var arrow_right = PackedVector2Array([Vector2(-6*s, -5*s), Vector2(6*s, 0*s), Vector2(-6*s, 5*s)])
	var arrow_left = PackedVector2Array([Vector2(6*s, -5*s), Vector2(-6*s, 0*s), Vector2(6*s, 5*s)])
	var arrow_shape = arrow_left if point_left else arrow_right
	
	var arrow_color = ThemeManager.arrow_color if ThemeManager else Color(0.9, 0.9, 0.9, 0.8)
	var backbone_color = ThemeManager.backbone_color if ThemeManager else Color(0.6, 0.6, 0.6, 0.9)
	var nick_color = ThemeManager.nick_color if ThemeManager else Color(1.0, 0.3, 0.3, 0.9)
	var width = ThemeManager.backbone_width if ThemeManager else 4.0
		
	for i in range(bases.size() - 1):
		var b1 = bases[i]
		var b2 = bases[i+1]
		
		var p1 = Vector2(b1.position.x, b1.position.y + y_offset)
		var p2 = Vector2(b2.position.x, b2.position.y + y_offset)
		
		if b1.position.distance_to(b2.position) < 50.0:
			draw_line(p1, p2, backbone_color, width, true) # <-- Uses centralized width
			
			var mid_point = (p1 + p2) / 2.0
			var arrow_points = PackedVector2Array()
			for p in arrow_shape:
				arrow_points.append(mid_point + p)
			draw_colored_polygon(arrow_points, arrow_color)
			
		else:
			var mid_point = (p1 + p2) / 2.0
			var nick_length = 10.0
			var is_sealed = sealed_gap_indices.has(i)
			
			if is_sealed:
				draw_line(p1, p2, backbone_color, width, true)
				var arrow_points = PackedVector2Array()
				for p in arrow_shape:
					arrow_points.append(mid_point + p)
				draw_colored_polygon(arrow_points, arrow_color)
			else:
				draw_line(mid_point - Vector2(nick_length, 0), mid_point + Vector2(nick_length, 0), nick_color, width * 0.75, true)

func seal_gap(gap_base_index: int):
	if not sealed_gap_indices.has(gap_base_index):
		sealed_gap_indices.append(gap_base_index)
		queue_redraw()

func get_unsealed_gaps() -> Array[Dictionary]:
	var gaps: Array[Dictionary] = []
	var all_bases = get_tree().get_nodes_in_group("nitrogen_bases")
	var bottom_new_bases: Array[NitrogenBase] = []
	
	for base in all_bases:
		if base.state == NitrogenBase.State.BOUND and base.partner_base != null:
			if base.position.y > base.partner_base.position.y:
				bottom_new_bases.append(base)
				
	bottom_new_bases.sort_custom(func(a, b): return a.position.x < b.position.x)
	
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
