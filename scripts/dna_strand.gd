extends Node2D
class_name DnaStrand

@export var is_top_strand: bool = true
@onready var backbone: Line2D = $Backbone

var bases: Array[NitrogenBase] = []
var left_marker: NitrogenBase
var right_marker: NitrogenBase
var current_helicase_x: float = 0.0

const PEEL_WIDTH: float = 60.0
const MAX_SEPARATION: float = 80.0
const BASE_RADIUS: float = 15.0


func _ready():
	if not backbone:
		push_warning("DnaStrand: 'Backbone' Line2D node not found! Check the scene hierarchy.")
	else:
		backbone.visible = true
		backbone.antialiased
		backbone.add_to_group("highlightable")
		backbone.z_index = -1
		backbone.z_as_relative = false
		
		# Apply initial theme values
		if ThemeManager:
			backbone.default_color = ThemeManager.backbone_color
			backbone.width = ThemeManager.backbone_width # <-- NEW
		
	# Listen for theme changes
	if ThemeManager:
		ThemeManager.theme_changed.connect(_on_theme_changed)

func _on_theme_changed():
	if backbone:
		backbone.default_color = ThemeManager.backbone_color
		backbone.width = ThemeManager.backbone_width # <-- NEW
	queue_redraw()

# Draws the 5'->3' directional arrows (< or >)
func _draw():
	if bases.size() < 2:
		return
		
	var arrow_right = PackedVector2Array([Vector2(-6, -5), Vector2(6, 0), Vector2(-6, 5)])
	var arrow_left = PackedVector2Array([Vector2(6, -5), Vector2(-6, 0), Vector2(6, 5)])
	var arrow_shape = arrow_left if is_top_strand else arrow_right
	
	var arrow_color = ThemeManager.arrow_color if ThemeManager else Color(0.9, 0.9, 0.9, 0.8)
	if backbone:
		arrow_color.a *= backbone.modulate.a 
	
	for i in range(bases.size() - 1):
		var b1 = bases[i]
		var b2 = bases[i+1]
		
		# Only draw if bases are close together
		if b1.position.distance_to(b2.position) < 100.0:
			
			# FIX: Calculate the dynamic offset for BOTH b1 and b2 individually!
			var dist1 = current_helicase_x - b1.original_pos.x
			var progress1 = clamp(dist1 / PEEL_WIDTH, 0.0, 1.0)
			var start_offset1 = -BASE_RADIUS if is_top_strand else BASE_RADIUS
			var end_offset1 = BASE_RADIUS if is_top_strand else -BASE_RADIUS
			var offset1 = lerp(start_offset1, end_offset1, progress1)
			
			var dist2 = current_helicase_x - b2.original_pos.x
			var progress2 = clamp(dist2 / PEEL_WIDTH, 0.0, 1.0)
			var start_offset2 = -BASE_RADIUS if is_top_strand else BASE_RADIUS
			var end_offset2 = BASE_RADIUS if is_top_strand else -BASE_RADIUS
			var offset2 = lerp(start_offset2, end_offset2, progress2)
			
			# Apply the specific offsets to each point
			var p1 = Vector2(b1.position.x, b1.position.y + offset1)
			var p2 = Vector2(b2.position.x, b2.position.y + offset2)
			
			# Calculate the angle and midpoint based on the correctly offset points
			var angle = (p2 - p1).angle()
			var mid_point = (p1 + p2) / 2.0
			
			var arrow_points = PackedVector2Array()
			for p in arrow_shape:
				arrow_points.append(mid_point + p.rotated(angle))
				
			draw_colored_polygon(arrow_points, arrow_color)

func build_sequence(sequence: Array, base_scene: PackedScene, spacing: float, start_x: float, start_y: float):
	left_marker = base_scene.instantiate()
	left_marker.base_type = "3'" if is_top_strand else "5'"
	left_marker.state = NitrogenBase.State.TEMPLATE
	left_marker.make_template()
	left_marker.original_pos = Vector2(start_x - spacing, start_y)
	left_marker.position = left_marker.original_pos
	add_child(left_marker)

	for i in range(sequence.size()):
		var base: NitrogenBase = base_scene.instantiate()
		base.base_type = sequence[i]
		base.state = NitrogenBase.State.TEMPLATE
		base.make_template()
		
		var pos = Vector2(start_x + (i * spacing), start_y)
		base.position = pos
		base.original_pos = pos
		
		add_child(base)
		bases.append(base)
		
	right_marker = base_scene.instantiate()
	right_marker.base_type = "5'" if is_top_strand else "3'"
	right_marker.state = NitrogenBase.State.TEMPLATE
	right_marker.make_template()
	right_marker.original_pos = Vector2(start_x + (sequence.size() * spacing), start_y)
	right_marker.position = right_marker.original_pos
	add_child(right_marker)

	_update_backbone()
	

# CALLED EVERY FRAME TO KEEP ARROWS VISIBLE
func _process(delta):
	# FIX: Removed the backbone.points update from here! 
	# It was overwriting the dynamic lerp calculated in update_peel() 
	# with a static offset every single frame.
	
	# We only need to redraw the directional arrows here.
	queue_redraw() 

# CALLED BY HELICASE EVERY FRAME FOR DYNAMIC UNZIPPING ANIMATION
func update_peel(helicase_x: float):
	current_helicase_x = helicase_x
	if not backbone:
		return
		
	var points: PackedVector2Array = []
	
	# Helper function to calculate the new position of unzipped bases
	var apply_position = func(node: NitrogenBase, original_x: float, original_y: float):
		node.is_unzipped = true
		var t = Time.get_ticks_msec() / 1000.0
		var wobble_x = sin(t * node.wobble_speed + node.wobble_phase) * 1.5
		var wobble_y = cos(t * node.wobble_speed * 0.7 + node.wobble_phase) * 1.5
		
		var dist = helicase_x - original_x
		var progress = clamp(dist / PEEL_WIDTH, 0.0, 1.0)
		
		var y_offset = 0.0
		if dist > 0:
			var ease = smoothstep(0.0, 1.0, progress)
			var direction = -1.0 if is_top_strand else 1.0
			y_offset = ease * MAX_SEPARATION * direction
		
		node.position.x = original_x + wobble_x
		node.position.y = original_y + y_offset + wobble_y

	# 1. Update the 5'/3' markers
	if left_marker:
		apply_position.call(left_marker, left_marker.original_pos.x, left_marker.original_pos.y)

	# 2. Update the bases and calculate the backbone curve
	for base in bases:
		apply_position.call(base, base.original_pos.x, base.original_pos.y)
		
		var dist = helicase_x - base.original_pos.x
		var progress = clamp(dist / PEEL_WIDTH, 0.0, 1.0)
		
		# THE -15 TO +15 INTERPOLATION OFFSET
		# Top strand: starts at -15, shifts to +15
		# Bottom strand: starts at +15, shifts to -15
		var start_offset = -BASE_RADIUS if is_top_strand else BASE_RADIUS
		var end_offset = BASE_RADIUS if is_top_strand else -BASE_RADIUS
		var tangential_offset = lerp(start_offset, end_offset, progress)
		
		# Apply the dynamic offset to the base's current position
		var backbone_y = base.position.y + tangential_offset
		points.append(Vector2(base.position.x, backbone_y))
		
	# 3. Update the 5'/3' markers
	if right_marker:
		apply_position.call(right_marker, right_marker.original_pos.x, right_marker.original_pos.y)

	# Apply the new curve to the Line2D
	backbone.points = points
	
	# Redraw the directional arrows
	queue_redraw()

func get_exposed_bases(helicase_x: float) -> Array:
	var exposed: Array[NitrogenBase] = []
	for base in bases:
		if helicase_x - base.original_pos.x > 20.0:
			exposed.append(base)
	return exposed

func _update_backbone():
	if not backbone:
		return
	var points: PackedVector2Array = []
	var tangential_offset = -BASE_RADIUS if is_top_strand else BASE_RADIUS
	
	for base in bases:
		var point_y = base.position.y + tangential_offset
		points.append(Vector2(base.position.x, point_y))
		
	backbone.points = points
	queue_redraw()
