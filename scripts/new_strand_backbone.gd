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
	# NEW: Physically move the active lagging strand bases into the loop shape
	# ORDERING NOTE: this reads partner_base.position / .is_on_loop, which are
	# set by dna_strand.gd's update_peel() -- called from helicase.gd's
	# _physics_process(). Godot runs all physics steps before _process() each
	# frame, so this is safe as-is, but if update_peel()'s caller ever moves
	# to _process(), this would need to read one frame behind instead.
	_update_active_fragment_positions()
	
	queue_redraw()

func _update_active_fragment_positions():
	var all_bases = get_tree().get_nodes_in_group("nitrogen_bases")
	var bottom_new_bases: Array[NitrogenBase] = []
	
	for base in all_bases:
		if base.state == NitrogenBase.State.BOUND and base.partner_base != null:
			var parent_strand = base.partner_base.get_parent()
			if parent_strand is DnaStrand and not parent_strand.is_top_strand:
				bottom_new_bases.append(base)
				
	# FIX: Sort by the TEMPLATE base's original X position. 
	# This keeps the order stable even when the loop moves the bases around!
	bottom_new_bases.sort_custom(func(a, b): return a.partner_base.original_pos.x < b.partner_base.original_pos.x)
	
	if bottom_new_bases.size() < 2:
		return

	# TROMBONE LOOP (synced to template): rather than computing a second,
	# independent loop curve, every new-strand base simply rides alongside
	# its template partner_base -- which dna_strand.gd's update_peel() has
	# already positioned correctly on the real loop curve. This guarantees
	# the new strand and template strand always agree, since they're the
	# same physical loop (base-paired the whole way), not two approximations
	# of it. See partner_base.is_on_loop / partner_base.loop_normal_angle.
	var on_loop_count = 0
	for base in bottom_new_bases:
		var partner = base.partner_base
		if partner.is_on_loop:
			on_loop_count += 1

	# DIAGNOSTIC: same 2s cadence as the other debug prints. Confirms whether
	# new-strand bases are actually inheriting is_on_loop from their template
	# partner at all -- if on_loop_count stays 0 while dna_strand.gd reports
	# loop:N > 0, the linkage between the two scripts is broken somewhere.
	if Engine.get_physics_frames() % 120 == 0:
		print("[%s] NEWSTRAND DEBUG | bottom_new_bases:%d on_loop:%d" % [
			Time.get_ticks_msec(), bottom_new_bases.size(), on_loop_count
		])

	for base in bottom_new_bases:
		var partner = base.partner_base
		if partner.is_on_loop:
			# On the curved part of the loop: offset outward along the
			# curve's local normal instead of a flat vertical offset, so the
			# new strand hugs the curve rather than cutting across it.
			var normal = Vector2.RIGHT.rotated(partner.loop_normal_angle)
			base.position = partner.position + normal * BASE_RADIUS
			
func _draw():
	# 1. GATHER AND SORT BASES
	# We find all bound bases in the scene and separate them into top (leading) 
	# and bottom (lagging) strands based on their Y position relative to their template partner.
	var all_bases = get_tree().get_nodes_in_group("nitrogen_bases")
	
	var top_new_bases: Array[NitrogenBase] = []
	var bottom_new_bases: Array[NitrogenBase] = []
	
	for base in all_bases:
		if base.state == NitrogenBase.State.BOUND and base.partner_base != null:
			var parent_strand = base.partner_base.get_parent()
			if parent_strand is DnaStrand and parent_strand.is_top_strand:
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
		
	var s = ThemeManager.arrow_scale if ThemeManager else 1.0
	var arrow_right = PackedVector2Array([Vector2(-6*s, -5*s), Vector2(6*s, 0*s), Vector2(-6*s, 5*s)])
	var arrow_left = PackedVector2Array([Vector2(6*s, -5*s), Vector2(-6*s, 0*s), Vector2(6*s, 5*s)])
	var arrow_shape = arrow_left if point_left else arrow_right
	
	var arrow_color = ThemeManager.arrow_color if ThemeManager else Color(0.9, 0.9, 0.9, 0.8)
	var backbone_color = ThemeManager.backbone_color if ThemeManager else Color(0.6, 0.6, 0.6, 0.9)
	var nick_color = ThemeManager.nick_color if ThemeManager else Color(1.0, 0.3, 0.3, 0.9)
	var width = ThemeManager.backbone_width if ThemeManager else 4.0

	# ==========================================
	# BOTTOM STRAND: TROMBONE LOOP LOGIC
	# ==========================================
	if point_left: 
		_draw_lagging_strand_loop(bases, y_offset, arrow_shape, arrow_color, backbone_color, nick_color, width)
		return

	# ==========================================
	# TOP STRAND: EXISTING STRAIGHT LINE LOGIC
	# ==========================================
	for i in range(bases.size() - 1):
		var b1 = bases[i]
		var b2 = bases[i+1]
		
		var p1 = Vector2(b1.position.x, b1.position.y + y_offset)
		var p2 = Vector2(b2.position.x, b2.position.y + y_offset)
		
		var angle = (p2 - p1).angle()
		var mid_point = (p1 + p2) / 2.0
		
		if b1.position.distance_to(b2.position) < 50.0:
			draw_line(p1, p2, backbone_color, width, true)
			
			var arrow_points = PackedVector2Array()
			for p in arrow_shape:
				arrow_points.append(mid_point + p.rotated(angle))
			draw_colored_polygon(arrow_points, arrow_color)
			
		else:
			var nick_length = 10.0
			var is_sealed = sealed_gap_indices.has(i)
			
			if is_sealed:
				draw_line(p1, p2, backbone_color, width, true)
				var arrow_points = PackedVector2Array()
				for p in arrow_shape:
					arrow_points.append(mid_point + p.rotated(angle))
				draw_colored_polygon(arrow_points, arrow_color)
			else:
				draw_line(mid_point - Vector2(nick_length, 0), mid_point + Vector2(nick_length, 0), nick_color, width * 0.75, true)

func _draw_lagging_strand_loop(bases: Array[NitrogenBase], y_offset: float, arrow_shape, arrow_color, backbone_color, nick_color, width):
	# FIX: Sort by template partner's original X position for stability
	bases.sort_custom(func(a, b): return a.partner_base.original_pos.x < b.partner_base.original_pos.x)

	var active_start_index = 0
	for i in range(bases.size() - 1):
		var b1 = bases[i]
		var b2 = bases[i+1]
		if b1.position.distance_to(b2.position) >= 50.0 and not sealed_gap_indices.has(i):
			active_start_index = i + 1 

	# Draw Completed Fragments (Straight Lines)
	for i in range(active_start_index - 1):
		var b1 = bases[i]
		var b2 = bases[i+1]
		var p1 = Vector2(b1.position.x, b1.position.y + y_offset)
		var p2 = Vector2(b2.position.x, b2.position.y + y_offset)
		var angle = (p2 - p1).angle()
		var mid_point = (p1 + p2) / 2.0
		
		if b1.position.distance_to(b2.position) < 50.0 or sealed_gap_indices.has(i):
			draw_line(p1, p2, backbone_color, width, true)
			var arrow_points = PackedVector2Array()
			for p in arrow_shape:
				arrow_points.append(mid_point + p.rotated(angle))
			draw_colored_polygon(arrow_points, arrow_color)
		else:
			var nick_length = 10.0
			draw_line(mid_point - Vector2(nick_length, 0), mid_point + Vector2(nick_length, 0), nick_color, width * 0.75, true)

	# Draw the Active Fragment (The Loop)
	# NOTE: active_bases are already correctly positioned by
	# _update_active_fragment_positions(), which derives each base's
	# position from its template partner (which itself rides the real
	# loop curve computed in dna_strand.gd). So we just connect the dots
	# here -- no need to compute a second, independent curve.
	if active_start_index < bases.size():
		var active_bases = bases.slice(active_start_index, bases.size())
		
		if active_bases.size() > 1:
			for i in range(active_bases.size() - 1):
				var b1 = active_bases[i]
				var b2 = active_bases[i+1]
				
				# Offset perpendicular to the segment direction (not a flat
				# y_offset) so the line hugs the curve correctly even while
				# the bases are going around the bend of the loop.
				var partner1 = b1.partner_base
				var partner2 = b2.partner_base
				var p1 = b1.position
				var p2 = b2.position
				if partner1 and partner1.is_on_loop:
					p1 = partner1.position + Vector2.RIGHT.rotated(partner1.loop_normal_angle) * BASE_RADIUS
				if partner2 and partner2.is_on_loop:
					p2 = partner2.position + Vector2.RIGHT.rotated(partner2.loop_normal_angle) * BASE_RADIUS
				
				draw_line(p1, p2, backbone_color, width, true)
				
				var angle = (p2 - p1).angle()
				var mid_point = (p1 + p2) / 2.0
				var arrow_points = PackedVector2Array()
				for p in arrow_shape:
					arrow_points.append(mid_point + p.rotated(angle))
				draw_colored_polygon(arrow_points, arrow_color)

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
			var parent_strand = base.partner_base.get_parent()
			if parent_strand is DnaStrand and not parent_strand.is_top_strand:
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
